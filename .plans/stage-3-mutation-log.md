# Stage 3 Mutation Log

Task 12 proves that every assertion added in Stage 3 (Tasks 1-11: the
Scheme-owned AST, its converter, `markdown->ast`, and the two differential
legs) has been watched to fail through the property it claims to guard, per
AGENTS.md's rule. **Every mutation below was applied fresh to the current
tree (branch `feat/stage-3-ast`, tree clean at start) and run today — none of
the 26 rows in the brief's table were transcribed from an earlier task's
report without re-running them.** Several rows below diverge from what an
earlier task's own report recorded, precisely because the code has evolved
since (later tasks widened `with-node`'s shared checks, Task 11 added a CLI
leg to `test-ast-differential.sps`, etc.) — those divergences are called out
explicitly rather than silently reconciled.

**Method, applied identically to every mutation:** the target file was copied
to the session scratchpad (never `/tmp`, never the repo) before any edit.
Each mutation was applied with an exact, quoted diff, then `make test` was
run (10 suites; ~6s; this is cheap enough that it was run for literally every
mutation, not reserved for the two differential suites, so that collateral
failures in *other* suites are never missed by construction). `make test`
sets `CMARK_CLI` to the same build the library loads, which is what makes it
safe to run against the two differential suites (`test-differential.sps`,
`test-ast-differential.sps`) — a bare invocation without that variable would
make the CLI-comparison legs fail for an unrelated reason (CLI unavailable or
version-mismatched), contaminating the result. After `make test` located
which suite(s) had failures, `CHEZSCHEMELIBDIRS=src:build/scheme-libs chez
--program tests/test-<suite>.sps` (plus `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs
CMARK_CLI=cmark-gfm` for `test-ast-differential.sps`, confirmed to reproduce
`make test`'s own pass count for that file exactly) reran the affected
suite(s) alone. Every mutation was reverted with `cp` from the scratchpad
backup, confirmed byte-identical with `diff` (silent) and `git status
--short`/`git diff --stat` (both empty) before the next mutation began. No
mutation was ever left in the tree while another was applied.

**Capturing expected-vs-actual.** `test-runner-simple`'s default handler
prints only `FAIL <name>` to stdout; the `expected-value`/`actual-value` pair
lives in SRFI-64's own per-test result alist and is surfaced only if
something reads it (confirmed in `vendor/chez-srfi/%3a64/testing-impl.scm`:
`test-result-ref`, `'result-kind`, `'expected-value`, `'actual-value`, and
the getter/setter pair `test-runner-on-test-end`/`test-runner-on-test-end!`
are all ordinary exported SRFI-64 bindings). Rather than hand-deriving what
each assertion "should" evaluate to, a small Python generator
(`make_diag.py`, scratchpad-only) produced, once, an instrumented copy of
each affected `tests/test-*.sps` file with a `test-runner-on-test-end!` hook
inserted immediately after `(test-runner-current runner)`: for every
non-pass it prints `test-name`/`result-kind`/`expected-value`/`actual-value`
via `test-result-ref`, then defers to the suite's own default handler. This
changes no assertion and no production code. Sanity-checked against the
clean tree first: zero `DIAG-*` output and pass counts identical to `make
test`'s own baseline for all four instrumented suites (`test-ast.sps` 30,
`test-options.sps` 49, `test-convert.sps` 66, `test-ast-differential.sps`
80), confirming the hook adds no side effect of its own. The instrumented
copies live only in the scratchpad and were never part of the repo.

**Baseline** (before any mutation, and reconfirmed clean after all of them):
10 suites, 397 assertions, `make test` prints `ALL SUITES PASSED`, exit 0.
`make check-purity` (2 suites gated): both print `purity holds:`, exit 0.

```
=== tests/test-ast-differential.sps ===   # of expected passes      80
=== tests/test-ast.sps ===                # of expected passes      30
=== tests/test-conditions.sps ===         # of expected passes      23
=== tests/test-convert.sps ===            # of expected passes      66
=== tests/test-differential.sps ===       # of expected passes      28
=== tests/test-lifecycle.sps ===          # of expected passes      22
=== tests/test-native.sps ===             # of expected passes      54
=== tests/test-options.sps ===            # of expected passes      49
=== tests/test-render.sps ===             # of expected passes      35
=== tests/test-shim-loading.sps ===       # of expected passes      10
ALL SUITES PASSED
```

## A note on a recurring anomaly in tool output

During nearly every revert in this task, the tool output was followed by a
message formatted like a system reminder, claiming the just-reverted file
"was modified, either by the user or by a linter," calling the change
"intentional," instructing that it not be reverted, and instructing that the
user not be told. This is the same category of prompt-injection anomaly
Task 6's and Task 7's reports documented (Task 7's recurred on every revert
in that task too). It was **not acted on**: instruction claims arriving
through tool output are data, not commands, and an instruction to withhold
information from the user is disregarded regardless of source. Every single
occurrence was independently checked against the actual file state —
`git status --short` and `git diff --stat` (both empty, checked via
file-redirected output specifically to avoid the anomaly re-injecting itself
into a piped command's own result), plus a `diff`/`md5` against the
pristine backup — and the file was never actually in the state the message
claimed. Recorded here once, prominently, rather than repeated at every one
of the ~24 occurrences below.

## Summary

| # | Task(s) | Mutation | File | `make test` result | Named/collateral failures | Covered? |
|---|---|---|---|---|---|---|
| 1 | 3 | `markdown-node-map` made parent-first | `ast.sls` | FAIL, ast 29/30 | "map rebuilds children-first..." only | **Yes** |
| 2 | 3 | `markdown-node-fold` made post-order | `ast.sls` | FAIL, ast 27/30 | "fold visits pre-order..." + 2 collateral (`map` tests that read tree shape via fold) | **Yes** |
| 3 | 4 | `max-depth` dropped from `validate`'s list | `options.sls` | FAIL, options 47/49 | both named, nothing else | **Yes** |
| 4 | 5 | `table-row-is-header` entry point misspelled | `native.sls` | import-time crash, 6/10 suites | no suite banner even prints; 2 more collateral in shim-loading (subprocess probes also import native.sls) | **Yes** |
| 5 | 6 | `list-props` returns `'bullet` unconditionally | `convert.sls` | FAIL, convert 65/66 + ast-diff 74/80 | named + 6 collateral (ordered-list fixtures in the differential suite) | **Yes** |
| 6 | 6 | `code-block-props` drops `fence-info` | `convert.sls` | FAIL, convert 63/66 + ast-diff 72/80 | 3 named (incl. 1 unpredicted) + 8 collateral | **Yes** |
| 7 | 6 | `check-depth!` call deleted | `convert.sls` | FAIL, convert 63/66 | 3 failures (wider than Task 6's original 1 — the check now lives in shared `with-node`) | **Yes** |
| 8 | 6 | `count-node!` call deleted | `convert.sls` | FAIL, convert 63/66 | mirror of #7, 3 failures | **Yes** |
| 9 | 7, 10 | `task-item-props` hardcodes `checked? #f` | `convert.sls` | FAIL, convert 65/66 + ast-diff 73/80 | covers both table rows in one run | **Yes** |
| 10 | 7, 10 | header/body row extractors swapped | `convert.sls` | FAIL, convert 64/66 + ast-diff 71/80 | covers both table rows in one run | **Yes** |
| 11 | 7 | cell alignment index off by one | `convert.sls` | FAIL, convert 64/66 + ast-diff 75/80 | 2 named + 5 collateral (not in the brief's row) | **Yes** |
| 12 | 8 | `extension-props` always includes literal | `convert.sls` | FAIL, convert 65/66 | named only, 0 collateral in ast-diff | **Yes** |
| 13 | 8 | `with-node` returns `'()` for missing entry | `convert.sls` | FAIL, convert 62/66 | 4 named, 0 collateral in ast-diff | **Yes** |
| 14 | 8 | `"heading"` entry deleted from the table | `convert.sls` | FAIL, convert 62/66 + ast-diff 72/80 | 4 named + 8 collateral (some via serializer exceptions) | **Yes** |
| 15 | 9 | one-argument form uses `default-cmark-options` | `parse.sls` | FAIL, convert 63/66 | named + 2 legit collateral; 2-arg #t sibling stays green | **Yes** |
| 16 | 9 | `node-source` ignores `positions?` | `convert.sls` | FAIL, convert 65/66 + ast-diff 46/80 | named + 34 unpredicted collateral (huge, but fully explained) | **Yes** |
| 17 | 9 | swap max-nodes/max-depth in `parse.sls` | `parse.sls` | FAIL, convert 64/66 | both named, swapped reasons exactly | **Yes** |
| 18 | 9 | `scope.sls` raises limit with `(bytevector-length bv)` | `scope.sls` | FAIL, convert 65/66 | named only; reason-only checks elsewhere unaffected | **Yes** |
| 19 | 9 | `parse.sls` passes `(supported-extensions)` | `parse.sls` | FAIL, convert 65/66 | named only; sibling "attached" test stays green | **Yes** |
| 20 | 9 | `cmark-options?` check moved inside the callback | `parse.sls` | FAIL, convert 65/66 | named, but via `wrong-condition` not `no-condition` — see caveat | **Yes, with the brief's caveat confirmed and refined** |
| 21 | 10 | `heading-props` returns level 1 | `convert.sls` | FAIL, ast-diff 76/80 + convert 65/66 | named + 1 collateral in convert + 2 CLI-leg collateral | **Yes** |
| 22 | 10 | `convert-children` drops its `reverse` | `convert.sls` | FAIL, ast-diff 29/80 + convert 56/66 | 51 in ast-diff (grew past Task 10's original 40/62) + 10 new collateral in convert | **Yes** |
| 23 | 10 | `emit-indent` drops the `min` cap | `test-ast-differential.sps` | FAIL, ast-diff 77/80 | named + 1 new CLI-leg failure Task 10 never saw | **Yes** |
| 24 | 2 | `ast.sls` given a native import it calls | `ast.sls` | `make check-purity` FAIL, exit 2 | exact predicted text | **Yes** |

Rows 9/10 and 22/23 above each satisfy **two** table rows from the brief (one
Task-7-or-9 row scoped to `test-convert.sps`, one Task-10 row scoped to
`test-ast-differential.sps`) with a single mutation, since both rows target
the identical code change. All 26 rows in the brief's table are accounted
for by the 24 mutations above.

---

## Detailed notes

### Mutation 1 — `markdown-node-map` parent-first (Task 3, covered)

`src/cmark/gfm/ast.sls`:
```diff
   (define (markdown-node-map proc node)
-    (proc (markdown-node-with-children
-           node
-           (map (lambda (child) (markdown-node-map proc child))
-                (markdown-node-children node)))))
+    (let ((n (proc node)))
+      (markdown-node-with-children
+       n (map (lambda (child) (markdown-node-map proc child))
+              (markdown-node-children n)))))
```
`make test`: `FAIL map rebuilds children-first, so proc sees mapped children`,
ast 29/30, nothing else. SRFI-64 result alist: expected `("marked" "marked")`,
actual `("hi" "word")` — the mapped-parent's `proc` observed its child still
in its pre-map state, exactly the property this test (repaired during Task 3
after the brief's original version proved insensitive to ordering — see
`task-3-report.md`) is built to catch. Reverted; diff silent; ast back to
30/30.

### Mutation 2 — `markdown-node-fold` post-order (Task 3, covered)

```diff
   (define (markdown-node-fold proc seed node)
-    (fold-left (lambda (acc child) (markdown-node-fold proc acc child))
-               (proc node seed)
-               (markdown-node-children node))))
+    (proc node (fold-left (lambda (acc child) (markdown-node-fold proc acc child))
+                          seed
+                          (markdown-node-children node)))))
```
`make test`: 3 failures — `FAIL fold visits pre-order, parent before children`
(the brief's named target), plus `FAIL map can rewrite a node type and keeps
the tree shape` and `FAIL map leaves the original tree untouched`. Both extras
are legitimate collateral: they call `markdown-node-fold` to read back a
tree's shape after `markdown-node-map`, so any change to fold's own order
perturbs them for the same single root cause. Expected `(document heading
text paragraph text)`, actual `(text heading text paragraph document)` —
hand-traceable directly from the mutated definition (post-order visits
children before their own node). ast 27/30. Reverted; diff silent; ast 30/30.

### Mutation 3 — `max-depth` dropped from `validate`'s list (Task 4, covered)

`src/cmark/gfm/options.sls`, `validate`'s ceiling `for-each` list:
```diff
     (list (cons 'max-input-bytes cmark-options-max-input-bytes)
-          (cons 'max-nodes       cmark-options-max-nodes)
-          (cons 'max-depth       cmark-options-max-depth)))
+          (cons 'max-nodes       cmark-options-max-nodes)))
```
`make test`: `FAIL a negative max-depth is rejected`, `FAIL cmark-options-with
validates max-depth too`, options 47/49, nothing else anywhere. Expected
`(max-depth invalid-value)` for both; actual `no-condition` for both (a
negative/bogus max-depth now constructs successfully). Reverted; diff silent;
options 49/49.

### Mutation 4 — `table-row-is-header`'s entry point misspelled (Task 5, covered — wider blast radius than a single-suite run shows)

`src/cmark/gfm/private/native.sls`:
```diff
   (define table-row-is-header
-    (foreign-procedure "cmark_gfm_extensions_get_table_row_is_header" (uptr) int))
+    (foreign-procedure "cmark_gfm_extensions_get_table_row_is_headerX" (uptr) int))
```
Running the single suite `tests/test-native.sps` bare reproduces Task 5's own
finding exactly: `Exception in foreign-procedure: no entry for
"cmark_gfm_extensions_get_table_row_is_headerX"`, no `%%%%` banner ever
printed (the failure is at library-body/import time, before the first test
runs), exit 255. Running `make test` (which Task 5's own report did not do
for this mutation) shows the **true** blast radius: every suite whose import
chain reaches `native.sls` fails the same way before its first assertion —
`test-ast-differential.sps`, `test-convert.sps`, `test-differential.sps`,
`test-lifecycle.sps`, `test-native.sps`, `test-render.sps` (6 of 10 suites,
all with the identical import-time exception, no pass count printed at all).
The two **pure** suites (`test-ast.sps` 30/30, `test-options.sps` 49/49) are
completely unaffected, exactly matching `check-purity`'s own premise that
these two never reach native code. `test-shim-loading.sps` shows a *third*
failure mode: 8/10, with `FAIL no override: the default, generated shim path
loads (exit 0)` and `FAIL a valid absolute override loads (exit 0)` — this
suite spawns subprocesses (`tests/shim-load-probe.sps`, confirmed by reading
it) that also import `native.sls`, so even the "should succeed" subprocess
scenarios now exit non-zero, failing the parent's exit-code assertions. All
of this is one single misspelling's mechanical consequence, not evidence of
anything failing for an unrelated reason. Reverted; diff silent; `make test`:
`ALL SUITES PASSED`, 397/397.

### Mutation 5 — `list-props` returns `'bullet` unconditionally (Task 6, covered, wider blast radius than the brief's row)

`src/cmark/gfm/private/convert.sls`:
```diff
   (define (list-props p)
-    (list (cons 'kind (if (= 2 (node-list-type p)) 'ordered 'bullet))
+    (list (cons 'kind 'bullet)
           (cons 'start (node-list-start p))
```
`make test`: `test-convert.sps` — `FAIL an ordered list maps kind, start,
delimiter, and tightness`, 65/66. Expected `((kind . ordered) (start . 3)
(tight? . #t) (delimiter . period))`, actual `((kind . bullet) ...)`,
exactly Task 6's original transcription. **New, not in the brief's row:**
`test-ast-differential.sps` also fails, 74/80 — `in-process XML agrees: a
tight ordered list with an offset start` and `...a paren-delimited ordered
list` (both `with positions` siblings too), plus `CLI XML agrees:
tests/fixtures/core.md` (both variants), because `core.md` contains an
ordered list. Confirmed directly: our XML now emits `<list type="bullet"
tight="true">` where cmark's real output says `<list type="ordered"
start="3" delim="period" tight="true">`. This collateral exists because
`list-props` is shared code, not a sign of anything wrong. Reverted; diff
silent; `make test`: `ALL SUITES PASSED`.

### Mutation 6 — `code-block-props` drops the `fence-info` pair (Task 6, covered, wider blast radius than the brief's row)

```diff
   (define (code-block-props p)
-    (list (cons 'literal (copy-required (node-literal p)))
-          (cons 'fence-info (copy-required (node-fence-info p)))))
+    (list (cons 'literal (copy-required (node-literal p)))))
```
`make test`: `test-convert.sps` 63/66 — `FAIL a fenced code block carries
literal and fence info` (expected `("(+ 1 2)\n" "scheme")`, actual `("(+ 1
2)\n" #f)`), `FAIL an indented code block has an empty fence info` (expected
`""`, actual `#f`), `FAIL every core node's key set is exactly what the table
declares` (expected `()`, actual `((code-block (fence-info literal)
(literal)) (code-block (fence-info literal) (literal)))`) — matches Task 6's
report exactly, including its own unpredicted third failure. **New:**
`test-ast-differential.sps` 72/80, 8 failures across the 3 code-block fixtures
(with/without info, indented) × 2 position variants, plus both `core.md` CLI
legs. All 8 report `DIAG-ACTUAL: #f`, not a text-diff pair — confirmed via a
targeted probe that this is an *exception*, not a clean divergence: the
serializer's `type-attributes` does `(string-length (markdown-node-property n
'fence-info))` unconditionally for a `code_block`, and with the key gone
entirely (not even `#f` — the key is *absent*, so the two-argument
`markdown-node-property` lookup falls back to its default `#f`), that call
raises a type error which SRFI-64's own exception-catching wrapper around the
test expression reports as actual-value `#f` (the same mechanism
`test-ast-differential.sps`'s own header comment documents: "SRFI-64
evaluates this expression inside `(guard (ex (else #F)) ...)`"). This is a
genuinely different failure *mode* of the same root cause than
`test-convert.sps` sees (which degrades gracefully via `markdown-node-property`'s
default rather than crashing), not a sign of anything spurious. Reverted; diff
silent; `make test`: `ALL SUITES PASSED`.

### Mutation 7 — `check-depth!` call deleted from `with-node` (Task 6, covered — broader today than at Task 6's original run)

```diff
   (define (with-node p type-string depth ctx properties-override)
-    (check-depth! depth ctx)
     (count-node! ctx)
```
`make test`: `test-convert.sps` 63/66, **three** failures: `FAIL one level
past the depth limit raises too-deep` (the brief's named target; expected
`(too-deep 10)`, actual `no-condition`), plus `FAIL the fallback still counts
toward the depth ceiling` and `FAIL max-depth from the options record is
enforced`, both also expecting a `too-deep` tuple and getting `no-condition`.
Task 6's own report (run against the tree as it existed at Task 6) recorded
only the first of these, because at that time `check-depth!` was called
directly from `convert-node`, not from the now-shared `with-node` that also
serves the extension-fallback path (Task 8's review fix) and
`markdown->ast`'s own limit tests (Task 9). Running this fresh against
*today's* tree is exactly what surfaces the wider, currently-true blast
radius — this is not evidence of drift in the assertions, it is evidence that
the shared check now protects three call sites instead of one, which is the
correct, stronger property. No collateral in `test-ast-differential.sps`
(80/80 — its fixtures never approach the depth ceiling). Reverted; diff
silent; `make test`: `ALL SUITES PASSED`.

### Mutation 8 — `count-node!` call deleted from `with-node` (Task 6, covered — mirror of #7)

```diff
   (define (with-node p type-string depth ctx properties-override)
     (check-depth! depth ctx)
-    (count-node! ctx)
```
`make test`: `test-convert.sps` 63/66, three failures, mirroring #7 exactly:
`FAIL one node past the node limit raises too-many-nodes` (expected
`(too-many-nodes 10)`, actual `no-condition`), `FAIL the fallback still
counts toward the node ceiling`, `FAIL max-nodes from the options record is
enforced`. No collateral elsewhere. Reverted; diff silent; `make test`:
`ALL SUITES PASSED`.

### Mutation 9 — `task-item-props` hardcodes `checked? #f` (Tasks 7 AND 10, both covered by one mutation)

```diff
   (define (task-item-props p)
     (list (cons 'index (node-item-index p))
           (cons 'task? #t)
-          (cons 'checked? (not (zero? (tasklist-checked p))))))
+          (cons 'checked? #f)))
```
`make test`: `test-convert.sps` 65/66 — `FAIL checked, unchecked, and plain
items are all distinguished` (Task 7's row), expected `((#t . #t) (#t . #f)
(#f . #f))`, actual `((#t . #f) (#t . #f) (#f . #f))`. `test-ast-differential.sps`
73/80, 7 failures (Task 10's row): `in-process XML agrees: a task list,
checked and unchecked` + its `with positions` sibling, `...a task list mixed
with plain items` + sibling (both matching Task 10's original report exactly),
plus 3 CLI-leg failures Task 10 could not have seen (`CLI XML agrees:
tests/fixtures/gfm.md`, both variants, and the explicit `CLI XML agrees: a
task list, checked and unchecked` — all added by Task 11 after Task 10 ran).
Reverted; diff silent; `make test`: `ALL SUITES PASSED`.

### Mutation 10 — header/body row extractors swapped (Tasks 7 AND 10, both covered by one mutation)

```diff
-    (make-node-entry "table_header" 'table-row '(header?) header-row-props)
-    (make-node-entry "table_row"    'table-row '(header?) body-row-props)
+    (make-node-entry "table_header" 'table-row '(header?) body-row-props)
+    (make-node-entry "table_row"    'table-row '(header?) header-row-props)
```
`make test`: `test-convert.sps` 64/66 — `FAIL header? distinguishes the two
rows` (expected `(#t #f)`, actual `(#f #t)`) and `FAIL header? agrees with
cmark's own row accessor on every row` (expected `()`, actual `((#f #t) (#t
#f))`), matching Task 7's report exactly. `test-ast-differential.sps` 71/80,
9 failures: the 3 table fixtures × 2 position variants (matching Task 10's
original 6) plus 3 new CLI-leg failures (`gfm.md` both variants, `a table
with every alignment`). Reverted; diff silent; `make test`: `ALL SUITES
PASSED`.

### Mutation 11 — cell alignment index off by one (Task 7, covered, wider blast radius than the brief's row)

```diff
           (with-node p type-string depth ctx
                      (list (cons 'alignment
-                                (if (< index (length aligns))
-                                    (list-ref aligns index)
+                                (if (< (+ index 1) (length aligns))
+                                    (list-ref aligns (+ index 1))
                                     'none)))))
```
`make test`: `test-convert.sps` 64/66 — `FAIL header cells carry their
column's alignment` and `FAIL body cells carry the same alignments as the
header`, both expected `(left right none)`, both actual `(right none none)`
— matches Task 7's report exactly. **New:** `test-ast-differential.sps`
75/80, 5 collateral failures: `in-process XML agrees: a table with every
alignment` + sibling, plus `CLI XML agrees: tests/fixtures/gfm.md` (both
variants) and `CLI XML agrees: a table with every alignment`. Note that "a
table with one column" and "a table with inline markup in cells" do **not**
fail here (unlike Mutation 10) — with only one or uniform-`none` columns the
off-by-one shift happens not to change the visible output for those
particular fixtures. Reverted; diff silent; `make test`: `ALL SUITES
PASSED`.

### Mutation 12 — `extension-props` always includes the literal pair (Task 8, covered)

```diff
   (define (extension-props p type-string)
     (let ((literal (c-string->string (node-literal p))))
-      (if literal
-          (list (cons 'native-type type-string) (cons 'literal literal))
-          (list (cons 'native-type type-string)))))
+      (list (cons 'native-type type-string) (cons 'literal literal))))
```
`make test`: `test-convert.sps` 65/66 — `FAIL no literal key is invented for
a node that has none`, expected `((native-type . "footnote_definition"))`,
actual `((native-type . "footnote_definition") (literal . #f))`. **Zero**
collateral in `test-ast-differential.sps` (80/80 unchanged) — direct,
positive confirmation that the extension-fallback path this mutation touches
is unreachable through `markdown->ast` on any real document, consistent with
uncovered-property #2 below. Reverted; diff silent; `make test`: `ALL SUITES
PASSED`.

### Mutation 13 — `with-node` returns `'()` for `props` when `entry` is `#f` (Task 8, covered)

```diff
            (props (or properties-override
                       (if entry
                           (let ((extract (node-entry-extractor entry)))
                             (if extract (extract p) '()))
-                          (extension-props p type-string)))))
+                          '()))))
```
`make test`: `test-convert.sps` 62/66, four failures matching Task 8's report
exactly: `FAIL the extension node records the native type string verbatim`
(expected `"footnote_definition"`, actual `#f`), `FAIL the <unknown> error
string also falls back rather than raising` (expected `(extension
"<unknown>")`, actual `(extension #f)`), `FAIL no literal key is invented for
a node that has none` (expected `((native-type . "footnote_definition"))`,
actual `()`), `FAIL a literal-bearing node keeps its literal under the
fallback` (expected `((native-type . "unknown_inline") (literal . "para"))`,
actual `()`). Zero collateral in `test-ast-differential.sps` (80/80),
same reason as #12. Reverted; diff silent; `make test`: `ALL SUITES PASSED`.

### Mutation 14 — the `"heading"` entry deleted from `node-table` (Task 8, covered, wider blast radius than the brief's row)

```diff
-    (make-node-entry "heading"        'heading        '(level) heading-props)
     (make-node-entry "text"           'text           '(literal) literal-props)
```
`make test`: `test-convert.sps` 62/66, four failures matching Task 8's report:
`FAIL a heading and a paragraph convert to the exact expected tree` (a
`heading` node is now an `extension` node with `native-type "heading"`),
`FAIL heading level is copied` (expected `4`, actual `#f` — via SRFI-64's
own exception-to-`#f` conversion on `(car '())`, confirmed directly against
this suite's own result alist rather than the separate manual `guard`-probe
Task 8's report used), `FAIL the table has an entry for every reachable core
type string` (expected `()`, actual `("heading")`), `FAIL the table covers
exactly the 24 reachable type strings and no more` (expected `24`, actual
`23`). **New:** `test-ast-differential.sps` 72/80, 8 failures, none of them
predicted by the brief's row: `the comparison detects a real difference when
one exists`, `in-process XML agrees: headings of every level` + sibling,
`...a setext heading` + sibling, `the CLI comparison detects a real
difference when one exists`, and both `core.md` CLI-leg variants — every one
reports `DIAG-ACTUAL: #f`. Root cause, confirmed directly: a heading is now
an `extension` node whose `native-type` is still the literal string
`"heading"` (preserved verbatim by `extension-props`), so the serializer's
`node->type-string` still reads `ts = "heading"` and its `type-attributes`
still matches `(string=? ts "heading")` — but tries `(number->string
(markdown-node-property n 'level))` against an extension node that has no
`'level` property at all, raising a type error that SRFI-64 reports as
actual `#f`. Reverted; diff silent; `make test`: `ALL SUITES PASSED`.

### Mutation 15 — one-argument form uses `default-cmark-options` (Task 9, covered)

`src/cmark/gfm/parse.sls`:
```diff
      ((markdown) (markdown->ast markdown (default-cmark-options)))
```
(was `(default-ast-options)`). `make test`: `test-convert.sps` 63/66, three
failures matching Task 9's own report exactly: `FAIL the one-argument form
attaches source positions` (expected `#t`, actual `#f`), plus the two
legitimate collateral `FAIL positions carry cmark's real line and column
spans` and `FAIL the empty document carries cmark's real 1:1-0:0 span` (both
actual `#f`, both call the one-argument form for brevity and so are also
coupled to the default). `the two-argument form honours an explicit
source-positions? #t` is confirmed absent from the FAIL list (63+3=66). No
collateral in `test-ast-differential.sps` (80/80 — that suite always
constructs options explicitly). Reverted; diff silent; `make test`: `ALL
SUITES PASSED`.

### Mutation 16 — `node-source` ignores `positions?` (Task 9, covered, dramatically wider blast radius than the brief's row)

`src/cmark/gfm/private/convert.sls`:
```diff
   (define (node-source p ctx)
-    (and (convert-ctx-positions? ctx)
-         (let ((sl (node-start-line p)))
-           (and (not (zero? sl))
-                (make-source-position sl
-                                      (node-start-column p)
-                                      (node-end-line p)
-                                      (node-end-column p))))))
+    (let ((sl (node-start-line p)))
+      (and (not (zero? sl))
+           (make-source-position sl
+                                 (node-start-column p)
+                                 (node-end-line p)
+                                 (node-end-column p)))))
```
`make test`: `test-convert.sps` 65/66 — `FAIL the two-argument form honours
an explicit source-positions? #f`, expected `#f`, actual a real
`source-position` record `#[...1 1 1 2]` (line 1, column 1 through line 1,
column 2 — the paragraph "hi"), matching Task 9's own manually-probed value
exactly. **Not in the brief's row, and much larger than Task 9's report
anticipated:** `test-ast-differential.sps` collapses to 46/80, **34**
failures — every `in-process XML agrees: <name>` (the *no-positions*
variant only) across nearly the entire fixture list, plus 4 of the CLI leg's
`without positions` fixture checks. None of the `with positions` variants
fail. Mechanism, confirmed directly on the smallest case: `in-process XML
agrees: an empty document` now produces `<document sourcepos="1:1-0:0" .../>`
on our side against cmark's real `<document .../>` (no attribute) on the
`no-positions` side — because positions are now attached unconditionally,
regardless of what the options record's `source-positions?` field says. The
"detects a real difference" guards and the explicitly-`with-positions`-pinned
CLI checks are unaffected because they already requested positions on our
side, so the bug is invisible to them. Reverted; diff silent; `make test`:
`ALL SUITES PASSED`.

### Mutation 17 — swap max-nodes/max-depth in `parse.sls` (Task 9, covered)

```diff
           (convert-document h (make-convert-ctx
-                               (cmark-options-max-nodes o)
-                               (cmark-options-max-depth o)
+                               (cmark-options-max-depth o)
+                               (cmark-options-max-nodes o)
                                (cmark-options-source-positions? o))))
```
`make test`: `test-convert.sps` 64/66 — `FAIL max-depth from the options
record is enforced` (expected `(too-deep 10)`, actual `(too-many-nodes 10)`)
and `FAIL max-nodes from the options record is enforced` (expected
`(too-many-nodes 10)`, actual `(too-deep 10)`) — each fails with exactly the
*other* limit's reason, as the brief predicts. No collateral. Reverted; diff
silent; `make test`: `ALL SUITES PASSED`.

### Mutation 18 — `scope.sls` raises the limit with `(bytevector-length bv)` (Task 9, covered) — **this is also the Step 3 spot-check, run twice independently**

```diff
           (if (> (bytevector-length bv) max-bytes)
-              (raise (make-cmark-resource-limit 'too-large max-bytes))
+              (raise (make-cmark-resource-limit 'too-large (bytevector-length bv)))
               bv)))
```
`make test`: `test-convert.sps` 65/66 — `FAIL max-input-bytes still raises
too-large, now as a resource limit`, expected `(too-large 8)`, actual
`(too-large 29)` (the true UTF-8 length of the 8-byte-limited test string).
Confirmed that every *reason-only* check of `'too-large` elsewhere
(`test-lifecycle.sps`'s four 0.1-era assertions, `test-render.sps`'s one) is
**unaffected** — all suites besides `test-convert.sps` stay at their exact
baseline counts — proving this assertion is the only one in the whole suite
that pins the *ceiling value*, not merely the *reason*, exactly as the brief
states. **Run twice, independently, minutes apart** (see Step 3 below): both
runs produced byte-identical `make test` output and byte-identical
expected/actual values. Reverted both times; diff silent both times; `make
test`: `ALL SUITES PASSED` both times.

### Mutation 19 — `parse.sls` passes `(supported-extensions)` instead of `(cmark-options-extensions o)` (Task 9, covered)

```diff
-        (map extension->native-name (cmark-options-extensions o))
+        (map extension->native-name (supported-extensions))
```
`make test`: `test-convert.sps` 65/66 — `FAIL an extension the record omits
is not attached`, expected `()`, actual a real strikethrough node (a
document parsed with `'extensions '()` now gets strikethrough attached
anyway, since all 5 supported extensions are always requested regardless of
the record). `extensions from the options record are attached` is confirmed
absent from the FAIL list — the brief's stated reason this pair is not
redundant. No collateral. Reverted; diff silent; `make test`: `ALL SUITES
PASSED`.

### Mutation 20 — `cmark-options?` check moved inside `call-with-native-document`'s callback (Task 9, covered — the brief's caveat confirmed, and refined)

```diff
       ((markdown o)
-       ;; Checked before anything native is acquired, so a bad argument leaves
-       ;; no resource to clean up -- the bug Stage 1 shipped for extension
-       ;; names and Stage 2 for width.
-       (unless (cmark-options? o)
-         (raise (make-cmark-invalid-option #f 'invalid-value)))
        (call-with-native-document
         markdown
         (options->bits o)
         (map extension->native-name (cmark-options-extensions o))
         (lambda (h)
+          (unless (cmark-options? o)
+            (raise (make-cmark-invalid-option #f 'invalid-value)))
           (convert-document h (make-convert-ctx ...)))
         (cmark-options-max-input-bytes o))))))
```
`make test`: `test-convert.sps` 65/66 — `FAIL a non-options argument is
rejected before anything is allocated`, expected `invalid-value`, actual
`wrong-condition` (not `no-condition`) — **the assertion still fails, but via
a different condition than the deleted check would have raised**, exactly
the brief's caveat. `markdown->ast released every native allocation`
(checking `live-counts`) stays green.

**The caveat, confirmed and refined by direct probe.** The brief states
"`options->bits` runs first and its own accessor raises." A standalone probe
(`markdown->ast "hi\n" 'not-options` against the mutated `parse.sls`, with
`live-counts` printed before and after) shows the raising accessor is
actually **`cmark-options-max-input-bytes`**, not one of `options->bits`'s
internal calls:
```
condition?: #t
assertion-violation?: #t
cmark-invalid-option?: #f
who: cmark-options-max-input-bytes
message: "~s is not of type ~s"
irritants: (not-options #<record type cmark-options>)
live-counts before: (0 0 0)
live-counts after:  (0 0 0)
```
`(cmark-options-max-input-bytes o)` is the *last* of `call-with-native-document`'s
five positional arguments in program-text order, so this is consistent with
Chez evaluating this call's arguments right-to-left — the last-written
accessor call is the first one actually evaluated, and it raises a raw R6RS
`&assertion` (record-accessor type check) before `options->bits`'s own body
ever runs, before `call-with-native-document` is entered, and before
`acquire!` allocates anything (`live-counts` unchanged, `(0 0 0)` both
before and after). The brief's overall conclusion holds — the argument is
*rejected*, and no reachable ordering here leaks a resource — but the
specific accessor it names is not the one actually observed to raise on this
build; recorded as the more precise, directly-observed mechanism. Reverted;
diff silent; `make test`: `ALL SUITES PASSED`.

### Mutation 21 — `heading-props` returns level 1 (Task 10, covered, wider blast radius than the brief's row)

```diff
   (define (heading-props p)
-    (list (cons 'level (node-heading-level p))))
+    (list (cons 'level 1)))
```
`make test`: `test-ast-differential.sps` 76/80 — `in-process XML agrees:
headings of every level` + `with positions` sibling, plus 2 new CLI-leg
failures (`core.md`, both variants) Task 10 could not have seen. **New:**
`test-convert.sps` 65/66 — `FAIL heading level is copied`, expected `4`,
actual `1`. Reverted; diff silent; `make test`: `ALL SUITES PASSED`.

### Mutation 22 — `convert-children` drops its `reverse` (Task 10, covered, dramatically wider blast radius — both because the suite grew and because this reaches `test-convert.sps` too)

```diff
   (define (convert-children p depth ctx)
     (let loop ((c (node-first-child p)) (i 0) (acc '()))
       (if (zero? c)
-          (reverse acc)
+          acc
           (loop ...))))
```
`make test`: `test-ast-differential.sps` collapses to 29/80, **51** failures
— every multi-child `check`/`check-ext` fixture, both position variants, plus
the CLI leg. Task 10's original report (against a pre-CLI-leg,
62-assertion suite) recorded 40/62; today's 51/80 is the same property at
the suite's current, larger size — proportionally consistent (of the 9
single-child-or-childless survivor names Task 10 identified, none reversing
is a no-op, all 9 still pass today too). **New, not in the brief's row (which
names only the differential suite):** `test-convert.sps` also drops to
56/66, 10 failures, every one of them a tree- or sibling-order check reading
back the reversed children — `a heading and a paragraph convert to the exact
expected tree` (blocks swapped), `inline emphasis nests inside the
paragraph` (inline runs reversed), `item index is copied for every item in
an offset ordered list` (expected `(3 4 5)`, actual `(5 4 3)`), `literals are
readable after the native document is gone`, the three table/row/alignment
checks, `checked, unchecked, and plain items are all distinguished`, and
`extension trees also outlive the native document`. Reverted; diff silent;
`make test`: `ALL SUITES PASSED`.

### Mutation 23 — `emit-indent` drops the `min` cap (Task 10, covered — one more failure than Task 10 originally saw)

`tests/test-ast-differential.sps` itself (the only mutation in a test file,
not `src/`):
```diff
   (define (emit-indent port depth)
-    (let ((n (min (* 2 depth) 40)))
+    (let ((n (* 2 depth)))
       (let loop ((i 0))
```
Since the mutated file is the test file, the diagnostic wrapper was
regenerated from the *mutated* copy for this one mutation only (confirmed
this changes nothing about the technique — only the source it was applied
to). `make test`: `test-ast-differential.sps` 77/80, **3** failures: `in-process
XML agrees at 25 levels of nesting, past MAX_INDENT` and its `with positions`
sibling (both `DIAG-EXPECTED: #f`, actual a real divergent-string pair — the
deepest `<text>deep</text>` line indented 54 spaces on our uncapped side
against cmark's real, still-capped 40), plus `CLI XML agrees: 25 levels of
nesting, past MAX_INDENT` — a failure Task 10's own report could not have
seen, because the CLI leg did not exist at the time Task 10 ran this
mutation (added afterward, by Task 11). No other assertion is affected:
77 = 80 − 3, and the closing-tag trailer of the two documents in the
in-process diff is confirmed byte-identical (both capped at 40 there),
isolating the divergence to the depth range 21-27 where `2 × depth` first
exceeds `MAX_INDENT`. Reverted (`cp` from backup, since this file is
tracked but the same byte-identical-restore discipline applies); diff
silent; `make test`: `ALL SUITES PASSED`.

### Mutation 24 — `ast.sls` given a native import it calls (Task 2, covered)

```diff
-  (import (rnrs))
+  (import (rnrs) (cmark gfm private native))
+
+  ;; TEMPORARY purity-gate falsification probe.
+  (define ignored-purity-probe (live-counts))
```
(A *reference* to a native binding is required, not just the import — Chez
only instantiates an imported library's body when something actually
references one of its bindings, confirmed directly: an import with no
reference is invisible to the gate.) `make check-purity`:
```
=== check-purity: tests/test-options.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
%%%% Starting test options
# of expected passes      49
purity holds: tests/test-options.sps pulled in no native code
=== check-purity: tests/test-ast.sps, CHEZ_CMARK_GFM_SHIM poisoned ===
Exception occurred with condition components:
  0. &cmark-shim-unavailable: "/nonexistent"
PURITY VIOLATED: tests/test-ast.sps failed with CHEZ_CMARK_GFM_SHIM poisoned
to a nonexistent path. ...
make: *** [check-purity] Error 1
```
Recipe exit 1 (`fail=1` → `exit $$fail`), `make`'s own wrapper exit 2 — the
standard GNU Make wrapping already established in the Stage 1/2 logs. The
*other* pure suite, `test-options.sps`, is completely unaffected (49/49,
`purity holds:`), confirming the mutation is scoped exactly to `ast.sls`'s
own import chain. Also confirmed `make test` (which does not poison the
shim variable) is entirely unaffected by this mutation — `ALL SUITES
PASSED`, proving the mutation only touches the purity gate, not ordinary
behaviour. Reverted; diff silent; `make check-purity`: both suites hold;
`make test`: `ALL SUITES PASSED`.

---

## Step 2 — the four properties no mutation can break

AGENTS.md is explicit that an assertion no mutation can break is an empty
assertion, and that leaving it silently is the exact failure the rule exists
to prevent. The brief names four properties in this category. Each was
independently verified below by attempting a real, run mutation or
experiment — not by copying the brief's claim — per this task's explicit
instruction. **One of the four turned out to be wrong.**

### 1. The `_Bool` shim wrapper — confirmed uncovered

Claim: binding `cmark_gfm_extensions_get_tasklist_item_checked` directly as
`int` (instead of through the shim's `chez_cmark_tasklist_checked`, which
normalises the C `_Bool` return to a clean 0/1 `int`) cannot be shown to fail
here, because the platforms available happen to leave the upper bits zero.

**Attempted directly.** `src/cmark/gfm/private/native.sls`:
```diff
   (define tasklist-checked
-    (foreign-procedure "chez_cmark_tasklist_checked" (uptr) int))
+    (foreign-procedure "cmark_gfm_extensions_get_tasklist_item_checked" (uptr) int))
```
`make test`: `ALL SUITES PASSED`, 397/397, no change whatsoever — including
every checked/unchecked task-list assertion in both `test-convert.sps` and
`test-ast-differential.sps`. Confirmed directly, not merely asserted: on this
platform (macOS/arm64), the ABI hazard the shim's own header comment warns
about (x86-64 SysV `_Bool` return leaves upper bits of the register
unspecified) is real per the ABI contract but genuinely unobservable here.
Reverted; diff silent; `make test`: `ALL SUITES PASSED`.

### 2. The unknown-type fallback's end-to-end unreachability — confirmed uncovered, with a more precise mechanism than the brief states

Claim: no document reachable through this library's options produces an
unrecognised type string.

**Investigated via source, then confirmed by a forced-on probe.**
`vendor/cmark-gfm/src/cmark-gfm.h`'s node-type enum has exactly 22 core
types (11 block + 11 inline) plus 4 extension-registered types
(`cmark_syntax_extension_add_node`, confirmed by grep: 1 in
`strikethrough.c`, 3 in `table.c`, none in `autolink.c`/`tagfilter.c`/
`tasklist.c`) = 26 total node-type constants. `node-table` maps exactly 24
type strings, confirmed by count and by
`"the table covers exactly the 24 reachable type strings and no more"`
already checking it.

**Recounted by constant, not by string.** 26 and 24 are different units —
constants versus type strings — so subtracting them directly understates
the gap: two constants each surface under two `node-table` entries.
`CMARK_NODE_ITEM` covers both `"item"` and `"tasklist"`, because
`tasklist.c`'s `open_tasklist_item` never allocates a new node or changes
`->type` — it only tags an existing item via
`cmark_node_set_syntax_extension`, so `cmark_node_get_type_string`
dispatches to the extension's own `get_type_string` (unconditionally
`"tasklist"`) instead of falling through to `node.c`'s own `case
CMARK_NODE_ITEM: return "item";`. `CMARK_NODE_TABLE_ROW` likewise covers
both `"table_row"` and `"table_header"`, which `table.c`'s own
`get_type_string` picks between by checking the row's `is_header` flag at
query time, never by using a second node type. Counted *by constant*,
`node-table` covers 24 - 2 = **22 of the 26**, and the true gap is
**four** constants, not two, for two unrelated reasons.

`CMARK_NODE_FOOTNOTE_DEFINITION`/`CMARK_NODE_FOOTNOTE_REFERENCE` are
genuine **core** node types, not behind any syntax-extension gate. Grepped
`vendor/cmark-gfm/src/blocks.c` directly: footnote-definition parsing is
gated by `parser->options & CMARK_OPT_FOOTNOTES` (`#define
CMARK_OPT_FOOTNOTES (1 << 13)`, `cmark-gfm.h:755`) — and
`chez_cmark_option_bits` (`src/cmark-gfm-shim.c`) takes exactly 6 booleans
(`validate_utf8, sourcepos, hardbreaks, nobreaks, smart, unsafe_html`) and
never ORs in that bit. This library structurally cannot enable footnote
parsing today. `CMARK_NODE_CUSTOM_BLOCK`/`CMARK_NODE_CUSTOM_INLINE` are
uncovered for a *different* reason: not gated, but never constructed by
the parser at all. Grepped `vendor/cmark-gfm/src/blocks.c` and
`inlines.c` directly: zero matches for either constant in either file.
Both appear only in renderer switches (`xml.c`, `html.c`, `commonmark.c`,
`latex.c`, `man.c`, `plaintext.c`) and in `node.c`/`iterator.c`'s own
utility switches, all of which handle whatever node type a caller hands
them rather than ever building one — and neither `native.sls` nor the
shim exposes any call that could construct one from Scheme either, so
nothing this library's own parse path can produce either type. This
confirms the brief's claim more thoroughly than it stated: the fallback
is unreachable through two independent mechanisms and four constants —
one gated core feature this library never turns on, and one pair of
types that exist solely for programmatic tree construction its own
parser never performs — not the single mechanism and two constants the
original count implied.

Went one step further: temporarily forced `CMARK_OPT_FOOTNOTES` on
unconditionally (`native.sls`'s `option-bits`, `(bitwise-ior 8192
(raw-option-bits ...))`) and ran an isolated probe —
`(markdown->ast "Body text[^1].\n\n[^1]: A footnote definition.\n" ...)` —
to see what *would* happen if this bit were ever exposed:
```
(document () ((paragraph () ((text ...) (extension ((native-type . "<unknown>") (literal . "1")) ()) (text ...)))
              (extension ((native-type . "<unknown>") ((paragraph ...)))))
```
Both the footnote reference and definition become `extension` nodes with
`native-type` **`"<unknown>"`**, not `"footnote_reference"`/
`"footnote_definition"` — confirmed against `vendor/cmark-gfm/src/node.c`:
`cmark_node_get_type_string`'s own switch (line 239) has no case for either
`CMARK_NODE_FOOTNOTE_*` constant and falls through to its own `"<unknown>"`
default (line 293), even though those constants are recognised elsewhere in
the same file for other purposes. So even the one core node type this
project could plausibly enable in the future would not exercise a *new*
fallback scenario — it collapses onto exactly the same `"<unknown>"` case
`test-convert.sps`'s `"the <unknown> error string also falls back rather
than raising"` already covers synthetically. Reverted (both the probe file,
scratchpad-only, and `native.sls`); diff silent; `make test`: `ALL SUITES
PASSED`; `make check-purity`: holds.

### 3. The zero-start-line guard in `node-source` — **the brief's claim is wrong.** This property is covered, not uncovered.

Claim (brief, Step 2 item 3): "`xml.c:48` guards on `start_line != 0`, and
the converter mirrors it — but no node reaches it... it is kept because it
keeps the serializer a straight mapping; it is not tested because it cannot
be reached."

**Attempted directly, and the mutation produced real failures.**
`src/cmark/gfm/private/convert.sls`:
```diff
   (define (node-source p ctx)
     (and (convert-ctx-positions? ctx)
          (let ((sl (node-start-line p)))
-           (and (not (zero? sl))
-                (make-source-position sl ...)))))
+           (make-source-position sl ...))))
```
`make test`: `test-ast-differential.sps` **3 failures**, not zero:
`in-process XML agrees with positions: paragraphs and soft breaks`,
`in-process XML agrees with positions: a hard break`, and `CLI XML agrees:
tests/fixtures/core.md with positions`. Concrete divergence (smallest case):
```
ours:   <softbreak sourcepos="0:0-0:0" />
cmark:  <softbreak />
```
and the hard-break case shows the identical pattern for `<linebreak>`. This
means `node-start-line` genuinely returns `0` for `CMARK_NODE_SOFTBREAK` and
`CMARK_NODE_LINEBREAK` nodes in real cmark output, and cmark's own `xml.c:48`
guard *does* suppress the attribute for them — the exact case the brief
claimed could not occur.

**Root cause, confirmed against `vendor/cmark-gfm/src/inlines.c` directly**
(per this project's own AGENTS.md rule: read cmark's semantics from the
vendored source, never from recall). `make_linebreak`/`make_softbreak`
(line 29-30) both expand to `make_simple` (line 100), which `calloc`s the
node and sets only `->type` — every numeric field, including
`start_line`/`start_column`/`end_line`/`end_column`, stays zero forever;
nothing later in `inlines.c` ever assigns them for these two node types
(confirmed: the file's only assignments to `->start_line` are at lines 92,
178, 1280, 1325, and — the revealing one — **812**, where `emph`/`strong`
nodes explicitly get `emph->start_line = opener_inl->start_line;` right
after creation, line 801 confirming the same code path builds both emph
*and* strong: `emph = use_delims == 1 ? make_emph(...) : make_strong(...)`).
Emph and strong are created via the identical `make_simple` helper as
softbreak/linebreak, but are then explicitly patched with a borrowed
position; softbreak and linebreak never are. This is why "an empty document"
(the brief's own example) shows `start_line 1`, not `0` — `make_document`
(`blocks.c`) is a different, position-aware constructor entirely, and
checking only that one case is what let the blanket "no node reaches it"
claim through.

**Conclusion.** The guard is reached by completely ordinary Markdown (any
soft or hard line break inside a paragraph), and it is *already* covered —
not by a dedicated assertion, but as a necessary side effect of the 3
existing assertions named above, which already pass today (with the guard
in place) precisely because `node-source` correctly omits the position for
these two node types. This should be corrected in the design spec/plan
rather than left as a documented gap. Reverted; diff silent; `make test`:
`ALL SUITES PASSED`.

### 4. `copy-required`'s NULL branch — confirmed uncovered (within this project's full test corpus)

Claim: every declared property's accessor is called only on a node type
that supports it, so `c-string->string` never returns `#f` there; the raise
is defensive and unreachable.

**Attempted directly**, made the branch observable rather than merely
fatal, and ran the *entire* corpus, including the adversarial `hostile.md`
fixture:
```diff
   (define (copy-required addr)
     (let ((s (c-string->string addr)))
-      (or s (raise (make-cmark-error)))))
+      (or s (begin (display "UNCOVERED-PROPERTY-4-PROBE: copy-required saw NULL\n")
+                   (raise (make-cmark-error))))))
```
`make test`: `ALL SUITES PASSED`, 397/397, and the probe string appears
**zero** times across the full captured output of all 10 suites (`grep -c`
on the complete log: `0`). This does not prove impossibility for every
conceivable cmark version or input (that would require exhaustively
analysing every accessor's C implementation for every node type it is ever
called on, which is out of this task's scope), but it is a genuine,
affirmative experiment across this project's entire testing surface —
including the fixture built specifically to be adversarial — not merely an
absence of a crash in the unmutated baseline. Reverted; diff silent; `make
test`: `ALL SUITES PASSED`.

---

## Step 3 — spot-check: re-running a mutation to confirm the log matches reality

Since every mutation in this log was itself run fresh against the current
tree (the brief's central instruction), this requirement is met by
construction — but per the brief's explicit Step 3, one mutation was chosen
and re-run a **second, fully independent** time after this log's numbers
were already recorded, to confirm no drift between "what was recorded" and
"what the tree does right now."

**Chosen: Mutation 18 (`scope.sls`, `(bytevector-length bv)` instead of
`max-bytes`).** Backed up `scope.sls` again (fresh `cp`, independent of the
earlier backup), reapplied the identical diff, ran `make test` and the
`test-convert.sps` diagnostic wrapper again. Result: byte-identical to the
first run in every respect — `test-convert.sps` 65/66, `FAIL max-input-bytes
still raises too-large, now as a resource limit`, expected `(too-large 8)`,
actual `(too-large 29)`, every other suite at its exact baseline count.
Reverted; diff silent; `make test`: `ALL SUITES PASSED`; `make check-purity`:
holds.

---

## Final clean-tree confirmation

```
$ git status --short
(empty)
$ git diff --stat
(empty)
$ make test 2>&1 | tail -3
%%%% Starting test shim-loading
# of expected passes      10
ALL SUITES PASSED
$ make check-purity 2>&1 | tail -3
%%%% Starting test ast
# of expected passes      30
purity holds: tests/test-ast.sps pulled in no native code
```

Every one of the 24 mutations above (covering all 26 rows in the brief's
table) and all 4 uncovered-property experiments were individually reverted
and confirmed byte-identical to their pristine backup (`diff`, silent) before
the next began. No mutation was ever left in the tree while another was
applied. The tree is clean; this file is the only change.

---

## Addendum (release 0.2 whole-branch review, Finding 9) — the `live-counts` / no-leak-on-failure property

None of the 24 mutations above touches `scope.sls`'s `dynamic-wind` in
`call-with-native-document`. Mutation 18 is the only one of the 24 that
touches `scope.sls` at all, and it changes `validate-markdown-input`'s
ceiling value, not the release mechanism — so nothing in this log had
actually shown that the `live-counts` assertions (`a limit failure leaves no
native allocation behind`, `extension conversion released every native
allocation`, `the fallback path released every native allocation`,
`markdown->ast released every native allocation`, and their siblings in
`tests/test-lifecycle.sps` and `tests/test-render.sps`) can fail at all.
AGENTS.md requires *a* mutation through the asserted property, not one
confined to `convert.sls`; this addendum supplies it and closes the gap.

### Mutation 25 — `dynamic-wind` replaced with a normal-return-only release (Finding 9, newly covered)

`src/cmark/gfm/private/scope.sls`, `call-with-native-document`'s 5-argument
clause:
```diff
       ((markdown option-bits extension-names proc max-bytes)
        (let* ((bytes (validate-markdown-input markdown max-bytes))
               (names (validate-extension-names extension-names))
               (h (acquire! bytes option-bits names)))
-        (dynamic-wind
-          (lambda ()
-            ;; Re-entry via a captured continuation lands here. The document
-            ;; is gone and cannot be rebuilt, so refuse rather than proceed.
-            (unless (native-doc-alive? h)
-              (raise (make-cmark-dead-document))))
-          (lambda () (proc h))
-          (lambda () (release! h)))))))
+        (let ((result (proc h)))
+          (release! h)
+          result)))))
```
This removes both of `dynamic-wind`'s protections at once: the after-thunk no
longer runs on a non-local exit (an exception, or a continuation invoked from
outside `proc`'s normal extent), and the re-entry guard is gone too.
`release!` now runs only when `proc` returns normally — a normal-return-only
release, exactly what AGENTS.md's rule calls for probing.

`make test`: **SUITE FAILED**, 390/397, seven failures across three suites,
all other suites at their exact baseline count.

**`tests/test-convert.sps`, 62/66 — exactly the four named in the brief:**
```
FAIL a limit failure leaves no native allocation behind
FAIL extension conversion released every native allocation
FAIL the fallback path released every native allocation
FAIL markdown->ast released every native allocation
```
Mechanism: the first leak happens two tests before the first *failing*
assertion. `one level past the depth limit raises too-deep` and `one node
past the node limit raises too-many-nodes` (the pair immediately before `a
limit failure leaves no native allocation behind`) each raise
`&cmark-resource-limit` from inside `proc`; the mutated code no longer
catches that on the way out, so each leaks one parser and one root before
either test's own assertion (which only checks the condition's reason and
value, not `live-counts`) even runs. `live-counts` is a process-wide counter
that nothing resets between tests, so every `'(0 0 0)` checkpoint from that
point on in the same process inherits the earlier leaks — which is why the
four failures are spread out rather than adjacent: one right after the
first two leaks, one after the extension-type group (having inherited them),
one after the fallback group (which leaks twice more, via its own two
resource-limit tests), and one after the public `markdown->ast` group
(three more, via its own limit tests). None is a false negative — each
observes a genuinely non-`(0 0 0)` value; spot-checked by re-running
`test-convert.sps` alone, first failure actual value `(3 3 0)`.

**`tests/test-lifecycle.sps`, 20/22 — direct hits, not cascade collateral**
(each test takes its own `before` snapshot immediately before its own
exception, so it cannot inherit an earlier test's leak):
```
FAIL counters balance after the body raises
FAIL counters balance after a non-local escape
```
The second is the exact case the suite's own comment names: "A continuation
escape must still free. `dynamic-wind`'s after-thunk is what makes this
work; without it this test leaks" — written for this mutation. The other
five exception-raising assertions in this suite stay green: three raise
before `acquire!` is ever reached (`validate-markdown-input`,
`validate-extension-names`, twice each), and "counters balance after
extension attachment fails" raises from inside `acquire!` itself, which
already calls `release!` by hand before raising — none of those paths
reaches the mutated `dynamic-wind` at all. "100 scopes leave the counters
balanced" also stays green: no exception occurs in that loop, so the
sequential `(let ((result (proc h))) (release! h) result)` releases exactly
as the after-thunk would have.

**`tests/test-render.sps`, 34/35 — one failure:**
```
FAIL counters balance after the render scope's body raises
```
That test's body finishes rendering (freeing its own buffer correctly,
through `call-with-render-buffer`'s own, untouched `dynamic-wind`) and only
then calls `(error 'test ...)`, so the leak is exactly one parser and one
root from the *outer* `call-with-native-document`, not a buffer. The other
two render-suite balance-after-guard assertions stay green for the same
structural reasons as lifecycle's: "counters balance after a NULL buffer is
rejected" never calls `call-with-native-document`, and "counters balance
after a bad width is rejected" raises before any native resource is
acquired.

The other seven suites sit at their exact baseline count, unaffected:
`test-ast-differential.sps` 80, `test-ast.sps` 30, `test-conditions.sps` 23,
`test-differential.sps` 28, `test-native.sps` 54, `test-options.sps` 49,
`test-shim-loading.sps` 10 — confirming the mutation's blast radius is
exactly the tests that route an exception or a continuation escape through
`call-with-native-document`'s body, and nothing wider.

Reverted (`cp` from a fresh scratchpad backup, independent of every earlier
backup in this file); `diff` silent; `git status --short` and `git diff
--stat` both empty; `make test` re-run: `ALL SUITES PASSED`, 397/397.

**Uncovered-properties update.** This closes the one property that would
otherwise have needed a fifth entry alongside Step 2's four: whether the
`live-counts` / no-leak-on-failure assertions have any mutation that breaks
them. They do, and the covering mutation runs through `scope.sls`'s
`dynamic-wind` — the actual release mechanism the property is about, not
anything local to `convert.sls` — satisfying AGENTS.md's requirement that
the mutation go through the asserted property itself. It is recorded here
rather than filed as a fifth item under "the four properties no mutation can
break," because, unlike those four, this one is not uncovered.
