# Design Spec: Stage 2 — Direct Renderers (release 0.1)

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** Milestone 2 of the project plan; ships as release **0.1** per ADR-0007
- **Related:** [project plan](chez-cmark-gfm-sxml-project-plan.md) §6, §9, §15 · [design spec](2026-08-16-chez-cmark-gfm-design.md) §5, §7.5, §8 · ADR-0005, ADR-0006, ADR-0007

## 1. Scope

Stage 2 turns the Stage 1 lifecycle foundation into a usable library: immutable
options, four direct renderers, and a differential harness proving our option-bit
construction and extension attachment do not alter native semantics.

**Exit criterion** (design spec §8): output matches the pinned `cmark-gfm` CLI across
the option matrix; counters balance; Valgrind clean.

**In scope:** `markdown->html`, `markdown->commonmark`, `markdown->plaintext`,
`markdown->xml`; the options record and its validation; the renderer-buffer lifecycle;
version and capability inspection; the CLI differential harness; release 0.1.

**Out of scope:** the Scheme AST (Stage 3), SXML (Stage 5), `latex` and `man`
renderers, footnotes, and every plan §3 non-goal. Stage 4 owns security hardening;
0.1 nonetheless carries safe-default regression tests because the hostile fixture is
needed anyway to make `unsafe-html?` discriminate (§7.3).

## 2. Module layout

Follows plan §5. No structure the plan did not ask for.

| Path | Layer | Holds native pointers |
|---|---|---|
| `src/cmark/gfm/options.sls` | 3 (public) | **No — imports nothing native** |
| `src/cmark/gfm/render.sls` | 3 (public) | No |
| `src/cmark/gfm.sls` | 3 (façade) | No |
| `src/cmark/gfm/private/scope.sls` | 2 | Yes (extended) |
| `src/cmark/gfm/private/native.sls` | 2 | Yes (extended) |
| `src/cmark/gfm/private/conditions.sls` | 2 | No (extended) |

### 2.1 The functional-core boundary is sharp

`options.sls` imports **no native library at all** — not even `(cmark gfm private
native)`. It holds booleans and symbols and never computes cmark's bit mask;
`render.sls` calls `option-bits` at render time. Two consequences:

- The entire option-validation suite runs with no shared object loaded.
- No assertion in that suite can pass by accident because of native behaviour.

This is the functional core / imperative shell split made structural rather than
aspirational.

### 2.2 Conditions are public by re-export

`conditions.sls` stays under `private/` per plan §5, but plan §12 defines the
condition types as part of the public contract. `(cmark gfm)` therefore re-exports
every condition predicate and accessor. The `private/` path is an implementation
location; for conditions specifically it is not an access-control statement.

## 3. Options — the functional core

### 3.1 Record and defaults

Immutable record, constructed only through the two procedures in §3.2.

| Field | Default | Notes |
|---|---|---|
| `extensions` | `(autolink strikethrough table tagfilter tasklist)` | list of **symbols** |
| `validate-utf8?` | `#t` | behaviourally unreachable — see §10.1 |
| `source-positions?` | `#f` | **diverges from plan §6.2** — ADR-0008 |
| `hardbreaks?` | `#f` | |
| `nobreaks?` | `#f` | |
| `smart?` | `#f` | |
| `unsafe-html?` | `#f` | |
| `max-input-bytes` | `5242880` (5 MiB) | flows into `call-with-native-document`'s 5-argument form |

`source-positions?` defaults off because 0.1 has no AST: the flag's only observable
effect is `data-sourcepos` attributes in HTML and `sourcepos` in XML. Verified, not
assumed — `vendor/cmark-gfm/src/html.c:155` onward emits the attribute at every block,
and `cmark-gfm --sourcepos` on `# hi` produces
`<h1 data-sourcepos="1:1-1:4">hi</h1>`. ADR-0008 records that Stage 3's AST *wants*
source positions and that this default is scoped to renderer-only releases.

### 3.2 Construction

```scheme
(make-cmark-options 'extensions '(table) 'unsafe-html? #t)   ; plist over defaults
(default-cmark-options)                                       ; all defaults
(cmark-options-with opts 'smart? #t)                          ; functional update
```

One pure `validate` runs on the **resulting record** from both constructors, so
`(cmark-options-with o 'hardbreaks? #t)` cannot slip past a check the base object
passed.

### 3.3 Validation rules

Every rejection raises `&cmark-invalid-option` with a `key` (or `#f`) and a `reason`
symbol:

| Reason | Condition |
|---|---|
| `malformed-plist` | odd-length argument list |
| `unknown-key` | key not in the table above |
| `duplicate-key` | same key supplied twice — silently taking the last is a footgun |
| `invalid-value` | wrong type for the key (booleans, symbol list, positive exact integer) |
| `unknown-extension` | extension symbol outside `supported-extensions` |
| `contradictory` | `hardbreaks?` and `nobreaks?` both `#t` |

### 3.4 `hardbreaks?` + `nobreaks?` — corrected premise

Plan §6.2 calls this combination contradictory. **It is not.** Read from
`vendor/cmark-gfm/src/html.c:319-325`: `CMARK_OPT_HARDBREAKS` is tested first and
`CMARK_OPT_NOBREAKS` is its `else if`, so hardbreaks simply wins. Observed:
`--hardbreaks --nobreaks` is byte-identical to `--hardbreaks` alone.

Rejecting the pair is therefore a **policy choice**, not a defence against undefined
behaviour. It is still the right choice: silently discarding one of two explicit
caller requests is exactly the quiet no-op this project refuses elsewhere. Fail
closed.

Consequence: those 16 boolean combinations are unreachable through the public API,
which is why the cartesian sweep excludes them (§7.4).

### 3.5 Extensions are symbols, mapped by data

The public API takes symbols (`'table`); `render.sls` converts at the boundary. The
same reasoning that keeps cmark's numeric constants out of Scheme applies to its
string names.

The mapping lives in `options.sls` as an explicit association list, **not** as a bare
`symbol->string`. Relying on the two spellings happening to coincide would be an
invariant held by luck. A test asserts every entry resolves via
`cmark_find_syntax_extension`, so the mapping is checked rather than assumed (§9).

Validating extension symbols at construction means an unknown extension is rejected
before any native resource exists. Consequence to record:
`&cmark-extension-unavailable` becomes unreachable through the public API and
survives as a private-layer backstop with its existing Stage 1 test.

`supported-extensions` (static, what the API accepts) and
`cmark-gfm-available-extensions` (probed, what the loaded library provides) are
deliberately distinct; §6 covers the latter.

### 3.6 Dropped for 0.1 — YAGNI

`max-nodes` and `max-depth` from plan §6.2 are omitted. Nothing in a renderer-only
release can enforce them; they arrive with the AST in Stage 3. `max-input-bytes`
stays — it is live today in `validate-markdown-input`.

## 4. Renderer buffer lifecycle — the imperative shell

Added to `scope.sls`, which remains the sole owner of native teardown. Splitting
teardown across two libraries would falsify that file's load-bearing header comment.

```scheme
(define (call-with-render-buffer format make-buffer)
  (let ((buf (make-buffer)))
    (when (zero? buf) (raise (make-cmark-render-failed format)))
    (count-buffer-new!)
    (dynamic-wind
      (lambda () #f)
      (lambda () (c-string->string buf))          ; no caller code runs here
      (lambda () (unless (zero? buf)
                   (free-buffer buf)
                   (count-buffer-free!)
                   (set! buf 0))))))
```

Two properties, both structural rather than documented:

1. **The buffer address never reaches a caller-supplied procedure.** `make-buffer` is
   a thunk built inside `render.sls` that only invokes the foreign procedure; the body
   is a single `c-string->string` with no user code. No continuation can be captured
   inside the extent, so ADR-0006's liveness machinery is not needed here — and cannot
   be circumvented by a caller, because there is no caller code inside to capture one.
2. **`(set! buf 0)` after freeing** mirrors `release!`'s discipline, making the
   after-thunk idempotent by construction rather than by argument.

This makes the shim's `chez_cmark_count_buffer_*` counters live for the first time.
`live-buffers` joins every balance assertion, and gets a "counters must move"
discrimination test matching the Stage 1 pattern — without which a counters-free shim
would satisfy every balance test by comparing 0 to 0.

### 4.1 ADR-0005 is enforced by existing machinery

`render.sls` calls `call-with-render-buffer` **inside** `call-with-native-document`'s
body, reading root, extensions, and option bits through the checked accessors. A dead
handle raises `&cmark-dead-document` before any renderer is invoked. Parser-outlives-
render needs no new guard: it is enforced by the liveness flag that already has tests.

## 5. Renderer dispatch and width

Three native signature shapes, confirmed in `vendor/cmark-gfm/src/cmark-gfm.h`:

| Scheme | Native | Arity |
|---|---|---|
| `markdown->html` | `cmark_render_html(root, options, extensions)` | 2 |
| `markdown->xml` | `cmark_render_xml(root, options)` | 2 |
| `markdown->commonmark` | `cmark_render_commonmark(root, options, width)` | 2 or 3 |
| `markdown->plaintext` | `cmark_render_plaintext(root, options, width)` | 2 or 3 |

Only HTML receives the extension list, matching the CLI
(`vendor/cmark-gfm/src/main.c:79` passes `parser->syntax_extensions`) — which is the
same list `cmark_parser_get_syntax_extensions` already stores in the handle.

**Width is a renderer argument, not an options field.** In cmark's own factoring
option bits go to both parser and renderer while width goes only to some renderers;
the Scheme API mirrors that. `markdown->html` and `markdown->xml` are fixed at arity
2, so passing a width to them is an arity error at the call site rather than a
silently ignored field. Plan §6.3 explicitly permits either encoding.

Width is validated as a non-negative exact integer, defaulting to `0` (nowrap) to
match the CLI (`vendor/cmark-gfm/src/main.c:129`). Violations raise
`&cmark-invalid-option` with reason `invalid-width`.

## 6. Version and capability inspection

Per plan §6.1, defined in `(cmark gfm)`:

- `(cmark-gfm-version)` — runtime version string, from a new `cmark_version_string`
  binding.
- `(cmark-gfm-version-compatible?)` — wraps the existing `version-compatible?`.
- `(cmark-gfm-available-extensions)` — **probes** rather than enumerates: calls
  `cmark_find_syntax_extension` on each supported name and returns those that resolve.
  `cmark_list_syntax_extensions` would return a `cmark_llist*` needing Scheme-side
  traversal and its own free; probing adds no allocation to own and reports what is
  actually *usable* rather than merely registered.

`cmark-gfm-version` is not decoration: it is what lets the differential harness prove
the CLI and the loaded library are the same build (§7.1).

## 7. Differential harness

Design spec §7.5: differential tests exist to prove our option-bit construction and
extension attachment do not alter native semantics.

### 7.1 The CLI must be the same build as the loaded library

Diffing Homebrew's CLI against a vendored-linked shim would compare two different
builds and could pass or fail for irrelevant reasons.

- The Makefile resolves `CMARK_CLI` in the **same** `ifeq ($(HAVE_PKG),yes)` branch
  that sets `CMARK_LIBS`: the installed CLI on `PATH`, or
  `build/vendor/src/cmark-gfm`.
- The harness's first assertion compares `cmark-gfm --version` against
  `(cmark-gfm-version)` from the loaded library.

**A missing CLI fails the suite; it does not skip it.** "Skip when unavailable" is how
an exit criterion silently stops being enforced — the same failure shape as the
empty-test rule and the `check-pins` drift. Both supported acquisition paths ship the
binary (CI runs vendored on Linux, pkg-config on macOS), so there is no legitimate
case to accommodate.

### 7.2 Invocation

Write the fixture to `tests/tmp/`, run through `system` with stdout redirected to a
file, check the exit status, read the file. Precedent exists
(`tests/tmp/shim-load-probe-stderr.txt`), and it avoids port deadlock and zombie
handling. Every input is ours; nothing untrusted reaches the shell.

The CLI needs `--validate-utf8` whenever our options set it, since the CLI does not
set `CMARK_OPT_VALIDATE_UTF8` by default (`vendor/cmark-gfm/src/main.c:185`) but our
defaults do. Omitting it would diff against a different parse.

### 7.3 Layer 1 — one factor at a time, with a discrimination guard

From an all-off, no-extension baseline, flip each *observable* boolean — the five
whose effect is visible through the public API, excluding `validate-utf8?` per
§10.1 — and each of the five extensions individually. Ten cells. Per cell:

1. assert the **CLI's own** output changed versus the baseline;
2. assert our output equals the CLI's for the flipped configuration;
3. assert our output equals the CLI's for the baseline.

Step 1 is the load-bearing one. A differential assertion only discriminates if the
flag actually changes output for that fixture: if `--smart` produces identical bytes
for a fixture with no quotes or dashes, step 2 passes whether or not `smart?` is wired
to `CMARK_OPT_SMART` at all. That is an empty test of exactly the kind AGENTS.md
exists to prevent.

Each option must therefore have at least one `(fixture, format)` pair where
discrimination is proven. Expect this to force at least one baseline adjustment during
implementation: `tagfilter` likely cannot discriminate without `unsafe-html?` also
set, because raw HTML is already suppressed entirely under safe mode. Discovering that
is the point — the guard converts "I believe this cell tests something" into a
mechanically enforced fact.

This layer is also what catches an argument transposition in `option-bits`, whose C
signature is six consecutive `int` parameters
(`chez_cmark_option_bits(validate_utf8, sourcepos, hardbreaks, nobreaks, smart,
unsafe_html)`). Swapping two would be invisible to a bit-distinctness check but breaks
the named OFAT cell for both swapped options.

### 7.4 Layer 2 — cartesian bulk sweep

All 48 valid boolean combinations (64 minus the 16 §3.4 rejects) × 4 formats × 2
fixtures = 384 CLI invocations, extensions pinned to the default five. Parity only, no
discrimination guard. A few seconds of subprocess time.

Note the sweep's effective width: because `validate-utf8?` is behaviourally
unreachable (§10.1), those 48 combinations exercise **24 distinct behaviours, each
tested twice**. The redundancy is cheap and confirms the flag breaks nothing, but the
figure to quote when describing coverage is 24, not 48.

### 7.5 Fixtures

`tests/fixtures/`:

| Fixture | Purpose |
|---|---|
| `core.md` | CommonMark spread: headings, emphasis, tight and loose lists, links, images, code span, fenced code with info string, blockquote, thematic break, soft and hard breaks |
| `gfm.md` | Table with alignments, strikethrough, autolink, checked and unchecked task items |
| `smart.md` | Quotes, em and en dashes, ellipses — so `smart?` can discriminate |
| `hostile.md` | Plan §13.4's corpus — so `unsafe-html?` can discriminate, and 0.1 gets safe-default regressions early |

## 8. Testing and exit gate

### 8.1 Suites

Each ends in its own `(exit …)` — SRFI-64 sets no process exit status, and a suite
missing that line reports success through real failures.

| Suite | Covers |
|---|---|
| `tests/test-options.sps` | Pure. Defaults, every validation rejection reason, functional update re-validation. Loads no shared object. |
| `tests/test-render.sps` | The four renderers, buffer counter balance **and movement**, dead-handle rejection, width validation, extension-name mapping resolves natively, safe-by-default spot checks |
| `tests/test-differential.sps` | §7's two layers |

The Makefile's `TESTS` wildcard picks them up with no edit.

`test-memory` gains a named `MEMORY_TESTS := $(filter-out
tests/test-differential.sps,$(TESTS))`. Those 384 subprocesses are not
Valgrind-instrumented and add no memory coverage `test-render.sps` does not already
provide.

### 8.2 Exit gate

1. Layers 1 and 2 green — output matches the pinned CLI across the option matrix.
2. `live-buffers` included in every balance assertion, plus a movement test.
3. Linux CI `make test-memory` clean under Valgrind.
4. `.plans/stage-2-mutation-log.md` in the Stage 1 format.

### 8.3 Planned mutations

Each must break its named test, or be recorded as uncovered with a reason:

| # | Mutation | Expected to break |
|---|---|---|
| A | Transpose two `chez_cmark_option_bits` arguments | The OFAT cells for both swapped options |
| B | Drop the extension list from the `cmark_render_html` call | The `tagfilter` escaping assertion and the tagfilter differential cell — **not** tables or strikethrough; see §13 |
| C | Free the buffer before copying it | The render suite, and ASan/Valgrind |
| D | Delete `count-buffer-free!` | Buffer balance assertions |
| E | Remove the `hardbreaks?`/`nobreaks?` rejection | A named options test |
| F | Make `cmark-options-with` skip validation | A named options test |
| G | Flip the `source-positions?` default to `#t` | A named defaults test, and HTML parity cells |
| H | Change one extension's mapped string | The mapping-resolves test, and that extension's OFAT cell |

## 9. Invariants enforced as checks, not comments

Per AGENTS.md: when about to write a comment stating an invariant, ask whether it can
be a make target, a test, or an assertion.

| Invariant | Enforcement |
|---|---|
| Width does not apply to HTML or XML | Fixed arity 2 — arity error at the call site |
| The CLI is the same build as the loaded library | First assertion in `test-differential.sps` |
| Every differential cell tests something | Per-cell discrimination guard (§7.3) |
| The buffer address never escapes | No caller code runs inside the extent (§4) |
| The buffer is freed exactly once | `(set! buf 0)` after freeing |
| Parser outlives rendering (ADR-0005) | Checked accessors on a live handle |
| Options are validated after functional update | One `validate` shared by both constructors |
| Our extension names match cmark's | Explicit alist plus a resolves-natively test |
| The counters actually count | "Counters must move" assertion |
| `options.sls` loads no native code | `make check-purity` |

## 10. Deliberate coverage gaps

Recorded here and in the Stage 2 mutation log rather than papered over.

### 10.1 `validate-utf8?` is behaviourally unreachable

The public API takes a Scheme string, and `string->utf8` always produces valid UTF-8.
`CMARK_OPT_VALIDATE_UTF8` therefore has no observable effect on any input reachable
through `markdown->*`. No differential cell can discriminate it: the CLI can be fed
invalid bytes from a file, we cannot.

Rather than ship an assertion that passes either way, test what *is* testable — that
the bit is wired, via `(option-bits #t …)` ≠ `(option-bits #f …)` — and record the
behavioural property as structurally uncovered, with this reason. The option stays
exposed: plan §6.2 names it, it costs nothing, and it stays correct if the input path
ever widens to bytevectors.

### 10.2 `&cmark-extension-unavailable` is unreachable from the public API

By design (§3.5). It keeps its Stage 1 private-layer test.

## 11. Release 0.1

- `Akku.manifest`: `0.1.0-alpha` → `0.1.0`.
- `CHANGELOG.md`: first entry (the file is currently empty).
- `README.org`: usage examples for the four renderers and the options API.
- **ADR-0008**: the `source-positions?` divergence from plan §6.2, recording that
  Stage 3's AST wants source positions and that `#f` is scoped to renderer-only
  releases — to be revisited, possibly per-entry-point, when `markdown->ast` lands.

The options-plist shape (§3.2) and width-as-argument (§5) are recorded here rather
than as ADRs: they are API shape, not project-shaping corrections. ADRs 0001–0007 are
reserved for decisions and corrections of that weight.

## 12. References

- `.plans/chez-cmark-gfm-sxml-project-plan.md` — §6 public API, §9 memory, §15 M2
- `.plans/2026-08-16-chez-cmark-gfm-design.md` — §5 ownership, §7.5 differential, §8 stages
- `.plans/decisions/0005-parser-outlives-rendering.md`
- `.plans/decisions/0006-liveness-flag-with-dynamic-wind.md`
- `.plans/decisions/0007-incremental-release-staging.md`
- `spike/FINDINGS.md` — Q1 string marshalling, Q2 ASan detection of the ADR-0005 defect
- `vendor/cmark-gfm/src/cmark-gfm.h` — renderer signatures
- `vendor/cmark-gfm/src/html.c` — softbreak precedence, sourcepos emission
- `vendor/cmark-gfm/src/main.c` — CLI defaults and flag handling

---

## 13. Correction: what the HTML renderer's extension list actually controls

Recorded during Stage 2 implementation, verified against `vendor/cmark-gfm/` and the
pinned CLI rather than inferred.

§5 states that only `cmark_render_html` receives the extension list. True — but this
spec, and the plan derived from it, implied the list is what makes **extension nodes**
render. It is not.

- `src/html.c:480-485` filters the `extensions` argument down to only those extensions
  having an `html_filter_func`, storing them as `renderer.filter_extensions`.
- `extensions/tagfilter.c` is the **only** core extension that sets one.
- Extension *node* rendering — tables, strikethrough, tasklists — dispatches through
  each node's own `->extension` pointer, set at **parse** time (`src/html.c:142-144`),
  and is entirely unaffected by the render-time argument.

Observed, `cmark-gfm` on `<script>alert(1)</script>`:

| Flags | Output |
|---|---|
| `--unsafe -e tagfilter` | `&lt;script>alert(1)&lt;/script>` |
| `--unsafe` | `<script>alert(1)</script>` |
| `-e tagfilter` (safe) | `<!-- raw HTML omitted -->` |

Note tagfilter escapes only the opening `<`.

**Consequences.**

1. The list's only observable effect is tagfilter's escaping, and only under
   `unsafe-html?`. Safe mode suppresses raw HTML wholesale first, so tagfilter is
   invisible there — which independently confirms §7.3's prediction that the tagfilter
   OFAT cell needs `unsafe-html?` in its baseline.
2. Mutation B must break the tagfilter assertion, not a table one. A plan that expected
   tables to break would have recorded a passing mutation as evidence of coverage it
   did not have. `tests/test-render.sps` now carries the assertion that does fail.
3. **ADR-0005 is unaffected.** `cmark_parser_free` frees `parser->syntax_extensions`,
   and `cmark_render_html` walks that same list at `html.c:480` — so the
   use-after-free the Stage 0 spike caught under AddressSanitizer is real regardless of
   what the list is subsequently used for.

---

## 14. Limitation: the sweep cannot detect a wrong default

Found by mutation G during Stage 2 and recorded here so no future reader over-trusts
the harness.

`config->flags` derives the CLI's flags from the same options record it renders with
(`tests/test-differential.sps:69-88` — `config->flags` calls `config->options`, which
is `(apply make-cmark-options cfg)`). That is deliberate: one value drives both sides,
so the two can never describe different configurations by accident.

The cost is that **a change to a default moves both sides together.** Flipping the
`source-positions?` default made every `default options agree with the CLI` cell
compare our sourcepos output against the CLI invoked *with* `--sourcepos` — and they
matched, so all four cells passed. The sweep answers "given a config, do we produce
what the CLI produces for that config", which is §7.5's actual question. It does not
and cannot answer "is this the right default".

Defaults are covered instead by the explicit per-field assertions in
`tests/test-options.sps` and the `data-sourcepos` on/off pair in
`tests/test-render.sps` — mutation G failed seven named tests across three suites, so
the property is well guarded. Just not by the layer one might assume.
