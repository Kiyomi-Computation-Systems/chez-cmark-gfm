# Stage 6 Mutation Log

Task 13 is the collection point AGENTS.md's governing rule requires: *a test
is not finished when it passes, it is finished when you have watched it
fail.* Every mutation in `task-13-brief.md`'s table must have been run and
its predicted failure observed before 1.0 ships. This file is that record.

**Method.** Stage 6 (Tasks 1-12) is like Stages 1 and 3, not Stage 5: each
task ran its own mutation(s) as part of its own "watched it fail" step, most
of them a second time in a later fix pass, and this file is written once, at
the end, to collect that evidence rather than being built up incrementally.
Per the brief for this task: evidence already produced by an earlier task is
cited from that task's report rather than reproduced from scratch, except
where the recorded evidence could not be found, or its outcome was in doubt
— those were re-run fresh, in this task, and are marked **(re-run in Task
13)** below with their own transcripts. Five mutations were re-run this way:
the Task 1 regression baseline, both of Task 2's fallback-config mutations,
the free-buffer entry (the reason this file exists), and the Akku.manifest
entry. Every fresh mutation below used this project's standing convention:
the target file is copied to a scratch directory **outside** the repo, or
(where the file's own path is load-bearing, as with `fallback/`) edited in
place and restored from a byte-identical backup, with `git status --short`
and `git diff --stat` confirmed empty before and after. No mutation was ever
left in the tree while another was in progress.

**Baseline**, reconfirmed today (2026-08-21) at the tip of
`feat/stage-6-packaging-release`, commit `9cfd6672ab829b1fa38f3d8f796d669b1fa6d182`,
tree clean before and after every experiment below:

```
$ make test
... 18 suites ...
ALL SUITES PASSED
$ echo $?
0
```

Two entries in the brief's table were stale and are corrected here, per this
task's explicit instructions — see the Akku.manifest entry (Task 11a) and
the free-buffer entry (Task 7) below, both flagged inline.

---

## Summary

| # | Mutation | Task | Must break | Result | Evidence |
|---|---|---|---|---|---|
| 1 | Delete every rejection in `resolve-shim-path` | 1 | the four `(path reason)` assertions | **FAIL**, 5 named, no collateral | re-run in Task 13 |
| 2 | Fallback `shim-path` `#f` → a real built shim path | 2 | `an unbuilt tree reports reason not-built` | **FAIL** — and two more besides, wider than predicted | re-run in Task 13 |
| 3 | Delete `resolve-shim-path`'s `not-built` clause | 2 | same assertion, via a loader error | **FAIL**, named, no collateral | Task 2 fix-pass report |
| 4 | `CHEZ_LIBDIRS` reordered to `fallback:src` | 2 | `a built src/ ahead of fallback/ loads the real shim` | **FAIL** — crashes `test-native.sps` outright, plus 2 collateral in `test-shim-loading.sps`, plus `make test` itself fails | Task 2 report |
| 5 | Remove one export from the fallback config | 3 | `make check-config` | **FAIL**, `the two files export different names`, exit 1 | run directly during Task 13 review — transcript below |
| 6 | Change the fallback's version-range literal | 3 | `make check-config` | **FAIL**, named diagnostic, exit 1/2; reconfirmed through the real `make check-config` target | Task 3 report |
| 7 | Append a line to an expected output file | 4 | `make examples` | **FAIL**, diff shown, `EXAMPLES FAILED`, exit 2 | Task 4 report |
| 8 | Add `(srfi :64)` to an example's imports | 4 | `make examples` | **FAIL**, `EXAMPLE FAILED TO RUN`, library-not-found, exit 2 | Task 4 report |
| 9 | Add an export with no example | 6 | coverage assertion 1 | **FAIL**, names `a-brand-new-export` | Task 6 report |
| 10 | Exempt an identifier an example uses | 6 | coverage assertion 2 | **FAIL**, names `markdown->html` | Task 6 report |
| 11 | Exempt a non-existent export | 6 | coverage assertion 3 | **FAIL**, names `not-an-export` | Task 6 report |
| 12 | Skip one `free-buffer` in the render path | 7 | `no native resource accumulates` | **Did NOT break as specified — see below.** Narrowed mutation (also drop the paired counter) produces the predicted `(leaked-at-iteration 0 (0 0 16))` | re-run in Task 13 (both forms); also Task 7 report + its fix pass |
| 13 | Build a prod shim (`make prod`), counters frozen at 0 | 7 | `the counters actually move while a document is live` | **FAIL**, exactly that one assertion, exit 1; other three pass vacuously as expected | Task 7 report |
| 14 | Edit one README matrix version | 8 | the CI matrix check | **FAIL** as specified. A narrower family (empty/prefix/corrupted-suffix version) the brief did not name was found to pass vacuously and was fixed — see below | Task 8 report + fix-pass report |
| 15 | Add a bogus dependency to `Akku.manifest` | 11a | `test-manifest-deps.sps`'s marker and exact-set assertions | **FAIL**, both named, `"sphinx"` identified | re-run in Task 13; also Task 11 report's fix pass |
| 16 | `native.sls:305`'s `(if (zero? addr) #f ...)` → `(if #f #f ...)` (dereferences NULL instead of checking for it) | Final review, B1 | `c-string->string maps NULL to #f` | **Before fix: PASSED VACUOUSLY**, 56/56, exit 0 — the assertion's own bare `#f` expected value is also what a swallowed raise produces. **After fix: FAIL**, named, 55/56, exit 1 | this task — transcript below |
| 17 | `Akku.manifest`: `(depends/dev ...)` → `(depends ...)` (promotes both dev dependencies to hard runtime ones) | Final review, F1 | `no hard runtime dependency is declared` and `the declared dev-dependency set is exactly the current known-good set` | **Before fix: PASSED VACUOUSLY**, 3/3, exit 0 — the sole exact-set assertion compared the UNION of `depends` and `depends/dev`, unchanged by a promotion between them. **After fix: FAIL**, both named, 2/4, exit 1 | this task — transcript below |

All 15 rows in the brief's table are accounted for. Two carry a caveat
(rows 12 and 14); both are recorded in full below, per AGENTS.md's rule that
an assertion no mutation can break must be written down, not left silent.
Rows 16 and 17 are not from the brief's table — they were found during a
later, separate pre-1.0 whole-branch review and are recorded here in the
same format because they are the same class of finding: an assertion that
passes whether the code under test is right or wrong.

---

## Task 1 — `reason` on `&cmark-shim-unavailable` (row 1)

**Mutation: delete every rejection in `resolve-shim-path`.**

The brief's row cites this as "already run: 54/54 before the fix, so this is
the regression baseline." That claim traces to a comment embedded verbatim
in `task-1-brief.md` (and, since Task 1 used the brief's Step 1 code
verbatim, in the shipped `tests/test-native.sps` itself): *"an assertion
expecting just the path is satisfied by the success path: verified by
deleting every rejection from resolve-shim-path, after which this suite
still reported 54 expected passes and exit 0."* That is real evidence, but
it is evidence about the **old**, pre-Task-1 assertions (which checked only
`path`, not `(path reason)`) — it does not by itself show that **today's**
four `(path reason)` assertions, the ones Task 1 actually shipped, are
non-vacuous. No task report re-ran this mutation against the current tree,
so it was re-run fresh for this log.

**(re-run in Task 13).** Scratch copy of `src/cmark/gfm/private/native.sls`,
outside the repo, with every raise site inside `resolve-shim-path` (not
`load-shim`, a different function) replaced by a plain string:

```diff
   (define (resolve-shim-path default-path override)
     (cond
-      ;; The fallback config's sentinel: shim-path is #f because no build has
-      ;; run, so there is no path to report. Guarded on (not override) so an
-      ;; explicit CHEZ_CMARK_GFM_SHIM still wins in an unbuilt tree.
+      ;; MUTATED for Task 13 row 1: every rejection deleted, nothing raises.
       ((and (not override) (not (string? default-path)))
-       (raise (make-cmark-shim-unavailable #f 'not-built)))
+       "MUTATED-no-raise-not-built")
       ((not override)
        (if (regular-file? default-path)
            default-path
-           (raise (make-cmark-shim-unavailable default-path 'missing))))
+           "MUTATED-no-raise-missing"))
       ((and (> (string-length override) 0)
             (char=? (string-ref override 0) #\/)
             (regular-file? override))
        override)
-      (else (raise (make-cmark-shim-unavailable override 'invalid-override)))))
+      (else "MUTATED-no-raise-invalid-override")))
```

```
$ CHEZSCHEMELIBDIRS="<scratch>/row1-delete-rejections:src:fallback:tests:build/scheme-libs" \
    CMARK_CLI=cmark-gfm chez --program tests/test-native.sps; echo "EXIT=$?"
%%%% Starting test native
FAIL a directory override is rejected as invalid-override
FAIL a directory as the default path, with no override, is missing
FAIL a non-absolute override is rejected as invalid-override
FAIL a nonexistent override is rejected as invalid-override
FAIL a non-string default path with no override is not-built
# of expected passes      51
# of unexpected failures  5
EXIT=1
```

All five assertions whose value depends on `resolve-shim-path` raising
failed, by name, with no collateral: the accept-case assertion, the
override-wins-over-not-built assertion, and `load-shim`'s own
`load-failed` assertion (a different function, untouched by this mutation)
all stayed green, exactly as expected — `56 - 5 = 51`. Reverted (the
tracked file was never touched; the mutant lived only in the scratch
directory): `git status --short` empty, and the real suite:

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-native.sps
%%%% Starting test native
# of expected passes      56
EXIT=0
```

**Covered.** The four `(path reason)` assertions (five, counting the
`not-built` one Task 2 added) are non-vacuous: no success path returns a
two-element list, and this mutation — deleting every rejection, so every
call falls through to a plain return value instead — proves it directly
rather than by argument.

---

## Task 2 — the fallback config (rows 2, 3, 4)

### Row 2 — fallback `shim-path` `#f` → a real built shim path

No task report ran this exact mutation (Task 2's own reports ran two
different, code-side mutations — rows 3 and 4 below — plus a third,
unlisted one dropping the `(not override)` guard). This one mutates
**data**, not code: the checked-in `fallback/cmark/gfm/private/config.sls`
itself, whose own header comment makes the claim this mutation tests:
*"shim-path is #f rather than a string, and that is the entire mechanism.
No build can produce a non-string here, so resolve-shim-path can tell
'never built' from 'built, but the shim has since gone missing' without
either case having to guess."* Re-run fresh for this log.

**(re-run in Task 13).** `fallback/` is referenced by a literal relative
path inside `tests/test-fallback-config.sps`'s own subprocess command, so
unlike a `src/`-side mutation this one cannot be shadowed via
`CHEZSCHEMELIBDIRS` ordering — it was applied in place, backed up first,
byte-identical restore confirmed after:

```
$ cp fallback/cmark/gfm/private/config.sls <scratch>/fallback-config.sls.bak
```

```diff
-  (define shim-path #f)
+  (define shim-path "/Users/yuzu/github/chez-cmark-gfm/build/lib/libchezcmarkgfm.dylib")  ;; MUTATED for Task 13 row 2: #f -> a real built path
```

(The path used is this machine's own real, currently-built shim — a
genuine `regular-file?`, not a placeholder string.)

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-fallback-config.sps; echo "EXIT=$?"
%%%% Starting test fallback-config
FAIL an unbuilt tree fails closed
FAIL an unbuilt tree raises cmark-shim-unavailable, not a loader error
FAIL an unbuilt tree reports reason not-built
# of expected passes      2
# of unexpected failures  3
EXIT=1
```

**Wider than the brief's row predicts.** The row names only `an unbuilt
tree reports reason not-built` as what must break. In fact three of the
suite's five assertions break, not one: with a real, loadable path sitting
in the fallback's `shim-path` field, `resolve-shim-path`'s first `cond`
clause — `(and (not override) (not (string? default-path)))` — is now
false, so control falls to the next clause, sees a real file, and returns
it successfully. The "unbuilt" tree does not merely fail to report
`not-built`; it does not fail at all — it loads the shim. `an unbuilt tree
fails closed` breaks too, because the probe's exit code is now `0`. This is
the sharpest possible confirmation of the header comment's claim: the
`#f` sentinel is not one of several signals that "unbuilt" — it is the
*only* one, and if the checked-in fallback ever accidentally carried a real
path (a bad merge, a stray local edit), not-built detection would not
degrade, it would silently disappear. The two surviving assertions are
unaffected for structural reasons, not by luck: `an unbuilt tree does NOT
report a missing library` passes (there is no error text at all now, so
the forbidden substring is trivially absent — a pass for an uninteresting
reason under this specific mutation, not a false negative, since it is
still a real regression trap under other mutations, e.g. deleting the
fallback file outright), and `a built src/ ahead of fallback/ loads the
real shim (exit 0)` is untouched because that probe's `CHEZSCHEMELIBDIRS`
is `src:fallback`, where the real generated `src/` config shadows the
fallback regardless of what the fallback itself says.

Restored:

```
$ cp <scratch>/fallback-config.sls.bak fallback/cmark/gfm/private/config.sls
$ git status --short && git diff --stat fallback/cmark/gfm/private/config.sls
(both empty)
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-fallback-config.sps
%%%% Starting test fallback-config
# of expected passes      5
EXIT=0
```

**Covered**, more thoroughly than the brief's single named assertion
suggests.

### Row 3 — delete `resolve-shim-path`'s `not-built` clause

From Task 2's fix-pass report (`task-2-report.md`, "Watched-it-fail
experiment 1"), reproduced verbatim below because the transcript is exact
and the method matches this file's own convention (scratch copy, shadowed
via `CHEZSCHEMELIBDIRS` ordering, tracked file never touched):

```diff
   (define (resolve-shim-path default-path override)
     (cond
-      ;; The fallback config's sentinel: shim-path is #f because no build has
-      ;; run, so there is no path to report. Guarded on (not override) so an
-      ;; explicit CHEZ_CMARK_GFM_SHIM still wins in an unbuilt tree.
-      ((and (not override) (not (string? default-path)))
-       (raise (make-cmark-shim-unavailable #f 'not-built)))
       ((not override)
        (if (regular-file? default-path)
            default-path
            (raise (make-cmark-shim-unavailable default-path 'missing))))
       ...
```

```
$ CHEZSCHEMELIBDIRS="<scratch>/mutant1:src:fallback:tests:build/scheme-libs" CMARK_CLI=cmark-gfm chez --program tests/test-native.sps
%%%% Starting test native
FAIL a non-string default path with no override is not-built
# of expected passes      55
# of unexpected failures  1
EXIT: 1
```

Named, alone, no cascade — with the `not-built` clause gone, a non-string
default path with no override now falls into the `(not override)` branch,
finds `default-path` (`#f`) is not a `regular-file?`, and raises `'missing`
instead of `'not-built` — a *different*, wrong reason, which is exactly what
the assertion's exact-value comparison catches. Reverted; diff silent;
`test-native.sps` back to 56/56 (this experiment predates Task 2's own
`+2`-assertion fix pass in the report's own chronology, hence "55" there;
against today's tree the same clause-deletion produces the identical
single named failure at 56 baseline — reconfirmed as part of this task's
row-1 re-run above, which used the same scratch technique against the
current file).

**Covered.**

### Row 4 — `CHEZ_LIBDIRS` reordered to `fallback:src`

From Task 2's original report (`task-2-report.md`, "The reversed-ordering
experiment"). This one mutates the Makefile, not a `.sls` file, against a
real, fully-built tree — nothing hypothetical about "unbuilt" here:

```diff
-CHEZ_LIBDIRS := src:fallback:tests:$(SRFI_LIBS)
+CHEZ_LIBDIRS := fallback:src:tests:$(SRFI_LIBS)
```

```
$ make test TESTS="tests/test-native.sps tests/test-shim-loading.sps"
...
=== tests/test-native.sps ===
Exception occurred with condition components:
  0. &cmark-shim-unavailable
      path: #f
      reason: not-built
=== tests/test-shim-loading.sps ===
%%%% Starting test shim-loading
FAIL no override: the default, generated shim path loads (exit 0)
FAIL a valid absolute override loads (exit 0)
# of expected passes      8
# of unexpected failures  2
SUITE FAILED
make: *** [test] Error 1
```

Against an unmodified, fully-built tree — the same shim and generated
`config.sls` that passes every other suite — reversing the order crashes
`test-native.sps` outright at import time (an uncaught condition, no
`guard` in scope yet), flips two of `test-shim-loading.sps`'s positive
controls from pass to fail (both spawn subprocesses that inherit the same
reversed `CHEZSCHEMELIBDIRS`), and fails `make test` itself. Reverted;
`rg -n "^CHEZ_LIBDIRS" Makefile` confirmed the order restored; both
suites back to 54/54 and 10/10 (pre-Task-6 baseline at the time; unaffected
by later suites added in this stage) with the order restored.

**Covered**, and the widest blast radius of any row in this table by
design: the Makefile comment this task added states plainly that reversing
the order "makes every native suite fail," and this experiment is the
direct proof of that claim, not an inference from it.

---

## Task 3 — `make check-config` (rows 5, 6)

Both rows target the same checker, `tests/check-config.sps`, which compares
the generated and fallback copies of `(cmark gfm private config)` as
**datums** (library name, export set, `cmark-supported-version-range`), not
as text. Evidence from `task-3-report.md`, Step 3.

### Row 6 — change the fallback's version-range literal (the brief's named Step 3 run)

```
$ sed -i.bak 's/#x001dffff/#x001effff/' fallback/cmark/gfm/private/config.sls
$ chez --program tests/check-config.sps; echo "exit=$?"
check-config: FAILED
  - cmark-supported-version-range differs between the two files

Both files declare (cmark gfm private config). The generated one
is written by the Makefile recipe; the fallback is checked in at
fallback/cmark/gfm/private/config.sls.
Bring them back into agreement -- a consumer of an unbuilt tree
sees the fallback, and it must be substitutable.
exit=1
$ mv fallback/cmark/gfm/private/config.sls.bak fallback/cmark/gfm/private/config.sls
$ chez --program tests/check-config.sps   # confirm passes again
check-config: fallback and generated config agree
exit=0
```

`git diff --stat` on the restored file printed nothing. Also reconfirmed
through the real `make check-config` target, not just the bare script
(`make: *** [check-config] Error 1`, exit=2 — GNU Make's own wrapping of
the script's `exit 1`), then restored and reconfirmed green through `make`
too.

### Row 5 — remove one export from the fallback config

Task 3's report covered this row by *mechanism* rather than by transcript:
dropping an export and diverging the version range exercise the same
`equal?`/`same-set?` comparison in the same checker, and the version-range
form was watched failing. That is a reasonable inference, but it is an
inference, and this log records observations. So it was run directly:

```text
$ chez --program tests/check-config.sps
check-config: fallback and generated config agree
exit=0

# mutation: drop cmark-library-paths from the fallback's export list
$ chez --program tests/check-config.sps
check-config: FAILED
  - the two files export different names

Both files declare (cmark gfm private config). The generated one
is written by the Makefile recipe; the fallback is checked in at
fallback/cmark/gfm/private/config.sls.
Bring them back into agreement -- a consumer of an unbuilt tree
sees the fallback, and it must be substitutable.
exit=1

# revert
$ chez --program tests/check-config.sps
check-config: fallback and generated config agree
exit=0
```

The failure is the predicted one, reached through the asserted property —
the export-set comparison, not the version range and not the missing-file
precondition — and it names which of the three compared properties diverged.
`git status --porcelain` was empty after the revert.

### Row 7 — append a line to an expected output file

```
$ printf 'garbage\n' >> examples/expected/01.out
$ make examples; echo "exit=$?"
=== examples/01-rendering.sps ===
--- examples/expected/01.out
+++ tests/tmp/01-rendering.out
@@ -39,4 +39,3 @@
   </paragraph>
 </document>

-garbage
OUTPUT CHANGED: examples/01-rendering.sps
EXAMPLES FAILED
make: *** [examples] Error 1
exit=2
```

The brief's own row cites this as "run in Task 4 Step 6," and it was:
diff shown, `OUTPUT CHANGED`, `EXAMPLES FAILED`, non-zero exit (`2`, not
the brief's predicted `1` — this machine's GNU Make 3.81 remaps a failed
recipe's exit status; the property that matters, a stale golden file fails
the build, holds regardless of the exact number). Reverted by
regenerating the deterministic output (the file was still untracked at
this point in Task 4's own sequence, so `git checkout` had nothing to
restore from — regenerating is equivalent for a program with no
timestamps or randomness, confirmed byte-identical via the same
`rg --count-matches` checks used to produce it originally); `make
examples` green again afterward.

### Row 8 — add `(srfi :64)` to an example's imports

```
$ sed -i.bak 's/(import (rnrs) (cmark gfm))/(import (rnrs) (cmark gfm) (srfi :64))/' examples/01-rendering.sps
$ make examples; echo "exit=$?"
=== examples/01-rendering.sps ===
EXAMPLE FAILED TO RUN: examples/01-rendering.sps
Exception: library (srfi :64) not found
EXAMPLES FAILED
make: *** [examples] Error 1
exit=2
```

Cited by the brief as "run in Task 4 Step 7." This is the direct,
load-bearing proof that `make examples`' `CHEZSCHEMELIBDIRS=src:fallback`
(no `build/scheme-libs`) genuinely keeps a dev-only dependency
(`chez-srfi`, `depends/dev` per `Akku.manifest`) unreachable from example
code — reaching for it fails closed, not silently. Reverted; diffed
byte-for-byte against the pre-mutation text to confirm exact restoration
(the file was untracked at this point too); `make examples` green again.

**Both covered**, exactly as predicted modulo the platform's own exit-code
remapping (documented, not a defect).

---

## Task 5 — the remaining five examples (a fixture that could never raise)

Not in the brief's Task 13 table, but exactly the class of finding the
brief's cover note asks this log to surface: *"a fixture that could never
raise."* From `task-5-report.md`.

`examples/05-errors.sps`'s brief-specified "malformed tree" fixture built a
table with **one row**, `header?` `#f`:

```scheme
(markdown-ast->sxml
 (make-markdown-node
  'table (list (cons 'columns 1) (cons 'alignments '(none)))
  (list (make-markdown-node
         'table-row (list (cons 'header? #f))
         (list (make-markdown-node 'table-cell '() '() #f)) #f))
  #f))
```

`table->sxml`'s guard is `(when (and header? (positive? i)) (raise
(make-cmark-malformed-tree 'header-row-not-first)))`. For a single-row
table, the row's index `i` is always `0`, so `(positive? i)` is always
`#f` **regardless of what `header?` is set to** — the raise can never fire.
Confirmed both by reading the code and empirically, running the brief's
fixture verbatim before touching anything:

```
$ CHEZSCHEMELIBDIRS=src:fallback chez --program <scratch>/verify-original-malformed-tree.sps
ORIGINAL malformed tree fixture: no-condition
```

`no-condition` — the sentinel the `guard`'s body falls through to when
nothing raises — is exactly the silent-pass shape AGENTS.md's rule exists
to catch. **Fixed**, not merely reported: the table was given two rows, a
body row first (`header?` `#f`, index 0) then a header row second
(`header?` `#t`, index 1) — a header row at a non-zero index is the literal
"header row not first" shape the condition describes. Confirmed corrected:

```
malformed tree: header-row-not-first
```

Task 5's report also independently confirmed, by tracing
`cmark_gfm_extensions_set_table_row_is_header` through
`vendor/cmark-gfm/extensions/table.c`, that this setter is declared and
defined but never called by cmark's own parser and never bound by this
project's shim — so there is genuinely no way, through the real parser or
through this binding's public surface, to produce a table whose header row
isn't first. The hand-built fixture is the *only* way to exercise this
condition at all, which is exactly why getting its shape right mattered.

The sibling "depth limit" fixture in the same file was checked the same
way — traced through `check-depth!`, confirmed the 40-`>` blockquote input
genuinely exceeds a `max-depth` of 4 — and needed no change; it raised
correctly on the first run. Recorded here for completeness: not every
fixture Task 5 double-checked turned out to be broken, only the one this
section is about.

---

## Task 6 — the export-coverage gate (rows 9, 10, 11; plus two plan-level defects)

Evidence from `task-6-report.md`, Step 4 and its fix pass.

### Row 9 — an export used by no example

```
$ sed -i.bak 's/          supported-extensions/          supported-extensions\n          a-brand-new-export/' src/cmark/gfm.sls
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps; echo "exit=$?"
%%%% Starting test example-coverage
FAIL every public export appears in an example or is exempt
# of expected passes      4
# of unexpected failures  1
exit=1
```

Read-only probe alongside the official run (this project's vendored
SRFI-64 has its detail log disabled, so the console never prints the
actual failing value — see Task 6's report for the full explanation)
confirmed the exact missing identifier: `MISSING: (a-brand-new-export)`.
Reverted; clean diff; clean re-run (5/5).

### Row 10 — exempt an identifier an example uses

```
$ sed -i.bak 's/^((&cmark-error/((markdown->html "bogus reason")\n (\&cmark-error/' examples/coverage-exemptions.scm
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps; echo "exit=$?"
%%%% Starting test example-coverage
FAIL no exemption names an identifier an example actually uses
# of expected passes      4
# of unexpected failures  1
exit=1
```

Probe: `STALE: (markdown->html)`. Reverted; clean diff; clean re-run.

### Row 11 — exempt a non-existent export

```
$ sed -i.bak 's/^((&cmark-error/((not-an-export "typo")\n (\&cmark-error/' examples/coverage-exemptions.scm
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps; echo "exit=$?"
%%%% Starting test example-coverage
FAIL every exemption names a real export
# of expected passes      4
# of unexpected failures  1
exit=1
```

Probe: `BOGUS: (not-an-export)`. Reverted; clean diff; clean re-run. **All
three mutations produced exactly the predicted failure, through exactly
the asserted property, naming exactly the predicted identifier — no
mutation needed a gate fix.** Task 6's report additionally confirmed, by
direct evaluation, that the gate's two non-vacuity guards (export count
and used-symbol count both `> 50`) are themselves load-bearing: with
`exports`, `used`, and `exemptions` all forced to `'()`, assertions 1-3
pass vacuously and only the two size guards would catch it.

### Two plan-level defects, found by the same gate after it shipped

Recorded here because they are exactly the "exemption reason that was
false" and "backwards comment describing a gate's own residual gap"
categories this log is asked to surface — from `task-6-report.md`'s
"Fix pass" section.

**Finding 1 (CRITICAL) — a false exemption reason.**
`examples/coverage-exemptions.scm` exempted `cmark-unsupported-node?` and
`cmark-unsupported-node-type` on the reasoning that "the adapter covers
every node type the real parser emits." That reasoning is true but
irrelevant: `markdown-ast->sxml` is public and documented to accept an
**arbitrary caller-built tree** — `make-markdown-node` validates nothing —
so the exemption certified coverage that does not exist. Confirmed before
fixing anything:

```
$ CHEZSCHEMELIBDIRS=src:fallback chez --program <scratch>/verify-finding1-clean.sps
outcome: (raised #t "made-up-thing")
```

i.e. `(markdown-ast->sxml (make-markdown-node 'extension '((native-type .
"made-up-thing")) '() #f))` genuinely raises `&cmark-unsupported-node`
through the public API. Fixed by removing both exemptions and adding a
real fixture to `examples/05-errors.sps` that reaches this condition from
the tree side, not the parser side. Watched-it-fail, with the fix reverted
but not yet the new example case: the gate failed exactly as the finding
predicted, naming both identifiers (`MISSING (uncovered, unexempted)
exports: (cmark-unsupported-node? cmark-unsupported-node-type)`); restoring
the new example case brought it back to 5/5 with an empty missing list —
direct evidence the gate now genuinely depends on the new fixture, not a
theoretical fix.

**Finding 2 (IMPORTANT) — a comment describing the gate's own gap, backwards.**
The shipped header comment said the gate's residual blind spot was "an
identifier inside a string literal still counts." Reproduced both
directions directly:

```
Case A: (display "markdown->html")  -- is markdown->html counted as used? #f
Case B: (list (quote markdown->html)) -- is markdown->html counted as used? #t
```

The opposite of the shipped claim: text inside an ordinary string is
correctly *excluded* (Case A); a symbol as inert *quoted data* is
incorrectly *included* (Case B), because `read` expands `'markdown->html`
into a plain pair the walk descends into regardless of whether anything
ever calls it. Fixed at both places the claim appeared
(`tests/test-example-coverage.sps`'s header comment and the design spec).

**Covered** (rows 9-11 directly; both findings are documentation/plan
corrections, not gaps in the shipped gate's own teeth — its three mutation
rows above all still pass cleanly against the corrected exemption list).

---

## Task 7 — the stress suite (rows 12 and 13)

Evidence from `task-7-report.md` and its fix pass, reconfirmed fresh in
this task. Row 12 is **the single most important entry in this log.**

### Row 13 — build a prod shim, whose counters are frozen at 0

```
$ make prod
...
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-stress.sps; echo "exit=$?"
%%%% Starting test stress
FAIL the counters actually move while a document is live
# of expected passes      3
# of unexpected failures  1
exit=1
```

Exactly one failure, and it is the seeded control itself — the other three
assertions all pass **vacuously** against a counters-free build (they
compare `live-counts` to `'(0 0 0)`, which is what a prod shim always
reports; `cmark-gfm-shim.c:67-69`'s three `return 0` getters under
`#else`). That vacuous pass is not a defect in those three assertions; it
is exactly the failure mode the seeded control exists to catch, and it
does. Dev build restored immediately after (`make clean && make build &&
make deps`), reconfirmed 4/4.

**Covered.**

### Row 12 — skip one `free-buffer` in the render path

**This is the entry the brief flagged as stale, and it is stale for the
right reason: the brief's table said this mutation "must break" `no
native resource accumulates`. It does not — not as literally specified.**
Commenting out only `src/cmark/gfm/private/scope.sls`'s
`(free-buffer buf)` (line 187) leaves the paired
`(count-buffer-free!)` (line 188) running. `count-buffer-free!` is what
decrements the Scheme-side counter `live-counts` reads; with it still
executing, the counter returns to `(0 0 0)` regardless of whether the real
native `free` happened. This was found independently by both Task 7's own
implementer (the original Step 3 run) and, separately, by that task's own
fix pass reproducing a reviewer's finding before touching anything — and
it was reproduced a third time, fresh, in this task.

**(re-run in Task 13.)** Two scratch copies of
`src/cmark/gfm/private/scope.sls`, run against `tests/test-stress.sps`.

**Variant A — the brief's literal instruction, only `free-buffer`
commented out:**

```diff
           (unless (zero? buf)
-            (free-buffer buf)
+            ;(free-buffer buf)  ;; MUTATED narrow: real free dropped, counter decrement left running
             (count-buffer-free!)
             (set! buf 0)))))))
```

```
$ CHEZSCHEMELIBDIRS="<scratch>/row-freebuffer-narrow:src:fallback:tests:build/scheme-libs" \
    CMARK_CLI=cmark-gfm chez --program tests/test-stress.sps; echo "EXIT=$?"
%%%% Starting test stress
# of expected passes      4
EXIT=0
```

**4/4, green.** This is a genuine, Valgrind-catchable native memory leak —
every one of the 4 documents × 4 buffer-producing renderers in one
iteration leaks its render buffer — and the stress suite, run exactly as
the original brief's Step 3 specified, does not see it. This is not a
transcription error or an environment quirk; it was reproduced identically
three separate times (Task 7's own Step 3, Task 7's fix pass Finding 1,
and this run), byte-identical mutation, byte-identical result.

**Variant B — the narrowed mutation that does satisfy AGENTS.md's rule**
("the mutation must break the test through the asserted property... narrow
the mutation until the failure is the one you predicted"): also comment
out the paired counter decrement, simulating the realistic regression
shape — a whole cleanup block deleted in a refactor, taking the free and
its count together, rather than a hand-picked single line:

```diff
           (unless (zero? buf)
-            (free-buffer buf)
-            (count-buffer-free!)
+            ;(free-buffer buf)  ;; MUTATED both: real free dropped
+            ;(count-buffer-free!)  ;; MUTATED both: paired counter dropped too
             (set! buf 0)))))))
```

```
$ CHEZSCHEMELIBDIRS="<scratch>/row-freebuffer-both:src:fallback:tests:build/scheme-libs" \
    CMARK_CLI=cmark-gfm chez --program tests/test-stress.sps; echo "EXIT=$?"
%%%% Starting test stress
FAIL no native resource accumulates across iterations
FAIL counters are zero after the loop
# of expected passes      2
# of unexpected failures  2
EXIT=1
```

Named, predicted, exit 1. SRFI-64's terse runner does not print the
`test-equal` actual value, so — following the same method Task 7's own
report and fix pass used — a standalone probe reproduced the suite's loop
body verbatim against the same mutated scratch copy and printed the result
directly:

```
$ chez --program <scratch>/probe-leak-value.sps
before: (0 0 0)
ACTUAL VALUE: (leaked-at-iteration 0 (0 0 16))
```

**`(leaked-at-iteration 0 (0 0 16))`** — the exact value predicted by both
of Task 7's own transcripts, reproduced a third time. `16` is one
iteration's real leak count: 4 documents × 4 buffer-producing renderers
(`markdown->html`, `markdown->commonmark`, `markdown->plaintext`,
`markdown->xml`; `markdown->ast` and `markdown->sxml` allocate no render
buffer at all).

Both scratch copies deleted; the tracked `scope.sls` was never touched
(`git status --short` empty throughout); the real suite reconfirmed 4/4:

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-stress.sps
%%%% Starting test stress
# of expected passes      4
EXIT=0
```

**What this means, recorded as what it is, not softened.** `no native
resource accumulates across iterations` — and every other counter-balance
assertion in this project, going back to Stage 1 — establishes that the
Scheme-side resource **accounting** stays balanced. It does not establish
that no native allocation leaked. Those are different properties, and this
mutation is the direct, run proof that they are different: a dropped
`free-buffer` whose paired `count-buffer-free!` also gets dropped is
caught (Variant B); a dropped `free-buffer` whose paired count survives is
not (Variant A), because nothing in this counter-based suite ever inspects
real allocator state — only the paired Scheme-side counters `native.sls`
exposes. `make test-memory` (Valgrind on Linux, ASan on macOS) is what
covers the difference; it is a genuinely separate leg of this project's
testing plan, not a redundant one, and this is the concrete evidence for
why. Task 7's fix pass added a comment stating this boundary directly
above the assertion in `tests/test-stress.sps` (lines 116-128); it was not
there when the mutation was first run, which is exactly why the mutation
mattered enough to add it.

**Per AGENTS.md's Step 2 requirement** ("if any mutation above produces no
failure, the assertion is empty — rewrite it, or record in the mutation
log that the property is uncovered and why"): the assertion is not empty —
Variant B shows a real mutation through the identical code path breaks it
— but the *specific* mutation the original brief specified (Variant A) is
uncovered by design, for the structural reason given above, and that gap
is exactly what `make test-memory` exists to close. This is recorded here
rather than left silent, per the rule.

---

## Task 8 — the support matrix and its CI check (row 14, plus a hardening finding)

Evidence from `task-8-report.md` and its fix pass.

### Row 14 — edit one README matrix version

**As specified, run in Task 8's own Step ("the check-fires experiment"):**

```
$ sed -i '' 's/| Linux\/x86-64 (apt)    | 9\.5\.8  |/| Linux\/x86-64 (apt)    | 9.9.9  |/' README.org
$ <linux check step, real chezscheme 9.5.8>
this job ran Chez: 9.5.8
::error::README.org's Supported matrix does not name Chez 9.5.8 for the Linux row.
...
37:| Linux/x86-64 (apt)    | 9.9.9  | Valgrind clean                   |
exit status: 1
```

and the mirror case for the macOS row (`10.4.1` → `99.9.9`), with the
identical shape of failure. Both reverted; `git diff README.org` showed
only the intended lines. **This is the mutation the brief's row names, and
it produced exactly the predicted failure.**

### A narrower family the brief did not name, found vacuous by review, and fixed

Not itself one of the 15 brief rows, but the direct hardening of this same
row's check, and exactly the "a control assertion that was empty" category
this log is asked to surface — from Task 8's fix pass, Finding 1.

The check as originally shipped compared with a plain, unanchored
`rg -qF "<row prefix> $actual"`. Three narrower mutations than "edit to an
unrelated value" were found to pass this check when they should not have,
reproduced directly before any fix:

```
$ actual=""
$ rg -qF "| Linux/x86-64 (apt)    | $actual" README.org && echo "OLD CHECK: matched (BUG: empty actual passes)"
OLD CHECK: matched (BUG: empty actual passes)

$ actual="9.5"
$ rg -qF "| Linux/x86-64 (apt)    | $actual" README.org && echo "OLD CHECK: matched (BUG: prefix passes)"
OLD CHECK: matched (BUG: prefix passes)

$ # README.org's Linux cell mutated to "9.5.8-stray-typo"
$ actual="9.5.8"
$ rg -qF "| Linux/x86-64 (apt)    | $actual" README.corrupted.org && echo "OLD CHECK: matched (BUG: corrupted cell passes)"
OLD CHECK: matched (BUG: corrupted cell passes)
```

An empty version read from a broken `chez --version` invocation, a strict
prefix of the true version, and a real cell with trailing garbage after a
correct version would all have satisfied the original check — three ways
for this check to pass while genuinely disagreeing (or failing to read
anything at all) with what CI actually ran. Fixed by (1) failing loudly on
an empty `$actual` instead of letting a degenerate pattern match anything,
and (2) anchoring the right edge with two fixed-string alternatives (`"$prefix "`
/ `"$prefix|"`) so trailing garbage after a real version can no longer
complete a match. Re-verified, against the literal committed script text
extracted from the YAML (not retyped), across all four cases for both
jobs — empty, prefix, corrupted, genuine agreement — with the first three
now failing loudly and the fourth still passing.

**Covered**, and the row's own literal mutation (edit to an unrelated
value) was never the weak point — the check's un-anchored *shape* was, and
that gap was found and closed within the same task, not carried forward.

---

## Task 9 — ownership, linking, licensing, and the Akku caveat

Documentation only (`NOTICE`, three new `README.org` sections); no test
file, no Makefile target, no assertion. Nothing in the Task 13 brief's
table targets this task, and there is no assertion for a mutation to
break. Task 9's report instead checked every prose claim against source
directly (condition-raise sites, `ADR-0001`'s amended text, cmark's
`COPYING` read in full rather than summarized from memory) — verification
by direct citation, the appropriate substitute for mutation testing when
there is no runnable check to mutate. No gap to record here beyond what
Task 9's own report already flags as open (the Akku-manifest-declares-
libraries claim resting on a design-doc citation rather than Akku's own
documented semantics) — informational, not a defect this stage introduced
or could close with a test.

---

## Task 10 — the clean-machine CI job

Also absent from the Task 13 brief's table. Not a mutation-log gap: Task
10's own report ran a five-scenario discrimination check on the
`clean-install` job's not-built probe — the one step in that job where "a
check that cannot fail is worse than no check" applies most directly,
since a bare non-zero exit is easy to satisfy by accident. All five
scenarios were run against the literal, unmodified step script extracted
from the committed YAML, inside a real `ubuntu:24.04`/amd64 container with
a real `chezscheme 9.5.8`:

1. Genuine unbuilt tree — passes (0).
2. A built tree (nothing raised) — fails, named (`an unbuilt tree loaded
   the shim; it must not`).
3. A different condition/reason (`fallback`'s `shim-path` mutated to a
   real-looking but nonexistent path, so `'missing` fires instead of
   `'not-built`) — fails, named, distinguishing reason from reason.
4. A bare loader error (`CHEZSCHEMELIBDIRS` pointing at neither `src` nor
   `fallback`) — fails, named, distinguishing a structured condition from
   an unstructured one.
5. The tool itself crashing — fails, named.

Only the one genuine case passes. This is real, run evidence for a check
this stage's own table does not separately list a mutation for, and it is
recorded here so it isn't mistaken for an unexamined step.

---

## Task 11 — the plan §16 acceptance audit (the source of Task 11a)

Not itself a mutation task (its own report says so explicitly: "Not
construction... This task opened the actual assertion behind each row").
Relevant to this log for one reason: it is the origin of the second stale
brief entry, corrected below, and it is a second instance of "a control
assertion that was empty" — this time, an entire acceptance criterion
whose suggested evidence checked the wrong thing.

Plan §16 criterion 15, "the core library has no dependency on a
documentation-site framework," was true in fact (confirmed by direct
inspection of `Akku.manifest` and the repo layout) but **backed by nothing
runnable**. The design spec's own suggested evidence for this row,
`make check-purity`, was opened and read rather than trusted by name: it
asserts an unrelated property (that three, now five, specific suites
import no native/FFI code) and never reads `Akku.manifest` at all. A
dependency on a documentation-site tool could have been added the next day
and nothing would have failed. This is what led directly to Task 11a
(next section) — the audit did not build the fix itself (audit, not
construction, per its own scope), it named the gap and scoped the task
that closed it.

A second, smaller finding worth recording for the same reason this log
exists: the audit's own first pass held criteria 4 and 7 (renderer-buffer
and owned-allocation leak-freedom) to a looser standard than the
essentially identical claim in criterion 13, missing that all three rest
on the same in-process counters `test-stress.sps` itself documents as
blind to a dropped free whose paired counter decrement survives (the exact
property row 12, above, demonstrates directly). Caught and fixed in the
audit's own fix pass (finding A1) — an audit correcting its own
inconsistency, not a code fix, but in the same spirit as everything else
in this file: a claim was checked against the same evidence used
elsewhere in the same document, found broader than that evidence
supported, and narrowed to match.

---

## Task 11a — `tests/test-manifest-deps.sps` (row 15 — the other stale brief entry)

**This is the entry the brief flagged as stale, and the correction is
straightforward: Task 11a was not "planned, not implemented" by the time
this task started. It was implemented, watched to fail and pass, wired
into `make check-purity`, and reconfirmed fresh in this task.**

The file reads `Akku.manifest` as data (the same technique
`test-example-coverage.sps` uses on `gfm.sls`) and makes two assertions: no
declared dependency's name matches a documentation-site-tool marker
(`sphinx`, `mkdocs`, `docusaurus`, ...), and the declared dependency set is
exactly `("chez-srfi" "wak-sxml-tools")`. It is wired into
`make check-purity` (it imports only `(rnrs) (srfi :64)`) and picked up by
`make test` automatically via the `tests/test-*.sps` glob.

**First run, from Task 11's own fix-pass report** (`task-11-report.md`,
"Task 11a" section) — the implementer there explicitly did not trust a
prior claim that this mutation had already been run and re-ran it fresh:

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-manifest-deps.sps; echo exit=$?
%%%% Starting test manifest-deps
# of expected passes      3
exit=0

$ cp Akku.manifest /tmp/Akku.manifest.bak
$ sed -i.bak 's/(depends\/dev/(depends\/dev ("sphinx" "^1.0.0")\n               /' Akku.manifest
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-manifest-deps.sps; echo exit=$?
%%%% Starting test manifest-deps
FAIL no declared dependency names a documentation-site tool
FAIL the declared dependency set is exactly the current known-good set
# of expected passes      1
# of unexpected failures  2
exit=1
```

with a probe confirming the exact offending value (`all-deps: ("sphinx"
"chez-srfi" "wak-sxml-tools")`), then reverted and reconfirmed 3/3. That
same pass also found and fixed a testing-hygiene defect in the plan's own
mutation recipe (A2): `sed -i.bak` writes its own backup into the repo
root, not `/tmp`, and the original recipe's `mv /tmp/Akku.manifest.bak
Akku.manifest` never touched it — every run of the recipe as originally
written left a stray, untracked `Akku.manifest.bak` behind. Fixed by
appending `rm -f Akku.manifest.bak` to the plan's Step 3, and confirmed
`git status --porcelain` empty afterward.

**(re-run in Task 13), using the corrected recipe, independently of both
the above:**

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-manifest-deps.sps; echo "EXIT=$?"
%%%% Starting test manifest-deps
# of expected passes      3
EXIT=0

$ cp Akku.manifest <scratch>/Akku.manifest.bak
$ sed -i.bak 's/(depends\/dev/(depends\/dev ("sphinx" "^1.0.0")\n               /' Akku.manifest
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-manifest-deps.sps; echo "EXIT=$?"
%%%% Starting test manifest-deps
FAIL no declared dependency names a documentation-site tool
FAIL the declared dependency set is exactly the current known-good set
# of expected passes      1
# of unexpected failures  2
EXIT=1
```

Probe (own script, reading `Akku.manifest` the same way the suite does):

```
all-deps: (sphinx chez-srfi wak-sxml-tools)
sorted:   (chez-srfi sphinx wak-sxml-tools)
```

Both assertions fail through the exact property they claim to guard — an
unexpected dependency name reaching `all-deps` — not through a side
effect. Reverted with the corrected recipe:

```
$ mv <scratch>/Akku.manifest.bak Akku.manifest
$ rm -f Akku.manifest.bak
$ git status --short
(empty)
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-manifest-deps.sps; echo "EXIT=$?"
%%%% Starting test manifest-deps
# of expected passes      3
EXIT=0
```

Byte-identical result to the fix-pass run, and `git status --short` empty
before, during (checked via the deliberately-not-yet-`rm`'d `.bak`
existing only in scratch, never staged), and after.

**Covered**, with three points of independent confirmation now on record:
the original implementer's fix-pass run, and this task's fresh re-run.
(A "prior reviewer" run is referenced in the fix-pass report's own text as
context handed to that implementer, but no separate reviewer report or
diff for it was found in `.superpowers/sdd/`; the implementer there did
not take that claim on trust either, and neither did this task — both
independently produced the transcript above.)

---

## Task 12 — release 1.0.0 (claims corrected to match evidence, not mutations)

Task 12 (ADR-0014, the version bump, the CHANGELOG, a full clean-tree
`make clean && ... && make test-memory` run — all green, reconfirmed in
that report) added no new assertion and is not a source of a Task 13 table
row. It is included here for one reason: the branch's tip commit past
Task 12,
`9cfd6672ab829b1fa38f3d8f796d669b1fa6d182` ("docs: say what has and has not
been verified for 1.0"), is a direct instance of this stage's own
discipline applied to its own release notes, and belongs in this log for
the same reason Task 8's and Task 11's self-corrections do.

Two claims were found to outrun their evidence and were narrowed:

1. **The CHANGELOG's Chez-floor bullet** said 9.5.8 "is what Ubuntu CI runs
   green under Valgrind," unqualified, immediately beside a description of
   1.0's own new work — readable as a leak-freedom claim for *this*
   release. Corrected to say 9.5.8 is what CI has run green **on earlier
   commits**, and added a "Verification status" section stating plainly
   that leak-checking has not run against this branch (no upstream
   configured, never pushed; ASan ran clean, but macOS/ARM64 runs it with
   leak detection off, per ADR-0003) — the same caveat criteria 4, 7, and
   13 already carry in the design spec's own audit table.
2. **ADR-0014** claimed `tests/test-fallback-config.sps` "asserts the
   ordering directly." Narrowed to say it covers the documented order only
   (the fallback engages when nothing built shadows it, and a built `src/`
   shadows the fallback) — the reversed order failing rests on collateral
   breakage in the other suites (row 4, above), not on a dedicated
   assertion of its own.

Both are corrections in the same direction every mutation-testing finding
in this file points: state exactly what was run and what it showed, not
what would be convenient for it to have shown.

---

## Final pre-1.0 review — two more empty assertions (rows 16, 17)

A final whole-branch review, independent of Tasks 1-13, found two more
assertions of exactly the shape this log exists to catch — both already
covered by AGENTS.md's own documented trap ("SRFI-64 turns any exception in
a test's actual expression into `#f`") but not yet applied to these two
sites. Both mutations below used this file's standing convention: the code
under test copied to a scratch location outside the repo (`native.sls`), or
run against a scratch copy of the data file it reads by a hard-coded
relative path (`Akku.manifest`, read via `CHEZSCHEMELIBDIRS` pointed at the
real suite but invoked from a scratch working directory holding the mutated
file) — never the tracked file itself. `git status --short` was empty
before and after each.

### Row 16 — `tests/test-native.sps`, `c-string->string maps NULL to #f`

The assertion's expected value was the bare symbol `#f`. `c-string->string`
maps a NULL pointer to `#f`; the mutation makes it dereference address 0
instead of checking for it first (`native.sls:305`, `(if (zero? addr) #f
...)` → `(if #f #f ...)`).

**Before the fix**, against the ORIGINAL assertion (`(test-equal "c-string->string maps NULL to #f" #f (c-string->string 0))`):

```
$ CHEZSCHEMELIBDIRS="<scratch>/b1-mutation:src:fallback:tests:build/scheme-libs" \
    CMARK_CLI=cmark-gfm chez --program tests/test-native.sps; echo "EXIT=$?"
%%%% Starting test native
# of expected passes      56
EXIT=0
```

56/56, exit 0 — not even a collateral failure, exactly as B1 reported.
Dereferencing address 0 did not crash the process on this machine (macOS
10.4.1/ARM64); whatever it raises internally is caught by SRFI-64's
catch-all guard and turned into `#f`, which matched the assertion's own
bare `#f` expected value.

**Fixed** to a sentinel the raise path cannot produce:

```scheme
(test-equal "c-string->string maps NULL to #f"
  'null
  (let ((r (c-string->string 0))) (if (eq? r #f) 'null (list 'got r))))
```

**After the fix**, normal run (real `native.sls`, unmutated):

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-native.sps
%%%% Starting test native
# of expected passes      56
EXIT=0
```

**After the fix**, against the SAME mutated `native.sls`:

```
$ CHEZSCHEMELIBDIRS="<scratch>/b1-mutation:src:fallback:tests:build/scheme-libs" \
    CMARK_CLI=cmark-gfm chez --program tests/test-native.sps; echo "EXIT=$?"
%%%% Starting test native
FAIL c-string->string maps NULL to #f
# of expected passes      55
# of unexpected failures  1
EXIT=1
```

Fails by name, through the exact asserted property (NULL detection), with
no collateral. **Covered.**

While fixing this, the rest of `tests/test-native.sps` was checked for any
other assertion whose expected value is bare `#f` or bare truthiness. One
more was found: `"all flags off is the default mask, and differs from all
flags on"` (originally `(test-equal "..." #f (= (option-bits ...)
(option-bits ...)))`) — a raise from either `option-bits` call would be
swallowed to `#f` by the same mechanism and satisfy the same bare-`#f`
expected value. Fixed the same way, with a `'differ`/`'same` sentinel pair
rather than a bare boolean. (One further candidate was considered and left
alone: `"tasklist-checked returns exactly 1 or 0, never a stray bit
pattern"` expects bare `#t`, not `#f` — a swallowed raise produces `#f`,
which mismatches `#t` and correctly fails the assertion, so this one is not
an instance of the trap.) No dedicated watched-mutation run was performed
for the second (`option-bits`) fix — it was corrected by inspection, using
the identical reasoning just demonstrated on row 16 — and that is recorded
here rather than left silent, per AGENTS.md.

### Row 17 — `tests/test-manifest-deps.sps`, the exact-dependency-set assertion

The suite's sole exact-set assertion compared `(list-sort string<?
all-deps)` — the UNION of `(dep-names 'depends)` and `(dep-names
'depends/dev)` — against `'("chez-srfi" "wak-sxml-tools")`. Promoting both
declared dependencies from `depends/dev` to `depends` in `Akku.manifest`
leaves that union unchanged.

**Before the fix**, against the ORIGINAL assertion, from a scratch working
directory holding a copy of `Akku.manifest` with `(depends/dev ...)`
rewritten to `(depends ...)`:

```
$ cat Akku.manifest
...
  (depends ("chez-srfi" "^0.0.0-akku.181.7879b52")
               ("wak-sxml-tools" "^0.0.0-akku.1.5c14730")))

$ CHEZSCHEMELIBDIRS=<repo>/src:<repo>/fallback:<repo>/tests:<repo>/build/scheme-libs \
    chez --program <repo>/tests/test-manifest-deps.sps; echo "EXIT=$?"
%%%% Starting test manifest-deps
# of expected passes      3
EXIT=0
```

3/3, exit 0 — both of today's dev dependencies promoted to hard runtime
dependencies, and nothing notices, exactly as F1 reported.

**Fixed** by checking `depends` and `depends/dev` independently rather than
their union:

```scheme
(test-equal "no hard runtime dependency is declared"
  '()
  (dep-names 'depends))

(test-equal "the declared dev-dependency set is exactly the current known-good set"
  '("chez-srfi" "wak-sxml-tools")
  (list-sort string<? (dep-names 'depends/dev)))
```

**After the fix**, normal run (real `Akku.manifest`, unmutated):

```
$ CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-manifest-deps.sps
%%%% Starting test manifest-deps
# of expected passes      4
EXIT=0
```

**After the fix**, against the SAME mutated `Akku.manifest`:

```
$ CHEZSCHEMELIBDIRS=<repo>/src:<repo>/fallback:<repo>/tests:<repo>/build/scheme-libs \
    chez --program <repo>/tests/test-manifest-deps.sps; echo "EXIT=$?"
%%%% Starting test manifest-deps
FAIL no hard runtime dependency is declared
FAIL the declared dev-dependency set is exactly the current known-good set
# of expected passes      2
# of unexpected failures  2
EXIT=1
```

Both fail by name, through the exact asserted property (a dependency's
declared class), with no unrelated collateral — the marker-check and seed
assertions, unaffected by this mutation, stayed green. **Covered.**

`git status --short` and `git diff --stat` were confirmed empty for both
`native.sls` and `Akku.manifest` throughout; only the scratch copies were
ever mutated.

---

## Final confirmation

Every mutation re-run in this task lived only in a scratch directory
outside the repo, or (the two `fallback/`-config mutations, which are
referenced by a literal path) was applied in place and restored from a
byte-identical backup. `git status --short` and `git diff --stat` were
checked empty after every single one, not just at the end. Final state:

```
$ git status --short
(empty)
$ git diff --stat
(empty)
$ make test
... 18 suites ...
ALL SUITES PASSED
$ echo $?
0
```

No mutation was left in the tree while another was in progress. This file
is the only change this task makes to the repository.

---

## Final confirmation (final pre-1.0 review pass)

Rows 16 and 17 above, plus the false-comment and documentation fixes from
the same review, are a later, separate pass over this branch, after Task
13. All five covering checks were run fresh against the finished tree; real
output below.

```
$ make test
... 18 suites, ALL SUITES PASSED ...
$ echo $?
0

$ make examples
... 6 examples, ALL EXAMPLES PASSED ...

$ make check-purity
... 5 pure suites, purity holds for every one ...

$ make check-config
check-config: fallback and generated config agree

$ make test-memory
... 17 memory-eligible suites (test-differential.sps excluded by design), no FAIL lines ...
$ echo $?
0
```

All green. Nothing was left uncommitted or half-fixed; see
`.superpowers/sdd/final-fix-report.md` for the full per-finding breakdown
and commit SHAs.
