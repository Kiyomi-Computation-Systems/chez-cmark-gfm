# ADR-0016: Resolve the cmark libraries by versioned filename, as a matched pair

- **Status:** Accepted
- **Date:** 2026-08-22
- **Scope:** chez-cmark-gfm 2.0
- **Related:** [Shimless FFI design](../2026-08-21-shimless-ffi-design.md) §3, §4, §11.4 ·
  [ADR-0015](0015-bind-libcmark-gfm-directly.md) (this is how it finds the library) ·
  [ADR-0014](0014-fallback-config-shadowing.md) (the generated paths this replaces)

## Context

ADR-0015 removed the build step that used to record where cmark-gfm lived, so the two
shared objects must be found at import time. The obvious implementation —
`(load-shared-object "libcmark-gfm.so")` and let the loader decide — is wrong in
several ways, and the one that matters most does not announce itself.

The one that motivates every rule below is the **double-load hazard**. The extensions
library does not reference the core by soname stem; it references it by full versioned
name. Verified on this machine:

```text
$ otool -L /opt/homebrew/lib/libcmark-gfm-extensions.0.29.0.gfm.13.dylib
	…
	@rpath/libcmark-gfm.0.29.0.gfm.13.dylib (compatibility version 0.29.0, …)
```

which is a `DT_NEEDED` on the equivalent SONAME under ELF. So a core and an extensions
library chosen independently do not merely disagree — loading the pair loads *the core
we picked*, and then lets the loader satisfy the extensions library's own dependency by
pulling in **a second core**. Two cmark cores in one process, with `cmark_version()`
reporting whichever one our `foreign-procedure` bindings happened to resolve against,
and a parser allocated by one core handed to accessors in the other. Nothing about that
fails loudly.

Multiple versions in one directory is the normal case, not a broken machine:
`vendor/cmark-gfm/src/CMakeLists.txt:106` sets `SOVERSION` to the *full* version
including the gfm patch, so every upstream release changes the SONAME and Debian gives
each its own co-installable runtime package.

## Decision

> **Core and extensions must be the same version, found in the same directory, selected
> by numeric comparison, and matched by versioned filename only.**

`(cmark gfm private discovery)` implements it, taking its filesystem access as
arguments so every branch is unit-testable against synthetic listings with no files on
disk (`discovery.sls:169`, `tests/test-discovery.sps`). Each clause closes a specific
failure:

1. **Versioned filename only.** A name is a candidate only if what sits between the
   platform's prefix and suffix parses as `MAJOR.MINOR.PATCH.gfm.GFMPATCH`, all four
   components numeric and the literal `gfm` in place (`discovery.sls:52-62`, `:92-101`).
   Debian's *runtime* package ships only `libcmark-gfm.so.0.29.0.gfm.13`; the
   unversioned `libcmark-gfm.so` symlink lives in `libcmark-gfm-dev`, alongside the
   headers, the static archive, and the `.pc` file. Checked against the two packages'
   own file lists on packages.debian.org (trixie/amd64), not inferred. Matching the
   unversioned name would therefore force a `-dev` package dependency on a Scheme
   library that compiles nothing. Asserted at `tests/test-discovery.sps:41-44` and
   `:85-86`.
2. **Numeric comparison.** `maximum` compares encoded integers, not strings
   (`discovery.sls:157-160`). Lexically, `"libcmark-gfm.so.0.29.0.gfm.9"` sorts *above*
   `"…gfm.13"` — `#\9` is greater than `#\1` — so a string sort selects the older
   library while looking entirely reasonable. `tests/test-discovery.sps:72-77` pins both
   the `gfm.6`/`gfm.13` and the `gfm.9`/`gfm.13` cases; the second fails if comparison
   is ever made lexical.
3. **Same version.** Only versions present as *both* a core and an extensions library
   are considered — a set intersection on the encoded version
   (`discovery.sls:155`, `:180-181`).
4. **Same directory, matched pair.** The intersection is computed per directory, so a
   directory holding only one half of a pair is skipped rather than completed from
   somewhere else (`discovery.sls:169-190`). This is the clause that closes the
   double-load hazard, and it is a correctness requirement rather than tidiness:
   `tests/test-discovery.sps:82-84` asserts that core `gfm.13` beside extensions
   `gfm.6` yields `not-found`, and `:97-99` that an unpaired core in the first directory
   falls through to a paired second one.

Within a directory the numerically greatest in-range version wins; across directories,
the first directory that yields a pair wins, matching conventional loader precedence.
A paired-but-unsupported version returns `out-of-range` carrying what it found
(`discovery.sls:173-175`, `tests/test-discovery.sps:90-92`) so a machine with only
cmark-gfm 0.30 is told that, rather than being sent looking for a package it already
has.

Rejected alternatives:

- **Load by bare soname and let the loader resolve it.** On macOS this silently finds
  Apple's own copy; see the first Consequence. On Linux it needs the `-dev` symlink,
  which is clause 1's problem, and it discards every guarantee above.
- **Match the unversioned symlink where it exists, and fall back to versioned names.**
  Same `-dev` dependency, plus a machine-dependent selection: which library the
  symlink names is not something this project can state in its supported-version range.
  The environment override is the supported way to name an unversioned file, and it is
  the user's explicit choice rather than our guess.
- **Choose core and extensions independently, each the newest of its kind.** This is the
  double-load hazard as a design.
- **Scan every `/usr/lib/*-linux-gnu*` directory on a multiarch box.** One triple is
  derived from `(machine-type)` instead (`discovery.sls:115-145`), because there is
  deliberately no fall-through on load failure: a wrong-architecture candidate that
  passed the filename check would be a hard error, not a retry. The full scan survives
  only as the fallback for a machine stem the table does not know
  (`discovery.sls:121-129`).

## Consequences

- **macOS's own `/usr/lib/libcmark-gfm.dylib` stays unreachable, by three independent
  properties.** Probed on macOS 26.5 arm64 under Chez 10, with `DYLD_LIBRARY_PATH`
  unset and no cmark in `/usr/local/lib`, so the shared cache is the only thing the
  bare name can reach: `(load-shared-object "libcmark-gfm.dylib")` succeeds,
  `cmark_version()` returns `#x1D000D` — identical to the pin — and both
  `cmark_gfm_core_extensions_ensure_registered` and
  `cmark_gfm_extensions_get_tasklist_item_checked` resolve out of that single library.
  So a soname fallback would satisfy every check this binding makes while running a
  build the differential suite does not oracle against, whose headers ship nowhere, and
  which Apple may change on any OS update — and it would do so with no extensions
  library involved at all. What keeps it out is that (1) it has no filesystem entry —
  `file-exists?` and `file-regular?` both `#f`, and `(directory-list "/usr/lib")` shows
  no `libcmark-gfm*` at all; (2) its name is unversioned, so it fails clause 1; and
  (3) `(load-shared-object "libcmark-gfm-extensions.dylib")` raises, so there is no
  pair for clause 4 to match and `/usr/lib` is rejected regardless.
  `native.sls:57-64` carries this as a comment, because the natural "simplification" of
  adding a soname fallback reintroduces it silently.
- **A stale `/usr/local` build shadows a newer system package.** First-directory-wins
  means an old `/usr/local/lib/libcmark-gfm.so.0.29.0.gfm.0` is chosen over a packaged
  `gfm.13` in `/usr/lib/<triple>`. Both are in range so both work; the older is simply
  older. This matches conventional loader precedence and `CHEZ_CMARK_GFM_LIBS` is the
  escape hatch. Documented, not fixed, and there is no test for it — it is emergent
  from the first-directory-wins case at `tests/test-discovery.sps:94-96` rather than
  asserted on its own.
- **A library installed under a name we do not recognise is invisible.** Anything not
  matching the two shapes at `discovery.sls:78-90` — a hand-built cmark installed with
  `VERSION` but no `SOVERSION`, a distro that changes its naming, a static archive — is
  not a candidate and produces `not-found`. The remedy is `CHEZ_CMARK_GFM_LIBS`, and it
  is the same remedy for every `invalid-override` cause, which is why those causes are
  deliberately not discriminated (`conditions.sls:97-100`).
- **`not-found` does not say where it looked.** The condition carries `path` `#f` and
  the reason symbol and nothing else (`conditions.sls:101-104`); the diagnostic
  `tests/preflight.sps` prints both the reason symbol and the *remedy* — the two install
  one-liners and the override — and CI asserts both (`.github/workflows/ci.yml`, step
  "build must fail with not-found, and name the remedy"). Asserting the remedy alone was
  not enough: the program's catch-all `else` clause prints the same one-liners for *any*
  condition, so that grep passed on a raw FFI crash or an unreadable directory just as
  readily as on `not-found`. The reason symbol is the discriminating half. The design spec asked
  for a message naming the candidate directories and that was not
  built. For the common case, a machine with no cmark-gfm, the remedy is the more useful
  answer; for the uncommon one, a library present in a directory the search does not
  cover, the user is told to name it explicitly without being told what was already
  tried. A real gap, recorded rather than papered over.
- **The rules are more machinery than a soname load, and each one is invisible until it
  fails.** Twelve selection cases in `tests/test-discovery.sps:61-99` exist because
  nothing else in the repository notices when one of these rules is relaxed. That is
  the cost of the guarantee, and it is why `discovery.sls:10-12` points at the design
  spec before anything here is changed.
- **The override does no version parsing at all** (`discovery.sls:220-243`). An explicit
  `CHEZ_CMARK_GFM_LIBS` may legitimately name the unversioned symlinks from a `-dev`
  package, so selection is the user's. Verification is still ours: `cmark_version()` is
  read immediately after the two loads and checked against the supported range in
  `native.sls`'s library body (`native.sls:134`, `:157`), so it runs on every path, the
  override included. That covers the version and only the version — see the last two
  Consequences. Entries are classified by **basename**, not whole
  path, so a directory named `…cmark-gfm-extensions-cache…` cannot silently swap the
  pair (`discovery.sls:203-218`, `tests/test-discovery.sps:150-157`); order in the
  variable therefore does not matter.
- **Two checks run at different times for different reasons**, and both are needed: the
  filename check diagnoses an out-of-range library *by name, before loading it*, on the
  discovery path only; the post-load `cmark_version()` check is authoritative — a
  filename is a claim and distros patch — and runs on both paths. The second is reachable
  only because of where it sits. Chez resolves a foreign entry point when the
  `foreign-procedure` expression is *evaluated*, and a library body evaluates its
  definitions in order, so `native.sls` binds `cmark_version` alone straight after the
  loads and checks it there (`native.sls:134`, `:157`), ahead of every other
  `foreign-procedure`. Placed any later — in `ensure-native-loaded!`, which runs at first
  *use*, as it originally was — the check is unreachable for precisely the libraries it
  exists to reject, because an unsupported library aborts the import at whichever binding
  it cannot satisfy. `ensure-native-loaded!` still re-runs it; under this ordering that
  copy cannot fire, and it is kept as cheap redundancy rather than as coverage.
- **The version check is not a symbol check and must not be read as one.** It rejects a
  library whose `cmark_version()` is out of range, and nothing else. A library *inside*
  the range that is missing one of the symbols bound below the check still dies at import
  with a raw `Exception in foreign-procedure: no entry for "…"`, and so does a library
  that does not export `cmark_version` at all. The design spec §3.8 defect —
  `cmark_node_get_item_index`, absent before `0.29.0.gfm.11`, under a range that claims
  `gfm.0` — was exactly that shape: no version check of any placement could have
  diagnosed it, and the remedy was to stop binding the symbol. Keeping the declared range
  honest about the symbols actually bound is a review obligation, not something this
  machinery enforces.
