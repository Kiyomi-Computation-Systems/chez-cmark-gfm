# chez-cmark-gfm Stage 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `markdown->ast` — an immutable, Scheme-owned Markdown AST that contains no native pointers and stays valid after every cmark object is freed — plus the two resource limits it makes necessary, and ship release 0.2.

**Architecture:** A pure functional core (`ast.sls`) holding the node and source-position records, over an imperative shell (`private/convert.sls`) that walks native nodes through the Stage 1 checked accessors and copies every borrowed string on read. A new layer-3 entry point (`parse.sls`) unpacks the options record into primitives so layer 2 never imports layer 3, mirroring how `render.sls` unpacks option bits. Correctness is proved by re-serializing our AST into cmark's own XML dialect and diffing byte-for-byte against `cmark_render_xml` and the pinned CLI — an oracle that cannot be tuned to accommodate a converter bug.

**Tech Stack:** Chez Scheme 10.4.1, C99, cmark-gfm 0.29.0.gfm.13, SRFI-64 (vendored chez-srfi), Make, Valgrind (Linux) / AddressSanitizer (macOS).

**Source documents:**
- Design spec: `.plans/2026-08-17-stage-3-ast-design.md` — read this first; every §-reference below points at it
- Stage 2 plan: `.plans/2026-08-16-stage-2-implementation.md`
- Project plan: `.plans/chez-cmark-gfm-sxml-project-plan.md` §6.4, §7, §9.7, §12, §13.2
- ADRs: `.plans/decisions/0002`, `0005`, `0006`, `0007`, `0008`

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Chez Scheme** 10.4.1 or later. The binary is `chez` (**not** `scheme`); `petite` cannot compile and must not be used for tests.
- **cmark-gfm** pinned to `0.29.0.gfm.13`; supported range `0.29.0.gfm.x`.
- **Read cmark's semantics from `vendor/cmark-gfm/`, never from recall.** Every claim in the design spec carries a `file:line`. Verify before trusting.
- **Numeric cmark constants never appear in Scheme.** Dispatch on `cmark_node_get_type_string`, never on the node-type enum — extension node types are assigned at runtime by `cmark_syntax_extension_add_node` and are not constants at all.
- **Only layer 2** (`cmark gfm private *`) may hold a native pointer. `ast.sls`, `options.sls`, `parse.sls`, `render.sls`, and `gfm.sls` are layer 3.
- **Layer 2 must not import layer 3.** `convert.sls` takes primitives (`max-nodes`, `max-depth`, `positions?`), never the options record.
- **`ast.sls` and `options.sls` import no native library**, not even transitively. `make check-purity` enforces it. Breaking this silently destroys the property that their suites cannot pass by accident.
- **Every borrowed `const char *` is copied on read** with `c-string->string`. No lazy or deferred reads: the tree must be fully materialized before the native scope exits.
- **Teardown order is fixed** (ADR-0005): renderer buffer → root → parser last. Stage 3 adds no native resource and must not touch `release!`.
- **Every `tests/test-*.sps` must end with its own `(exit (if (zero? (test-runner-fail-count runner)) 0 1))`.** SRFI-64 sets no process exit status; a suite missing that line reports success through real failures. Anything after it is dead code.
- **`file-exists?` and `exit` import conflicts:** `(rnrs)` already exports both. A test importing `(only (chezscheme) …)` must NOT also request them, or the library body fails with "multiple definitions for …".
- **`foreign-procedure` resolves its entry point when the expression is evaluated**, not at first call. New bindings in `native.sls` must go **after** the `load-shim` definitions.
- **A test is not finished when it passes. It is finished when you have watched it fail.** Every new assertion gets a mutation that breaks it *through the asserted property*, recorded in `.plans/stage-3-mutation-log.md` (Task 12).
- **Prefer comparing against an expected value over `test-assert`.** `0` is truthy in Scheme and `guard` returns its body's value when nothing raises. Use a distinct sentinel (`'no-condition`, `'wrong-condition`) for the no-raise case.
- **The absent-key variant of the truthiness trap:** `markdown-node-property`'s two-argument form returns `#f` for a key that is not there, so any assertion whose expected value is `#f` must pass a sentinel default — `(markdown-node-property n 'key 'absent)` — or it cannot tell a correctly computed `#f` from a property the converter never emitted. This shipped once in Task 6 and was caught only by mutation.
- **Prefer a check to a comment.** If you are about to write a comment stating an invariant, ask whether it can be a make target, a test, or an assertion first.
- **Where a step predicts a test count, the plan's own test code is authoritative, not the prose.** Several of these counts were wrong on the first pass and were caught by implementers who transcribed the code and reported the real number. Do the same: use the code, report what you actually saw, and flag the mismatch.
- **Commits:** Conventional Commits. Run `make test` before every commit.

---

## File Structure

| Path | Responsibility | Status |
|---|---|---|
| `src/cmark/gfm/private/conditions.sls` | Add `&cmark-resource-limit` | Modify (Task 1) |
| `src/cmark/gfm/private/limits.sls` | Add `default-max-nodes`, `default-max-depth` | Modify (Task 1) |
| `src/cmark/gfm/ast.sls` | **Pure** node and source-position records, accessors, functional update, `map`/`fold` | Create (Tasks 2–3) |
| `src/cmark/gfm/options.sls` | Add `max-nodes`, `max-depth`, `default-ast-options` | Modify (Task 4) |
| `src/cmark-gfm-shim.{c,h}` | Add `chez_cmark_tasklist_checked` — the `_Bool` ABI wrapper | Modify (Task 5) |
| `src/cmark/gfm/private/native.sls` | Add 21 accessor bindings + `alignment-bytes` | Modify (Task 5) |
| `src/cmark/gfm/private/convert.sls` | The native walk, the type table, the limit counters | Create (Tasks 6–8) |
| `src/cmark/gfm/parse.sls` | Layer-3 entry point: `markdown->ast` | Create (Task 9) |
| `src/cmark/gfm.sls` | Façade: re-export the AST bindings and `markdown->ast` | Modify (Task 9) |
| `tests/test-conditions.sps` | Extend for `&cmark-resource-limit` | Modify (Task 1) |
| `tests/test-ast.sps` | **Pure** node-algebra suite — loads no shared object | Create (Tasks 2–3) |
| `tests/test-options.sps` | Extend for the two limits and `default-ast-options` | Modify (Task 4) |
| `tests/test-native.sps` | Extend for the new accessors and the `_Bool` wrapper | Modify (Task 5) |
| `tests/test-convert.sps` | Per-type conversion, key sets, positions, limits, fallback | Create (Tasks 6–9) |
| `tests/test-ast-differential.sps` | AST→XML serializer; in-process then CLI leg | Create (Tasks 10–11) |
| `tests/cmark-testing.sls` | Helpers shared by the two differential suites | Create (Task 11) |
| `tests/test-differential.sps` | Migrate onto the shared helpers; no behaviour change | Modify (Task 11) |
| `Makefile` | `check-purity` covers `test-ast.sps`; `tests` on `CHEZ_LIBDIRS` | Modify (Tasks 2, 11) |
| `.plans/stage-3-mutation-log.md` | Evidence that each assertion fails when its decision breaks | Create (Task 12) |
| `Akku.manifest`, `CHANGELOG.md`, `README.org`, `.plans/decisions/0009-*.md`, `0010-*.md` | Release 0.2 | Modify/Create (Task 13) |
| `.github/workflows/ci.yml` | Resync the `check-purity` step name with what it now gates | Modify (Task 13) |

**One addition to the design spec's §2 module table:** the spec lists `convert.sls` but no layer-3 entry point for `markdown->ast`. Putting the public procedure in `convert.sls` would place a layer-3 export inside layer 2, so this plan adds `src/cmark/gfm/parse.sls`, which mirrors `render.sls` exactly: layer 3, imports `options` and the private libraries, unpacks the options record, holds no pointer. Task 13 syncs the spec's table.

---

# Task 1: `&cmark-resource-limit` and the two limit constants

**Files:**
- Modify: `src/cmark/gfm/private/conditions.sls`
- Modify: `src/cmark/gfm/private/limits.sls`
- Test: `tests/test-conditions.sps`

**Interfaces:**
- Produces: `&cmark-resource-limit` / `make-cmark-resource-limit` (2 args: `reason`, `value`) / `cmark-resource-limit?` / `cmark-resource-limit-value`. Derives from `&cmark-invalid-input`, so it inherits the `reason` field and satisfies `cmark-invalid-input?` and `cmark-error?`. Also `default-max-nodes` = 250000 and `default-max-depth` = 1000 from `(cmark gfm private limits)`.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-conditions.sps`, immediately **before** the final `(test-end "conditions")` line:

```scheme
;; --- Stage 3: resource limits (design spec 6.2) -------------------------
;; The parentage is the whole point of this type: a 0.1 caller guarding
;; cmark-invalid-input? on an oversized document must keep working, while new
;; code discriminates precisely. Both directions are asserted.
(test-equal "resource-limit satisfies its parent's predicate"
  #t
  (guard (e ((cmark-invalid-input? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-many-nodes 250000))
    'no-condition))

(test-equal "resource-limit satisfies cmark-error?"
  #t
  (guard (e ((cmark-error? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-deep 1000))
    'no-condition))

(test-equal "resource-limit inherits the reason field"
  'too-deep
  (guard (e ((cmark-resource-limit? e) (cmark-invalid-input-reason e))
            (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-deep 1000))
    'no-condition))

(test-equal "resource-limit carries the exceeded ceiling"
  1000
  (guard (e ((cmark-resource-limit? e) (cmark-resource-limit-value e))
            (#t 'wrong-condition))
    (raise (make-cmark-resource-limit 'too-deep 1000))
    'no-condition))

;; The converse: a plain invalid-input is NOT a resource limit. Without this,
;; a mutation that made every &cmark-invalid-input a resource-limit would go
;; unnoticed, and the discrimination the type exists to provide would be gone.
(test-equal "a malformed-input condition is not a resource limit"
  #f
  (guard (e ((cmark-invalid-input? e) (cmark-resource-limit? e))
            (#t 'wrong-condition))
    (raise (make-cmark-invalid-input 'embedded-nul))
    'no-condition))
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-conditions.sps
```

Expected: the library body fails at import with an unbound-variable error naming `make-cmark-resource-limit` — the suite does not even start. That is the correct failure for a missing export.

- [ ] **Step 3: Add the condition type**

In `src/cmark/gfm/private/conditions.sls`, add to the `export` list, after the `&cmark-invalid-input` group:

```scheme
          &cmark-resource-limit make-cmark-resource-limit
          cmark-resource-limit? cmark-resource-limit-value
```

Then add the definition immediately **after** the `&cmark-invalid-input` definition (the parent must be defined first):

```scheme
  ;; A resource ceiling, not malformed input. Derives from
  ;; &cmark-invalid-input rather than from &cmark-error directly so that 0.1
  ;; callers guarding cmark-invalid-input? on an oversized document keep
  ;; working unchanged (design spec 6.2), while new code can catch the whole
  ;; class of "the input was fine, the budget was too small" -- the one input
  ;; failure where retrying with a larger limit is a sensible response.
  ;;
  ;; One added field, not two. A `limit` field naming the category would be
  ;; one-to-one redundant with the inherited `reason`, and two fields that
  ;; must agree forever is the invariant limits.sls's header argues against.
  ;; reason discriminates ('too-large, 'too-many-nodes, 'too-deep); value
  ;; carries what reason cannot -- the ceiling as configured by the caller.
  (define-condition-type &cmark-resource-limit &cmark-invalid-input
    make-cmark-resource-limit cmark-resource-limit?
    (value cmark-resource-limit-value))
```

- [ ] **Step 4: Add the two limit constants**

In `src/cmark/gfm/private/limits.sls`, extend the export list to `(export default-max-input-bytes default-max-nodes default-max-depth)` and append:

```scheme
  ;; design spec 6.1: max-input-bytes does NOT bound this. Five MiB of
  ;; "*a*\n" repeated parses to millions of nodes, so without a separate
  ;; ceiling the Scheme-side allocation is unbounded even at the input limit.
  ;; 250000 is roughly two orders of magnitude above realistic documents and
  ;; keeps the copied tree in the tens of megabytes.
  (define default-max-nodes 250000)

  ;; What makes recursive traversal safe (design spec 5.1). Chez's stack is
  ;; heap-allocated and segmented, so recursion depth is bounded by memory
  ;; rather than a small frame limit -- but the bound has to be enforced
  ;; rather than assumed, and 1000 is far past any non-adversarial Markdown.
  (define default-max-depth 1000)
```

- [ ] **Step 5: Run the suite to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-conditions.sps
```

Expected: `# of expected passes` rises by 5, `# of unexpected failures 0`.

- [ ] **Step 6: Run the full suite and commit**

```bash
make test
git add src/cmark/gfm/private/conditions.sls src/cmark/gfm/private/limits.sls tests/test-conditions.sps
git commit -m "feat: add &cmark-resource-limit and the node and depth ceilings"
```

---

# Task 2: The node model — records and accessors

**Files:**
- Create: `src/cmark/gfm/ast.sls`
- Create: `tests/test-ast.sps`
- Modify: `Makefile` (extend `check-purity`)

**Interfaces:**
- Produces, all from `(cmark gfm ast)`:
  - `(make-markdown-node type properties children source)` → node. `type` is a symbol, `properties` an alist with symbol keys, `children` a list of nodes, `source` a `source-position` or `#f`.
  - `(markdown-node? x)` → boolean
  - `(markdown-node-type node)` → symbol
  - `(markdown-node-properties node)` → alist
  - `(markdown-node-children node)` → list
  - `(markdown-node-source node)` → source-position or `#f`
  - `(markdown-node-property node key)` → value or `#f`; `(markdown-node-property node key default)` → value or `default`
  - `(markdown-node-with-properties node properties)` → new node
  - `(markdown-node-with-children node children)` → new node
  - `(make-source-position start-line start-column end-line end-column)` → source-position
  - `(source-position? x)`, `(source-position-start-line p)`, `(source-position-start-column p)`, `(source-position-end-line p)`, `(source-position-end-column p)`
- Consumes: nothing. This library imports **only `(rnrs)`**.

- [ ] **Step 1: Write the failing test suite**

Create `tests/test-ast.sps`:

```scheme
#!r6rs
;; PURE SUITE. This file must never import a library that loads a shared
;; object. That is what makes every assertion below unable to pass by
;; accident because of native behaviour -- they exercise Scheme values only.
;; `make check-purity` enforces it by running this file with
;; CHEZ_CMARK_GFM_SHIM poisoned; if the import chain ever reaches
;; (cmark gfm private native), that target fails. Check transitive imports
;; before adding one here or to ast.sls.
(import (rnrs)
        (srfi :64)
        (cmark gfm ast))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "ast")

;; --- a small fixture tree ---------------------------------------------
;; # hi
;;
;; word
(define leaf-hi   (make-markdown-node 'text '((literal . "hi")) '() #f))
(define heading   (make-markdown-node 'heading '((level . 1)) (list leaf-hi) #f))
(define leaf-word (make-markdown-node 'text '((literal . "word")) '() #f))
(define para      (make-markdown-node 'paragraph '() (list leaf-word) #f))
(define doc       (make-markdown-node 'document '() (list heading para) #f))

;; --- construction and accessors ----------------------------------------
(test-equal "a node reports its type" 'heading (markdown-node-type heading))
(test-equal "a node reports its properties"
  '((level . 1)) (markdown-node-properties heading))
(test-equal "a node reports its children as a list"
  (list leaf-hi) (markdown-node-children heading))
(test-equal "source is #f when absent" #f (markdown-node-source heading))
(test-equal "markdown-node? accepts a node" #t (markdown-node? heading))
(test-equal "markdown-node? rejects a non-node" #f (markdown-node? '(heading)))
(test-equal "markdown-node? rejects a source-position"
  #f (markdown-node? (make-source-position 1 1 1 4)))

;; --- property lookup ---------------------------------------------------
;; Compared against VALUES, not asserted truthy: a level of 1 and a missing
;; key returning #f are both distinguishable only by comparison, and
;; test-assert would pass on any non-#f whatsoever.
(test-equal "property lookup finds a present key" 1
  (markdown-node-property heading 'level))
(test-equal "property lookup returns #f for an absent key with no default" #f
  (markdown-node-property heading 'url))
(test-equal "property lookup returns the supplied default for an absent key"
  'missing (markdown-node-property heading 'url 'missing))
(test-equal "an explicit default does not override a present key" 1
  (markdown-node-property heading 'level 'missing))
;; A property whose real value is #f must be distinguishable from absence.
;; Seeded deliberately: without this, an implementation using #f internally
;; as its not-found marker would pass every other assertion here.
(test-equal "a present key whose value is #f returns #f, not the default"
  #f
  (markdown-node-property
   (make-markdown-node 'item '((task? . #f)) '() #f) 'task? 'missing))

;; --- source positions ---------------------------------------------------
(define pos (make-source-position 3 5 3 9))
(test-equal "source-position? accepts one" #t (source-position? pos))
(test-equal "start-line"   3 (source-position-start-line pos))
(test-equal "start-column" 5 (source-position-start-column pos))
(test-equal "end-line"     3 (source-position-end-line pos))
(test-equal "end-column"   9 (source-position-end-column pos))
(test-equal "a node carries its position"
  pos
  (markdown-node-source (make-markdown-node 'text '() '() pos)))

;; --- functional update --------------------------------------------------
;; Each of these asserts BOTH the new value and that the original is
;; unchanged. Asserting only the new value would pass against a mutable
;; record with setters, which is exactly the design this rejects.
(test-equal "with-properties replaces the property list"
  '((level . 3))
  (markdown-node-properties (markdown-node-with-properties heading '((level . 3)))))
(test-equal "with-properties leaves the original untouched"
  '((level . 1)) (markdown-node-properties heading))
(test-equal "with-properties preserves type, children, and source"
  (list 'heading (list leaf-hi) #f)
  (let ((n (markdown-node-with-properties heading '((level . 3)))))
    (list (markdown-node-type n) (markdown-node-children n)
          (markdown-node-source n))))
(test-equal "with-children replaces the children"
  (list leaf-word)
  (markdown-node-children (markdown-node-with-children heading (list leaf-word))))
(test-equal "with-children leaves the original untouched"
  (list leaf-hi) (markdown-node-children heading))
(test-equal "with-children preserves type, properties, and source"
  (list 'heading '((level . 1)) #f)
  (let ((n (markdown-node-with-children heading (list leaf-word))))
    (list (markdown-node-type n) (markdown-node-properties n)
          (markdown-node-source n))))

(test-end "ast")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-ast.sps
```

Expected: failure at import — `library (cmark gfm ast) not found`.

- [ ] **Step 3: Write the implementation**

Create `src/cmark/gfm/ast.sls`:

```scheme
#!r6rs
;;; The Scheme-owned Markdown AST -- the functional core.
;;;
;;; This library imports ONLY (rnrs). No native library, not even
;;; transitively, which is what makes tests/test-ast.sps run with no shared
;;; object loaded and therefore unable to pass by accident because of native
;;; behaviour. `make check-purity` enforces it. Check transitive imports
;;; before adding one.
;;;
;;; SECURITY: a node tree is UNTRUSTED STRUCTURED INPUT. Parsing preserves
;;; exactly what the document said, including raw HTML literals and
;;; javascript: URLs; no sanitisation happens during conversion, and
;;; unsafe-html? has no effect here -- that option is a renderer policy
;;; (project plan 10.3, and 17 names "users assume AST content is sanitized"
;;; as a project risk). Sanitise at the point of rendering, not here.
;;;
;;; Nodes are immutable. Every field is read-only and the two update helpers
;;; return new nodes, so a caller cannot corrupt a tree another caller holds.
;;; An accessor applied to a non-node raises R6RS &assertion from the record
;;; accessor itself; this library adds no checking layer, because a wrong type
;;; here is a programming error in Scheme-only code, not one of the native or
;;; option failures &cmark-error exists to describe.
(library (cmark gfm ast)
  (export make-markdown-node markdown-node?
          markdown-node-type markdown-node-properties
          markdown-node-children markdown-node-source
          markdown-node-property
          markdown-node-with-properties markdown-node-with-children

          make-source-position source-position?
          source-position-start-line source-position-start-column
          source-position-end-line   source-position-end-column)
  (import (rnrs))

  ;; Diagnostic metadata, not a security boundary. cmark's positions for
  ;; some inline and extension constructs have known limitations (project
  ;; plan 7.2).
  (define-record-type (source-position make-source-position source-position?)
    (fields start-line start-column end-line end-column))

  ;; Generic rather than one record per node type, so an extension node type
  ;; needs no new record definition and no new export (project plan 7.1).
  ;; Children are a LIST: the traversal helpers are the intended access path
  ;; and neither wants random access. Properties are an immutable ALIST: no
  ;; node type carries more than four, so a mapping structure would cost more
  ;; than it saves, and an alist compares directly in tests.
  (define-record-type (markdown-node make-markdown-node markdown-node?)
    (fields type properties children source))

  ;; The default argument is not decoration. Several properties have #f as a
  ;; legitimate VALUE (task?, checked?, header?, tight?), so a lookup that
  ;; returned #f for both "absent" and "present and false" would be unable to
  ;; express the difference. assq distinguishes them; the default is only
  ;; consulted when the key is genuinely absent.
  (define markdown-node-property
    (case-lambda
      ((node key) (markdown-node-property node key #f))
      ((node key default)
       (let ((hit (assq key (markdown-node-properties node))))
         (if hit (cdr hit) default)))))

  (define (markdown-node-with-properties node properties)
    (make-markdown-node (markdown-node-type node)
                        properties
                        (markdown-node-children node)
                        (markdown-node-source node)))

  (define (markdown-node-with-children node children)
    (make-markdown-node (markdown-node-type node)
                        (markdown-node-properties node)
                        children
                        (markdown-node-source node))))
```

- [ ] **Step 4: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-ast.sps
```

Expected: `# of expected passes 24`, `# of unexpected failures 0`.

- [ ] **Step 5: Extend the purity gate to cover this suite**

The target already exists and CI runs it (`.github/workflows/ci.yml:79`). Replace the `check-purity` recipe in `Makefile` (currently lines 142–153) with a loop over both pure suites:

```make
check-purity: build deps
	@fail=0; \
	for t in tests/test-options.sps tests/test-ast.sps; do \
	  echo "=== check-purity: $$t, CHEZ_CMARK_GFM_SHIM poisoned ==="; \
	  if CHEZ_CMARK_GFM_SHIM=/nonexistent CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	      $(CHEZ) --program $$t; then \
	    echo "purity holds: $$t pulled in no native code"; \
	  else \
	    echo "PURITY VIOLATED: $$t failed with CHEZ_CMARK_GFM_SHIM poisoned" >&2; \
	    echo "to a nonexistent path. Its import chain now reaches" >&2; \
	    echo "(cmark gfm private native), which loads a shared object -- check" >&2; \
	    echo "what it (or something it imports) just started pulling in." >&2; \
	    fail=1; \
	  fi; \
	done; \
	exit $$fail
```

Leave the long comment block above the target in place; it explains the probe and its one caveat (Chez instantiates an imported library's body only when something references one of its bindings, so an unused import is invisible to this check).

- [ ] **Step 6: Verify the gate actually gates**

```bash
make check-purity
```

Expected: two `purity holds:` lines, exit 0.

Now prove the check can fail. Temporarily add to `src/cmark/gfm/ast.sls`'s import list `(cmark gfm private native)` **and** a reference that forces instantiation — an unused import is invisible to the probe:

```scheme
  (define ignored-purity-probe (live-counts))
```

Run `make check-purity` again. Expected: `PURITY VIOLATED: tests/test-ast.sps …`, exit 1. **Revert both edits** and re-run to confirm it passes again.

- [ ] **Step 7: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/ast.sls tests/test-ast.sps Makefile
git commit -m "feat: add the immutable Scheme AST node model"
```

---

# Task 3: Traversal helpers — `markdown-node-map` and `markdown-node-fold`

**Files:**
- Modify: `src/cmark/gfm/ast.sls`
- Modify: `tests/test-ast.sps`

**Interfaces:**
- Consumes: everything Task 2 produced.
- Produces: `(markdown-node-map proc node)` → node. `proc` receives a node whose children have **already** been mapped and returns the replacement node; rebuilding is children-first (bottom-up). `(markdown-node-fold proc seed node)` → accumulator. `proc` receives `(node accumulator)` and returns the new accumulator; traversal is **pre-order** — parent before children, children left to right.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-ast.sps`, immediately **before** the final `(test-end "ast")` line:

```scheme
;; --- traversal helpers -------------------------------------------------
;; The ORDER is the contract, so the order is what gets asserted. A helper
;; that visited every node but in the wrong order would satisfy any
;; count-based or set-based assertion, which is why both tests below record a
;; sequence and compare it against an expected list.

;; Pre-order: parent before children, children left to right.
(test-equal "fold visits pre-order, parent before children"
  '(document heading text paragraph text)
  (reverse (markdown-node-fold
            (lambda (n acc) (cons (markdown-node-type n) acc))
            '() doc)))

(test-equal "fold threads the accumulator and counts every node"
  5 (markdown-node-fold (lambda (n acc) (+ acc 1)) 0 doc))

;; Children-first: proc must already see mapped children. proc records, on
;; each parent, the literal it observes on that parent's own first child AT
;; THE MOMENT proc runs on the parent -- checking only the final assembled
;; tree would NOT prove this: markdown-node-with-children always rewraps a
;; node with the fully-recursed children regardless of order, so a proc that
;; never inspects its children cannot tell parent-first from children-first
;; apart. With a parent-first implementation, proc sees the child still in its
;; ORIGINAL state, so the recorded literal would be "hi"/"word" rather than
;; "marked".
;;
;; This exact shape is why the assertion is written the awkward way: an
;; earlier draft marked text nodes and inspected the final tree, which passed
;; identically under both orderings -- an empty test by this project's own
;; standard, caught only by running the mutation.
(test-equal "map rebuilds children-first, so proc sees mapped children"
  '("marked" "marked")
  (let ((out (markdown-node-map
              (lambda (n)
                (cond
                  ((eq? (markdown-node-type n) 'text)
                   (markdown-node-with-properties n '((literal . "marked"))))
                  ((pair? (markdown-node-children n))
                   (markdown-node-with-properties
                    n `((observed-child-literal
                         . ,(markdown-node-property
                             (car (markdown-node-children n)) 'literal)))))
                  (else n)))
              doc)))
    ;; document -> (heading paragraph), each with one text child
    (map (lambda (block) (markdown-node-property block 'observed-child-literal))
         (markdown-node-children out))))

(test-equal "map can rewrite a node type and keeps the tree shape"
  '(document paragraph text paragraph text)
  (reverse
   (markdown-node-fold
    (lambda (n acc) (cons (markdown-node-type n) acc))
    '()
    (markdown-node-map
     (lambda (n)
       (if (eq? (markdown-node-type n) 'heading)
           (make-markdown-node 'paragraph '() (markdown-node-children n)
                               (markdown-node-source n))
           n))
     doc))))

(test-equal "map leaves the original tree untouched"
  '(document heading text paragraph text)
  (begin
    (markdown-node-map
     (lambda (n) (make-markdown-node 'clobbered '() '() #f))
     doc)
    (reverse (markdown-node-fold
              (lambda (n acc) (cons (markdown-node-type n) acc))
              '() doc))))

(test-equal "map on a leaf applies proc to the leaf itself"
  'rewritten
  (markdown-node-type
   (markdown-node-map (lambda (n) (make-markdown-node 'rewritten '() '() #f))
                      leaf-hi)))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-ast.sps
```

Expected: import failure naming `markdown-node-map` as unbound.

- [ ] **Step 3: Implement the two helpers**

In `src/cmark/gfm/ast.sls`, add to the export list after `markdown-node-with-children`:

```scheme
          markdown-node-map markdown-node-fold
```

and append the definitions to the library body:

```scheme
  ;; Children-first (bottom-up): proc receives a node whose children have
  ;; already been mapped, so a rewrite can inspect its final subtree. Both
  ;; orders here are asserted by test rather than merely documented -- an
  ;; ordering guarantee stated only in a comment does not enforce itself.
  ;;
  ;; Recursive, like the converter, and for the same reason: it runs on trees
  ;; already bounded by max-depth, so no separate limit applies.
  (define (markdown-node-map proc node)
    (proc (markdown-node-with-children
           node
           (map (lambda (child) (markdown-node-map proc child))
                (markdown-node-children node)))))

  ;; Pre-order: parent before children, children left to right.
  (define (markdown-node-fold proc seed node)
    (fold-left (lambda (acc child) (markdown-node-fold proc acc child))
               (proc node seed)
               (markdown-node-children node)))
```

- [ ] **Step 4: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-ast.sps
```

Expected: `# of expected passes 30`, `# of unexpected failures 0`.

- [ ] **Step 5: Watch the order assertions fail**

Copy `ast.sls` to a scratch location outside the repo, then in the working copy make `markdown-node-map` parent-first:

```scheme
  (define (markdown-node-map proc node)
    (let ((n (proc node)))
      (markdown-node-with-children
       n (map (lambda (child) (markdown-node-map proc child))
              (markdown-node-children n)))))
```

Run the suite. Expected: `map rebuilds children-first, so proc sees mapped children` FAILS by name, reporting expected `("marked" "marked")` and actual `("hi" "word")` — proc saw the original children. If it does **not** fail, the assertion is empty and must be rewritten before proceeding; that is not a hypothetical, it is what happened to the first draft of this test.

Then restore, and make `markdown-node-fold` post-order:

```scheme
  (define (markdown-node-fold proc seed node)
    (proc node (fold-left (lambda (acc child) (markdown-node-fold proc acc child))
                          seed
                          (markdown-node-children node))))
```

Run the suite. Expected: `fold visits pre-order, parent before children` FAILS by name. Restore the correct implementations and confirm all 30 pass. Record both mutations for Task 12.

- [ ] **Step 6: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/ast.sls tests/test-ast.sps
git commit -m "feat: add markdown-node-map and markdown-node-fold"
```

---

# Task 4: Options — `max-nodes`, `max-depth`, `default-ast-options`

**Files:**
- Modify: `src/cmark/gfm/options.sls`
- Test: `tests/test-options.sps`

**Interfaces:**
- Consumes: `default-max-nodes`, `default-max-depth` from Task 1.
- Produces: `cmark-options-max-nodes` and `cmark-options-max-depth` accessors; `max-nodes` and `max-depth` accepted as plist keys by `make-cmark-options` and `cmark-options-with`; `(default-ast-options)` → an options record identical to `(default-cmark-options)` except `source-positions?` is `#t`.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-options.sps`, immediately **before** the final `(test-end "options")` line:

```scheme
;; --- Stage 3: the two new ceilings (design spec 6.1) --------------------
(test-equal "max-nodes defaults to 250000"
  250000 (cmark-options-max-nodes (default-cmark-options)))
(test-equal "max-depth defaults to 1000"
  1000 (cmark-options-max-depth (default-cmark-options)))

(test-equal "max-nodes is settable"
  20000 (cmark-options-max-nodes (make-cmark-options 'max-nodes 20000)))
(test-equal "max-depth is settable"
  64 (cmark-options-max-depth (make-cmark-options 'max-depth 64)))

;; Both of these seed a NON-DEFAULT value before updating an unrelated field,
;; and that is the entire mechanism. cmark-options-with rebuilds from ten
;; near-identical field reads; a copy/paste slip on one of them would silently
;; substitute the global default, which a test starting from the default value
;; cannot see. Verified: replacing (cmark-options-max-depth o) with the bare
;; constant default-max-depth leaves every other assertion in this suite green.
(test-equal "max-nodes survives a functional update of another field"
  20000
  (cmark-options-max-nodes
   (cmark-options-with (make-cmark-options 'max-nodes 20000) 'smart? #t)))

(test-equal "max-depth survives a functional update of another field"
  64
  (cmark-options-max-depth
   (cmark-options-with (make-cmark-options 'max-depth 64) 'smart? #t)))

;; Validated exactly as max-input-bytes is: exact positive integer.
(test-equal "a non-integer max-nodes is rejected"
  '(max-nodes invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (make-cmark-options 'max-nodes 1.5)
    'no-condition))
(test-equal "a zero max-nodes is rejected"
  '(max-nodes invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (make-cmark-options 'max-nodes 0)
    'no-condition))
(test-equal "a negative max-depth is rejected"
  '(max-depth invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (make-cmark-options 'max-depth -1)
    'no-condition))
;; The same rule must hold on the update path, which builds through the same
;; validator. Without this, cmark-options-with could smuggle past a check the
;; base constructor enforces.
(test-equal "cmark-options-with validates max-depth too"
  '(max-depth invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (cmark-options-with (default-cmark-options) 'max-depth 'huge)
    'no-condition))

;; --- default-ast-options (design spec 4.2, ADR-0009) --------------------
;; The ONE field that differs, and the fact that nothing else does. Asserting
;; only source-positions? would pass against a constructor that also flipped
;; unsafe-html?, which is exactly the accident this pair of tests prevents.
(test-equal "default-ast-options turns source positions on"
  #t (cmark-options-source-positions? (default-ast-options)))
(test-equal "the renderer default is unchanged -- positions stay off"
  #f (cmark-options-source-positions? (default-cmark-options)))
(test-equal "default-ast-options differs from the renderer defaults in nothing else"
  (list '(autolink strikethrough table tagfilter tasklist) #t #f #f #f #f
        5242880 250000 1000)
  (let ((o (default-ast-options)))
    (list (cmark-options-extensions o)
          (cmark-options-validate-utf8? o)
          (cmark-options-hardbreaks? o)
          (cmark-options-nobreaks? o)
          (cmark-options-smart? o)
          (cmark-options-unsafe-html? o)
          (cmark-options-max-input-bytes o)
          (cmark-options-max-nodes o)
          (cmark-options-max-depth o))))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-options.sps
```

Expected: import failure naming `cmark-options-max-nodes` as unbound.

- [ ] **Step 3: Extend the options record**

Four coordinated edits in `src/cmark/gfm/options.sls`. Every one is required — the record, the key list, the validator, and both constructors' default tuples.

Add to the export list after `cmark-options-max-input-bytes`:

```scheme
          cmark-options-max-nodes
          cmark-options-max-depth
          default-ast-options
```

Add two fields to the record definition, after `max-input-bytes`:

```scheme
            max-nodes
            max-depth))
```

Add both keys to `option-keys`:

```scheme
  (define option-keys
    '(extensions validate-utf8? source-positions? hardbreaks?
      nobreaks? smart? unsafe-html? max-input-bytes max-nodes max-depth))
```

Replace the `max-input-bytes` clause of `validate` with one that covers all three ceilings, so a fourth cannot be added without a check:

```scheme
    (for-each
     (lambda (pair)
       (let ((key (car pair)) (n ((cdr pair) o)))
         (unless (and (integer? n) (exact? n) (positive? n))
           (raise (make-cmark-invalid-option key 'invalid-value)))))
     (list (cons 'max-input-bytes cmark-options-max-input-bytes)
           (cons 'max-nodes       cmark-options-max-nodes)
           (cons 'max-depth       cmark-options-max-depth)))
```

Extend `build`'s parameter list and body with the two new defaults:

```scheme
  (define (build a
                 d-extensions d-validate-utf8? d-source-positions?
                 d-hardbreaks? d-nobreaks? d-smart? d-unsafe-html?
                 d-max-input-bytes d-max-nodes d-max-depth)
    (validate
     (%make-cmark-options
      (lookup a 'extensions        d-extensions)
      (lookup a 'validate-utf8?    d-validate-utf8?)
      (lookup a 'source-positions? d-source-positions?)
      (lookup a 'hardbreaks?       d-hardbreaks?)
      (lookup a 'nobreaks?         d-nobreaks?)
      (lookup a 'smart?            d-smart?)
      (lookup a 'unsafe-html?      d-unsafe-html?)
      (lookup a 'max-input-bytes   d-max-input-bytes)
      (lookup a 'max-nodes         d-max-nodes)
      (lookup a 'max-depth         d-max-depth))))
```

Extend `make-cmark-options`'s call — this is the one place the default tuple is written:

```scheme
  (define (make-cmark-options . plist)
    (build (plist->alist plist)
           default-extensions #t #f #f #f #f #f
           default-max-input-bytes default-max-nodes default-max-depth))
```

Extend `cmark-options-with`'s call with the two field reads:

```scheme
           (cmark-options-max-input-bytes o)
           (cmark-options-max-nodes o)
           (cmark-options-max-depth o))))
```

- [ ] **Step 4: Add `default-ast-options`**

Append to `src/cmark/gfm/options.sls`, after `default-cmark-options`:

```scheme
  ;; ADR-0009 and design spec 4.2: markdown->ast's per-entry-point default.
  ;; Positions are worth having in an AST and are not worth having in
  ;; rendered markup, and one shared default cannot serve both -- so the
  ;; entry point picks, by arity, rather than the record carrying a third
  ;; "unset" state that every validation path would have to handle.
  ;;
  ;; Built by functional update from make-cmark-options rather than by
  ;; restating the default tuple, so a future change to any other default
  ;; cannot desync the two constructors.
  (define (default-ast-options)
    (cmark-options-with (make-cmark-options) 'source-positions? #t))
```

- [ ] **Step 5: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-options.sps
```

Expected: 13 new passes, `# of unexpected failures 0`.

- [ ] **Step 6: Watch the validator assertion fail**

In the working copy, drop `max-depth` from the `validate` list above (leave `max-input-bytes` and `max-nodes`). Run the suite. Expected: both `a negative max-depth is rejected` and `cmark-options-with validates max-depth too` FAIL by name, reporting `no-condition`. Restore and confirm they pass. Record for Task 12.

- [ ] **Step 7: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/options.sls tests/test-options.sps
git commit -m "feat: add max-nodes, max-depth, and default-ast-options"
```

---

# Task 5: Native accessors and the `_Bool` ABI wrapper

**Files:**
- Modify: `src/cmark-gfm-shim.h`
- Modify: `src/cmark-gfm-shim.c`
- Modify: `src/cmark/gfm/private/native.sls`
- Test: `tests/test-native.sps`

**Interfaces:**
- Produces, all exported from `(cmark gfm private native)`. Every one takes a node pointer (`uptr`) as its first argument:
  - Pointer/string returns (declared `uptr`, must be passed through `c-string->string`): `node-first-child`, `node-next`, `node-type-string`, `node-literal`, `node-fence-info`, `node-url`, `node-title`, `table-alignments`
  - Integer returns: `node-heading-level`, `node-list-type` (0 none, 1 bullet, 2 ordered), `node-list-delim` (0 none, 1 period, 2 paren), `node-list-start`, `node-list-tight` (0/1), `node-item-index`, `node-start-line`, `node-start-column`, `node-end-line`, `node-end-column`, `table-row-is-header` (0/1), `table-columns` (`unsigned-16`), `tasklist-checked` (0/1, via the shim)
  - `(alignment-bytes addr count)` → list of `count` exact integers read from the alignments array; all zeros when `addr` is 0.
- Consumes: `c-string->string`, `option-bits`, `call-with-native-document`, `doc-root` (all pre-existing).

**No Makefile change is needed.** Both acquisition paths already expose the extensions header: `pkg-config --cflags libcmark-gfm` points at an include dir containing `cmark-gfm-core-extensions.h`, and the vendored branch already passes `-I$(VENDOR_DIR)/extensions` (`Makefile:39-40`).

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-native.sps`, immediately **before** the final `(test-end "native")` line. First extend the import list at the top of the file to add scope:

```scheme
        (cmark gfm private scope)
```

Then the assertions:

```scheme
;; --- Stage 3: node accessors -------------------------------------------
;; Driven through call-with-native-document rather than a bare parser so the
;; teardown rules of ADR-0005 and ADR-0006 keep applying to every probe here.
(define (with-root markdown exts proc)
  (call-with-native-document
   markdown (option-bits #f #t #f #f #f #f) exts
   (lambda (h) (proc (doc-root h)))))

;; Walk a path of zero-based child indices down from a node.
(define (walk node path)
  (if (null? path)
      node
      (let loop ((n (node-first-child node)) (i (car path)))
        (if (zero? i)
            (walk n (cdr path))
            (loop (node-next n) (- i 1))))))

(define (type-at markdown exts path)
  (with-root markdown exts
             (lambda (root) (c-string->string (node-type-string (walk root path))))))

(test-equal "the root's type string is document"
  "document" (type-at "# hi\n" '() '()))
(test-equal "a heading's type string is heading"
  "heading" (type-at "# hi\n" '() '(0)))
(test-equal "node-next reaches the second block, not the first"
  "paragraph" (type-at "# hi\n\npara\n" '() '(1)))
(test-equal "a heading's child is a text node"
  "text" (type-at "# hi\n" '() '(0 0)))

(test-equal "node-heading-level reads the level"
  3 (with-root "### three\n" '() (lambda (r) (node-heading-level (walk r '(0))))))
(test-equal "node-literal copies the text"
  "hi" (with-root "# hi\n" '()
         (lambda (r) (c-string->string (node-literal (walk r '(0 0)))))))
(test-equal "node-url and node-title read a link"
  '("http://e.example/" "T")
  (with-root "[x](http://e.example/ \"T\")\n" '()
    (lambda (r)
      (let ((link (walk r '(0 0))))
        (list (c-string->string (node-url link))
              (c-string->string (node-title link)))))))
(test-equal "node-fence-info reads a fence info string"
  "scheme"
  (with-root "```scheme\n(+ 1 2)\n```\n" '()
    (lambda (r) (c-string->string (node-fence-info (walk r '(0)))))))
;; Empty, not #f: cmark returns "" for a code block with no info string and
;; NULL only for a node that is not a code block (src/cmark-gfm.h). Conflating
;; the two would invent data, so the distinction is asserted.
(test-equal "an indented code block has an empty, not absent, fence info"
  ""
  (with-root "    indented\n" '()
    (lambda (r) (c-string->string (node-fence-info (walk r '(0)))))))

;; 2 = CMARK_ORDERED_LIST, 1 = CMARK_PERIOD_DELIM. The numbers stay here in
;; layer 2; convert.sls maps them to symbols.
(test-equal "list accessors read kind, start, delim, and tightness"
  '(2 3 1 1)
  (with-root "3. one\n4. two\n" '()
    (lambda (r)
      (let ((l (walk r '(0))))
        (list (node-list-type l) (node-list-start l)
              (node-list-delim l) (node-list-tight l))))))
(test-equal "a bullet list reports kind 1 and start 0"
  '(1 0)
  (with-root "- one\n" '()
    (lambda (r)
      (let ((l (walk r '(0))))
        (list (node-list-type l) (node-list-start l))))))
(test-equal "node-item-index reads the second item's index"
  4 (with-root "3. one\n4. two\n" '()
      (lambda (r) (node-item-index (walk r '(0 1))))))

(test-equal "position accessors read the paragraph's span"
  '(3 1 3 4)
  (with-root "# hi\n\npara\n" '()
    (lambda (r)
      (let ((p (walk r '(1))))
        (list (node-start-line p) (node-start-column p)
              (node-end-line p) (node-end-column p))))))

;; --- extension accessors ------------------------------------------------
;; These three live in libcmark-gfm-extensions, not libcmark-gfm. They resolve
;; only because native.sls loads both shared objects explicitly, ahead of the
;; shim; if that ever regressed these would fail at IMPORT time on Linux while
;; still passing on macOS, whose loader searches dependencies.
(define table-md "| a | b |\n|:--|--:|\n| 1 | 2 |\n")

(test-equal "a table's type string is table"
  "table" (type-at table-md '("table") '(0)))
(test-equal "a header row's type string is table_header, not table_row"
  "table_header" (type-at table-md '("table") '(0 0)))
(test-equal "a body row's type string is table_row"
  "table_row" (type-at table-md '("table") '(0 1)))

(test-equal "table-columns counts the columns"
  2 (with-root table-md '("table") (lambda (r) (table-columns (walk r '(0))))))
;; 108 = 'l', 114 = 'r' (vendor/cmark-gfm/extensions/table.c:387-391).
(test-equal "table-alignments yields one byte per column"
  '(108 114)
  (with-root table-md '("table")
    (lambda (r)
      (let ((t (walk r '(0))))
        (alignment-bytes (table-alignments t) (table-columns t))))))
(test-equal "table-row-is-header agrees with the type string"
  '(1 0)
  (with-root table-md '("table")
    (lambda (r)
      (list (table-row-is-header (walk r '(0 0)))
            (table-row-is-header (walk r '(0 1)))))))

;; A task item's type string is "tasklist", which is the ONLY way to tell a
;; task item from a plain one: get_tasklist_item_checked returns false both
;; for an unchecked task and for a non-task
;; (vendor/cmark-gfm/extensions/tasklist.c:30-40).
(define task-md "- [x] done\n- [ ] todo\n")
(test-equal "a task item's type string is tasklist"
  "tasklist" (type-at task-md '("tasklist") '(0 0)))
(test-equal "a plain item's type string is item"
  "item" (type-at "- plain\n" '("tasklist") '(0 0)))
(test-equal "tasklist-checked distinguishes checked from unchecked"
  '(1 0)
  (with-root task-md '("tasklist")
    (lambda (r)
      (list (tasklist-checked (walk r '(0 0)))
            (tasklist-checked (walk r '(0 1)))))))
;; The shim wrapper's reason for existing: the underlying entry point returns
;; C _Bool, whose upper return-register bits are unspecified. Values other
;; than exactly 1 and 0 above would be the symptom.
(test-equal "tasklist-checked returns exactly 1 or 0, never a stray bit pattern"
  #t
  (with-root task-md '("tasklist")
    (lambda (r) (and (memv (tasklist-checked (walk r '(0 0))) '(0 1)) #t))))

;; alignment-bytes must not read through a NULL pointer.
(test-equal "alignment-bytes yields zeros for a NULL array"
  '(0 0 0) (alignment-bytes 0 3))
(test-equal "alignment-bytes yields the empty list for zero columns"
  '() (alignment-bytes 0 0))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
make build && CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-native.sps
```

Expected: import failure naming `node-first-child` as unbound.

- [ ] **Step 3: Add the shim wrapper**

Append to `src/cmark-gfm-shim.h`, before the closing `#endif`:

```c
/* Tasklist checked state, normalised to int.
 *
 * cmark_gfm_extensions_get_tasklist_item_checked returns C _Bool. On the
 * x86-64 SysV ABI a _Bool return occupies only the low byte of the return
 * register, with the upper bits unspecified, so binding that entry point
 * directly as `int` would read whatever happens to be there. Normalising in C
 * -- where the return type is known to the compiler -- is exactly the
 * "stable, Chez-friendly function" job plan 8.1 assigns the shim, and adds no
 * traversal, parsing, or rendering (ADR-0002).
 *
 * Returns 1 if node is a checked task-list item, 0 otherwise (including for
 * a node that is not a task-list item at all).
 *
 * `struct cmark_node` is forward-declared at file scope (rather than left to
 * be introduced implicitly by the parameter list below) because a tag whose
 * first appearance is inside a function's parameter-type-list has prototype
 * scope only (C99 6.2.1p7): it does not extend to cmark-gfm-shim.c's
 * definition of this same function, so without this line the header's
 * `struct cmark_node` and the .c file's are two distinct, incompatible
 * incomplete types, and the two declarations of chez_cmark_tasklist_checked
 * conflict -- a hard error, independent of -Werror. */
struct cmark_node;
int chez_cmark_tasklist_checked(struct cmark_node *node);
```

The `struct cmark_node;` line is load-bearing, not decoration. `cmark-gfm-shim.c`
includes its own header **before** `<cmark-gfm.h>`, so at the point the prototype
is parsed the tag is not yet known at file scope. Omit the forward declaration
and the build fails with a conflicting-types error on the function's own
definition. The `struct` form is used rather than the `cmark_node` typedef so the
header stays self-contained. In `src/cmark-gfm-shim.c`, add the extensions include
below the existing includes:

```c
#include <cmark-gfm-core-extensions.h>
```

and the function, after `chez_cmark_free_buffer`:

```c
int chez_cmark_tasklist_checked(struct cmark_node *node) {
  return cmark_gfm_extensions_get_tasklist_item_checked((cmark_node *)node) ? 1 : 0;
}
```

The explicit `? 1 : 0` rather than a cast keeps `-Wconversion -Werror` quiet
and makes the normalisation the point rather than a side effect.

- [ ] **Step 4: Verify the shim still builds clean**

```bash
make build
```

Expected: no warnings (the build runs `-Wall -Wextra -Werror -Wconversion -Wshadow`), and `build/lib/libchezcmarkgfm.dylib` (or `.so`) relinks.

- [ ] **Step 5: Add the Scheme bindings**

In `src/cmark/gfm/private/native.sls`, add to the export list:

```scheme
          node-first-child node-next node-type-string node-literal
          node-heading-level node-list-type node-list-delim node-list-start
          node-list-tight node-item-index node-fence-info
          node-url node-title
          node-start-line node-start-column node-end-line node-end-column
          table-columns table-alignments table-row-is-header tasklist-checked
          alignment-bytes
```

Add the bindings **after** the existing `render-plaintext` definition — every
`foreign-procedure` expression must be evaluated after `load-shim`, and the
existing bindings are already positioned correctly:

```scheme
  ;; --- Stage 3: node accessors ------------------------------------------
  ;; Every `const char *` return is declared uptr and copied by
  ;; c-string->string at the call site, per the Stage 1 rule: the
  ;; conservative form does not depend on marshalling behaviour, and it keeps
  ;; NULL distinguishable from "". Several of these accessors return NULL for
  ;; a node of an incompatible type, so that distinction carries meaning.
  (define node-first-child
    (foreign-procedure "cmark_node_first_child" (uptr) uptr))
  (define node-next     (foreign-procedure "cmark_node_next" (uptr) uptr))
  (define node-type-string
    (foreign-procedure "cmark_node_get_type_string" (uptr) uptr))
  (define node-literal  (foreign-procedure "cmark_node_get_literal" (uptr) uptr))
  (define node-fence-info
    (foreign-procedure "cmark_node_get_fence_info" (uptr) uptr))
  (define node-url      (foreign-procedure "cmark_node_get_url" (uptr) uptr))
  (define node-title    (foreign-procedure "cmark_node_get_title" (uptr) uptr))

  (define node-heading-level
    (foreign-procedure "cmark_node_get_heading_level" (uptr) int))
  (define node-list-type
    (foreign-procedure "cmark_node_get_list_type" (uptr) int))
  (define node-list-delim
    (foreign-procedure "cmark_node_get_list_delim" (uptr) int))
  (define node-list-start
    (foreign-procedure "cmark_node_get_list_start" (uptr) int))
  (define node-list-tight
    (foreign-procedure "cmark_node_get_list_tight" (uptr) int))
  (define node-item-index
    (foreign-procedure "cmark_node_get_item_index" (uptr) int))
  (define node-start-line
    (foreign-procedure "cmark_node_get_start_line" (uptr) int))
  (define node-start-column
    (foreign-procedure "cmark_node_get_start_column" (uptr) int))
  (define node-end-line
    (foreign-procedure "cmark_node_get_end_line" (uptr) int))
  (define node-end-column
    (foreign-procedure "cmark_node_get_end_column" (uptr) int))

  ;; --- extension accessors ----------------------------------------------
  ;; These live in libcmark-gfm-extensions. They resolve only because
  ;; cmark-loaded above loads both cmark shared objects explicitly, before the
  ;; shim: on Linux a dlopened library's dependencies are not placed in the
  ;; global symbol namespace, so a missing explicit load fails HERE, at import
  ;; time, and only on Linux.
  ;;
  ;; table-columns and table-alignments dereference node->type with no NULL
  ;; guard (vendor/cmark-gfm/extensions/table.c:878-890), so a caller must
  ;; have confirmed the node is a table first. convert.sls calls them only
  ;; from inside the "table" branch of its dispatch table, which makes that
  ;; structural rather than a documented promise.
  (define table-columns
    (foreign-procedure "cmark_gfm_extensions_get_table_columns" (uptr) unsigned-16))
  (define table-alignments
    (foreign-procedure "cmark_gfm_extensions_get_table_alignments" (uptr) uptr))
  (define table-row-is-header
    (foreign-procedure "cmark_gfm_extensions_get_table_row_is_header" (uptr) int))
  ;; Via the shim, NOT the cmark entry point directly: the underlying function
  ;; returns C _Bool and binding it as int would read unspecified upper bits.
  (define tasklist-checked
    (foreign-procedure "chez_cmark_tasklist_checked" (uptr) int))

  ;; Copies `count` bytes out of a borrowed uint8_t array. Kept here rather
  ;; than in convert.sls so foreign-ref appears in exactly one library. A NULL
  ;; array yields all zeros -- "no alignment set" -- instead of faulting.
  (define (alignment-bytes addr count)
    (let loop ((i (- count 1)) (acc (quote ())))
      (cond
        ((negative? i) acc)
        ((zero? addr) (loop (- i 1) (cons 0 acc)))
        (else (loop (- i 1)
                    (cons (foreign-ref (quote unsigned-8) addr i) acc))))))
```

- [ ] **Step 6: Run it to verify it passes**

```bash
make build && CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-native.sps
```

Expected: 25 new passes, `# of unexpected failures 0`.

- [ ] **Step 7: Watch the extension-library assertion fail**

In `native.sls`, temporarily change `table-row-is-header`'s entry point name to
`"cmark_gfm_extensions_get_table_row_is_headerX"`. Run the suite. Expected:
failure at **import** time with `no entry for
"cmark_gfm_extensions_get_table_row_is_headerX"` — proof that these symbols are
resolved at library-body evaluation, not at first call. Revert and confirm the
suite passes. Record for Task 12.

- [ ] **Step 8: Run the full suite and commit**

```bash
make test
git add src/cmark-gfm-shim.h src/cmark-gfm-shim.c \
        src/cmark/gfm/private/native.sls tests/test-native.sps
git commit -m "feat: bind the cmark node accessors and normalise the _Bool return"
```

---

# Task 6: The converter — core CommonMark node types and both ceilings

**Files:**
- Create: `src/cmark/gfm/private/convert.sls`
- Create: `tests/test-convert.sps`

**Interfaces:**
- Consumes: everything from Tasks 1–3 and 5.
- Produces, from `(cmark gfm private convert)`:
  - `(make-convert-ctx max-nodes max-depth positions?)` → ctx, node count starting at 0
  - `(convert-document h ctx)` → node. `h` is a live `native-doc` handle; reads its root and converts the whole tree.
  - `(convert-node ptr type-string depth ctx)` → node. **The type string is a parameter, not read internally.** That is what lets Task 8 reach the unknown-type branch with a real node and a synthetic type string; there is no other way to test a branch cmark cannot produce.
  - `(type-string->entry type-string)` → entry record or `#f`
  - `(node-entry-type entry)` → symbol, `(node-entry-keys entry)` → list of symbols, `(node-entry-extractor entry)` → procedure or `#f`
  - `(node-table-type-strings)` → list of the type strings the table covers

- [ ] **Step 1: Write the failing test suite**

Create `tests/test-convert.sps`:

```scheme
#!r6rs
;;; The native-to-Scheme AST copy.
;;;
;;; These suites drive convert.sls directly, through
;;; call-with-native-document, because markdown->ast does not exist yet
;;; (Task 9) and because driving layer 2 directly is what keeps the lifecycle
;;; rules of ADR-0005 and ADR-0006 in force around every probe.
(import (rnrs)
        (srfi :64)
        (cmark gfm ast)
        (cmark gfm private native)
        (cmark gfm private scope)
        (cmark gfm private convert)
        (cmark gfm private conditions))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "convert")

;; --- drivers ------------------------------------------------------------
(define ast-of
  (case-lambda
    ((markdown) (ast-of markdown #f (quote ())))
    ((markdown positions?) (ast-of markdown positions? (quote ())))
    ((markdown positions? exts)
     (call-with-native-document
      markdown (option-bits #f positions? #f #f #f #f) exts
      (lambda (h)
        (convert-document h (make-convert-ctx 250000 1000 positions?)))))))

(define (ast-of/limits markdown max-nodes max-depth)
  (call-with-native-document
   markdown (option-bits #f #f #f #f #f #f) (quote ())
   (lambda (h) (convert-document h (make-convert-ctx max-nodes max-depth #f)))))

;; A compact, directly comparable rendering: type, properties, children.
(define (shape n)
  (list (markdown-node-type n)
        (markdown-node-properties n)
        (map shape (markdown-node-children n))))

(define (nodes-of-type tree type)
  (reverse (markdown-node-fold
            (lambda (n acc)
              (if (eq? (markdown-node-type n) type) (cons n acc) acc))
            (quote ()) tree)))

(define (first-of-type tree type) (car (nodes-of-type tree type)))

;; --- the whole tree, exactly ---------------------------------------------
;; Compared as a complete structure rather than by spot-checking accessors: a
;; converter that dropped a child, duplicated one, or nested them one level
;; wrong would satisfy any per-node assertion while failing this.
(test-equal "a heading and a paragraph convert to the exact expected tree"
  '(document ()
    ((heading ((level . 1)) ((text ((literal . "hi")) ())))
     (paragraph () ((text ((literal . "para")) ())))))
  (shape (ast-of "# hi\n\npara\n")))

(test-equal "inline emphasis nests inside the paragraph"
  '(document ()
    ((paragraph ()
      ((text ((literal . "a ")) ())
       (emph () ((text ((literal . "b")) ())))
       (text ((literal . " c")) ())))))
  (shape (ast-of "a *b* c\n")))

(test-equal "strong, code, and breaks convert"
  '(strong code softbreak linebreak)
  (map markdown-node-type
       (list (first-of-type (ast-of "**b**\n") 'strong)
             (first-of-type (ast-of "`c`\n") 'code)
             (first-of-type (ast-of "a\nb\n") 'softbreak)
             (first-of-type (ast-of "a\\\nb\n") 'linebreak))))

(test-equal "a block quote wraps its paragraph"
  '(blockquote () ((paragraph () ((text ((literal . "q")) ())))))
  (shape (first-of-type (ast-of "> q\n") 'blockquote)))

(test-equal "a thematic break is a childless node with no properties"
  '(thematic-break () ())
  (shape (first-of-type (ast-of "---\n") 'thematic-break)))

;; --- per-type properties -------------------------------------------------
(test-equal "heading level is copied"
  4 (markdown-node-property (first-of-type (ast-of "#### h\n") 'heading) 'level))

(test-equal "a fenced code block carries literal and fence info"
  '("(+ 1 2)\n" "scheme")
  (let ((n (first-of-type (ast-of "```scheme\n(+ 1 2)\n```\n") 'code-block)))
    (list (markdown-node-property n 'literal)
          (markdown-node-property n 'fence-info))))
;; Empty string, not #f: cmark distinguishes "no info string" from "not a code
;; block", and so must the AST.
(test-equal "an indented code block has an empty fence info"
  ""
  (markdown-node-property
   (first-of-type (ast-of "    x\n") 'code-block) 'fence-info))

(test-equal "a link carries url and title"
  '("http://e.example/" "T")
  (let ((n (first-of-type (ast-of "[x](http://e.example/ \"T\")\n") 'link)))
    (list (markdown-node-property n 'url)
          (markdown-node-property n 'title))))
(test-equal "a link with no title carries an empty title, not #f"
  "" (markdown-node-property
      (first-of-type (ast-of "[x](http://e.example/)\n") 'link) 'title))
(test-equal "an image carries url and title"
  '("i.png" "alt")
  (let ((n (first-of-type (ast-of "![x](i.png \"alt\")\n") 'image)))
    (list (markdown-node-property n 'url)
          (markdown-node-property n 'title))))

(test-equal "raw HTML is preserved verbatim in both positions"
  '("<div>\n" "<b>")
  (list (markdown-node-property
         (first-of-type (ast-of "<div>\n") 'html-block) 'literal)
        (markdown-node-property
         (first-of-type (ast-of "a <b> c\n") 'html-inline) 'literal)))

;; --- lists and items ----------------------------------------------------
;; The numeric cmark constants are mapped to symbols HERE, in layer 3's data,
;; not carried through as integers.
(test-equal "an ordered list maps kind, start, delimiter, and tightness"
  '((kind . ordered) (start . 3) (tight? . #t) (delimiter . period))
  (markdown-node-properties (first-of-type (ast-of "3. a\n4. b\n") 'list)))
(test-equal "a paren-delimited ordered list maps the delimiter"
  'paren
  (markdown-node-property (first-of-type (ast-of "1) a\n") 'list) 'delimiter))
(test-equal "a bullet list maps kind bullet and no delimiter"
  '((kind . bullet) (start . 0) (tight? . #t) (delimiter . none))
  (markdown-node-properties (first-of-type (ast-of "- a\n") 'list)))
;; The three-argument form with a sentinel is load-bearing here, not verbosity:
;; markdown-node-property's two-argument form returns #f for an ABSENT key, and
;; #f is also the correct value for a loose list -- so without the sentinel this
;; assertion passes identically whether tight? was computed correctly or was
;; never produced at all. Verified: deleting the tight? pair from list-props
;; leaves the two-argument form green while three other assertions fail.
(test-equal "a loose list reports tight? #f"
  #f (markdown-node-property (first-of-type (ast-of "- a\n\n- b\n") 'list)
                             'tight? 'absent))

;; index is one of the three properties cmark's XML never emits, so the
;; differential harness of Tasks 10-11 cannot see it. It is asserted directly
;; here or it is not covered at all (design spec 8.3).
(test-equal "item index is copied for every item in an offset ordered list"
  '(3 4 5)
  (map (lambda (n) (markdown-node-property n 'index))
       (nodes-of-type (ast-of "3. a\n4. b\n5. c\n") 'item)))
(test-equal "a plain item is not a task and is not checked"
  '((index . 0) (task? . #f) (checked? . #f))
  (markdown-node-properties (first-of-type (ast-of "- a\n") 'item)))

;; --- key sets are exactly what the table declares ------------------------
;; This is project plan 7.3's property table turned into an executable check.
;; An extractor that invents a key, renames one, or forgets one fails here by
;; name -- which is what makes the generic property lookup safe without a
;; named accessor per property.
(define (key-set-mismatches tree)
  (reverse
   (markdown-node-fold
    (lambda (n acc)
      (let* ((ts (node-type->type-string-for-test n))
             (entry (and ts (type-string->entry ts))))
        (if (not entry)
            acc
            (let ((declared (list-sort symbol<? (node-entry-keys entry)))
                  (actual (list-sort symbol<?
                                     (map car (markdown-node-properties n)))))
              (if (equal? declared actual)
                  acc
                  (cons (list (markdown-node-type n) declared actual) acc))))))
    (quote ()) tree)))

;; The test's OWN mapping from node type back to a type string, written
;; independently of convert.sls's table. If it read the table it would be
;; comparing the table against itself.
(define (node-type->type-string-for-test n)
  (case (markdown-node-type n)
    ((document) "document") ((paragraph) "paragraph")
    ((blockquote) "block_quote") ((thematic-break) "thematic_break")
    ((softbreak) "softbreak") ((linebreak) "linebreak")
    ((emph) "emph") ((strong) "strong")
    ((heading) "heading") ((text) "text") ((code) "code")
    ((html-inline) "html_inline") ((html-block) "html_block")
    ((code-block) "code_block") ((link) "link") ((image) "image")
    ((list) "list")
    ((item) (if (markdown-node-property n 'task?) "tasklist" "item"))
    (else #f)))

(define (symbol<? a b) (string<? (symbol->string a) (symbol->string b)))

(test-equal "every core node's key set is exactly what the table declares"
  (quote ())
  (key-set-mismatches
   (ast-of (string-append
            "# h\n\npara with *emph* and `code` and <b>html</b>\n\n"
            "> quote\n\n---\n\n```scheme\nx\n```\n\n    indented\n\n"
            "3. a\n4. b\n\n- bullet\n\n<div>\n\n"
            "[l](u \"t\") ![i](v \"w\")\n\nsoft\nbreak\n"))))

;; --- the table covers every reachable core type -------------------------
;; The expected list is derived independently from cmark's node-type enum
;; (vendor/cmark-gfm/src/cmark-gfm.h), not from the table. Comparing the table
;; against itself would prove nothing.
(test-equal "the table has an entry for every reachable core type string"
  (quote ())
  (filter (lambda (ts) (not (type-string->entry ts)))
          '("document" "block_quote" "list" "item" "code_block" "html_block"
            "paragraph" "heading" "thematic_break"
            "text" "softbreak" "linebreak" "code" "html_inline"
            "emph" "strong" "link" "image")))

;; --- the tree outlives the native document ------------------------------
;; M3's exit criterion. The tree is returned OUT of the scope, so every
;; assertion below runs after the parser and root have been freed. Reading a
;; literal here would be a use-after-free if any string had been borrowed
;; rather than copied.
(define escaped (ast-of "# hi\n\n[l](http://e.example/ \"T\")\n"))

(test-equal "literals are readable after the native document is gone"
  '("hi" "l")
  (map (lambda (n) (markdown-node-property n 'literal))
       (nodes-of-type escaped 'text)))
(test-equal "a url is readable after the native document is gone"
  "http://e.example/"
  (markdown-node-property (first-of-type escaped 'link) 'url))
(test-equal "every native allocation was released"
  '(0 0 0) (live-counts))

;; Structural proof that no pointer escaped: a borrowed pointer would show up
;; as an integer where a string is documented.
(test-equal "every string-valued property really is a string"
  (quote ())
  (reverse
   (markdown-node-fold
    (lambda (n acc)
      (fold-left
       (lambda (acc pair)
         (if (and (memq (car pair) '(literal url title fence-info))
                  (not (string? (cdr pair))))
             (cons (list (markdown-node-type n) (car pair) (cdr pair)) acc)
             acc))
       acc (markdown-node-properties n)))
    (quote ()) escaped)))

;; --- resource limits ----------------------------------------------------
;; n leading '>' characters produce n nested block quotes, so the document
;; holds 1 + n + 1 + 1 nodes (document, quotes, paragraph, text) at a maximum
;; depth of n + 3. Both numbers are computed from that structure rather than
;; hardcoded, so the tests say why they use the values they use.
(define (nested n) (string-append (make-string n #\>) " x\n"))

(test-equal "a document exactly at the depth limit converts"
  'document (markdown-node-type (ast-of/limits (nested 7) 250000 10)))
(test-equal "one level past the depth limit raises too-deep"
  '(too-deep 10)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (ast-of/limits (nested 8) 250000 10)
    'no-condition))
(test-equal "a document exactly at the node limit converts"
  'document (markdown-node-type (ast-of/limits (nested 7) 10 1000)))
(test-equal "one node past the node limit raises too-many-nodes"
  '(too-many-nodes 10)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (ast-of/limits (nested 8) 10 1000)
    'no-condition))
;; The failure path is also a memory test: the condition escapes through
;; call-with-native-document, whose after-thunk must still free the parser and
;; root on the way out (design spec 6.3).
(test-equal "a limit failure leaves no native allocation behind"
  '(0 0 0)
  (begin
    (guard (e ((cmark-resource-limit? e) #t))
      (ast-of/limits (nested 400) 10 1000))
    (live-counts)))

(test-end "convert")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: import failure — `library (cmark gfm private convert) not found`.

- [ ] **Step 3: Write the converter**

Create `src/cmark/gfm/private/convert.sls`:

```scheme
#!r6rs
;;; The native-to-Scheme AST copy -- the imperative shell.
;;;
;;; This is the only library that walks a native tree. Three rules govern it:
;;;
;;;   1. Dispatch on cmark_node_get_type_string, never on the node-type enum.
;;;      The extension node types are assigned at RUNTIME by
;;;      cmark_syntax_extension_add_node (extensions/table.c:871-873), so
;;;      their numeric values are not constants at all.
;;;
;;;   2. Every borrowed string is copied at the moment of read. There is no
;;;      lazy read: the tree must be fully materialised before the enclosing
;;;      call-with-native-document scope exits, because that is what makes the
;;;      result valid after teardown.
;;;
;;;   3. This library takes PRIMITIVES, never the options record. Layer 2 must
;;;      not import layer 3; parse.sls unpacks the record, exactly as
;;;      render.sls unpacks option bits.
;;;
;;; convert-node takes the type string as an ARGUMENT rather than reading it
;;; from the node. That is deliberate: it is the only way to exercise the
;;; unknown-type branch, which cmark cannot be made to produce through this
;;; library's options (design spec 7).
(library (cmark gfm private convert)
  (export convert-document convert-node make-convert-ctx
          type-string->entry
          node-entry-type node-entry-keys node-entry-extractor
          node-table-type-strings)
  (import (rnrs)
          (cmark gfm ast)
          (cmark gfm private native)
          (cmark gfm private scope)
          (cmark gfm private conditions))

  ;; --- conversion context ----------------------------------------------
  ;; count is mutable and threaded by reference rather than returned, so the
  ;; recursion stays a plain tree walk instead of a state-passing fold.
  (define-record-type (convert-ctx %make-convert-ctx convert-ctx?)
    (fields (mutable count) max-nodes max-depth positions?))

  (define (make-convert-ctx max-nodes max-depth positions?)
    (%make-convert-ctx 0 max-nodes max-depth positions?))

  ;; --- borrowed strings -------------------------------------------------
  ;; c-string->string maps NULL to #f. For every property the table declares,
  ;; the accessor is called only on a node type that supports it, so NULL is
  ;; unreachable -- but writing #f where a string is documented would be a
  ;; silent lie about the document's contents, so this raises instead. The
  ;; unreachability is recorded as a deliberate gap (design spec 12).
  (define (copy-required addr)
    (let ((s (c-string->string addr)))
      (or s (raise (make-cmark-error)))))

  ;; --- property extractors ---------------------------------------------
  ;; One procedure per shape, shared where the shape is shared, so there is
  ;; one place to fix each mapping.
  (define (literal-props p)
    (list (cons 'literal (copy-required (node-literal p)))))

  (define (heading-props p)
    (list (cons 'level (node-heading-level p))))

  (define (code-block-props p)
    (list (cons 'literal (copy-required (node-literal p)))
          (cons 'fence-info (copy-required (node-fence-info p)))))

  (define (link-props p)
    (list (cons 'url (copy-required (node-url p)))
          (cons 'title (copy-required (node-title p)))))

  ;; cmark's numeric list constants stop here: 1 = CMARK_BULLET_LIST,
  ;; 2 = CMARK_ORDERED_LIST; 1 = CMARK_PERIOD_DELIM, 2 = CMARK_PAREN_DELIM.
  (define (list-props p)
    (list (cons 'kind (if (= 2 (node-list-type p)) 'ordered 'bullet))
          (cons 'start (node-list-start p))
          (cons 'tight? (not (zero? (node-list-tight p))))
          (cons 'delimiter
                (case (node-list-delim p)
                  ((1) 'period)
                  ((2) 'paren)
                  (else 'none)))))

  ;; Uniform key set with the task variant below (design spec 3.4): a
  ;; consumer never branches on key presence, and the key-set check compares a
  ;; fixed set rather than a conditional one.
  (define (plain-item-props p)
    (list (cons 'index (node-item-index p))
          (cons 'task? #f)
          (cons 'checked? #f)))

  ;; --- the table --------------------------------------------------------
  ;; type string -> node type, declared property keys, extractor (#f for
  ;; propertyless types). The declared keys are DATA so the suite can assert
  ;; that what an extractor produces is exactly what the table promises.
  ;; Four fields: the cmark type string (the dispatch key), the node-type
  ;; symbol the AST uses, the declared property keys, and the extractor.
  (define-record-type (node-entry make-node-entry node-entry?)
    (fields type-string type keys extractor))

  (define node-table
    (list
     (make-node-entry "document"       'document       '() #f)
     (make-node-entry "paragraph"      'paragraph      '() #f)
     (make-node-entry "block_quote"    'blockquote     '() #f)
     (make-node-entry "thematic_break" 'thematic-break '() #f)
     (make-node-entry "softbreak"      'softbreak      '() #f)
     (make-node-entry "linebreak"      'linebreak      '() #f)
     (make-node-entry "emph"           'emph           '() #f)
     (make-node-entry "strong"         'strong         '() #f)
     (make-node-entry "heading"        'heading        '(level) heading-props)
     (make-node-entry "text"           'text           '(literal) literal-props)
     (make-node-entry "code"           'code           '(literal) literal-props)
     (make-node-entry "html_inline"    'html-inline    '(literal) literal-props)
     (make-node-entry "html_block"     'html-block     '(literal) literal-props)
     (make-node-entry "code_block"     'code-block     '(literal fence-info)
                      code-block-props)
     (make-node-entry "link"           'link           '(url title) link-props)
     (make-node-entry "image"          'image          '(url title) link-props)
     (make-node-entry "list"           'list           '(kind start tight? delimiter)
                      list-props)
     (make-node-entry "item"           'item           '(index task? checked?)
                      plain-item-props)))

  (define (type-string->entry ts)
    (let loop ((es node-table))
      (cond ((null? es) #f)
            ((string=? ts (node-entry-type-string (car es))) (car es))
            (else (loop (cdr es))))))

  (define (node-table-type-strings)
    (map node-entry-type-string node-table))

  ;; --- source positions -------------------------------------------------
  ;; Only when requested, and only when cmark actually has one: xml.c:48
  ;; guards its own sourcepos attribute with start_line != 0, and the AST
  ;; reports the same absence as #f rather than inventing 0:0-0:0. Positions
  ;; obtained from a parse WITHOUT CMARK_OPT_SOURCEPOS are not merely absent
  ;; but wrong (inlines.c:292-296 skips a correction that propagates to later
  ;; inlines), which is why this is gated on the same flag that was parsed
  ;; with, never on a separate switch.
  (define (node-source p ctx)
    (and (convert-ctx-positions? ctx)
         (let ((sl (node-start-line p)))
           (and (not (zero? sl))
                (make-source-position sl
                                      (node-start-column p)
                                      (node-end-line p)
                                      (node-end-column p))))))

  ;; --- the walk ---------------------------------------------------------
  (define (check-depth! depth ctx)
    (when (> depth (convert-ctx-max-depth ctx))
      (raise (make-cmark-resource-limit 'too-deep (convert-ctx-max-depth ctx)))))

  (define (count-node! ctx)
    (convert-ctx-count-set! ctx (+ 1 (convert-ctx-count ctx)))
    (when (> (convert-ctx-count ctx) (convert-ctx-max-nodes ctx))
      (raise (make-cmark-resource-limit 'too-many-nodes
                                       (convert-ctx-max-nodes ctx)))))

  (define (convert-children p depth ctx)
    (let loop ((c (node-first-child p)) (acc '()))
      (if (zero? c)
          (reverse acc)
          (loop (node-next c)
                (cons (convert-node c (copy-required (node-type-string c))
                                    depth ctx)
                      acc)))))

  ;; Both ceilings are checked on entry, before any child is visited, so
  ;; exceeding one raises instead of recursing further. The condition escapes
  ;; through call-with-native-document, whose after-thunk frees the parser and
  ;; root; the partially built Scheme tree is simply dropped.
  (define (convert-node p type-string depth ctx)
    (check-depth! depth ctx)
    (count-node! ctx)
    (let ((entry (type-string->entry type-string))
          (children (convert-children p (+ depth 1) ctx))
          (source (node-source p ctx)))
      (make-markdown-node (node-entry-type entry)
                          (let ((extract (node-entry-extractor entry)))
                            (if extract (extract p) '()))
                          children
                          source)))

  ;; The document root is depth 1; a child is its parent's depth plus one.
  (define (convert-document h ctx)
    (let ((root (doc-root h)))
      (convert-node root (copy-required (node-type-string root)) 1 ctx))))
```

- [ ] **Step 4: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: 29 passes, `# of unexpected failures 0`.

`convert-node` will raise `&cmark-error` from `node-entry-type` applied to `#f`
if a type string has no entry — that is Task 8's branch and is not reachable
from these fixtures. If it fires here, a core type is missing from the table.

- [ ] **Step 5: Watch the load-bearing assertions fail**

Four mutations, each run and reverted one at a time. Each must fail **by name**
through the property it claims to guard:

1. In `list-props`, return `'bullet` unconditionally. Expected: `an ordered list maps kind, start, delimiter, and tightness` FAILS; the bullet-list test still passes.
2. In `code-block-props`, drop the `fence-info` pair. Expected: `every core node's key set is exactly what the table declares` FAILS, reporting `(code-block (fence-info literal) (literal))`, **and** `a fenced code block carries literal and fence info` FAILS.
3. Delete the `check-depth!` call from `convert-node`. Expected: `one level past the depth limit raises too-deep` FAILS with `no-condition`.
4. Delete the `count-node!` call. Expected: `one node past the node limit raises too-many-nodes` FAILS with `no-condition`.

Confirm all 29 pass after each revert. Record all four for Task 12.

- [ ] **Step 6: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/private/convert.sls tests/test-convert.sps
git commit -m "feat: copy core CommonMark nodes into the Scheme AST, with ceilings"
```

---

# Task 7: The converter — GFM extension node types

**Files:**
- Modify: `src/cmark/gfm/private/convert.sls`
- Modify: `tests/test-convert.sps`

**Interfaces:**
- Consumes: everything from Task 6, plus `table-columns`, `table-alignments`, `table-row-is-header`, `tasklist-checked`, `alignment-bytes` from Task 5.
- Produces: six more `node-table` entries — `"strikethrough"` → `strikethrough` (no properties), `"tasklist"` → `item` with `(index task? checked?)`, `"table"` → `table` with `(columns alignments)`, `"table_header"` → `table-row` with `(header?)`, `"table_row"` → `table-row` with `(header?)`, `"table_cell"` → `table-cell` with `(alignment)`. Alignment values are the symbols `left`, `center`, `right`, `none`.

Cell alignment is the one property that cannot be read from the cell itself:
`get_cell_alignment` uses `node->as.cell_index`
(`vendor/cmark-gfm/extensions/table.c:133-139`), which is not exported. It is
derived from the cell's zero-based position among its row's children, indexing
the table's `alignments` list — which means the table's alignments have to be
in scope while the cells are converted.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-convert.sps`, immediately **before** the final
`(test-end "convert")` line:

```scheme
;; --- GFM extension node types -------------------------------------------
(define all-exts '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))
(define (ext-ast markdown) (ast-of markdown #f all-exts))

(define table-md "| a | b | c |\n|:--|--:|---|\n| 1 | 2 | 3 |\n")

(test-equal "strikethrough converts and keeps its child"
  '(strikethrough () ((text ((literal . "s")) ())))
  (shape (first-of-type (ext-ast "~~s~~\n") 'strikethrough)))

;; An autolink becomes an ordinary link node (project plan 7.3), so there is
;; no autolink node type to map.
(test-equal "an autolink becomes an ordinary link node"
  "http://e.example/"
  (markdown-node-property
   (first-of-type (ext-ast "http://e.example/\n") 'link) 'url))

;; columns is one of the three properties cmark's XML never emits, so the
;; differential harness cannot see it (design spec 8.3). Asserted here.
(test-equal "a table reports its column count and per-column alignments"
  '((columns . 3) (alignments . (left right none)))
  (markdown-node-properties (first-of-type (ext-ast table-md) 'table)))

(test-equal "the header row and the body row are both table-row nodes"
  '(table-row table-row)
  (map markdown-node-type (nodes-of-type (ext-ast table-md) 'table-row)))
;; Sentinel default: header? is one of the properties ast.sls names as having
;; #f as a legitimate value, so a two-argument lookup could not tell a body row
;; correctly reporting #f from an extractor that stopped emitting the key.
(test-equal "header? distinguishes the two rows"
  '(#t #f)
  (map (lambda (n) (markdown-node-property n 'header? 'absent))
       (nodes-of-type (ext-ast table-md) 'table-row)))

;; Body-cell alignment is the third XML blind spot: table.c:661 emits align=
;; only for cells whose parent row is a header. Both rows are asserted here so
;; the body row is not silently uncovered.
(test-equal "header cells carry their column's alignment"
  '(left right none)
  (map (lambda (n) (markdown-node-property n 'alignment))
       (markdown-node-children
        (car (nodes-of-type (ext-ast table-md) 'table-row)))))
(test-equal "body cells carry the same alignments as the header"
  '(left right none)
  (map (lambda (n) (markdown-node-property n 'alignment))
       (markdown-node-children
        (cadr (nodes-of-type (ext-ast table-md) 'table-row)))))

;; Task detection comes from the type string, because
;; get_tasklist_item_checked cannot distinguish an unchecked task from a
;; non-task (tasklist.c:30-40). All three cases are asserted together, since
;; that is the discrimination a single-case test would miss.
;; Sentinel defaults for the same reason as the loose-list assertion in Task 6:
;; the plain item's expected pair is (#f . #f), which a two-argument lookup would
;; also produce if plain-item-props stopped emitting either key at all.
(test-equal "checked, unchecked, and plain items are all distinguished"
  '((#t . #t) (#t . #f) (#f . #f))
  (map (lambda (n) (cons (markdown-node-property n 'task? 'absent)
                         (markdown-node-property n 'checked? 'absent)))
       (nodes-of-type (ext-ast "- [x] done\n- [ ] todo\n\n* plain\n") 'item)))

(test-equal "a task item still carries its index"
  0 (markdown-node-property
     (first-of-type (ext-ast "- [x] done\n") 'item) 'index))

;; Two independent channels for the same fact: the type string
;; (table.c:523-535) and the extension accessor. Redundancy turned into a
;; cross-check for one assertion's worth of effort.
(test-equal "header? agrees with cmark's own row accessor on every row"
  (quote ())
  (call-with-native-document
   table-md (option-bits #f #f #f #f #f #f) all-exts
   (lambda (h)
     (let* ((tree (convert-document h (make-convert-ctx 250000 1000 #f)))
            (ours (map (lambda (n) (markdown-node-property n 'header? 'absent))
                       (nodes-of-type tree 'table-row)))
            ;; walk to the table's rows natively: document -> table -> rows
            (table (node-first-child (doc-root h)))
            (theirs (let loop ((r (node-first-child table)) (acc (quote ())))
                      (if (zero? r)
                          (reverse acc)
                          (loop (node-next r)
                                (cons (not (zero? (table-row-is-header r)))
                                      acc))))))
       (if (equal? ours theirs) (quote ()) (list ours theirs))))))

;; --- key sets and coverage for the extension types ----------------------
(test-equal "the table has an entry for every reachable extension type string"
  (quote ())
  (filter (lambda (ts) (not (type-string->entry ts)))
          '("strikethrough" "tasklist" "table" "table_header" "table_row"
            "table_cell")))

(test-equal "the table covers exactly the 24 reachable type strings and no more"
  24 (length (node-table-type-strings)))

(test-equal "extension nodes' key sets are exactly what the table declares"
  (quote ())
  (let ((tree (ext-ast (string-append table-md "\n~~s~~\n\n- [x] a\n- [ ] b\n"))))
    (reverse
     (markdown-node-fold
      (lambda (n acc)
        (let* ((ts (case (markdown-node-type n)
                     ((strikethrough) "strikethrough")
                     ((table) "table")
                     ((table-row) (if (markdown-node-property n 'header?)
                                      "table_header" "table_row"))
                     ((table-cell) "table_cell")
                     ((item) (if (markdown-node-property n 'task?)
                                 "tasklist" "item"))
                     (else #f)))
               (entry (and ts (type-string->entry ts))))
          (if (not entry)
              acc
              (let ((declared (list-sort symbol<? (node-entry-keys entry)))
                    (actual (list-sort symbol<?
                                       (map car (markdown-node-properties n)))))
                (if (equal? declared actual)
                    acc
                    (cons (list (markdown-node-type n) declared actual) acc))))))
      (quote ()) tree))))

(test-equal "extension trees also outlive the native document"
  '("s" "a" "b")
  (let ((escaped-ext (ext-ast "~~s~~\n\n- [x] a\n- [ ] b\n")))
    (map (lambda (n) (markdown-node-property n 'literal))
         (nodes-of-type escaped-ext 'text))))
(test-equal "extension conversion released every native allocation"
  '(0 0 0) (live-counts))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: failures on the extension assertions. The `strikethrough` case fails
with an `&assertion` from `node-entry-type` applied to `#f` — the table has no
entry, so the lookup returns `#f`. That is the correct pre-Task-8 failure.

- [ ] **Step 3: Add alignment mapping and the table-aware walk**

In `src/cmark/gfm/private/convert.sls`, add the alignment vocabulary and the
extension extractors after `plain-item-props`:

```scheme
  ;; Alignment bytes are ASCII: 0 (none), 'l', 'c', 'r'
  ;; (vendor/cmark-gfm/extensions/table.c:387-391).
  (define (alignment-byte->symbol b)
    (cond ((= b 108) 'left)      ; #\l
          ((= b 99)  'center)    ; #\c
          ((= b 114) 'right)     ; #\r
          (else 'none)))

  ;; table-columns and table-alignments (extensions/table.c:878-890) test
  ;; node->type and safely return 0/NULL for a non-table node -- not a fault.
  ;; What they lack, unlike get_cell_alignment (table.c:133-139), is a guard
  ;; against a NULL node. Moot here: get_type_string (table.c:526) returns
  ;; "table" only when node->type == CMARK_NODE_TABLE, checked on the same
  ;; node whose type string dispatched us to this branch.
  (define (table-props p)
    (let ((n (table-columns p)))
      (list (cons 'columns n)
            (cons 'alignments
                  (map alignment-byte->symbol
                       (alignment-bytes (table-alignments p) n))))))

  (define (header-row-props p) (list (cons 'header? #t)))
  (define (body-row-props p)   (list (cons 'header? #f)))

  ;; A task item's checked state is meaningful only because its TYPE STRING is
  ;; "tasklist" (extensions/tasklist.c:13-17). tasklist-checked alone cannot
  ;; distinguish an unchecked task from a non-task, so it is consulted only
  ;; after the type string has already established that this is a task item.
  (define (task-item-props p)
    (list (cons 'index (node-item-index p))
          (cons 'task? #t)
          (cons 'checked? (not (zero? (tasklist-checked p))))))
```

Cell alignment needs the enclosing table's alignments, which no cell accessor
exposes. Thread them down the walk: add a fifth field to the context holding
the alignments of the table currently being converted.

Replace the context definition and constructor with:

```scheme
  ;; column-alignments holds the alignments of the table currently being
  ;; walked, because a cell cannot ask for its own: get_cell_alignment reads
  ;; node->as.cell_index (extensions/table.c:133-139), which is not exported.
  ;; A cell's alignment is therefore its zero-based position among its row's
  ;; children, indexed into this list.
  (define-record-type (convert-ctx %make-convert-ctx convert-ctx?)
    (fields (mutable count) max-nodes max-depth positions?
            (mutable column-alignments)))

  (define (make-convert-ctx max-nodes max-depth positions?)
    (%make-convert-ctx 0 max-nodes max-depth positions? '()))
```

Replace `convert-children` so it passes each child's index, and have the
`table` and `table_cell` cases use it:

```scheme
  (define (convert-children p depth ctx)
    (let loop ((c (node-first-child p)) (i 0) (acc '()))
      (if (zero? c)
          (reverse acc)
          (loop (node-next c) (+ i 1)
                (cons (convert-node/index c (copy-required (node-type-string c))
                                          depth i ctx)
                      acc)))))

  ;; Cell alignment is positional, so the child index has to reach the
  ;; extractor. Only table_cell uses it; everything else ignores it.
  (define (convert-node/index p type-string depth index ctx)
    (if (string=? type-string "table_cell")
        (let ((aligns (convert-ctx-column-alignments ctx)))
          (with-node p type-string depth ctx
                     (list (cons 'alignment
                                 (if (< index (length aligns))
                                     (list-ref aligns index)
                                     'none)))))
        (convert-node p type-string depth ctx)))
```

Then factor the node-building body out of `convert-node` so both entry points
share it, and make the `table` case record its alignments before descending:

```scheme
  ;; properties-override is #f for every type except table_cell, whose
  ;; alignment cannot be computed from the node alone.
  (define (with-node p type-string depth ctx properties-override)
    (check-depth! depth ctx)
    (count-node! ctx)
    (let* ((entry (type-string->entry type-string))
           ;; A table publishes its alignments into the context before its
           ;; rows and cells are walked, and restores the previous value
           ;; afterwards so nested tables cannot leak alignments outward.
           ;; cmark cannot nest tables today; the save/restore costs one
           ;; binding and removes the question.
           (saved (convert-ctx-column-alignments ctx))
           (props (or properties-override
                      (let ((extract (node-entry-extractor entry)))
                        (if extract (extract p) '())))))
      (when (string=? type-string "table")
        (convert-ctx-column-alignments-set!
         ctx (cdr (assq 'alignments props))))
      (let ((children (convert-children p (+ depth 1) ctx))
            (source (node-source p ctx)))
        (convert-ctx-column-alignments-set! ctx saved)
        (make-markdown-node (node-entry-type entry) props children source))))

  ;; Exported so tests can drive it directly (see the type-string note at
  ;; the top of this file), but never call this with type-string
  ;; "table_cell": alignment is supplied positionally by convert-node/index,
  ;; the only path convert-children takes, so a direct table_cell call here
  ;; would silently produce a table-cell node with no alignment property.
  (define (convert-node p type-string depth ctx)
    (with-node p type-string depth ctx #f))
```

Finally add the six entries to `node-table`, after the `"item"` entry:

```scheme
     (make-node-entry "strikethrough" 'strikethrough '() #f)
     (make-node-entry "tasklist"     'item      '(index task? checked?)
                      task-item-props)
     (make-node-entry "table"        'table     '(columns alignments) table-props)
     (make-node-entry "table_header" 'table-row '(header?) header-row-props)
     (make-node-entry "table_row"    'table-row '(header?) body-row-props)
     ;; alignment is supplied positionally by convert-node/index, so this
     ;; entry declares the key but has no extractor of its own.
     (make-node-entry "table_cell"   'table-cell '(alignment) #f)))
```

- [ ] **Step 4: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: 15 new passes, `# of unexpected failures 0`, and
`the table covers exactly the 24 reachable type strings and no more` reporting 24.

- [ ] **Step 5: Watch the extension assertions fail**

Three mutations, one at a time, each reverted after:

1. In `task-item-props`, hardcode `(cons 'checked? #f)`. Expected: `checked, unchecked, and plain items are all distinguished` FAILS, reporting `((#t . #f) (#t . #f) (#f . #f))`.
2. Swap `header-row-props` and `body-row-props` in the table entries. Expected: `header? distinguishes the two rows` FAILS with `(#f #t)`, **and** `header? agrees with cmark's own row accessor on every row` FAILS — two independent channels catching one error.
3. In `convert-node/index`, use `(+ index 1)` as the alignment index. Expected: both `header cells carry their column's alignment` and `body cells carry the same alignments as the header` FAIL with `(right none none)`.

Record all three for Task 12.

- [ ] **Step 6: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/private/convert.sls tests/test-convert.sps
git commit -m "feat: copy GFM tables, task lists, and strikethrough into the AST"
```

---

# Task 8: Unknown node types preserved as `extension` nodes

**Files:**
- Modify: `src/cmark/gfm/private/convert.sls`
- Modify: `tests/test-convert.sps`

**Interfaces:**
- Consumes: everything from Tasks 6–7.
- Produces: a type string with no table entry converts to a node of type `extension` whose properties are `((native-type . "<the cmark type string>"))`, plus `(literal . "…")` when `cmark_node_get_literal` returns a string for that node. Children are always converted. This is the one node type whose key set is not fixed, because the key set of an unknown type cannot be known in advance.

**Why this needs a synthetic type string.** Given the options this library
exposes, no unknown type is reachable: `footnote_definition` and
`footnote_reference` require `CMARK_OPT_FOOTNOTES`, which is not exposed;
`custom_block` and `custom_inline` are never produced by the parser. The branch
is nonetheless real code and must be exercised — which is why `convert-node`
takes the type string as a parameter. The test passes a **real** node pointer
with a **fake** type string, so the fallback runs against real memory.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-convert.sps`, immediately **before** the final
`(test-end "convert")` line:

```scheme
;; --- the unknown-type fallback (design spec 7) --------------------------
;; No document can reach this branch through the public options, so it is
;; driven directly: a real node pointer with a type string cmark never
;; produced here. That is what convert-node's type-string parameter is for.
(define (convert-as markdown type-string)
  (call-with-native-document
   markdown (option-bits #f #f #f #f #f #f) (quote ())
   (lambda (h)
     ;; document -> first block, converted as though it were an unknown type
     (let ((block (node-first-child (doc-root h))))
       (convert-node block type-string 2 (make-convert-ctx 250000 1000 #f))))))

(test-equal "an unrecognised type string becomes an extension node"
  'extension
  (markdown-node-type (convert-as "para\n" "footnote_definition")))

(test-equal "the extension node records the native type string verbatim"
  "footnote_definition"
  (markdown-node-property (convert-as "para\n" "footnote_definition")
                          'native-type))

;; Children must survive: plan 7.4's requirement is preserve, never discard.
(test-equal "an extension node keeps its converted children"
  '((text ((literal . "para")) ()))
  (map shape (markdown-node-children
              (convert-as "para\n" "footnote_definition"))))

;; cmark's "<unknown>" error return takes the same path.
(test-equal "the <unknown> error string also falls back rather than raising"
  '(extension "<unknown>")
  (let ((n (convert-as "para\n" "<unknown>")))
    (list (markdown-node-type n)
          (markdown-node-property n 'native-type))))

;; A paragraph has no literal, so no literal key is invented. Compared as a
;; whole property list: asserting only that native-type is present would pass
;; against an implementation that also added (literal . #f).
(test-equal "no literal key is invented for a node that has none"
  '((native-type . "footnote_definition"))
  (markdown-node-properties (convert-as "para\n" "footnote_definition")))

;; A node that DOES have a literal keeps it, so an unknown extension type
;; carrying text is not silently emptied. The fixture's first block is a
;; paragraph; its first child is the text node, which has a literal.
(test-equal "a literal-bearing node keeps its literal under the fallback"
  '((native-type . "unknown_inline") (literal . "para"))
  (call-with-native-document
   "para\n" (option-bits #f #f #f #f #f #f) (quote ())
   (lambda (h)
     (let ((text (node-first-child (node-first-child (doc-root h)))))
       (markdown-node-properties
        (convert-node text "unknown_inline" 3
                      (make-convert-ctx 250000 1000 #f)))))))

;; The fallback is still subject to both ceilings.
(test-equal "the fallback still counts toward the node ceiling"
  '(too-many-nodes 1)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (call-with-native-document
     "para\n" (option-bits #f #f #f #f #f #f) (quote ())
     (lambda (h)
       (convert-node (node-first-child (doc-root h)) "footnote_definition" 2
                     (make-convert-ctx 1 1000 #f))))
    'no-condition))

;; Both ceilings, not just one. with-node checks depth and count before it
;; computes `entry`, so the fallback is bound exactly as a known type is --
;; but that has to be asserted for each, or a later edit could extend the
;; fallback's (if entry ...) idiom to the ceiling checks with nothing noticing.
;; Verified: making check-depth! conditional on `entry` left all 52 other
;; assertions green. The target node is CHILDLESS on purpose -- with a
;; non-leaf, a deeper known-type child would trip its own check-depth! and
;; mask the mutation.
(test-equal "the fallback still counts toward the depth ceiling"
  '(too-deep 1)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (call-with-native-document
     "---\n" (option-bits #f #f #f #f #f #f) (quote ())
     (lambda (h)
       (convert-node (node-first-child (doc-root h)) "footnote_definition" 2
                     (make-convert-ctx 250000 1 #f))))
    'no-condition))

(test-equal "the fallback path released every native allocation"
  '(0 0 0) (live-counts))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: the first new assertion fails with an `&assertion` from
`node-entry-type` applied to `#f` — the lookup misses and nothing handles it.

- [ ] **Step 3: Add the fallback**

In `src/cmark/gfm/private/convert.sls`, add the extension-node extractor after
`task-item-props`:

```scheme
  ;; Plan 7.4's default: preserve rather than discard, and never lose children
  ;; or literals. Preservation over a raise means a future cmark that adds a
  ;; node type degrades to a usable AST instead of failing every document
  ;; containing one.
  ;;
  ;; This is the one node type whose key set is not fixed (design spec 3.4):
  ;; the keys of an unknown type cannot be known in advance, so `literal` is
  ;; present only when cmark actually has one. c-string->string is used
  ;; directly rather than copy-required, because here #f is the legitimate
  ;; answer -- an unknown node type may well have no string content.
  (define (extension-props p type-string)
    (let ((literal (c-string->string (node-literal p))))
      (if literal
          (list (cons 'native-type type-string) (cons 'literal literal))
          (list (cons 'native-type type-string)))))
```

Then make `with-node` handle a missing entry. Replace its `let*` bindings and
final `make-markdown-node` call with:

```scheme
    (let* ((entry (type-string->entry type-string))
           ;; A table publishes its alignments into the context before its
           ;; rows and cells are walked, and restores the previous value
           ;; afterwards so nested tables cannot leak alignments outward.
           ;; cmark cannot nest tables today; the save/restore costs one
           ;; binding and removes the question.
           (saved (convert-ctx-column-alignments ctx))
           (props (or properties-override
                      (if entry
                          (let ((extract (node-entry-extractor entry)))
                            (if extract (extract p) '()))
                          (extension-props p type-string)))))
      (when (string=? type-string "table")
        (convert-ctx-column-alignments-set!
         ctx (cdr (assq 'alignments props))))
      (let ((children (convert-children p (+ depth 1) ctx))
            (source (node-source p ctx)))
        (convert-ctx-column-alignments-set! ctx saved)
        (make-markdown-node (if entry (node-entry-type entry) 'extension)
                            props children source)))
```

- [ ] **Step 4: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: 9 new passes, `# of unexpected failures 0`.

- [ ] **Step 5: Watch the fallback assertions fail**

Two mutations, one at a time:

1. Make `extension-props` always include the literal pair, even when `c-string->string` returns `#f`. Expected: `no literal key is invented for a node that has none` FAILS, reporting `((native-type . "footnote_definition") (literal . #f))`.
2. In `with-node`, return `'() ` for `props` when `entry` is `#f` instead of calling `extension-props`. Expected: `the extension node records the native type string verbatim` FAILS with `#f`.

Also confirm the fallback does not swallow a real type: temporarily delete the
`"heading"` entry from `node-table` and run the suite. Expected: `a heading and
a paragraph convert to the exact expected tree` FAILS, showing an `extension`
node where a `heading` belongs — proof the fallback is reachable only for types
the table genuinely lacks. Revert all three. Record for Task 12.

- [ ] **Step 6: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/private/convert.sls tests/test-convert.sps
git commit -m "feat: preserve unknown node types as extension nodes"
```

---

# Task 9: `markdown->ast` — the public entry point

**Files:**
- Create: `src/cmark/gfm/parse.sls`
- Modify: `src/cmark/gfm.sls`
- Modify: `tests/test-convert.sps`

**Interfaces:**
- Consumes: `default-ast-options` and the options accessors (Task 4); `convert-document`, `make-convert-ctx` (Tasks 6–8); `call-with-native-document` (pre-existing).
- Produces: `(markdown->ast markdown)` → node, using `(default-ast-options)` so positions are on; `(markdown->ast markdown options)` → node, honouring the caller's record verbatim. Exported from `(cmark gfm parse)` and re-exported from `(cmark gfm)` along with every `(cmark gfm ast)` binding.

`parse.sls` exists so that `markdown->ast` is layer 3. Putting it in
`convert.sls` would place a public export inside layer 2 and would force
`convert.sls` to import `options.sls`, inverting the layering. This mirrors
`render.sls`, which unpacks the options record into option bits for the same
reason.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-convert.sps`, immediately **before** the final
`(test-end "convert")` line. Add two libraries to the suite's import list at the
top of the file:

```scheme
        (cmark gfm options)
        (cmark gfm parse)
```

**Not `(cmark gfm)`.** The façade re-exports the same AST bindings this suite
already imports from `(cmark gfm ast)`. R6RS permits importing one binding by
two routes, but this repo has already been bitten twice by the neighbouring
case where the names collide and the bindings differ (`file-exists?`, `exit`),
so the precise import avoids the question. The façade's re-exports are verified
instead by `tests/test-ast-differential.sps` (Task 10), which imports **only**
`(cmark gfm)` and uses every re-exported AST binding — if `gfm.sls` misses one,
that suite fails at import. The re-exported condition bindings are covered by
Task 13's README check, which reaches `cmark-resource-limit?`,
`cmark-invalid-input-reason`, and `cmark-resource-limit-value` through the
façade.

Then:

```scheme
;; --- markdown->ast, the public entry point ------------------------------
(test-equal "markdown->ast converts through the public API"
  '(document ()
    ((paragraph () ((text ((literal . "hi")) ())))))
  (let ((tree (markdown->ast "hi\n" (make-cmark-options 'source-positions? #f))))
    (shape tree)))

;; ADR-0009: the one-argument form uses default-ast-options, so positions are
;; ON. This is the assertion that makes the arity meaningful -- swap the
;; default and it fails.
(test-equal "the one-argument form attaches source positions"
  #t
  (source-position?
   (markdown-node-source
    (first-of-type (markdown->ast "hi\n") 'paragraph))))

(test-equal "the two-argument form honours an explicit source-positions? #f"
  #f
  (markdown-node-source
   (first-of-type (markdown->ast "hi\n" (make-cmark-options 'source-positions? #f))
                  'paragraph)))

(test-equal "the two-argument form honours an explicit source-positions? #t"
  #t
  (source-position?
   (markdown-node-source
    (first-of-type (markdown->ast "hi\n" (make-cmark-options 'source-positions? #t))
                   'paragraph))))

;; Positions are read from cmark, not synthesised. "# hi" then a blank line
;; then "para" puts the paragraph on line 3, columns 1-4.
(test-equal "positions carry cmark's real line and column spans"
  '(3 1 3 4)
  (let ((p (markdown-node-source
            (first-of-type (markdown->ast "# hi\n\npara\n") 'paragraph))))
    (list (source-position-start-line p) (source-position-start-column p)
          (source-position-end-line p)   (source-position-end-column p))))

;; design spec 4.3 mirrors xml.c:48's `start_line != 0` guard. Verified against
;; the pinned CLI, that branch is UNREACHABLE in ordinary parsing: even an
;; empty document is created with start_line 1 (make_document in
;; vendor/cmark-gfm/src/blocks.c) and cmark emits sourcepos="1:1-0:0" for it.
;; The guard stays, because it keeps the serializer of Task 10 a straight
;; mapping from our record to cmark's output -- but what is asserted here is
;; cmark's real answer, not a synthesised absence. The unreachability is a
;; deliberate gap (Task 13 records it).
(test-equal "the empty document carries cmark's real 1:1-0:0 span"
  '(1 1 0 0)
  (let ((p (markdown-node-source (markdown->ast ""))))
    (list (source-position-start-line p) (source-position-start-column p)
          (source-position-end-line p)   (source-position-end-column p))))

;; The options record's ceilings reach the converter -- this is what proves
;; parse.sls unpacks the record rather than using the defaults.
(test-equal "max-depth from the options record is enforced"
  '(too-deep 10)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (markdown->ast (nested 8) (make-cmark-options 'max-depth 10))
    'no-condition))
(test-equal "max-nodes from the options record is enforced"
  '(too-many-nodes 10)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (markdown->ast (nested 8) (make-cmark-options 'max-nodes 10))
    'no-condition))
;; max-input-bytes reaches it too, and still raises the reason 0.1 shipped.
(test-equal "max-input-bytes still raises too-large, now as a resource limit"
  '(too-large 8)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (markdown->ast "much longer than eight bytes\n"
                   (make-cmark-options 'max-input-bytes 8))
    'no-condition))

;; The extensions the options record names are the ones attached.
(test-equal "extensions from the options record are attached"
  'strikethrough
  (markdown-node-type
   (first-of-type (markdown->ast "~~s~~\n" (make-cmark-options
                                            'extensions '(strikethrough)))
                  'strikethrough)))
(test-equal "an extension the record omits is not attached"
  (quote ())
  (nodes-of-type (markdown->ast "~~s~~\n" (make-cmark-options 'extensions '()))
                 'strikethrough))

(test-equal "a non-options argument is rejected before anything is allocated"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->ast "hi\n" 'not-options)
    'no-condition))

(test-equal "markdown->ast released every native allocation"
  '(0 0 0) (live-counts))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: import failure naming `markdown->ast` as unbound.

- [ ] **Step 3: Write `parse.sls`**

Create `src/cmark/gfm/parse.sls`:

```scheme
#!r6rs
;;; markdown->ast -- the public AST entry point.
;;;
;;; This library exists so that the public procedure is layer 3. convert.sls
;;; is layer 2 and must not import the options record; parse.sls unpacks the
;;; record into primitives, exactly as render.sls unpacks it into option bits.
;;;
;;; The arity is the API. (markdown->ast md) uses default-ast-options, whose
;;; only difference from default-cmark-options is source-positions? #t; the
;;; two-argument form honours the caller's record verbatim. That is ADR-0009's
;;; per-entry-point default, delivered as ordinary data rather than as a third
;;; "unset" state inside the options record.
;;;
;;; Positions are governed by the SAME flag the parse used, never by a
;;; separate switch. CMARK_OPT_SOURCEPOS is not merely a rendering flag: with
;;; it off, cmark skips a correction (vendor/cmark-gfm/src/inlines.c:292-296)
;;; that leaves multi-line code spans and raw inline HTML with wrong end
;;; positions, and the error propagates to later inlines in the same block. So
;;; positions are attached only when they were parsed correctly.
(library (cmark gfm parse)
  (export markdown->ast)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm private conditions)
          (cmark gfm private native)
          (cmark gfm private scope)
          (cmark gfm private convert))

  (define (options->bits o)
    (option-bits (cmark-options-validate-utf8? o)
                 (cmark-options-source-positions? o)
                 (cmark-options-hardbreaks? o)
                 (cmark-options-nobreaks? o)
                 (cmark-options-smart? o)
                 (cmark-options-unsafe-html? o)))

  (define markdown->ast
    (case-lambda
      ((markdown) (markdown->ast markdown (default-ast-options)))
      ((markdown o)
       ;; Checked before anything native is acquired, so a bad argument leaves
       ;; no resource to clean up -- the bug Stage 1 shipped for extension
       ;; names and Stage 2 for width.
       (unless (cmark-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       (call-with-native-document
        markdown
        (options->bits o)
        (map extension->native-name (cmark-options-extensions o))
        (lambda (h)
          (convert-document h (make-convert-ctx
                               (cmark-options-max-nodes o)
                               (cmark-options-max-depth o)
                               (cmark-options-source-positions? o))))
        (cmark-options-max-input-bytes o))))))
```

- [ ] **Step 4: Raise the input-size condition as a resource limit**

`validate-markdown-input` in `src/cmark/gfm/private/scope.sls` currently raises
`(make-cmark-invalid-input 'too-large)`. Change that one expression to:

```scheme
               (raise (make-cmark-resource-limit 'too-large max-bytes))
```

This is not a breaking change: `&cmark-resource-limit` derives from
`&cmark-invalid-input`, so the condition still satisfies `cmark-invalid-input?`
with reason `'too-large` and 0.1's regression test passes untouched. What it
adds is the ceiling and membership in the resource-limit class (design spec
6.2).

- [ ] **Step 5: Wire the façade**

In `src/cmark/gfm.sls`, add `(cmark gfm ast)` and `(cmark gfm parse)` to the
import list, and add to the export list:

```scheme
          ;; AST
          markdown->ast
          make-markdown-node markdown-node?
          markdown-node-type markdown-node-properties
          markdown-node-children markdown-node-source
          markdown-node-property
          markdown-node-with-properties markdown-node-with-children
          markdown-node-map markdown-node-fold
          make-source-position source-position?
          source-position-start-line source-position-start-column
          source-position-end-line   source-position-end-column

          ;; new options
          cmark-options-max-nodes cmark-options-max-depth
          default-ast-options

          ;; new condition
          &cmark-resource-limit cmark-resource-limit?
          cmark-resource-limit-value
```

The AST records are re-exported for the same reason the condition types are
(Stage 2 §2.2): `(cmark gfm)` is the supported import, and a caller should not
have to know which file a record lives in.

- [ ] **Step 6: Run it to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-convert.sps
```

Expected: 13 new passes, `# of unexpected failures 0`.

- [ ] **Step 7: Watch the arity default fail**

Change `parse.sls`'s one-argument case to use `(default-cmark-options)`. Run the
suite. Expected: `the one-argument form attaches source positions` FAILS with
`#f`, **and so do the two other assertions that call the one-argument form** —
`positions carry cmark's real line and column spans` and `the empty document
carries cmark's real 1:1-0:0 span`. That collateral is legitimate: all three
read positions produced by the same defaulted call. What matters is that `the
two-argument form honours an explicit source-positions? #t` still passes, which
is what isolates the arity default from the flag's plumbing. Revert.

Then, in `convert.sls`, make `node-source` ignore `convert-ctx-positions?` and
always build a position. Run the suite. Expected: `the two-argument form
honours an explicit source-positions? #f` FAILS. Revert. Record both for
Task 12.

- [ ] **Step 8: Run the full suite and commit**

```bash
make test && make check-purity
git add src/cmark/gfm/parse.sls src/cmark/gfm.sls \
        src/cmark/gfm/private/scope.sls tests/test-convert.sps
git commit -m "feat: add markdown->ast and re-export the AST from the facade"
```

---

# Task 10: The AST→XML serializer and the in-process differential leg

**Files:**
- Create: `tests/test-ast-differential.sps`

**Interfaces:**
- Consumes: `markdown->ast` and the AST accessors from `(cmark gfm)`.
- Produces: nothing in `src/`. The serializer is **test-only code**, and that is the point: it is written against `vendor/cmark-gfm/src/xml.c` and judged byte-for-byte against cmark's real output, so it cannot be adjusted to accommodate a converter bug.

Every formatting rule below was verified against the pinned CLI while this plan
was written. The shapes to reproduce:

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE document SYSTEM "CommonMark.dtd">
<document sourcepos="1:1-4:6" xmlns="http://commonmark.org/xml/1.0">
  <heading sourcepos="1:1-1:4" level="1">
    <text sourcepos="1:3-1:4" xml:space="preserve">hi</text>
  </heading>
</document>
```

- `sourcepos` precedes `xmlns` and every other attribute (`src/xml.c:48` runs before `:55` and the type switch).
- Extension attributes come next (`src/xml.c:55-59`), then type-specific ones.
- A header cell carries `align="left"`; a **body** cell carries no `align` at all (`extensions/table.c:661`).
- A task item's element name is `tasklist`, not `item`, and it always carries `completed="true"` or `"false"`.
- An ordered list emits `type`, `start`, `delim`, then `tight`; `delim` is omitted only when there is none. A bullet list emits `type="bullet"` then `tight`.
- Indentation is two spaces per level, capped at 40 (`MAX_INDENT`, `src/xml.c:14`, applied at `:28-32`).
- A childless non-literal element self-closes as ` />`; literal-bearing types emit ` xml:space="preserve">`, the escaped literal, and the closing tag on the same line.
- Escaping is `houdini_escape_html0` with `secure = 0` (`src/houdini_html_e.c:32-60`): exactly `&`, `<`, `>`, `"`. A `'` and a `/` are emitted literally.

- [ ] **Step 1: Write the suite with the serializer and the in-process leg**

Create `tests/test-ast-differential.sps`:

```scheme
#!r6rs
;;; The AST verified against cmark's own serialization of the same parse.
;;;
;;; cmark_render_xml walks the very tree markdown->ast copies, so re-rendering
;;; our Scheme AST into that dialect and diffing byte-for-byte is a near-total
;;; oracle: a wrong heading level, a dropped child, a mislabelled table header,
;;; a missing fence info, or a bad source position all surface as a byte
;;; difference.
;;;
;;; The load-bearing property is that this serializer CANNOT be tuned to
;;; accommodate a converter bug. It is written against
;;; vendor/cmark-gfm/src/xml.c and judged against cmark's real bytes, so
;;; "adjust the expectation until it passes" is not available -- the
;;; expectation is produced by cmark.
;;;
;;; Three properties are invisible to this oracle and are asserted directly in
;;; tests/test-convert.sps instead: item index, table columns, and alignment on
;;; body cells (design spec 8.3).
(import (rnrs)
        (srfi :64)
        (cmark gfm))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "ast-differential")

;; --- cmark's XML dialect ------------------------------------------------

;; houdini_escape_html0 with secure = 0 (src/houdini_html_e.c:32-60). Exactly
;; four characters; ' and / are deliberately NOT escaped, because that
;; function only escapes them in secure mode and xml.c passes 0.
(define (xml-escape s)
  (let-values (((port get) (open-string-output-port)))
    (string-for-each
     (lambda (c)
       (case c
         ((#\&) (put-string port "&amp;"))
         ((#\<) (put-string port "&lt;"))
         ((#\>) (put-string port "&gt;"))
         ((#\") (put-string port "&quot;"))
         (else  (put-char port c))))
     s)
    (get)))

;; Our node type back to cmark's element name. The two conditionals are where
;; the AST's uniform key sets pay off: a task item and a header row are
;; ordinary nodes carrying a boolean, and the boolean picks the element name.
(define (node->type-string n)
  (case (markdown-node-type n)
    ((document) "document")
    ((paragraph) "paragraph")
    ((blockquote) "block_quote")
    ((thematic-break) "thematic_break")
    ((softbreak) "softbreak")
    ((linebreak) "linebreak")
    ((emph) "emph")
    ((strong) "strong")
    ((strikethrough) "strikethrough")
    ((heading) "heading")
    ((text) "text")
    ((code) "code")
    ((html-inline) "html_inline")
    ((html-block) "html_block")
    ((code-block) "code_block")
    ((link) "link")
    ((image) "image")
    ((list) "list")
    ((item) (if (markdown-node-property n 'task?) "tasklist" "item"))
    ((table) "table")
    ((table-row) (if (markdown-node-property n 'header?)
                     "table_header" "table_row"))
    ((table-cell) "table_cell")
    ((extension) (markdown-node-property n 'native-type))
    (else (error 'node->type-string "unmapped node type"
                 (markdown-node-type n)))))

;; The five types xml.c renders as literal text rather than as a container.
(define (literal-type? ts)
  (and (member ts '("text" "code" "html_block" "html_inline" "code_block")) #t))

(define (sourcepos-attribute n)
  (let ((p (markdown-node-source n)))
    (if p
        (string-append " sourcepos=\""
                       (number->string (source-position-start-line p)) ":"
                       (number->string (source-position-start-column p)) "-"
                       (number->string (source-position-end-line p)) ":"
                       (number->string (source-position-end-column p)) "\"")
        "")))

;; xml.c:55-59: the extension's attribute function runs before the type
;; switch, so these come first. in-header? is threaded down the walk because
;; align is emitted only for a cell whose PARENT row is a header
;; (extensions/table.c:661) and a cell cannot see its parent from our AST.
(define (extension-attributes n ts in-header?)
  (cond
    ((string=? ts "tasklist")
     (if (markdown-node-property n 'checked?)
         " completed=\"true\"" " completed=\"false\""))
    ((and (string=? ts "table_cell") in-header?)
     (let ((a (markdown-node-property n 'alignment)))
       (if (memq a '(left center right))
           (string-append " align=\"" (symbol->string a) "\"")
           "")))
    (else "")))

(define (type-attributes n ts)
  (cond
    ((string=? ts "document") " xmlns=\"http://commonmark.org/xml/1.0\"")
    ((string=? ts "list")
     (string-append
      (if (eq? 'ordered (markdown-node-property n 'kind))
          (string-append
           " type=\"ordered\" start=\""
           (number->string (markdown-node-property n 'start)) "\""
           (case (markdown-node-property n 'delimiter)
             ((paren)  " delim=\"paren\"")
             ((period) " delim=\"period\"")
             (else "")))
          " type=\"bullet\"")
      " tight=\"" (if (markdown-node-property n 'tight?) "true" "false") "\""))
    ((string=? ts "heading")
     (string-append " level=\""
                    (number->string (markdown-node-property n 'level)) "\""))
    ((string=? ts "code_block")
     (let ((info (markdown-node-property n 'fence-info)))
       (if (> (string-length info) 0)
           (string-append " info=\"" (xml-escape info) "\"")
           "")))
    ((or (string=? ts "link") (string=? ts "image"))
     (string-append " destination=\""
                    (xml-escape (markdown-node-property n 'url)) "\""
                    " title=\""
                    (xml-escape (markdown-node-property n 'title)) "\""))
    (else "")))

;; Two spaces per level, capped at MAX_INDENT = 40 (src/xml.c:14, :28-32).
;; Dropping the cap makes every document nested deeper than 20 levels diverge.
(define (emit-indent port depth)
  (let ((n (min (* 2 depth) 40)))
    (let loop ((i 0))
      (unless (= i n) (put-char port #\space) (loop (+ i 1))))))

(define (serialize port n depth in-header?)
  (let* ((ts (node->type-string n))
         (kids (markdown-node-children n)))
    (emit-indent port depth)
    (put-string port "<")
    (put-string port ts)
    (put-string port (sourcepos-attribute n))
    (put-string port (extension-attributes n ts in-header?))
    (put-string port (type-attributes n ts))
    (cond
      ((literal-type? ts)
       (put-string port " xml:space=\"preserve\">")
       (put-string port (xml-escape (markdown-node-property n 'literal)))
       (put-string port "</")
       (put-string port ts)
       (put-string port ">\n"))
      ((pair? kids)
       (put-string port ">\n")
       ;; A row sets the flag for its cells; anything else passes it through.
       (let ((hdr (cond ((string=? ts "table_header") #t)
                        ((string=? ts "table_row") #f)
                        (else in-header?))))
         (for-each (lambda (k) (serialize port k (+ depth 1) hdr)) kids))
       (emit-indent port depth)
       (put-string port "</")
       (put-string port ts)
       (put-string port ">\n"))
      (else (put-string port " />\n")))))

(define (ast->xml tree)
  (let-values (((port get) (open-string-output-port)))
    (put-string port "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    (put-string port "<!DOCTYPE document SYSTEM \"CommonMark.dtd\">\n")
    (serialize port tree 0 #f)
    (get)))

;; --- leg one: in-process, same options on both sides --------------------
;; markdown->xml is cmark's renderer over the same input and the same option
;; record, so the only thing that can differ is our copy of the tree.
(define (divergence markdown o)
  (let ((mine (ast->xml (markdown->ast markdown o)))
        (theirs (markdown->xml markdown o)))
    (if (string=? mine theirs) #f (list mine theirs))))

(define (agrees? markdown o) (not (divergence markdown o)))

(define positions (make-cmark-options 'source-positions? #t))
(define no-positions (make-cmark-options 'source-positions? #f))

;; --- the detector must be able to report a difference at all ------------
;; Without this, every agreement assertion below could be passing because
;; divergence always returns #f. Seeded with a document whose XML differs
;; under two option settings.
(test-equal "the comparison detects a real difference when one exists"
  #t
  (let ((a (ast->xml (markdown->ast "# hi\n" positions)))
        (b (markdown->xml "# hi\n" no-positions)))
    (not (string=? a b))))

;; --- agreement, one construct at a time ---------------------------------
(define (check name markdown)
  (test-equal (string-append "in-process XML agrees: " name)
    #f (divergence markdown no-positions))
  (test-equal (string-append "in-process XML agrees with positions: " name)
    #f (divergence markdown positions)))

(check "an empty document" "")
(check "headings of every level"
       "# a\n\n## b\n\n### c\n\n#### d\n\n##### e\n\n###### f\n")
(check "a setext heading" "title\n=====\n")
(check "paragraphs and soft breaks" "one\ntwo\n\nthree\n")
(check "a hard break" "one\\\ntwo\n")
(check "emphasis and strong" "*a* **b** ***c***\n")
(check "inline code, including a multi-line span" "`a` and `b\nc` end\n")
(check "a fenced code block with info" "```scheme\n(+ 1 2)\n```\n")
(check "a fenced code block without info" "```\nplain\n```\n")
(check "an indented code block" "    indented\n")
(check "a thematic break" "a\n\n---\n\nb\n")
(check "a block quote, including nesting" "> a\n>\n> > b\n")
(check "a bullet list" "- a\n- b\n")
(check "a tight ordered list with an offset start" "3. a\n4. b\n")
(check "a paren-delimited ordered list" "1) a\n2) b\n")
(check "a loose list" "- a\n\n- b\n")
(check "links with and without titles"
       "[a](u) [b](v \"t\") [c](<sp ace> \"q\")\n")
(check "images" "![a](u) ![b](v \"t\")\n")
(check "raw block and inline HTML" "<div>\nx\n</div>\n\na <b>c</b> d\n")
(check "characters the XML escaper must handle" "a & b < c > d \" e ' f / g\n")
(check "a reference link" "[a][ref]\n\n[ref]: u \"t\"\n")

;; The escaping set is the whole point of one of those cases, so it also gets
;; a direct assertion: ' and / must NOT be escaped, because xml.c passes
;; secure = 0.
(test-equal "the escaper handles exactly the four characters cmark escapes"
  "&amp;&lt;&gt;&quot;'/"
  (xml-escape "&<>\"'/"))

;; --- extensions ---------------------------------------------------------
(define with-exts
  (make-cmark-options 'extensions '(autolink strikethrough table tagfilter
                                    tasklist)))
(define with-exts+pos
  (cmark-options-with with-exts 'source-positions? #t))

(define (check-ext name markdown)
  (test-equal (string-append "in-process XML agrees: " name)
    #f (divergence markdown with-exts))
  (test-equal (string-append "in-process XML agrees with positions: " name)
    #f (divergence markdown with-exts+pos)))

(check-ext "strikethrough" "~~a~~\n")
(check-ext "an autolink" "http://e.example/ and www.example.org\n")
(check-ext "a table with every alignment"
           "| a | b | c | d |\n|:--|--:|:-:|---|\n| 1 | 2 | 3 | 4 |\n")
(check-ext "a table with one column" "| a |\n|---|\n| 1 |\n")
(check-ext "a table with inline markup in cells"
           "| *a* | `b` |\n|-----|-----|\n| ~~c~~ | [d](u) |\n")
(check-ext "a task list, checked and unchecked" "- [x] a\n- [ ] b\n")
(check-ext "a task list mixed with plain items" "- [x] a\n- plain\n- [ ] b\n")
(check-ext "tagfilter's suppression is a renderer concern, not an AST one"
           "<title>x</title>\n")

;; --- the indentation cap ------------------------------------------------
;; MAX_INDENT is 40, so indentation stops growing past 20 levels. A serializer
;; without the cap agrees on every fixture above and diverges only here.
(define (nested-quotes n) (string-append (make-string n #\>) " deep\n"))

(test-equal "in-process XML agrees at 25 levels of nesting, past MAX_INDENT"
  #f (divergence (nested-quotes 25) no-positions))
(test-equal "in-process XML agrees at 25 levels with positions"
  #f (divergence (nested-quotes 25) positions))

(test-end "ast-differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it and fix the serializer until it agrees**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --program tests/test-ast-differential.sps
```

Expected on the first run: some `check` cases fail. **Read the divergence the
failure prints** — `divergence` returns both strings, so the SRFI-64 output
shows exactly which bytes differ. Fix the serializer, not the converter, unless
the difference is a genuine converter bug (a wrong property value rather than a
formatting difference). Repeat until every case reports `#f`.

Expected final state: every `check` and `check-ext` case reports `#f`, and
`# of unexpected failures 0`. Do not chase a specific total -- each `check`
emits two assertions (with and without positions), so the number moves
whenever a case is added, and the gate that matters is that no case reports
a divergence.

- [ ] **Step 3: Watch the oracle catch converter bugs**

This is the step that proves the harness is worth having. Four mutations in
`src/cmark/gfm/private/convert.sls`, one at a time:

1. In `heading-props`, return `(cons 'level 1)` unconditionally. Expected: `in-process XML agrees: headings of every level` FAILS, and the printed divergence shows `level="1"` where cmark says `level="2"`.
2. In `task-item-props`, hardcode `(cons 'checked? #f)`. Expected: `in-process XML agrees: a task list, checked and unchecked` FAILS on `completed="false"` versus `completed="true"`.
3. Swap `header-row-props` and `body-row-props`. Expected: the table cases FAIL — both the element name (`table_row` versus `table_header`) and the header cells' `align` attributes move.
4. In `convert-children`, drop the final `reverse`. Expected: every multi-child case FAILS with children in reverse order.

Then one mutation in the **serializer** itself, to prove the cap is load-bearing:

5. In `emit-indent`, remove the `min` so indentation is `(* 2 depth)`. Expected: **only** `in-process XML agrees at 25 levels of nesting, past MAX_INDENT` FAILS; every other case still passes.

Revert each. Record all five for Task 12.

- [ ] **Step 4: Run the full suite and commit**

```bash
make test && make check-purity
git add tests/test-ast-differential.sps
git commit -m "test: verify the AST against cmark's own XML serialization"
```

---

# Task 11: Shared test helpers and the CLI differential leg

**Files:**
- Create: `tests/cmark-testing.sls`
- Modify: `Makefile` (add `tests` to `CHEZ_LIBDIRS`)
- Modify: `tests/test-differential.sps` (migrate onto the shared helpers)
- Modify: `tests/test-ast-differential.sps`

**Interfaces:**
- Consumes: the serializer, `ast->xml`, `divergence`, `positions`, `no-positions`, `with-exts`, `with-exts+pos`, and `nested-quotes` from Task 10.
- Produces: `(cmark-testing)` exporting `file->bytevector`, `string-contains?`, and `capture-command`; plus a second comparison leg against the pinned `cmark-gfm` binary.

**Why a shared library.** Task 10's suite needs the same
`file->bytevector`, `string-contains?`, and subprocess-capture helpers that
`tests/test-differential.sps:29-71` already has. Writing them again is about
40 duplicated lines, and this repo's standing preference is to remove a
duplicated invariant rather than assert it. The three helpers extracted are
generic — read a file, find a substring, run a command and capture its bytes.
`options->flags` is **not** extracted: Stage 2's takes a format argument and
Stage 3's is xml-only, so sharing it would couple two suites that should be
free to diverge.

The single-element library name `(cmark-testing)` keeps the file at
`tests/cmark-testing.sls` with no directory nesting; Chez resolves it against
`CHEZ_LIBDIRS`, which this task extends to include `tests`.

- [ ] **Step 1: Write the shared library**

Create `tests/cmark-testing.sls`:

```scheme
#!r6rs
;;; Helpers shared by the two differential suites.
;;;
;;; Only genuinely generic operations live here: read a file, find a
;;; substring, run a command and capture its bytes. Suite-specific logic --
;;; notably each suite's options-to-CLI-flags mapping -- stays in the suite,
;;; because the two differ (Stage 2's is per-format, Stage 3's is xml-only)
;;; and coupling them would stop either from changing independently.
;;;
;;; This library is test-only and deliberately NOT under src/. It is reachable
;;; because the Makefile puts tests/ on CHEZ_LIBDIRS.
(library (cmark-testing)
  (export file->bytevector string-contains? capture-command)
  (import (rnrs)
          (only (chezscheme) system))

  (define (file->bytevector path)
    (let* ((p (open-file-input-port path))
           (bv (get-bytevector-all p)))
      (close-port p)
      (if (eof-object? bv) (make-bytevector 0) bv)))

  (define (string-contains? hay needle)
    (let ((h (string-length hay)) (n (string-length needle)))
      (let loop ((i 0))
        (cond ((> (+ i n) h) #f)
              ((string=? needle (substring hay i (+ i n))) #t)
              (else (loop (+ i 1)))))))

  ;; Runs cmd with stdout redirected to out-path and stderr discarded, then
  ;; returns the captured bytes. A non-zero exit is an ERROR, not an empty
  ;; result: a silently empty capture would make a byte comparison pass
  ;; against a CLI that never ran.
  (define (capture-command cmd out-path)
    (let ((rc (system (string-append cmd " > " out-path " 2>/dev/null"))))
      (unless (zero? rc)
        (error 'capture-command "command failed" cmd rc))
      (file->bytevector out-path))))
```

- [ ] **Step 2: Put `tests` on the library path and migrate the Stage 2 suite**

In `Makefile`, extend line 72:

```make
CHEZ_LIBDIRS := src:tests:$(SRFI_LIBS)
```

In `tests/test-differential.sps`, add `(cmark-testing)` to the import list,
delete the now-duplicated `file->bytevector` and `string-contains?`
definitions, and rewrite the two places that ran the CLI in terms of
`capture-command`:

```scheme
(define (cli-version-line)
  (utf8->string (capture-command (string-append cli " --version 2>&1")
                                 out-path)))

(define (run-cli flags fixture)
  (capture-command (string-append cli " " flags " " fixture) out-path))
```

Note the `2>&1` stays inside the command string for the version probe, because
`capture-command` discards stderr and `--version` output is worth capturing in
full when the probe fails.

- [ ] **Step 3: Prove the migration changed no behaviour**

```bash
make test
```

Expected: `test-differential` reports the same pass count as before this task
(check `git stash` / re-run if unsure), and `ALL SUITES PASSED`. A refactor that
changes a test count has changed behaviour and must be investigated, not
accepted.

- [ ] **Step 4: Write the failing CLI-leg tests**

Insert into `tests/test-ast-differential.sps`, immediately **before** the final
`(test-end "ast-differential")` line. First extend the import list at the top of
the file:

```scheme
        ;; file-exists? is deliberately absent: (rnrs) already exports it and
        ;; requesting it here too fails the library body with "multiple
        ;; definitions for file-exists?".
        (only (chezscheme) getenv mkdir)
        (cmark-testing)
```

Then:

```scheme
;; --- leg two: the pinned CLI --------------------------------------------
;; The in-process leg compares our serializer against cmark's renderer inside
;; one process. If both were wrong in the same way -- say, our AST and our
;; reading of xml.c drifted together -- that leg would still pass. The CLI is
;; an independent witness.
(define cli (or (getenv "CMARK_CLI") "cmark-gfm"))
(define tmp-dir "tests/tmp")
(define out-path "tests/tmp/ast-diff-out.bin")
(define fixture-path "tests/tmp/ast-diff-in.md")

(unless (file-exists? tmp-dir) (mkdir tmp-dir))

;; A missing or mismatched CLI FAILS this suite. It does not skip it: "skip
;; when unavailable" is how an exit criterion silently stops being enforced.
;; Both supported acquisition paths ship the binary.
(test-equal "the CLI is the same build as the loaded library"
  #t
  (string-contains?
   (utf8->string (capture-command (string-append cli " --version 2>&1") out-path))
   (string-append " " (cmark-gfm-version) " ")))

;; The flags come from the options record, so the two sides cannot describe
;; different configurations by accident. --to xml is fixed: this suite has one
;; format. Not shared with test-differential.sps's version, which is
;; per-format -- see this task's preamble.
(define (options->flags o)
  (string-append
   "--to xml"
   (if (cmark-options-validate-utf8? o)    " --validate-utf8" "")
   (if (cmark-options-source-positions? o) " --sourcepos" "")
   (if (cmark-options-hardbreaks? o)       " --hardbreaks" "")
   (if (cmark-options-nobreaks? o)         " --nobreaks" "")
   (if (cmark-options-smart? o)            " --smart" "")
   (if (cmark-options-unsafe-html? o)      " --unsafe" "")
   (fold-left (lambda (acc e) (string-append acc " -e " (symbol->string e)))
              "" (cmark-options-extensions o))))

(define (write-fixture markdown)
  (let ((p (open-file-output-port fixture-path (file-options no-fail))))
    (put-bytevector p (string->utf8 markdown))
    (close-port p)))

(define (cli-xml markdown o)
  (write-fixture markdown)
  (utf8->string
   (capture-command (string-append cli " " (options->flags o) " " fixture-path)
                    out-path)))

(define (cli-divergence markdown o)
  (let ((mine (ast->xml (markdown->ast markdown o)))
        (theirs (cli-xml markdown o)))
    (if (string=? mine theirs) #f (list mine theirs))))

;; Same guard as the in-process leg: prove the detector can report a
;; difference before trusting it to report none.
(test-equal "the CLI comparison detects a real difference when one exists"
  #t
  (not (string=? (ast->xml (markdown->ast "# hi\n" positions))
                 (cli-xml "# hi\n" no-positions))))

(define (check-cli name markdown o)
  (test-equal (string-append "CLI XML agrees: " name)
    #f (cli-divergence markdown o)))

;; The committed fixtures, which is what makes this leg a corpus test rather
;; than a restatement of the cases above. hostile.md is included because an
;; AST must preserve exactly what it parsed -- raw HTML and dangerous URLs
;; included -- and this is where that is proved rather than asserted.
(define (fixture->string path) (utf8->string (file->bytevector path)))

(for-each
 (lambda (path)
   (for-each
    (lambda (o)
      (check-cli (string-append path " " (if (cmark-options-source-positions? o)
                                             "with positions" "without positions"))
                 (fixture->string path) o))
    (list with-exts with-exts+pos)))
 '("tests/fixtures/core.md"
   "tests/fixtures/gfm.md"
   "tests/fixtures/smart.md"
   "tests/fixtures/hostile.md"))

;; Every construct from the in-process leg, re-verified against the CLI.
(check-cli "a table with every alignment"
           "| a | b | c | d |\n|:--|--:|:-:|---|\n| 1 | 2 | 3 | 4 |\n"
           with-exts+pos)
(check-cli "a task list, checked and unchecked" "- [x] a\n- [ ] b\n" with-exts+pos)
(check-cli "a multi-line inline code span" "`a\nb` end\n" with-exts+pos)
(check-cli "25 levels of nesting, past MAX_INDENT"
           (nested-quotes 25) with-exts+pos)
(check-cli "the XML escaper's four characters"
           "a & b < c > d \" e ' f / g\n" with-exts+pos)

;; smart? changes the text literals cmark produces, so the AST must carry the
;; smart-punctuation forms. Verified against the CLI's own --smart output.
(check-cli "smart punctuation reaches the AST's literals"
           "\"quoted\" -- dashed --- and 'single'\n"
           (cmark-options-with with-exts+pos 'smart? #t))

;; unsafe-html? is a RENDERER policy and must not change the AST at all
;; (design spec 3.5). The XML renderer ignores it, so both settings must
;; produce identical output -- which is what proves the AST preserved the raw
;; HTML rather than suppressing it.
(test-equal "unsafe-html? does not change the AST"
  #t
  (string=? (ast->xml (markdown->ast (fixture->string "tests/fixtures/hostile.md")
                                     with-exts+pos))
            (ast->xml (markdown->ast (fixture->string "tests/fixtures/hostile.md")
                                     (cmark-options-with with-exts+pos
                                                         'unsafe-html? #t)))))
```

- [ ] **Step 5: Run it to verify it fails, then passes**

```bash
make test
```

`make test` is used rather than a bare `chez` invocation because it sets
`CMARK_CLI` to the same build the library loads — a bare run may find a
different `cmark-gfm` on `PATH` and fail the version assertion, which is the
guard working correctly.

Expected: any failure here is a genuine divergence between our serializer and
the CLI. Fix and re-run until every case reports `#f`. Expected final state:
every `check-cli` case reports `#f` and the suite reports
`# of unexpected failures 0`.

- [ ] **Step 6: Confirm the new suite runs under the memory gate**

`MEMORY_TESTS` filters out only `tests/test-differential.sps`, so
`test-ast-differential.sps` is included automatically — and it should be: unlike
the Stage 2 suite, its in-process leg allocates and frees native objects inside
the Chez process, which is exactly what Valgrind needs to see.

```bash
make test-memory
```

On macOS this reports the ASan-only caveat and cannot support a leak claim
(ADR-0003). On Linux, expect a clean Valgrind run. If only macOS is available,
say so when reporting rather than claiming the memory gate passed.

- [ ] **Step 7: Commit**

```bash
git add tests/cmark-testing.sls tests/test-differential.sps \
        tests/test-ast-differential.sps Makefile
git commit -m "test: verify the AST against the pinned CLI, on shared helpers"
```

---

# Task 12: The Stage 3 mutation log

**Files:**
- Create: `.plans/stage-3-mutation-log.md`

**Interfaces:** none. This task produces the evidence that AGENTS.md requires:
every assertion added in Tasks 1–11 has been watched to fail, through the
property it claims to guard.

Read `.plans/stage-2-mutation-log.md` first and follow its format. The rule it
enforces: a mutation that fails for some *other* reason — a syntax error, an
import failure, a side effect of the edit — has proved nothing. Narrow the
mutation until the failure is the one predicted.

**Run every mutation in the table below. Do not transcribe it.** Several rows
were added by reviewers who ran them during earlier tasks, and several
assertions in this stage turned out to be empty precisely because someone
trusted a prediction instead of watching the failure. A log certifying a
mutation nobody re-ran is worse than no log: it is evidence of something that
was true once.

- [ ] **Step 1: Create the log with one entry per mutation already performed**

Create `.plans/stage-3-mutation-log.md`. Each entry records: the file and
mutation, the assertion predicted to fail, the observed failure output, and
confirmation that reverting restored the pass. The mutations performed during
Tasks 1–11 were:

| Task | Mutation | Assertion that must fail |
|---|---|---|
| 3 | `markdown-node-map` made parent-first | map rebuilds children-first, so proc sees mapped children |
| 3 | `markdown-node-fold` made post-order | fold visits pre-order, parent before children |
| 4 | `max-depth` dropped from `validate`'s list | a negative max-depth is rejected; cmark-options-with validates max-depth too |
| 5 | `table-row-is-header`'s entry point misspelled | import-time failure: no entry for … |
| 6 | `list-props` returns `'bullet` unconditionally | an ordered list maps kind, start, delimiter, and tightness |
| 6 | `code-block-props` drops the `fence-info` pair | every core node's key set is exactly what the table declares; a fenced code block carries literal and fence info |
| 6 | `check-depth!` call deleted | one level past the depth limit raises too-deep |
| 6 | `count-node!` call deleted | one node past the node limit raises too-many-nodes |
| 7 | `task-item-props` hardcodes `checked? #f` | checked, unchecked, and plain items are all distinguished |
| 7 | header and body row extractors swapped | header? distinguishes the two rows; header? agrees with cmark's own row accessor |
| 7 | cell alignment index off by one | header cells carry their column's alignment; body cells carry the same alignments |
| 8 | `extension-props` always includes the literal pair | no literal key is invented for a node that has none |
| 8 | `with-node` returns `'()` for a missing entry | the extension node records the native type string verbatim |
| 8 | `"heading"` entry deleted from the table | a heading and a paragraph convert to the exact expected tree |
| 9 | one-argument form uses `default-cmark-options` | the one-argument form attaches source positions — **plus two legitimate collateral**: `positions carry cmark's real line and column spans` and `the empty document carries cmark's real 1:1-0:0 span`, both of which call the one-argument form. `the two-argument form honours an explicit source-positions? #t` must keep passing |
| 9 | `node-source` ignores `positions?` | the two-argument form honours an explicit source-positions? #f |
| 9 | swap `(cmark-options-max-nodes o)` / `(cmark-options-max-depth o)` in `parse.sls` | max-depth from the options record is enforced; max-nodes from the options record is enforced — both fail with the *other* limit's reason |
| 9 | `scope.sls` raises the limit with `(bytevector-length bv)` instead of `max-bytes` | max-input-bytes still raises too-large, now as a resource limit — proves the assertion pins the **ceiling value**, not merely the reason |
| 9 | `parse.sls` passes `(supported-extensions)` instead of `(cmark-options-extensions o)` | an extension the record omits is not attached — and `extensions from the options record are attached` must keep passing, which is what shows the pair is not redundant |
| 9 | move the `cmark-options?` check inside `call-with-native-document`'s callback | a non-options argument is rejected before anything is allocated — **but read the caveat below** |
| 10 | `heading-props` returns level 1 | in-process XML agrees: headings of every level |
| 10 | `task-item-props` hardcodes `checked? #f` | in-process XML agrees: a task list, checked and unchecked |
| 10 | row extractors swapped | in-process XML agrees: a table with every alignment |
| 10 | `convert-children` drops its `reverse` | every multi-child in-process case |
| 10 | `emit-indent` drops the `min` cap | in-process XML agrees at 25 levels of nesting, past MAX_INDENT — **and nothing else** |
| 2 | `ast.sls` given a native import it calls | `make check-purity` |

The last of those needs its result written down honestly rather than ticked off.
Moving the `cmark-options?` check into the callback **does** still fail the
assertion — but not for the reason the assertion's name claims. `options->bits`
runs first and its own accessor raises a raw R6RS `&assertion` on the bad
argument before `call-with-native-document` is ever entered, and `live-counts`
stays at `(0 0 0)` either way. So the assertion proves the argument is
*rejected*; it does not prove rejection happens *before acquisition*. Record
that distinction — the property the name asserts is only partly covered, and the
reason it is hard to cover is that no reachable ordering leaks a resource.

- [ ] **Step 2: Record the properties that no mutation can break**

AGENTS.md is explicit that an assertion no mutation can break is an empty
assertion, and that leaving it silently is the exact failure the rule exists to
prevent. Four properties in Stage 3 are in that category and must be written
down as uncovered, with the reason:

1. **The `_Bool` shim wrapper.** Binding `cmark_gfm_extensions_get_tasklist_item_checked` as `int` instead of routing it through `chez_cmark_tasklist_checked` cannot be shown to fail here: the upper bits of the return register happen to be zero on the platforms available. The justification is the x86-64 SysV ABI contract, not an observed failure.
2. **The unknown-type fallback's end-to-end unreachability.** No document reachable through this library's options produces an unrecognised type string. The branch is covered by direct unit calls with a synthetic type string (Task 8); nothing exercises it through `markdown->ast`.
3. **The zero-start-line guard in `node-source`.** `xml.c:48` guards on `start_line != 0`, and the converter mirrors it — but no node reaches it. Even an empty document is created with `start_line 1` (`make_document`, `src/blocks.c`) and cmark emits `sourcepos="1:1-0:0"`. The guard is kept because it keeps the serializer a straight mapping; it is not tested because it cannot be reached.
4. **`copy-required`'s NULL branch.** Every declared property's accessor is called only on a node type that supports it, so `c-string->string` never returns `#f` there. The raise is a defensive assertion on an unreachable path.

- [ ] **Step 3: Verify the log matches reality**

Re-run one mutation chosen at random from the table and confirm the log's
recorded failure output matches what you observe. A log that has drifted from
the code is worse than no log, because it is evidence of something that is no
longer true.

- [ ] **Step 4: Commit**

```bash
git add .plans/stage-3-mutation-log.md
git commit -m "docs: record the Stage 3 mutation evidence and uncovered properties"
```

---

# Task 13: Release 0.2

**Files:**
- Modify: `Akku.manifest`
- Modify: `CHANGELOG.md`
- Modify: `README.org`
- Modify: `.plans/2026-08-17-stage-3-ast-design.md`
- Create: `.plans/decisions/0009-per-entry-point-source-position-defaults.md`
- Create: `.plans/decisions/0010-xml-as-the-ast-oracle.md`

**Interfaces:** none. Documentation and version metadata only.

- [ ] **Step 1: Write ADR-0009**

Create `.plans/decisions/0009-per-entry-point-source-position-defaults.md`:

```markdown
# ADR-0009: Source-position defaults belong to the entry point, not the record

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.2
- **Related:** [ADR-0008](0008-source-positions-off-for-renderer-releases.md), [Stage 3 design](../2026-08-17-stage-3-ast-design.md) §4

## Context

ADR-0008 defaulted `source-positions?` to `#f` for release 0.1 and required Stage 3
to revisit rather than inherit that choice, predicting the resolution would be
"per-entry-point defaults — positions on for `markdown->ast`, off for the renderers".

ADR-0008 also concluded that in a renderer-only release the flag's only observable
effect is markup. That premise is too weak. `CMARK_OPT_SOURCEPOS` also changes the
positions cmark *records*:

    /* vendor/cmark-gfm/src/inlines.c:292-296 */
    static void adjust_subj_node_newlines(subject *subj, cmark_node *node,
                                          int matchlen, int extra, int options) {
      if (!(options & CMARK_OPT_SOURCEPOS)) {
        return;
      }

Positions are written onto every node unconditionally during parsing, but this
correction — which fixes `end_line`/`end_column` for a span crossing a newline and
advances `subj->line` and `subj->column_offset` for everything parsed afterwards — is
skipped when the flag is off. Its callers are multi-line code spans
(`src/inlines.c:407`) and multi-line raw inline HTML (`:999`, `:1009`).

So positions parsed without the flag are present but wrong, and wrong in a way that
propagates to later inlines in the same block.

## Decision

`markdown->ast` selects its default by **arity**:

```scheme
(markdown->ast markdown)          ; (default-ast-options): source-positions? #t
(markdown->ast markdown options)  ; the caller's record, verbatim
```

`(default-ast-options)` is `(cmark-options-with (make-cmark-options)
'source-positions? #t)` — ordinary data, one field different.

The flag governs the parse bits and the attachment together. When it is off,
`markdown->ast` parses without `SOURCEPOS` **and** every `markdown-node-source` is
`#f`, so an unreliable position can never reach a node.

Rejected alternatives:

- **Flip the shared default to `#t`.** Makes `markdown->html` emit `data-sourcepos`
  on every element at the defaults, which is the behaviour ADR-0008 was written to
  avoid, and is a breaking change for 0.1 callers.
- **A tri-state `'unset` sentinel** in the options record, so a per-entry-point
  default could distinguish "defaulted `#f`" from "explicitly `#f`". Puts a third
  value into a field documented as boolean; every validation path would carry it.
- **Always attach positions on the AST path**, ignoring the option. Never-wrong
  positions and no tri-state, but a caller's explicit `#f` would be silently
  disregarded.

## Consequences

- No 0.1 behaviour changes. ADR-0008's decision stands for the renderers.
- The AST at its own defaults carries positions, which is what makes it worth more
  than one without them.
- `xml.c:48`'s `start_line != 0` guard is mirrored in the converter, so a node cmark
  has no position for reports `#f` rather than `0:0-0:0`. That branch is unreachable
  in practice — even an empty document is created with `start_line 1` — and is
  recorded as an uncovered property in the Stage 3 mutation log.
- Two assertions hold the arity in place: the one-argument form must attach
  positions, and the two-argument form must honour an explicit `#f`. Neither can
  drift silently.
```

- [ ] **Step 2: Write ADR-0010**

Create `.plans/decisions/0010-xml-as-the-ast-oracle.md`:

```markdown
# ADR-0010: Verify the AST against cmark's own XML serialization

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.2
- **Related:** [Stage 3 design](../2026-08-17-stage-3-ast-design.md) §8, [Stage 2 design](../2026-08-16-stage-2-renderers-design.md) §7

## Context

The AST copy touches 24 node types and roughly a dozen properties. Hand-written
expected trees are readable but cover only what someone had the patience to type
out, and the table, list, and position permutations are exactly where that runs
out.

`cmark_render_xml` walks the same tree `markdown->ast` copies, and emits the type
string, source positions, and most properties of every node.

## Decision

A test-only serializer renders our Scheme AST into cmark's XML dialect, and the
result is compared byte-for-byte against cmark's output for the same parse — first
in-process against `cmark_render_xml`, then against the pinned CLI.

The serializer is written against `vendor/cmark-gfm/src/xml.c` and judged against
cmark's real bytes. That is the property that matters: it **cannot be tuned** to
accommodate a converter bug. "Adjust the expectation until it passes" is not
available, because the expectation is produced by cmark.

## Consequences

- A wrong heading level, a dropped or reordered child, a mislabelled table header, a
  missing fence info, or a bad source position all surface as a byte difference.
- Both legs are needed. The in-process leg would still pass if our AST and our
  reading of `xml.c` were wrong in the same way; the CLI is an independent witness.
- Three properties are invisible to the oracle and need direct assertions: `item`
  index, table `columns`, and alignment on **body** cells — `extensions/table.c:661`
  emits `align=` only for cells whose parent row is a header.
- The serializer must reproduce cmark's formatting exactly, including `MAX_INDENT`
  (`src/xml.c:14`), which caps indentation at 40 spaces. A serializer without the cap
  agrees on every shallow fixture and diverges only past 20 levels of nesting, so
  that case is asserted specifically.
- Each comparison leg carries a guard proving the detector can report a difference at
  all, for the same reason Stage 2 §7.3's discrimination guard exists: a parity
  assertion whose comparator always returns "equal" passes against anything.
```

- [ ] **Step 3: Sync the design spec**

Two edits to `.plans/2026-08-17-stage-3-ast-design.md`, both recording what
implementation established:

Add a row to the §2 module-layout table, after the `convert.sls` row:

```markdown
| `src/cmark/gfm/parse.sls` | 3 (public) | **yes** | No |
```

and a sentence after that table:

```markdown
`parse.sls` is the layer-3 entry point for `markdown->ast`. It exists so that
`convert.sls` stays layer 2: a public export inside layer 2 would force
`convert.sls` to import the options record, inverting the layering. It mirrors
`render.sls`, which unpacks the same record into option bits.
```

Then extend §12's gap list — §4.3's guard turned out to be unreachable:

```markdown
8. **The zero-start-line guard is unreachable.** §4.3 mirrors `xml.c:48`'s
   `start_line != 0` test, but no node reaches it: even an empty document is
   created with `start_line 1` (`make_document`, `src/blocks.c`) and cmark emits
   `sourcepos="1:1-0:0"`. The guard is kept because it keeps the Task 10
   serializer a straight mapping from our record to cmark's output.
```

- [ ] **Step 3b: Resync the purity check's own description**

Task 2 extended `check-purity` to gate `tests/test-ast.sps` as well as
`tests/test-options.sps`, but two descriptions of it still say options-only. In
a repo whose rule is "prefer a check to a comment", a comment that understates
what its check protects is the failure mode that rule exists to prevent.

In `Makefile`, the comment block above `check-purity` (around lines 122-124)
opens with "options.sls must import no library that loads a shared object" and
cites "test-options.sps's 36 assertions". Widen it to name both pure libraries
and both suites, without dropping the existing explanation of the poisoned-path
probe or its Chez-instantiation caveat.

In `.github/workflows/ci.yml:74`, the step name is `Check options.sls stays free
of native imports`. Change it to name both:

```yaml
      - name: Check options.sls and ast.sls stay free of native imports
```

- [ ] **Step 4: Bump the version**

In `Akku.manifest`, change the version:

```scheme
(akku-package ("chez-cmark-gfm" "0.2.0")
```

- [ ] **Step 5: Write the CHANGELOG entry**

Insert into `CHANGELOG.md`, immediately after the introductory paragraph and
**before** the `## [0.1.0]` heading:

```markdown
## [0.2.0] — 2026-08-17

The Scheme-owned AST. `markdown->ast` returns immutable records containing no
native pointers, valid after every cmark object has been freed. The SXML
adapter follows in 0.3 (ADR-0007).

### Added

- `markdown->ast`. Two arities: `(markdown->ast md)` uses
  `(default-ast-options)`, which turns source positions on; `(markdown->ast md
  opts)` honours the caller's options record verbatim. See ADR-0009 — one
  shared default cannot serve both the AST and the renderers well.
- `(cmark gfm ast)`, re-exported from `(cmark gfm)`: `make-markdown-node`,
  `markdown-node?`, the four field accessors, `markdown-node-property` with an
  optional default, `markdown-node-with-properties`,
  `markdown-node-with-children`, `markdown-node-map` (children-first),
  `markdown-node-fold` (pre-order), and the `source-position` record.
- 24 node types covering CommonMark and all five GFM extensions. A task item
  and a table header row are distinguished by cmark's own type strings
  (`"tasklist"`, `"table_header"`), which is the only reliable channel for
  either: `cmark_gfm_extensions_get_tasklist_item_checked` returns false both
  for an unchecked task and for a non-task.
- `max-nodes` (default 250000) and `max-depth` (default 1000) options.
  `max-input-bytes` does not bound the AST — 5 MiB of adversarial input parses
  to millions of nodes — so the copy has its own ceilings.
- `&cmark-resource-limit`, carrying the ceiling that was exceeded. It derives
  from `&cmark-invalid-input`, so existing code guarding
  `cmark-invalid-input?` on an oversized document keeps working while new code
  can catch resource exhaustion as a class.
- `default-ast-options`.

### Security

- **The AST is untrusted structured input.** Parsing preserves exactly what the
  document said, including raw HTML literals and `javascript:` URLs. No
  sanitisation happens during conversion and `unsafe-html?` has no effect on
  it — that option is a renderer policy. Sanitise when rendering.
- Node and depth ceilings bound the Scheme-side allocation, and a document
  exceeding either raises before the tree is built rather than exhausting
  memory.

### Notes

- Source positions are only trustworthy with `CMARK_OPT_SOURCEPOS` on:
  `vendor/cmark-gfm/src/inlines.c:292-296` skips a correction when it is off,
  leaving multi-line code spans and raw inline HTML with wrong end positions
  that propagate to later inlines. The AST therefore attaches a position only
  when it parsed with the flag, and reports `#f` otherwise.
- An unrecognised node type is preserved as an `extension` node carrying the
  native type string, never discarded. No such type is reachable through the
  options this library exposes — footnotes require `CMARK_OPT_FOOTNOTES`, which
  is not exposed — so the branch is unit-tested rather than exercised
  end-to-end.
- The AST is verified by re-serializing it into cmark's own XML dialect and
  diffing byte-for-byte against `cmark_render_xml` and the pinned CLI across
  the four fixtures with and without positions. Item index, table column count,
  and body-cell alignment are invisible to that oracle and carry direct
  assertions instead. See ADR-0010.
```

- [ ] **Step 6: Document the AST in the README**

Insert into `README.org`, after the existing `** Options` table and before
`** Errors`:

```org
** The AST

#+begin_src scheme
(import (cmark gfm))

;; One argument: source positions ON (ADR-0009).
(define tree (markdown->ast "# Hello\n\n~~struck~~\n"))

(markdown-node-type tree)                   ;; => document
(markdown-node-property
  (car (markdown-node-children tree)) 'level)  ;; => 1

;; Two arguments: your options record, verbatim.
(markdown->ast "# Hello\n" (make-cmark-options 'source-positions? #f))

;; Immutable. Both helpers return new trees.
(markdown-node-map (lambda (n) n) tree)     ;; children-first
(markdown-node-fold (lambda (n acc) (+ acc 1)) 0 tree)  ;; pre-order
#+end_src

Nodes are ~(type properties children source)~. Properties are read with
~markdown-node-property~, which takes an optional default — several
properties have ~#f~ as a legitimate value, so absence and false are
distinguishable:

| Node type | Properties |
|-----------------+---------------------------------------|
| ~heading~ | ~level~ |
| ~text~ ~code~ ~html-inline~ ~html-block~ | ~literal~ |
| ~code-block~ | ~literal~ ~fence-info~ |
| ~link~ ~image~ | ~url~ ~title~ |
| ~list~ | ~kind~ ~start~ ~tight?~ ~delimiter~ |
| ~item~ | ~index~ ~task?~ ~checked?~ |
| ~table~ | ~columns~ ~alignments~ |
| ~table-row~ | ~header?~ |
| ~table-cell~ | ~alignment~ |
| ~extension~ | ~native-type~, and ~literal~ when the node has one |

~document~, ~paragraph~, ~blockquote~, ~thematic-break~, ~softbreak~,
~linebreak~, ~emph~, ~strong~, and ~strikethrough~ carry no properties.

#+begin_quote
⚠️ *The AST is untrusted structured input.* It preserves exactly what the
document said, including raw HTML and ~javascript:~ URLs. ~unsafe-html?~ does
not affect it — that option is a renderer policy. Sanitise when you render,
not when you parse.
#+end_quote

Two ceilings bound the copy, because ~max-input-bytes~ does not: 5 MiB of
adversarial Markdown parses to millions of nodes.

| Key | Default |
|-------------+---------|
| ~max-nodes~ | 250000 |
| ~max-depth~ | 1000 |

Exceeding either raises ~&cmark-resource-limit~, which derives from
~&cmark-invalid-input~ and carries the ceiling that was exceeded:

#+begin_src scheme
(guard (e ((cmark-resource-limit? e)
           (list (cmark-invalid-input-reason e)
                 (cmark-resource-limit-value e))))
  (markdown->ast deeply-nested (make-cmark-options 'max-depth 64)))
;; => (too-deep 64)
#+end_src
```

Also add `max-nodes` and `max-depth` rows to the existing `** Options` table so
the two lists do not disagree.

- [ ] **Step 7: Verify the documented example actually works**

A README example that does not run is worse than none. Check every snippet:

```bash
cat > /tmp/readme-check.sps <<'EOF'
#!r6rs
(import (rnrs) (cmark gfm))
(define tree (markdown->ast "# Hello\n\n~~struck~~\n"))
(display (markdown-node-type tree)) (newline)
(display (markdown-node-property (car (markdown-node-children tree)) 'level))
(newline)
(display (markdown-node-fold (lambda (n acc) (+ acc 1)) 0 tree)) (newline)
(display (guard (e ((cmark-resource-limit? e)
                    (list (cmark-invalid-input-reason e)
                          (cmark-resource-limit-value e))))
           (markdown->ast (string-append (make-string 100 #\>) " x\n")
                          (make-cmark-options 'max-depth 64))))
(newline)
EOF
CHEZSCHEMELIBDIRS=src chez --program /tmp/readme-check.sps
```

Expected output:

```
document
1
6
(too-deep 64)
```

- [ ] **Step 8: Final verification and commit**

```bash
make clean && make build && make test && make check-purity && make test-memory
```

All four must pass. On macOS, `make test-memory` reports the ASan-only caveat —
that is not a leak claim, and only Linux CI can make one (ADR-0003). Say which
platform the run happened on when reporting.

```bash
git add Akku.manifest CHANGELOG.md README.org \
        .plans/2026-08-17-stage-3-ast-design.md \
        .plans/decisions/0009-per-entry-point-source-position-defaults.md \
        .plans/decisions/0010-xml-as-the-ast-oracle.md
git commit -m "docs: release 0.2 — the Scheme AST, with ADR-0009 and ADR-0010"
```

- [ ] **Step 9: Finish the branch**

Use the `superpowers:finishing-a-development-branch` skill to decide how this
work integrates. Do not merge without asking.

---

## Plan self-review

Run against `.plans/2026-08-17-stage-3-ast-design.md`, section by section.

| Spec section | Implemented by |
|---|---|
| §1 scope, §1.1 M4 remainder | Tasks 1, 6 (ceilings), 11 (hostile corpus) |
| §2 module layout, §2.1 purity gate, §2.2 core/shell split | Tasks 2 (gate), 6, 9 (`parse.sls`) |
| §3.1 records, §3.2 helper semantics | Tasks 2, 3 |
| §3.3 type and property table | Tasks 6, 7 |
| §3.4 uniform key sets | Tasks 6, 7 (key-set assertions) |
| §3.5 AST is untrusted | Task 2 (`ast.sls` header), 11 (`unsafe-html?` no-op assertion), 13 (README, CHANGELOG) |
| §4.1 corrected `SOURCEPOS` premise | Task 13 (ADR-0009) |
| §4.2 per-entry-point defaults | Tasks 4, 9 |
| §4.3 zero start line | Tasks 6, 9 — **and corrected**: the branch is unreachable, recorded in Tasks 12 and 13 |
| §5.1 shape, §5.2 borrowed strings | Task 6 |
| §5.3 tables, §5.4 task items | Task 7 |
| §6.1 the three limits | Tasks 1, 4 |
| §6.2 `&cmark-resource-limit` | Tasks 1, 9 (`scope.sls` raises it) |
| §6.3 enforcement points | Task 6 |
| §7 unknown node types | Task 8 |
| §8.1 the oracle, §8.2 format, §8.3 blind spots | Tasks 10, 11; blind spots asserted in Tasks 6 and 7 |
| §9.1 suites, §9.2 exit gate, §9.3 mutations | Tasks 2, 6, 10, 11, 12, 13 |
| §10 native additions, §10.1 `_Bool`, §10.2 extension library | Task 5 |
| §11 invariants as checks | Tasks 2, 6, 7 |
| §12 deliberate gaps | Task 12, extended in Task 13 |
| §13 release | Task 13 |

**No gaps.** Two corrections the spec needs, both handled in Task 13: the
missing `parse.sls` row in §2's table, and §4.3's guard turning out to be
unreachable rather than merely mirrored.

**Naming consistency across tasks.** `make-convert-ctx` (3 arguments) and
`convert-document` (2) are used identically in Tasks 6–9. `convert-node` takes
`(ptr type-string depth ctx)` in Tasks 6, 8, and 9. `node-entry` has four
fields — `type-string`, `type`, `keys`, `extractor` — so the accessors used are
`node-entry-type-string`, `node-entry-type`, `node-entry-keys`,
`node-entry-extractor`. `alignment-bytes` takes `(addr count)` in Tasks 5 and 7.
`divergence` and `ast->xml` are defined in Task 10 and reused in Task 11.
