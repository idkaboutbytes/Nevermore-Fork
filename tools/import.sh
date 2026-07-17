#!/usr/bin/env bash
#
# import.sh — copy a Nevermore package out of the torojo dump into the fork's
# lib/, preserving the package's internal folder structure, renaming .lua ->
# .luau, and swapping the old hardcoded loader bootstrap for the fork's one-line
# relative bootstrap. Bare-name `require('Name')` calls are left untouched. The
# correct `../` depth is set afterwards by fix-loader-paths.sh.
#
# Resolution is package-oriented: a name resolves to its package FOLDER (e.g.
# `SecretService` -> services/secretservice) and the WHOLE subtree is copied with
# its nesting intact (folder-modules `init.lua`, `Cmdr/Commands/…`, `.meta.json`).
# That fixes both (a) folder-module packages with no `<Name>.lua`, and (b)
# submodules being flattened into the top level.
#
# By default it recurses: after importing a package it scans for bare-name
# `require("Dep")` loader requires and imports each missing Dep's package too,
# until the whole transitive tree is present.
#
# Usage:
#   tools/import.sh <Name> [--dest lib/<subdir>] [--file-only] [--force] [--no-deps]
#
#   <Name>        package/module name, e.g. Rx, Maid, SecretService, Signal
#   --dest DIR    destination folder for the ROOT package (default: lib/<package-folder>)
#   --file-only   copy just <Name>.luau (single module), not the whole package subtree
#   --no-deps     import only <Name>; do not follow its require() dependencies
#   --force       overwrite existing destination files
#
# Env overrides:
#   NEVERMORE_SRC   default /home/admin/Desktop/torojo/src/ReplicatedStorage/Services/Nevermore
#   SIGNAL_SRC      default .../Packages/Signal.lua
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$ROOT_DIR/lib"

NEVERMORE_SRC="${NEVERMORE_SRC:-/home/admin/Desktop/torojo/src/ReplicatedStorage/Services/Nevermore}"
SIGNAL_SRC="${SIGNAL_SRC:-/home/admin/Desktop/torojo/src/ReplicatedStorage/Packages/Signal.lua}"

NAME=""
DEST=""
FILE_ONLY=0
FORCE=0
WITH_DEPS=1

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dest) DEST="$2"; shift 2 ;;
	--file-only) FILE_ONLY=1; shift ;;
	--no-deps) WITH_DEPS=0; shift ;;
	--force) FORCE=1; shift ;;
	-*) echo "unknown option: $1" >&2; exit 2 ;;
	*)
		if [[ -n "$NAME" ]]; then echo "unexpected extra argument: $1" >&2; exit 2; fi
		NAME="$1"; shift ;;
	esac
done

if [[ -z "$NAME" ]]; then
	echo "usage: $(basename "$0") <Name> [--dest lib/<subdir>] [--file-only] [--force] [--no-deps]" >&2
	exit 2
fi

# --- helpers -------------------------------------------------------------------

# module_exists <Name> -> prints the path of an existing lib/**/<Name>.luau (if any)
module_exists() {
	find "$LIB_DIR" -type f -iname "$1.luau" -print -quit 2>/dev/null
}

# required_names_in_tree -> unique bare-name require("X") deps across lib/
required_names_in_tree() {
	find "$LIB_DIR" -name '*.luau' -print0 \
		| xargs -0 perl -ne 'while (/require\(\s*["\x27]([A-Za-z_][A-Za-z0-9_]*)["\x27]\s*\)/g) { print "$1\n" }' 2>/dev/null \
		| sort -u
}

# swap the torojo bootstrap for the fork's relative bootstrap (depth fixed later).
# returns 0 if a bootstrap was found and swapped, 1 otherwise.
swap_bootstrap() {
	local f="$1"
	if ! grep -Eq 'local[[:space:]]+require[[:space:]]*=[[:space:]]*require\(.*[Ll]oader.*\)\.load\(\)' "$f"; then
		return 1
	fi
	perl -0777 -i -pe \
		's{local\s+require\s*=\s*require\([^\n]*?[Ll]oader[^\n]*?\)\.load\(\)}{const require = require("../Loader").load()}g' "$f"
	if [[ "$(grep -c 'ReplicatedStorage' "$f")" -eq 1 ]]; then
		perl -0777 -i -pe \
			's{^[ \t]*local[ \t]+ReplicatedStorage[ \t]*=[ \t]*game:GetService\((["\x27])ReplicatedStorage\1\)[ \t]*\r?\n}{}m' "$f"
	fi
	return 0
}

# package_root_of <abs path under NEVERMORE_SRC> -> echoes NEVERMORE_SRC/<category>/<pkg>
package_root_of() {
	local rel="${1#"$NEVERMORE_SRC"/}"
	[[ "$rel" == "$1" ]] && return 1
	local cat="${rel%%/*}" rest="${rel#*/}" pkg
	pkg="${rest%%/*}"
	[[ -n "$pkg" && -d "$NEVERMORE_SRC/$cat/$pkg" ]] || return 1
	echo "$NEVERMORE_SRC/$cat/$pkg"
}

# resolve_source <Name> <file_only 0|1>
#   sets SRC_MODE ("folder"|"files"), SRC_ROOT (folder mode), SRC_FILES (files mode),
#   and DEFAULT_DEST. returns 1 = not found, 2 = ambiguous.
SRC_FILES=()
SRC_ROOT=""
SRC_MODE=""
DEFAULT_DEST=""
resolve_source() {
	local name="$1" file_only="$2"
	SRC_FILES=(); SRC_ROOT=""; SRC_MODE=""; DEFAULT_DEST=""

	if [[ "${name,,}" == "signal" && -f "$SIGNAL_SRC" ]]; then
		SRC_FILES=("$SIGNAL_SRC"); SRC_MODE="files"; DEFAULT_DEST="lib/signal"
		return 0
	fi

	[[ -d "$NEVERMORE_SRC" ]] || { echo "error: Nevermore source not found at $NEVERMORE_SRC" >&2; return 1; }

	# 1. A package folder at category level: NEVERMORE_SRC/<category>/<name> (case-insensitive).
	local pkg_dir=""
	pkg_dir="$(find "$NEVERMORE_SRC" -mindepth 2 -maxdepth 2 -type d -iname "$name" | sort | head -1)"

	# 2. Else find <name>.lua and resolve to its package root.
	if [[ -z "$pkg_dir" ]]; then
		local matches=()
		mapfile -t matches < <(find "$NEVERMORE_SRC" -type f -iname "${name}.lua" ! -iname "*.spec.lua" | sort)
		[[ ${#matches[@]} -eq 0 ]] && return 1

		if [[ "$file_only" -eq 1 ]]; then
			[[ ${#matches[@]} -gt 1 ]] && return 2
			SRC_FILES=("${matches[0]}"); SRC_MODE="files"
			DEFAULT_DEST="lib/$(basename "$(dirname "${matches[0]}")")"
			return 0
		fi

		local root0="" r m
		for m in "${matches[@]}"; do
			r="$(package_root_of "$m")" || r="$(dirname "$m")"
			if [[ -z "$root0" ]]; then root0="$r"; elif [[ "$r" != "$root0" ]]; then return 2; fi
		done
		pkg_dir="$root0"
	fi

	if [[ "$file_only" -eq 1 ]]; then
		local one=""
		one="$(find "$pkg_dir" -type f -iname "${name}.lua" ! -iname "*.spec.lua" | sort | head -1)"
		[[ -z "$one" ]] && return 1
		SRC_FILES=("$one"); SRC_MODE="files"; DEFAULT_DEST="lib/$(basename "$pkg_dir")"
		return 0
	fi

	SRC_ROOT="$pkg_dir"; SRC_MODE="folder"; DEFAULT_DEST="lib/$(basename "$pkg_dir")"
	return 0
}

# --- copy one file (rename .lua->.luau handled by caller); swap bootstrap -------

IMPORTED_COUNT=0
declare -A UNRESOLVED=()

import_file() {
	local src="$1" dest_file="$2"
	local disp="${dest_file#"$ROOT_DIR"/}"
	if [[ -e "$dest_file" && "$FORCE" -ne 1 ]]; then
		echo "skip (exists): $disp"
		return 0
	fi
	mkdir -p "$(dirname "$dest_file")"
	cp "$src" "$dest_file"
	local note=""
	if [[ "$dest_file" == *.luau ]] && swap_bootstrap "$dest_file"; then
		note="  [bootstrap swapped]"
	fi
	echo "imported: $disp$note"
	IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
}

# do_import <Name> <dest_override|""> <file_only 0|1>
do_import() {
	local name="$1" dest_override="$2" file_only="$3"
	local rc; resolve_source "$name" "$file_only"; rc=$?
	if [[ $rc -ne 0 ]]; then
		if [[ $rc -eq 2 ]]; then UNRESOLVED["$name"]="ambiguous (matches in multiple packages)"; else UNRESOLVED["$name"]="not found in the dump"; fi
		return 1
	fi

	local dest_rel="${dest_override:-$DEFAULT_DEST}"
	local dest_dir="$ROOT_DIR/$dest_rel"

	if [[ "$SRC_MODE" == "folder" ]]; then
		# Whole package subtree, structure preserved: .lua -> .luau, keep .meta.json,
		# skip *.spec.lua.
		local f rel dest_file
		while IFS= read -r -d '' f; do
			rel="${f#"$SRC_ROOT"/}"
			case "$f" in
			*.lua) dest_file="$dest_dir/${rel%.lua}.luau" ;;
			*) dest_file="$dest_dir/$rel" ;;
			esac
			import_file "$f" "$dest_file"
		done < <(find "$SRC_ROOT" -type f \( -name '*.lua' -o -name '*.meta.json' \) ! -iname '*.spec.lua' -print0 | sort -z)
	else
		local src base dest_file
		for src in "${SRC_FILES[@]}"; do
			base="$(basename "$src")"
			dest_file="$dest_dir/${base%.lua}.luau"
			import_file "$src" "$dest_file"
		done
	fi
	return 0
}

# --- import the root -----------------------------------------------------------

do_import "$NAME" "$DEST" "$FILE_ONLY" || {
	echo "error: could not import root package '$NAME': ${UNRESOLVED[$NAME]:-unresolved}" >&2
	exit 1
}

# --- recurse over dependencies (fixpoint) --------------------------------------

if [[ "$WITH_DEPS" -eq 1 ]]; then
	echo "--- resolving dependencies ---"
	changed=1
	while [[ "$changed" -eq 1 ]]; do
		changed=0
		while IFS= read -r dep; do
			[[ -z "$dep" ]] && continue
			[[ "$dep" == "Loader" ]] && continue
			[[ -n "${UNRESOLVED[$dep]:-}" ]] && continue
			[[ -n "$(module_exists "$dep")" ]] && continue
			if do_import "$dep" "" 0; then changed=1; fi
		done < <(required_names_in_tree)
	done

	if [[ ${#UNRESOLVED[@]} -gt 0 ]]; then
		echo "--- unresolved requires (left as bare-name; resolve manually) ---"
		for k in "${!UNRESOLVED[@]}"; do
			printf '  %-28s %s\n' "$k" "${UNRESOLVED[$k]}"
		done
	fi
fi

if [[ "$IMPORTED_COUNT" -gt 0 ]]; then
	echo "TODO: style pass on imported files (Moonwave/strict/dot-self) — see CLAUDE.md"
else
	echo "nothing imported (everything already present)."
fi

# --- fix loader require depths across the tree ---------------------------------

LOADER_FIXER=""
for candidate in "$SCRIPT_DIR/relative_loader.sh" "$SCRIPT_DIR/fix-loader-paths.sh"; do
	if [[ -x "$candidate" ]]; then
		LOADER_FIXER="$candidate"
		break
	fi
done

if [[ -n "$LOADER_FIXER" ]]; then
	echo "--- fixing loader require depths ---"
	"$LOADER_FIXER"
else
	echo "note: loader path fixer (tools/relative_loader.sh) not found — run it to set '../' depth." >&2
fi
