# Design Spec: Shimless FFI and Akku Installation (release 2.0)

- **Status:** Proposed
- **Date:** 2026-08-21
- **Scope:** post-1.0; ships as release **2.0**
- **Related:** [Stage 6 design](2026-08-18-stage-6-packaging-design.md) · ADR-0001 (amended
  again here) · ADR-0002 · ADR-0003 · ADR-0004 · ADR-0007 · ADR-0014 (this is its named
  successor) · ADR-0015, ADR-0016, ADR-0017 (new, this stage)

## 1. Scope

Delete the C shim. Bind `libcmark-gfm` directly from Scheme, and resolve it at runtime
from a candidate list rather than from paths a build step recorded. The result installs
through Akku with **no compiler, no CMake, no pkg-config, and no `-dev` package**.

This is ADR-0014's successor, which it described as "configuration read at runtime rather
than generated into the source tree."

**Exit criterion:** on a machine with only `apt install cmark-gfm` (or
`brew install cmark-gfm`) and Chez, an `akku install chez-cmark-gfm` yields a working
`(cmark gfm)` with nothing set in the environment.

### 1.1 In scope

- Removing `src/cmark-gfm-shim.{c,h}` and every build path that produced it.
- A new pure `(cmark gfm private discovery)` library: version parsing, platform-specific
  library naming, and candidate selection.
- Runtime resolution of the two cmark shared objects, with a `CHEZ_CMARK_GFM_LIBS`
  override.
- Renaming `&cmark-shim-unavailable` to `&cmark-library-unavailable`, and reshaping
  `&cmark-version-incompatible`.
- Deleting `fallback/`, `make check-config`, and the generated `config.sls`.
- Documentation: revised install contract, and a note directing RHEL/Fedora and Alpine
  users to a source build (§8.2).
- `Akku.manifest` gains `homepage` and a real `depends` set; **no `scripts` clause**.
- Version 2.0.0, a CHANGELOG entry, three ADRs, and a `v2.0.0` tag.

### 1.2 Out of scope, explicitly

- Publishing to the Akku archive. That is a submission process, not a code change, and it
  should follow a release that has proven itself.
- Windows (ADR-0004). Nothing here precludes it, and removing the C build removes the
  largest obstacle, but it is not attempted.
- Any change to parsing, rendering, the AST, the SXML mapping, options, or limits. **The
  public API changes only where the shim's disappearance forces it** (§5).
- Vendoring or building `cmark-gfm` at install time (rejected; see §11.3).
- A `docs/` tree. README additions stay terse.

### 1.3 The install contract for 2.0

| | 1.0 | 2.0 |
|---|---|---|
| Linux | clone, submodule init, CMake build (~2 min), `cmake` + `build-essential` + `pkg-config` | `apt install cmark-gfm` |
| macOS | clone + `make build`, Xcode CLT | `brew install cmark-gfm` |
| Library path | `CHEZSCHEMELIBDIRS=src:fallback` | `CHEZSCHEMELIBDIRS=src` |
| Akku | not supported | supported |
| RHEL / Alpine | works (vendored build) | **source build required** (§11.1) |

## 2. Why the shim goes

`src/cmark-gfm-shim.c` is 71 lines doing five jobs. Scheme already binds ~30 cmark entry
points directly (`native.sls`); these five are the remainder.

### 2.1 The five jobs

| Shim job | Replacement | Evidence |
|---|---|---|
| `chez_cmark_shim_compiled_version` | **deleted** — no compile step, so no header/runtime skew can exist | §4 |
| `chez_cmark_runtime_version` | `(foreign-procedure "cmark_version" () int)` | probed: returns `#x1D000D` |
| `chez_cmark_option_bits` | six constants defined in Scheme | §2.3 |
| `chez_cmark_free_buffer` | third `void*` of `cmark_get_default_mem_allocator()`, called via address | probed: render→free round-trip clean |
| `chez_cmark_tasklist_checked` | `unsigned-8` result type | probed: `[x]`→1, `[ ]`→0 |
| debug counters | a Scheme box in `scope.sls` | they already only count Scheme-side calls |

### 2.2 The allocator and the `_Bool` return, precisely

`cmark_get_default_mem_allocator()` returns a pointer to `struct cmark_mem`, whose three
members are `calloc`, `realloc`, `free` in that order. Read the third:

```scheme
(define mem ((foreign-procedure "cmark_get_default_mem_allocator" () uptr)))
(define free-addr (foreign-ref 'uptr mem (* 2 (foreign-sizeof 'void*))))
(define cmark-free (foreign-procedure free-addr (uptr) void))
```

Chez accepts an integer address where a name string normally goes; this was verified
against the installed 0.29.0.gfm.13. The offset is an ABI assumption on a struct layout
and is recorded as a risk in §11.2, with a test in §7.4.

For `cmark_gfm_extensions_get_tasklist_item_checked`, declare the result as `unsigned-8`.
`_Bool` occupies only the low byte of the return register with the upper bits
unspecified, so an `int` result would read whatever happens to be there. `unsigned-8`
reads exactly the defined byte. This is the same reasoning the shim header records; it
simply moves into the binding.

### 2.3 The option constants, and what still guards them

The six `CMARK_OPT_*` values move into Scheme. ADR-0002's "read from the real headers and
cannot drift" weakens to "drift fails a test." Two tests carry it:

- `tests/test-differential.sps:120-143` already covers **five of six** with paired
  assertions — first that the CLI's own output moves when the flag is passed, then that
  ours matches it byte-for-byte. A wrong constant fails the second half.
- `validate-utf8?` is unreachable through the public API (`test-differential.sps:102`),
  so no fixture can discriminate it, and the structural assertions in
  `test-native.sps:134` become self-referential against a Scheme-defined table. **A new
  test parses `vendor/cmark-gfm/src/cmark-gfm.h` and asserts all six constants** (§7.3).

## 3. Discovery

### 3.1 The hard invariant

> **Core and extensions must be the same version, found in the same directory, selected
> by numeric comparison, and matched by versioned filename only.**

Every clause closes a specific failure:

1. **Versioned filename only.** Debian's runtime package ships *only*
   `libcmark-gfm.so.0.29.0.gfm.13`; the unversioned `libcmark-gfm.so` symlink lives in
   `libcmark-gfm-dev`. Matching the unversioned name would force a `-dev` dependency on
   a pure-runtime Scheme library.
2. **Numeric comparison.** String sorting is wrong: `"...gfm.9" > "...gfm.13"` lexically.
   Verified in Chez — a naive "greatest string" pick selects `gfm.9` over `gfm.13`.
3. **Same version.** `vendor/cmark-gfm/src/CMakeLists.txt:106` sets `SOVERSION` to the
   *full* version including the gfm patch, so every upstream release changes the SONAME
   and Debian gives each its own co-installable package. Multiple versions in one
   directory is the normal case, not a broken machine.
4. **Same directory, matched pair.** `otool -L` shows the extensions library references
   `@rpath/libcmark-gfm.0.29.0.gfm.13.dylib` — the full versioned name, a DT_NEEDED
   SONAME on Linux. Pairing core gfm.13 with extensions gfm.6 would load the chosen core
   *and then* let the loader satisfy the extensions library's own dependency by pulling
   in a **second** core. Two cmark cores in one process, with `cmark_version()` reporting
   whichever one Scheme's bindings resolved against. This clause is a correctness
   requirement, not tidiness.

### 3.2 Name shapes

| Platform | Core | Extensions |
|---|---|---|
| Linux | `libcmark-gfm.so.<ver>` | `libcmark-gfm-extensions.so.<ver>` |
| macOS | `libcmark-gfm.<ver>.dylib` | `libcmark-gfm-extensions.<ver>.dylib` |

`<ver>` is `MAJOR.MINOR.PATCH.gfm.GFMPATCH`, all four numeric. Encode as cmark does:
`(M<<24) | (m<<16) | (p<<8) | g`. Check: `0.29.0.gfm.13` → `#x001D000D`, which is what
`cmark_version()` returned under probe.

Anything that does not parse as four numeric components is not a candidate. This is what
makes `libcmark-gfm.so` and `libcmark-gfm.dylib` invisible to the search — deliberately.

### 3.3 The algorithm

`select-cmark-libraries` lives in the new pure `(cmark gfm private discovery)` and takes
its filesystem access as arguments, so it is unit-testable against synthetic listings
with no real files. This mirrors why `resolve-shim-path` was made an exported procedure
rather than a bare expression.

It returns **two values** — a status symbol and a payload — rather than overloading one
return shape. A success pair `(core . ext)` and a failure pair `(out-of-range . version)`
would otherwise be distinguishable only by inspecting the car's type, which is exactly the
kind of "`#f` is dangerous as an expected value" trap ADR-0014 §2.2 warns about.

```
select-cmark-libraries(list-dir, dir?, candidates, range)
  -> (values 'found        (core-path . extensions-path))
   | (values 'not-found    #f)
   | (values 'out-of-range encoded-version)

for each directory D in candidates, in order:
    if not (dir? D): skip
    names := list-dir(D)
    cores := { v | name in names matches CORE shape with version v }
    exts  := { v | name in names matches EXT  shape with version v }
    both  := cores ∩ exts                        ; set intersection on encoded version
    ok    := { v in both | range-lo <= v <= range-hi }
    if ok is non-empty:
        v := numeric maximum of ok
        return (values 'found (D/core-name(v) . D/ext-name(v)))
    else if both is non-empty:
        remember max(both) as an out-of-range sighting; continue

after all directories:
    if any out-of-range sighting: return (values 'out-of-range greatest-sighting)
    else: return (values 'not-found #f)
```

**First directory that yields a pair wins**, matching conventional loader precedence.
Within a directory, the numerically greatest in-range version wins.

The `out-of-range` result exists so that a machine with only cmark-gfm 0.30 reports
`&cmark-version-incompatible` naming what it found, rather than the misleading
"no library found."

### 3.4 Candidate directories

**macOS**, in order: `/opt/homebrew/lib`, `/usr/local/lib`, `/opt/local/lib`.

**Linux**, in order: `/usr/local/lib`, `/usr/lib/<triple>`, `/usr/lib`, `/usr/lib64`.

`<triple>` is derived from `(machine-type)` through a small table:

| machine-type stem | triple |
|---|---|
| `a6` | `x86_64-linux-gnu` |
| `arm64` | `aarch64-linux-gnu` |
| `i3` | `i386-linux-gnu` |
| `ppc64le` | `powerpc64le-linux-gnu` |
| `rv64` | `riscv64-linux-gnu` |

If the stem is not in the table, enumerate every `/usr/lib/*-linux-gnu*` subdirectory in
sorted order instead. Deriving one triple rather than scanning all of them keeps a
multiarch box from ever attempting a wrong-architecture load — there is no fall-through
on load failure (§3.6), so a wrong-arch attempt would be a hard error rather than a retry.

Alpine and other musl systems place libraries directly in `/usr/lib`, which the list
already covers.

### 3.5 The environment override

`CHEZ_CMARK_GFM_LIBS` — colon-separated, **exactly two** absolute paths to existing
regular files.

- **Order does not matter.** Each basename is classified: one containing
  `cmark-gfm-extensions` is the extensions library, the other is the core. A swapped
  variable is not a footgun.
- **No version parsing.** An explicit override may name unversioned files such as
  `/usr/lib/x86_64-linux-gnu/libcmark-gfm.so`. Selection is the user's; verification is
  still ours (§4).
- **Set means used.** A valid override is used verbatim and the candidate search never
  runs. An invalid one raises `&cmark-library-unavailable` reason `invalid-override` and
  **never falls back to the search** — the same fail-closed posture
  `CHEZ_CMARK_GFM_SHIM` has today.

Anything other than exactly two entries, each absolute and each an existing regular file,
one of each kind, is `invalid-override`.

### 3.6 Loading

Core first, then extensions — preserving the rationale in the comment above `core-loaded`
in `native.sls`: on Linux the symbols of a dlopen'd library's dependencies are not placed
in the global namespace, so extensions must find an already-loaded core. Both are loaded
by absolute path.

**No fall-through.** A path that passed validation but fails to load raises
`load-failed`. Discovery decides; loading reports.

### 3.7 Why Apple's copy is unreachable

macOS 26.5 ships `/usr/lib/libcmark-gfm.dylib` from the dyld shared cache — 217 `cmark_*`
exports including the extension entry points, reporting `0.29.0.gfm.13`, identical to the
pin. A bare-soname load finds it, and every check we have would pass while running a
library that is not the one the differential suite oracles against, whose headers ship
nowhere, and which Apple may change on any OS update.

Three independent properties keep it out, and each is worth preserving deliberately:

1. It has **no filesystem presence** — `file-exists?` and `file-regular?` both return
   `#f`, and `directory-list "/usr/lib"` does not show it.
2. Its name is **unversioned**, so it does not match the shape in §3.2.
3. There is **no** `/usr/lib/libcmark-gfm-extensions.dylib` at all, so the pairing rule
   in §3.1 would reject `/usr/lib` regardless.

`native.sls` must carry a comment saying so, because the natural "simplification" of
falling back to `(load-shared-object "libcmark-gfm.dylib")` silently reintroduces it.

### 3.8 The version floor, and why `index` was redefined

The declared range `(#x001d0000 . #x001dffff)` claims support from `0.29.0.gfm.0`. As
written for 1.0 that was **false**, and 2.0 inherited it: `native.sls` bound
`cmark_node_get_item_index`, which upstream added in commit `f040422` and first tagged in
**0.29.0.gfm.11**. On any older library the import died with
`Exception in foreign-procedure: no entry for "cmark_node_get_item_index"` — a raw Chez
error, not a structured condition. Reproduced in a bare `ubuntu:24.04` container.

1.0 shipped the same defect but rarely hit it, because its documented install was
clone-plus-`make build` against a vendored, pinned `gfm.13`. 2.0 documents
`apt install cmark-gfm`, which walks straight into it: Debian 11 (gfm.0), Ubuntu 22.04 LTS
(gfm.3), Debian 12 and Ubuntu 24.04 LTS (both gfm.6) — the four largest installed bases.

**Decision: drop the binding and compute `index` in Scheme**, so the declared floor becomes
true rather than raising it to gfm.11 and dropping those platforms.

That is a redefinition, not a reimplementation, and the difference is the point:

| | before | after |
|---|---|---|
| `1. 2. 3.` | `(1 2 3)` | `(1 2 3)` |
| `1. 1. 1.` | `(1 1 1)` | `(1 2 3)` |
| `1. 5. 9.` | `(1 5 9)` | `(1 2 3)` |
| bullets, tasks | `(0 0 0)` | `(0 0 0)` |

`cmark_node_get_item_index` returns `node->as.list.start` **for an item**, which the parser
sets to the literal number typed in the source. That value is not derivable from position
and start, so this genuinely discards information. Three things make the trade acceptable:

- **cmark itself does not treat it as durable.** `render.c:188-190` overwrites it with
  `start`, then `previous + 1`, whenever it renders to commonmark, man, or plaintext — so
  `markdown->commonmark` already renumbers `1. 1. 1.` to `1. 2. 3.` today. The ordinal is
  cmark's own rendering semantics, not an invention.
- **`1. 1. 1.` is a common idiom**, and reporting `(1 1 1)` tells a consumer what was typed
  rather than which item it is. The ordinal is the more useful of the two for most callers.
- **Nothing depends on the old meaning.** There are no users of this library.

The cost is stated rather than hidden: `1. 5. 9.` and `1. 2. 3.` are now indistinguishable
in the AST, with no other route to the literal numbers. §8's "what the SXML mapping drops"
table must lose its `item index` → `markdown->ast` row, because index no longer survives —
it is replaced.

No new FFI surface: `convert-children` already threads a 0-based sibling index for
`table_cell` alignment, and the parent node it walks *is* the list, so `node-list-start`
and `node-list-type` supply the rest.

### 3.9 Two behaviour boundaries at gfm.10, and why the range still starts at gfm.0

CI's first real run against Ubuntu 24.04 (cmark-gfm **0.29.0.gfm.6**) found two places
where cmark's *rendering* changes inside the declared range. Both landed in **0.29.0.gfm.10**:

| | gfm.0 – gfm.9 | gfm.10 – gfm.13 |
|---|---|---|
| nested `strong` (`5c75d23`) | emits nested `<strong>` tags | splices the inner one away |
| XML indent (`f7e31f8`) | indents without bound | caps at `MAX_INDENT` = 40 |

The indent one is confined to a test oracle: `markdown->xml` calls cmark and is correct on
every version, so only the suite's own serializer had to learn the boundary.

**The nested-`strong` one is not.** `markdown-ast->sxml` is pure Scheme implementing a
*fixed* mapping written against gfm.13's `html.c`, so it always splices, while
`markdown->html` calls cmark and does not on gfm.0–9. On those libraries **the two public
entry points disagree with each other**, and §8's mapping table cites `html.c:366` as
though the rule were universal.

**Decision: keep the range at gfm.0 and document the divergence** rather than raise the
floor to gfm.10. Raising it would drop Debian 11/12 and Ubuntu 22.04/24.04 LTS — the same
four platforms §3.8 declined to drop — and the alternative of making the adapter
version-aware would destroy its determinism and contradict `make check-purity`, which runs
it with no library loaded at all.

The accepted cost, stated rather than buried: on cmark-gfm older than 0.29.0.gfm.10,
`markdown->sxml` splices a `strong` directly inside a `strong` while that library's own
`markdown->html` does not. Both are self-consistent; they are not consistent with each
other. The affected differential assertions ask the loaded library which behaviour to
expect, and must keep discriminating on both sides of the boundary rather than skipping.

### 3.10 The floor is a symbol, not a version

CI and two independent audits confirmed that `(cmark gfm)` does not work on an *unpatched
upstream* `0.29.0.gfm.0`: `cmark_gfm_extensions_get_tasklist_item_checked` first shipped in
gfm.1 (gfm.0 spells it `char *cmark_gfm_extensions_get_tasklist_state`), so 11 of 20 suites
die with a raw `Exception in foreign-procedure`.

**A version check cannot fix this**, and that is the whole point. Debian 11 ships a
*patched* gfm.0 that backports the rename — its own
`libcmark-gfm-extensions0.symbols` lists the symbol at `@Base 0.29.0.gfm.0` — and it
reports `0.29.0.gfm.0` from `cmark_version()`. So:

- a floor of gfm.0 admits Debian 11 (correct) and upstream gfm.0 (which then crashes);
- a floor of gfm.1 rejects upstream gfm.0 (correct) *and Debian 11* (wrong — it works).

The two are indistinguishable by version because the constraint is not a version. **It is
the presence of one entry point**, and distributions patch entry points independently of
the version they report.

**Decision: probe the symbol.** That one `foreign-procedure` is wrapped in a `guard` — a
failed resolution is catchable, verified — and raises `&cmark-library-unavailable` with
reason `missing-entry-point` naming the extensions library. This is true for both kinds of
gfm.0 and requires no change to the declared range, which stays `(#x001d0000 .
#x001dffff)`.

It also generalises: any future library that satisfies the range but lacks an entry point
this binding needs now fails diagnosably rather than with a raw FFI error. §4's version
gate covers the *range*; this covers the *contents*, which is the half the gate structurally
cannot see.

## 4. Version checking

Two checks, at different times, for different reasons.

1. **At selection**, from the filename, so an out-of-range library is diagnosed by name
   before anything is loaded. Discovery path only — `CHEZ_CMARK_GFM_LIBS` does no version
   parsing whatsoever (§3.5).
2. **After loading**, from `cmark_version()`, because a filename is a claim and distros
   patch. This is the authoritative check, and it runs on **both** paths, override
   included, because it lives in `native.sls`'s library body: `cmark_version` is bound
   alone immediately after the two `load-shared-object` calls (the `cmark-runtime-version`
   definition) and checked there (the `version-checked` definition), ahead of every other
   `foreign-procedure` definition.

That position is load-bearing, not stylistic. Chez resolves a foreign entry point when
the `foreign-procedure` expression is **evaluated**, and a library body evaluates its
definitions in order, so any binding placed above the check would abort the import first
if its symbol were missing. The check is written as a *definition* — an R6RS body admits
no expression among the definitions that follow it — the same idiom the two loads already
use. Written any later, notably in `ensure-native-loaded!`, which runs at first *use*, it
is unreachable for exactly the libraries it exists to reject; that is how it was built
until this was corrected.

**What it covers, exactly.** A library whose `cmark_version()` falls outside
`cmark-supported-version-range` raises `&cmark-version-incompatible` at import, on either
path. Nothing else.

**What it does not cover.** A library *inside* the range that is missing a symbol this
binding declares still dies at import with a raw
`Exception in foreign-procedure: no entry for "…"`, because those declarations are
evaluated after the check; so does a library that does not export `cmark_version` at all,
one definition earlier. §3.8's `cmark_node_get_item_index` defect was precisely that
shape — in range, symbol absent — and no version check of any placement could have
diagnosed it. The remedy for that class is to stop binding the symbol, which is what §3.8
does.

`ensure-native-loaded!` keeps a second copy of the range check. Under the ordering above
it cannot fire — same library, same constant, same answer — so it is redundant
re-verification kept for its price (one foreign call, once per process, behind a mutex
that is taken anyway), not for coverage.

`version-compatible?` loses its `compiled` argument and collapses to `version-supported?`.

`&cmark-version-incompatible` currently carries `(compiled runtime)`, where `compiled`
was the shim's build-time `CMARK_GFM_VERSION`. That value no longer exists. The field
becomes **`supported`**, carrying the `(lo . hi)` range pair:

```scheme
(define-condition-type &cmark-version-incompatible &cmark-error
  make-cmark-version-incompatible cmark-version-incompatible?
  (supported cmark-version-incompatible-supported)   ; was: compiled
  (runtime   cmark-version-incompatible-runtime))
```

This is strictly more informative than what it replaces: the condition now states both
what was expected and what was found.

Call sites to update: `gfm.sls:57` (export), `native.sls` (its raise sites),
`tests/test-conditions.sps:19-31`, and `examples/coverage-exemptions.scm:51` — the last
of which is the export-coverage gate, so missing it fails `make examples` rather than
failing silently.

## 5. Errors

`&cmark-shim-unavailable` → **`&cmark-library-unavailable`**, still deriving from
`&cmark-error`, still carrying `path` and `reason`.

| reason | raised when |
|---|---|
| `not-found` | no candidate directory held a matched pair, and no override was set |
| `invalid-override` | `CHEZ_CMARK_GFM_LIBS` is set but is not two absolute paths to existing regular files, one of each kind |
| `load-failed` | `load-shared-object` raised on a path that passed validation |

`not-built` and `missing` retire with the build step.

`path` is `#f` for `not-found` — there is no single path to report. `not-found` is the one
users will actually hit, so ADR-0014's "name the remedy" principle has to be honoured
somewhere; **as built, that somewhere is `tests/preflight.sps`, not the condition.**

An earlier revision of this section required the condition's *message* to name the
directories that were tried. It does not, and that is the accepted shape rather than an
oversight. `make build` runs the preflight, which catches the condition and prints the
`apt install cmark-gfm` / `brew install cmark-gfm` lines plus the `CHEZ_CMARK_GFM_LIBS`
escape hatch; CI's `no-library` job asserts that exact remedy text is present, so the
interactive path — the one a user hits — is covered end to end and guarded against
rotting.

The accepted cost: a caller who catches `&cmark-library-unavailable` programmatically,
without going through the preflight, learns that resolution failed but not where discovery
looked. Adding the candidate list to the condition would close that, at the price of one
more public-API change in a release already breaking the API; it was weighed and declined.

**Every in-repo reference is ours to update.** There are ~40 across `conditions.sls`,
`native.sls`, `gfm.sls:62`, six test suites, `examples/coverage-exemptions.scm`, and
`README.org`. No alias is kept: `v1.0.0` was tagged 2026-08-21 with no archive presence,
so there is no external caller to protect, and a name that lies about the architecture is
exactly the drift this project's ADRs exist to prevent.

## 6. What gets deleted

| Path | Why |
|---|---|
| `src/cmark-gfm-shim.c`, `src/cmark-gfm-shim.h` | §2 |
| `src/cmark/gfm/private/config.sls` | generated; nothing left to generate |
| `fallback/` (whole tree) | shadowed a generated file that no longer exists |
| `tests/check-config.sps` | compared two config files; there is one, checked in |
| `tests/test-fallback-config.sps` | tested `not-built`, now unreachable |
| `tests/test-shim-loading.sps` | replaced by §7.1–7.2 |
| `tests/shim-load-probe.sps` | subprocess probe; its only callers are the two suites above |
| `tests/check-prod.sps` | discriminated shim flavors; see §6.2 |
| Makefile: `check-config`, `mode-flip-relink`, `prod`, `check-prod`, `FLAVOR`, shim/vendor-link machinery | no C artifact to build, flavor, or relink |

`vendor/` and `make vendor` **stay**. The submodule is still needed for three things:
the `cmark-gfm` CLI (the differential oracle), the header the constant test reads (§7.3),
and the 744-example corpus `tests/test-sxml-differential.sps` reads from the working tree
(`Makefile:291` documents this). It becomes a **development** dependency only — nothing at
runtime touches it.

`CHEZSCHEMELIBDIRS` collapses from `src:fallback` to `src`, and `make dev` / `make test`
lose the `fallback` entry.

### 6.1 What `make build` becomes

`build: $(SHIM) $(CONFIG_SLS)` loses both prerequisites. Rather than delete a canonical
target or leave it empty, **`make build` becomes a preflight**: it runs discovery and
prints the two absolute paths it resolved, or fails with the same diagnostic
`&cmark-library-unavailable` would carry.

That keeps `make build` meaningful — it answers "is this machine set up?" in one command,
which is precisely the question the 2.0 install contract raises — and it gives CI a cheap
assertion that discovery picked the library the job intended.

`make dev`, `make test`, and `make clean` keep their meanings. `make deps` is unchanged.

### 6.2 `make prod` goes, deliberately

`prod`, `check-prod`, and `FLAVOR` exist only to build the shim with and without
`-DCHEZ_CMARK_DEBUG_COUNTERS`. With the counters as a Scheme box there is no artifact to
flavor and nothing to relink, so all three go.

The counters become **always on**. Three fixnum increments per document is not a cost
worth a build mode, and it removes the entire class of bug the `mode-flip-relink` fix
existed for. `tests/test-lifecycle.sps` loses its dev/prod discriminator and simply
asserts the counts move.

This leaves the project without a `make prod`, which the house Makefile convention lists
as "where relevant." It is no longer relevant: there is no compiled artifact and no
build-time configuration. Recorded here so the absence reads as a decision.

### 6.3 `make check-purity` survives, renamed

The purity gate poisons the shim path and asserts the pure suites still pass
(`Makefile:252`). It keeps working unchanged in shape — `CHEZ_CMARK_GFM_LIBS=/nonexistent`
is an `invalid-override`, which fails closed exactly as the poisoned shim path did. Only
the variable name changes. `(cmark gfm sxml)` must remain reachable without touching a
shared object.

`&cmark-version-incompatible`'s ADR-0002 justification for the shim ("constants read from
real headers") is amended by ADR-0015 rather than deleted; ADR-0002's actual decision —
AST traversal in Scheme — is unaffected and still stands.

## 7. Testing

The existing suites are the safety net; most need only the rename. New coverage:

### 7.1 Discovery, against synthetic listings

`select-cmark-libraries` takes `list-dir` and `dir?` as arguments, so a suite can drive
every branch with no filesystem at all. Cases, each asserted:

- Empty directory → `not-found`.
- Core present, extensions absent → that directory is skipped, not paired.
- Extensions present, core absent → likewise.
- **`gfm.6` and `gfm.13` both present and paired → `gfm.13` selected.** This is the
  string-sort footgun; it must fail if comparison is lexical.
- **`gfm.9` and `gfm.13` both present → `gfm.13` selected.** The specific case where
  string sorting picks wrong.
- Core `gfm.13` + extensions `gfm.6` only → **no pair**, directory skipped. The
  double-load hazard of §3.1(4).
- Unversioned `libcmark-gfm.so` + `libcmark-gfm-extensions.so` only → not candidates.
- Only `0.30.0.gfm.0` present and paired → `(out-of-range . #x001E0000)`.
- Two directories, first has a pair → first wins, second never listed.
- Two directories, first has an unpaired core, second has a pair → second wins.

### 7.2 Override validation

Unit tests on the override parser with synthetic paths: not set; one entry; three
entries; a relative path; a directory; a nonexistent file; two cores; two extensions;
swapped order (must succeed). Plus a subprocess test that a valid override wins over a
working candidate directory, and that an invalid one raises rather than falling back.

### 7.3 Option constants against the real header

New suite: parse `#define CMARK_OPT_*` out of `vendor/cmark-gfm/src/cmark-gfm.h` and
assert all six equal the Scheme table. Skips with a clear message if the submodule is not
checked out; **CI must not let it skip** — the vendored job asserts it ran.

This is the only coverage `validate-utf8?` can have (§2.3), and it is the direct
replacement for the guarantee the shim provided.

### 7.4 Allocator round-trip

Two assertions, folded into `test-stress.sps` rather than added as a new suite:

1. **The slot is the right one.** `cmark_get_default_mem_allocator()` returns three
   non-null, mutually distinct function pointers, and the third one accepts a rendered
   buffer without faulting. This catches a reordered or resized `struct cmark_mem` — the
   §11.2 risk — rather than leaving it to chance.
2. **Buffers are actually released.** `live-counts` returns to its pre-loop value after
   the existing accumulation loop. That is a Scheme-side ownership check, not a heap
   measurement; it proves every acquire was paired, which is what the counters are for.

Neither is a leak claim. `make test-memory` under Valgrind on Linux remains the only
evidence that supports one (ADR-0003), unchanged in shape by this work.

### 7.5 Regression baseline

The full suite passes on `main` as of 2026-08-21 — 72/35/10/4/53/5/19/40 across the eight
reported suites, `ALL SUITES PASSED`. Every suite except the deleted three must still pass
with only mechanical changes; any behavioral diff is a bug in this work, not an expected
consequence.

### 7.6 CI

- The macOS job drops the vendored row and gains a **Homebrew-only** row that asserts no
  compiler ran.
- The Linux job becomes `apt install cmark-gfm` plus a **second** job that removes the
  package and asserts `&cmark-library-unavailable` reason `not-found` with a message
  naming the candidate directories.
- An **akku job** runs `akku install` from the manifest and then *calls into*
  `(cmark gfm)` with nothing set in the environment, proving §1's exit criterion. It does
  not need `container:` isolation — §1 requires only cmark-gfm plus Chez and an unset
  environment, not an otherwise-bare machine, and nothing preinstalled on a runner puts a
  conflicting versioned cmark-gfm on the searched paths. A bare *import* would not prove
  it: Chez invokes an imported library's body only when a binding is referenced.
- The support matrix in `README.org` is still asserted against the versions each job ran.
  Its "Memory evidence" column is unchanged, but the acquisition-path framing must be
  replaced: ADR-0001's two paths (pkg-config vs vendored) no longer exist, so the matrix
  should record **how each job obtained cmark-gfm** — Homebrew, apt, or absent — which is
  what the rows now actually differ in.

## 8. Documentation

### 8.1 Install section

Rewritten around the two one-liners. Both `apt install cmark-gfm` and
`brew install cmark-gfm` pull core **and** extensions at matching versions — Debian's CLI
package `Depends:` on both versioned runtime packages, which independently enforces §3.1's
pairing rule — and both also install the `cmark-gfm` CLI the differential suite uses.

The supported-version table from §1.3 replaces the current "clone and build" contract.

### 8.2 The RHEL / Fedora / Alpine note

Required, and it must be honest that this is a **regression** for those platforms: 1.0's
vendored path built cmark-gfm from the submodule, so they worked with no system package.
2.0 does not build anything.

Draft text for `README.org`, under **Installing**:

```org
*** RHEL, Fedora, and Alpine

Neither Fedora/RHEL (including EPEL) nor Alpine packages the cmark-gfm C
library. Fedora ships only language bindings — ~ghc-cmark-gfm~ and
~python3-cmarkgfm~ — and ~cmark-devel~ is upstream cmark, not the GFM fork.
Alpine's ~cmark~ is likewise not the GFM fork.

Build it once from source; the default prefix is on the search path:

#+begin_src sh
git clone --branch 0.29.0.gfm.13 https://github.com/github/cmark-gfm
cmake -S cmark-gfm -B cmark-gfm/build \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMARK_SHARED=ON -DCMARK_TESTS=OFF
cmake --build cmark-gfm/build --target install   # -> /usr/local/lib
#+end_src

Any ~0.29.x.gfm.y~ satisfies the supported range. If you install somewhere
other than a searched directory, name both libraries explicitly:

#+begin_src sh
export CHEZ_CMARK_GFM_LIBS=/opt/cmark/lib/libcmark-gfm.so.0.29.0.gfm.13:/opt/cmark/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13
#+end_src

This is a step 1.0 did not require: its vendored build path compiled
cmark-gfm from the submodule. 2.0 compiles nothing, which is what makes the
Akku install work, and the cost falls on the platforms with no package.
```

### 8.3 Elsewhere

- `CHEZ_CMARK_GFM_SHIM` section replaced by `CHEZ_CMARK_GFM_LIBS`, keeping the
  validated-never-searched framing.
- The static-vs-dynamic section shrinks — ADR-0001's static-linking impossibility
  argument is now moot, since there is nothing of ours to link.
- `packaging/debian-prereqs.txt` splits: users need `cmark-gfm` alone, while CI still
  needs `cmake` and `build-essential` for the vendored oracle. One file with two labelled
  sections, or two files — either way the "one copy, deliberately" rule in its header
  must survive, since `README.org` and `ci.yml` both read from it.
- `NOTICE` stays. It reproduces cmark-gfm's license because the project builds and links
  against it; 2.0 still builds it under `vendor/` for the test oracle, so the obligation
  is unchanged. Its framing should say *development dependency* rather than implying the
  runtime links a bundled copy.
- The Memory-ownership section keeps every guarantee; only the counter mechanism changed.
- The support matrix (`README.org` §Supported matrix) gains the acquisition column
  described in §7.6, since "vendored vs pkg-config" no longer names the two paths.

## 9. Akku packaging

`Akku.manifest` gains `homepage`. **No `depends` key is added** — `(cmark gfm)` needs no
Scheme dependency at runtime, and `chez-srfi` and `wak-sxml-tools` stay `depends/dev`.

That is not merely a convention here: `tests/test-manifest-deps.sps` asserts `depends` is
exactly empty and that `depends/dev` matches a literal known-good set, as plan §16
criterion 15. Adding `homepage` must leave both assertions passing, and any change to the
dev set must update that literal in the same commit.

**No `scripts` clause.** Akku's script mechanism (`akku/lib/scripts.scm:183`) would run a
build, but it prompts for approval on every install until the package is vetted in the
index — for downstream dependants too, not just this project — and `run-cmd` ignores exit
status, so a failed build would report success. A script-free manifest avoids all of it.
Recorded as ADR-0017.

`akku install` will place `src/cmark/**.sls` under `.akku/lib/cmark/`. Nothing else is
needed: no `.akku/ffi` artifact, no generated file, no post-install step.

## 10. Release and migration

**2.0.0.** The breaking changes are §5's rename, §4's condition reshape, the retirement of
`CHEZ_CMARK_GFM_SHIM`, and the `CHEZSCHEMELIBDIRS` change. CHANGELOG gets a migration
table mapping each old name to its new one.

Order of work, each step leaving the suite green:

1. `(cmark gfm private discovery)` + its unit suite (§7.1), pure, nothing else touched.
2. The constant table + the header-parity test (§7.3), still with the shim in place. While
   both exist, add a **transitional assertion** that the Scheme table agrees with
   `chez_cmark_option_bits` for all 64 flag combinations. That is a direct equivalence
   proof against the very code being replaced, and it is deleted along with the shim in
   step 3 — its purpose is to make step 3 safe, not to live on.
3. `native.sls`: the five bindings replace the shim's, counters move to `scope.sls`.
   Shim still built; both paths live briefly.
4. Discovery wired into `native.sls`; `config.sls` and `fallback/` deleted.
5. The rename (§5) and the condition reshape (§4), mechanically across all ~40 sites.
6. Makefile and CI (§6, §7.6).
7. Documentation (§8), ADRs, CHANGELOG, version bump, tag.

Step 2 before step 3 is the load-bearing ordering: it proves the Scheme constants against
the shim that read them from the headers, while that shim still exists.

## 11. Risks and accepted consequences

### 11.1 RHEL, Fedora, and Alpine regress

Accepted, and documented rather than mitigated (§8.2). Those users gain a one-time
system-level source build in exchange for the platforms that *do* package it dropping a
per-project CMake build. Coverage: Debian 11+, Ubuntu 22.04+, Arch, openSUSE Tumbleweed,
NixOS, Gentoo, Void, and Homebrew all package it, and every packaged version falls inside
the existing supported range.

### 11.2 The allocator struct offset is an ABI assumption

"`free` is the third `void*` in `struct cmark_mem`" is a layout dependency where the shim
had a compiler-checked member access. It is stable across the pinned 0.29 range and
covered by §7.4, but it is new fragility and is recorded as such in ADR-0015.

### 11.3 Vendoring at install time was rejected

An Akku archive tarball is a repack of the git tree, so `vendor/cmark-gfm` arrives empty
and a script would have to clone during install — a network fetch and a multi-minute CMake
build inside a mechanism that ignores exit codes and logs at `debug`. Worse failure mode
than requiring the package.

### 11.4 A stale `/usr/local` build shadows a newer system package

First-directory-wins means an old `/usr/local/lib/libcmark-gfm.so.0.29.0.gfm.0` is chosen
over a newer packaged `gfm.13`. Both are in range, so both work; the older is simply
older. This matches conventional loader precedence, and `CHEZ_CMARK_GFM_LIBS` is the
escape hatch. Documented, not fixed.

### 11.5 Discovery is a search, and that reverses a stated position

`native.sls:46-47` (at `87c501b`) said the shim path is "validated, never searched." Directory
scanning is a search. The distinction being drawn — and it must be drawn explicitly in
ADR-0015, not left implied — is that a *fixed list of absolute system directories matched
against a versioned filename shape* is not the thing that posture excluded, which was
resolving an attacker- or accident-influenced **name** through a loader search path. The
override retains the strict no-search rule.

## 12. ADRs to write

- **ADR-0015 — Bind libcmark-gfm directly; delete the C shim.** Amends ADR-0001 (both
  acquisition paths collapse to "system package") and ADR-0002's shim rationale. Records
  §11.2 and §11.5.
- **ADR-0016 — Resolve cmark libraries by versioned filename, paired.** The §3.1
  invariant, all four clauses, with the double-load hazard as the motivating failure.
- **ADR-0017 — Ship no Akku `scripts` clause.** §9.

---

## Appendix A: probe evidence

Run against Chez 10.4.1 / libcmark-gfm 0.29.0.gfm.13 on macOS 26.5 arm64, 2026-08-21.

| Claim | Result |
|---|---|
| `cmark_version()` bound directly | `#x1D000D` |
| allocator slot 2 callable via address | render→free round-trip clean |
| `unsigned-8` reads `_Bool` correctly | `[x]`→1, `[ ]`→0 |
| bare soname resolves to Apple's copy | `/usr/lib/libcmark-gfm.dylib`, macOS 26.5, 217 `cmark_*` exports |
| Apple's copy has no dirent | `file-exists?` `#f`, `file-regular?` `#f` |
| `directory-list "/usr/lib"` versioned match | `()` |
| Homebrew versioned match | `("libcmark-gfm.0.29.0.gfm.13.dylib")`, `("libcmark-gfm-extensions.0.29.0.gfm.13.dylib")` |
| string-sort version selection | picks `gfm.9` over `gfm.13` — wrong |
| extensions → core reference | `@rpath/libcmark-gfm.0.29.0.gfm.13.dylib` (full version) |
| `machine-type` | `tarm64osx` |

## Appendix B: packaging survey

| Distro | Package | Version | In range |
|---|---|---|---|
| Debian 13/14/sid | `libcmark-gfm0.29.0.gfm.13` + `-extensions…` | 0.29.0.gfm.13 | ✓ |
| Debian 12 | (versioned name for gfm.6) | 0.29.0.gfm.6 | ✓ |
| Debian 11 | (versioned name for gfm.0) | 0.29.0.gfm.0 | ✓ |
| Ubuntu 25.04+ | as Debian 13 | 0.29.0.gfm.13 | ✓ |
| Ubuntu 24.04 LTS | | 0.29.0.gfm.6 | ✓ |
| Ubuntu 22.04 LTS | | 0.29.0.gfm.3 | ✓ |
| Arch / openSUSE TW / NixOS / Gentoo / Void | | 0.29.0.gfm.13 | ✓ |
| Homebrew | `cmark-gfm` | 0.29.0.gfm.13 | ✓ |
| **Fedora / RHEL / EPEL** | **none** (bindings only) | — | — |
| **Alpine** | **none** | — | — |

Debian's `cmark-gfm` CLI package `Depends:` on both versioned runtime libraries, so
`apt install cmark-gfm` is sufficient and cannot produce a mismatched pair.
