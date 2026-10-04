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

### Amended 2026-09-28: the macOS arm never loaded ASan, and now there is a check

The preload described above never reached a suite. From its first commit
(`3752e78`, 2026-08-16) the macOS arm of `make test-memory` set
`DYLD_INSERT_LIBRARIES` on `sh -c '…'`. `/bin/sh` is SIP-protected, and macOS purges
every `DYLD_*` variable when it launches a protected binary, so every suite ran
without ASan. Every tag from v0.1.0 to v2.0.0 carries that recipe. A `memset` one
byte past a block exited 0 through it and 134, with ASan's report, when `chez` was
launched directly. 1.0.0's CHANGELOG says ASan "ran clean" on macOS/ARM64; through
this recipe it had not run. `spike/FINDINGS.md`'s ASan runs were live, because they
invoked `chez` directly. Found through the identical defect in chez-libuv on
2026-09-27.

A second mechanism sits beside the first: ASan's Darwin runtime removes itself from
`DYLD_INSERT_LIBRARIES` in whatever process it loads into (`strip_env`), so a wrapper
such as `timeout(1)` gets ASan and the Chez it starts does not.

**Fix.** The loop runs in the recipe's own shell, and the preload is set on each
`$(CHEZ)` command with nothing in between. All 21 memory suites pass with ASan live,
and every suite's process printed ASan's start-up banner in a one-off witness run.

**Check.** `make check-memory-gate` plants defects (`tests/memory-gate-sabotage.sps`)
and runs the real `test-memory` recipe on each. It requires a non-zero exit *and* the
tool's own report of the defect, after a plain run has shown the planted program is
clean without a tool. macOS plants a libc `memset` overrun. Linux plants that, the
same overrun by a Scheme store, and a 777-byte definite leak. CI runs the check before
`test-memory`. The design is chez-libuv's (`4f63d56`).

**`MallocNanoZone=0` is removed.** It was added for Stage 2's Mutation C, on the
reading that the Nano allocator trapped on a double free before ASan's `free` could
report it. ASan was never loaded in that run. The trap was the plain allocator, which
traps with the Nano zone off as well, and with ASan live the variable changes nothing
measured.

**The Linux flags gain `--errors-for-leak-kinds=definite`.** Its default,
`definite,possible`, made a possibly-lost block fail the gate while
`--show-leak-kinds=definite` printed no record of it: exit 9, with only a summary
total in the log. No suite produces such a block today. The check's `possible-leak`
mode holds that the gate never fails on a leak kind it does not print.

**What the live macOS arm sees.** Only what passes through libc or the allocator:
overruns inside `memset` and `memcpy`, and double frees. Chez's generated code is not
instrumented. A `foreign-set!` past a block and a `foreign-ref` of freed memory both
exit 0 under live ASan and are caught by Valgrind, and `c-string->string` reads
render buffers with `foreign-ref`. So Linux Valgrind is the gate for more than leaks:
it is the only one that sees Scheme-side access to native memory.

Measurements and mutations are in `.plans/memory-gate-mutation-log.md`.

## Consequences

- A green macOS run is **not** sufficient evidence for a memory claim. CI
  configuration and documentation must say so.
- Counters give per-test granularity, behave identically on both platforms, close the
  macOS LSan gap, and compile to nothing under `make prod`.
- Counters also make failure-path testing possible: inject a failure, assert the
  counters returned to baseline.
- Valgrind and ASan remain the outer gate for what counters cannot see — overflows,
  use-after-free, and leaks originating inside cmark itself.
