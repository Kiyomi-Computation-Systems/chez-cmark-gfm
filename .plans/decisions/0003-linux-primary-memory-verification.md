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

Linux CI is the gate for all memory claims, running Valgrind against a stock Chez
plus ASan/UBSan. macOS runs ASan/UBSan via `DYLD_INSERT_LIBRARIES` and `leaks` on a
best-effort basis.

Independently, the shim maintains debug allocation counters for parsers, roots, and
renderer buffers under `-DCHEZ_CMARK_DEBUG_COUNTERS`, queryable from Scheme, so each
test can assert its own balance.

## Consequences

- A green macOS run is **not** sufficient evidence for a memory claim. CI
  configuration and documentation must say so.
- Counters give per-test granularity, behave identically on both platforms, close the
  macOS LSan gap, and compile to nothing under `make prod`.
- Counters also make failure-path testing possible: inject a failure, assert the
  counters returned to baseline.
- Valgrind and ASan remain the outer gate for what counters cannot see — overflows,
  use-after-free, and leaks originating inside cmark itself.
