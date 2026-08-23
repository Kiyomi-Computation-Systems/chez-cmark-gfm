# Public API Reference Implementation Plan

**Goal:** Add an authored `docs/reference.md` covering every export of every
non-private chez-cmark-gfm module, publish it through the existing site, and
make source/reference drift fail by name.

**Architecture:** `(site reference)` is a pure functional core that analyses
R6RS library datums and the constrained structure of the Markdown reference.
`tests/reference-check.sps` is the imperative shell that reads the real source
and document. The existing site remains the renderer. `site/render.sls` keeps
all heading ids in its registry but limits the visible right rail to h2
sections so 85 h3 binding entries do not overwhelm it.

**Tech stack:** Chez Scheme 9.5.8+ and R6RS, SRFI-64, Markdown, GNU Make, the
existing Markdown -> SXML site generator.

**Design:** `.plans/2026-08-23-api-reference-design.md`

## Global constraints

- Do not change any export or runtime behaviour under `src/`.
- Treat `(cmark gfm)` as canonical while documenting all six non-private
  modules.
- Cover the 85-identifier union, including `extension->native-name`.
- Do not document constructors exported only from
  `(cmark gfm private conditions)`.
- Read export forms from source. Do not maintain a second hand-written export
  inventory inside the checker.
- Keep `(site reference)` pure: `(rnrs)` only, no filesystem, no site renderer,
  and no native import.
- The real checker must reject empty discovery and empty reference data; it
  must never succeed because both sides accidentally became `()`.
- The only binding-coverage signal in Markdown is a valid level-three entry
  heading. Mentions in prose, examples, the module table, and the alphabetical
  index do not count.
- Every new SRFI-64 assertion is watched failing for its intended reason before
  it is accepted. Every suite ends with its own `(exit ...)`; nothing follows
  it.
- Apply mutations to scratch copies outside the repository, record the exact
  named failure, revert by discarding the scratch copy, and rerun the clean
  version green.
- Keep `.PHONY` on one physical line and give `check-reference` a `## ` help
  description.
- Generated `build/site/` content remains ignored and uncommitted.
- Do not commit, push, or open a pull request unless the user separately asks.

## Files

### Create

| Path | Responsibility |
|---|---|
| `docs/reference.md` | authored API reference |
| `site/reference.sls` | pure reference-analysis core |
| `tests/test-reference.sps` | pure unit suite |
| `tests/reference-check.sps` | real source/document gate |
| `.plans/api-reference-mutation-log.md` | proof that new checks fail |

### Modify

| Path | Change |
|---|---|
| `Makefile` | add `check-reference`, compose into `check-site`, update `.PHONY` |
| `site/render.sls` | display h2 only in the right-rail TOC |
| `tests/test-site-render.sps` | distinguish registry/body h3 from rail h3 |
| `site/pages.sls` | add `reference.md` after `usage.md` |
| `site/index.md` | add API reference to Read next |
| `README.org` | add API reference to Documentation |
| `CHANGELOG.md` | add an Unreleased bullet |

---

## Task 0: Baseline and work boundary

- [ ] Confirm `git status --short --branch` is clean. If it is not, identify
  unrelated user changes and keep this work away from them.
- [ ] Record the current public source set:

  ```text
  src/cmark/gfm.sls
  src/cmark/gfm/options.sls
  src/cmark/gfm/render.sls
  src/cmark/gfm/parse.sls
  src/cmark/gfm/ast.sls
  src/cmark/gfm/sxml.sls
  ```

- [ ] Run the relevant baseline gates:

  ```text
  make test
  make check-site
  make check-help
  ```

- [ ] Record their success in the implementation notes. Do not treat an
  existing failure as caused by this task.

Expected baseline: all existing suites pass, `check-site` validates the nine
current generated pages (home plus eight docs), and the worktree remains
clean.

---

## Task 1: Pure library/export analysis

**Files:**

- Create `tests/test-reference.sps`
- Create `site/reference.sls`

### Interface

Keep the public surface of `(site reference)` small:

```scheme
(library-datum->api datum)
  -> (values module-name exports problem)

(markdown->reference-analysis markdown)
  -> reference-analysis

(reference-analysis-modules analysis)
(reference-analysis-entries analysis)
(reference-analysis-problems analysis)

(reference-diagnostics module-apis analysis)
  -> ((diagnostic-tag . values) ...)
```

`module-name` is the R6RS library-name list. `exports` is a list of symbols.
`problem` is `#f` on success or a tagged datum such as
`(unsupported-export-spec (rename old new))`.

Each parsed reference entry carries at least
`(name kind available-modules body-present?)`. Internal records and additional
accessors are fine, but do not export generic string utilities that no caller
needs.

`reference-diagnostics` returns only non-empty diagnostics, in deterministic
tag and lexical value order. Its possible tags are:

```text
no-public-modules
no-public-bindings
no-reference-modules
no-reference-bindings
unsupported-export-specs
missing-modules
extra-modules
duplicate-modules
missing-bindings
extra-bindings
duplicate-bindings
empty-entry-bodies
missing-availability
duplicate-availability
module-membership-mismatches
malformed-entry-headings
```

### Step 1: Write the failing unit suite

- [ ] Create `tests/test-reference.sps` importing `(site reference)` before
  that library exists.
- [ ] Cover these fixtures with exact expected values:

  1. `(library (demo) (export a b c) (import (rnrs)) ...)` produces module
     `(demo)` and exports `(a b c)` in declaration order.
  2. A `(rename ...)` export produces `unsupported-export-spec`, not an empty
     export and not a raw matcher error.
  3. Only rows inside `## Modules` whose first cell is a code-formatted module
     count as module rows.
  4. `### \`markdown->html\` (procedure)` produces the binding symbol and
     kind.
  5. A mention of `markdown->html` in prose, a code fence, or the Alphabetical
     index produces no binding entry.
  6. Two headings for one binding produce `duplicate-bindings`.
  7. Every entry requires exactly one `**Available from:**` line, from which
     module-name lists are extracted.
  8. A missing or repeated availability line produces its own named
     diagnostic.
  9. A heading with an availability line but no signature or prose before the
     next h2/h3 or EOF produces `empty-entry-bodies`; metadata alone is not a
     substantive entry.
  10. Synthetic source `(a b)` versus reference `(a c)` produces
     `missing-bindings=(b)` and `extra-bindings=(c)`.
  11. Module set differences are reported independently from binding set
     differences.
  12. An entry's documented module set is compared with the modules that
      actually export it, in both directions.
  13. Empty module APIs and empty reference analysis produce the explicit
      `no-*` diagnostics; they never return success.

- [ ] Make every expected-success assertion compare with a positive sentinel
  such as `'agree`, not truthiness or `#f`.
- [ ] End the suite with:

  ```scheme
  (exit (if (zero? (test-runner-fail-count runner)) 0 1))
  ```

- [ ] Run the suite and confirm it fails because `(site reference)` does not
  exist. This is only the red starting point, not mutation proof for any
  assertion.

### Step 2: Implement the pure core

- [ ] Read a library datum structurally:
  - first element must be `library`;
  - second element is the module name;
  - the first body form headed by `export` supplies export specs;
  - every current export spec must be a symbol;
  - any other export shape becomes an explicit problem.
- [ ] Parse Markdown line by line. Do not build a general Markdown parser;
  this checker owns one deliberately constrained authoring convention.
- [ ] Recognize the `## Modules` section and stop module-row parsing at the
  next h2.
- [ ] Recognize binding headings only when they match:

  ```text
  ### `<identifier>` (<allowed-kind>)
  ```

- [ ] Allow exactly these kinds:

  ```text
  procedure
  record constructor
  predicate
  accessor
  condition type
  ```

- [ ] Preserve duplicates until diagnostics are calculated. Do not deduplicate
  early and thereby erase evidence.
- [ ] Count an entry body only when a nonblank, non-comment line occurs before
  the next h2/h3 or EOF, excluding the `Available from` metadata line.
- [ ] Require exactly one `Available from` line per entry and parse every
  code-formatted module name on it.
- [ ] Invert the source APIs into binding -> exporting modules and compare that
  set with each entry's availability line.
- [ ] Sort diagnostic values for deterministic output without sorting the
  authored entry order itself.
- [ ] Run `tests/test-reference.sps`; confirm all assertions pass.

### Step 3: Mutation-proof Task 1

For each mutation, copy `site/reference.sls` under a temporary root as
`<scratch>/site/reference.sls`, put that root first in
`CHEZSCHEMELIBDIRS`, and run the unchanged unit suite.

- [ ] Break export traversal so the final symbol is dropped. Confirm the test
  named for full declaration-order extraction fails, not import or syntax.
- [ ] Broaden the heading recognizer so an inline-code mention in the index is
  counted. Confirm the test excluding index mentions fails by name.
- [ ] Deduplicate entries before diagnostics. Confirm the duplicate-binding
  test fails by name.
- [ ] Treat a blank entry as substantive. Confirm the empty-body test fails by
  name.
- [ ] Skip module-membership comparison. Confirm the fixture with a missing
  exporting module fails by name.
- [ ] Replace the empty-input diagnostics with ordinary set comparison.
  Confirm the no-public-modules/no-reference-bindings assertion fails by name.
- [ ] Discard the scratch root, rerun the clean suite, and record all evidence
  in `.plans/api-reference-mutation-log.md`.

---

## Task 2: The real-tree gate

**Files:**

- Create `tests/reference-check.sps`
- Modify `Makefile`

### Step 1: Write the shell

- [ ] Implement local file-reading helpers in `tests/reference-check.sps`.
  Do not import `(site io)`, because it imports `(site render)` and would turn
  this static documentation check into a native load.
- [ ] Discover public source files as:
  - the fixed root `src/cmark/gfm.sls`; and
  - every immediate filename ending in `.sls` returned from
    `src/cmark/gfm/`.
- [ ] Do not recurse into its `private` directory.
- [ ] Read the first datum from each source file with `read`; Chez skips the
  leading `#!r6rs` directive and comments.
- [ ] If `docs/reference.md` does not exist, fail explicitly with:

  ```text
  check-reference: reference page missing: docs/reference.md
  ```

- [ ] Format every diagnostic on stderr by its tag. Exit 1 if any exists.
- [ ] On success print only a positive, counted result:

  ```text
  check-reference: COMPLETE -- 6 modules, 85 unique bindings
  ```

### Step 2: Add the Make target first

- [ ] Add `check-reference` to the single physical `.PHONY` line.
- [ ] Add:

  ```make
  check-reference: ## Verify API reference modules and bindings match source exports
  ```

  running `tests/reference-check.sps` with the repository's existing
  `CHEZSCHEMELIBDIRS` convention.
- [ ] Make `check-site` depend on both `check-reference` and `build`.
- [ ] Run `make check-help`; it must remain green.
- [ ] Run `make check-reference` before creating the document. Confirm the
  named missing-page failure and non-zero status.

This red state proves the shell is reached. It does not yet prove the coverage
decisions; those mutations come after real content exists.

---

## Task 3: Reference foundation, modules, entry points, and capabilities

**File:** Create `docs/reference.md`

### Step 1: Page frame

- [ ] Add the h1, a short statement that `(cmark gfm)` is canonical, and the
  distinction between this lookup page and the deeper topic pages.
- [ ] Add the exact six-row module table. State which modules are pure and
  which instantiate the native binding.
- [ ] In `## Conventions`, define:
  - Markdown arguments are Scheme strings;
  - option records are immutable;
  - widths are exact non-negative integers;
  - ASTs and SXML are Scheme-owned after conversion;
  - `->` in the displayed signatures describes the return, not Scheme syntax;
  - `#f` may be a legitimate field value and should not be confused with
    absence where a default argument exists.

### Step 2: Rendering and conversion entries

- [ ] Add one substantive h3 entry for each:

  ```text
  markdown->html
  markdown->commonmark
  markdown->plaintext
  markdown->xml
  markdown->ast
  markdown->sxml
  markdown-ast->sxml
  ```

- [ ] Read arities from `render.sls`, `parse.sls`, `gfm.sls`, and `sxml.sls`.
- [ ] Link detailed rendering behaviour to `usage.md`, AST behaviour to
  `ast.md`, and SXML behaviour to `sxml.md`.
- [ ] State that `markdown->sxml` is available only through the umbrella,
  while `markdown-ast->sxml` is also the sole export of `(cmark gfm sxml)`.
- [ ] State refused SXML-inapplicable cmark options exactly as documented in
  `sxml.md`; do not paraphrase them into a broader rule.

### Step 3: Runtime and capability entries

- [ ] Add:

  ```text
  cmark-gfm-version
  cmark-gfm-version-compatible?
  cmark-gfm-available-extensions
  ```

- [ ] Distinguish `supported-extensions` (the binding's known symbolic set,
  documented with options) from `cmark-gfm-available-extensions` (what the
  loaded native runtime actually provides).
- [ ] Preserve the diagnostic purpose of `cmark-gfm-version`: it reports the
  runtime version without first demanding compatibility.

- [ ] Run `make check-reference`. Expect a real, non-empty list of the still
  missing option, AST, and condition bindings. Confirm the entries just added
  are absent from that missing list.

---

## Task 4: Options reference entries

**File:** Modify `docs/reference.md`

### Step 1: cmark options -- 17 entries

- [ ] Add:

  ```text
  make-cmark-options
  default-cmark-options
  cmark-options-with
  cmark-options?
  cmark-options-extensions
  cmark-options-validate-utf8?
  cmark-options-source-positions?
  cmark-options-hardbreaks?
  cmark-options-nobreaks?
  cmark-options-smart?
  cmark-options-unsafe-html?
  cmark-options-max-input-bytes
  cmark-options-max-nodes
  cmark-options-max-depth
  default-ast-options
  supported-extensions
  extension->native-name
  ```

- [ ] For constructors and update, state the property-list calling convention,
  immutability, duplicate-key policy, and shared validation path.
- [ ] For accessors, state the exact return kind and link to the defaults table
  rather than duplicating all option semantics.
- [ ] For `default-ast-options`, state the one intentional default difference:
  source positions are on.
- [ ] For `extension->native-name`, state that it is exported only from
  `(cmark gfm options)` and can raise `&cmark-invalid-option` for an unknown
  extension symbol.

### Step 2: SXML options -- 7 entries

- [ ] Add:

  ```text
  make-sxml-options
  default-sxml-options
  sxml-options-with
  sxml-options?
  sxml-options-raw-html
  sxml-options-softbreak
  sxml-options-attribute-marker
  ```

- [ ] Use the exact accepted symbolic values from `options.sls` and
  `docs/sxml.md`.
- [ ] Make clear that these options govern the Scheme SXML adapter, not cmark's
  parser or native renderers.
- [ ] Run `make check-reference`; only AST and condition bindings should remain
  missing.

---

## Task 5: AST and source-position entries

**File:** Modify `docs/reference.md`

### Step 1: markdown-node -- 11 entries

- [ ] Add:

  ```text
  make-markdown-node
  markdown-node?
  markdown-node-type
  markdown-node-properties
  markdown-node-children
  markdown-node-source
  markdown-node-property
  markdown-node-with-properties
  markdown-node-with-children
  markdown-node-map
  markdown-node-fold
  ```

- [ ] State constructor field order exactly.
- [ ] For `markdown-node-property`, document both arities and why an explicit
  default distinguishes absence from a legitimate `#f` property value.
- [ ] For functional updates, state that the original is unchanged and name
  the fields preserved from it.
- [ ] For traversal, state `markdown-node-map` is children-first/bottom-up and
  `markdown-node-fold` is parent-first/pre-order, children left to right.
- [ ] State that wrong record types reach ordinary R6RS assertion behaviour,
  not a fabricated `&cmark-error` subtype.

### Step 2: source-position -- 6 entries

- [ ] Add:

  ```text
  make-source-position
  source-position?
  source-position-start-line
  source-position-start-column
  source-position-end-line
  source-position-end-column
  ```

- [ ] State constructor order and exact-integer return values.
- [ ] Link to `ast.md` for when the node source field is `#f`.
- [ ] Repeat the security boundary once at the group introduction: AST content
  is untrusted structured input and is not sanitized by parsing.
- [ ] Run `make check-reference`; only condition bindings should remain
  missing.

---

## Task 6: Condition entries

**File:** Modify `docs/reference.md`

Add the 34 public bindings below. Keep each family adjacent: condition type,
predicate, then accessors.

### Base family -- 2

```text
&cmark-error
cmark-error?
```

### Version incompatibility -- 4

```text
&cmark-version-incompatible
cmark-version-incompatible?
cmark-version-incompatible-supported
cmark-version-incompatible-runtime
```

### Dead document -- 2

```text
&cmark-dead-document
cmark-dead-document?
```

### Extension unavailable -- 3

```text
&cmark-extension-unavailable
cmark-extension-unavailable?
cmark-extension-unavailable-name
```

### Invalid input -- 3

```text
&cmark-invalid-input
cmark-invalid-input?
cmark-invalid-input-reason
```

### Resource limit -- 3

```text
&cmark-resource-limit
cmark-resource-limit?
cmark-resource-limit-value
```

### Library unavailable -- 4

```text
&cmark-library-unavailable
cmark-library-unavailable?
cmark-library-unavailable-path
cmark-library-unavailable-reason
```

### Invalid option -- 4

```text
&cmark-invalid-option
cmark-invalid-option?
cmark-invalid-option-key
cmark-invalid-option-reason
```

### Render failure -- 3

```text
&cmark-render-failed
cmark-render-failed?
cmark-render-failed-format
```

### Unsupported node -- 3

```text
&cmark-unsupported-node
cmark-unsupported-node?
cmark-unsupported-node-type
```

### Malformed tree -- 3

```text
&cmark-malformed-tree
cmark-malformed-tree?
cmark-malformed-tree-reason
```

- [ ] For each condition type, name its parent exactly. In particular,
  `&cmark-resource-limit` derives from `&cmark-invalid-input`, while
  `&cmark-unsupported-node` and `&cmark-malformed-tree` do not.
- [ ] For each accessor, state the value shape and link to the reason/value
  table in `errors.md` rather than copying its full enumeration.
- [ ] Do not list any `make-cmark-*` condition constructor; none is re-exported
  by `(cmark gfm)`.
- [ ] Where a condition is unreachable through ordinary public calls, say so
  as `errors.md` does instead of inventing an example that uses private
  constructors.
- [ ] Run `make check-reference`. It must print the counted COMPLETE sentinel:
  6 modules and 85 unique bindings.

---

## Task 7: Alphabetical index and deep links

**File:** Modify `docs/reference.md`

- [ ] Add one alphabetical list item for each of the 85 entry headings.
- [ ] Link to the slug implied by the complete heading text, including its
  kind suffix. Representative forms:

  ```text
  markdown-html-procedure
  cmark-error-condition-type
  cmark-error-predicate
  cmark-options-extensions-accessor
  ```

- [ ] Derive slugs with the existing `(site slug)` implementation; do not
  hand-wave punctuation rules.
- [ ] Keep the index outside binding-entry h3s so its identifiers do not count
  toward coverage.
- [ ] Run `make check-reference` again; adding the index must not create
  duplicate or extra bindings.
- [ ] Defer anchor validation until the page is registered with the site in
  Task 9.

---

## Task 8: Keep h3 bindings out of the right rail

**Files:**

- Modify `tests/test-site-render.sps`
- Modify `site/render.sls`

### Step 1: Write the failing integration assertion

- [ ] Add a synthetic page containing one h2 category and one h3 binding.
- [ ] Render it through `render-site`.
- [ ] Assert with positive sentinels that:
  - the result registry contains both h2 and h3 slugs;
  - the rendered body contains `id="..."` for the h3;
  - the right rail contains `href="#..."` for the h2; and
  - no right-rail link exists for the h3.
- [ ] Make the last distinction on `href`, not on raw slug text: the body must
  still contain the h3 id.
- [ ] Run only `tests/test-site-render.sps` and confirm the h3-rail assertion
  fails by name against the current `> 1` policy.

### Step 2: Narrow the rail policy

- [ ] Change `rail-toc` in `site/render.sls` to retain level 2 only.
- [ ] Do not change `transform-body` or the registry; all heading levels remain
  linkable.
- [ ] Rerun `tests/test-site-render.sps`; confirm pass.

### Step 3: Mutation proof

- [ ] Put a scratch copy of mutated `site/render.sls` first on the library
  path, restore the old `> 1` predicate there, and run the unchanged test.
- [ ] Confirm the new assertion fails by its h3-rail name.
- [ ] Discard the scratch copy, rerun green, and record the evidence.

---

## Task 9: Navigation and reader entry points

**Files:**

- Modify `site/pages.sls`
- Modify `site/index.md`
- Modify `README.org`
- Modify `CHANGELOG.md`

### Step 1: Observe the existing nav gate go red

- [ ] Before changing `site/pages.sls`, run `make check-site` with the complete
  `docs/reference.md` present.
- [ ] Confirm the already-proven nav-completeness invariant fails by name with
  `reference.md` missing from the registry. This is evidence that the new page
  cannot be silently omitted from the site.

### Step 2: Register and link the page

- [ ] Add `("reference.md" . "API reference")` immediately after
  `usage.md` in `site/pages.sls`.
- [ ] Add an API reference item after Usage in `site/index.md`'s Read next
  list.
- [ ] Add a matching row after Usage in `README.org`'s Documentation table.
- [ ] Add an Unreleased `CHANGELOG.md` bullet covering both the authored page
  and the executable export-coverage gate.
- [ ] Do not revise historical plans or the 2.0.0 changelog text that records
  the earlier eight-page state.

### Step 3: Check navigation and links

- [ ] Run `make check-reference`.
- [ ] Run `make check-site`; all module/detail/index links and all generated
  entry anchors must resolve.
- [ ] If an index link dangles, inspect the actual generated slug from the
  registry. Fix the authored link; do not weaken anchor validation.
- [ ] Confirm prev/next for the reference page are Usage and Options.

---

## Task 10: Real-check mutations

**Files:** scratch copies only; append evidence to
`.plans/api-reference-mutation-log.md`.

Build a minimal scratch root containing:

```text
docs/reference.md
site/reference.sls
tests/reference-check.sps
src/cmark/gfm.sls
src/cmark/gfm/{options,render,parse,ast,sxml}.sls
```

Run the checker from that scratch working directory with the scratch root
first on `CHEZSCHEMELIBDIRS`. Edit scratch files with `apply_patch`.

- [ ] Delete the `markdown->html` entry, including its body. Confirm:

  ```text
  missing-bindings=(markdown->html)
  ```

- [ ] Starting clean, rename only its heading to `markdown->htlm`. Confirm the
  diagnostic names both the missing real export and extra typo.
- [ ] Starting clean, duplicate the complete entry. Confirm
  `duplicate-bindings=(markdown->html)`.
- [ ] Starting clean, delete only its substantive body. Leave its
  `Available from` line intact and confirm
  `empty-entry-bodies=(markdown->html)` rather than missing binding.
- [ ] Starting clean, delete the `(cmark gfm sxml)` module-table row. Confirm
  `missing-modules=((cmark gfm sxml))`.
- [ ] Starting clean, remove `(cmark gfm render)` only from
  `markdown->html`'s `Available from` line. Confirm
  `module-membership-mismatches` names the binding and missing module.
- [ ] Starting clean, break source export extraction in the scratch
  `site/reference.sls` so it drops one export. Confirm the checker reports the
  reference entry as extra; a parser that undercounts cannot pass green.
- [ ] After every mutation, restore from a clean scratch copy rather than
  layering mutations.
- [ ] Run the unmutated repository's `make check-reference` after all
  mutations and record the counted COMPLETE line.

Do not accept a mutation failure caused by malformed Markdown, Scheme syntax,
or a missing import. The named coverage/body/module property must be what
fails.

---

## Task 11: Full verification and visual review

- [ ] Run:

  ```text
  make test
  make check-reference
  make check-site
  make site
  make check-help
  git diff --check
  ```

- [ ] Inspect `build/site/reference.html` in a browser at desktop width:
  - sidebar order is correct;
  - right rail contains the nine level-two sections, not 85 bindings;
  - typography remains readable for the long page;
  - module table does not overflow;
  - representative binding anchors land correctly;
  - condition identifiers containing `&` render escaped as text, not markup;
  - code signatures preserve `->`, `?`, and quoted symbols.
- [ ] Inspect at or below 640px:
  - sidebar wraps without hiding API reference;
  - tables and code blocks remain horizontally usable;
  - the intentionally hidden right rail does not leave an empty column.
- [ ] Verify generated `build/site/*` remains ignored and unstaged.
- [ ] Review `git diff` for accidental edits under `src/`, historical plan
  rewrites, or duplicated explanations copied from topic pages.
- [ ] Confirm final `git status --short` lists only the planned source,
  documentation, test, Makefile, and plan changes.

## Completion report

Report:

- the page and navigation location;
- six modules / 85 unique bindings covered;
- the exact green gate results;
- each mutation and the named failure it triggered;
- the h3 registry-versus-rail evidence;
- visual verification at desktop and narrow widths; and
- that no runtime export or behaviour changed.
