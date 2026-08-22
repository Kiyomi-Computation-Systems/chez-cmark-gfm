# ADR-0015: Bind `libcmark-gfm` directly and delete the C shim

- **Status:** Accepted
- **Date:** 2026-08-22
- **Scope:** chez-cmark-gfm 2.0
- **Related:** [Shimless FFI design](../2026-08-21-shimless-ffi-design.md) §2, §4, §6, §11 ·
  [ADR-0001](0001-hybrid-native-dependency-acquisition.md) (amended again here) ·
  [ADR-0002](0002-traverse-ast-in-scheme.md) (the thin shim it kept is now deleted;
  its traversal decision stands) ·
  [ADR-0014](0014-fallback-config-shadowing.md) (this is its named successor) ·
  [ADR-0016](0016-paired-versioned-library-discovery.md), [ADR-0017](0017-no-akku-scripts.md)

## Context

1.0 shipped `src/cmark-gfm-shim.c` — 71 lines declaring fourteen `chez_cmark_*` entry
points (`git show 87c501b:src/cmark-gfm-shim.c`, `…shim.h`). ADR-0002 kept it thin: it did
no traversal, no parsing, and no rendering. Everything else Scheme bound directly.

The shim's cost was never its size. It was that **something had to compile it**.
ADR-0001 gave two acquisition paths — a `pkg-config` system library, or a CMake build
of the `vendor/cmark-gfm` submodule — and both ended in a C compiler run before
`(import (cmark gfm))` would work at all. ADR-0014 then had to invent a checked-in
fallback `config.sls` so that an unbuilt tree failed with a diagnosable condition
rather than "library not found", and its own Consequences conceded the result: "Akku
installation becomes *diagnosable* rather than supported."

ADR-0014 named its successor as configuration read at runtime rather than generated
into the source tree. That is this decision, and it turned out to reach further than
ADR-0014 expected: with the library resolved at runtime there is nothing left for the
build step to record, and with the five remaining C jobs bound from Scheme there is
nothing left for the build step to build.

## Decision

Delete `src/cmark-gfm-shim.{c,h}` and every build path that produced it. Bind
`libcmark-gfm` and `libcmark-gfm-extensions` directly, and resolve both at runtime
(ADR-0016). `src/cmark/gfm/private/native.sls` now binds 37 named cmark entry points
plus one bound by address; nothing of ours is compiled.

The five jobs that stood between Scheme and cmark, and what replaced each:

| Shim job | Replacement | Where |
|---|---|---|
| `chez_cmark_shim_compiled_version` | deleted — no compile step, so no header/runtime skew can exist | `native.sls:288-292` |
| `chez_cmark_runtime_version` | `(foreign-procedure "cmark_version" () int)` | `native.sls:119` |
| `chez_cmark_option_bits` | six constants and the mask builder, in Scheme | `native.sls:304-326` |
| `chez_cmark_free_buffer` | the third `void*` of `cmark_get_default_mem_allocator()`, called via its address | `native.sls:131-142` |
| `chez_cmark_tasklist_checked` | `unsigned-8` as the result type, so only the defined byte of a C `_Bool` is read | `native.sls:149-153` |

The debug counters were never cmark's. They counted acquisitions this binding makes,
and they are now three Scheme variables in `native.sls:161-173`, always on. `make prod`,
`make check-prod`, and the `FLAVOR` machinery existed only to compile them out; all
three are gone.

Three alternatives were rejected:

- **Keep the shim; drop only the vendored path.** Requiring a system cmark-gfm removes
  CMake, `pkg-config`, and the submodule build, and it is a smaller change. It does not
  remove the C compiler, and the compiler is the whole obstacle: the exit criterion for
  2.0 is a machine with a package manager and Chez and nothing else.
- **Keep the shim and build it during `akku install`.** Rejected on the mechanism —
  see [ADR-0017](0017-no-akku-scripts.md) — and on the substance: an Akku archive
  tarball is a repack of the git tree, so `vendor/cmark-gfm` arrives empty and the
  script would have to clone during install and then run a multi-minute CMake build.
- **Ship prebuilt shims.** An Akku archive entry is a repack of the source tree, so
  there is no per-platform binary channel to put them in; and a checked-in binary would
  have been built against a cmark the installing machine may not have, reintroducing
  exactly the compiled-versus-runtime skew the first row of the table above deletes.

## Consequences

- **ADR-0001's two acquisition paths collapse into one.** There is no `pkg-config`
  path and no vendored-build path, because there is nothing of ours to link. A user
  installs the system package. `vendor/` and `make vendor` stay, as a **development**
  dependency only: the `cmark-gfm` CLI is the differential oracle, `cmark-gfm.h` is
  what `tests/test-option-bits.sps:18` parses, and the 744-example corpus is read from
  the working tree.
- **RHEL, Fedora, and Alpine regress.** 1.0's vendored path built cmark-gfm from the
  submodule, so those platforms worked with no system package. None of them packages
  the GFM fork — checked, not assumed: Fedora has no `cmark-gfm` package at all (its
  `cmark-devel` is upstream cmark, and only bindings such as `ghc-cmark-gfm` and
  `python3-cmarkgfm` carry the name), and Alpine ships plain `cmark` only. So 2.0 asks
  those users for a one-time source build. This is a real loss, taken so that the
  platforms which *do* package it stop paying for a per-project CMake build.
- **The rationale for keeping the option bits in C is amended; ADR-0002's decision is
  not.** ADR-0002 listed "option-bit construction" among the jobs it left to C, and
  `src/cmark-gfm-shim.h:19-20` (at `87c501b`) gave the reason: keeping it there "means
  the numeric constants are read from the real headers and cannot drift from what
  Scheme believes them to be." (The design spec attributes that sentence to ADR-0002;
  it is the shim header's.) The guarantee weakens to "drift fails a test." Two tests
  carry it, and they cover different amounts:
  - `tests/test-differential.sps:120-142` — five of the six flags, each with a paired
    assertion: first that the CLI's own output moves when the flag is passed, then that
    ours matches it byte for byte. A wrong constant fails the second half.
  - `tests/test-option-bits.sps:64-69` — all six, parsed out of
    `vendor/cmark-gfm/src/cmark-gfm.h`. This is the only place `validate-utf8?`'s
    constant is checked against the real header: it is structurally unreachable
    through the public API
    (`tests/test-differential.sps:102-106`), so no fixture can discriminate it, and the
    structural assertions beside the parity check (`tests/test-option-bits.sps:75-82`)
    compare the Scheme table with itself. If the submodule is not checked out, that
    suite's first assertion fails rather than skipping — an absent oracle is a failure
    here, not an excuse.

  ADR-0002's actual decision — traverse the AST in Scheme, keep C to a minimum — is
  unaffected, and the amount of C is now zero.
- **The allocator offset is an ABI dependency, and it is new fragility.** "`free` is the
  third `void*` of `struct cmark_mem`" was a compiler-checked member access in the
  shim; it is now `(foreign-ref 'uptr mem (* 2 (foreign-sizeof 'void*)))` at
  `native.sls:137-139`, believed rather than checked. The test at
  `tests/test-native.sps:331-337` asserts the three slots are present, distinct, and
  non-null, which catches a NULL slot, a duplicated slot, and a struct shrunk to fewer
  members. **It does not catch a reordering** — three distinct non-null pointers stay
  three distinct non-null pointers under any permutation — and
  `tests/test-native.sps:320-330` says so in the source. The ordering guarantee rests on
  `tests/test-differential.sps`, whose renders exercise the real release path through
  that exact slot, and on `make test-memory` (ADR-0003). A future cmark that inserted a
  member ahead of `free` would pass the slot test, and the first render would call
  through the wrong function pointer.
- **Discovery is a search, and that reverses a stated position.** 1.0's `native.sls:46-47`
  (at `87c501b`) said the shim path is "validated, never searched". That comment is gone
  from `native.sls`, but the posture still has to be answered for, because scanning
  candidate directories is a search. The distinction being drawn, and it is the whole of
  why this is not a reversal in substance: what that posture excluded was resolving an
  attacker- or accident-influenced **name** through a loader search path — `dlopen("libcmark-gfm.so")`
  and whatever `LD_LIBRARY_PATH`, `DYLD_*`, or a shared cache decides that means. What
  2.0 does instead is match a **fixed list of absolute system directories**
  (`discovery.sls:108-113`) against a **versioned filename shape**
  (`discovery.sls:84-101`), and load the result by absolute path
  (`native.sls:103-116`). No name we did not construct is ever handed to the loader.
  `CHEZ_CMARK_GFM_LIBS` keeps the strict rule unchanged: two absolute paths to existing
  regular files, used verbatim, with no fallback to the search when they are wrong
  (`native.sls:74-79`, `discovery.sls:228-243`).
- **ADR-0014 is spent.** `fallback/`, the generated `src/cmark/gfm/private/config.sls`,
  `make check-config`, `tests/check-config.sps`, and `tests/test-fallback-config.sps`
  are all deleted, and the Makefile's `CHEZ_LIBDIRS` drops its `fallback` segment:
  `src:fallback:tests:$(SRFI_LIBS)` becomes `src:tests:$(SRFI_LIBS)` (`Makefile:21`).
  The `not-built` reason retires with them.
- **What ADR-0014 predicted and what shipped are not the same shape**, and the
  difference is worth recording rather than smoothing over. Its Successor said "shim
  path and cmark library paths from the environment or a config file, resolved and
  validated at load time," and called it "a second config mechanism". Delivered:
  runtime resolution validated at load time, as promised; but there is no shim path,
  because there is no shim; there is no config file, only `CHEZ_CMARK_GFM_LIBS` or the
  built-in candidate search; and it is not a *second* mechanism, since the generated
  config it would have sat beside is gone. ADR-0014 did not anticipate a directory
  search at all, which is why the paragraph above has to exist.
- **`make build` no longer builds.** It runs `tests/preflight.sps` (`Makefile:70-71`),
  which prints the two absolute paths discovery resolved and the version they report,
  or exits non-zero naming the remedy (`tests/preflight.sps:25-47`). That keeps the
  canonical target meaningful — it answers "is this machine set up?", which is the
  question the 2.0 install contract raises — and it puts the resolved paths in CI's log,
  so a later failure can be read against the library that job actually loaded. The house
  Makefile convention's `make prod` is simply absent; there is no compiled artifact to
  have a production flavour of.
- **`make check-purity` survives unchanged in shape.** `CHEZ_CMARK_GFM_LIBS=/nonexistent`
  is an `invalid-override` and fails closed exactly as the poisoned shim path did
  (`Makefile:183`).

## Successor

Windows (ADR-0004) is closer than it was: the C build was the largest obstacle and it
is gone. Nothing here attempts it — `discovery.sls:78-90` knows two name shapes, both
POSIX — and the work is a stage of its own.
