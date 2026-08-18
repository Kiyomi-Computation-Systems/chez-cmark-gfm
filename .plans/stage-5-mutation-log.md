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

---

## Task 2 — `make-sxml-options`

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-options.sps`: 56/56 passes, exit 0. `make test`: 10 suites, all
`ALL SUITES PASSED`. `make check-purity`: holds.

**Mutation** (brief Step 6): in the scratch copy only, delete the
`validate-sxml` call from `sxml-options-with`, leaving `make-sxml-options`
untouched:

```diff
   (define (sxml-options-with o . plist)
     (let ((a (sxml-plist->alist plist)))
-      (validate-sxml
-       (%make-sxml-options
-        (lookup a 'raw-html (sxml-options-raw-html o)))))))
+      (%make-sxml-options
+       (lookup a 'raw-html (sxml-options-raw-html o))))))
```

`src/cmark/gfm/options.sls` in the repo was never touched — only
`<scratch>/cmark/gfm/options.sls` was edited. Confirmed by `md5`, taken
before the scratch copy was made and again after the exercise
(`22357d64719d35ff38ac94d9997830f5`, unchanged), and by `git diff --stat`
(the same 50 insertions / 2 deletions as this task's legitimate feature
change, identical before and after).

**Run:** `CHEZSCHEMELIBDIRS=<scratch>:src:tests:build/scheme-libs chez
--program tests/test-options.sps`

**Result: FAIL, 55/56 — exactly the assertion the brief names, nothing
wider.**

```
%%%% Starting test options
FAIL sxml-options-with validates too
# of expected passes      55
# of unexpected failures  1
```

Unlike Task 1's mutation, whose one-line diff had an unavoidable arity side
effect that took three assertions down with it, this one isolates cleanly:
only **"sxml-options-with validates too"** fails, exactly as Step 6
predicts, and the result needed no reconciliation. Every constructor-side
assertion stays green — including "an unknown raw-html value is rejected",
which exercises the very same `validate-sxml` check through
`make-sxml-options` rather than `sxml-options-with`, and stays green
precisely because `make-sxml-options`'s own call to `validate-sxml` was left
untouched by this mutation. That is the property Step 6 exists to establish:
`sxml-options-with` builds through `%make-sxml-options` directly, so without
its own `validate-sxml` call it could smuggle an invalid `raw-html` value
past validation by starting from an existing record instead of a fresh
plist -- the same back door `cmark-options-with` is closed against for the
contradictory hardbreaks?/nobreaks? pair. No second probe was needed: the
observed failure matches the brief's prediction exactly, both in which
assertion fails and in which stay green.

**Revert.** Nothing in the repo was ever edited during the mutation — only
the external scratch copy was. Confirmed via `git diff --stat
src/cmark/gfm/options.sls` (unchanged before and after) and via `md5`
(`22357d64719d35ff38ac94d9997830f5`, identical before the scratch copy was
mutated and after). Re-ran the suite through the ordinary, non-scratch
command: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-options.sps` → `# of expected passes 56`, exit 0. Also
reconfirmed `make test` (10 suites, `ALL SUITES PASSED`) and `make
check-purity` (holds) both before and after this exercise.

---

## Task 2 review fix — `sxml-options-with`'s first-argument guard

Two review findings against Task 2's plan-mandated code, adjudicated in the
reviewer's favour and folded into the plan by commit `1c17578`: (1)
`sxml-plist->alist` was a structural copy of `plist->alist`, collapsed by
giving `plist->alist` a `valid-keys` parameter; (2) `sxml-options-with` was
missing the non-options guard `cmark-options-with` already has, so a swapped
argument raised a bare R6RS `assertion-violation` instead of
`&cmark-invalid-option`. Finding 1 is a pure refactor covered entirely by
pre-existing assertions (both key sets are walked by the same tests as
before, just through one shared function). Finding 2 adds exactly one new
assertion, `"sxml-options-with rejects a non-options first argument"`, which
is what this entry's mutation targets.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-options.sps`: 57/57 passes, exit 0 (56 pre-existing + this fix
pass's one new assertion). `make test`: 10 suites, all `ALL SUITES PASSED`.
`make check-purity`: holds.

**Mutation**: in the scratch copy only, delete the `(unless (sxml-options?
o) ...)` guard just added to `sxml-options-with`:

```diff
   (define (sxml-options-with o . plist)
-    ;; Guards its first argument exactly as cmark-options-with does. Two
-    ;; record types with matching APIs now coexist, so passing the wrong one
-    ;; is a realistic caller error, and it must surface as this library's own
-    ;; condition rather than as a bare R6RS assertion from the accessor.
-    (unless (sxml-options? o)
-      (raise (make-cmark-invalid-option #f 'invalid-value)))
     (let ((a (plist->alist plist sxml-option-keys)))
       (validate-sxml
        (%make-sxml-options
```

`src/cmark/gfm/options.sls` in the repo was never touched — only
`<scratch>/cmark/gfm/options.sls` was edited. Confirmed by `md5`, taken
before the scratch copy was made and again after the exercise
(`3ddd634662bf8c9f8ae5172dfe553716`, unchanged), and by `git diff --stat`
(the same 16 insertions / 22 deletions as this fix pass's legitimate change,
identical before and after).

**Run:** `CHEZSCHEMELIBDIRS=<scratch>:src:tests:build/scheme-libs chez
--program tests/test-options.sps`

**Result: FAIL, 56/57 — exactly the assertion the fix brief names, nothing
wider.**

```
%%%% Starting test options
FAIL sxml-options-with rejects a non-options first argument
# of expected passes      56
# of unexpected failures  1
```

Only **"sxml-options-with rejects a non-options first argument"** fails;
every other assertion stays green, including "cmark-options-with rejects a
non-options first argument" (the pre-existing sibling test for the other
record type, whose own guard was never touched by this mutation) and every
other sxml-options assertion.

**Root cause confirmed by direct probe, not merely inferred.** The fix
brief's own text predicts the failure mode: with the guard gone,
`sxml-options-with` calls `(sxml-options-raw-html o)` on `o`, and when `o` is
actually a `cmark-options` record (as in the new test, which passes
`(default-cmark-options)`), that accessor call is a record-type mismatch at
the R6RS level, not a condition this library raises itself. A standalone
probe (`probe-task2.sps`, scratch-only, against the mutated library) calls
`(sxml-options-with (default-cmark-options) 'raw-html 'escape)` directly and
inspects what is actually signalled:

```
condition-type: R6RS assertion-violation
who: sxml-options-raw-html
message: ~s is not of type ~s
irritants: (#[cmark-options ...] #<record type sxml-options>)
```

Confirmed: a bare R6RS `assertion-violation` from the `sxml-options-raw-html`
accessor, not `&cmark-invalid-option` — exactly Finding 2's description of
the defect. In the test itself this is why the result is `'wrong-condition`
rather than `'(#f invalid-value)`: the guard's `(#t 'wrong-condition)` clause
catches any condition, the assertion-violation satisfies neither branch
of `(cmark-invalid-option? e)`, and `test-equal` reports the resulting
mismatch as the named failure. No second probe was needed: the observed
failure, both which assertion falls and which stay green, matches
prediction exactly.

**Revert.** Nothing in the repo was ever edited during the mutation — only
the external scratch copy was. Confirmed via `git diff --stat
src/cmark/gfm/options.sls` (unchanged before and after) and via `md5`
(`3ddd634662bf8c9f8ae5172dfe553716`, identical before the scratch copy was
mutated and after). Re-ran the suite through the ordinary, non-scratch
command: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-options.sps` → `# of expected passes 57`, exit 0. Also
reconfirmed `make test` (10 suites, `ALL SUITES PASSED`) and `make
check-purity` (holds) both before and after this exercise. Scratch copy and
probe script deleted afterward.

---

## Task 3 — the test-only SXML→HTML serializer

Two mutations, both against `tests/sxml-html-serializer.sls` (brief Step 5).
Method as stated above: scratch copy outside the repo, `CHEZSCHEMELIBDIRS`
prepended with the scratch directory so the mutated copy resolves first,
tracked file never touched.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-serializer.sps`: 16/16 passes, exit 0. `make test`: 11
suites (10 pre-existing + this task's own), all `ALL SUITES PASSED`. `make
check-purity`: holds. `make check-pins`: holds. `md5` of the tracked file at
baseline: `64887ab18335f5bab16c05a3bc519ee6`.

### Mutation 1 — `emit-cr` unconditional

**Mutation** (brief Step 5, literal reading): in a scratch copy only,
change `emit-cr` to emit `"\n"` unconditionally:

```diff
   (define (emit-cr)
-    (when (and (pair? chunks) (not last-newline?)) (emit "\n")))
+    (emit "\n"))
```

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation1:src:tests:build/scheme-libs
chez --program tests/test-sxml-serializer.sps`

**Result: FAIL, 0/16 — every assertion fails, far wider than the brief's
Step 5 text predicts** ("Confirm... fails and the others stay green").

```
# of unexpected failures  16
```

**Root cause confirmed by direct probe, not merely inferred.** A
standalone probe (`probe-mutation1.sps`, scratch-only) calls `(sxml->html
'(*TOP* (p "a & b")))` against the mutated library and prints the result:
`"\n<p>a &amp; b</p>\n"` — a spurious **leading** newline, before anything
at all has been written. The literal reading of "emit `\n`
unconditionally" collapses two independent guards into one deletion:
`(pair? chunks)` (html.c's own `html->size &&` — never emit a newline
before the first byte of output) and `(not last-newline?)` (the
collapse-on-repeat rule the named assertion actually targets). Removing
both at once means almost every test's tree — nearly all of them open with
a `cr-before-open` tag such as `p`, `blockquote`, `ul`, or `table` as their
very first node — now gets an unwanted leading `\n`, which fails the
assertion regardless of whether the collapse rule itself is exercised.
This is a different reason than the one named assertion is meant to
isolate, so per the plan's instruction not to accept "it failed, therefore
covered," a second, surgical mutation isolates the collapse rule alone.

**Isolated mutation 1b**, scratch-only, drops only the collapse-on-repeat
check and leaves the empty-buffer guard intact:

```diff
   (define (emit-cr)
-    (when (and (pair? chunks) (not last-newline?)) (emit "\n")))
+    (when (pair? chunks) (emit "\n")))
```

**Run:** same command against `<scratch>/mutation1b`.

**Result: FAIL, 9/16 — still wider than "one assertion fails, the others
stay green," but for a reason directly and verifiably tied to the named
property, not a side effect.**

```
FAIL hr and br close XHTML-style with a trailing newline
FAIL blockquote and list open tags are followed by a newline
FAIL list items close with a newline, open without
FAIL ol start renders as an attribute
FAIL newlines at block boundaries collapse, they do not stack
FAIL table sections and cells place newlines like table.c
FAIL a block-level comment gets newlines on both sides
# of unexpected failures  7
```

Confirmed by direct probe (`probe-mutation1b.sps`, scratch-only), comparing
baseline vs. mutated output side by side for four of the seven:

| tree | baseline (correct) | mutation 1b |
|---|---|---|
| `(blockquote (p "a"))` | `<blockquote>\n<p>a</p>\n</blockquote>\n` | `<blockquote>\n\n<p>a</p>\n\n</blockquote>\n` |
| `(ul (li "a") (li "b"))` | `<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n` | `<ul>\n\n<li>a</li>\n\n<li>b</li>\n</ul>\n` |
| `(p "a") (*COMMENT* " x ") (p "b")` | `<p>a</p>\n<!-- x -->\n<p>b</p>\n` | `<p>a</p>\n\n<!-- x -->\n\n<p>b</p>\n` |
| `(blockquote (p "a")) (p "b")` (the named test) | `<blockquote>\n<p>a</p>\n</blockquote>\n<p>b</p>\n` | `<blockquote>\n\n<p>a</p>\n\n</blockquote>\n\n<p>b</p>\n` |

Every one of the seven shows the identical signature: a doubled `\n\n`
appearing exactly at a boundary where the buffer already ended in a
newline and the correct code collapses to one. None are spurious or
unrelated — `blockquote`'s own `cr-after-open` followed immediately by its
child `p`'s `cr-before-open`, `ul`'s `cr-after-open` followed by `li`'s
`cr-before-open`, the block-comment's `emit-cr` immediately after `p`'s own
unconditional trailing newline, and the table's dense chain of adjacent
`thead`/`tr`/`th` boundaries, are all independently-occurring instances of
exactly the same collapse-on-repeat rule the named assertion exercises —
they are just additional, real trigger points the brief's Step 5 text did
not enumerate. So: the brief's prediction that "the others stay green" is
factually inaccurate (6 further assertions beyond the named one also
correctly fail), but the property Step 5 exists to establish is not merely
covered — it is covered more redundantly than the brief states, by seven
independent assertions rather than one, all for the single, correctly
isolated reason.

**Revert.** Nothing in the repo was ever edited by either variant — only
`<scratch>/mutation1` and `<scratch>/mutation1b` were. Confirmed via `md5
tests/sxml-html-serializer.sls` (`64887ab18335f5bab16c05a3bc519ee6`,
unchanged throughout both mutation attempts). Re-ran the suite through the
ordinary, non-scratch command: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program tests/test-sxml-serializer.sps` → `# of expected passes 16`,
exit 0.

### Mutation 2 — `href` dropped from `href-attribute?`

**Mutation** (brief Step 5): in a fresh scratch copy, remove `href` from
`href-attribute?`, leaving only `src`:

```diff
-  (define (href-attribute? name) (memq name '(href src)))
+  (define (href-attribute? name) (memq name '(src)))
```

`tests/sxml-html-serializer.sls` in the repo was never touched — only
`<scratch>/mutation2/sxml-html-serializer.sls` was edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation2:src:tests:build/scheme-libs
chez --program tests/test-sxml-serializer.sps`

**Result: FAIL, 15/16 — exactly the assertion the brief names, nothing
wider.**

```
FAIL href escapes ampersand and apostrophe as entities
# of expected passes      15
# of unexpected failures  1
```

**"a non-href attribute leaves apostrophe alone" stays green**, exactly as
predicted — that test never calls `href-attribute?` on `href` in the first
place (it uses `title`), so its code path is untouched by this mutation.
No second probe was needed to isolate anything, but one was run anyway to
record the exact mechanism: `probe-mutation2.sps` (scratch-only) calls
`(sxml->html '(*TOP* (p (a (\x40; (href "/a&b'c")) "l")))))` against the
mutated library and gets `"<p><a href=\"/a&amp;b'c\">l</a></p>\n"` — the
`&` is still escaped (via `escape-html`'s own `&` rule, a different code
path that still fires) but the `'` now survives unescaped, because `href`
no longer routes through `escape-href` at all. That is precisely the
property this mutation is meant to isolate: without `href` in
`href-attribute?`, an href value's apostrophe is no longer entity-escaped,
silently producing HTML that would break the attribute boundary were the
character actually `"` instead of `'`.

**Revert.** Confirmed via `md5 tests/sxml-html-serializer.sls` →
`64887ab18335f5bab16c05a3bc519ee6`, unchanged. Re-ran the suite through the
ordinary, non-scratch command: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program tests/test-sxml-serializer.sps` → `# of expected passes 16`,
exit 0.

**Final reconfirmation for the task.** `make test`: 11 suites, all `ALL
SUITES PASSED`. `make check-purity`: holds. `make check-pins`: holds.
Scratch copies and probe scripts deleted afterward.
