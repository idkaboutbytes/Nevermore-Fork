#!/usr/bin/env bash
#
# relative_loader.sh — normalise every module's Loader require to the correct
# relative depth, so packages and submodules at any nesting resolve `Loader`.
#
# The loader bootstrap is a relative require-by-string:
#
#     const require = require("../Loader").load()
#
# The number of `../` depends on how deep the file sits under lib/. Rojo turns a
# folder containing `init.luau` into a single ModuleScript whose siblings become
# its children, so an `init.luau` needs ONE FEWER `../` than a regular file in
# the same folder (only the file *being* an init.luau matters — an ancestor
# module-folder does not change the count).
#
# Usage:
#   tools/relative_loader.sh [--check]
#     (no args)  rewrite every file's Loader require prefix in place
#     --check    report files whose prefix is wrong; exit 1 if any (for CI)
#
set -euo pipefail

# Resolve the fork root (parent of this tools/ dir) and its lib/.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$ROOT_DIR/lib"

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
	CHECK_ONLY=1
elif [[ -n "${1:-}" ]]; then
	echo "usage: $(basename "$0") [--check]" >&2
	exit 2
fi

if [[ ! -d "$LIB_DIR" ]]; then
	echo "error: lib/ not found at $LIB_DIR" >&2
	exit 2
fi

# Matches a loader require with a mandatory relative prefix (./ or one-or-more
# ../), e.g. require("../Loader") or require('./Loader'). A bare require("Loader")
# (a loader-closure bare-name require) has no prefix and is deliberately NOT
# matched, so it is left alone.
HAS_BOOTSTRAP_RE='require\((["'\''])(\./|(\.\./)+)Loader\1\)'

# compute_prefix <file-relative-to-lib>  ->  echoes "./" or "../" * n
compute_prefix() {
	local rel="$1"
	local dir base segments dots
	dir="$(dirname "$rel")"
	base="$(basename "$rel")"

	if [[ "$dir" == "." ]]; then
		segments=0
	else
		segments="$(awk -F/ '{print NF}' <<<"$dir")"
	fi

	if [[ "$base" == "init.luau" ]]; then
		dots=$((segments - 1))
	else
		dots=$segments
	fi

	if ((dots <= 0)); then
		printf './'
	else
		local i
		for ((i = 0; i < dots; i++)); do printf '../'; done
	fi
}

changed=0
wrong=0
scanned=0

while IFS= read -r -d '' file; do
	rel="${file#"$LIB_DIR"/}"

	# Skip the loader itself — it never requires itself.
	[[ "$rel" == "Loader.luau" ]] && continue

	# Skip files that don't use the loader bootstrap at all.
	grep -Eq "$HAS_BOOTSTRAP_RE" "$file" || continue

	scanned=$((scanned + 1))
	want="$(compute_prefix "$rel")"

	# Current prefix as written (first match), for reporting / no-op detection.
	current="$(grep -Eo "$HAS_BOOTSTRAP_RE" "$file" | head -1 | sed -E 's/.*require\((["'\''])(.*)Loader\1\).*/\2/')"

	if [[ "$current" == "$want" ]]; then
		continue
	fi

	if ((CHECK_ONLY)); then
		printf 'wrong: %-48s has "%sLoader" wants "%sLoader"\n' "$rel" "$current" "$want"
		wrong=$((wrong + 1))
		continue
	fi

	# Rewrite the prefix in place, preserving the original quote style.
	WANT="$want" perl -0777 -i -pe '
		my $w = $ENV{WANT};
		s{require\((["\x27])(?:\./|(?:\.\./)+)Loader\1\)}{require("${w}Loader")}g;
	' "$file"

	printf 'fixed: %-48s -> require("%sLoader")\n' "$rel" "$want"
	changed=$((changed + 1))
done < <(find "$LIB_DIR" -name '*.luau' -print0 | sort -z)

if ((CHECK_ONLY)); then
	if ((wrong > 0)); then
		echo "$wrong file(s) have an incorrect Loader require prefix (of $scanned with a bootstrap)." >&2
		exit 1
	fi
	echo "OK: all $scanned bootstrap file(s) have the correct Loader require prefix."
else
	echo "Done: fixed $changed file(s) of $scanned with a bootstrap."
fi
