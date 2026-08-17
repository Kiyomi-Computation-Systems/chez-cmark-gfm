# Stage 5 Mutation Log

Per the [implementation plan](2026-08-17-stage-5-implementation.md)'s Global
Constraints: a test is finished only once it has been watched to fail through
the specific property it guards, then reverted and reconfirmed green. This
file is built up incrementally, one entry per task, as each task in Stage 5
(the SXML adapter) completes its own mutation step — unlike Stages 1-3, whose
logs were written once by a dedicated end-of-stage task.

**Method used in this file, unless a task's entry says otherwise:** the
target file is copied to a scratch directory *outside* the repo (this
session's scratchpad, mirroring the library's path, e.g.
`<scratch>/cmark/gfm/private/conditions.sls`), mutated only there, and the
suite is run with that scratch directory prepended to `CHEZSCHEMELIBDIRS` so
Chez's library resolver finds the mutated copy first for the one library
being probed while every other library still resolves normally from
`src`/`tests`/`build/scheme-libs`. The tracked file in the repo is never
edited, so "revert" means confirming `git diff --stat` on it is empty (or
unchanged from before the exercise) and re-running the suite through the
ordinary, non-scratch command.

---

## Task 1 — `&cmark-unsupported-node`

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-conditions.sps`: 26/26 passes, exit 0. `make test`: 10 suites, all
`ALL SUITES PASSED`. `make check-purity`: holds.

**Mutation** (brief Step 6): in the scratch copy only, change
`&cmark-unsupported-node`'s parent type from `&cmark-error` to
`&cmark-invalid-input`:

```diff
-  (define-condition-type &cmark-unsupported-node &cmark-error
+  (define-condition-type &cmark-unsupported-node &cmark-invalid-input
     make-cmark-unsupported-node cmark-unsupported-node?
     (type cmark-unsupported-node-type)))
```

`src/cmark/gfm/private/conditions.sls` in the repo was never touched — only
`<scratch>/cmark/gfm/private/conditions.sls` was edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>:src:tests:build/scheme-libs chez
--program tests/test-conditions.sps`

**Result: FAIL, 23/26 — wider than the brief's Step 6 text predicts.** All
three of this task's new assertions fail, not only the one the brief names:

```
FAIL unsupported-node carries the native type string
FAIL unsupported-node is a cmark-error
FAIL unsupported-node is not invalid-input
# of expected passes      23
# of unexpected failures  3
```

**Root cause, confirmed by direct probe, not merely inferred.** R6RS
`define-condition-type` generates a constructor that takes one argument per
field of the *entire* ancestor chain, parent fields first — confirmed
independently against the already-existing `&cmark-resource-limit`, which
already derives from `&cmark-invalid-input` and is constructed with 2 args,
`(make-cmark-resource-limit 'too-many-nodes 250000)` (`reason` then
`value`). Reparenting `&cmark-unsupported-node` onto `&cmark-invalid-input`
therefore silently turns `make-cmark-unsupported-node` into a
**2-argument** constructor (inherited `reason`, then `type`) — but the
brief's own Step 1 test code (transcribed verbatim) calls it with exactly
**one** argument, in all three assertions. A standalone probe
(`probe.sps`, scratch-only) against the mutated library shows the 1-argument
call raises Chez's own wrong-number-of-arguments violation
(`assertion-violation? #t`, irritants `(1
#<procedure make-cmark-unsupported-node>)`) *before* any
`&cmark-unsupported-node` or `&cmark-invalid-input` condition object is ever
built. So in every one of the three tests, `e` inside `guard` satisfies
neither `cmark-invalid-input?` nor `cmark-unsupported-node?`, and all three
fall to each test's own `(#t 'wrong-condition)` clause — which is why the
third test's actual value is `'wrong-condition`, not the brief-predicted
`'wrongly-invalid-input`.

**The semantic half of the brief's prediction is still correct, confirmed in
isolation.** A second probe (`probe2.sps`) calls the mutated, now-2-argument
constructor *correctly* — `(make-cmark-unsupported-node 'dummy "x")` — and
re-runs just the third test's guard logic against the result:
`cmark-invalid-input?` does answer `#t`, and the guard's own logic then does
evaluate to exactly `'wrongly-invalid-input`, precisely as the brief
predicts. The brief's prediction describes the mutation's intended semantic
effect correctly; it just did not anticipate the constructor's arity
changing as an unavoidable side effect of the identical one-line diff (R6RS
condition-type inheritance always appends new fields after inherited ones —
there is no way to change only the parent type without also changing the
constructor's arity here, short of also editing the field list, which the
brief's Step 6 does not ask for).

**Either way, the property Step 6 exists to establish holds.** "unsupported-
node is not invalid-input" is not a vacuous assertion: it is directly
sensitive to the exact derivation the brief names, and fails immediately the
moment that derivation is wrong — whether the failure is observed through
the arity violation (the real, literal outcome of the brief's stated
mutation) or, isolated from that side effect, through the predicted semantic
path. Recorded here explicitly, per this project's established norm (see
`stage-3-mutation-log.md`'s Property 3), rather than silently reconciling
the discrepancy with the brief's stated prediction.

**Revert.** Nothing in the repo was ever edited during the mutation — only
the external scratch copy was. Confirmed via `git diff --stat
src/cmark/gfm/private/conditions.sls` (shows only this task's legitimate,
already-intended feature addition, unchanged before and after the mutation
exercise) and via `md5` (identical before the scratch copy was mutated and
after). Re-ran the suite through the ordinary, non-scratch command:
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-conditions.sps` → `# of expected passes 26`, exit 0. Also
reconfirmed `make test` (10 suites, `ALL SUITES PASSED`) and `make
check-purity` (holds) both before and after this exercise, to rule out any
collateral effect from this task's actual (non-mutated) change.
