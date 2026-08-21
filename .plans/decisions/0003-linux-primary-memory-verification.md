# ADR-0003: Verify memory on Linux primarily, with in-process allocation counters

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md), [ADR-0002](0002-traverse-ast-in-scheme.md)

## Context

Because traversal lives in Scheme
([ADR-0002](0002-traverse-ast-in-scheme.md)), the risky lifecycle sequencing cannot
be exercised by a pure C harness — it must be tested in-process, with Chez running.

Chez is not built with sanitizers, so ASan requires preloading its runtime
(`LD_PRELOAD` / `DYLD_INSERT_LIBRARIES`) into a process that was not instrumented for
it. Valgrind, by contrast, needs no instrumentation of anything.

The decisive constraint: **LeakSanitizer is not supported on macOS/ARM64**, which is
the development machine. ASan there catches use-after-free and overflows but will not
find leaks.

Separately, neither Valgrind nor ASan can attribute a leak to an individual test —
both give a process-level verdict.

## Decision

Linux CI is the gate for all memory claims, running Valgrind against a stock,
uninstrumented Chez. macOS CI preloads the system ASan runtime
(`DYLD_INSERT_LIBRARIES`) into that same uninstrumented Chez, with its own leak
detection explicitly turned off (`ASAN_OPTIONS=detect_leaks=0`) since LeakSanitizer
does not exist on macOS/ARM64.

Independently, the shim maintains debug allocation counters for parsers, roots, and
renderer buffers under `-DCHEZ_CMARK_DEBUG_COUNTERS`, queryable from Scheme, so each
test can assert its own balance.

### Amended 2026-08-21, Stage 6

This ADR originally specified Linux CI running "Valgrind against a stock Chez plus
ASan/UBSan" and macOS running "ASan/UBSan via `DYLD_INSERT_LIBRARIES` and `leaks` on a
best-effort basis." Neither half of that was ever built. Verified directly: `rg
fsanitize Makefile .github/workflows/ci.yml` finds nothing, so no compiler-instrumented
ASan or UBSan exists anywhere in this project, on either platform — Linux CI runs
Valgrind alone, with no sanitizer step at all. UBSan is not used anywhere. macOS's
`test-memory` recipe never invokes the `leaks` tool.

What macOS CI actually does is preload the system ASan **runtime** (not a
`-fsanitize=address` build) into a Chez binary that was never compiled with any
sanitizer flag. That preload gives **allocator interposition** — the preloaded
runtime's `malloc`/`free` family intercept every allocation the process makes
through them, which is what lets it catch some heap corruption classes such as
double-free and use-after-free on the frees it sees — not the **compiler
instrumentation** a genuine `-fsanitize=address` build adds, which additionally
catches stack- and global-buffer overflows no allocator-level interposition can see.
Conflating the two overstates what the macOS leg actually proves. This distinction
does not change the Decision's bottom line, which was already correct and is restated
above: only Linux Valgrind supports a leak-freedom claim, and a green macOS run does
not.

Five places in this repository cite this ADR as authority for that leak-claim policy
(`README.org`, `Makefile`, `CHANGELOG.md`, and the two design specs). None needed a
change: each cites only the high-level policy above, and none repeated the specific
ASan/UBSan/`leaks` mechanism this amendment corrects.

## Consequences

- A green macOS run is **not** sufficient evidence for a memory claim. CI
  configuration and documentation must say so.
- Counters give per-test granularity, behave identically on both platforms, close the
  macOS LSan gap, and compile to nothing under `make prod`.
- Counters also make failure-path testing possible: inject a failure, assert the
  counters returned to baseline.
- Valgrind and ASan remain the outer gate for what counters cannot see — overflows,
  use-after-free, and leaks originating inside cmark itself.
