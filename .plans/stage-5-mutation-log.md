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

---

## Task 4 — the adapter's local block and inline nodes

Two mutations, both against `src/cmark/gfm/sxml.sls` (brief Step 8). Method
as stated above: scratch copy outside the repo (mirroring the library's path
as `<scratch>/cmark/gfm/sxml.sls`), `CHEZSCHEMELIBDIRS` prepended with the
scratch directory so the mutated copy resolves first for `(cmark gfm sxml)`
while `(cmark gfm)`, `(sxml-html-serializer)`, and everything else still
resolve normally from `src`/`tests`/`build/scheme-libs`; the tracked file
never edited.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps`: 12/12 passes, exit 0.
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps`: 9/9 passes, exit 0. `make test`: 13
suites, all `ALL SUITES PASSED`. `make check-purity`: three "purity holds"
lines. `make check-pins`: holds. `md5` of the tracked file at baseline:
`9acbaa836113922af00abcf1206d6728`.

### Mutation 1 — `strikethrough` mapped to `s` instead of `del`

**Mutation** (brief Step 8): in a scratch copy only, change the
`strikethrough` case:

```diff
-      ((strikethrough) (element 'del n raw-html))
+      ((strikethrough) (element 's n raw-html))
```

`src/cmark/gfm/sxml.sls` in the repo was never touched — only
`<scratch>/mutation1/cmark/gfm/sxml.sls` was edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation1:src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps`, then the same
`CHEZSCHEMELIBDIRS` against `tests/test-sxml-serializer.sps`.

**Result: FAIL, 8/9 in the differential — exactly the assertion the brief
names, nothing wider. The serializer's own suite stays fully green.**

```
%%%% Starting test sxml-differential
FAIL emphasis agrees
# of expected passes      8
# of unexpected failures  1
```

```
%%%% Starting test sxml-serializer
# of expected passes      16
```

Only **"emphasis agrees"** fails in the differential; every other
assertion — including "blockquotes agree", "breaks agree", and "adjacent
blocks agree", which exercise unrelated node types — stays green. The
serializer's own 16 assertions all still pass, unaffected, because
`tests/test-sxml-serializer.sps` imports only `(sxml-html-serializer)` and
never touches `(cmark gfm sxml)` at all — it cannot see this mutation to
compensate for it even in principle.

**Confirmed by direct probe** (`probe-mutation1.sps`, scratch-only) calling
`ours` and `theirs` on `"*e* **s** ~~d~~ \`c\`\n"` directly, reproducing what
the differential's `divergence` helper computes and would report as
`(list 'ours a 'theirs b)`:

```
ours:   "<p><em>e</em> <strong>s</strong> <s>d</s> <code>c</code></p>\n"
theirs: "<p><em>e</em> <strong>s</strong> <del>d</del> <code>c</code></p>\n"
agree?  #f
```

The two strings differ at exactly one place, the strikethrough tag —
`<s>d</s>` from the mutated adapter against cmark's real `<del>d</del>` —
which is precisely the property Step 8 exists to establish: the serializer
is generic over element names (it maps whatever tag the tree hands it), so
it renders `s` faithfully rather than silently correcting it back to `del`.
A wrong tag from the adapter is a byte difference in the differential, not
an error the serializer's own suite could ever be positioned to catch,
since that suite never constructs a strikethrough tree in the first place
and never imports the adapter under test here.

**Revert.** Nothing in the repo was ever edited during the mutation — only
`<scratch>/mutation1/cmark/gfm/sxml.sls` was. Confirmed via `git status
--short` (only the pre-existing untracked/modified files this task itself
added — `src/cmark/gfm/sxml.sls`, `tests/test-sxml.sps`,
`tests/test-sxml-differential.sps`, `Makefile` — unchanged before and after)
and via `md5 src/cmark/gfm/sxml.sls` (`9acbaa836113922af00abcf1206d6728`,
identical before the scratch copy was mutated and after). Re-ran the suite
through the ordinary, non-scratch command:
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps` → `# of expected passes 9`, exit 0.

### Mutation 2 — `first-token` returns the whole info string

**Mutation** (brief Step 8): in a fresh scratch copy, collapse `first-token`
to the identity function, so the entire fence-info string (not just its
first whitespace-delimited token) reaches the `class` attribute:

```diff
   ;; The first whitespace-delimited token of the info string, per
   ;; html.c:223-227.
-  (define (first-token s)
-    (let loop ((i 0))
-      (cond ((>= i (string-length s)) s)
-            ((memv (string-ref s i) '(#\space #\tab #\newline #\return))
-             (substring s 0 i))
-            (else (loop (+ i 1))))))
+  (define (first-token s) s)
```

`src/cmark/gfm/sxml.sls` in the repo was never touched — only
`<scratch>/mutation2/cmark/gfm/sxml.sls` was edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation2:src:tests:build/scheme-libs
chez --program tests/test-sxml.sps`, then the same `CHEZSCHEMELIBDIRS`
against `tests/test-sxml-differential.sps`.

**Result: FAIL in both suites, exactly the two assertions the brief names,
nothing wider.**

```
%%%% Starting test sxml
FAIL only the first token of the fence info becomes the class
# of expected passes      11
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL code blocks agree
# of expected passes      8
# of unexpected failures  1
```

Every other assertion in both suites stays green, including "a code block
with no info has a bare code element" (info is `""`, so `first-token`'s
mutation is a no-op on that fixture — the empty-info branch never calls
`first-token` on anything but an already-empty string) and every
differential case that touches no code block at all.

**Confirmed by direct probe** (`probe-mutation2.sps`, scratch-only):

```
pure-suite actual:   (*TOP* (pre (code (\x40; (class "language-scheme linenos=3")) "x\n")))
pure-suite expected: (*TOP* (pre (code (\x40; (class "language-scheme")) "x\n")))

differential ours:   "<pre><code class=\"language-scheme linenos\">(f x)\n</code></pre>\n<pre><code>indented\n</code></pre>\n"
differential theirs: "<pre><code class=\"language-scheme\">(f x)\n</code></pre>\n<pre><code>indented\n</code></pre>\n"
agree?  #f
```

In both cases the mutated adapter leaks the full fence-info string
(`"scheme linenos=3"`, `"scheme linenos"`) into the `class` attribute
instead of stopping at the first whitespace, exactly matching html.c:223-227
(`cmark_isspace` scan to the first space/tab/newline/CR) and exactly the
property both named assertions exist to guard. The indented-code-block half
of the differential fixture (`"    indented\n"`, empty fence-info) is
unaffected in both outputs, isolating the failure to the fenced case as
expected.

**Revert.** Nothing in the repo was ever edited during the mutation — only
`<scratch>/mutation2/cmark/gfm/sxml.sls` was. Confirmed via `md5
src/cmark/gfm/sxml.sls` (`9acbaa836113922af00abcf1206d6728`, identical
before the scratch copy was mutated and after) and via `git status --short`
(unchanged). Re-ran both suites through the ordinary, non-scratch command:
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps` → `# of expected passes 12`, exit 0;
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps` → `# of expected passes 9`, exit 0.

**Final reconfirmation for the task.** `make test`: 13 suites, all `ALL
SUITES PASSED`. `make check-purity`: three "purity holds" lines. `make
check-pins`: holds. Scratch copies and probe scripts deleted afterward.

**Note on the differential test's import list.** The brief's Step 6 code for
`tests/test-sxml-differential.sps` imports only `(rnrs)`, `(srfi :64)`,
`(cmark gfm)`, and `(sxml-html-serializer)`, then calls `markdown-ast->sxml`
unqualified. `(cmark gfm)` does not currently re-export `markdown-ast->sxml`
— that re-export is `(cmark gfm)`'s Task 8 (`markdown->sxml`), which this
task's own Files list (Create: `src/cmark/gfm/sxml.sls`; Test:
`tests/test-sxml.sps`, `tests/test-sxml-differential.sps`; Modify:
`Makefile`) does not include `src/cmark/gfm.sls` for. As literally
transcribed, the brief's differential test fails to load under any correct
`sxml.sls` (unbound identifier `markdown-ast->sxml`), independent of the
adapter's correctness — a self-inconsistent fixture in the sense the plan's
task notes warn about (input, not expectation, needs the fix). Fixed by
adding `(cmark gfm sxml)` to this test file's own import list, touching no
assertion, no expected value, and no file outside this task's scope.

---

## Task 5 — links, images, and the URL policy

Three mutations, all against `src/cmark/gfm/sxml.sls` (brief Step 7).

**Method used for this task, a variant of the convention stated at the top
of this file.** Instead of mirroring only the single library's path under
the scratch directory and prepending `CHEZSCHEMELIBDIRS`, the entire
working tree was `rsync`'d (excluding `.git`) to
`<scratch>/mutation-repo/`, including the already-built `build/scheme-libs`
directory, and each suite was run with `CHEZSCHEMELIBDIRS=src:tests:build/
scheme-libs` from inside that scratch clone — i.e. a full second checkout
outside the repo rather than one overridden library directory layered in
front of the real one. This satisfies the same invariant the stated method
protects ("the target file is... mutated only there", "the tracked file in
the repo is never edited") by construction: the mutated file never exists
inside `/Users/yuzu/github/chez-cmark-gfm` at all, only inside
`/private/tmp/.../scratchpad/mutation-repo/`. Confirmed throughout by `git
status --short` / `git diff --stat` on the real repo (showing only this
task's own already-intended feature changes to three files, unchanged
before, during, and after all three mutation runs) and by `md5
src/cmark/gfm/sxml.sls` on the real, tracked file.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps`: 19/19 passes, exit 0.
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps`: 15/15 passes, exit 0. `make test`: 13
suites, all `ALL SUITES PASSED`. `make check-purity`: three "purity holds"
lines. `md5` of the tracked file at baseline: `027f5834316662dd3da2d0b404ba5cb1`.
Reconfirmed identical in the scratch clone before any mutation (`diff
src/cmark/gfm/sxml.sls <scratch>/mutation-repo/src/cmark/gfm/sxml.sls` →
no output) and both suites re-run inside the untouched scratch clone as a
second baseline: 19/19 and 15/15, exit 0 both.

### Mutation 1 — percent-encode `&` as well

**Mutation** (brief Step 7.1): in the scratch clone only, remove `&` from
`href-safe-extra`:

```diff
   (define href-safe-extra
-    (string->list "!#$%()*+,-./:;=?@_~&'"))
+    (string->list "!#$%()*+,-./:;=?@_~'"))
```

**Run:** both suites, from inside `<scratch>/mutation-repo`, ordinary
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs`.

**Result: FAIL in both suites — the two assertions the brief names both
fail, plus one further differential assertion for the identical reason.**

```
%%%% Starting test sxml
FAIL a URL is percent-encoded but ampersand and apostrophe pass through
# of expected passes      18
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL links agree
FAIL autolinks agree
# of expected passes      13
# of unexpected failures  2
```

**"a URL is percent-encoded but ampersand and apostrophe pass through"** and
**"links agree"** both fail exactly as Step 7.1 predicts. **"autolinks
agree"** is not named by the brief, but it is not a different mechanism
either: its own fixture, `<https://example.com/a?b=1&c=2>`, contains a
literal `&`, and this mutation turns every `&` in every href into `%26`
regardless of which test constructed the link, so a second, unnamed
assertion whose fixture happens to contain `&` fails for the same, single
reason — unlike Task 1's or Task 3's discrepancies, this is not a case
needing a second isolating probe, because the failing property is identical
to the named one, just exercised by more than one fixture. No other
assertion in either suite regressed, including "images agree" and "data
urls agree", whose fixtures contain no bare `&`.

**Revert.** Confirmed via `diff` against the tracked file (`IDENTICAL`,
no output) and `md5 src/cmark/gfm/sxml.sls` on the real repo
(`027f5834316662dd3da2d0b404ba5cb1`, unchanged throughout). Re-ran both
suites through the ordinary, non-scratch command against the real repo →
19/19 and 15/15, exit 0 both.

### Mutation 2 — `data:image` allowlist moved after the `data:` rejection

**Mutation** (brief Step 7.2): in a fresh scratch clone, swap the order of
the two `cond` clauses in `dangerous-url?`:

```diff
   (define (dangerous-url? url)
     (let ((u (ascii-downcase url)))
       (cond
-        ((or (prefix? "data:image/png"  u) (prefix? "data:image/gif"  u)
-             (prefix? "data:image/jpeg" u) (prefix? "data:image/webp" u))
-         #f)
-        ((or (prefix? "javascript:" u) (prefix? "vbscript:" u)
-             (prefix? "file:" u) (prefix? "data:" u))
-         #t)
+        ((or (prefix? "javascript:" u) (prefix? "vbscript:" u)
+             (prefix? "file:" u) (prefix? "data:" u))
+         #t)
+        ((or (prefix? "data:image/png"  u) (prefix? "data:image/gif"  u)
+             (prefix? "data:image/jpeg" u) (prefix? "data:image/webp" u))
+         #f)
         (else #f))))
```

**Run:** both suites, from inside the fresh scratch clone.

**Result: FAIL in both suites, exactly the assertions the mutation
implicates, nothing wider.**

```
%%%% Starting test sxml
FAIL data: is rejected except for the four image subtypes
# of expected passes      18
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL data urls agree
# of expected passes      14
# of unexpected failures  1
```

**"data: is rejected except for the four image subtypes"** fails exactly as
Step 7.2 predicts, and it predicts the failure's *content*, not only that it
fails: it says the mutation "reports an empty href for the png." Confirmed
directly rather than inferred from the FAIL line — a standalone probe
(`probe-mutation2.sps`, scratch-only) called `markdown-ast->sxml` against
the mutated library on the exact fixture the named test uses and printed
the result:

```
(*TOP* (p (a (\x40; (href "")) "html")
          (a (\x40; (href "")) "png")
          (a (\x40; (href "")) "webp")))
```

Both the `png` and `webp` links — not only the already-dangerous `html`
one — now get an empty `href`, because the general `data:` rejection now
matches and returns `#t` before the image-subtype allowlist clause is ever
reached. Exactly the predicted mechanism. "data urls agree" (Step 5's own
differential fixture, not named by Step 7.2 but covering the identical
code path) fails for the same reason. No other assertion in either suite
regressed.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`027f5834316662dd3da2d0b404ba5cb1`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 19/19 and 15/15,
exit 0 both.

### Mutation 3 — `plain-text`'s `else` branch deleted

**Mutation** (brief Step 7.3): in a fresh scratch clone, delete the `else`
branch of `plain-text`, so a node type other than
`text`/`code`/`html-inline`/`softbreak`/`linebreak` (e.g. `emph`) is simply
not matched by `case` and contributes nothing — nor do its children get
visited:

```diff
   (define (plain-text n port)
     (case (markdown-node-type n)
       ((text code html-inline) (put-string port (prop n 'literal)))
-      ((softbreak linebreak)   (put-char port #\space))
-      (else
-       ;; Contributes nothing itself, but its children still render --
-       ;; the plain-mode branch returns before the element markup, it does
-       ;; not skip the subtree.
-       (for-each (lambda (c) (plain-text c port))
-                 (markdown-node-children n)))))
+      ((softbreak linebreak)   (put-char port #\space))))
```

**Run:** both suites, from inside the fresh scratch clone.

**Result: FAIL in both suites, exactly the two assertions the brief names,
nothing wider.**

```
%%%% Starting test sxml
FAIL image alt is the flattened plaintext of its children
# of expected passes      18
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL images agree
# of expected passes      14
# of unexpected failures  1
```

Exactly **"image alt is the flattened plaintext of its children"** and
**"images agree"** fail; every other assertion in both suites, including
"an image title is omitted when empty and kept when present" and "an image
src takes the same dangerous-URL policy" (whose fixtures have no non-leaf
children in the alt subtree, so this mutation is a no-op on them), stays
green. This is the property the named test exists to establish: `emph`'s
`(text "b")` child no longer contributes `"b"` to the flattened alt text
once `emph` itself is unmatched by `case`, because `case` without a
matching clause and no `else` returns unspecified and never reaches the
recursive `for-each` over children at all — the subtree is skipped, not
merely under-rendered.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`027f5834316662dd3da2d0b404ba5cb1`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 19/19 and 15/15,
exit 0 both.

**Final reconfirmation for the task.** `make test`: 13 suites, all `ALL
SUITES PASSED`. `make check-purity`: three "purity holds" lines. Scratch
clone and probe script deleted afterward.

---

## Task 6 — lists, list items, and task items

Three mutations, all against `src/cmark/gfm/sxml.sls` (brief Step 7). Same
rsync-a-full-scratch-clone method as Task 5:
`<scratch>/mutation-repo/`, the whole tree except `.git` (including the
already-built `build/scheme-libs`), each suite run from inside that clone
with `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs`. The tracked file in
the real repo is never edited; `diff` against it and `md5
src/cmark/gfm/sxml.sls` on the real repo confirm this before, during, and
after every mutation.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps`: 23/23 passes, exit 0.
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps`: 23/23 passes, exit 0 (22 from the
brief's Step 5 plus one fixture added ahead of the mutation step — see
"An unbrief-ed fix" below). `make test`: 13 suites, all `ALL SUITES
PASSED`. `make check-purity`: three "purity holds" lines. `md5` of the
tracked file at this baseline: `edf36283223fbfc12c2c7093f93241b3`.
Reconfirmed identical in the scratch clone before any mutation (`diff
src/cmark/gfm/sxml.sls <scratch>/mutation-repo/src/cmark/gfm/sxml.sls` →
no output) and both suites re-run inside the untouched scratch clone as a
second baseline: 23/23 both.

### An unbrief-ed fix, found and closed before the mutation step

Before mutating anything, a direct probe (`ours`/`theirs`, the same
comparator the differential uses) was run against a fixture *not* in the
brief's Step 5 list: `"- > q\n- b\n"` (a blockquote directly inside a tight
list item). The brief's Step 3, taken completely literally, says "update
the existing cases to pass `tight?` through unchanged" for every call site
`node->sxml`/`children->sxml` already had from Tasks 4-5 — including
`blockquote`. Doing exactly that disagreed with cmark:

```
OURS:   "<ul>\n<li>\n<blockquote>\nquoted\n</blockquote>\n</li>\n<li>b</li>\n</ul>\n"
THEIRS: "<ul>\n<li>\n<blockquote>\n<p>quoted</p>\n</blockquote>\n</li>\n<li>b</li>\n</ul>\n"
```

`vendor/cmark-gfm/src/html.c:288-291` keys tightness on the paragraph's
**grandparent being the list node itself** (`grandparent->type ==
CMARK_NODE_LIST`), not on being reachable through one. Once a `blockquote`
sits between an `item` and a `paragraph`, that paragraph's grandparent is
the `item`, never a `list`, so cmark always gives it a `<p>` regardless of
the enclosing list's tightness. Threading the inbound `tight?` through
`blockquote` unchanged — correct for every *other* container in the
dispatch, since none of the rest (`emph`, `strong`, `strikethrough`,
`heading`, `link`) can ever hold a `paragraph` as a descendant — extends
tightness one hop too far for this one container.

Per the task's own governing rule ("[the differential's] expectation is
produced by cmark and must never be adjusted to accommodate your code. If
they disagree, read the governing lines in `vendor/cmark-gfm/` and fix the
adapter"), the `blockquote` case was changed to force `#f` rather than
thread `tight?` through:

```diff
-      ((blockquote) (element 'blockquote n raw-html tight?))
+      ((blockquote) (element 'blockquote n raw-html #f))
```

Re-running the same probe after the fix: both sides produce
`"<ul>\n<li>\n<blockquote>\n<p>quoted</p>\n</blockquote>\n</li>\n<li>b</li>\n</ul>\n"`
— agree. Both suites re-run clean (23/23, 23/23) — no regression to any
brief-named fixture, including "nested lists agree", which has no
blockquote in it and was never at risk. A permanent regression fixture,
`"a blockquote in a tight item keeps its own <p>"` for `"- > q\n- b\n"`,
was added to `tests/test-sxml-differential.sps` (documented in-file as
beyond Step 5's exact list) so this cannot silently regress; it is the
23rd pass in every differential run reported in this task's entry. This is
not a Step 7 mutation — it is a real, pre-existing gap the brief's literal
text would have shipped, caught by the same cmark-as-oracle discipline
Step 7 exists to exercise, closed before Step 7 began so the mutations
below probe a correct baseline.

### Mutation 1 — tightness propagates from a list to all descendants, not just its own children

**Mutation** (brief Step 7.1): in the scratch clone only, make the `list`
case forward the *inbound* `tight?` to its own children instead of reading
its own `tight?` property:

```diff
       ((list)
-       (let ((kids (children->sxml n raw-html (prop n 'tight?)))
+       (let ((kids (children->sxml n raw-html tight?))
             (start (prop n 'start)))
```

**Run:** both suites, from inside `<scratch>/mutation-repo`.

**Result: FAIL in both suites, substantially WIDER than the two assertions
the brief names — flagged in advance by the task instructions as the
mutation "most likely to behave differently than predicted."**

```
%%%% Starting test sxml
FAIL a tight list has no p elements, a loose one does
FAIL tightness does not leak into a nested list
FAIL task items get a disabled checkbox, checked ones get the attribute
# of expected passes      20
# of unexpected failures  3
```

```
%%%% Starting test sxml-differential
FAIL tight lists agree
FAIL ordered lists agree
FAIL ol start agrees
FAIL nested lists agree
FAIL task lists agree
FAIL a blockquote in a tight item keeps its own <p>
# of expected passes      17
# of unexpected failures  6
```

The brief names exactly two: **"tightness does not leak into a nested
list"** and **"nested lists agree."** Both fail, but so do four more
assertions the brief does not name, and the ones it does name fail for a
*different* mechanism than their own name suggests. A second, isolating
probe (`probe-mutation1.sps`, scratch-only) pinned this down directly by
printing the actual tree, rather than inferring it from which FAIL lines
appeared:

```
nested-list fixture, actual tree under the mutation:
(*TOP* (ul (li (p "a") (ul (li (p "b"))))))
expected tree:
(*TOP* (ul (li "a" (ul (li (p "b"))))))

plain top-level tight list (no nesting at all):
(*TOP* (ul (li (p "x"))))
expected: (*TOP* (ul (li "x")))

loose outer list containing a nested TIGHT list:
(*TOP* (ul (li (p "a") (ul (li (p "b"))))))
expected: (*TOP* (ul (li (p "a") (ul (li "b")))))
```

The name "tightness does not leak into a nested list" suggests the failure
mode is over-application: a loose list wrongly inheriting `#t` from a
tight ancestor. That is not what happens. The mutated `list` case never
reads `(prop n 'tight?)` at all any more, so the *only* place in the whole
file that ever turns `tight?` on — anywhere, at any depth — is deleted.
`markdown-ast->sxml` seeds the walk with `#f`
(`(node->sxml ast (sxml-options-raw-html o) #f)`), `document` passes it
through unchanged, and now `list` does too, so every list in the tree,
top-level or nested, tight or loose by its own declared property, is
stuck at `tight?` = `#f` forever. The second probe proves this directly:
a plain, non-nested `bullet #t` list (no nesting anywhere in the
document) loses its tightness just as completely as the nested-list
fixture does. The third probe shows the failure runs in the *opposite*
direction from "leak": a nested list that is genuinely declared tight
(`bullet #t`) *fails to render tight* when its enclosing list is loose,
because it now inherits the outer list's incoming `#f` instead of
consulting its own property — under-tightening, not over-tightening.

The named fixture "tightness does not leak into a nested list" still
fails, but by coincidence of what its expected value happens to pin (the
bare `"a"` on the *outer*, non-nested item), not because the nested list
specifically leaked anything: the outer item's own paragraph loses its
splice for the same global-collapse reason as the plain top-level case.
"task items get a disabled checkbox, checked ones get the attribute"
fails for the identical root cause working through the splice mechanism
exactly as flagged: its fixture is a tight list, so under the mutation its
paragraphs stop splicing and `(li input " " "a")` becomes `(li input " "
(p "a"))`, a mismatch having nothing to do with the checkbox attributes
themselves. The differential fixtures that fail split the same way: "ol
start agrees" and "ordered lists agree" have nothing to do with the
`start` attribute (unaffected by this mutation) and fail purely because
their lists are tight and stop rendering tight; "a blockquote in a tight
item keeps its own `<p>`" fails because *its* second item ("b", a bare
paragraph, not the blockquote) also loses its splice.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`edf36283223fbfc12c2c7093f93241b3`, unchanged throughout). Re-ran both
suites through the ordinary, non-scratch command against the real repo →
23/23 and 23/23, exit 0 both.

### Mutation 2 — `(checked "")` emitted unconditionally

**Mutation** (brief Step 7.2): in a fresh scratch clone, drop the
`checked?` conditional in the `item` case so every task item's checkbox
carries `checked=""`:

```diff
                                            (append
-                                           (if (prop n 'checked?)
-                                               '((checked ""))
-                                               '())
+                                           '((checked ""))
                                            '((disabled ""))))))
```

**Run:** both suites, from inside the fresh scratch clone.

**Result: FAIL in both suites — the two assertions the brief names both
fail, plus one further differential assertion for the identical reason.**

```
%%%% Starting test sxml
FAIL task items get a disabled checkbox, checked ones get the attribute
# of expected passes      22
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL task lists agree
FAIL loose task lists agree
# of expected passes      21
# of unexpected failures  2
```

**"task items get a disabled checkbox, checked ones get the attribute"**
and **"task lists agree"** both fail exactly as Step 7.2 predicts. **"loose
task lists agree"** is not named by the brief, but — as with Task 5's
"autolinks agree" under its Mutation 1 — it is not a different mechanism:
its own fixture, `"- [ ] a\n\n- [x] b\n"`, contains an *unchecked* task
item, and this mutation gives every checkbox `checked=""` regardless of
which test constructed it. Confirmed directly with a standalone probe
(`probe-mutation2.sps`, scratch-only) comparing `ours`/`theirs` on that
exact fixture:

```
OURS:   "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> \n<p>a</p>\n</li>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> \n<p>b</p>\n</li>\n</ul>\n"
THEIRS: "<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> \n<p>a</p>\n</li>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> \n<p>b</p>\n</li>\n</ul>\n"
```

Item "a" (unchecked) picks up a spurious `checked=""` in `OURS`; item "b"
(checked) is identical in both — exactly the predicted mechanism, exercised
by a second fixture. No other assertion in either suite regressed.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`edf36283223fbfc12c2c7093f93241b3`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 23/23 and 23/23,
exit 0 both.

### Mutation 3 — `(\x40; (start "1"))` emitted for every ordered list

**Mutation** (brief Step 7.3): in a fresh scratch clone, drop the `(= 1
start)` guard in the `list` case so the `start` attribute is always
written, even when it is 1:

```diff
         (if (eq? 'ordered (prop n 'kind))
-            (if (= 1 start)
-                (cons 'ol kids)
-                (cons 'ol (cons (list '\x40; (list 'start (number->string start)))
-                                kids)))
+            (cons 'ol (cons (list '\x40; (list 'start (number->string start)))
+                            kids))
             (cons 'ul kids))))
```

**Run:** both suites, from inside the fresh scratch clone.

**Result: FAIL in both suites, exactly the two assertions the brief names,
nothing wider.**

```
%%%% Starting test sxml
FAIL ol start is emitted only when it is not one
# of expected passes      22
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL ordered lists agree
# of expected passes      22
# of unexpected failures  1
```

Exactly **"ol start is emitted only when it is not one"** and **"ordered
lists agree"** fail. "ol start agrees" (the differential's other
ordered-list fixture, `"5. a\n6. b\n"`) stays green, because it already
starts at 5 and so already took the "write the attribute" branch even
before the mutation — this mutation is a no-op on it, exactly as expected
since its own start value was never 1. No other assertion in either suite
regressed.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`edf36283223fbfc12c2c7093f93241b3`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 23/23 and 23/23,
exit 0 both.

**Final reconfirmation for the task.** `git status --short` on the real
repo throughout showed only this task's own three intended files modified
(`src/cmark/gfm/sxml.sls`, `tests/test-sxml.sps`,
`tests/test-sxml-differential.sps`) — never touched by any mutation or
probe run. `make test`: 13 suites, all `ALL SUITES PASSED`. `make
check-purity`: three "purity holds" lines. Scratch clone and probe scripts
deleted afterward.
