# CLAUDE.md — Nevermore Fork

**WHAT**: A cleaner, optimized re-implementation of Nevermore Engine packages, authored in the house
style (`const`, `@checked`, `--!strict`, Moonwave, dot-with-typed-self).
**WHERE FROM**: packages are ported out of the torojo Nevermore dump at
`/home/admin/Desktop/torojo/src/ReplicatedStorage/Services/Nevermore/` (Signal comes from
`.../Packages/Signal.lua`).

## Layout

```
lib/
  Loader.luau            # the name-based dependency resolver (fork root)
  <package>/<Module>.luau  # one folder per package, e.g. maid/Maid.luau, rx/Rx.luau
tools/
  import.sh              # copy a package from the dump + swap its bootstrap
  fix-loader-paths.sh    # normalise every Loader require to the right depth
```

## The loader (how modules import each other)

Two require kinds:

1. **Acquire the loader** with a one-line relative require-by-string, then call `load()`:
   ```luau
   const require = require("../Loader").load()
   ```
   `Loader.luau` sits at the fork root (`lib/`). The number of `../` depends on nesting — **do not
   hand-count it**; run `tools/fix-loader-paths.sh` and it sets the correct depth.
   - `../` climbs one folder; `./` is the current folder.
   - **`init.luau` collapses its folder** (Rojo makes the folder a single ModuleScript whose siblings
     become children), so an `init.luau` needs **one fewer `../`** than a regular file in the same folder
     (`lib/rx/init.luau` → `./Loader`; `lib/rx/Rx.luau` → `../Loader`). Only the file *being* an init
     matters — an ancestor module-folder does not change the count.

2. **Import sibling packages by bare name** through the loader closure — location-independent:
   ```luau
   const Maid = require("Maid")
   const Signal = require("Signal")
   ```
   `require("Name")` searches the fork root recursively for a ModuleScript named `Name`. Keep these
   exactly as-is when porting.

> luau-lsp note: stock luau-lsp resolves `require("../Loader")` but **not** the bare-name
> `require("Maid")` form — the Quenty luau-lsp fork (loader string-requires + `const`) is a separate
> workstream that adds types/autocomplete for those. Lint/format work without it.

## Conventions

> **Deferred for now**: `const` and `@checked` are optional and currently **skipped** during porting —
> keep files faithful with plain `local` and no `@checked`. The rules below describe the eventual target
> style; apply the rest (strict, Moonwave, banners, dot-self, naming) but leave const/@checked for later.


- **`--!strict`** on every module (the sole exception is `Loader.luau`, which is `--!nonstrict` — dynamic
  instance search).
- **`const`** for all module-level bindings — requires, constants, and module-level helper functions
  (`const function foo()`). `local` only inside function bodies.
- **Moonwave header**: `--[=[ @class Name ]=]` for classes, `--[=[ @util NameUtil ]=]` for utils, with
  docstrings on every public method.
- **Section banners** (only as needed): `--> Packages` (third-party) / `--> Dependencies` (other fork
  modules) / `--> Types` / `--> Constants`.
- **Methods use dot notation with an explicit typed self**, never colons:
  `function SomeClass.SomeMethod(self: ClassType)`.
- **Classes**: `SomeClass.ClassName = "SomeClass"`, `SomeClass.__index = SomeClass`,
  `export type ClassType = typeof(setmetatable({} :: { ... }, SomeClass))`. `.new()` is the top method,
  `.Destroy` the bottom; every class owns a `_maid` and `.Destroy` does `self._maid:DoCleaning()` then
  `table.clear(self)` + `setmetatable(self, nil)`.
- **Naming**: class public methods `PascalCase`; util/private methods `camelCase`; all private members
  `_camelCase`, placed below public members and undocumented. Promise-returning methods suffixed `Async`.
- **`@checked`** attribute on public typed functions (valid Roblox Luau; accepted by stylua/selene).
- **Quotes**: double (StyLua `ForceDouble`). Requires are auto-sorted (`sort_requires`).

## Porting workflow

1. **Import**: `tools/import.sh <Name> [--dest lib/<subdir>] [--file-only] [--force]`
   - Copies the package's `.lua` files → `lib/<folder>/<Name>.luau`, swaps the old
     `require(ReplicatedStorage.Services.Nevermore.loader).load()` bootstrap for
     `const require = require("../Loader").load()`, keeps bare-name requires, then runs the depth fixer.
   - `--file-only` grabs a single module (e.g. pull `MaidTaskUtils` into `--dest lib/maid`).
   - `Signal` is special-cased to the external lemonsignal source.
2. **Style pass** (manual, per file — this is the actual rewrite):
   - Header → `--!strict` + Moonwave `@class`/`@util`.
   - `--> Packages` / `--> Dependencies` / `--> Types` banners.
   - `local` → `const` at module scope (incl. `const function` helpers). **Keep `require("Name")` calls.**
   - Colon methods → dot-with-explicit-typed-self; add/verify `export type ClassType`.
   - Apply the naming matrix; move privates below publics; add `@checked` to public typed functions.
3. **Fix depths**: `tools/fix-loader-paths.sh` (or `--check` in CI) — idempotent.

## Lint / format

Tools come from rokit (`rokit.toml`: rojo, selene, StyLua, luau-lsp). From the fork root:

```bash
stylua lib/                    # format
stylua --check lib/            # verify formatting
selene lib/                    # lint
tools/fix-loader-paths.sh --check   # verify loader require depths
```

## Rx port order (bottom-up)

Signal → leaves (Symbol, Throttle, cancellableDelay, MaidTaskUtils, DuckTypeUtils, Maid, Promise) →
Observable, Subscription → Rx (faithful port; keep `--!nocheck`/lighter typing at first).
