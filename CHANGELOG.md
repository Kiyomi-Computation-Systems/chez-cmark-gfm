# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org).

## Unreleased

### Added

- A pinned Guix development environment for x86_64 Linux, which keeps the
  build and test toolchain off the host. `scripts/guix-env` opens a
  container shell or runs one command (`scripts/guix-env make test`) with
  the toolchain pinned by `channels.scm` and `manifest.scm`. The container
  holds no credentials: edit, commit and push on the host, agents included
  (ADR-0019). `make check-guix` (local, not CI) asserts that the library
  loads from `/gnu/store`, that nothing of `HOME` is visible inside, that
  `scheme`, `make`, `git` and `cmark-gfm` resolve to the pinned binaries,
  and that `$CHEZ` is the real Chez binary Valgrind instruments. See
  [docs/building.md](docs/building.md#guix-development-environment),
  ADR-0018 and ADR-0019.
- A source-checked [API reference](docs/reference.md) for all six public
  modules and 85 exported bindings. `make check-reference` compares its module
  and binding coverage against the R6RS export declarations, and
  `make check-site` runs that gate before rendering the documentation site.
- A static documentation site generated from `docs/*.md` and an authored
  `site/index.md`, rendered entirely through `markdown->sxml` → transform →
  serialize and deployed to GitHub Pages. Flexoki theme, sidebar + per-page
  TOC. `make site` builds it into `build/site/` (nothing committed);
  `make check-site` asserts nav completeness, anchor resolution, no `.md`
  leak, and no `<pre>` reflow. `.github/workflows/pages.yml` deploys on a
  `v*` tag.
- `make check-memory-gate`, which proves `make test-memory` can fail. It
  plants memory defects (`tests/memory-gate-sabotage.sps`) and requires the
  real recipe to fail on each, with the tool's own report of that defect in
  the log. Linux plants a one-byte overrun by a Scheme store, the same by
  libc's `memset`, and a definite leak; macOS plants the `memset` overrun.
  CI runs it before the Valgrind step. See
  [docs/building.md](docs/building.md#make-check-memory-gate).

### Fixed

- **`make test-memory` on macOS never loaded AddressSanitizer.** It set
  `DYLD_INSERT_LIBRARIES` on `sh -c '…'`, and macOS drops `DYLD_*`
  variables when it launches a SIP-protected binary such as `/bin/sh`. So
  every suite ran without ASan, in every release up to 2.0.0, and the run
  was green. 1.0.0's "Verification status" says ASan ran clean on
  macOS/ARM64; it had not run. The preload is now set on each `chez`
  command, and all 21 memory suites pass with ASan live. The Linux arm ran
  Valgrind on Chez directly at every tag, so Linux leak evidence is
  unaffected. The recipe's
  `MallocNanoZone=0` is removed: the reason recorded for it was a misreading
  of this same defect. See ADR-0003's 2026-09-28 amendment.
- **Valgrind could fail `make test-memory` without saying why.** The Linux
  arm failed on "possibly lost" blocks but printed only "definitely lost"
  ones, so such a block would have turned the run red with only a summary
  total in the log. It now fails only on definite leaks, the kind it prints.
  No suite produced a possibly-lost block, so no result changes.

## [2.0.0] — 2026-08-22

The C shim is gone. `(cmark gfm)` binds `libcmark-gfm` directly and locates it
on the host at import time, so installing this package needs no compiler, no
CMake, and no submodule checkout: `apt install cmark-gfm` or `brew install
cmark-gfm`, and then `akku install` works — the release's whole reason to
exist. Parsing, rendering, the AST, and the SXML mapping are unchanged; every
API change below follows from the shim's disappearance, not from a change of
behaviour. See ADR-0015, ADR-0016, ADR-0017.

### Breaking changes

| Removed / changed | Replacement |
|---|---|
| `&cmark-shim-unavailable`, `cmark-shim-unavailable?`, `-path`, `-reason` | `&cmark-library-unavailable`, `cmark-library-unavailable?`, `-path`, `-reason` — same shape, same two fields |
| reasons `not-built`, `missing` | `not-found`, whose `path` is `#f`: discovery searched several directories, so there is no single path to name |
| `cmark-version-incompatible-compiled` | `cmark-version-incompatible-supported`, and it now carries the `(lo . hi)` supported range rather than one encoded version — there is no compile step left to skew against |
| `CHEZ_CMARK_GFM_SHIM`, one absolute path to the shim | `CHEZ_CMARK_GFM_LIBS`, **two** colon-separated absolute paths — core and extensions, in either order, classified by basename |
| `CHEZSCHEMELIBDIRS=src:fallback` | `CHEZSCHEMELIBDIRS=src` |
| `make prod`, `make check-prod`, `make check-config` | removed. `make build` is now a discovery preflight: it compiles nothing and prints the library that would be loaded |
| `HAVE_PKG`, `FLAVOR`, `CC`, `CFLAGS_*`, and the acquisition/flavor stamp machinery | removed. With no artifact there is no build mode to select and no mode flip to relink across |
| `item` `index`, the number typed in the source | `item` `index`, the item's **ordinal position** — its list's `start` plus its offset among that list's items, and 0 for every item of a bullet list. `1. 1. 1.` was `(1 1 1)` and is now `(1 2 3)`; `1. 5. 9.` was `(1 5 9)` and is now `(1 2 3)`. `1. 2. 3.` and `5. 6. 7.` are unchanged. The literal numbers are no longer recoverable from the AST |

`invalid-override` and `load-failed` keep their names and meanings.
`invalid-override` now covers a wider set of causes — wrong entry count, a
relative path, an absent file, two libraries of the same kind — because the
remedy is identical for all of them: name both libraries, by absolute path.

A fourth reason, `missing-entry-point`, is new. It is listed here rather than
under *Added* only so the reasons stay in one place — **it is not a breaking
change**. Adding a reason is additive for existing `guard` clauses: they
discriminate on `cmark-library-unavailable?`, and every one of them still
catches every condition it caught before. Only code that exhaustively
`case`s on the reason symbol and errors on the default would notice, and
nothing is obliged to. See the `0.29.0.gfm.0` floor note below for why it
exists.

`cmark-gfm-version-compatible?` keeps its name and arity. It now answers "is
the loaded library inside the supported range", which is the only version
question left once nothing is compiled against a header.

The `index` redefinition is *half* of what makes the declared `0.29.0.gfm.0`
floor true. `cmark_node_get_item_index`, which returned the literal number, was
added upstream in `f040422` and first tagged in `0.29.0.gfm.11`; binding it
killed `(import (cmark gfm))` outright — with a raw Chez
`no entry for …`, not a structured condition — on every library below that,
which is Debian 11 and 12 and Ubuntu 22.04 and 24.04. The ordinal is not an
invention either: cmark's own commonmark, man, and plaintext renderers
overwrite that field with exactly this number (`render.c:188-190`), so
`markdown->commonmark` already renumbered `1. 1. 1.` to `1. 2. 3.`. It is
computed from `cmark_node_get_list_start` and `cmark_node_get_list_type` on
the parent list, both present since well before 0.29, plus the sibling
offset `convert-children` already threaded for table-cell alignment — so no
FFI surface was added to remove one. See design spec §3.8.

The other half is `cmark_gfm_extensions_get_tasklist_item_checked`, and it
could not be fixed the same way, because it cannot be fixed by a version check
at all. That entry point first shipped in `0.29.0.gfm.1` — unpatched upstream
`0.29.0.gfm.0` spells it `cmark_gfm_extensions_get_tasklist_state` — and on
such a library 11 of the 20 suites died with the same raw
`no entry for …`. But Debian 11 backports the rename into *its* `gfm.0` (its
`libcmark-gfm-extensions0.symbols` lists the symbol at `@Base 0.29.0.gfm.0`)
while still reporting `0.29.0.gfm.0` from `cmark_version()`. A `gfm.0` floor
therefore admits the upstream build that crashes; a `gfm.1` floor rejects the
Debian build that works. The two are indistinguishable by version because the
constraint is not a version — it is the presence of one symbol, which
distributions patch independently of the version they report. So the symbol is
probed instead: that one binding is wrapped in a `guard` and raises
`&cmark-library-unavailable` with reason `missing-entry-point`, naming the
extensions library. The declared range is unchanged. See design spec §3.10.

### Added

- **Akku install support.** `akku install` places `src/cmark/**.sls` under
  `.akku/lib/` and needs no post-install step: no generated file, no native
  artifact, no `scripts` clause. `Akku.manifest` gains `homepage` and still
  declares no runtime `depends` — `chez-srfi` and `wak-sxml-tools` remain
  development-only. CI's `akku-install` job installs from the manifest and
  then *calls into* `(cmark gfm)` with nothing set in the environment; a bare
  import would not prove it, since Chez instantiates a library's body only
  when a binding is referenced.
- **`src/cmark/gfm/private/discovery.sls`** — pure library resolution. It
  takes its filesystem access as arguments, so every branch is testable
  against synthetic listings with no files on disk. Core and extensions must
  pair at the *same version* in the *same directory*, and version comparison
  is numeric, not lexical: `0.29.0.gfm.9` sorts above `0.29.0.gfm.13` as a
  string, which would have selected the older library. See ADR-0016.
- **`tests/test-discovery.sps`** — the discovery algorithm against those
  synthetic listings: name shapes, pairing, range filtering, first-directory
  wins, the Linux triple table, and override parsing including the swapped
  and same-kind cases.
- **`tests/test-library-loading.sps`** and **`tests/load-failed-probe.sps`** —
  the override's validation rules, the `load-failed` path, and the
  `missing-entry-point` path. The last two run in a subprocess because the
  failure happens at library-instantiation time. `missing-entry-point` is
  reached without compiling or committing a stub: the decoy extensions
  library is a symlink to the *resolved core library*, which loads, reports
  an in-range version, and exports no `cmark_gfm_extensions_*` symbol at all
  — the same shape as an unpatched `gfm.0`, from a file already on the
  machine.
- **`tests/test-option-bits.sps`** — asserts every cmark option constant now
  built in Scheme against `vendor/cmark-gfm/src/cmark-gfm.h`, which is what
  replaced the shim's job of reading them from the header.
- **`tests/preflight.sps`** — what `make build` runs.
- **CI jobs `no-library` and `akku-install`.** The first installs Chez and
  deliberately no cmark-gfm, asserting `make build` fails, reports reason
  `not-found`, and names the remedy; without it, nothing would ever exercise
  the `not-found` branch, because every other job installs the package. Both
  greps are needed: `tests/preflight.sps`'s catch-all clause prints the same
  remedy for any condition, so the reason symbol is the only half of the
  assertion that discriminates.

- `make help` lists every target, and `make check-help` fails when one is
  undocumented.
- `make install` / `make uninstall` copy `src/cmark/**.sls` to
  `$(PREFIX)/lib/chez-cmark-gfm` for consumers not using Akku. Nothing is
  compiled. Chez has no system-wide R6RS library directory, so the target
  prints the `CHEZSCHEMELIBDIRS` line to add — with the trailing colon
  that keeps `.` on the search path.
- `make check-install` installs to a temporary prefix and renders a
  document with `CHEZSCHEMELIBDIRS` naming only that directory.

### Removed

- **The C shim** — `src/cmark-gfm-shim.c` (71 lines) and
  `src/cmark-gfm-shim.h` (70). Fourteen `chez_cmark_*` entry points, doing
  five jobs, are gone: `compiled_version` had nothing left to compare
  against; `runtime_version` became `cmark_version` bound directly;
  `option_bits` became six Scheme constants asserted against the header;
  `free_buffer` became the third
  `void*` of `cmark_get_default_mem_allocator()`, called via its address;
  and `tasklist_checked` became a direct binding with an `unsigned-8`
  result, which reads the one byte `_Bool` actually defines. The debug
  counters moved into Scheme — they only ever counted this library's own
  acquisitions, never the C heap.
- **`fallback/`** and the generated `src/cmark/gfm/private/config.sls`.
  Nothing is generated, so "unbuilt" is no longer a distinct state and there
  is no sentinel configuration for a built tree to shadow. ADR-0014's
  mechanism is retired with them.
- **The CMake shim build**, and with it `make prod`, `tests/check-prod.sps`,
  `tests/check-config.sps`, `tests/shim-load-probe.sps`,
  `tests/test-fallback-config.sps`, and `tests/test-shim-loading.sps`.
  `make vendor` still builds `vendor/cmark-gfm`, but only as a development
  dependency: the 744-example corpus, the header `test-option-bits.sps`
  parses, and a CLI build to point `CMARK_CLI` at. The differential suites'
  default oracle is the `cmark-gfm` the system package puts on `PATH`.

### Changed

- The two CI steps that grep the Supported matrix, and the preflight's
  cmake-recipe pointer, now name `docs/installing.md`.
- CI now runs `make check-help` and `make check-install`. Both targets were
  added to the Makefile but invoked by no workflow step, and neither is a
  prerequisite of `build`, `test`, `check-purity`, or `examples` — so
  neither was reached transitively either. `check-install` runs on both
  Linux and macOS, which is not one run duplicated: discovery hardcodes a
  different candidate directory list *and* a different filename shape per
  platform, so a break in either branch is invisible to the other job.

### Documentation

- `README.org` cut from 643 lines to 165. Reference material moved to
  eight pages under `docs/`: installing, usage, options, the AST, SXML
  (serializing included), errors, memory ownership, and building.
- Dropped the 1.0-vs-2.0 comparison table. Nobody consumed 1.0; the
  history is in this file.
- `NOTICE` now states the obligation that actually applies — expression
  transcribed from cmark-gfm into `src/cmark/gfm/sxml.sls`,
  `tests/spec-corpus.sls`, and `tests/sxml-html-serializer.sls`, each cited
  by file and line — and drops four licenses nothing here derives from
  (`buffer`/`chunk`, `utf8proc`, `normalize.py`, and the CC-BY-SA spec
  text).
- Corrected cmark-gfm's license label in `NOTICE`: it is **BSD-2-Clause**,
  not BSD-3. `vendor/cmark-gfm/COPYING` carries no endorsement clause, and
  cmark-gfm's own README says "BSD2-licensed". chez-cmark-gfm's own license
  is untouched and really is BSD-3-Clause — a different project under a
  different license.
- Added `CONTRIBUTING.md`, `SECURITY.md`, and GitHub issue/PR templates.

### Notes

- **RHEL, Fedora, and Alpine regress, and this is accepted rather than
  mitigated.** None of them packages the cmark-gfm C library — Fedora ships
  only language bindings, and both distributions' `cmark` is upstream cmark,
  not the GFM fork. 1.0's vendored path compiled cmark-gfm from the
  submodule, so those platforms worked with no system package; 2.0 compiles
  nothing and asks for a one-time source build instead. `README.org` gives
  the commands. Debian 11+, Ubuntu 22.04+, Arch, openSUSE Tumbleweed, NixOS,
  Gentoo, Void, and Homebrew all package it; every packaged version falls
  inside the supported range and exports every entry point this library
  resolves at import, which is what the `index` redefinition above bought.
- **The `0.29.0.gfm.0` floor holds for every *packaged* library, with one
  caveat about an *upstream* `gfm.0` build.** Of the 36 entry points still
  bound, 35 exist at every upstream 0.29 tag. The exception is
  `cmark_gfm_extensions_get_tasklist_item_checked`, which first appears in
  `0.29.0.gfm.1`; upstream `gfm.0` spells it
  `cmark_gfm_extensions_get_tasklist_state` and returns `char *` instead.
  This does not reach the documented install path — Debian and Ubuntu
  backport the rename into their `0.29.0.gfm.0-N` packages, and bullseye's
  `debian/libcmark-gfm-extensions0.symbols` lists the new name — but a
  library built from an unpatched upstream `0.29.0.gfm.0` checkout would
  still fail at import. The source-build instructions in `README.org` pin
  `0.29.0.gfm.13`, so nothing this project documents reaches it.
- **The supported-range check is what an out-of-range library hits, and it is
  a version check only.** `cmark_version()` is read in `native.sls`'s library
  body, immediately after the two loads and ahead of every other
  `foreign-procedure` definition, so an unsupported version raises
  `&cmark-version-incompatible` at import — on the discovery path and on the
  `CHEZ_CMARK_GFM_LIBS` override alike, the latter doing no filename version
  parsing at all. It cannot help with the case in the bullet above: a library
  *inside* the range that is missing a symbol still dies at whichever binding
  it cannot satisfy, with a raw Chez `no entry for …`. Keeping the declared
  range honest about the symbols actually bound is a review obligation, not
  something this check enforces.
- **"`free` is the third `void*` in `struct cmark_mem`" is an ABI
  assumption**, where the shim had a compiler-checked member access. It is
  stable across the pinned 0.29 range and is covered by an allocator
  round-trip assertion, but it is new fragility. See ADR-0015.
- **Discovery is a search, and 1.0's `native.sls` said the path was
  "validated, never searched."** The distinction being drawn is that a fixed
  list of absolute system directories matched against a versioned filename
  shape is not what that posture excluded, which was resolving an attacker-
  or accident-influenced *name* through a loader search path.
  `CHEZ_CMARK_GFM_LIBS` retains the strict no-search rule.
- **First directory wins**, so a stale `/usr/local/lib` build shadows a newer
  packaged one. Both are in range, so both work; this matches conventional
  loader precedence, and `CHEZ_CMARK_GFM_LIBS` is the escape hatch.

## [1.0.0] — 2026-08-21

Packaging, documentation, and release. No parsing, rendering, or mapping
behavior changed: 1.0 freezes the API. The one public-API change is additive.

### Added

- **`examples/`** — six runnable programs covering rendering, options, the
  AST, SXML, the condition family, and capability inspection. `make examples`
  runs each and diffs its output. It sets `CHEZSCHEMELIBDIRS=src:fallback` and
  nothing else, so an example that reached a dev dependency breaks the build —
  which is what keeps 0.3.0's "a consumer acquires neither" true rather than
  merely written down.
- **`tests/test-example-coverage.sps`** — fails when `(cmark gfm)` gains an
  export that appears in no example. It reads the export list and each
  example as *datums*, not text, so an identifier mentioned only in a comment
  does not count. Exemptions carry a reason each and are themselves checked
  for staleness and typos; today they cover eleven condition type names,
  which are not first-class values, and eleven predicates and accessors on
  conditions an example cannot trigger through the public API — most
  genuinely unreachable, three (`cmark-shim-unavailable?` and its two
  accessors) reachable only at import time, before an example's own code
  runs. `cmark-unsupported-node?`/`cmark-unsupported-node-type` carry no
  exemption: an earlier version of the list exempted them on the reasoning
  that the adapter covers every node type the real parser emits, which
  argues from the parser's side — `markdown-ast->sxml` is public and accepts
  an arbitrary caller-built tree, and `make-markdown-node` validates
  nothing, so the condition is reachable through public procedures alone.
  `examples/05-errors.sps` demonstrates it directly, handing the adapter an
  `extension` node that names a native type cmark-gfm never registered.
- **`tests/test-manifest-deps.sps`** — reads `Akku.manifest` as data, the
  same technique `test-example-coverage.sps` uses on `gfm.sls`, and asserts
  that no declared dependency's name matches a documentation-site-tool
  marker and that the declared dependency set is exactly today's known-good
  one. Plan §16, criterion 15 (no dependency on a documentation-site
  framework) was true only by inspection before this suite existed.
  `make check-purity` now gates five pure suites, up from three: this one
  and `test-example-coverage.sps` join `test-options.sps`, `test-ast.sps`,
  and `test-sxml.sps`.
- **`tests/test-stress.sps`** — asserts the live parser, root, and buffer
  counts return to zero after *every* iteration of a repeated
  parse/render/AST/SXML loop. Every counter assertion before this was
  single-shot, so a per-call leak of one buffer satisfied all of them.
  `CMARK_STRESS_ITERATIONS` tunes the count; the memory targets drop it to 2.
- **`fallback/cmark/gfm/private/config.sls`** — a checked-in configuration,
  shadowed by the generated one whenever a build has happened. See below.
- **`NOTICE`** — the binding's own BSD-3-Clause notice, plus all seven
  license blocks bundled in `vendor/cmark-gfm/COPYING`, reproduced in full:
  cmark-gfm's core and its `test/` suite (BSD-2-Clause, both John
  MacFarlane); the `houdini`-, `buffer`/`chunk`-, and `utf8proc`-derived code
  (three separate MIT grants); `normalize.py` (MIT, Karl Dubost); and the
  CommonMark spec text itself (CC-BY-SA 4.0). Plan §14 requires license
  notices for the binding and its native dependency. `LICENSE` (the
  binding's own) predates this branch; `NOTICE`, covering the native
  dependency, is new here — closing the half of §14 that was still open.
- **A clean-machine CI job** in a bare `ubuntu:24.04` container that runs only
  the steps the README documents. It never runs `make deps`.
- **`make check-config`** and **`make examples`**.

### Changed

- **`&cmark-shim-unavailable` carries a `reason`**: `not-built`, `missing`,
  `invalid-override`, or `load-failed`. Four distinct failures previously
  shared one field, so a caller could not tell a missing build from a bad
  `CHEZ_CMARK_GFM_SHIM`. Additive for existing `guard` clauses. Mirrors
  `&cmark-invalid-option`'s `key` + `reason` pair.
- **An unbuilt tree now names its own remedy.** It used to fail with
  `library (cmark gfm private config) not found`, which names no cause and is
  not a condition; it now raises `&cmark-shim-unavailable` with reason
  `not-built`. The fallback's `shim-path` is `#f` rather than a plausible fake
  path, because no build can produce a non-string there — which is what keeps
  "never built" distinguishable from "shim deleted since". See ADR-0014.
- **`CHEZSCHEMELIBDIRS` is now `src:fallback`.** The order is the mechanism:
  Chez resolves a library from the first entry that has it.
- **The documented Chez floor is 9.5.8, not 10.4.1.** The old claim recorded
  one developer's machine and was never tested; 9.5.8 is the version Ubuntu CI
  has run green under Valgrind on earlier commits (see Verification status below
  for what that does and does not establish about this release). A CI step now asserts the README matrix against the
  version each job actually ran, so a runner-image bump fails the build rather
  than letting the claim go stale.

### Verification status

- **Leak-checking has now run against this release, and is clean.** Plan §16
  names "native tests pass under AddressSanitizer *and* a leak checker" as a v1
  acceptance criterion. Both halves are satisfied. On Linux/x86-64, all 17
  memory-eligible suites ran under Valgrind (`--leak-check=full
  --show-leak-kinds=definite --error-exitcode=9`): **`definitely lost: 0 bytes
  in 0 blocks`** in every suite reporting a leak summary, "all heap blocks were
  freed" in the rest, and `ERROR SUMMARY: 0 errors` in all 17. The residual
  `still reachable: 6,019 bytes in 31 blocks` is identical in every suite and is
  Chez's own runtime allocation, not this binding's. On macOS/ARM64 ASan ran
  clean with leak detection disabled, because LeakSanitizer does not exist there
  (ADR-0003) — which is why the Linux run, and only the Linux run, is what
  supports this claim.
- **This release is the first whose CI has actually executed.** The branch
  carrying it was pushed before merge specifically so the evidence above would
  exist rather than being assumed, and the first run failed all three jobs: CI
  had come to depend on `ripgrep`, which GitHub-hosted runners do not install.
  A silently-empty package list, two matrix checks that could not distinguish a
  missing tool from a real mismatch, and a container-ownership refusal were all
  found that way and fixed before merge.

### Fixed

- **Four empty assertions in `tests/test-native.sps`.** Each expected exactly
  the path `resolve-shim-path` *returns on success*, so all four passed against
  code with every rejection deleted — verified: 54 of 54, exit 0. They now
  assert `(path reason)`, a shape no success path here produces, and each
  `guard` body ends in `'no-condition`.

### Documentation

- The supported platform/Chez/cmark matrix, the memory-ownership contract, and
  the static-versus-dynamic linking behavior (static linking is *impossible*
  here, not merely unchosen — cmark's static archives hide every symbol that
  ADR-0002 requires Scheme to resolve at runtime). All three are Plan §14
  requirements the README had never met.
- Prerequisites live in `packaging/debian-prereqs.txt` in exactly one copy,
  which the README points at and CI installs from.
- Akku is documented as *not yet* a supported install path, with what an
  unbuilt tree does instead. README additions are deliberately terse; in-depth
  documentation is deferred to a `docs/` tree.

## [0.3.0] — 2026-08-18

The SXML adapter. `markdown->sxml` and `markdown-ast->sxml` turn Markdown into
an SXML tree in HTML vocabulary, which a conforming serializer renders as an
HTML fragment. `(cmark gfm sxml)` is pure and optional in both directions: it
imports nothing that reaches a shared object, and no existing library imports
it, so a caller who never mentions SXML links no new code and acquires no new
dependency.

### Added

- `markdown->sxml`. Three arities: `(markdown->sxml md)` uses
  `(default-cmark-options)` and `(default-sxml-options)`; `(markdown->sxml md
  opts)` and `(markdown->sxml md opts sxml-opts)` take the caller's records.
  It lives in `(cmark gfm)` rather than in the adapter because it parses.
- `markdown-ast->sxml` in the new library `(cmark gfm sxml)`, re-exported from
  `(cmark gfm)`. Arity 1–2. It is a pure Scheme-records-to-Scheme-lists
  transformation and runs under `make check-purity` as a third gated suite.
- `make-sxml-options`, `default-sxml-options`, `sxml-options-with`, and the
  three accessors, mirroring the `cmark-options` trio — including its
  rejection of unknown keys, duplicate keys, and unknown values. Fields:
  `raw-html` (`omit` | `escape`, default `omit`), `softbreak` (`newline` |
  `break` | `space`, default `newline`), and `attribute-marker` (`caret` |
  `at`, default `caret`).
- `softbreak` exists because cmark's `hardbreaks?` and `nobreaks?` are
  renderer options that never reach the parse, so no AST can carry them
  (`html.c:319-325`). It names what a softbreak *becomes*, because cmark's own
  pair is mutually exclusive with a precedence rule and a three-valued field
  cannot express the contradictory state at all.
- `attribute-marker` defaults to `caret`, **not** the SXML specification's
  `@`. Both serializers reachable on this platform mark an attribute list `^`
  — `wak-sxml-tools` (`sxml-tools/upstream/sxml-tools.scm:44-48`) and
  `wak-htmlprag` (`htmlprag/htmlprag.scm:334`) — and neither recognises `@` at
  all: handed a `@`-marked tree, `srl:sxml->html` does not raise, it silently
  turns every attribute list into bogus child elements. `'attribute-marker
  'at` gives the specification's spelling. See ADR-0013.
- `&cmark-unsupported-node`, carrying the native type string. It derives from
  `&cmark-error` directly rather than from `&cmark-invalid-input`: the
  document is not invalid, the adapter is incomplete. The SXML adapter is the
  first consumer with no way to continue, since it has no HTML vocabulary for
  a node type it does not know.
- `&cmark-malformed-tree`, carrying a reason. `markdown-ast->sxml` is public
  and takes an arbitrary tree, so a caller can hand it a table whose header
  row is not first — an order cmark's own parser never produces
  (`extensions/table.c:402-403,447`) and whose faithful rendering would open a
  `thead` inside an open `tbody`.
- `chez-srfi` moved from `depends` to `depends/dev`, where it always belonged
  — `(cmark gfm)` imports none of it — and `wak-sxml-tools` added alongside
  it. Both are test-only; a consumer of this package acquires neither.

### Security

- **`raw-html` defaults to `omit` because it is the policy that does not
  depend on the caller's serializer.** Under `omit` a raw `html-block` or
  `html-inline` becomes `(*COMMENT* " raw HTML omitted ")`, reproducing
  `html.c:259` and `html.c:337` exactly: there is nothing to escape, because
  the tree holds no attacker-controlled markup at all, so the output is safe
  whatever serializer the caller chose. Under `escape` the literal is carried
  through as an ordinary string and the safety rests entirely on that
  serializer escaping it — a policy only as good as code this project does not
  control, which is why it is opt-in and why the third-party serializer suite
  exists. There is no trusted or unsafe mode and none is planned (ADR-0011):
  SXML has no portable raw-markup node, and a caller needing the literal reads
  it from the AST.
- `markdown->sxml` raises `&cmark-invalid-option` with reason
  `not-applicable` for `unsafe-html?`, `hardbreaks?`, and `nobreaks?`. All
  three are cmark **renderer** options — verified absent from `blocks.c`,
  `inlines.c`, and `parser.h` — so none can reach the AST, and SXML is a
  different renderer with its own policies. Silently discarding a
  security-relevant setting the caller made explicitly is not acceptable; the
  cost is one `cmark-options-with` line for a record shared with
  `markdown->html`, which makes the divergence explicit at the call site.
- **The URL rule is cmark's own**, transcribed from `src/scanners.re:345-354`:
  a URL is dangerous when it begins `javascript:`, `vbscript:`, `file:`, or
  `data:`, matched case-insensitively — re2c single-quoted literals are
  case-insensitive — **including cmark's `data:image` carve-out**, which lets
  `data:image/png`, `data:image/gif`, `data:image/jpeg`, and
  `data:image/webp` through. It applies to `link` `href` and `image` `src`
  only, and a rejected URL yields an empty attribute value rather than a
  raised condition or a removed attribute (`html.c:387-391,405-409`). Adopting
  cmark's rule rather than inventing one is what makes the corpus differential
  run with zero URL deltas.
- The adapter percent-encodes bytes outside `HREF_SAFE`
  (`src/houdini_href_e.c:32-44`) and never touches `&` or `'`; entity-escaping
  those is the serializer's half. `houdini_escape_href` does both jobs in one
  pass, and doing both halves in one place silently produces `%2520` or
  `&amp;amp;` — valid HTML carrying the wrong URL.

### Notes

- `source-positions?` is **accepted and silently discarded**, the one stated
  exception to the rule above. Unlike the three renderer-only options it
  refuses, positions genuinely reach the AST; it is the adapter that drops
  them, per ADR-0011. The cost is wasted parse work, not a downgraded policy.
  `markdown->sxml` therefore defaults to `(default-cmark-options)`, not
  `(default-ast-options)` — ADR-0009's per-entry-point principle pointing the
  other way from `markdown->ast`.
- The tree carries HTML vocabulary and nothing else (ADR-0011): no
  annotations, no `data-*` metadata, no source positions. List `delimiter`,
  `item` index, fence info past the first token, image child structure, and
  every source position are dropped, and `markdown->ast` remains the interface
  for all of them. That is what puts almost everything under the oracle: with
  no metadata channel, what the tree says about the document is what the HTML
  shows. Two properties still sit outside it and carry direct assertions
  instead — `raw-html: escape`, which cmark has no equivalent for, and
  `attribute-marker`, which the test serializer normalises away because it
  accepts `^` and `@` alike. See design spec §10.
- `tagfilter` has no observable effect on SXML. `extensions/tagfilter.c:58`
  registers only an HTML filter function — no postprocess, block, or inline
  handler — so it cannot reach the AST. Asserted rather than documented.
- Verified by re-serializing the tree through a test-only serializer written
  against `vendor/cmark-gfm/src/html.c` and diffing byte-for-byte against
  `markdown->html`, in-process, across all 744 examples of cmark's own corpus
  (`spec.txt` 672, `extensions.txt` 30, `smart_punct.txt` 16, `regression.txt`
  26), once per attribute marker. The second leg — the pinned `cmark-gfm` CLI,
  the independent witness that the parse itself was configured right — runs the
  four `tests/fixtures/*.md`, not the corpus; 744 × 2 subprocesses costs about
  13 s against a suite that otherwise finishes in 0.36 s. Design spec §10
  records that reduction and what it gives up. `raw-html: escape` and
  `attribute-marker` sit outside the oracle entirely and carry direct
  assertions only (design spec §10 again).
- **Byte-equality with cmark is a property of that serializer, not a promise
  about the caller's pipeline.** A conforming third-party serializer differs
  in inter-block whitespace, `"` in text, `'` in an `href`, childless-element
  form, and the document's trailing newline — all semantically equivalent
  HTML. A **pretty-printing** serializer is a different matter: injected
  indentation corrupts `<pre>` content. See README.org.

## [0.2.0] — 2026-08-17

The Scheme-owned AST. `markdown->ast` returns immutable records containing no
native pointers, valid after every cmark object has been freed. The SXML
adapter follows in 0.3 (ADR-0007).

### Added

- `markdown->ast`. Two arities: `(markdown->ast md)` uses
  `(default-ast-options)`, which turns source positions on; `(markdown->ast md
  opts)` honours the caller's options record verbatim. See ADR-0009 — one
  shared default cannot serve both the AST and the renderers well.
- `(cmark gfm ast)`, re-exported from `(cmark gfm)`: `make-markdown-node`,
  `markdown-node?`, the four field accessors, `markdown-node-property` with an
  optional default, `markdown-node-with-properties`,
  `markdown-node-with-children`, `markdown-node-map` (children-first),
  `markdown-node-fold` (pre-order), and the `source-position` record.
- 24 cmark type strings covering CommonMark and all five GFM extensions,
  mapping to 22 distinct `markdown-node-type` values — `"item"`/`"tasklist"`
  both yield `item`, and `"table_row"`/`"table_header"` both yield
  `table-row`. A task item and a table header row are distinguished by
  cmark's own type strings, which is the only reliable channel for either:
  `cmark_gfm_extensions_get_tasklist_item_checked` returns false both
  for an unchecked task and for a non-task.
- `max-nodes` (default 250000) and `max-depth` (default 1000) options.
  `max-input-bytes` does not bound the AST — 5 MiB of adversarial input parses
  to millions of nodes — so the copy has its own ceilings.
- `&cmark-resource-limit`, carrying the ceiling that was exceeded. It derives
  from `&cmark-invalid-input`, so existing code guarding
  `cmark-invalid-input?` on an oversized document keeps working while new code
  can catch resource exhaustion as a class.
- `default-ast-options`.

### Security

- **The AST is untrusted structured input.** Parsing preserves exactly what the
  document said, including raw HTML literals and `javascript:` URLs. No
  sanitisation happens during conversion and `unsafe-html?` has no effect on
  it — that option is a renderer policy. Sanitise when rendering.
- Node and depth ceilings bound the Scheme-side allocation, and a document
  exceeding either raises before the tree is built rather than exhausting
  memory.

### Notes

- Source positions are only trustworthy with `CMARK_OPT_SOURCEPOS` on:
  `vendor/cmark-gfm/src/inlines.c:292-296` skips a correction when it is off,
  leaving multi-line code spans and raw inline HTML with wrong end positions
  that propagate to later inlines. The AST therefore attaches a position only
  when it parsed with the flag, and reports `#f` otherwise.
- An unrecognised node type is preserved as an `extension` node carrying the
  native type string, never discarded. No such type is reachable through the
  options this library exposes — footnotes require `CMARK_OPT_FOOTNOTES`, which
  is not exposed — so the branch is unit-tested rather than exercised
  end-to-end.
- The AST is verified by re-serializing it into cmark's own XML dialect and
  diffing byte-for-byte against `cmark_render_xml` and the pinned CLI across
  the four fixtures with and without positions. Item index, table column count,
  and body-cell alignment are invisible to that oracle and carry direct
  assertions instead. See ADR-0010.

## [0.1.0] — 2026-08-17

First release. Parsing and direct rendering with safe defaults; the Scheme
AST and the SXML adapter follow in 0.2 and 0.3 (ADR-0007).

### Added

- `(cmark gfm)` — the public API: options, renderers, version and capability
  inspection, and the structured condition types.
- `markdown->html`, `markdown->commonmark`, `markdown->plaintext`, and
  `markdown->xml`. The commonmark and plaintext renderers take an optional
  wrap width; html and xml are fixed at arity 2, because cmark applies width
  only to the renderers that wrap.
- Immutable options: `make-cmark-options`, `default-cmark-options`, and
  `cmark-options-with`. Options are named symbols; cmark's numeric constants
  and string names never appear in the public API.
- All five standard GFM extensions — `autolink`, `strikethrough`, `table`,
  `tagfilter`, `tasklist` — enabled by default.
- `cmark-gfm-version`, `cmark-gfm-version-compatible?`, and
  `cmark-gfm-available-extensions`.

### Security

- HTML rendering is safe by default: raw HTML and unsafe link schemes are
  suppressed unless `'unsafe-html? #t` is set explicitly. There is no global
  switch; the setting belongs to each immutable options object.
- Embedded NUL input is rejected, and input is bounded by `max-input-bytes`
  (5 MiB by default) before parsing.

### Notes

- `source-positions?` defaults to `#f` in this release, diverging from
  project plan §6.2. See ADR-0008 — the AST in 0.2 is the consumer that
  wants positions, and this default is scoped to renderer-only releases.
- `validate-utf8?` is accepted and wired, but has no observable effect on
  input reaching the public API: Scheme strings always encode to valid
  UTF-8. See the Stage 2 design spec §10.1.
- Output is verified byte-for-byte against the pinned `cmark-gfm`
  0.29.0.gfm.13 CLI across 24 distinct option configurations in four formats,
  each exercised twice via the sweep's 48 boolean combinations. See the Stage
  2 design spec §7.4.
