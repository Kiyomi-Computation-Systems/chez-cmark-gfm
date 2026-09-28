# The macOS memory gate never loaded ASan: mutation log

Evidence for `fix/asan-preload-reaches-chez`. The macOS arm of
`make test-memory` never put ASan into the Chez process that runs the
suites. This change makes it live, adds `make check-memory-gate` to require
the real recipe to fail on planted defects, and closes a gap in the Linux
arm's leak flags. ADR-0003's 2026-09-28 amendment records the decision;
this file records the measurements.

The same defect was found in chez-libuv on 2026-09-27. `check-memory-gate`
and `tests/memory-gate-sabotage.sps` copy its design from chez-libuv
commit `4f63d56` (branch `fix/memory-gate-traces-chez`, unmerged when this
was written). Every number below was measured here, not carried over.

Environment, unless a line says otherwise:

- **macOS:** 26.6.2 (25G83) on arm64, SIP enabled. Homebrew Chez 10.4.1
  (`tarm64osx`), GNU Make 3.81 (`/usr/bin/make`), and Xcode clang 21's
  `libclang_rt.asan_osx_dynamic.dylib`.
- **Linux, CI's stack:** `ubuntu:24.04` amd64 under Docker Desktop's
  emulation, with `packaging/debian-prereqs.txt` plus `valgrind`: Chez
  9.5.8 (`/usr/bin/chezscheme`, a real binary), Valgrind 3.22.0 and
  cmark-gfm 0.29.0.gfm.6, as ci.yml's linux job installs them.
- **Linux, native:** Debian bookworm on aarch64 (chez-libuv's
  `chez-libuv-valgrind:10.4.1` image plus apt's `cmark-gfm`): Chez 10.4.1
  (`scheme`), Valgrind 3.19.0 and cmark-gfm 0.29.0.gfm.6.

A worktree's `.git` is a pointer file that a container cannot resolve, so
every Linux run used a real clone in the session scratchpad, with
submodules cloned from the local checkouts. Every mutation ran on a scratch
clone outside the repository, reset from a commit between mutations, and
each edit was confirmed present before its run.

---

## The defect

### `/bin/sh` is SIP-protected, and macOS purges `DYLD_*` when it launches one

The macOS arm set `DYLD_INSERT_LIBRARIES` on
`sh -c 'for t in $(MEMORY_TESTS); do $(CHEZ) --program $$t || exit 1; done'`.
`ls -lO /bin/sh` shows `restricted`, and:

```
$ DYLD_INSERT_LIBRARIES=/x FOO=bar sh -c 'echo "[DYLD=$DYLD_INSERT_LIBRARIES] [FOO=$FOO]"'
[DYLD=] [FOO=bar]
```

`chez` itself honours the variable: `codesign -dv` shows
`flags=0x20002(adhoc,linker-signed)`, with no hardened runtime. With
`DYLD_PRINT_LIBRARIES=1`, a direct `chez` launch prints
`libclang_rt.asan_osx_dynamic.dylib` 4 times; the same launch through
`sh -c` prints it 0 times.

A probe that `memset`s 30 bytes into a 29-byte `foreign-alloc` block:

| launch | exit | ASan report |
|---|---|---|
| plain `chez` | 0 | none |
| `env DYLD_INSERT_LIBRARIES=… chez` | 134 | `heap-buffer-overflow`, `0 bytes after 29-byte region` |
| `DYLD_INSERT_LIBRARIES=… sh -c 'chez …'` | 0 | none |
| **the real recipe**: `make test-memory MEMORY_TESTS=<probe>` | **0** | none; the probe printed its "planted" line |

The shape dates from the arm's first commit (`3752e78`, 2026-08-16), and
every tag from v0.1.0 to v2.0.0 carries it (`git show <tag>:Makefile`). So
`make test-memory` never ran a suite under ASan. 1.0.0's CHANGELOG
("Verification status") says ASan "ran clean" on macOS/ARM64 and that Plan
§16's AddressSanitizer half was satisfied; through this recipe it was not.
`spike/FINDINGS.md`'s ASan runs were live: they invoked `chez` directly and
showed the runtime in a `DYLD_PRINT_LIBRARIES` trace. The spike checked
that `chez` was not SIP-restricted, then the recipe put `/bin/sh`, which
is, in between.

### A wrapper loses it too: ASan's `strip_env`

ASan's Darwin runtime removes itself from `DYLD_INSERT_LIBRARIES` in the
process it loads into. Through brew's `timeout` (not SIP-protected), the
memset probe exits **0**; with `ASAN_OPTIONS=…:strip_env=0` it exits 134
with the report. So a wrapper gets ASan and the Chez it starts does not.

This caught one of this session's own probes. A capability probe written as
`env DYLD_INSERT_LIBRARIES=… env CHEZ_CMARK_GFM_SABOTAGE=… chez …` put a
second, SIP-protected `/usr/bin/env` in between, and exited 0 as though
ASan had missed the defect. Its `verbosity=1` witness count was empty,
which is how it was noticed. Every "live ASan" row below carries that
witness.

---

## The fix

The loop runs in the recipe's own shell, and `DYLD_INSERT_LIBRARIES` is
set on each `$(CHEZ) --program $$t` command, with nothing in between. The
recipe now prints the runtime it found.

---

## `MallocNanoZone=0`: the recorded explanation was wrong

The recipe's comment said macOS's Nano allocator "can SIGTRAP on a
double-free before ASan's interposed free() gets a chance to run its
check", citing `stage-2-mutation-log.md`'s Mutation C. That diagnostic
changed two things at once: it ran `chez` directly, not through the
recipe's `sh -c`, *and* it added `MallocNanoZone=0`. It credited the
second. A double free of a 16-byte `foreign-alloc` block, 3 of 3 runs
each:

| launch | `MallocNanoZone` | exit | report |
|---|---|---|---|
| plain `chez` | unset | 133 (SIGTRAP) | none |
| plain `chez` | `0` | 133 (SIGTRAP) | none |
| ASan, direct | unset | 134 | `attempting double-free` |
| ASan, direct | `0` | 134 | `attempting double-free` |
| pre-fix shape (`sh -c`) | `0` | 133 (SIGTRAP) | none |
| pre-fix shape (`sh -c`) | unset | 133 (SIGTRAP) | none |

Mutation C itself, re-applied to today's `scope.sls` (free the render
buffer, then read it, then free it again in the after-thunk) and run as
`make test-memory MEMORY_TESTS=tests/test-render.sps`:

| recipe | result |
|---|---|
| pre-fix (`e0118a3`'s Makefile) | `sh: line 1: 54073 Trace/BPT trap: 5       chez --program $t`, the line stage 2 recorded but for the pid |
| fixed, no `MallocNanoZone` | `ERROR: AddressSanitizer: attempting double-free`, from `free` in the ASan runtime |
| fixed, `MallocNanoZone=0` re-added | identical |
| plain `chez`, no tool | exit 133 |

The bare trap was the plain allocator: ASan was not loaded, and the trap
fires with the Nano zone off too. With ASan live, `MallocNanoZone=0`
changes nothing measured here: not the double-free report, not the memset
report, and not the start-up output of a clean program (no "nano zone
abandoned" warning either way). Deleting it leaves `check-memory-gate`
green (row N1 below) and all 21 suites pass without it. It was removed,
not re-explained. The read of the freed buffer was never caught on macOS,
because a Scheme-side read is invisible to ASan (see "What live ASan
sees").

---

## The check: `make check-memory-gate`

`tests/memory-gate-sabotage.sps` plants one defect, chosen by
`CHEZ_CMARK_GFM_SABOTAGE`. For each of the platform's modes the check
requires a plain run with no tool to exit 0 and print
`memory-gate-sabotage: planted <mode>`, then runs `$(MAKE) test-memory
MEMORY_TESTS=tests/memory-gate-sabotage.sps` and requires a non-zero exit
and the tool's own report of that defect in the log.

### Markers

Each was measured 3 of 3 runs directly under Valgrind with the recipe's
flags as they stood, identical on both Linux stacks. The check has since
matched every one through the final recipe on both stacks:

| mode | defect | Valgrind (Linux) | ASan (macOS) |
|---|---|---|---|
| `store-overrun` | `foreign-set!` 1 byte past a 23-byte block | `0 bytes after a block of size 23 alloc'd` | not seen (exit 0, ASan live) |
| `libc-overrun` | `memset` of 30 bytes into a 29-byte block | `0 bytes after a block of size 29 alloc'd` | `0 bytes after 29-byte region` |
| `leak` | `foreign-alloc 777`, dropped | `777 bytes in 1 blocks are definitely lost` | not applicable (`detect_leaks=0`) |

Linux runs all three and macOS runs `libc-overrun`. `memset` is not a
foreign entry until libc is loaded, so the program loads `libc.dylib` or
`libc.so.6` first.

### Red, then green (macOS)

With the check added and the recipe unfixed:

```
=== check-memory-gate: libc-overrun ===
MEMORY GATE VACUOUS: make test-memory exited 0 with the libc-overrun defect planted;
the memory tool is not checking the Chez process. Tail of build/check-memory-gate-libc-overrun.log:
...
memory-gate-sabotage: planting libc-overrun
memory-gate-sabotage: planted libc-overrun
MEMORY GATE CHECK FAILED
```

The "planted" line inside the "ASan" arm cannot appear when ASan is
loaded, because ASan aborts at the `memset`. After the fix:
`gate caught libc-overrun: 0 bytes after 29-byte region`,
`MEMORY GATE CAN FAIL`.

### Linux was live

The Linux arm runs `valgrind … $(CHEZ) --program $$t`, with nothing in
between, and it was already checking Chez. With the recipe as it stood,
the check printed `gate caught` for all three defects on both stacks, and
every Valgrind `Command:` line was `chezscheme` or `scheme --program
tests/memory-gate-sabotage.sps`.

---

## The Linux leak flags: `--errors-for-leak-kinds=definite`

The Linux arm passed `--show-leak-kinds=definite` and left
`--errors-for-leak-kinds` at its default, `definite,possible`. A 555-byte
block whose only reference is an interior pointer (`p+8`, stored as raw
bytes in a live bytevector; memcheck scans the Scheme heap) measured the
same on both stacks:

| flags | exit | log |
|---|---|---|
| as they stood | **9** | `possibly lost: 555 bytes in 1 blocks` in the summary, `ERROR SUMMARY: 1 errors`, **no loss record** |
| plus `--errors-for-leak-kinds=definite` | 0 | the same summary total, `ERROR SUMMARY: 0 errors` |

So a possibly-lost block failed the gate with a log that names no block
and no allocation site. No suite produces one today on either stack
(below), so it has not fired on the current suites.

It is held by a check, not a comment. The Linux mode `possible-leak`
plants that block and requires consistency: the gate may pass on it, or
fail and print its loss record (`555 bytes in 1 blocks are possibly
lost`), but it must not fail without one. It also requires the summary
total, or the plant proved nothing. Against the old flags (first seen red
before the flag was added; this wording is from row M5 of the final
sweep, which restores the old flags):

```
=== check-memory-gate: possible-leak ===
GATE RED WITHOUT A REPORT: make test-memory failed on a possibly-lost block
and printed no loss record for it: --errors-for-leak-kinds names a kind
that --show-leak-kinds hides. Tail of build/check-memory-gate-possible-leak.log:
```

With the flag: `gate consistent on possible-leak: exit 0, possibly lost:
555 bytes in 1 blocks`. Row P7 below shows the check also accepts the other
consistent policy, showing and failing on both kinds.

---

## Mutations

Both sweeps ran against the Makefile as committed, each from a scratch
clone reset to it between rows. N1 is the exception: the line it deletes
is gone from the final recipe, so it ran on the intermediate recipe that
still had it.

### macOS (scratch clone, final recipe)

| # | mutation | check-memory-gate |
|---|---|---|
| — | control: final, unmutated | exit 0, `gate caught libc-overrun` |
| A1 | the pre-fix shape: the loop under `sh -c` | exit 2, `MEMORY GATE VACUOUS … libc-overrun` |
| A2 | brew `timeout 600` between the preload and `$(CHEZ)` | exit 2, `MEMORY GATE VACUOUS … libc-overrun` |
| A3 | the `DYLD_INSERT_LIBRARIES` line deleted | exit 2, `MEMORY GATE VACUOUS … libc-overrun` |
| H | `ASAN_OPTIONS=…:halt_on_error=0`: ASan reports and carries on | exit 2, `MEMORY GATE VACUOUS … libc-overrun` |
| N1 | `MallocNanoZone=0` deleted (run on the intermediate recipe that still had it) | exit 0, `gate caught libc-overrun` |
| C1 | the sabotage program ends with `(exit 3)` | exit 2, `SABOTAGE NOT CLEAN: the libc-overrun program exited 3` |
| C2 | an unrelated failure: the recipe finds no ASan runtime and refuses | exit 2, `failed, but not on the planted libc-overrun` |
| C2′ | C2, with the marker test disabled (`elif false`) | **exit 0, `gate caught libc-overrun`, `MEMORY GATE CAN FAIL`**, while the sub-make printed `refusing to run test-memory uninstrumented` |
| C1′ | the clean-run guard disabled, plus H, plus C1 | **exit 0, `gate caught libc-overrun`** |
| E | an empty mode list (`MEMORY_SABOTAGE_MODES=`) | exit 2, `MEMORY_SABOTAGE_MODES is empty; nothing was planted.` |
| E′ | E, with the empty-list guard disabled | **exit 0, `MEMORY GATE CAN FAIL`**, having planted nothing |

- **H needs the exit-status test.** ASan prints the full report, so a
  marker-only check would credit it.
- **C2′ shows the marker test is load-bearing.** Without it, a gate that
  ran no tool at all is credited.
- **C1′ shows the clean-run guard is load-bearing.** Under H, ASan reports
  and exits with the program's own status, so a program that fails by
  itself makes a broken gate look like a working one.
- **E′ is why the check counts its modes.** A loop over nothing reports
  success.

### Linux (aarch64 scratch clone, final recipe)

| # | mutation | store-overrun | libc-overrun | leak | possible-leak | exit |
|---|---|---|---|---|---|---|
| — | control | caught | caught | caught | consistent | 0 |
| M1 | `timeout 900` between `valgrind` and `$(CHEZ)` (chez-libuv's #14 shape) | VACUOUS | VACUOUS | VACUOUS | never counted | 2 |
| M2 | `--error-exitcode=9` dropped | VACUOUS | VACUOUS | VACUOUS | consistent | 2 |
| M3 | `--leak-check=full` dropped | caught | caught | VACUOUS | consistent | 2 |
| M4 | `--errors-for-leak-kinds=possible` | caught | caught | VACUOUS | red without report | 2 |
| M5 | `--errors-for-leak-kinds` deleted (the flags before this change) | caught | caught | caught | red without report | 2 |
| P7 | not a defect: show and fail on `definite,possible` | caught | caught | caught | consistent | 0 |
| C1 | the sabotage program ends with `(exit 3)` | not clean | not clean | not clean | not clean | 2 |
| C2 | an unrelated failure: Valgrind rejects `--bogus-flag` | not on planted | not on planted | not on planted | never counted | 2 |
| C2′ | C2, with the marker test disabled | **caught** | **caught** | **caught** | never counted | 2 |
| C1′ | the clean-run guard disabled, plus M2, plus C1 | **caught** | **caught** | **caught** | red without report | 2 |
| E | an empty mode list (`MEMORY_SABOTAGE_MODES=`) | — | — | — | — | 2, `nothing was planted` |
| E′ | E, with the empty-list guard disabled | — | — | — | — | **0, `MEMORY GATE CAN FAIL`** |

Rows M1, M2, M5 and C2 were rerun on CI's stack (amd64, Chez 9.5.8,
Valgrind 3.22), with the same verdict in every cell.

In C2′ and C1′ the check still exits 2, but only because `possible-leak`
has its own marker test. The three defect modes are credited wrongly in
both, which is what those rows test. M4 leaves the leak's record in the
log while the gate exits 0, so a marker-only check would credit it.

---

## What live ASan sees

docs/building.md states what the macOS arm catches now that it is live.
Each claim was probed with ASan live (`verbosity=1` witness in every run),
3 of 3:

| probe | macOS, ASan live | Linux Valgrind (both stacks) |
|---|---|---|
| `foreign-set!` 1 byte past a 23-byte block | missed (exit 0) | `0 bytes after a block of size 23 alloc'd` |
| `foreign-ref` of a freed 23-byte block | missed (exit 0) | `Invalid read of size 1 … inside a block of size 23 free'd` |
| `memcpy` of 30 bytes into a 29-byte block | `heap-buffer-overflow` (exit 134) | not probed |
| `memset` of 30 bytes into a 29-byte block | `heap-buffer-overflow` (exit 134) | `0 bytes after a block of size 29 alloc'd` |
| double free of a 16-byte block | `attempting double-free` (exit 134) | not probed |

Chez's generated code is not instrumented, so ASan sees only what passes
through libc or the allocator. `c-string->string` reads render buffers
with `foreign-ref`, so a read of a freed buffer is caught by Valgrind alone.
A double free also traps plain macOS malloc (exit 133 with no tool), which
is why it cannot be a sabotage witness: a red gate would not prove the tool
was loaded.

---

## Full runs, both arms live

- **macOS, `make test-memory` (final recipe, no `MallocNanoZone`):** exit 0
  in 8 s, 21 suites, no ASan report. A one-off copy with `verbosity=1`
  printed 21 `AddressSanitizer: libc interceptors initialized` banners for
  21 suites: ASan was in every suite's process, and in none of their
  children. `make test` takes 9 s, so a vacuous run would look the same;
  the banner count is what tells them apart.
- **Linux aarch64, `make CHEZ=scheme test-memory`:** exit 0 in 174 s with
  the flags as they stood, and in 166 s with `--errors-for-leak-kinds=
  definite`. Both times 21 suites and 21 summaries, every `Command:` a
  `scheme --program tests/test-*.sps`, and in each suite `ERROR SUMMARY: 0
  errors` with 0 bytes definitely, indirectly and possibly lost.
- **Linux amd64, CI's stack, `make CHEZ=chezscheme check-memory-gate` then
  `test-memory` (final flags):** the check, on the committed Makefile,
  printed `gate caught` for the three defects, `gate consistent on
  possible-leak` and `MEMORY GATE CAN FAIL` (98 s), and every Valgrind
  client was `chezscheme`. `test-memory` exited 0 in 575 s under emulation
  (its recipe differs from the committed one only in a comment): 21
  suites, every `Command:` a `chezscheme --program …`, 21 `ERROR SUMMARY: 0
  errors`. 11 suites reported 0 bytes definitely, indirectly and possibly
  lost, and the other 10 "All heap blocks were freed".

---

## Not covered

- **`--show-leak-kinds=definite` itself** is a pre-existing decision and
  was not re-mutated. What is covered is that failing and printing agree.
- **The macOS arm has no per-suite time cap,** as before. Any cap added
  there must not sit between `DYLD_INSERT_LIBRARIES` and `chez` (A2).
- **CI's own Valgrind** has not run this branch. The emulated amd64 stack
  above is its package set; if its report wording ever drifts, the check
  fails loudly with "failed, but not on the planted", and cannot pass
  silently.
