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

---

## Task 7 — tables

Three mutations, all against `src/cmark/gfm/sxml.sls` (brief Step 7). Same
rsync-a-full-scratch-clone method as Tasks 5-6: `<scratch>/mutation-repo/`,
the whole tree except `.git` (including the already-built
`build/scheme-libs`), each suite run from inside that clone with
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs`. The tracked file in the
real repo is never edited; `diff` against it and `md5
src/cmark/gfm/sxml.sls` on the real repo confirm this before, during, and
after every mutation.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps`: 26/26 passes, exit 0.
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps`: 28/28 passes, exit 0. `make test`: 13
suites, all `ALL SUITES PASSED`. `make check-purity`: three "purity holds"
lines. `md5` of the tracked file at this baseline:
`da305d27db8c95c518041b3144d58b02`. Reconfirmed identical in the scratch
clone before any mutation (`diff src/cmark/gfm/sxml.sls
<scratch>/mutation-repo/src/cmark/gfm/sxml.sls` → no output) and both
suites re-run inside the untouched scratch clone as a second baseline:
26/26 and 28/28.

### Mutation 1 — open a new `tbody` per body row

**Mutation** (brief Step 7.1): in the scratch clone only, stop
accumulating body rows under one shared `tbody`; instead wrap each body
row's `tr` in its own `tbody` as soon as it is folded in:

```diff
        ((null? rows)
         (cons 'table
               (append
                (if (null? head) '() (list (cons 'thead (reverse head))))
-               (if (null? body) '() (list (cons 'tbody (reverse body)))))))
+               (reverse body))))
        (else
         (let* ((r (car rows))
                (header? (markdown-node-property r 'header?))
                (tr (cons 'tr (map (lambda (c) (cell->sxml c header? raw-html))
                                   (markdown-node-children r)))))
           (if header?
               (loop (cdr rows) (cons tr head) body)
-              (loop (cdr rows) head (cons tr body))))))))
+              (loop (cdr rows) head (cons (list 'tbody tr) body))))))))
```

**Run:** both suites, from inside `<scratch>/mutation-repo`.

**Result: FAIL in both suites, exactly the two assertions the brief names,
nothing wider.**

```
%%%% Starting test sxml
FAIL header rows go in thead, body rows share one tbody
# of expected passes      25
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL tables agree
# of expected passes      27
# of unexpected failures  1
```

Confirmed with a direct probe (`probe-mutation1.sps`, scratch-only) on the
"tables agree" fixture (`"| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4
|\n"`):

```
OURS:   "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n<tbody>\n<tr>\n<td>3</td>\n<td>4</td>\n</tr>\n</tbody>\n</table>\n"
THEIRS: "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n<tr>\n<td>3</td>\n<td>4</td>\n</tr>\n</tbody>\n</table>\n"
```

Two body rows produce two separate `<tbody>` elements in OURS instead of
one shared `<tbody>` holding both `<tr>`s — exactly the mechanism Step 7.1
names, and exactly what `extensions/table.c:781-785`'s `else if
(!table_state->need_closing_table_body)` guard exists to prevent: cmark
opens a fresh `<tbody>` only the *first* time a non-header row is seen,
not on every one.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`da305d27db8c95c518041b3144d58b02`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 26/26 and 28/28,
exit 0 both.

### Mutation 2 — `align` emitted only on header cells

**Mutation** (brief Step 7.2): in a fresh scratch clone, restrict
`cell->sxml`'s alignment attribute to header cells only — the XML
renderer's behaviour (`extensions/table.c`'s `xml_attr`, not its
`html_render`):

```diff
-      (if (memq align '(left center right))
+      (if (and header? (memq align '(left center right)))
           (cons tag (cons (list '\x40; (list 'align (symbol->string align)))
                           kids))
           (cons tag kids))))
```

**Run:** both suites, from inside the fresh scratch clone.

**Result: FAIL in both suites — exactly the two assertions the brief
names, nothing wider. This is the assertion that proves the ADR-0010 blind
spot is actually closed.**

```
%%%% Starting test sxml
FAIL alignment renders on header and body cells alike, omitted when none
# of expected passes      25
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL table alignment agrees
# of expected passes      27
# of unexpected failures  1
```

Confirmed with a direct probe (`probe-mutation2.sps`, scratch-only) on the
"table alignment agrees" fixture (`"| l | c | r | n |\n|:--|:-:|--:|---|\n|
1 | 2 | 3 | 4 |\n"`):

```
OURS:   "<table>\n<thead>\n<tr>\n<th align=\"left\">l</th>\n<th align=\"center\">c</th>\n<th align=\"right\">r</th>\n<th>n</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n<td>3</td>\n<td>4</td>\n</tr>\n</tbody>\n</table>\n"
THEIRS: "<table>\n<thead>\n<tr>\n<th align=\"left\">l</th>\n<th align=\"center\">c</th>\n<th align=\"right\">r</th>\n<th>n</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">1</td>\n<td align=\"center\">2</td>\n<td align=\"right\">3</td>\n<td>4</td>\n</tr>\n</tbody>\n</table>\n"
```

The header row is byte-identical in both. The body row's three aligned
cells lose `align="left"`/`"center"`/`"right"` in OURS under the mutation
while THEIRS (real cmark) keeps them. This is `extensions/table.c:798-812`
exactly: entering a `CMARK_NODE_TABLE_CELL`, the `if
(table_state->in_table_header)` test at line 801 picks only the tag name
(`<th>` vs `<td>`); the `switch (get_cell_alignment(node))` at lines
807-812 that actually writes the `align` attribute sits *outside* that
`if`/`else` and runs unconditionally for every cell, header or body alike.
Had this suite been built against cmark's XML renderer instead (ADR-0010's
oracle for the AST stage; `extensions/table.c:608-621`'s `xml_attr`, which
DOES gate `align` behind `cmark_gfm_extensions_get_table_row_is_header
(node->parent)`), the mutated code above would satisfy every XML-oracle
assertion while still silently disagreeing with cmark's actual HTML
output. That is the precise blind spot the design docs charge to ADR-0010
and that Stage 5's HTML-oracle differential (ADR-0012) closes: this
mutation is caught here specifically because the HTML renderer, unlike the
XML renderer, was actually consulted.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`da305d27db8c95c518041b3144d58b02`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 26/26 and 28/28,
exit 0 both.

### Mutation 3 — an empty `(tbody)` emitted when there are no body rows

**Mutation** (brief Step 7.3): in a fresh scratch clone, drop the `(if
(null? body) …)` guard around the `tbody` half of the result so an empty
`tbody` is always appended:

```diff
                (if (null? head) '() (list (cons 'thead (reverse head))))
-               (if (null? body) '() (list (cons 'tbody (reverse body)))))))
+               (list (cons 'tbody (reverse body))))))
```

**Run:** both suites, from inside the fresh scratch clone.

**Result: FAIL in both suites, exactly the two assertions the brief names,
nothing wider.**

```
%%%% Starting test sxml
FAIL a table with no body rows emits no tbody
# of expected passes      25
# of unexpected failures  1
```

```
%%%% Starting test sxml-differential
FAIL header-only tables agree
# of expected passes      27
# of unexpected failures  1
```

Confirmed with a direct probe (`probe-mutation3.sps`, scratch-only) on the
"header-only tables agree" fixture (`"| a | b |\n| --- | --- |\n"`):

```
OURS:   "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n</tbody>\n</table>\n"
THEIRS: "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n</table>\n"
```

OURS appends a spurious empty `<tbody>\n</tbody>` that cmark's own
`html_render` never writes. In the C, `need_closing_table_body`
(`extensions/table.c:742-743,784`) is a bit set only inside the
`CMARK_NODE_TABLE_ROW` entering branch, the first time a genuine
non-header row is seen; a table with zero body rows never sets it, so the
table's own closing branch (`extensions/table.c:764-768`) never writes
`</tbody>` — and, because there is no procedural "enter tbody" event
independent of a row in cmark's model at all, no `<tbody>` was ever opened
either. Our fold mirrors this by keeping `body` an empty list and gating
the whole `(cons 'tbody …)` on `(null? body)`; the mutation deletes exactly
that gate.

**Revert.** Confirmed via `diff` against the tracked file (no output) and
`md5 src/cmark/gfm/sxml.sls` on the real repo
(`da305d27db8c95c518041b3144d58b02`, unchanged). Re-ran both suites through
the ordinary, non-scratch command against the real repo → 26/26 and 28/28,
exit 0 both.

**Final reconfirmation for the task.** `git status --short` on the real
repo throughout all three mutations showed only this task's own three
intended files modified (`src/cmark/gfm/sxml.sls`, `tests/test-sxml.sps`,
`tests/test-sxml-differential.sps`) — never touched by any mutation or
probe run. `make test`: 13 suites, all `ALL SUITES PASSED`. `make
check-purity`: three "purity holds" lines. Scratch clone and probe scripts
deleted afterward.

---

## Task 7 review fix — refusing a non-canonical table row order

A review finding against Task 7's `table->sxml`: the fold bucketed every
header-flagged row into one merged `thead`, which cmark does not do —
`extensions/table.c:777-780,792-795` opens and closes a `<thead>` around
*each* header row, with no accumulation guard analogous to `tbody`'s
`need_closing_table_body`. The parser itself can never produce more than
one header row, or one anywhere but first (`table.c:402-403` sets
`is_header` exactly once, on the row synthesised when the table block
opens; every later row is `calloc`'d with it false at `table.c:447`), so no
differential fixture can reach this path. But `markdown-ast->sxml` is a
public entry point taking an arbitrary AST, and `(cmark gfm ast)` ships
`markdown-node-map`/`markdown-node-with-children` precisely so callers can
rewrite trees, so the shape is reachable from outside the parser. The
project owner decided to refuse it rather than normalise it: silently
bucketing is not what cmark does, and reproducing cmark's own
header-after-body output exactly is worse, since it opens a `<thead>` while
a `<tbody>` is still open, which is not well-formed HTML. The fix gives the
fold a row index and raises `&cmark-invalid-input` with reason
`'malformed-table` when a header row appears at any position but the first
— covering both bad shapes, since a second header row necessarily follows a
first row, and a header row after body rows likewise follows earlier rows.
Two assertions were added to `tests/test-sxml.sps`, immediately before
"alignment renders on header and body cells alike, omitted when none": "a
header row after the first row is refused" and "two leading header rows are
refused".

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps`: 28/28 passes, exit 0 (26 pre-existing + this fix
pass's two new assertions). `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps`: 28/28 passes, exit 0,
unchanged from before the fix — every differential fixture goes through the
parser, which only ever produces canonical row order, so the new guard is
never exercised there. `make check-purity`: holds (all three pure suites,
including `test-sxml.sps` at 28/28). `make test`: 13 suites, all `ALL
SUITES PASSED`.

**Mutation**: in a scratch copy at `<scratch>/cmark/gfm/sxml.sls` (outside
the repo; the tracked file was never edited), delete the guard just added
to `table->sxml`:

```diff
-           ;; The parser cannot produce a header row anywhere but first:
-           ;; extensions/table.c:402-403 sets is_header exactly once, on the
-           ;; row synthesised when the table block opens, and every later row
-           ;; is calloc'd false (table.c:447). markdown-ast->sxml is public
-           ;; and takes an arbitrary tree, though, so a caller who built or
-           ;; rewrote one can hand us an order the parser never makes.
-           ;;
-           ;; Raising beats both alternatives. Bucketing every header row into
-           ;; one merged thead is silently NOT what cmark does -- table.c
-           ;; :777-780,792-795 opens and closes a thead around each header row,
-           ;; with no accumulation guard like tbody's need_closing_table_body.
-           ;; And reproducing cmark exactly is worse still: its header-after-
-           ;; body output opens a thead while a tbody is still open, which is
-           ;; not well-formed HTML.
-           (when (and header? (positive? i))
-             (raise (make-cmark-invalid-input 'malformed-table)))
            (if header?
```

`src/cmark/gfm/sxml.sls` in the repo was never touched — only
`<scratch>/cmark/gfm/sxml.sls` was edited. Confirmed by `md5`, taken before
the scratch copy was made and again after the exercise
(`42593826a30894e00aa6e357feb55e79`, unchanged), and by `git diff --stat`
(the same 19 insertions / 3 deletions in `src/cmark/gfm/sxml.sls` and 21
insertions / 0 deletions in `tests/test-sxml.sps` as this fix pass's
legitimate change, identical before and after).

**Run:** `CHEZSCHEMELIBDIRS=<scratch>:src:tests:build/scheme-libs chez
--program tests/test-sxml.sps` and the same against
`tests/test-sxml-differential.sps`.

**Result: FAIL in `test-sxml.sps`, exactly the two assertions the fix
brief names, nothing wider; `test-sxml-differential.sps` stays at
28/28.**

```
%%%% Starting test sxml
FAIL a header row after the first row is refused
FAIL two leading header rows are refused
# of expected passes      26
# of unexpected failures  2
```

```
%%%% Starting test sxml-differential
# of expected passes      28
```

Both new assertions fail by name and nothing else does: each `guard`'s
`(#t 'wrong-condition)` clause never fires, because the call no longer
raises at all — `->sxml` returns normally (bucketing every header row into
one `thead`, the same pre-fix behaviour), so the enclosing `test-equal`
compares `'malformed-table` against the trailing `'no-raise` instead, and
that mismatch is what `test-sxml.sps` reports as the two named failures.
`test-sxml-differential.sps` is unaffected for the reason the fix brief
predicts: no fixture there is anything but parser output, the parser
cannot construct the row order this guard exists to catch, so the deleted
code was dead weight from that suite's point of view — this is the
intended asymmetry, not a gap.

**Revert.** Confirmed via `md5 src/cmark/gfm/sxml.sls` on the real repo
(`42593826a30894e00aa6e357feb55e79`, unchanged throughout) and `git status
--short` showing only `src/cmark/gfm/sxml.sls` and `tests/test-sxml.sps`
modified, both this fix pass's own legitimate changes. Re-ran
`tests/test-sxml.sps` through the ordinary, non-scratch command → 28/28,
exit 0. Scratch copy deleted afterward.

---

## Task 7 review fix 2 — condition taxonomy and guard placement

Two further review findings against Task 7's `table->sxml`, both
adjudicated by the project owner and folded into the plan by commit
`52eb6c9`.

**Finding 1 (Important).** The previous fix pass's guard raised
`&cmark-invalid-input` with reason `'malformed-table`. But
`conditions.sls:59-60`(then-numbering) documents `&cmark-invalid-input`'s
reasons as a closed set — `'embedded-nul`, `'too-large`, `'not-a-string`,
`'extension-name-not-a-string` — all checks on raw Markdown text or option
values, and `&cmark-unsupported-node` was deliberately kept *out* of that
family (design spec 3.4) so a caller guarding bad documents cannot silently
swallow adapter-side problems. A malformed AST handed to the public
`markdown-ast->sxml` is neither a bad document nor an adapter gap, so it
gets its own condition, `&cmark-malformed-tree`, deriving from
`&cmark-error` directly — the same derivation `&cmark-unsupported-node`
uses, for the same reason. The reason symbol also changed from
`'malformed-table` (names the container) to `'header-row-not-first` (names
the check).

**Finding 2 (Minor).** `tr` was bound in the same `let*` as `header?`, so a
row about to be rejected was fully rendered — including any unsupported
node inside it — before the guard ran; such a node would raise
`&cmark-unsupported-node` and mask the more specific `&cmark-malformed-tree`
diagnosis. Fixed by moving `tr`'s binding into its own `let`, below the
guard.

### Files touched
- `src/cmark/gfm/private/conditions.sls` — new `&cmark-malformed-tree`
  condition type, deriving from `&cmark-error`; its four names (including
  the constructor) exported from this library, next to
  `&cmark-unsupported-node`.
- `src/cmark/gfm.sls` — re-exports `&cmark-malformed-tree`,
  `cmark-malformed-tree?`, `cmark-malformed-tree-reason` (constructor
  withheld — matching how every other condition type is re-exported from
  this library; the public API never lets a caller construct one).
- `src/cmark/gfm/sxml.sls` — `table->sxml` now raises
  `(make-cmark-malformed-tree 'header-row-not-first)`; `tr`'s binding moved
  into a nested `let`, below the guard.
- `tests/test-sxml.sps` — the two existing table-row-order assertions now
  guard on `cmark-malformed-tree?`/`cmark-malformed-tree-reason` and expect
  `'header-row-not-first` (the `'wrong-condition`/`'no-raise` sentinels
  unchanged).
- `tests/test-conditions.sps` — three new assertions mirroring
  `&cmark-unsupported-node`'s own coverage: the reason is carried, the
  condition is a `cmark-error?`, and — the load-bearing one — it is **not**
  a `cmark-invalid-input?`.

**Baseline**, at HEAD before this fix pass's edits:
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-conditions.sps`: 26/26 passes, exit 0.
`tests/test-sxml.sps`: 28/28, exit 0.

**Post-fix.** `tests/test-conditions.sps`: **29/29** (26 pre-existing + 3
new). `tests/test-sxml.sps`: **28/28** (unchanged count — the two
table-row-order assertions were edited in place, not added to).
`tests/test-sxml-differential.sps`: **28/28**, unchanged, confirming the
guard is still never exercised by parser output — every differential
fixture parses, so it can never fire. `make check-purity`: holds, all
three pure suites including `test-sxml.sps` at 28/28. `make test`: 13
suites, all `ALL SUITES PASSED`.

---

### Mutation 1 — reparent `&cmark-malformed-tree` onto `&cmark-invalid-input`

In a scratch copy at `<scratch>/mutation1/cmark/gfm/private/conditions.sls`
(outside the repo; the tracked file was never edited), change the new
condition type's parent:

```diff
@@ -122,5 +122,5 @@
   ;; swallow a structurally ill-shaped tree, any more than it should swallow
   ;; a coverage gap in the adapter. Neither is "the document was bad".
-  (define-condition-type &cmark-malformed-tree &cmark-error
+  (define-condition-type &cmark-malformed-tree &cmark-invalid-input
     make-cmark-malformed-tree cmark-malformed-tree?
     (reason cmark-malformed-tree-reason)))
```

`src/cmark/gfm/private/conditions.sls` in the repo was never touched.
Confirmed by `md5` (`d57557d57ac763329ea880671ae11841`, identical before
the scratch copy was made and after the exercise) and by `git status
--short` (only this fix pass's five legitimate files modified, unchanged
before and after).

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation1:src:tests:build/scheme-libs
chez --program tests/test-conditions.sps`

**Result: FAIL, 26/29 — all three of this fix pass's new assertions fail,
wider than a literal reading of Finding 1's one-line diff suggests, in
exactly the shape Task 1's entry predicted for this same kind of mutation.**

```
%%%% Starting test conditions
FAIL malformed-tree carries its reason
FAIL malformed-tree is a cmark-error
FAIL malformed-tree is not invalid-input
# of expected passes      26
# of unexpected failures  3
```

**Root cause confirmed by direct probe, not merely inferred**, following
Task 1's method exactly (it hit the identical shape of confound, reparenting
`&cmark-unsupported-node` the same way). R6RS `define-condition-type` gives
the generated constructor one argument per field of the whole ancestor
chain, parent fields first. `&cmark-invalid-input` already carries one field
(`reason`), so reparenting `&cmark-malformed-tree` onto it silently turns
`make-cmark-malformed-tree` into a **2-argument** constructor (inherited
`reason`, then the type's own `reason`) — but every call site (the three new
tests, and `table->sxml` itself) calls it with exactly **one** argument.
`probe.sps` (scratch-only) calls the mutated constructor the way the suite
does and shows the 1-argument call itself raises Chez's own
wrong-number-of-arguments violation before any condition object is ever
built:

```
(assertion-violation? #t who n/a
 message "incorrect number of arguments ~s to ~s"
 irritants (1 #<procedure make-cmark-malformed-tree>)
 cmark-error? #f cmark-invalid-input? #f cmark-malformed-tree? #f)
```

Neither `cmark-error?`, `cmark-invalid-input?`, nor `cmark-malformed-tree?`
is true of it, so in all three tests `e` falls to each guard's own `(#t
'wrong-condition)` clause — the mechanism behind all three failures above,
not only the named "is not invalid-input" one.

**The semantic half of the mutation is confirmed separately, isolated from
the arity side effect.** `probe2.sps` calls the mutated, now-2-argument
constructor correctly — `(make-cmark-malformed-tree 'dummy
'header-row-not-first)` — and re-runs just the "is not invalid-input"
test's guard logic against the resulting condition:

```
(guard-result wrongly-invalid-input cmark-invalid-input-reason-of-e n/a)
(cmark-invalid-input-reason dummy cmark-malformed-tree-reason header-row-not-first)
```

`cmark-invalid-input?` answers `#t` and the guard evaluates to
`'wrongly-invalid-input` — exactly the failure Finding 1's separation
exists to catch: reparenting really does make every `&cmark-malformed-tree`
an `&cmark-invalid-input`, precisely as the derivation change states. The
second line also confirms R6RS's field order directly:
`cmark-invalid-input-reason` reads the first (inherited) argument,
`cmark-malformed-tree-reason` reads the second (own) argument.

**Either way, the property Finding 1 exists to establish holds.** "malformed-
tree is not invalid-input" is not vacuous: it is directly sensitive to the
exact derivation Finding 1 names and fails immediately the moment that
derivation is wrong — whether observed through the arity violation (the
real, literal outcome of this one-line mutation) or, isolated from that
side effect, through the predicted semantic path. Recorded here explicitly
per this file's Task 1 precedent, rather than silently reconciling the
discrepancy with a one-assertion-only prediction.

**Revert.** `src/cmark/gfm/private/conditions.sls` in the repo was never
edited — only the external scratch copy was. Confirmed via `md5`
(`d57557d57ac763329ea880671ae11841`, unchanged) and `git status --short`
(same five files as this fix pass's own change, unchanged before and
after). Re-ran `tests/test-conditions.sps` through the ordinary,
non-scratch command → 29/29, exit 0. Also reconfirmed `make check-purity`
and `make test` (13 suites, `ALL SUITES PASSED`) both before and after this
exercise. Scratch copy deleted afterward.

---

### Mutation 2 — move the guard back below the `tr` binding

Finding 2 is about diagnosis priority between two conditions, not a
boolean an existing suite assertion checks — no suite assertion constructs
an unsupported node inside an already-malformed row, so per the brief this
mutation needed a scratch probe rather than a suite run.

In a scratch copy at `<scratch>/mutation2/cmark/gfm/sxml.sls` (outside the
repo; the tracked file was never edited), move `tr`'s binding back into the
same `let*` as `header?`, ahead of the guard — reinstating the shape Finding
2 flags:

```diff
@@ -184,27 +184,13 @@
          (let* ((r (car rows))
-                (header? (markdown-node-property r 'header?)))
-           ;; [explanatory comment, unchanged, elided here]
+                (header? (markdown-node-property r 'header?))
+                (tr (cons 'tr (map (lambda (c) (cell->sxml c header? raw-html))
+                                   (markdown-node-children r)))))
+           ;; MUTATION 2 (probe only): tr is bound above, before the guard,
+           ;; reverting Finding 2's fix so a row about to be rejected is
+           ;; fully rendered first.
            (when (and header? (positive? i))
              (raise (make-cmark-malformed-tree 'header-row-not-first)))
-           ;; [explanatory comment, unchanged, elided here]
-           (let ((tr (cons 'tr (map (lambda (c) (cell->sxml c header? raw-html))
-                                    (markdown-node-children r)))))
-             (if header?
-                 (loop (cdr rows) (+ i 1) (cons tr head) body)
-                 (loop (cdr rows) (+ i 1) head (cons tr body)))))))))
+           (if header?
+               (loop (cdr rows) (+ i 1) (cons tr head) body)
+               (loop (cdr rows) (+ i 1) head (cons tr body))))))))
```

`src/cmark/gfm/sxml.sls` in the repo was never touched. Confirmed by `md5`
(`90989438eb2b53581e10cae5beed4de1`, identical before the scratch copy was
made and after the exercise) and by `git status --short` (unchanged).

**Probe** (`probe-mutation2.sps`, scratch-only, no suite assertion covers
this): build a table whose third row is a second header row (`i = 2`,
positive — the row the guard exists to refuse) and give that row's one cell
an `extension` node, the shape `node->sxml`'s `(extension)` case raises
`&cmark-unsupported-node` on (`sxml.sls:296-297`), in place of plain text.
Call `markdown-ast->sxml` on the whole tree and report which condition
comes out.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation2:src:tests:build/scheme-libs
chez --program <scratch>/mutation2/probe-mutation2.sps`

**Result:**
```
(raised &cmark-unsupported-node type footnote_definition)
```

With `tr` bound before the guard, `cell->sxml` renders the offending row's
cells — including the `extension` node — before the `when` ever runs, so
`&cmark-unsupported-node` fires first and the more specific
`&cmark-malformed-tree` never gets the chance. This is exactly the
behaviour Finding 2's fix removes.

**Contrast: the identical probe input against the real, fixed library**
(ordinary `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs`, no scratch
prefix, same `probe-mutation2.sps`):
```
(raised &cmark-malformed-tree reason header-row-not-first)
```
With the guard checked before `tr` is bound, the row is refused before any
of its cells are rendered, so the specific diagnosis wins and the extension
node inside the doomed row is never reached at all. The two runs against
identical input, differing only in which `sxml.sls` answers, is the
property Finding 2 exists to establish.

**Revert.** `src/cmark/gfm/sxml.sls` in the repo was never edited — only
the external scratch copy was. Confirmed via `md5`
(`90989438eb2b53581e10cae5beed4de1`, unchanged throughout) and `git status
--short` (same five files as this fix pass's own change, unchanged before
and after). Re-ran `tests/test-sxml.sps` and `tests/test-sxml-
differential.sps` through the ordinary, non-scratch command → 28/28 each,
exit 0. Also reconfirmed `make check-purity` and `make test` (13 suites,
`ALL SUITES PASSED`) after this exercise. Scratch copies deleted afterward.

---

## Task 8 — `markdown->sxml`

**Baseline**, at HEAD before this task's edits: `CHEZSCHEMELIBDIRS=src:
tests:build/scheme-libs chez --program tests/test-options.sps`: 57/57,
exit 0. `tests/test-sxml-differential.sps`: 28/28, exit 0. `make test`: 13
suites, all `ALL SUITES PASSED`. `make check-purity`: three "purity holds"
lines (`tests/test-options.sps` 57, `tests/test-ast.sps` 30,
`tests/test-sxml.sps` 28).

### Files touched
- `src/cmark/gfm.sls` — imports `(cmark gfm sxml)`; exports `markdown->sxml`
  and `markdown-ast->sxml` next to `markdown->ast`; defines `markdown->sxml`
  as a 1/2/3-argument `case-lambda` defaulting to `default-cmark-options`
  and `default-sxml-options`, rejecting a non-`cmark-options?` first
  argument and an `unsafe-html?` value of `#t` before calling
  `markdown->ast` then `markdown-ast->sxml`.
- `tests/test-options.sps` — imports `(cmark gfm)`; two new assertions
  (`markdown->sxml rejects unsafe-html?`, `markdown->sxml accepts an
  explicit unsafe-html? #f`); header comment rewritten (see deviation 2
  below).
- `tests/test-sxml-differential.sps` — two new assertions (`source-
  positions? does not change the SXML`, `tagfilter does not change the
  SXML`).
- `Makefile` — `check-purity`'s suite list drops `tests/test-options.sps`;
  surrounding comment rewritten (see deviation 2 below).

### Two deviations from the brief's literal text, found and fixed

**Deviation 1 — test placement in `tests/test-options.sps`.** Step 1 says
to append the two new assertions "before its final `(exit …)`", which
literally means *after* the existing `(test-end "options")`. Step 5's
instruction for the sibling file says the opposite — "before `(test-end
…)`" — and Step 4 expects the printed summary to read `# of expected passes
59`. These cannot all hold at once, so before trusting either placement a
scratch probe (`probe-testend.sps`, not part of this repo) checked what
SRFI-64 actually does with assertions placed after `test-end`:

```
%%%% Starting test probe
# of expected passes      1
FAIL after test-end -- should this pass 2 (intentionally wrong)
fail-count: 1
pass-count: 2
```

`test-end` pops the group stack and fires the `on-final` summary hook
immediately (`vendor/chez-srfi/%3a64/testing-impl.scm:405-429`); assertions
placed after it still run and still count toward `test-runner-fail-count`
(the value `(exit …)` checks — confirmed above: the deliberately-wrong
assertion after `test-end` produced `fail-count: 1` and exit 1), but they
are invisible to the summary line printed at `test-end`, which reports only
the count accumulated up to that point. Placing the two new assertions
literally where Step 1 says would make `(exit …)` still correct but the
printed count freeze at 57, never reaching 59 — self-inconsistent with Step
4's own expectation. Fixed by placing them before `(test-end "options")`
instead, matching Step 5's phrasing for the sibling file and the placement
of `test-end` as the last test-registering form in every other suite in
this repo. The expectation (59 in the summary) was kept; the input
(placement) was changed, per this file's own precedent for self-inconsistent
briefs.

**Deviation 2 — `make check-purity`'s suite list.** Step 1's own note says
"this suite imports `(cmark gfm)` ... so it is not in the purity gate", but
implementing that (necessary for `markdown->sxml` to be in scope at all) is
exactly what makes `tests/test-options.sps` fail `make check-purity`'s
existing loop outright: `(cmark gfm)` transitively imports `(cmark gfm
private native)`, whose library body loads the shared object unconditionally
at instantiation (`src/cmark/gfm/private/native.sls:100`, `(define
shim-loaded (load-shim shim-file))`, a bare top-level definition, not gated
behind any call) — confirmed by running the unmodified loop after Step 3 and
watching it crash before a single assertion runs:

```
=== check-purity: tests/test-options.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
Exception occurred with condition components:
  0. &cmark-shim-unavailable: "/nonexistent"
PURITY VIOLATED: tests/test-options.sps failed with CHEZ_CMARK_GFM_SHIM poisoned
make: *** [check-purity] Error 1
```

Step 4 expects "purity still holds for all three pure suites", but the only
three suites this repo has ever marked `PURE SUITE` (confirmed by `rg -n
"PURE SUITE" tests/`) are exactly the Makefile's original three-item list —
`test-options.sps`, `test-ast.sps`, `test-sxml.sps` — so once
`test-options.sps` is (correctly, per Step 1's own note) no longer one of
them, only two remain; no fourth pure suite exists to restore the count to
three, and the brief's file list does not request adding one. Fixed by
dropping `tests/test-options.sps` from the Makefile's loop and rewriting
the surrounding comment. `options.sls`'s own purity stays covered without
it: `tests/test-sxml.sps` also imports `(cmark gfm options)` and remains in
the loop, so a real regression there still fails `make check-purity`. This
is recorded here rather than silently reconciled, per this file's own
Task 1 precedent for a prediction that does not hold exactly as stated.

### TDD

**RED** (Step 2), before Step 3's implementation:
```
Exception: attempt to reference unbound identifier markdown->sxml at line 362, char 6 of tests/test-options.sps
```

**GREEN** (Step 4), after Step 3:
```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
%%%% Starting test options
# of expected passes      59
```
Exit 0.

**Step 6**, after Step 5's two assertions:
```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
%%%% Starting test sxml-differential
# of expected passes      30
```
Exit 0.

Both counts match the brief exactly (59 = 57 + 2; 30 = 28 + 2).

### Step 5's two no-effect assertions, confirmed non-vacuous

Both compare rendered strings specifically so a boolean-comparator bug
cannot make either pass by accident (Global Constraints). Confirmed each is
sensitive to the property it guards, not merely structurally incapable of
failing:

**`source-positions?`.** A scratch probe (`probe-nonvacuous.sps`) parsed
the Step 5 fixture with the flag on and off and inspected the heading
node's own `markdown-node-source` directly:
```
heading source, positions ON:  #[#{source-position ...} 1 1 1 3]
heading source, positions OFF: #f
sxml equal?: #t
distinct docs equal?: #f
```
The AST input to the adapter genuinely differs (`#f` vs. a real
`source-position` record) — this is not a case of both sides producing
identical input — yet the SXML output is identical, because `sxml.sls`
never calls `markdown-node-source` anywhere (confirmed by `rg -n "source"
src/cmark/gfm/sxml.sls`, whose only hit is a comment). The last line rules
out a vacuously-#t comparator: two genuinely different documents through
the same `equal?` produce `#f`.

**`tagfilter`.** `vendor/cmark-gfm/extensions/tagfilter.c:56-59`'s
`create_tagfilter_extension` calls exactly one setter,
`cmark_syntax_extension_set_html_filter_func` — no postprocess, block, or
inline handler, so the extension has no AST-shaping capability at all.
`rg -n "html_filter_func" vendor/cmark-gfm/src vendor/cmark-gfm/extensions`
shows its only three non-definition call sites are all in `src/html.c`
(cmark's own HTML renderer), a code path `markdown->ast`/`markdown-ast->sxml`
never runs. A scratch probe (`probe-tagfilter2.sps`) confirmed the flag is
not a global no-op — with `unsafe-html? #t` (required for `html.c:335`'s
`CMARK_OPT_UNSAFE` gate to consult the filter at all), cmark's own
`markdown->html` differs with vs. without tagfilter:
```
cmark markdown->html WITH tagfilter:    "&lt;title>x&lt;/title>\n<p>para &lt;iframe>y&lt;/iframe> end</p>\n"
cmark markdown->html WITHOUT tagfilter: "<title>x</title>\n<p>para <iframe>y</iframe> end</p>\n"
cmark HTML differs with vs without tagfilter: #t
our SXML equal with vs without tagfilter: #t
```
So the underlying feature is real and observable; it is specifically our
AST-based path that cannot see it, which is exactly what the assertion
claims.

### Mutation (Step 7)

**Method:** scratch copy outside the repo, mirroring only the one file
under test (`<scratch>/mutation-task8/cmark/gfm.sls`, this task's method,
matching Tasks 1-4: `gfm.sls` is a top-level facade no `src/` library
imports, so shadowing only it via a prepended `CHEZSCHEMELIBDIRS` entry
cannot desync any other library's version). `md5` of the tracked file
before the copy was made: `fa9f7bb3004b870df2dbcdde6813b2da`.

**Mutation** (brief Step 7): "Change the `unsafe-html?` guard to test key
presence rather than value (raise whenever the caller passed the key at
all)." A built `cmark-options` is a fixed-shape record, not a plist — every
field, `unsafe-html?` included, is unconditionally present once
construction has filled in defaults, so "the caller passed this key" has no
representation left to test on `o` at the point this guard runs. The literal
reading of "raise whenever the key is present" therefore collapses, on this
data representation, to "raise unconditionally":

```diff
-       (when (cmark-options-unsafe-html? o)
+       (when #t
          (raise (make-cmark-invalid-option 'unsafe-html? 'not-applicable)))
```

Applied only to `<scratch>/mutation-task8/cmark/gfm.sls`; the tracked
`src/cmark/gfm.sls` was never edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/mutation-task8:src:tests:build/scheme-libs
chez --program tests/test-options.sps`

**Result: FAIL, 58/59 — exactly the assertion the brief names, nothing
wider.**
```
%%%% Starting test options
FAIL markdown->sxml accepts an explicit unsafe-html? #f
# of expected passes      58
# of unexpected failures  1
```
**"markdown->sxml accepts an explicit unsafe-html? #f"** fails (the guard now
raises even though the caller passed `#f`) while **"markdown->sxml rejects
unsafe-html?"** stays green (the guard still raises when the caller passed
`#t`, which is what that assertion checks) — exactly Step 7's prediction,
needing no reconciliation.

**Revert.** Confirmed via `git diff --stat src/cmark/gfm.sls` (only this
task's own legitimate 27-line addition, unchanged before and after the
exercise) and `md5 src/cmark/gfm.sls` (`fa9f7bb3004b870df2dbcdde6813b2da`,
identical throughout). Re-ran the ordinary, non-scratch command:
```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
# of expected passes      59
```
exit 0. Scratch copy deleted afterward.

**Final reconfirmation for the task.** `git status --short` showed only
this task's four intended files modified (`src/cmark/gfm.sls`,
`tests/test-options.sps`, `tests/test-sxml-differential.sps`, `Makefile`) —
never touched by the mutation or any probe. `make test`: 13 suites, all
`ALL SUITES PASSED`, with `tests/test-options.sps` at 59 and `tests/test-
sxml-differential.sps` at 30. `make check-purity`: two "purity holds"
lines (`tests/test-ast.sps` 30, `tests/test-sxml.sps` 28) — see Deviation 2
above for why the count is two rather than three. `make check-pins`: pins
agree. All scratch copies and probe scripts deleted afterward.

---

## Task 8 fix pass — restoring the purity gate

Corrects the resolution taken at the end of Task 8's entry above, per a
follow-up review. Task 8's brief claimed `tests/test-options.sps` already
imported `(cmark gfm)` -- false. It was a `PURE SUITE`, and `make
check-purity`'s original three-item loop (`test-options.sps`,
`test-ast.sps`, `test-sxml.sps`) is exactly what proved that. Following
the brief literally (Deviation 2 above) forced `(cmark gfm)` into the
suite to reach `markdown->sxml`, which broke the gate, and the fix taken
-- dropping `tests/test-options.sps` from the loop -- kept everything
green by removing the thing the gate was watching, not by fixing the
misplacement. The two assertions were the thing in the wrong place, not
the gate. This entry corrects that: the assertions move to
`tests/test-sxml-differential.sps` (already impure, already importing
`(cmark gfm)` for `markdown->ast`), `tests/test-options.sps` goes back to
pure, and the Makefile's three-item loop is restored.

### Files touched
- `tests/test-options.sps` -- `(cmark gfm)` dropped from the import list;
  the two `markdown->sxml` assertions and their section comment removed;
  header comment restored to its pre-Task-8 wording. Confirmed exactly
  restored, not just similar: `diff <(git show d83fefd~1:tests/test-options.sps)
  tests/test-options.sps` produces no output at all -- the working file is
  now byte-for-byte identical to the commit immediately before Task 8
  touched it.
- `tests/test-sxml-differential.sps` -- the same two assertions added,
  verbatim, with a new leading comment (matching this file's existing habit
  of explaining non-obvious placement, e.g. its own header on `(cmark gfm
  sxml)` alongside `(cmark gfm)`) explaining why they live here rather than
  in `tests/test-options.sps`; placed immediately before `(test-end
  "sxml-differential")`.
- `Makefile` -- `check-purity`'s loop restored to `tests/test-options.sps
  tests/test-ast.sps tests/test-sxml.sps`; the paragraph explaining why
  `test-options.sps` had dropped out (no longer true) removed; the sentence
  above it once again names all three suites instead of two.

### Verification

```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
%%%% Starting test options
# of expected passes      57
```
Exit 0. (57 = Task 8's 59 minus the 2 assertions moved out -- matches this
fix's own prediction.)

```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
%%%% Starting test sxml-differential
# of expected passes      32
```
Exit 0. (32 = Task 8's 30 plus the 2 assertions moved in -- matches.)

```
make check-purity
=== check-purity: tests/test-options.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
# of expected passes      57
purity holds: tests/test-options.sps pulled in no native code
=== check-purity: tests/test-ast.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
# of expected passes      30
purity holds: tests/test-ast.sps pulled in no native code
=== check-purity: tests/test-sxml.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
# of expected passes      28
purity holds: tests/test-sxml.sps pulled in no native code
```
Three "purity holds" lines -- the count the Makefile's original loop, and
Task 8's own Step 4, expected all along. `make test`: 13 suites, all `ALL
SUITES PASSED`, `test-options.sps` at 57, `test-sxml-differential.sps` at
32. `make check-pins`: pins agree.

### Proving the gate is real again -- two probes, not one

The fix brief asked to add `(cmark gfm)` back to `tests/test-options.sps`'s
imports and watch `make check-purity` fail. Doing exactly that -- only the
import, nothing else -- was tried first, and is recorded here because it
did NOT reproduce a failure. That negative result is more informative than
a second attempt at a positive one, per this project's own rule that a
check proves nothing until you have watched it both hold and fail for the
reason you expect.

**Probe 1 -- import only, nothing that calls a `(cmark gfm)`-exclusive
binding.** `md5` of the fixed, working-tree file before this probe:
`b40854d8456705a0c8ecc3ee29f828a0`. Edited in place (working tree, not a
scratch copy -- see Method note below) to add back only the import:
```diff
 (import (rnrs)
         (srfi :64)
+        (cmark gfm)
         (cmark gfm options)
         (cmark gfm private conditions))
```
No other line touched.

```
make check-purity
=== check-purity: tests/test-options.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
%%%% Starting test options
# of expected passes      57
purity holds: tests/test-options.sps pulled in no native code
```
**Gate held. No failure, contrary to what a literal reading of the fix
brief's step would predict.** Root cause: every binding this file actually
calls (`cmark-options-extensions`, `make-cmark-options`,
`cmark-invalid-option?`, `sxml-options-with`, etc.) is DEFINED in `(cmark
gfm options)` or `(cmark gfm private conditions)` and merely re-exported by
`(cmark gfm)` -- `src/cmark/gfm.sls`'s `export` clause names them, its
`library` body does not define them. Nothing in the file references a
binding `(cmark gfm)` itself defines, such as `markdown->sxml`. Per the
Makefile's own "Caveat proven while wiring this up" paragraph
(`Makefile:147-152`, untouched by this fix pass and written about
`options.sls`/`ast.sls` gaining an inert import): Chez instantiates an
imported library's body only when something actually references a binding
that library's own body defines -- not merely because the library appears
in an `import` form. A reference satisfied entirely through a re-export
never forces the re-exporting library's body to run, so `(cmark gfm
private native)`'s unconditional top-level shim load
(`src/cmark/gfm/private/native.sls:100`) never ran, and the poisoned
`CHEZ_CMARK_GFM_SHIM` was never read. Same mechanism the Makefile already
documents for a library gaining an inert import; this is the identical
effect one level up, in a `.sps` program's own import list, discovered
because probe 1 was tried before assuming the brief's literal step would
work.

Reverted immediately: copied the pre-probe backup back over
`tests/test-options.sps`; `md5` afterward: `b40854d8456705a0c8ecc3ee29f828a0`,
matching. `git diff --stat` at that point showed only this fix pass's
three intended files.

**Probe 2 -- import plus a call to a `(cmark gfm)`-exclusive binding,
reproducing Task 8's actual committed state.** `markdown->sxml` is defined
in `(cmark gfm)`'s own body, so restoring the two assertions that call it,
not just the import, should force instantiation. Rather than hand-retype
Deviation 2's mutation, the exact commit this fix pass is correcting was
restored verbatim: `git show HEAD:tests/test-options.sps >
tests/test-options.sps` (`HEAD` at the time of this fix pass is `f17407f`,
Task 8's own commit). `md5` after: `f5dfbd50aebbcf6f84ee469c9c4b92d2`; a
`diff` against the backup confirmed the only differences were the header
comment, the `(cmark gfm)` import, and the two `markdown->sxml` assertions
-- nothing else.

```
make check-purity
=== check-purity: tests/test-options.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
Exception occurred with condition components:
  0. &cmark-shim-unavailable: "/nonexistent"
PURITY VIOLATED: tests/test-options.sps failed with CHEZ_CMARK_GFM_SHIM poisoned
to a nonexistent path. Its import chain now reaches
(cmark gfm private native), which loads a shared object -- check
what it (or something it imports) just started pulling in.
=== check-purity: tests/test-ast.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
# of expected passes      30
purity holds: tests/test-ast.sps pulled in no native code
=== check-purity: tests/test-sxml.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
# of expected passes      28
purity holds: tests/test-sxml.sps pulled in no native code
make: *** [check-purity] Error 1
```
**PURITY VIOLATED -- exactly the exception Task 8's own Deviation 2 first
recorded** (same condition, same message, same exit path), and specific to
`tests/test-options.sps`: `tests/test-ast.sps` and `tests/test-sxml.sps`
both still hold in the same run, confirming the failure tracks that one
suite's import chain rather than some global effect of the poisoned
environment variable.

**Revert.** Copied the backup back over `tests/test-options.sps`; `md5`
`b40854d8456705a0c8ecc3ee29f828a0`, matching the pre-probe value exactly.
`git diff --stat` afterward: only `Makefile`, `tests/test-options.sps`, and
`tests/test-sxml-differential.sps` -- this fix pass's three intended files,
nothing left over from either probe. Re-ran `make check-purity`: three
"purity holds" lines again. Re-ran `make test`: 13 suites, `ALL SUITES
PASSED`. `make check-pins`: pins agree.

### Method note -- deviates from this file's default

This file's intro states the default method: copy the target library to a
scratch directory outside the repo and prepend it to `CHEZSCHEMELIBDIRS` so
only the mutated copy resolves, leaving the tracked file untouched
throughout. That method does not apply to either probe above: the thing
under test is `tests/test-options.sps` itself, passed directly as `chez
--program`'s argument inside `check-purity`'s loop -- `CHEZSCHEMELIBDIRS`
shadows *library* resolution, not a `--program` file's own path, so a
scratch copy placed anywhere on that variable would never be the file
`make check-purity` actually runs. A full clone of the repository outside
it, so that `make check-purity` could run there unmodified, would work but
costs re-running `deps`/`build` against a second checkout to verify a
two-line import change; editing the tracked file directly, under a
recorded `md5` before and after and an immediate revert, was judged the
more reliable option for this repository's small size and is the fallback
the fix brief itself names. Both probes were reverted before touching any
other file, confirmed by `md5` and `git diff --stat`, and neither left a
trace once complete.

---

## Task 9 — the corpus parser

One file under test, `tests/spec-corpus.sls` (brief Step 5, two mutations).
Method as stated above: scratch copy outside the repo, `CHEZSCHEMELIBDIRS`
prepended with the scratch directory so the mutated copy resolves first,
tracked file never touched.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps`: 34/34 passes, exit 0. `make test`: 13
suites, all `ALL SUITES PASSED`. `make check-purity`: three "purity holds"
lines (unaffected — `tests/spec-corpus.sls` is reached only from
`tests/test-sxml-differential.sps`, which was never in that gate's list).
`md5` of the tracked file at baseline and throughout both mutations below:
`52aadbced3ae6465875019eebaa04be8`, confirmed unchanged after every run.

### Note on Step 4's expected count

Step 4 predicts `# of expected passes 32` after this task's additions. The
actual, correct result is 34, confirmed two independent ways: counting
assertion names by hand, and mechanically —
`grep -c '^(agrees ' tests/test-sxml-differential.sps` → 27,
`grep -c '^(test-equal ' tests/test-sxml-differential.sps` → 7 (anchored at
column 0 to exclude the `agrees` helper's own internal `(test-equal name
…)` call, which a plain substring grep also matches), 27 + 7 = 34. The same
count against `git show HEAD:tests/test-sxml-differential.sps` (the file as
it stood before this task touched it) gives 27 + 5 = 32 — Step 4's number
describes the *pre-existing* file, before Step 1's two new assertions are
added, not the post-Step-1 result. Step 1's own code block is unambiguous
(exactly two new `test-equal` forms, no alternate placement offered the way
Task 8's Step 1/Step 5 genuinely conflicted), so there is no input choice
that both matches Step 1 literally and also lands on 32 — reaching 32 would
require dropping one of the two prescribed assertions or deleting two of
the file's 32 pre-existing ones, either of which is a worse and unjustified
deviation from the brief than leaving a stale summary number uncorrected.
Per this file's own precedent for self-inconsistent briefs (Task 4's "Note
on the differential test's import list"; Task 8's Deviation 1): the input
(Step 1's code, used verbatim) was kept; Step 4's prose expectation is
recorded here as stale documentation, not acted on. `# of expected passes
34` is confirmed by every run in this entry, including the un-mutated
baseline above.

### Mutation 1 — fence narrowed to 31 backticks

**Mutation** (brief Step 5.1): in a scratch copy only, narrow `fence` from
32 backticks to 31:

```diff
-  (define fence (make-string 32 #\`))
+  (define fence (make-string 31 #\`))
```

`tests/spec-corpus.sls` in the repo was never touched — only
`<scratch>/task9-mutation1/spec-corpus.sls` was edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/task9-mutation1:src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps`

**Result: FAIL, 32/34 — wider than the brief's Step 5.1 text predicts.**
Step 5.1 names only "the corpus parser finds every example"; both new
assertions fail:

```
FAIL the corpus parser finds every example
FAIL tab arrows are translated to tabs
# of expected passes      32
# of unexpected failures  2
```

**Root cause confirmed by direct probe, not merely inferred**
(`probe-mutation1.sps` and `probe-mutation1-counts.sps`, scratch-only).
`open-prefix` is derived from `fence` (`(string-append fence " example")`),
so narrowing `fence` to 31 backticks narrows `open-prefix` to 31 backticks
followed immediately by a space. A real opening-fence line has 32
backticks before its space, so `open-prefix`'s 32nd character (a space)
never matches the real line's 32nd character (still a backtick) — `prefix?`
rejects every real example header, `state` never becomes `'markdown`, and
`spec-examples` returns `'()` for all four files:

```
(0 0 0 0)
```

— "counts other than `(672 30 16 26)`", exactly as Step 5.1 predicts, and
the direct cause of "the corpus parser finds every example" failing. The
second failure is a downstream consequence of the same corruption, not an
independent signal about tab handling: with zero examples parsed, `(corpus
"spec.txt")` is `'()`, so `(apply string-append '())` is `""`, and
`(memv #\tab (string->list ""))` is `#f` — the "tab arrows are translated to
tabs" assertion's second conjunct fails not because a translation step
misbehaved, but because there is no corpus content left for it to observe
one way or the other. Confirmed directly:

```scheme
(spec-examples "vendor/cmark-gfm/test/spec.txt")  ; => ()
```

**Revert.** Confirmed via `md5 tests/spec-corpus.sls`
(`52aadbced3ae6465875019eebaa04be8`, unchanged) and `git status --short`
(file shown only as `??`, i.e. still untracked and unedited by the
mutation). Re-ran the suite through the ordinary, non-scratch command:
`CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-differential.sps` → `# of expected passes 34`, exit 0.

### Mutation 2 — the `arrows->tabs` call deleted

**Mutation** (brief Step 5.2): in a fresh scratch copy, stop translating
U+2192 to tab at the point a completed example is folded into `out`, while
leaving the `arrows->tabs` definition itself in place (nothing else calls
it):

```diff
             ((string=? fence l)
              (loop rest 'text '()
                    (if (eq? state 'text)
                        out
-                       (cons (arrows->tabs (apply string-append (reverse cur)))
+                       (cons (apply string-append (reverse cur))
                              out))))
```

`tests/spec-corpus.sls` in the repo was never touched — only
`<scratch>/task9-mutation2/spec-corpus.sls` was edited.

**Run:** `CHEZSCHEMELIBDIRS=<scratch>/task9-mutation2:src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps`

**Result: FAIL, 33/34 — exactly the assertion the brief names, nothing
wider. This is the assertion that proves the differential is structurally
blind to a uniformly-mistranslated corpus.**

```
FAIL tab arrows are translated to tabs
# of expected passes      33
# of unexpected failures  1
```

**"the corpus parser finds every example" stays green** (not in the
failure list; 33 of 34 passed, only the tab assertion failed) — the example
*count* is untouched by this mutation, since `arrows->tabs` only rewrites
characters inside an already-delimited example, never the delimiters
themselves. **No `agrees` (differential) assertion failed either** —
confirmed by the single-line failure list above, and independently by
`grep -rln "spec-corpus" tests/ src/`, which shows only
`tests/test-sxml-differential.sps` and `tests/spec-corpus.sls` itself
reference the library at all: no `agrees` fixture in this file is built
from corpus content, so none of them could observe this mutation even in
principle. That is exactly the property Step 5.2 exists to demonstrate:
with the translation deleted, a tab-significant example's Markdown source
still contains a literal U+2192 character instead of a tab, `ours` and
`theirs` are handed that identical (wrong) input, and would agree with each
other regardless of what cmark does with a real tab — the differential is
structurally incapable of catching this class of corruption, which is why
`tests/spec-corpus.sls` needs an assertion that inspects the corpus's own
characters directly rather than relying on downstream agreement.

**Revert.** Confirmed via `md5 tests/spec-corpus.sls`
(`52aadbced3ae6465875019eebaa04be8`, unchanged) and `git status --short`
(`??` only, still untracked and unedited). Re-ran the suite through the
ordinary, non-scratch command: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps` → `# of expected passes
34`, exit 0.

**Final reconfirmation for the task.** `git status --short` throughout both
mutations showed only this task's two intended files
(`tests/spec-corpus.sls` untracked, `tests/test-sxml-differential.sps`
modified) — never touched by either mutation or probe run. `make test`: 13
suites, all `ALL SUITES PASSED`. `make check-purity`: three "purity holds"
lines. `make check-pins`: pins agree. Scratch copies and probe scripts
deleted afterward.

---

## Task 10 — the full corpus differential

**Baseline**, at HEAD before this task's edits: `CHEZSCHEMELIBDIRS=src:tests:
build/scheme-libs chez --program tests/test-sxml-differential.sps`: 34/34,
exit 0. `make test`: 13 suites, all `ALL SUITES PASSED`. `make check-purity`:
three "purity holds" lines. `make check-pins`: pins agree.

**Method deviation, stated because the log's header promises one.** The
header's method — copy the *library* to a scratch dir and prepend it to
`CHEZSCHEMELIBDIRS` — does not apply here: all three of this task's mutation
targets (`divergence`, `cli-divergence`, `cli-flags`) are defined in the
suite *program* `tests/test-sxml-differential.sps`, not in a library, and
Chez's library resolver never consults `CHEZSCHEMELIBDIRS` for a `--program`
file. So the whole `.sps` was copied to `<scratch>/mut/`, mutated there, and
run by absolute path — **from the repo root**, because `corpus-dir`,
`tests/fixtures/`, and `tests/tmp/` are all relative. The tracked file was
never edited: `md5 tests/test-sxml-differential.sps` matched the unmutated
scratch copy (`764827967f8957e7900967ac542b512e`) after all three runs.

An unmutated scratch copy was run first, to prove the copy-and-run-by-
absolute-path rig itself reproduces the baseline rather than silently
skipping work: **47/47, identical to the repo file.** Without that control, a
mutant that failed because the rig was broken would look like a passing
mutation.

### Mutation 1 — `divergence` always reports "equal"

The guard that stops every other in-process assertion in the file from being
vacuous.

```diff
      (let ((a (ours md our-o)) (b (theirs md their-o)))
-       (if (string=? a b) #f (list 'ours a 'theirs b))))))
+       #f))))
```

**Run:** `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs CMARK_CLI=cmark-gfm
chez --program <scratch>/mut/mutation1.sps`

**Result: FAIL, 46/47 — exactly the named assertion, nothing wider.**

```
FAIL the comparator can detect a difference
# of expected passes      46
# of unexpected failures  1
```

The 46 that still passed are the point, not a consolation: every `agrees`
fixture, the whole 744-example sweep, and the option matrix all passed
**vacuously** against a comparator wired to "equal". One assertion stands
between this file and testing nothing at all.

### Mutation 2 — `cli-divergence` always reports "equal"

```diff
      (let ((a (ours md our-o)) (b (cli-html md their-o)))
-       (if (string=? a b) #f (list 'ours a 'cli b))))))
+       #f))))
```

**Result: FAIL, 46/47 — exactly the named assertion.**

```
FAIL the CLI comparator can detect a difference
# of expected passes      46
# of unexpected failures  1
```

Note that "every fixture agrees against the pinned CLI" stayed green under
this mutation, which is precisely why its own guard has to exist separately:
the parity assertion cannot detect a broken comparator, because a broken
comparator is indistinguishable from perfect agreement.

### Mutation 3 — `cli-flags` drops `-e table`

Proves the CLI leg actually *exercises* the options record's extension list
rather than accepting whatever the CLI happens to default to.

```diff
-              (cmark-options-extensions o))))
+              (filter (lambda (x) (not (eq? 'table x)))
+                      (cmark-options-extensions o)))))
```

**Result: FAIL, 46/47 — exactly the named assertion.**

```
FAIL every fixture agrees against the pinned CLI
# of expected passes      46
# of unexpected failures  1
```

`tests/fixtures/gfm.md` contains a table; without `-e table` the subprocess
renders it as a paragraph of pipes while our side renders `<table>`, so the
byte comparison fails. `tests/fixtures/core.md` is checked first and still
agrees, which confirms the failure is the table specifically and not a
wholesale breakage of the CLI invocation.

**The two discrimination guards stayed green under mutation 3**, as they
must: both seed their mismatch from an *empty* extension list, which `filter`
leaves empty. Guard and parity assertion therefore fail independently —
neither can mask the other.

**Revert.** The repo file was never edited, so revert is confirmed by
`md5 tests/test-sxml-differential.sps` (`764827967f8957e7900967ac542b512e`,
equal to the pre-mutation copy) and by `git status --short` showing only the
one intended `M` line throughout. Re-ran through the ordinary, non-scratch
command: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs CMARK_CLI=cmark-gfm
chez --program tests/test-sxml-differential.sps` → `# of expected passes 47`,
exit 0.

**Final reconfirmation for the task.** `make test`: 13 suites, all
`ALL SUITES PASSED`. `make check-purity`: three "purity holds" lines
(`tests/test-options.sps` 57, `tests/test-ast.sps` 30, `tests/test-sxml.sps`
28). `make check-pins`: pins agree. Scratch copies and probe scripts deleted
afterward.

---

## Task 10 fix pass — refusing every renderer-only cmark option

Closes a concern raised against Task 10: `markdown->sxml` silently ignored
`hardbreaks?` and `nobreaks?`. Both are cmark RENDERER options -- verified,
same basis as Task 8's `unsafe-html?` finding: `CMARK_OPT_HARDBREAKS`,
`CMARK_OPT_NOBREAKS`, and `CMARK_OPT_UNSAFE` appear only in
`vendor/cmark-gfm/src/cmark-gfm.h`, `src/main.c`, and the five renderer
files, never in `blocks.c`, `inlines.c`, or `parser.h` -- so none of them can
reach the AST `markdown->sxml` builds from. The decision: `markdown->sxml`
refuses all three under one rule rather than three special cases. SXML is a
different renderer with its own policies -- `raw-html` and `softbreak` on
`sxml-options` -- so there is exactly one channel per setting; accepting a
renderer flag silently would discard a setting the caller made explicitly.

### Files touched
- `src/cmark/gfm.sls` -- the guard already rejecting `unsafe-html? #t`
  (Task 8) extended with two more `(when ... (raise (make-cmark-invalid-
  option '<key> 'not-applicable)))` clauses, one each for `hardbreaks?` and
  `nobreaks?`; the preceding comment rewritten to explain all three
  together instead of `unsafe-html?` alone.
- `tests/test-sxml-differential.sps` -- two new `test-equal` assertions,
  `markdown->sxml rejects hardbreaks?` and `markdown->sxml rejects
  nobreaks?`, matching the existing `markdown->sxml rejects unsafe-html?`
  assertion's shape exactly (same `guard`, same condition-accessor pair),
  placed immediately before it.

### What must NOT change, and why it doesn't
The option-matrix sweep (`every fixture agrees under every option
configuration`) drives `ours`, which calls `markdown-ast->sxml` directly
against an `sxml-opts-for`-derived record (lines 44-51) -- never
`markdown->sxml`. The new guard lives entirely inside `markdown->sxml`'s
`case-lambda` body, a path the sweep never calls, so the sweep is
structurally unreachable from this change. Confirmed empirically below: it
stays green both before and after, and, in the mutation, even while a guard
it does not use is deliberately broken.

### Baseline and verification

**Baseline, at HEAD before this fix pass's edits.** Confirmed by stashing
this fix pass's two files and re-running, then restoring -- not assumed
from the task brief's stated number:
```
git stash push -u -m "task10-fixpass-verify-baseline" -- src/cmark/gfm.sls tests/test-sxml-differential.sps
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-sxml-differential.sps
%%%% Starting test sxml-differential
# of expected passes      47
git stash pop
```
47/47, exit 0 -- matches the concern's stated baseline. Edits restored
afterward; `git diff --stat` showed the same two files, same shape, as
before the stash.

**After this fix pass's edits:**
```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-sxml-differential.sps
%%%% Starting test sxml-differential
# of expected passes      49
```
49/49, exit 0 -- 47 + 2 new assertions, matches the concern's prediction
exactly; no reconciliation needed.

`make check-purity`: three "purity holds" lines (`tests/test-options.sps`
57, `tests/test-ast.sps` 30, `tests/test-sxml.sps` 28) -- unaffected, since
neither touched file is in the purity loop. `make test`: 13 suites, all
`ALL SUITES PASSED`, `tests/test-sxml-differential.sps` at 49. `make
check-pins`: pins agree.

### Mutation

**Method:** matches Task 8's own mutation of this same file: `gfm.sls` is a
top-level facade no `src/` library imports, so shadowing only it via a
prepended `CHEZSCHEMELIBDIRS` entry cannot desync any other library's
version. Scratch copy outside the repo, mirroring only the one file
(`<scratch>/mutation-task10fix/cmark/gfm.sls`). `md5` of the tracked file
before the copy was made: `1318444a8e5446b1d641286aa172829e`.

**Control run**, scratch copy UNMUTATED, prepended to `CHEZSCHEMELIBDIRS`:
```
CHEZSCHEMELIBDIRS=<scratch>/mutation-task10fix:src:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-sxml-differential.sps
# of expected passes      49
```
49/49, identical to the repo file -- proves the shadowing rig reproduces
baseline before trusting the mutated run.

**Mutation** (brief's instruction: delete the `hardbreaks?` guard only):
```diff
        (when (cmark-options-unsafe-html? o)
          (raise (make-cmark-invalid-option 'unsafe-html? 'not-applicable)))
-       (when (cmark-options-hardbreaks? o)
-         (raise (make-cmark-invalid-option 'hardbreaks? 'not-applicable)))
        (when (cmark-options-nobreaks? o)
          (raise (make-cmark-invalid-option 'nobreaks? 'not-applicable)))
```
Applied only to `<scratch>/mutation-task10fix/cmark/gfm.sls`; the tracked
`src/cmark/gfm.sls` was never edited.

**Run:**
```
CHEZSCHEMELIBDIRS=<scratch>/mutation-task10fix:src:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-sxml-differential.sps
```

**Result: FAIL, 48/49 -- exactly the named assertion, nothing wider.**
```
%%%% Starting test sxml-differential
FAIL markdown->sxml rejects hardbreaks?
# of expected passes      48
# of unexpected failures  1
```
No other assertion is named in the FAIL output, and the count is exactly
one short of 49, so both **"markdown->sxml rejects nobreaks?"** (the guard
this mutation left untouched still raises on `nobreaks? #t`) and **"every
fixture agrees under every option configuration"** (the option-matrix
sweep, which never calls `markdown->sxml` -- see above) stayed green,
exactly as predicted. The failure matched the predicted property on the
first run; no second, reason-isolating probe was needed.

**Revert.** The repo file was never edited, so revert is confirmed by `md5
src/cmark/gfm.sls` (`1318444a8e5446b1d641286aa172829e`, identical
throughout) and by `git diff --stat` showing only this fix pass's own two
intended files (`src/cmark/gfm.sls`, `tests/test-sxml-differential.sps`),
unchanged in shape, throughout the exercise. Re-ran the ordinary,
non-scratch command:
```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs CMARK_CLI=cmark-gfm chez --program tests/test-sxml-differential.sps
# of expected passes      49
```
exit 0. Scratch copy deleted afterward.

**Final reconfirmation for the task.** `git status --short` showed only
this fix pass's two intended files modified. `make check-pins`: pins agree.
`make check-purity`: three "purity holds" lines (57/30/28). `make test`: 13
suites, all `ALL SUITES PASSED`, `tests/test-sxml-differential.sps` at 49.
Scratch copy deleted afterward; no probe scripts left behind.

---

## Task 11 — `wak-sxml-tools` and the portability suite

**Baseline**, at HEAD before this task's edits (Task 10 fix pass's own final
state): `make test`: 13 suites, all `ALL SUITES PASSED`. `make check-purity`:
three "purity holds" lines (57/30/28). `make check-pins`: one "pins agree"
line (chez-srfi).

### Files touched
- `.gitmodules`, `vendor/wak-sxml-tools` (submodule, pinned `5c14730`),
  `vendor/wak-common` (submodule, pinned `6d495fc`, **not anticipated by the
  brief** — see below).
- `Akku.manifest` — version to `0.3.0`; `chez-srfi` moved from `depends` to
  `depends/dev`; `wak-sxml-tools` added to `depends/dev`. Verbatim per the
  brief.
- `Akku.lock` — regenerated by `akku lock` (it worked on this host). Now
  names four projects: `chez-srfi`, `wak-common`, `wak-ssax`,
  `wak-sxml-tools`. `wak-ssax` is a transitive dependency of the
  `wak-sxml-tools` Akku *package* that this task's own import chain never
  touches (confirmed below) — consumers who `akku install` get it anyway;
  it is not vendored as a submodule and not part of `check-pins`, matching
  this repo's existing "consumers install what Akku.lock names; CI tests the
  submodule" asymmetry.
- `Makefile` — `SXMLT_SRC`, `COMMON_SRC`; `deps` extended for both
  submodules; `check-pins` generalised to loop over three `(dir, name)`
  pairs instead of one.
- `tests/test-sxml-portability.sps` — new.

### Verify rather than assume (the two items the task instructions flagged)

**Directory layout.** `find vendor/wak-sxml-tools -name 'serializer*'` →
`vendor/wak-sxml-tools/sxml-tools/serializer.sls` and
`.../sxml-tools/upstream/serializer.scm`. The brief's assumed
`wak/sxml-tools/` layout does not exist; the repo root has no `wak/`
directory at all. `Makefile`'s symlink target corrected to
`$(SXMLT_SRC)/sxml-tools`.

**Exported name.** `grep -rn 'srl:sxml->' vendor/wak-sxml-tools/` confirms
`srl:sxml->html` is exported from `sxml-tools/serializer.sls` exactly as the
brief names it (alongside `srl:sxml->html-noindent`, `srl:sxml->xml`,
`srl:sxml->xml-noindent`, `srl:sxml->string`). No change needed.

### A third thing the brief could not verify: `wak-sxml-tools` is not self-contained

Importing `(wak sxml-tools serializer)` with only the `wak-sxml-tools`
submodule linked in fails immediately:
```
Exception: library (wak private include) not found
```
`sxml-tools/serializer.sls` `include-file`s `upstream/serializer.scm` through
`(wak private include)` — a library that lives in a *different* Akku
package, `wak-common`, not anywhere in `wak-sxml-tools`'s own tree. Confirmed
via `akku lock`, which resolved `wak-common` (and `wak-ssax`) as
`wak-sxml-tools`'s own transitive dependencies. `wak-common` was vendored the
same way (git submodule, pinned to the commit `akku lock` names,
`6d495fc` — upstream's own commit message: "Fix for Chez Scheme
compatibility, use native define-values", i.e. this exact commit is the one
Akku's registry chose specifically for Chez).

A second wrinkle inside `wak-common`: `(wak private include compat)` ships
one file per Scheme implementation (`compat.chezscheme.sls`,
`compat.guile.sls`, `compat.mosh.sls`, ...), each declaring the identical
library name `(wak private include compat)` — Akku's installer picks one and
installs it as `compat.sls`; bypassing that installer (the whole reason this
project vendors via submodule at all) means `make deps` must do the same
rename itself. Handled with one more `ln -sfn`, the same kind of filename
massaging `chez-srfi`'s percent-encoding fix already does for a different
naming convention. `wak-ssax` was never linked in at all and the suite still
imports and runs correctly (see Files touched above), confirming it is
genuinely unused by this one import chain, not merely untested.

This is not "a missing binding to work around" — `srl:sxml->html` exists and
works exactly as documented once its own real dependency is present. It is a
transitive-dependency gap the brief's author could not have found without a
working `akku lock` or a real clone, exactly the situation the task
instructions anticipated for the two flagged items, just a third instance.

### A fourth finding, more serious: the attribute-list marker is a different token

`markdown->sxml` marks an attribute list with `'\x40;` (`'@`) — ADR-0011, and
this project's own Global Constraints ("SXML's `@` attribute marker must be
written `\x40;` in source"). `wak-sxml-tools` does not recognise that marker
at all. Every place `sxml-tools/upstream/serializer.scm` looks for the
attribute list, it tests `(eq? (car node) '^)` — lines 263, 432, 841, 845 —
and its own comments call this explicitly "the SXML 3.0 aux-list" (432: `'^^`
is glossed "aux-list in SXML 2.X", `'^` "aux-list in SXML 3.0"). `modif.scm`
and `sxml-tools.scm` agree throughout. `'@` is not in R6RS's
`<special-initial>` set and so cannot be a bare R6RS identifier at all (which
is exactly why *this* project spells it `\x40;`); `'^` is, which is almost
certainly why the R6RS portification of this "same Lizorkin/Kiselyov lineage"
(design spec 7.1) made that substitution. Both are real SXML; they disagree
on one token.

Left unbridged, `srl:sxml->html` does not raise on an `'@`-marked tree — it
silently treats `'@` as an ordinary element name and nests the attribute
pairs as child elements instead of attributes:
```
(a (@ (href "/x")) "l")  =>  "<a><@><href>/x</href></@>l</a>"   -- WRONG
```
Confirmed this is not merely cosmetic by running the brief's own Step 4 code
completely unbridged (scratch copy,
`/private/tmp/.../scratchpad/no-bridge/test-sxml-portability-nobridge.sps`):
```
%%%% Starting test sxml-portability
FAIL a quote in an attribute value comes out escaped
# of expected passes      3
# of unexpected failures  1
```
Root cause: with `'@` unrecognised, the link's `title` value lands as
*element content* (escaped by `srl:string->char-data`, which handles only
`& < >`) rather than as an *attribute value* (escaped by
`srl:string->html-att`, which also handles `"` and `'`) — so `&quot;` never
appears and the assertion fails for real, not hypothetically. The other
three assertions happen to stay green regardless (`accepts?` only checks
`string?`; the script-tag and pre fixtures carry no attributes), which is
exactly the kind of "passes for the wrong reason" the Global Constraints
warn about elsewhere (the `#f`-as-expected-value rule) — here structurally
analogous, not textually the same rule.

Fixed with `attrs->caret`, a small test-only tree rewrite in
`tests/test-sxml-portability.sps` that rewrites `('\x40; (k v) ...)` to
`('^ (k v) ...)` wherever it appears (attribute pairs are always flat
`(key string)` pairs in this adapter's output, never nested SXML, so no
recursion into them is needed) and otherwise walks the tree unchanged.
`src/cmark/gfm/sxml.sls` is untouched — the adapter's public contract stays
`'@`, exactly as every other suite in this repo (including
`tests/test-sxml-differential.sps`'s 744-example corpus) already verifies.
This is a dialect bridge in test-only glue, not a weakened assertion: the
assertions are byte-for-byte what the brief specifies, and the tree fed to
the third-party tool differs from ours by exactly one substituted token,
applied uniformly, never touching an attribute *value*.

Confirmed the bridge is what fixes it, and fixes only that: re-running the
full brief-literal (unbridged) file above shows exactly one failure, the one
predicted; re-running with the bridge (below) shows all four green.

### The brief's own Step 4/Step 5 mismatch

The brief's Step 4 code defines exactly four `test-equal` forms ("a document
exercising every mapped node type is accepted", "a script tag in a text node
comes out escaped", "a quote in an attribute value comes out escaped", "pre
content survives with no injected indentation") — confirmed by `grep -c
test-equal` on the brief file itself. Step 5's prose claims "`# of expected
passes 5`". Per this file's own precedent for a self-inconsistent brief (fix
the input, not the expectation, and say so): the code, not the prose aside,
is what was implemented verbatim (modulo the `attrs->caret` bridge above);
no fifth assertion was invented to force the printed count to 5.

### Step 5 — green

```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-portability.sps
%%%% Starting test sxml-portability
# of expected passes      4
```
Exit 0. `make test`: 14 suites (13 + this one), all `ALL SUITES PASSED`.
`make check-purity`: unaffected, three "purity holds" lines (57/30/28) —
`test-sxml-portability.sps` is not in that loop (it is not meant to be
pure: `markdown->sxml` parses). `make check-pins`: three "pins agree" lines.

### Step 6 — the mutation, and why the brief's named location does not reach the property

**Method:** scratch copy outside the repo, mirroring only
`src/cmark/gfm/sxml.sls` (`<scratch>/mutation-task11/cmark/gfm/sxml.sls`),
suite run with that scratch directory prepended to `CHEZSCHEMELIBDIRS`. `md5`
of the tracked file before any copy was made: `c92e75c9760d52938a69af019a031224`.

**Control run**, scratch copy UNMUTATED:
```
CHEZSCHEMELIBDIRS=<scratch>/control-task11:src:tests:build/scheme-libs chez --program tests/test-sxml-portability.sps
# of expected passes      4
```
4/4, identical to the repo file — the shadowing rig reproduces baseline
before trusting the mutated run.

**Mutation, exactly as the brief's Step 6 text says** ("apply an HTML escape
in the `text` case"):
```diff
+  (define (html-escape s)
+    (let-values (((port get) (open-string-output-port)))
+      (string-for-each
+       (lambda (c)
+         (case c
+           ((#\&) (put-string port "&amp;"))
+           ((#\<) (put-string port "&lt;"))
+           ((#\>) (put-string port "&gt;"))
+           ((#\") (put-string port "&quot;"))
+           (else  (put-char port c))))
+       s)
+      (get)))
   ...
-      ((text)       (prop n 'literal))
+      ((text)       (html-escape (prop n 'literal)))
```
(escape set mirrors `tests/sxml-html-serializer.sls`'s own `escape-html`,
i.e. `houdini_escape_html0`, secure=0). Applied only to
`<scratch>/mutation-task11/cmark/gfm/sxml.sls`; the tracked file was never
edited.

**Run:**
```
CHEZSCHEMELIBDIRS=<scratch>/mutation-task11:src:tests:build/scheme-libs chez --program tests/test-sxml-portability.sps
```

**Result: the mutation does not fail. At all. 4/4, exit 0 — narrower than
the brief's Step 6 text predicts, all the way down to nothing.** This is not
"a different failure than predicted" (Tasks 1/3/7's pattern) — it is *no*
failure, so before accepting that, the actual tree the "script tag" input
produces was inspected directly (`markdown->ast` on `"A <script>alert(1)</script> B\n"`):
```
paragraph
  text        "A "
  html-inline "<script>"
  text        "alert(1)"
  html-inline "</script>"
  text        " B"
```
`<script>` and `</script>` are `html-inline` nodes — cmark's inline HTML
scanner (`inlines.c:handle_pointy_brace` → `scan_html_tag`) matches one
generic open/close tag at a time; there is no block-level "script eats
everything to its closing tag" rule here because the line does not open with
`<script` (it opens with `"A "`), so that rule (a *block*-level exception for
`<script>`/`<pre>`/`<style>`, irrelevant here) never engages. `html-inline`
nodes are rendered by `raw-html->sxml`, **not** the `text` case the brief
names — under `raw-html: escape` that function returns `(prop n 'literal)`
verbatim, completely untouched by this mutation. The three surrounding `text`
nodes ("A ", "alert(1)", " B") *are* touched by the mutation, but none
contains `& < > "`, so escaping them is a byte-for-byte no-op. Net effect of
the brief's exact, literal instruction: zero observable change.

**Isolating second probe, per this file's own precedent (Tasks 1, 3, 7):**
same `html-escape` helper, applied instead to the branch that actually
carries this literal — `raw-html->sxml`'s `escape` case — leaving the `text`
case untouched, in a fresh scratch copy:
```diff
   (define (raw-html->sxml n opts)
     (if (eq? 'escape (sxml-options-raw-html opts))
-        (prop n 'literal)
+        (html-escape (prop n 'literal))
         (list '*COMMENT* " raw HTML omitted ")))
```
**Result: FAIL, exactly the named assertion, nothing wider:**
```
CHEZSCHEMELIBDIRS=<scratch>/mutation-task11-probe2:src:tests:build/scheme-libs chez --program tests/test-sxml-portability.sps
%%%% Starting test sxml-portability
FAIL a script tag in a text node comes out escaped
# of expected passes      3
# of unexpected failures  1
```
3/4, exit 1 — one short, and a direct probe of the mutated `render` output
confirms the predicted shape precisely:
```
"<p>A &amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt; B</p>"
```
`&amp;lt;script&amp;gt;` — double-escaped, exactly as the brief's Step 6
text predicted, just reached through `raw-html->sxml` rather than the `text`
case. This is the property Step 6 exists to establish: literals reaching the
tree as bare Scheme strings — whether from a `text` node or, under
`raw-html: escape`, from an `html-inline`/`html-block` node's `'literal` —
must be carried verbatim, because escaping them a second time inside the
adapter corrupts the output the instant a real serializer also escapes them,
which is the whole security claim `raw-html: escape` rests on.

**Revert.** The repo file was never edited by either probe. Confirmed by
`md5 src/cmark/gfm/sxml.sls` (`c92e75c9760d52938a69af019a031224`, identical
throughout) and `git diff --stat src/cmark/gfm/sxml.sls` (empty). Re-ran the
ordinary, non-scratch command:
```
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-portability.sps
# of expected passes      4
```
exit 0.

### `check-pins`, confirmed it still fails on drift (not just confirmed it passes)

Generalising a check that cannot fail is worse than not having one. Tested
two ways, both reverted afterward:

**Via `Akku.lock`** (`sed` in place, `wak-common`'s hash corrupted to
`deadbee`):
```
pins agree: chez-srfi 7879b52
pins agree: wak-sxml-tools 5c14730
PIN DRIFT: wak-common submodule 6d495fcaf7250f414614b1979d1ac07904496970 but Akku.lock names deadbee.
make: *** [check-pins] Error 1
```
Exit 2. `Akku.lock` restored from a pre-edit copy; re-ran clean → three
"pins agree" lines, exit 0.

**Via a real submodule detach** (`chez-srfi`, which has enough history to
detach from; `wak-sxml-tools` is a single-commit repo upstream and so has
nowhere else to detach to):
```
PIN DRIFT: chez-srfi submodule c6891b61e9d015daa5b9237f4f4413c4279b3981 but Akku.lock names 7879b52.
make: *** [check-pins] Error 1
```
Exit 2. The other two pairs still reported "pins agree" in the same run,
confirming the loop evaluates all three independently rather than
short-circuiting. `chez-srfi` re-checked-out to `7879b52` and re-staged;
`git ls-files -s vendor/chez-srfi` and `make check-pins` both confirmed
clean afterward.

### Final reconfirmation for the task

`git status --short` shows exactly this task's intended files: `.gitmodules`,
`vendor/wak-sxml-tools`, `vendor/wak-common` (staged, new submodules);
`Akku.lock`, `Akku.manifest`, `Makefile` (modified); `tests/test-sxml-
portability.sps` (untracked, new). `make test`: 14 suites, all `ALL SUITES
PASSED`, `tests/test-sxml-portability.sps` at 4. `make check-purity`: three
"purity holds" lines (57/30/28), unchanged. `make check-pins`: three "pins
agree" lines. All scratch copies and probe scripts deleted afterward.

---

## Task 11a — the attribute marker becomes an option

ADR-0013. `sxml-options` gains `attribute-marker` (`caret` | `at`, default
`caret`); `src/cmark/gfm/sxml.sls` computes the marker symbol once at
`markdown-ast->sxml` and threads it as `mark` beside `opts` to the six sites
that build an attribute list; `tests/sxml-html-serializer.sls` accepts
either marker; `tests/test-sxml-differential.sps` runs the corpus sweep, the
option matrix, and the CLI leg once per marker;
`tests/test-sxml-portability.sps` drops its `@`→`^` rewrite.

### Method note

Both mutations ran in scratch copies OUTSIDE the repo,
`$SCRATCH/mut1` and `$SCRATCH/mut2`, each holding real copies of `src/` and
`tests/` and symlinks to the repo's `build/` and `vendor/`. `CMARK_CLI` was
set to `cmark-gfm`, the value `make -s deps-info` reports, because the
scratch copies carry no `Makefile`. Each copy was confirmed green before
being mutated: 64 / 31 / 17 / 5 / 50 across test-options, test-sxml,
test-sxml-serializer, test-sxml-portability, test-sxml-differential. The
repo's own files were never edited by either probe — confirmed afterward by
`git status --short` (empty).

### Mutation 1 — the marker constant ignores the option and always emits `^`

`src/cmark/gfm/sxml.sls`:
```
  (define (marker opts)
-   (if (eq? 'at (sxml-options-attribute-marker opts)) '\x40; '^))
+   '^)
```

Predicted: the `at`-dialect assertions fail by name, the `caret` ones stay
green.

```
test-options             exit=0  # of expected passes      64
test-sxml                exit=1  # of expected passes      30 # of unexpected failures  1
test-sxml-serializer     exit=0  # of expected passes      17
test-sxml-portability    exit=1  # of expected passes      4  # of unexpected failures  1
test-sxml-differential   exit=0  # of expected passes      50
```
```
FAIL attribute-marker at emits the specification's marker at every site
FAIL the at dialect carries the specification's own marker
```

Exactly the two `at` assertions, and only those: `test-sxml` lost one of
thirty-one, and the two it kept are "the default marker is a caret at every
attribute site" and "attribute-marker caret, spelled explicitly, agrees with
the default".

**`test-sxml-differential` does NOT move, and that is correct.** The marker
never reaches HTML bytes — `tests/sxml-html-serializer.sls` accepts both and
writes neither — so byte-identity against cmark cannot see this mutation at
all. The differential is not the guard for *which* marker is emitted; the
pure unit suites are. What the differential does guard is that everything
downstream of an attribute list still agrees under both dialects, which is
Mutation 2's subject.

**Inverse half — always emit `\x40;`** (same file, `'^` → `'\x40;`), to
confirm the `caret` assertions are not vacuous either:
```
=== test-sxml exit=1                    18 passes, 13 failures
FAIL only the first token of the fence info becomes the class
FAIL an empty title is omitted, a present one is kept
FAIL a URL is percent-encoded but ampersand and apostrophe pass through
FAIL dangerous schemes yield an empty href, in any case
FAIL data: is rejected except for the four image subtypes
FAIL image alt is the flattened plaintext of its children
FAIL an image title is omitted when empty and kept when present
FAIL an image src takes the same dangerous-URL policy
FAIL ol start is emitted only when it is not one
FAIL task items get a disabled checkbox, checked ones get the attribute
FAIL alignment renders on header and body cells alike, omitted when none
FAIL the default marker is a caret at every attribute site
FAIL attribute-marker caret, spelled explicitly, agrees with the default
=== test-sxml-portability exit=1        4 passes, 1 failure
FAIL a quote in an attribute value comes out escaped
=== test-sxml-differential exit=0       50 passes
```

That portability failure is the whole point of dropping the `@`→`^`
rewrite, so it is worth stating plainly. Handed a `@`-marked tree,
`srl:sxml->html` does not raise — "a document exercising every mapped node
type is accepted" still passes — it silently nests the attribute pairs as
child elements, so the link title lands in ELEMENT content and is escaped by
`srl:string->char-data`, which handles only `& < >`, instead of in an
ATTRIBUTE value escaped by `srl:string->html-att`, which also handles `"`.
Under the old suite, `attrs->caret` rewrote the marker before handing the
tree over, so that assertion passed no matter what the adapter emitted. It
now depends on the tree the library actually produces.

**Revert.** Scratch copy deleted; the repo file was never touched
(`git status --short` empty, `md5 src/cmark/gfm/sxml.sls` =
`8519fe697487660fb064c6a5a29f0cd8` before and after).

### Mutation 2 — the test serializer's attribute predicate accepts only `^`

`tests/sxml-html-serializer.sls`:
```
  (define (attributes? x)
-   (and (pair? x) (memq (car x) '(^ \x40;)) #t))
+   (and (pair? x) (eq? '^ (car x))))
```

Predicted: the `at`-marker corpus sweep fails. This is what proves the twin
sweep is real coverage rather than the same run twice — if the second leg
were not actually running under `at`, a serializer that could not read `at`
would go unnoticed.

```
test-options             exit=0  # of expected passes      64
test-sxml                exit=0  # of expected passes      31
test-sxml-serializer     exit=1  # of expected passes       9 # of unexpected failures  8
test-sxml-portability    exit=0  # of expected passes       5
test-sxml-differential   exit=1  # of expected passes      47 # of unexpected failures  3
```
```
FAIL every corpus example agrees in-process, under both markers
FAIL every fixture agrees under every option configuration, under both markers
FAIL every fixture agrees against the pinned CLI, under both markers
```

All three legs, and only under the second marker. SRFI-64's simple runner
prints no values, so the report was read back through a standalone probe in
the same scratch copy, running the same driver over `spec.txt`:

```
(marker at 111 "```ruby\ndef foo(x)\n  return 3\nend\n```\n"
 ours   "<pre><code><@><class>language-ruby</class></@>def foo(x)…</code></pre>\n"
 theirs "<pre><code class=\"language-ruby\">def foo(x)…</code></pre>\n")
```

`marker at` — so the `caret` leg agreed across all 672 `spec.txt` examples
first and the `at` leg then diverged at example 111, which is the two legs
being genuinely different runs. The report names the marker, the example
index, the failing input, and both renderings, which is what "structure it
so a failure still names which marker and which example diverged" asked for.

`test-sxml` is untouched, correctly: it is the PURE suite and never loads
the serializer. `test-sxml-portability` is untouched too — it serializes
through `wak-sxml-tools`, not through ours.

**Revert.** Scratch copy and probe deleted; the repo file was never touched
(`git status --short` empty, `md5 tests/sxml-html-serializer.sls` =
`6aaa92e67120d5e1988919acd85609a6` before and after).

### The non-vacuity guard on the twin-sweep driver itself

`per-marker` is the new harness, so it needs its own pin: a driver that
iterated an empty list, or only the default, would leave all three sweeps
passing while covering one dialect or none. `tests/test-sxml-differential
.sps` asserts it directly with a probe leg that fails for `at` only:

```scheme
(test-equal "the per-marker driver runs both markers and names the failing one"
  '(marker at probe-failed)
  (per-marker (lambda (m) (if (eq? 'at m) '(probe-failed) 'agree))))
```

Watched fail before it passed: the first version returned the bare symbol
`'probe-failed`, so `(cons 'marker (cons m r))` built the improper list
`(marker at . probe-failed)` and the assertion failed — which also confirmed
the assertion reads the driver's real output rather than a shape it was
written to match.

### Final reconfirmation for the task

```
test-options            64   test-sxml               31
test-sxml-serializer    17   test-sxml-portability    5
test-sxml-differential  50
```
`make test`: 14 suites, `ALL SUITES PASSED`. `make check-purity`: three
"purity holds" lines (64 / 30 / 31). `make check-pins`: three "pins agree"
lines. The 744-example corpus is byte-identical to cmark under both markers.

---

## Task 12 Step 0 — the cleanup pass

Eleven reviewed tasks each deferred their Minor findings to this pass. The
findings that touch code are fixed here in a handful of commits grouped by
kind. This entry covers the first group, "untested code paths" — the one the
dispatch instructions singled out as mattering most, because a code path
with no assertion is the same failure as an assertion that cannot fail.
Later groups (latent traps, stale comments, the Task 11/11a review items)
follow below. Method as stated at the top of this file throughout.

### Group 1 — untested code paths

#### `sxml-options`' `softbreak` field (`tests/test-options.sps`)

Seven assertions added, mirroring raw-html's seven exactly: default, valid
values, an `sxml-options-with` round-trip, unknown key, duplicate key,
invalid value, and that `sxml-options-with` validates too.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-options.sps`: 71/71 passes, exit 0 (64 pre-existing + 7 new).

**Mutation 1** — the exact clause the brief named, `src/cmark/gfm/options.sls`:
```diff
    (unless (memq (sxml-options-raw-html o) '(omit escape))
      (raise (make-cmark-invalid-option 'raw-html 'invalid-value)))
-   (unless (memq (sxml-options-softbreak o) '(newline break space))
-     (raise (make-cmark-invalid-option 'softbreak 'invalid-value)))
    (unless (memq (sxml-options-attribute-marker o) '(caret at))
```
**Result: FAIL, 69/71 — exactly the two predicted assertions, nothing wider.**
```
FAIL an unknown softbreak value is rejected
FAIL sxml-options-with validates softbreak too
```
This is options.sls:228 (the brief's own words: "deleting [it] currently
breaks nothing"); it now has two assertions that notice.

**Mutation 2** — the hardcoded default, `(lookup a 'softbreak 'newline)` →
`(lookup a 'softbreak 'break)` in `make-sxml-options`.
**Result: FAIL, 69/71 — wider than the single assertion "default softbreak
policy is newline" predicts, but through the same property.**
```
FAIL default softbreak policy is newline
FAIL sxml-options-with returns a new record with softbreak changed
```
The second assertion's own baseline reads `(sxml-options-softbreak
(default-sxml-options))` and expects `'newline`; moving the shared default
moves that baseline too, so both failures are the intended property (the
real default value), not a different one — no second probe needed.

**Mutation 3** — remove `softbreak` from `sxml-option-keys` entirely.
**Result: FAIL, 66/71 — wider still, and for two different reasons.**
```
FAIL softbreak can be set to break or space
FAIL sxml-options-with returns a new record with softbreak changed
FAIL a duplicate softbreak key is rejected
FAIL an unknown softbreak value is rejected
FAIL sxml-options-with validates softbreak too
```
The first two fail through the intended property (softbreak stops being
settable at all). The last three fail for a DIFFERENT reason than their own
names claim: with `softbreak` unrecognised, `plist->alist`'s unknown-key
check fires before duplicate-key or invalid-value is ever reached, so they
report `unknown-key`, not the property each is named for. Still a genuine
FAIL — SRFI-64 sees a value mismatch either way — but not proof of the
specific claim, so a narrower probe follows for the one most in need of it.

**Mutation 4 (isolating duplicate-key)** — `softbreak` restored to
`sxml-option-keys`; delete only `plist->alist`'s duplicate check:
```diff
            (unless (memq k valid-keys)
              (raise (make-cmark-invalid-option k 'unknown-key)))
-           (when (memq k seen)
-             (raise (make-cmark-invalid-option k 'duplicate-key)))
            (loop (cddr p) (cons k seen) (cons (cons k v) acc)))))))
```
**Result: FAIL, 67/71 — every "duplicate key" assertion across both option
records, softbreak's included, each for exactly the reason it claims** (a
`no-raise` sentinel from silent last-wins, not the expected condition):
```
FAIL a duplicate key is rejected rather than last-wins
FAIL a duplicate sxml key is rejected
FAIL a duplicate softbreak key is rejected
FAIL a duplicate attribute-marker key is rejected
```
Mutations 1 and 4 isolate softbreak's invalid-value and duplicate-key
assertions cleanly. "An unknown softbreak-shaped key is rejected" and the
valid-values/round-trip assertions ride the same generic `plist->alist`
mechanism raw-html's own sibling tests already exercise (confirmed jointly
failing in Mutation 3's five-wide result); they are not independently at
risk of being vacuous.

**Revert.** Only scratch copies (outside the repo) were ever edited.
`git diff --stat src/cmark/gfm/options.sls` empty after every mutation
above; `md5` unchanged throughout (`cb84dab86111612ff7ccaebe62f5b97a`).
Re-ran the ordinary command after each: 71/71, exit 0.

#### Nested-`strong` collapse and `softbreak` 'break/'space, pure suite (`tests/test-sxml.sps`)

Three assertions added: the nested-strong splice and both non-default
`softbreak` renderings, previously exercised only through the native shim
and the CLI in `tests/test-sxml-differential.sps`.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml.sps`: green (counts below fold in later mutations in this
same file; see the running total after each).

**Mutation 1** — `src/cmark/gfm/sxml.sls`'s `strong` case, dropping the
parent-type splice:
```diff
       ((strong)
-       (if (eq? 'strong parent-type)
-           (cons 'splice (children->sxml n opts mark tight?))
-           (element 'strong n opts mark tight?)))
+       (element 'strong n opts mark tight?))
```
**Result: FAIL, 1 failure — exactly the predicted assertion.**
```
FAIL a strong directly inside a strong collapses to one tag
```

**Mutation 2** — the `softbreak` case, collapsing all three policies to the
default:
```diff
-      ((softbreak)
-       (case (sxml-options-softbreak opts)
-         ((break) '(br))
-         ((space) " ")
-         (else    "\n")))
+      ((softbreak) "\n")
```
**Result: FAIL, 2 failures — exactly the two predicted assertions; the
pre-existing default-policy test stays green, as it must** (the default
still routes through `else`/the hardcoded `"\n"` either way):
```
FAIL softbreak 'break renders a br element
FAIL softbreak 'space renders a literal space
```

**Revert.** Scratch copies only. `git diff --stat src/cmark/gfm/sxml.sls`
empty after both mutations; `md5` unchanged throughout
(`8519fe697487660fb064c6a5a29f0cd8`, the same value Task 11a's final entry
recorded).

#### The adapter's `else` branch, distinct from `extension` (`tests/test-sxml.sps`)

**Mutation** — `sxml.sls`'s fallthrough, made to swallow instead of raise:
```diff
       ((extension)
        (raise (make-cmark-unsupported-node (prop n 'native-type))))
-      (else
-       ;; A node type this library produces but the adapter has not mapped.
-       ;; Reported through the same condition rather than silently dropped.
-       (raise (make-cmark-unsupported-node
-               (symbol->string (markdown-node-type n)))))))
+      (else '())))
```
**Result: FAIL, 1 failure — exactly "an unmapped node type raises via the
else branch, not extension"; the sibling "an extension node raises, carrying
its native type" stays green**, confirming the two assertions guard
genuinely different branches rather than one covering the other by
coincidence.

**Revert.** Scratch copy only; `md5` unchanged.

#### `markdown-ast->sxml`'s `sxml-options?` guard, pure suite (`tests/test-sxml.sps`)

**Mutation** — delete the guard:
```diff
       ((ast o)
-       (unless (sxml-options? o)
-         (raise (make-cmark-invalid-option #f 'invalid-value)))
        (node->sxml ast o (marker o) #f #f)))))
```
**Result: FAIL, 1 failure — exactly "markdown-ast->sxml rejects a
non-sxml-options second argument."** With the guard gone, `(marker o)` calls
`sxml-options-attribute-marker` on a `cmark-options` record, a bare R6RS
accessor type-mismatch; the test's `guard` catches it as `'wrong-condition`,
which fails against the expected `'(#f invalid-value)` — the same shape of
finding as Task 2's review-fix entry for `sxml-options-with`'s own guard.

**Revert.** Scratch copy only; `md5` unchanged.

#### `markdown->sxml`'s `cmark-options?` guard (`tests/test-sxml-differential.sps`)

This guard lives in `src/cmark/gfm.sls`, not the pure adapter, so it is
pinned in the differential suite alongside the sibling
hardbreaks?/nobreaks?/unsafe-html? guard tests.

**Baseline**, `CMARK_CLI=<pinned> CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps`: 51/51 passes (50
pre-existing + 1 new).

**Mutation** — delete the guard in the 3-argument clause of `markdown->sxml`:
```diff
       ((md o so)
-       (unless (cmark-options? o)
-         (raise (make-cmark-invalid-option #f 'invalid-value)))
```
**Result: FAIL, 50/51 — exactly "markdown->sxml rejects a non-cmark-options
second argument."**

**Revert.** Scratch copy only; `git diff --stat src/cmark/gfm.sls` empty;
`md5` unchanged (`1e50f9fc17b76d639ba412a3cc33f1de`).

#### Body-only and empty tables (`tests/test-sxml.sps`)

Two assertions added: a table with body rows but no header (the mirror of
the pre-existing "no body rows" test), and a table with no rows at all —
`table->sxml`'s fold's base case with both accumulators still empty, which
the pre-existing "no body rows" test does not reach (there, head is
non-empty).

**Mutation** — `table->sxml`'s head-emptiness check, made unconditional:
```diff
                (append
-                (if (null? head) '() (list (cons 'thead (reverse head))))
+                (list (cons 'thead (reverse head)))
                 (if (null? body) '() (list (cons 'tbody (reverse body)))))))
```
**Result: FAIL, 2 failures — exactly the two predicted assertions; the
pre-existing "no body rows" test (non-empty head) stays green**, confirming
it does not already cover the empty-head cases:
```
FAIL a body-only table emits no thead
FAIL a table with no rows at all emits neither section
```

**Revert.** Scratch copy only; `md5` unchanged.

#### URL edge cases and all four `data:image` subtypes (`tests/test-sxml.sps`)

Three changes: the pre-existing `data:image` assertion extended from two
subtypes (png, webp) to all four named in its own title (+gif, +jpeg); a new
assertion for a URL where every byte needs percent-encoding (the pre-existing
percent-encoding assertion mixes safe and unsafe bytes); and an attempted
"empty URL" assertion, which mutation testing found to be vacuous and which
was removed rather than kept — see below.

**Mutation 1** — `dangerous-url?`'s allowlist, gif and jpeg dropped:
```diff
-        ((or (prefix? "data:image/png"  u) (prefix? "data:image/gif"  u)
-             (prefix? "data:image/jpeg" u) (prefix? "data:image/webp" u))
+        ((or (prefix? "data:image/png"  u)
+             (prefix? "data:image/webp" u))
          #f)
```
**Result: FAIL, 1 failure — exactly "data: is rejected except for the four
image subtypes."** Confirms the extended fixture actually exercises the gif
and jpeg prefix checks, not merely the two the old fixture already covered.

**Mutation 2** — `href-safe-byte?`, made to accept every byte:
```diff
-  (define (href-safe-byte? b)
-    (let ((c (integer->char b)))
-      (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9)
-          (memv c href-safe-extra))))
+  (define (href-safe-byte? b) #t)
```
**Result: FAIL, 2 failures — the pre-existing mixed-bytes assertion and the
new all-unsafe-bytes one; nothing else moves:**
```
FAIL a URL is percent-encoded but ampersand and apostrophe pass through
FAIL a URL of entirely unsafe bytes is percent-encoded throughout
```

**The "empty URL" assertion — attempted, found vacuous, removed.** The
initial fixture asserted `(link "" "" ...)` renders `(href "")`. Mutation
attempt: make `dangerous-url?` treat the empty string as dangerous —
```diff
   (define (dangerous-url? url)
+    (or (string=? "" url)
     (let ((u (ascii-downcase url)))
       (cond
```
**Result: no failure. All 40 assertions still passed.** `percent-encode("")`
is `""` — the same value `safe-url` returns on the *rejected* branch — so
`safe-url("")` is `""` whichever branch runs, and this assertion cannot
distinguish "empty routes to encoding" from "empty routes to rejection." Per
this repo's own rule ("if no mutation can break the assertion, the assertion
is empty"), the fixture was removed rather than left as a green check that
proves nothing; `tests/test-sxml.sps` carries a comment recording the
attempt and this result in its place. This is the "judgement call" the
dispatch instructions anticipated for the portability suite's text-node
fixture, arising instead here.

**Revert.** Scratch copies only throughout this subsection; `md5` of
`src/cmark/gfm/sxml.sls` unchanged after every mutation
(`8519fe697487660fb064c6a5a29f0cd8`).

#### `*COMMENT*` inside `blockquote` and `li` (`tests/test-sxml-serializer.sps`)

Two assertions added for the other two members of `block-comment-parents`
(`*TOP*` already had a direct test; `p`, a non-member, already stood in for
"anywhere else").

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-serializer.sps`: 19/19 (17 pre-existing + 2 new).

**Mutation** — `tests/sxml-html-serializer.sls`'s `block-comment-parents`,
narrowed to `'(*TOP*)`.

**Result, first fixture (comment as blockquote's ONLY child): FAIL, 1 of 2
— only the `li` assertion moved.** The `li` fixture failed exactly as
predicted; the `blockquote` fixture did not fail at all. Root cause: unlike
`li`, `blockquote` is also in `cr-before-close`, which — with the comment as
blockquote's sole child — inserts the identical trailing newline before
`</blockquote>` regardless of whether the comment itself was treated as
block or inline. The fixture passed whether or not `blockquote` was even a
member of `block-comment-parents`, i.e. it was vacuous as originally
written.

**Fix and second probe.** The `blockquote` fixture was changed to give the
comment a plain-string sibling (`"x"`, which triggers no `cr` rule of its
own, unlike a `p` or another block element, either of which would have
reintroduced the same masking): `(blockquote (*COMMENT* " raw HTML omitted
") "x")`, expecting `"<blockquote>\n<!-- raw HTML omitted -->\nx\n</blockquote>\n"`
(confirmed against the real, unmutated serializer before use, not assumed).
Re-run under the same mutation:
```
FAIL a comment directly in a blockquote is a block comment
FAIL a comment directly in a list item is a block comment
# of expected passes      17
```
Both now fail, each for the intended reason. `tests/test-sxml-serializer.sps`
carries a comment recording why the fixture takes this shape.

**Revert.** Scratch copy only; `git diff --stat tests/sxml-html-serializer.sls`
empty; `md5` unchanged (`6aaa92e67120d5e1988919acd85609a6`, the same value
Task 3's entry recorded).

### Group 1 — final counts

```
test-options            71   test-sxml               39
test-sxml-serializer    19   test-sxml-portability     5
test-sxml-differential  51
```
`make test`: 14 suites, `ALL SUITES PASSED`. `make check-purity`: three
"purity holds" lines. `make check-pins`: three "pins agree" lines. The
744-example corpus stayed byte-identical to cmark under both markers
throughout (unchanged from Task 11a — nothing in this group touches parse
or render behaviour).

---

### Group 2 — latent traps (`tests/test-sxml-differential.sps`)

#### `write-file`'s transcoder — fixed, no new assertion

The brief's concern: `write-file` wrote through `(make-transcoder
(utf-8-codec))` — an unstated *native* eol-style — while `file->string`
reads with an explicit `eol-style none`, and native and none are not always
the same encoding (Windows' native is `crlf`; a CR-bearing fixture written
through one and read through the other could corrupt on the way to disk).

**Checked empirically before deciding what to do, per the dispatch
instructions' warning about assumed-but-unverified fixtures.** A standalone
probe (scratch-only, deleted after) wrote `"a\rb\r\nc\n"` through the exact
unmutated `write-file` transcoder and read the raw bytes back:
`#vu8(97 13 98 13 10 99 10)` — byte-identical to the input. **On this
platform (macOS/Darwin, Chez 10.4.1), the described divergence does not
reproduce**: `native-eol-style` here is `lf`, and a transcoder's eol
handling only recognises and re-encodes `#\linefeed`, not a bare `#\return`,
so CR passes through untouched regardless.

Given that, a fixture asserting the CR round-trip would be vacuous *on this
machine* — it would pass whether `write-file` used the native transcoder or
the corrected binary form, so it could never be watched to fail here. Rather
than add a green check that proves nothing on this platform, the fix was
applied without a new pinned assertion: `write-file` now writes
`(string->utf8 s)` to a binary port with no transcoder at all, mirroring
`tests/test-ast-differential.sps:338-341`'s `write-fixture` exactly. This
removes the platform-dependent assumption outright rather than leaving it
correct-by-luck — AGENTS.md commits this project to Windows portability, and
native-eol-style is `crlf` there by convention (inferred from that
commitment and from R6RS's native-eol-style contract, not independently
verified — this session has no Windows environment to check against).

No mutation log entry follows because there is no new assertion to defend;
this is recorded as "checked, found not to reproduce here, fixed anyway,
and why" per the instruction to say so rather than invent evidence.

#### `cli-flags` — fixed, with a new direct pin

**Baseline**, `CMARK_CLI=<pinned> CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program tests/test-sxml-differential.sps`: 52/52 passes, exit 0 (51
from Group 1 + 1 new).

`cli-flags` translated only the extension list; `--hardbreaks`, `--nobreaks`,
`--smart`, `--validate-utf8` are now translated too, mirroring
`tests/test-ast-differential.sps`'s `options->flags`. `--unsafe` is
deliberately left untranslated — `unsafe-html?` has no SXML-side equivalent
at all (`sxml-opts-for` never derives `raw-html` from it, and
`markdown->sxml`'s own guard refuses the option outright), so translating it
would produce a real, expected policy disagreement rather than closing one;
the comment above `cli-flags` in the test file says so.

This function is only ever called with `opts` (the all-defaults record) in
this file today, so nothing else here would notice a regression in the four
newly-translated flags — hence the direct pin, cheaper than round-tripping
the CLI: `"cli-flags translates every parse-level boolean cmark
understands"`, asserting the exact flag string for each of the four booleans
in isolation (each call sets `validate-utf8?` explicitly, since its own
default is `#t`, to keep each case isolated to the one flag it names).

**Mutation** — in a scratch copy of the `.sps` file (not a library, so run
directly rather than layered through `CHEZSCHEMELIBDIRS`), silence the
`nobreaks?` translation:
```diff
-         (if (cmark-options-nobreaks? o)      "--nobreaks " "")
+         (if #f                                "--nobreaks " "")
```
**Run:** `CMARK_CLI=<pinned> CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
chez --program <scratch>/test-sxml-differential.sps`
**Result: FAIL, 51/52 — exactly the named assertion.**
```
FAIL cli-flags translates every parse-level boolean cmark understands
```

**Revert.** The repo file was never edited — only the scratch copy was.
`md5 tests/test-sxml-differential.sps`: `473d6d026fd9798c55382b05ec8addfc`,
identical before the scratch copy was made and after the exercise; `git
diff --stat` against the last commit unchanged by the mutation (same 46
insertions / 4 deletions as this group's legitimate edits, before and
after). Re-ran the ordinary command: 52/52, exit 0.

### Group 2 — final counts

`tests/test-sxml-differential.sps`: 52 (was 51 after Group 1). All other
suites unchanged from Group 1's final counts. `make test`: 14 suites, `ALL
SUITES PASSED`. `make check-purity` and `make check-pins` hold. The
744-example corpus stayed byte-identical to cmark under both markers
throughout.

---

### Group 3 — stale or wrong comments

No mutation applies to this group: nothing here changes behaviour, so there
is no decision for a mutation to break. Each item was verified against the
actual source it cites (per the Global Constraint "read cmark semantics from
vendor/cmark-gfm/, never from recall") before being fixed, not merely
re-read and trusted.

- `src/cmark/gfm/private/conditions.sls:118` cited `conditions.sls:59-60`
  for the reason-symbol enumeration comment; it now lives at `:62-63`.
  Corrected the citation.
- `tests/test-sxml-differential.sps` claimed importing `(cmark gfm)` alone
  loads native code. Verified against `check-purity`'s own Makefile comment
  ("Chez only instantiates an imported library's body when something
  actually REFERENCES one of its bindings"): the claim is backwards for the
  import itself. What actually disqualifies this file from the pure suite
  is that its assertions CALL `markdown->sxml`, which runs the shim.
  Rewritten to say so; the conclusion (this file cannot be the pure suite)
  is unchanged.
- `sxml-opts-for`'s closing comment claimed "each renderer told what it
  says," but the function derives `softbreak` only -- `raw-html` is never
  set from `unsafe-html?`, because there is nowhere for it to go (see Group
  2's `cli-flags` finding: no sxml-options field corresponds to cmark's
  unsafe/raw passthrough at all). Rewritten to say what it actually derives
  and why it stops there.
- `sxml.sls`'s `dangerous-url?` comment attributed the data:image-checked-
  first ordering to re2c. Checked `vendor/cmark-gfm/src/scanners.re:345-354`
  directly: re2c's rules there are `'data:image/' (...)` then the bare
  `'data:'` alternation, and re2c compiles `_scan_dangerous_url` to a DFA
  resolved by **longest match**, not source order -- `data:image/png`
  wins because it is the longer match, not because it is listed first. The
  Scheme `cond` here really is first-match, so its own ordering
  requirement is real, just not for the reason stated. Rewritten to
  attribute each mechanism correctly; both still agree on this input.
- `sxml.sls`'s `list` case emits `start` only when it is not 1, with no
  citation, unlike every other requirement in the file. Added
  `html.c:173-183` (verified with line numbers via `grep -n`), matching the
  citation `tests/test-sxml.sps`'s own comment for the same rule already
  carries.
- `tests/spec-corpus.sls`'s header lacked the "not under src/, reachable via
  CHEZ_LIBDIRS" note both `tests/sxml-html-serializer.sls` and
  `tests/cmark-testing.sls` carry. Added it, matching their wording.
- `tests/spec-corpus.sls`'s closing-fence branch guards on `(eq? state
  'text)` before appending, which `vendor/cmark-gfm/test/spec_tests.py:104-
  114` does not do -- it appends unconditionally on every closing-fence
  line, guarded only by `'disabled' not in extensions`, a different axis.
  Without our guard, a bare 32-backtick line found outside any open example
  would append a spurious empty entry (Python would too, for the same
  reason: `cur`/`markdown_lines` are both `'()`/`[]` at that point). This
  makes the Scheme parser strictly more defensive than the Python and, in
  that one situation, produce fewer entries than a literal port would --
  inert for all four corpus files (none contains such a line, which is why
  the example counts still match Python's), but previously undocumented.
  Added a comment recording the divergence and why it does not show up in
  the counts.

**Verification.** `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez
--program tests/test-sxml.sps`: 39/39 (unchanged). `tests/test-conditions.sps`:
29/29 (unchanged). `tests/test-sxml-differential.sps`: 52/52 (unchanged).
`tests/test-ast-differential.sps`: 80/80 (unchanged, confirms
`spec-corpus.sls`'s new comment did not disturb its parsing).
`tests/test-differential.sps`: 28/28 (unchanged). Every count is identical
to its pre-Group-3 value, as a comment-only change requires.

---

### Group 4 — the Task 11/11a review items

#### Rename: "a script tag in a text node..." → "raw-html: escape" (`tests/test-sxml-portability.sps`)

No mutation: a rename changes what a failure would point at, not what the
assertion tests. The content arrives at the adapter as `html-inline`, not
`text` -- confirmed by the same reasoning the next item verifies directly
against `markdown->ast` -- so the old name would have pointed a future
failure at `sxml.sls`'s `text` case when the real culprit is
`raw-html->sxml`. Renamed; assertion body unchanged.

#### A genuine `text`-node fixture (`tests/test-sxml-portability.sps`)

**Verified before writing, not assumed** — the dispatch instructions warned
this is exactly where an earlier task's mutation was misplaced (`<script>`
arrives as `html-inline`, not `text`). A standalone probe (scratch-only,
deleted after) ran `(markdown->ast "a < b\n")` and dumped the tree:
```
document
  paragraph
    text literal="a < b"
```
One `text` node, literal `"a < b"` — "<" followed by a space matches none
of cmark's raw-HTML-tag patterns, so it stays text. Confirmed the SXML tree
carries it verbatim: `(*TOP* (p "a < b"))`.

**Baseline**, `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program
tests/test-sxml-portability.sps`: 5/5 (unchanged count — this group nets to
zero: +1 new text-node assertion, -1 relocated in Group 4's next item below,
the rename costing nothing).

**Mutation** — `src/cmark/gfm/sxml.sls`'s `text` case, made to pre-escape
`<` before the tree reaches the (real, third-party) serializer:
```diff
-      ((text)       (prop n 'literal))
+      ((text)       (list->string (apply append (map (lambda (c) (if (char=? c #\<) (string->list "&lt;") (list c))) (string->list (prop n 'literal))))))
```
**Result: FAIL, 1 failure — exactly "text: a literal needing escaping
survives to the serializer."** With the literal pre-escaped to `"a &lt; b"`,
`srl:sxml->html` escapes the `&` again on top of it (`&` is itself one of
the four characters `escape_html` — houdini's html.c-equivalent — always
escapes), producing `"a &amp;lt; b"`, which contains neither the plain nor
the once-escaped form the assertion checks for. The other four assertions
in this suite are unaffected: the "every mapped node type" fixture still
serializes to *some* string (pre-escaping doesn't make it invalid SXML);
`raw-html: escape` exercises `raw-html->sxml`, a different case entirely;
the attribute-quoting assertion never touches a text node; and `pre`
content is inserted via `code-block->sxml` as a literal `code` child, never
through the mutated `text` case at all.

**Revert.** Scratch copy only; `git diff --stat src/cmark/gfm/sxml.sls`
against the last commit unaffected by the mutation.

#### The "at dialect" assertion relocated to the pure suite (`tests/test-sxml.sps`)

No new mutation: this is a straight move, not a new property. The original
assertion (`tests/test-sxml-portability.sps`, "the at dialect carries the
specification's own marker") called `markdown->sxml` directly and compared
SXML structure — no `srl:sxml->html`, no third-party code at all — so it
belonged in the pure suite next to "attribute-marker at emits the
specification's marker at every site" all along, which already covers the
same tree via the `\x40;` spelling. The one property this assertion adds —
that the tree built under `'at` is genuinely `equal?` to one built from
`(string->symbol "@")`, not merely from a `\x40;` escape the reader happens
to agree with — was already proven non-vacuous in its original location:
Task 11a's mutation log (Mutation 1, "the marker constant ignores the
option and always emits `^`") records this EXACT assertion failing there,
alongside its sibling. Moving it to a new file and adapting it from
`markdown->sxml` on a markdown string to `markdown-ast->sxml` on this
file's own `doc`/`para`/`link`/`text` fixture helpers changes neither the
code path nor the property, so that evidence still applies; re-run to
confirm the adapted form still passes: `tests/test-sxml.sps`, 40/40.

#### The per-marker non-vacuity probe, strengthened (`tests/test-sxml-differential.sps`)

**The gap, demonstrated before being closed.** The existing probe
(`"the per-marker driver runs both markers and names the failing one"`)
asserts `(per-marker (lambda (m) (if (eq? 'at m) '(probe-failed) 'agree)))`
equals `'(marker at probe-failed)`. **Mutation** — `markers`, `'(caret at)`
→ `'(at)` (caret silently dropped from the sweep entirely):
```diff
-(define markers '(caret at))
+(define markers '(at))
```
**Result: FAIL, 1 of 53 — and it is NOT the existing probe.**
```
FAIL the per-marker driver visits both markers, in order
# of expected passes      52
```
The pre-existing probe stays green: with `markers` reduced to `'(at)`, the
same probe leg still returns `'(probe-failed)` on the one marker it is
ever given, producing the identical `(marker at probe-failed)` report --
proving the brief's finding directly, not merely citing it. Every corpus,
option-matrix, and CLI sweep in the file *also* stays green under this
mutation, because the `'at` dialect genuinely agrees with cmark on its own
-- meaning that, before this fix, a `markers` silently narrowed to one
dialect would have been caught by NOTHING in this file.

**The fix.** A second assertion, `"the per-marker driver visits both
markers, in order"`, records the actual visit sequence through a mutable
accumulator, independent of any leg's return value:
```scheme
(let ((visited '()))
  (per-marker (lambda (m) (set! visited (cons m visited)) 'agree))
  (reverse visited))
```
expected `'(caret at)`. Re-run against the same mutation above (already
shown): this is the one assertion that fails, exactly as intended.

**Revert.** Scratch copy of the `.sps` file only (run directly, not layered
through `CHEZSCHEMELIBDIRS`, matching Task 10's method for this same file).
`md5 tests/test-sxml-differential.sps`: `83e7db1bafff458f06172ffc94bf9fd5`,
unchanged before the scratch copy was made and after. Re-ran the ordinary
command: 53/53, exit 0.

#### `default-marker` derived from the library, not restated (`tests/test-sxml-differential.sps`)

```diff
-(define default-marker 'caret)
+(define default-marker (sxml-options-attribute-marker (default-sxml-options)))
```
No new assertion: every existing non-sweep assertion in this file already
uses `default-marker` and continues to, so the fix is covered by the file's
existing 53 assertions rather than a new one — its purpose is to keep this
constant from silently desyncing from the library's own default if that
default ever changes, not to pin a new decision. Re-run:
`tests/test-sxml-differential.sps`, 53/53, unchanged.

#### `check-pins`'s mechanism (`Makefile`)

Not a Scheme assertion, so no SRFI-64 mutation applies; verified instead by
corrupting `Akku.lock` directly and confirming the check still catches it,
per the dispatch instructions.

The old `lock=` extraction used `sed -n "/$$name/,/^$$/s/.../\1/p" | head -1`:
an unanchored `/$$name/` search that could match `$$name` as a substring
anywhere in the file, and a `,/^$$/` range that never terminates because
`Akku.lock` has no blank lines, so the range always ran to EOF. It read the
right hash for all three packages today only because each entry's own URL
line is the very next line matching the hash pattern after its own
`(name ...)` line — correct by file layout, not by the mechanism's own
logic. Rewritten to match the URL line whose LAST PATH SEGMENT starts with
`"name_"` (Akku's own tarball-naming convention), which can only match the
target package's own line regardless of what precedes it in the file:
```diff
-  lock=$$(sed -n "/$$name/,/^$$/s/.*akku\.[0-9]*\.\([a-f0-9]*\)_repack.*/\1/p" Akku.lock | head -1); \
+  lock=$$(sed -n "s#.*/$${name}_[^\"]*-akku\.[0-9]*\.\([a-f0-9]*\)_repack.*#\1#p" Akku.lock | head -1); \
```

**Verification 1 — the check still holds on real pins.** `make check-pins`:
```
pins agree: chez-srfi 7879b52
pins agree: wak-sxml-tools 5c14730
pins agree: wak-common 6d495fc
```

**Verification 2 — drift is still caught, per pair, on a corrupted copy.**
`Akku.lock` backed up (`md5 e3a66d01e7920562c94bd43a591fc403`), then edited
in place three times, once per pair, each time replacing only that pair's
hash with `deadbee` and restoring the backup before the next:

```
### chez-srfi's hash corrupted only ###
PIN DRIFT: chez-srfi submodule 7879b527f267f067416552fb989135ad1b4ea436 but Akku.lock names deadbee.
pins agree: wak-sxml-tools 5c14730
pins agree: wak-common 6d495fc
exit=2

### wak-sxml-tools's hash corrupted only ###
pins agree: chez-srfi 7879b52
PIN DRIFT: wak-sxml-tools submodule 5c1473052d306536f770b065ed65e72df4c5c16c but Akku.lock names deadbee.
pins agree: wak-common 6d495fc
exit=2

### wak-common's hash corrupted only ###
pins agree: chez-srfi 7879b52
pins agree: wak-sxml-tools 5c14730
PIN DRIFT: wak-common submodule 6d495fcaf7250f414614b1979d1ac07904496970 but Akku.lock names deadbee.
exit=2
```
Each corruption is caught by name, reports drift for exactly the corrupted
pair, leaves the other two agreeing, and exits non-zero (`make`'s wrapping
of the recipe's own `exit $$fail`). `Akku.lock` restored and reconfirmed
byte-identical afterward (`md5 e3a66d01e7920562c94bd43a591fc403`, matching
the backup and `git status --short Akku.lock` empty).

**A first attempt at documenting this inline (embedding shell comments
inside the recipe's backslash-continued command via `` `# ...` ``
command-substitution tricks) broke the recipe outright** --
`lock=$$(sed ...)`'s own output was swallowed as a bare command instead of
an assignment, "command not found". Reverted; the explanation was moved to
a plain Makefile-level comment block above the target instead, which is
this project's existing convention for documenting recipe internals (the
block above `check-purity:` does the same). Lesson for this session, not
worth a permanent AGENTS.md entry on its own — Task 12 Step 3 is out of
this report's scope and can judge that independently.

#### `make deps` links every `wak-common/private/*.sls`, not just `include.sls` (`Makefile`)

Confirmed real, not speculative: `vendor/wak-common/private/` ships
`define-values.sls`, `define-values.chezscheme.sls`, and `let-optionals.sls`
alongside `include.sls`; `grep` across `vendor/wak-sxml-tools` and
`vendor/wak-common` found no importer of `(wak private define-values)` or
`(wak private let-optionals)` today, so the gap is currently dormant, not
yet a failure — exactly why it is a *latent* gap and not a bug report.

```diff
-	ln -sfn $(abspath $(COMMON_SRC))/private/include.sls $(abspath $(SRFI_LIBS))/wak/private/include.sls
-	src=$(abspath $(COMMON_SRC))/private/include; dst=$(abspath $(SRFI_LIBS))/wak/private/include; \
+	src=$(abspath $(COMMON_SRC))/private; dst=$(abspath $(SRFI_LIBS))/wak/private; \
+	for f in $$src/*.sls; do ln -sfn "$$f" "$$dst/$$(basename "$$f")"; done
+	src=$(abspath $(COMMON_SRC))/private/include; dst=$(abspath $(SRFI_LIBS))/wak/private/include; \
 	for f in $$src/*; do ln -sfn "$$f" "$$dst/$$(basename "$$f")"; done
```

Not mutation-testable (no assertion; the fix is the check-to-comment
upgrade AGENTS.md already asks for). Verified instead: cleared
`build/scheme-libs/wak/private/*.sls`, re-ran `make deps`, confirmed all
four files are now linked (`define-values.sls`,
`define-values.chezscheme.sls`, `include.sls`, `let-optionals.sls`), and
re-ran `tests/test-sxml-portability.sps` (5/5) and
`tests/test-sxml-serializer.sps` (19/19) to confirm the wak-common-dependent
suites still resolve correctly through the widened link set.

### Group 4 — final counts

```
test-options            71   test-sxml               40
test-sxml-serializer    19   test-sxml-portability     5
test-sxml-differential  53
```
`make test`: 14 suites, `ALL SUITES PASSED`. `make check-purity`: three
"purity holds" lines. `make check-pins`: three "pins agree" lines.

---

### Item 5 — the deliberate exception, stated rather than fixed

`markdown->sxml` (`src/cmark/gfm.sls`) silently discards `source-positions?`
rather than rejecting it alongside `unsafe-html?`/`hardbreaks?`/`nobreaks?`.
Per the dispatch instructions, this is explicitly "state, not fix" — no
guard was added, only a comment explaining why the existing behaviour is
correct: `source-positions?` is a PARSE-level option that genuinely reaches
`markdown->ast` (unlike the three RENDERER-only options that are rejected
because they cannot reach the AST at all), and it is `markdown-ast->sxml`,
not this guard, that drops positions per ADR-0011. Accepting it costs
wasted parse work, not a downgraded security posture, which is why it is
let through rather than refused. The comment also records why the
differential suite is entitled to build `opts` from `default-cmark-options`
rather than `default-ast-options`: turning `source-positions?` on is
already pinned not to change the SXML output ("source-positions? does not
change the SXML", `tests/test-sxml-differential.sps`).

No mutation applies — nothing here changes behaviour. Verified the suite
this comment cites still exists and still passes:
`tests/test-sxml-differential.sps`, 53/53, unchanged. Full re-verification:
`make test` (14 suites, `ALL SUITES PASSED`), `make check-purity` (three
"purity holds" lines), `make check-pins` (three "pins agree" lines).

---

## Task 12 Step 0 — final counts for the whole cleanup pass

```
test-options            71   test-sxml               40
test-sxml-serializer    19   test-sxml-portability     5
test-sxml-differential  53
```
Every other suite (`test-conditions`, `test-ast`, `test-ast-differential`,
`test-convert`, `test-differential`, `test-lifecycle`, `test-native`,
`test-render`, `test-shim-loading`) is untouched by this pass and holds its
pre-existing count. `make test`: 14 suites, `ALL SUITES PASSED`. `make
check-purity`: three "purity holds" lines (71 / 30 / 40). `make
check-pins`: three "pins agree" lines. The 744-example corpus stayed
byte-identical to cmark under both attribute-marker dialects throughout —
nothing in this pass touches parse or render behaviour.

---

## Task 12 Step 4 — the completeness audit

Step 4 is the audit this file exists to make possible: every assertion added
across Tasks 1–12 cross-checked against the entries above and against design
spec §8.3's mutation table, with any assertion that has no recorded mutation
either given one or written down here as uncovered and why.

**Method for the cross-check.** The log is hard-wrapped, so a line-oriented
`grep` for an assertion name gives false negatives — the phrase is split
across lines in most entries. Whitespace was normalised across the whole file
first, then every `(test-equal …)`/`(test-assert …)` name in the five Stage 5
suites was matched against it, and each hit classified by context as a
recorded *failure* (`FAIL <name>` in a run transcript, or `**Result: FAIL …
exactly "<name>"**` in prose) or a mere "stays green" mention. A green mention
is not coverage.

**Method for the mutations below.** As stated at the top of this file: the
target file is copied to a scratch directory outside the repo, mirroring the
library path (`<scratch>/mut/cmark/gfm/sxml.sls`, `…/options.sls`,
`…/cmark/gfm.sls`, `<scratch>/mut/sxml-html-serializer.sls`), mutated only
there, and the suite run with that directory prepended to `CHEZSCHEMELIBDIRS`.
For the three `.sps` files and for the vendored third-party serializer the
whole file is copied to scratch and run directly, matching Task 10's and Group
4's method for the same reason (a program, not a library). The tracked files
were never edited: `git status --short` after the whole exercise showed only
this task's two intended test edits, and `md5` of every mutated source was
unchanged throughout — `src/cmark/gfm/sxml.sls`
`47dafb7c709a7e5917bfd836d93b531a`, `src/cmark/gfm/options.sls`
`cb84dab86111612ff7ccaebe62f5b97a`, `src/cmark/gfm.sls`
`2e4bfbb0dd3a9205f2bd2890f8516ca0`, `tests/sxml-html-serializer.sls`
`6aaa92e67120d5e1988919acd85609a6`. Baseline before every mutation, through
the unmutated scratch copies, so the harness itself is proved inert:
`test-sxml` 40, `test-sxml-serializer` 19, `test-options` 71,
`test-sxml-differential` 53, `test-sxml-portability` 5.

### What the audit found

Thirty-eight assertions were carrying no recorded mutation. Thirty-six of them
had one available and it was run; the remaining two were **vacuous** and were
rewritten. Nothing was recorded as legitimately uncovered — every property in
Stage 5 now has a mutation that breaks its assertion by name.

Two of the three findings the dispatch note flagged as *candidates* turned out
not to be gaps at all: the entries for them exist, just under names the plain
grep could not see across a line wrap. The third — the serializer suite — was
a real gap: Task 3's Mutation 1 took all 16 assertions down at once for a
reason its own entry rejects as too wide, and Mutation 1b named seven; the
other eight had never been watched to fail.

### Group A — `tests/test-sxml.sps` (`src/cmark/gfm/sxml.sls`)

Each row is one mutation, run alone, against the pure suite. Baseline 40.

| # | Mutation | FAIL, by name | Count |
|---|---|---|---|
| A1 | `heading`'s computed tag hardcoded to `'h1` | heading level picks the tag | 39/1 |
| A2 | `text` case pre-escapes `<` to `&lt;` | a text literal is carried unescaped | 39/1 |
| A3 | `emph` mapped to `i` | inline containers map to their HTML tags | 39/1 |
| A4 | `blockquote` mapped to `div` | blockquote wraps its blocks | 39/1 |
| A5 | `linebreak` renders `" "` instead of `(br)` | softbreak is a newline string, linebreak is a br element | 39/1 |
| A6 | `thematic-break` given an empty-string child | thematic break is a childless hr | 39/1 |
| A7 | `code-block`'s empty-info branch made unreachable | a code block with no info has a bare code element | 39/1 |
| A8 | `omit`'s comment text changed to `" raw html omitted "` | omit replaces raw HTML with cmark's comment | 39/1 |
| A9 | `raw-html->sxml`'s `escape` branch made unreachable | escape carries the literal through as text | 39/1 |
| A12 | `extension` raises with the literal `"unknown"` instead of the node's type | an extension node raises, carrying its native type | 39/1 |
| A14 | `ascii-downcase` replaced by the identity | dangerous schemes yield an empty href, in any case | 39/1 |
| A15 | `safe-url` entity-escapes `&` on top of percent-encoding | a URL is percent-encoded but ampersand and apostrophe pass through | 39/1 |

A14 and A15 also moved the differential — A14: `unsafe links agree`, the
option matrix, and the CLI leg; A15: `links agree`, `autolinks agree`, and the
in-process corpus sweep. Both are design spec §8.3 rows ("compare URL schemes
case-sensitively", "escape `&` in the adapter *and* the serializer") that had
no entry above.

**A10 / A11 — the document root, wide and narrow.** `(cons '*TOP* …)` →
`(cons 'body …)` fails **35 of 40** assertions, because every fixture in the
file is rooted at `*TOP*`. That is redundancy through one property, not
isolation, so a second, narrow mutation pins the half `"a document becomes
*TOP*"` uniquely owns — the empty document. `children->sxml`'s base case made
to yield `'("")` when it produced no children at all:

```
FAIL a document becomes *TOP*
# of expected passes      39
```
Nothing else moves: no other fixture in the suite routes a childless container
through `children->sxml`.

**A13 — `title=""` when the title is empty** (design spec §8.3 row 4).
`maybe-title` made unconditional. Wide for the same structural reason as A10 —
12 failures in the pure suite and 10 in the differential — because every link
and image fixture carries a title through the one shared helper. The named
assertion, `"an empty title is omitted, a present one is kept"`, fails first
and through exactly its own property; the rest fail through theirs (a byte
difference against cmark, in every URL, alt, and marker assertion whose
expected tree now carries an extra attribute).

**A16 — paragraphs keep their `p` inside a tight list** (design spec §8.3 row
1; Task 6's own mutation ran the *opposite* direction, leaking tightness
inward). The `paragraph` case's splice branch deleted:
```
test-sxml               34 passes, 6 failures  (a tight list has no p elements, a loose one does; tightness does not leak into a nested list; task items…; the three marker assertions)
test-sxml-differential  44 passes, 9 failures  (tight lists agree; ordered lists agree; ol start agrees; nested lists agree; task lists agree; a blockquote in a tight item keeps its own <p>; and all three sweeps)
```

### Group S — `tests/test-sxml-serializer.sps` (`tests/sxml-html-serializer.sls`)

The real gap. Baseline 19.

| # | Mutation | FAIL, by name | Count |
|---|---|---|---|
| S1 | `escape-html` loses its `"` rule | a text child is escaped like escape_html | 18/1 |
| S2 | `escape-html` gains a `'` rule (houdini's secure mode) | apostrophe and slash survive unescaped in text; a non-href attribute leaves apostrophe alone | 17/2 |
| S3 | `em` added to `cr-before-open` | inline elements nest without whitespace | 18/1 |
| S4 | `write-attributes` reverses the attribute list | attributes render in list order; a non-href attribute leaves apostrophe alone; img and input close XHTML-style with no newline | 16/3 |
| S5 | `attributes?` narrowed to `'(\x40;)` | either attribute marker opens an attribute list | 18/1 |
| S6 | `img`/`input` added to `void-tags-with-newline` | img and input close XHTML-style with no newline | 18/1 |
| S7 | `pre` added to `cr-after-open` | pre and code nest with no injected whitespace | 18/1 |
| S8 | `p` added to `block-comment-parents` | an inline comment gets none | 18/1 |

S2's and S4's second and third failures are through their own properties, not
side effects: `"a non-href attribute leaves apostrophe alone"` is precisely
about `escape-html` not touching `'`, and its fixture is the only other one
pinning attribute order. S5 narrows to `at` rather than to `caret` on purpose —
narrowing to `caret` breaks seven assertions (most fixtures in the file are
`\x40;`-marked), while narrowing to `at` breaks only the one assertion that
renders a `^`-marked tree, which is the isolating direction. Task 11a's
Mutation 2 recorded the wide direction (`test-sxml-serializer exit=1 9 passes,
8 failures`) without naming the eight.

### Group O — `tests/test-options.sps` (`src/cmark/gfm/options.sls`)

Baseline 71 before this step's new assertion, 72 after.

| # | Mutation | FAIL, by name |
|---|---|---|
| O1 | `raw-html`'s constructor default → `'escape` | default raw-html policy is omit; sxml-options-with returns a new record |
| O2 | `make-sxml-options` ignores a supplied `raw-html` | raw-html can be set to escape; an unknown raw-html value is rejected; sxml-options-with sets the marker and carries raw-html through |
| O3 | `plist->alist`'s unknown-key check deleted | an unknown key is rejected; an unknown key is named in the condition; cmark-options-with rejects an unknown key; an unknown sxml key is rejected; an unknown softbreak-shaped key is rejected; a misspelled attribute-marker key is rejected |
| O4 | `validate-sxml`'s `raw-html` clause deleted | an unknown raw-html value is rejected; sxml-options-with validates too |
| O5 | `attribute-marker`'s constructor default → `'at` | the default attribute marker is caret; sxml-options-with sets the marker and carries raw-html through |
| O6 | `make-sxml-options` ignores a supplied `attribute-marker` | attribute-marker accepts both names; an unknown attribute-marker value is rejected |
| O7 | `validate-sxml`'s `attribute-marker` clause deleted | an unknown attribute-marker value is rejected; sxml-options-with validates attribute-marker too |

Each secondary failure is through the named property, not a side effect: O1's
and O5's second failure reads the shared default as its own baseline, O2's and
O6's second failure is the invalid value never reaching the record to be
rejected. O3 is the generic mechanism both option records share, which is why
it takes every unknown-key assertion in the file down at once and why Group 1
above could reach only the duplicate-key half.

#### The one real hole: `sxml-options-with`'s carry-through

**O8 / O10** — replacing `(lookup a 'attribute-marker (sxml-options-attribute-marker o))`,
and separately `(lookup a 'softbreak (sxml-options-softbreak o))`, with the
constructor's hardcoded default:

```
# of expected passes      71     (both mutations, no failures at all)
```

**Nothing noticed.** `sxml-options-with` could have rebuilt two of its three
fields from the defaults instead of from its argument and the suite stayed
green, because every base record any functional-update assertion started from
already held the default for whatever field the update did not name — so no
assertion could tell "carried from `o`" apart from "rebuilt from the default."
Only `raw-html`'s carry-through was pinned, by `"sxml-options-with sets the
marker and carries raw-html through"` (**O9**, the same mutation applied to
`raw-html`, fails it 70/71).

Rewritten rather than recorded as uncovered. One assertion added to
`tests/test-options.sps`, whose base sets *both* other fields to non-default
values and whose update names neither:

```scheme
(test-equal "sxml-options-with carries softbreak and attribute-marker through"
  '(space at escape)
  (let* ((base    (make-sxml-options 'softbreak 'space 'attribute-marker 'at))
         (updated (sxml-options-with base 'raw-html 'escape)))
    (list (sxml-options-softbreak updated)
          (sxml-options-attribute-marker updated)
          (sxml-options-raw-html updated))))
```

Re-run of O8 and of O10 against it, each alone:
```
FAIL sxml-options-with carries softbreak and attribute-marker through
# of expected passes      71
# of unexpected failures  1
```
Exactly the new assertion, in both directions, nothing wider. Unmutated: 72.

### Group D — `tests/test-sxml-differential.sps`

Baseline 53. `CMARK_CLI` from `make -s deps-info`.

| # | Mutation | Where | FAIL, by name |
|---|---|---|---|
| D1 | the `strikethrough` case deleted, so it falls to the `else` raise | `sxml.sls` | no corpus example raises unsupported-node (+ emphasis agrees, tables with inline content agree, and all three sweeps) |
| D2 | the `unsafe-html?` guard deleted | `gfm.sls` | markdown->sxml rejects unsafe-html? |
| D3 | the `nobreaks?` guard deleted | `gfm.sls` | markdown->sxml rejects nobreaks? |
| D4 | the `hardbreaks?` guard deleted | `gfm.sls` | markdown->sxml rejects hardbreaks? |
| D5 | the `heading` case emits `data-sourcepos` when the node carries a position | `sxml.sls` | source-positions? does not change the SXML |
| D6 | `sxml-opts-for` derives `raw-html` from the `tagfilter` extension | the `.sps` | tagfilter does not change the SXML (+ paragraphs agree, raw html agrees, all three sweeps) |
| D7 | `per-marker` drops the marker from its report | the `.sps` | the per-marker driver runs both markers and names the failing one |

D2 closes design spec §8.3's "let `markdown->sxml` accept `'unsafe-html? #t`",
which Task 8's entry did **not** cover: its mutation made the guard raise
*unconditionally*, which fails the sibling `"accepts an explicit unsafe-html?
#f"` and leaves `"rejects unsafe-html?"` green, as its own text says.

D5 and D6 close §8.3's two no-effect rows, which Task 8 addressed with probes
rather than mutations. Two false starts are worth recording, because both look
like the obvious mutation and neither works:

- Emitting `data-sourcepos` from `element` rather than from `heading` changes
  nothing: the fixture is `"# h\n\n| a |\n| --- |\n| 1 |\n\n- [x] t\n"`, whose
  heading, table, list, and tight-list item all bypass `element` entirely.
- Deriving the SXML policy from the extension list inside `markdown->sxml`
  changes nothing either: the differential's `ours` calls `markdown-ast->sxml`
  with `sxml-opts-for`'s record directly and never goes through
  `markdown->sxml`. `sxml-opts-for` is where the realistic regression lives —
  its own comment exists to explain why it derives `softbreak` and stops — and
  mutating it there is what the assertion notices.

### Group P — `tests/test-sxml-portability.sps`

**P1 — an attribute value left as a symbol** (`(list 'align align)` in place of
`(list 'align (symbol->string align))`), which is the shape `srl:sxml->html`
rejects rather than merely renders differently:
```
FAIL a document exercising every mapped node type is accepted
# of expected passes      4
```

#### The second vacuous assertion: `pre` content

`"pre content survives with no injected indentation"` was
`(contains? (render "```\n  indented\n\tтаb\n```\n") "  indented\n")`.

Three mutations were needed to find out that it could not fail, and the third
proves it:

- **P2** — `code-block->sxml` emits `div` instead of `pre`: **5/5, no
  failure.** `srl:sxml->html` suppresses indentation for any element with a
  bare-text child, independently of the tag.
- **P3** — the literal wrapped in a `span`, so `code` has no bare-text child:
  **5/5, no failure.** `pre` is in the serializer's own whitespace-sensitivity
  list, which still applies.
- **P4** — the vendored third-party serializer itself, copied to scratch
  (`<scratch>/mut/wak/sxml-tools/{serializer.sls,upstream/serializer.scm}`,
  confirmed live by first substituting a sentinel into the list and watching
  the copy take effect), turned into an *unconditional pretty-printer*: the
  `'("pre" "script" "style" "textarea")` exemption replaced, **and** the
  bare-text-child rule neutered. Neither edit alone is enough — this is design
  spec §11's "pretty-printing serializer" made real. **Still 5/5, no failure.**

Probed directly, mutated against unmutated:
```
mutated   "<pre>\n  <code>\n      indented\n\tтаb\n\n  </code>\n</pre>"
unmutated "<pre><code>  indented\n\tтаb\n</code></pre>"
```
The `<pre>` content is thoroughly corrupted — and `"  indented\n"` is *still a
substring of it*, because the injected indent is four spaces landing
immediately in front of the content's own two. The probe matched the exact
corruption it existed to detect. Design spec §11 leans on this assertion
("`test-sxml-portability.sps` asserts our chosen serializer does not do it"),
and the assertion was empty.

Rewritten to equality against the whole rendering, which cannot be satisfied
by a prefix:
```scheme
(test-equal "pre content survives with no injected indentation"
  "<pre><code>  indented\n\tтаb\n</code></pre>"
  (render "```\n  indented\n\tтаb\n```\n"))
```
Re-run under P4:
```
FAIL pre content survives with no injected indentation
# of expected passes      4
# of unexpected failures  1
```
Unmutated: 5/5. The scratch copy of the third-party tree was deleted
afterwards; `vendor/wak-sxml-tools` was never touched (`git status --short`
and `git submodule status` both clean).

### Assertions covered under an older name, not uncovered

Two look absent from this file until the rename is followed through, and both
are recorded above under the name they actually failed under:

- `"raw-html: escape"` (portability) — Task 11's isolating second probe records
  `FAIL a script tag in a text node comes out escaped`; Group 4 renamed it.
- `"attribute-marker at agrees with the specification's own (string->symbol
  \"@\")"` (`test-sxml.sps`) — Task 11a's Mutation 1 records
  `FAIL the at dialect carries the specification's own marker`; Group 4 moved
  it from the portability suite to the pure suite unchanged.

### Design spec §8.3, row by row

| Planned mutation | Recorded where |
|---|---|
| Emit `(p …)` inside tight lists | **A16** (Task 6's own is the inverse direction) |
| Open `<tbody>` for every body row | Task 7, Mutation 1 |
| Omit `align` on body cells | Task 7, Mutation 2 |
| Emit `title=""` when the title is empty | **A13** |
| Percent-encode `&` in the adapter | Task 5, Mutation 1 |
| Escape `&` in the adapter *and* the serializer | **A15** |
| Use the whole fence info as the class | Task 4, Mutation 2 |
| Flatten image `alt` without descending | Task 5, Mutation 3 |
| Drop the `data:image/*` carve-out | Task 5 Mutation 2; Step 0 Group 1 Mutation 1 |
| Compare URL schemes case-sensitively | **A14** |
| Append newlines unconditionally in the serializer | Task 3, Mutations 1 and 1b |
| Make the corpus parser match zero examples | Task 9, Mutation 1 |
| Make the differential comparator always return equal | Task 10, Mutations 1 and 2 |
| Let `markdown->sxml` accept `'unsafe-html? #t` | **D2** (Task 8's mutation is the inverse) |
| Give `tagfilter` an effect on the tree | **D6** |

All fifteen rows are now covered; six of them by this step.

### Final counts

```
test-options            72   test-sxml               40
test-sxml-serializer    19   test-sxml-portability     5
test-sxml-differential  53
```
`test-options` is +1 (the carry-through assertion); `test-sxml-portability`
holds at 5 (the `pre` assertion was rewritten, not added to). Every other
suite is unchanged from Step 0's final counts. `make test`, `make
check-purity`, `make check-pins`, and `make test-memory` are recorded in
Step 5's entry below.

---

## Task 12 Step 5 — the release gate

`CMARK_CLI` from `make -s deps-info | sed -n 's/^cmark-gfm CLI *: //p'` →
`cmark-gfm`. Platform: macOS (Darwin 25.5.0), arm64; Chez Scheme 10.4.1;
`cmark-gfm` 0.29.0.gfm.13 via pkg-config.

```
$ make test
… 14 suites …
test-ast-differential  80   test-ast               30   test-conditions   29
test-convert           66   test-differential      28   test-lifecycle    22
test-native            54   test-options           72   test-render       35
test-shim-loading      10   test-sxml-differential 53   test-sxml-portability 5
test-sxml-serializer   19   test-sxml              40
ALL SUITES PASSED

$ make check-purity
purity holds: tests/test-options.sps pulled in no native code   (72)
purity holds: tests/test-ast.sps pulled in no native code       (30)
purity holds: tests/test-sxml.sps pulled in no native code      (40)
exit 0

$ make check-pins
pins agree: chez-srfi 7879b52
pins agree: wak-sxml-tools 5c14730
pins agree: wak-common 6d495fc
exit 0

$ make test-memory
macOS: ASan preload only; LeakSanitizer is unsupported on arm64.
Leak claims must come from Linux CI (ADR-0003).
… all 13 instrumented suites, same counts as above minus test-differential …
exit 0
```

`make test-memory` runs every suite except `tests/test-differential.sps`
under the AddressSanitizer preload, `tests/test-sxml-differential.sps`
included — `markdown->sxml` parses, so that path is instrumented here even
though the adapter itself allocates nothing native. No ASan report on any
suite.
