# Stage 1 Mutation Log

Task 12 proves each memory rule in [design spec §7.4](2026-08-16-chez-cmark-gfm-design.md)
has a test that fails when the rule is broken. Method, applied identically to every
mutation below: edit `src/cmark/gfm/private/scope.sls`, run `make test`, record the
exact result, `git restore src/cmark/gfm/private/scope.sls`, confirm `git status
--short` is clean before moving to the next mutation. No mutation was left in the
tree while another was applied.

**Baseline** (before any mutation, and reconfirmed clean after all of them): 3
suites, 33 assertions, `make test` prints `ALL SUITES PASSED`, `exit=0`.

A note on exit codes below: this GNU Make reports the *make* process's exit code as
`2` for a failed recipe even though the recipe's own `exit $$fail` uses `1` — this
was established independently in Task 11 and is reconfirmed here, not a new finding.

## Summary

| # | Mutation | Change | `make test` result | Named test(s) that failed | Covered? |
|---|---|---|---|---|---|
| A | Free the parser before the root | Swapped the `node-free` and `parser-free` blocks in `release!` | PASS, 33/33, exit=0 | none | **Not yet** — see below |
| B | Drop the liveness check | `check-alive` body replaced with `#t` | FAIL, exit=2 | "the handle is dead after the scope exits"; "every checked accessor rejects a dead handle" | Yes |
| C | Make `release!` non-idempotent | Removed the outer `(when (native-doc-alive? h) …)` guard; moved `native-doc-alive?-set!` to the end | PASS, 33/33, exit=0 | none | **No** — contradicts the brief's prediction; see below |
| D | Skip the embedded-NUL check | Deleted the `(char=? #\nul …)` clause from `validate-markdown-input` | FAIL, exit=2 | "embedded NUL is rejected" | Yes |
| E | Measure characters instead of bytes | Size check changed to `(> (string-length markdown) max-bytes)` | FAIL, exit=2 | "the limit counts bytes, not characters" | Yes |
| F | Drop a counter decrement | Deleted `(count-parser-free!)` | FAIL, exit=2 | "counters balance after a successful scope"; "counters balance after the body raises"; "counters balance after a non-local escape"; "counters balance after extension attachment fails"; "100 scopes leave the counters balanced" | Yes |
| G | Disable the re-entry guard | `dynamic-wind` before-thunk replaced with `(lambda () #f)` | PASS, 33/33, exit=0 | none | **No**, by design — see below |
| H | Make `release!` genuinely double-callable | Not a mutation: attempted to add a test that triggers a second `release!` on a handle captured out of a completed scope | compile fails: `attempt to reference unbound identifier release!` | n/a (no test could be written) | **No** — enforced structurally, not tested; see below |

## Design spec §7.4 rule-by-rule coverage

The table above answers Task 12's checklist letters. The brief's own purpose line
asks for coverage of every §7.4 row, and Stage 1 doesn't implement all of them
(there is no renderer and no Scheme AST yet), so here is the direct mapping:

| §7.4 rule | Enforced by (Stage 1) | Status |
|---|---|---|
| Free parser before render must fail a table/strikethrough render test | Nothing yet — rendering does not exist until Stage 2 | **Gap, tracked below** |
| Drop the `alive?` check must fail a re-entry test | Split into two distinct mechanisms in the actual code — see the note on B vs G below | **Partially covered** (post-teardown access: yes via B; true continuation re-entry: no via G) |
| Non-idempotent `release!` must fail a cleanup-after-partial-failure test | Nothing — see Mutation C below | **Gap, recorded honestly** |
| Borrowed-pointer-instead-of-copy must fail a post-free AST traversal under Valgrind | Nothing — there is no Scheme AST until a later stage | **Out of scope for Stage 1** |
| Skip the embedded-NUL check must fail a truncation test | Mutation D / "embedded NUL is rejected" | **Covered** |
| libc `free` on a renderer buffer must fail a counter/ASan-mismatch test | Nothing — there is no renderer buffer until Stage 2 | **Out of scope for Stage 1** |

Only two of six design-spec rows are fully exercised by Stage 1 tests today
(the NUL check, and — separately from the table's own phrasing — the general
counter-balance discipline via Mutation F). That is an accurate, not a
disappointing, count: three of the remaining four rows describe machinery
(render, AST, renderer buffer) that Stage 1 does not build.

## Detailed notes on the four uncovered mutations

### Mutation A — parser/root teardown order (not yet covered)

Swapping which of `node-free`/`parser-free` runs first inside `release!` changes
nothing `make test` can see: both still run exactly once, so the debug counters
balance identically either way. This is the **correct and expected** result, not a
gap in the mutation — the ordering ADR-0005 actually cares about is parser-vs-
**render**, and nothing in Stage 1 renders. The only thing currently guarding the
real ADR-0005 order is the Stage 0 spike (`spike/03-uaf.ss`, results recorded in
`spike/FINDINGS.md` under "Q2: ADR-0005 use-after-free — CONFIRMED"), which is
about to be deleted by this same task (Step 10) because it has served its purpose
as a spike, not as regression coverage.

**Carried into Stage 2** (also stated in the plan's exit gate): Stage 2's first task
must add a render-with-extensions test that fails under ASan when the parser is
freed before `cmark_render_html` is called.

### Mutation C — non-idempotent `release!` (not covered; contradicts the brief's predicted result)

The brief predicts "FAIL or crash — a double `node-free` on the same root," with an
explicit instruction to investigate rather than accept a silent pass. It passes
silently. Investigated as instructed, in three steps, each reverted before the next:

1. **Mutation exactly as specified.** `make test`: PASS, 33/33, exit=0.
2. **Diagnostic (not part of the mutation): forced a second `release!` call.**
   Changed the `dynamic-wind` after-thunk to `(lambda () (release! h) (release! h))`
   on top of Mutation C's change. Still PASS, 33/33, exit=0.
3. **Diagnostic: also removed the inner `(unless (zero? …) …)` guards** around the
   `node-free`/`parser-free` calls, keeping the forced double call. Now FAILS: 7
   named failures (all five counter-balance tests, plus "the handle is dead after
   the scope exits" and "every checked accessor rejects a dead handle"), but the
   process does **not** crash — `make test` runs to completion and reports
   `SUITE FAILED`, exit=2.

Root cause, confirmed rather than assumed:

- **No path in the current suite calls `release!` more than once on the same
  handle.** Every exit from `call-with-native-document`'s `dynamic-wind` — normal
  return, an exception raised in the body, or a `call/1cc` escape — runs the
  after-thunk exactly once. The two `acquire!` failure paths (extension not found;
  `parser-finish` returns a null root) call `release!` directly, once, *before*
  `dynamic-wind` is ever established, so its after-thunk never fires for that
  handle. Removing the outer idempotency guard therefore has nothing to protect
  against in this suite — this is the same gap Mutation H names directly.
- **Even where `release!` is forced to run twice (diagnostic 2), a second,
  independent layer of protection still holds it together**: the per-field
  `(unless (zero? root) …)` / `(unless (zero? p) …)` checks null out each pointer
  immediately after freeing it, so a second pass sees zeros and does nothing —
  regardless of whether the *outer* `alive?` guard exists. Mutation C only removes
  the outer guard, which is why even a forced double call (diagnostic 2 step 1)
  still doesn't fail.
- **Only removing both layers together, with a forced double call, produces an
  observable failure** (diagnostic 3), and even then it surfaces as an ordinary
  SRFI-64 `FAIL` rather than a process crash. Confirmed directly with a standalone
  probe script (imports `(cmark gfm private native)`, calls `(node-free 0)`
  outside any test harness): Chez raises `Exception: invalid memory reference.
  Some debugging context lost` and the bare script exits 255 uncaught. Inside
  `make test`, that same condition is caught, not fatal: SRFI-64's
  `test-assert`/`test-equal` (`.akku/lib/srfi/%3a64/testing-impl.scm`) wrap each
  test expression's evaluation in `(guard (ex (else #f)) test-expression)`, which
  is why a memory fault this severe still produces a clean, itemized `FAIL` list
  instead of aborting `make test` outright.

The design spec's own §7.4 table expected this rule to be caught by a
"cleanup-after-partial-failure test," which in this suite is "counters balance
after extension attachment fails." That test also only calls `release!` once
(inside `acquire!`, before raising), so it cannot discriminate this mutation
either — the design spec's predicted discriminator has the identical gap.

**This is a genuine, currently-real gap**, not a theoretical one: `release!`'s
idempotency is asserted in a comment ("Idempotent by construction") and enforced
in code, but exercised by nothing. It will not be closed by Stage 1 — see
Mutation H, which is the same gap viewed from the "add a test" side, and the
Stage 2 carry-forward below.

### Mutation G — re-entry guard (not covered, by design)

Replacing the `dynamic-wind` before-thunk with `(lambda () #f)` removes the check
that rejects re-entering a torn-down scope via a captured continuation. `make
test`: PASS, 33/33, exit=0. This is expected, not a surprise: the only escape
mechanism used anywhere in this codebase or its tests is `call/1cc`
(`only (chezscheme) call/1cc`), which is **escape-only** — a `call/1cc`
continuation cannot be invoked a second time to re-enter the dynamic extent it
escaped from. Constructing the scenario the guard actually defends against
requires a full, multi-shot continuation (`call/cc`) captured inside the scope
body and invoked again after the scope has already torn down. Nothing in Stage 1
does that, so the before-thunk's own logic is currently decorative from the test
suite's point of view.

Note the distinction from Mutation B, which this table's §7.4 mapping calls out
explicitly: B breaks `check-alive`, used by the three **checked accessors**
(`doc-root`, `doc-parser`, `doc-extensions`) — that catches an *ordinary* escaped
reference used after its scope exited normally, and is well covered by "the handle
is dead after the scope exits" and "every checked accessor rejects a dead handle."
G breaks the separate `alive?` check in the `dynamic-wind` **before-thunk**, which
only ever matters on true continuation re-entry. These are two different
mechanisms defending two different hazards, and only one of them is reachable by
any test Stage 1 can write with the tools it imports.

### Mutation H — genuine double-`release!` (not covered, enforced structurally)

Per the brief, this step is "add a test," not "apply a mutation and revert it."
Attempted exactly as described: captured a handle out of a completed scope (the
same pattern the existing liveness tests already use — `(set! escaped h)` inside
the proc), let the scope tear down normally, then tried to trigger a second
release through that captured handle using only the public surface of
`(cmark gfm private scope)`.

`(cmark gfm private scope)` exports exactly six bindings:
`call-with-native-document`, `native-doc?`, `doc-root`, `doc-parser`,
`doc-extensions`, `validate-markdown-input`. `release!` is not among them, and
none of the six forwards to it a second time on an already-torn-down handle
(`call-with-native-document` always builds a fresh handle; the checked accessors
only ever raise `&cmark-dead-document`, they never call `release!`). Confirmed
empirically, not assumed: a standalone probe script that imported the library the
same way a real test file would and then wrote `(release! escaped)` failed to
compile with `attempt to reference unbound identifier release!`.

**Finding, written down as the brief requires:** `release!`'s idempotency is
enforced structurally — there is no code path reachable from outside
`(cmark gfm private scope)` that can invoke it a second time on one handle — not
by a test that exercises the guard itself. This is the same underlying gap as
Mutation C, confirmed from the opposite direction. It is an acceptable answer
per the brief, but it means: if a future change ever exports `release!`, or adds
any new exported function that internally calls it on a handle that isn't freshly
acquired, this idempotency guard would start being live code with zero test
coverage, and that would be the moment to add the test this step tried and failed
to write.

## `make test-memory`

Platform: macOS (Darwin), arm64. Per the Makefile and ADR-0003, this platform runs
an ASan preload with leak detection explicitly disabled
(`ASAN_OPTIONS=detect_leaks=0`) — LeakSanitizer is unsupported on macOS/arm64.

```
macOS: ASan preload only; LeakSanitizer is unsupported on arm64.
Leak claims must come from Linux CI (ADR-0003).
%%%% Starting test conditions
# of expected passes      11
%%%% Starting test lifecycle
# of expected passes      12
%%%% Starting test native
# of expected passes      10
exit=0
```

Confirmed the ASan runtime genuinely loads into the process (not a silent no-op):
a `DYLD_PRINT_LIBRARIES=1` run shows
`libclang_rt.asan_osx_dynamic.dylib` loaded with "interposing tuples," i.e. it is
actively intercepting the allocator.

**What this run does and does not show.** All 33 assertions pass under ASan with
zero sanitizer reports (no use-after-free, no heap-buffer-overflow, no
double-free). It does **not** show the absence of leaks — leak detection is
switched off on this platform, per the Makefile and ADR-0003, and per Stage 0's
own finding (`spike/FINDINGS.md`, Q1) that a DYLD-preloaded ASan against the
prebuilt (Homebrew pkg-config) `libcmark-gfm.dylib` is weaker evidence than a
from-source ASan build in the first place, since this machine's `HAVE_PKG=yes`
path links the prebuilt library, not a source-instrumented one. Leak claims for
this project require Linux CI, per ADR-0003; this run makes no such claim.

## Final clean-tree confirmation

```
$ git status --short
 M README.org
$ make test; echo "exit=$?"
...
ALL SUITES PASSED
exit=0
```

`README.org` is the human's pre-existing, unrelated uncommitted change and was
never touched by this task. No other modification remains. Every mutation above
was individually reverted with `git restore src/cmark/gfm/private/scope.sls` and
confirmed clean before the next one began.

## Carried into Stage 2

- ADR-0005's teardown ordering (Mutation A) has no regression test yet. Stage 2's
  first task must add a render-with-extensions test that fails under ASan when the
  parser is freed before rendering.
- `release!`'s idempotency (Mutations C and H) is enforced only by the absence of
  any caller that invokes it twice, not by a test. If Stage 2 or later introduces
  a code path that could plausibly call it twice (e.g. any new exported function
  taking an existing handle), that is the point to finally write this test.
- The re-entry guard (Mutation G) can only be exercised with a full, multi-shot
  continuation captured inside a scope body and invoked again after teardown.
  Nothing in this project currently needs that capability for its own sake; this
  is recorded as a known, permanent gap rather than a near-term TODO.
- Two §7.4 rows remain entirely out of scope until later machinery exists: the
  post-free AST traversal under Valgrind (needs the Scheme AST) and the renderer
  buffer's libc-`free`/counter mismatch (needs the renderer).
