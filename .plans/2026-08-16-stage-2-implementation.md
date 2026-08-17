# chez-cmark-gfm Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Stage 1 native-lifecycle foundation into a usable library — immutable options, four direct renderers, and a CLI differential harness — and ship it as release 0.1.

**Architecture:** A pure functional core (`options.sls`) that imports no native library at all, over an imperative shell that adds one new native resource to the Stage 1 scope: the renderer buffer. Public renderers run inside `call-with-native-document`, so ADR-0005's parser-outlives-render rule is enforced by the liveness flag that already has tests rather than by a new guard. Correctness is proved by diffing every option against the pinned `cmark-gfm` CLI, with a per-cell guard that the CLI's own output changed.

**Tech Stack:** Chez Scheme 10.4.1, C99, cmark-gfm 0.29.0.gfm.13, SRFI-64 (vendored chez-srfi), Make, Valgrind (Linux) / AddressSanitizer (macOS).

**Source documents:**
- Design spec: `.plans/2026-08-16-stage-2-renderers-design.md`
- Stage 1 plan: `.plans/2026-08-16-stages-0-1-implementation.md`
- Project plan: `.plans/chez-cmark-gfm-sxml-project-plan.md` §6, §9, §15
- ADRs: `.plans/decisions/0005`, `0006`, `0007`

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Chez Scheme** 10.4.1 or later. The binary is `chez` (**not** `scheme`); `petite` cannot compile and must not be used for tests.
- **cmark-gfm** pinned to `0.29.0.gfm.13`; supported range `0.29.0.gfm.x`.
- **Numeric cmark constants never appear in Scheme.** The shim reads them from installed headers.
- **cmark's string names never appear in the public API.** Extensions are symbols; the mapping to native names is an explicit alist in `options.sls`.
- **Only layer 2** (`cmark gfm private *`) may hold a native pointer.
- **`options.sls` imports no native library**, not even transitively. Breaking this silently destroys the property that its suite cannot pass by accident.
- **Teardown order is fixed** (ADR-0005): renderer buffer → root → parser last.
- **Every `tests/test-*.sps` must end with its own `(exit …)`.** SRFI-64 sets no process exit status; a suite missing that line reports success through real failures. Anything after it is dead code.
- **`file-exists?` import conflict:** `(rnrs)` already exports it. A test importing `(only (chezscheme) …)` must NOT also request `file-exists?`, or the library body fails with "multiple definitions for file-exists?".
- **`foreign-procedure` resolves its entry point when the expression is evaluated**, not at first call. New bindings in `native.sls` must go after the `load-shim` definitions.
- **A test is not finished when it passes. It is finished when you have watched it fail.** Every new assertion gets a mutation that breaks it *through the asserted property*, recorded in the Stage 2 mutation log (Task 10).
- **Prefer comparing against an expected value over `test-assert`.** `0` is truthy in Scheme and `guard` returns its body's value when nothing raises.
- **Commits:** Conventional Commits. Run `make test` before every commit.

---

## File Structure

| Path | Responsibility | Status |
|---|---|---|
| `src/cmark/gfm/private/limits.sls` | `default-max-input-bytes` — pure, shared by `options.sls` and `scope.sls` | Create (Task 2) |
| `src/cmark/gfm/private/conditions.sls` | Add `&cmark-invalid-option`, `&cmark-render-failed` | Modify (Task 1) |
| `src/cmark/gfm/private/native.sls` | Add three renderer bindings + version-string; widen exports | Modify (Task 4) |
| `src/cmark/gfm/private/scope.sls` | Add `call-with-render-buffer`; import `limits` | Modify (Tasks 2, 5) |
| `src/cmark/gfm/options.sls` | Immutable options record, plist constructor, validation | Create (Tasks 2–3) |
| `src/cmark/gfm/render.sls` | The four `markdown->*` procedures | Create (Task 6) |
| `src/cmark/gfm.sls` | Façade: re-exports + version/capability inspection | Create (Task 7) |
| `tests/test-conditions.sps` | Extend for the two new conditions | Modify (Task 1) |
| `tests/test-options.sps` | Pure options suite — loads no shared object | Create (Tasks 2–3) |
| `tests/test-native.sps` | Extend for version-string and option-bit distinctness | Modify (Task 4) |
| `tests/test-render.sps` | Buffer lifecycle, the four renderers, width, safe defaults | Create (Tasks 5–7) |
| `tests/fixtures/*.md` | Four differential fixtures | Create (Task 8) |
| `tests/test-differential.sps` | OFAT + discrimination, then cartesian sweep | Create (Tasks 8–9) |
| `Makefile` | `CMARK_CLI`, `MEMORY_TESTS` | Modify (Tasks 8–9) |
| `.plans/stage-2-mutation-log.md` | Evidence that each decision has a test that fails | Create (Task 10) |
| `Akku.manifest`, `CHANGELOG.md`, `README.org`, `.plans/decisions/0008-*.md` | Release 0.1 | Modify/Create (Task 11) |

---

# Task 1: Conditions for invalid options and renderer failure

**Files:**
- Modify: `src/cmark/gfm/private/conditions.sls`
- Test: `tests/test-conditions.sps`

**Interfaces:**
- Produces: `&cmark-invalid-option` / `make-cmark-invalid-option` (2 args: `key`, `reason`) / `cmark-invalid-option?` / `cmark-invalid-option-key` / `cmark-invalid-option-reason`; `&cmark-render-failed` / `make-cmark-render-failed` (1 arg: `format`) / `cmark-render-failed?` / `cmark-render-failed-format`. Both derive from `&cmark-error`.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-conditions.sps`, immediately **before** the final `(test-end "conditions")` line:

```scheme
;; --- Stage 2: invalid option ------------------------------------------
;; key is #f for whole-plist problems (odd length), a symbol otherwise.
(test-equal "invalid-option carries the offending key"
  'smart?
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-equal "invalid-option carries the reason"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-equal "invalid-option accepts #f as the key for whole-plist problems"
  #f
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (raise (make-cmark-invalid-option #f 'malformed-plist))))

(test-assert "invalid-option is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-assert "invalid-option is distinguishable from invalid-input"
  (guard (e ((cmark-invalid-input? e) #f)
            ((cmark-invalid-option? e) #t)
            (#t #f))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

;; --- Stage 2: renderer failure ----------------------------------------
(test-equal "render-failed names the format that failed"
  'commonmark
  (guard (e ((cmark-render-failed? e) (cmark-render-failed-format e)))
    (raise (make-cmark-render-failed 'commonmark))))

(test-assert "render-failed is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-render-failed 'html))))
```

Then add the new names to the import in that file — it currently imports the whole `(cmark gfm private conditions)` library, so **no import change is needed**. Verify by reading line 4 of the file: it must already be `(cmark gfm private conditions))` with no `only`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
make test 2>&1 | tail -20
```

Expected: the `test-conditions` suite fails to load with an unbound-identifier error naming `make-cmark-invalid-option`. Exit status non-zero.

- [ ] **Step 3: Add the condition types**

In `src/cmark/gfm/private/conditions.sls`, add to the `export` list (after the `&cmark-shim-unavailable` group):

```scheme
          &cmark-invalid-option make-cmark-invalid-option
          cmark-invalid-option? cmark-invalid-option-key
          cmark-invalid-option-reason

          &cmark-render-failed make-cmark-render-failed
          cmark-render-failed? cmark-render-failed-format
```

And append these definitions before the library's closing paren:

```scheme
  ;; Raised by the options layer before any native resource exists. key is a
  ;; field name, or #f when the problem is the argument list as a whole
  ;; (odd length). reason is a symbol: 'malformed-plist, 'unknown-key,
  ;; 'duplicate-key, 'invalid-value, 'unknown-extension, 'contradictory,
  ;; 'invalid-width.
  (define-condition-type &cmark-invalid-option &cmark-error
    make-cmark-invalid-option cmark-invalid-option?
    (key    cmark-invalid-option-key)
    (reason cmark-invalid-option-reason))

  ;; Raised when a cmark renderer returns NULL. format is a symbol:
  ;; 'html, 'xml, 'commonmark, 'plaintext.
  (define-condition-type &cmark-render-failed &cmark-error
    make-cmark-render-failed cmark-render-failed?
    (format cmark-render-failed-format))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/cmark/gfm/private/conditions.sls tests/test-conditions.sps
git commit -m "feat: conditions for invalid options and renderer failure"
```

---

# Task 2: Options record, defaults, and the plist constructor

**Files:**
- Create: `src/cmark/gfm/private/limits.sls`
- Create: `src/cmark/gfm/options.sls`
- Create: `tests/test-options.sps`
- Modify: `src/cmark/gfm/private/scope.sls`

**Interfaces:**
- Consumes: `&cmark-invalid-option` from Task 1.
- Produces: `(default-cmark-options)` → record; `(make-cmark-options . plist)` → record; predicate `cmark-options?`; accessors `cmark-options-extensions`, `cmark-options-validate-utf8?`, `cmark-options-source-positions?`, `cmark-options-hardbreaks?`, `cmark-options-nobreaks?`, `cmark-options-smart?`, `cmark-options-unsafe-html?`, `cmark-options-max-input-bytes`. `default-max-input-bytes` moves to `(cmark gfm private limits)`.

**Why `limits.sls` exists:** `options.sls` needs the 5 MiB default, and `scope.sls` already defines it. Importing it from `scope.sls` would drag `(cmark gfm private native)` in transitively and load the shared object during the pure options suite. Duplicating the constant would let the two drift. One definition in a pure library removes the invariant instead of asserting it.

- [ ] **Step 1: Write the failing test**

Create `tests/test-options.sps`:

```scheme
#!r6rs
;; PURE SUITE. This file must never import a library that loads a shared
;; object. That is what makes every assertion below unable to pass by
;; accident because of native behaviour. If you add an import here, check
;; its transitive imports first.
(import (rnrs)
        (srfi :64)
        (cmark gfm options)
        (cmark gfm private conditions))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "options")

;; --- defaults ---------------------------------------------------------
;; Compared field by field against expected VALUES, not asserted truthy:
;; every boolean default here is #f, and #f is the one Scheme value that
;; test-assert would catch -- but 'extensions and 'max-input-bytes are not
;; booleans, so a uniform value comparison is the only form that
;; discriminates all eight.
(test-equal "default extensions are the five standard GFM extensions"
  '(autolink strikethrough table tagfilter tasklist)
  (cmark-options-extensions (default-cmark-options)))

(test-equal "validate-utf8? defaults to #t"
  #t (cmark-options-validate-utf8? (default-cmark-options)))

;; ADR-0008: OFF for renderer-only releases. Flipping this default to #t
;; makes markdown->html emit data-sourcepos on every element.
(test-equal "source-positions? defaults to #f"
  #f (cmark-options-source-positions? (default-cmark-options)))

(test-equal "hardbreaks? defaults to #f"
  #f (cmark-options-hardbreaks? (default-cmark-options)))

(test-equal "nobreaks? defaults to #f"
  #f (cmark-options-nobreaks? (default-cmark-options)))

(test-equal "smart? defaults to #f"
  #f (cmark-options-smart? (default-cmark-options)))

(test-equal "unsafe-html? defaults to #f"
  #f (cmark-options-unsafe-html? (default-cmark-options)))

(test-equal "max-input-bytes defaults to 5 MiB"
  5242880 (cmark-options-max-input-bytes (default-cmark-options)))

;; --- plist construction ------------------------------------------------
(test-equal "a supplied key overrides its default"
  #t (cmark-options-smart? (make-cmark-options 'smart? #t)))

(test-equal "an unsupplied key keeps its default"
  #f (cmark-options-unsafe-html? (make-cmark-options 'smart? #t)))

(test-equal "two keys can be supplied at once"
  '(#t #t)
  (let ((o (make-cmark-options 'smart? #t 'unsafe-html? #t)))
    (list (cmark-options-smart? o) (cmark-options-unsafe-html? o))))

(test-equal "an empty plist yields the defaults"
  #f (cmark-options-smart? (make-cmark-options)))

;; --- plist rejection ---------------------------------------------------
;; Each guard returns a distinct sentinel in all three outcomes -- expected
;; condition, wrong condition, nothing raised -- and is compared against the
;; expected value. A bare test-assert here would pass on a no-raise
;; fall-through, which is the trap this repo has already shipped.
(test-equal "an odd-length plist is rejected"
  'malformed-plist
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart?)
    'no-condition))

(test-equal "an odd-length plist reports no key"
  #f
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (make-cmark-options 'smart?)))

(test-equal "an unknown key is rejected"
  'unknown-key
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'unsaef-html? #t)
    'no-condition))

(test-equal "an unknown key is named in the condition"
  'unsaef-html?
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (make-cmark-options 'unsaef-html? #t)))

(test-equal "a duplicate key is rejected rather than last-wins"
  'duplicate-key
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart? #t 'smart? #f)
    'no-condition))

(test-equal "a non-boolean value for a boolean key is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart? 'yes)
    'no-condition))

;; 0 is truthy in Scheme, so this is the value most likely to slip past a
;; sloppy check.
(test-equal "0 is rejected as a boolean value"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart? 0)
    'no-condition))

(test-equal "a non-positive max-input-bytes is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'max-input-bytes 0)
    'no-condition))

(test-equal "an inexact max-input-bytes is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'max-input-bytes 1024.0)
    'no-condition))

(test-equal "a positive exact max-input-bytes is accepted"
  1024 (cmark-options-max-input-bytes (make-cmark-options 'max-input-bytes 1024)))

(test-end "options")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | tail -20
```

Expected: failure loading `tests/test-options.sps` — `(cmark gfm options)` does not exist. Exit non-zero.

- [ ] **Step 3: Create the shared limits library**

Create `src/cmark/gfm/private/limits.sls`:

```scheme
#!r6rs
;;; Pure resource limits, shared between the public options layer and the
;;; private native scope.
;;;
;;; This library exists so the constant has exactly ONE definition. options.sls
;;; must not import scope.sls (which would load the shared object and destroy
;;; the property that the options suite runs with no native code), and
;;; duplicating the value in both would let the two drift silently. Removing
;;; the invariant beats asserting it.
(library (cmark gfm private limits)
  (export default-max-input-bytes)
  (import (rnrs))

  ;; design spec 5.5: the only pre-allocation defence. 5 MiB comfortably
  ;; covers real Markdown while still bounding the UTF-8 bytevector that
  ;; validate-markdown-input allocates.
  (define default-max-input-bytes (* 5 1024 1024)))
```

- [ ] **Step 4: Point `scope.sls` at the shared definition**

In `src/cmark/gfm/private/scope.sls`, add `(cmark gfm private limits)` to the import list:

```scheme
  (import (rnrs)
          (cmark gfm private native)
          (cmark gfm private limits)
          (cmark gfm private conditions))
```

Then **delete** the local definition and its comment (the block beginning `;; design spec 5.5: max-input-bytes is the only pre-allocation defence` and ending `(define default-max-input-bytes (* 5 1024 1024))`). Leave `default-max-input-bytes` in `scope.sls`'s `export` list — it now re-exports the shared one, so `tests/test-lifecycle.sps` keeps working unchanged.

- [ ] **Step 5: Create the options library**

Create `src/cmark/gfm/options.sls`:

```scheme
#!r6rs
;;; Immutable parser options -- the functional core.
;;;
;;; This library imports NO native library, not even transitively. That is
;;; deliberate: it means tests/test-options.sps runs with no shared object
;;; loaded, so no assertion in it can pass by accident because of native
;;; behaviour. Check the transitive imports before adding one.
;;;
;;; Options describe PARSING. Wrap width is a renderer argument and lives in
;;; (cmark gfm render), because in cmark's own factoring option bits go to
;;; both the parser and the renderer while width goes only to some renderers.
(library (cmark gfm options)
  (export make-cmark-options default-cmark-options cmark-options-with
          cmark-options?
          cmark-options-extensions
          cmark-options-validate-utf8?
          cmark-options-source-positions?
          cmark-options-hardbreaks?
          cmark-options-nobreaks?
          cmark-options-smart?
          cmark-options-unsafe-html?
          cmark-options-max-input-bytes
          supported-extensions
          extension->native-name)
  (import (rnrs)
          (cmark gfm private limits)
          (cmark gfm private conditions))

  ;; The public spelling of an extension is a SYMBOL; cmark's own spelling is
  ;; a string. They coincide today for all five, and this alist is what stops
  ;; that coincidence from becoming an invariant held by luck. Task 7 asserts
  ;; every native name here resolves through cmark_find_syntax_extension.
  (define extension-names
    '((autolink      . "autolink")
      (strikethrough . "strikethrough")
      (table         . "table")
      (tagfilter     . "tagfilter")
      (tasklist      . "tasklist")))

  (define (supported-extensions) (map car extension-names))

  (define (extension->native-name sym)
    (let ((hit (assq sym extension-names)))
      (if hit
          (cdr hit)
          (raise (make-cmark-invalid-option 'extensions 'unknown-extension)))))

  (define default-extensions '(autolink strikethrough table tagfilter tasklist))

  (define-record-type (cmark-options %make-cmark-options cmark-options?)
    (fields extensions
            validate-utf8?
            source-positions?
            hardbreaks?
            nobreaks?
            smart?
            unsafe-html?
            max-input-bytes))

  (define option-keys
    '(extensions validate-utf8? source-positions? hardbreaks?
      nobreaks? smart? unsafe-html? max-input-bytes))

  ;; Walks the plist, rejecting structural problems before any value is read.
  ;; A duplicate key is an error rather than last-wins: silently honouring one
  ;; of two conflicting instructions is the failure mode this library exists
  ;; to prevent.
  (define (plist->alist plist)
    (let loop ((p plist) (seen '()) (acc '()))
      (cond
        ((null? p) (reverse acc))
        ((null? (cdr p))
         (raise (make-cmark-invalid-option #f 'malformed-plist)))
        (else
         (let ((k (car p)) (v (cadr p)))
           (unless (memq k option-keys)
             (raise (make-cmark-invalid-option k 'unknown-key)))
           (when (memq k seen)
             (raise (make-cmark-invalid-option k 'duplicate-key)))
           (loop (cddr p) (cons k seen) (cons (cons k v) acc)))))))

  (define (lookup alist key default)
    (let ((hit (assq key alist)))
      (if hit (cdr hit) default)))

  (define (check-boolean key v)
    (unless (boolean? v)
      (raise (make-cmark-invalid-option key 'invalid-value))))

  ;; Runs on the RESULTING record, so both constructors share one policy and
  ;; cmark-options-with cannot slip past a check the base object passed.
  ;; Returns the record so it can be used in tail position.
  (define (validate o)
    (check-boolean 'validate-utf8?    (cmark-options-validate-utf8? o))
    (check-boolean 'source-positions? (cmark-options-source-positions? o))
    (check-boolean 'hardbreaks?       (cmark-options-hardbreaks? o))
    (check-boolean 'nobreaks?         (cmark-options-nobreaks? o))
    (check-boolean 'smart?            (cmark-options-smart? o))
    (check-boolean 'unsafe-html?      (cmark-options-unsafe-html? o))
    (let ((n (cmark-options-max-input-bytes o)))
      (unless (and (integer? n) (exact? n) (positive? n))
        (raise (make-cmark-invalid-option 'max-input-bytes 'invalid-value))))
    (let ((xs (cmark-options-extensions o)))
      (unless (list? xs)
        (raise (make-cmark-invalid-option 'extensions 'invalid-value)))
      (for-each
       (lambda (x)
         (unless (symbol? x)
           (raise (make-cmark-invalid-option 'extensions 'invalid-value)))
         (unless (assq x extension-names)
           (raise (make-cmark-invalid-option 'extensions 'unknown-extension))))
       xs))
    o)

  (define (build a
                 d-extensions d-validate-utf8? d-source-positions?
                 d-hardbreaks? d-nobreaks? d-smart? d-unsafe-html?
                 d-max-input-bytes)
    (validate
     (%make-cmark-options
      (lookup a 'extensions        d-extensions)
      (lookup a 'validate-utf8?    d-validate-utf8?)
      (lookup a 'source-positions? d-source-positions?)
      (lookup a 'hardbreaks?       d-hardbreaks?)
      (lookup a 'nobreaks?         d-nobreaks?)
      (lookup a 'smart?            d-smart?)
      (lookup a 'unsafe-html?      d-unsafe-html?)
      (lookup a 'max-input-bytes   d-max-input-bytes))))

  ;; ADR-0008: source-positions? is #f, diverging from project plan 6.2.
  ;; 0.1 has no AST, so the flag's only observable effect is data-sourcepos
  ;; attributes in HTML and sourcepos in XML.
  (define (default-cmark-options)
    (%make-cmark-options default-extensions #t #f #f #f #f #f
                         default-max-input-bytes))

  (define (make-cmark-options . plist)
    (build (plist->alist plist)
           default-extensions #t #f #f #f #f #f default-max-input-bytes)))
```

Note the library closes after `make-cmark-options`; `cmark-options-with` arrives in Task 3, and `validate`'s contradictory-pair rule arrives with it.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0. Four suites now run.

- [ ] **Step 7: Prove the pure suite really is pure**

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs CHEZ_CMARK_GFM_SHIM=/nonexistent \
  chez --program tests/test-options.sps 2>&1 | tail -3
```

Expected: the suite still passes. `CHEZ_CMARK_GFM_SHIM` pointing at a missing file makes `native.sls` raise `&cmark-shim-unavailable` at import time, so a pass here proves no native library was loaded. If this fails, an import chain reaches `native.sls` — find it before continuing.

- [ ] **Step 8: Commit**

```bash
git add src/cmark/gfm/private/limits.sls src/cmark/gfm/private/scope.sls \
        src/cmark/gfm/options.sls tests/test-options.sps
git commit -m "feat: immutable options record with plist constructor and validation"
```

---

# Task 3: Functional update and the contradictory-pair rule

**Files:**
- Modify: `src/cmark/gfm/options.sls`
- Test: `tests/test-options.sps`

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: `(cmark-options-with opts . plist)` → record.

**Premise correction, recorded in the design spec §3.4:** project plan §6.2 calls `hardbreaks?` + `nobreaks?` contradictory. Read from `vendor/cmark-gfm/src/html.c:319-325`, it is not — `CMARK_OPT_HARDBREAKS` is tested first and `CMARK_OPT_NOBREAKS` is its `else if`, so hardbreaks wins and `--hardbreaks --nobreaks` is byte-identical to `--hardbreaks` alone. Rejecting the pair is a policy choice: silently discarding one of two explicit caller requests is the quiet no-op this project refuses elsewhere.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-options.sps`, immediately **before** `(test-end "options")`:

```scheme
;; --- functional update -------------------------------------------------
(test-equal "cmark-options-with overrides the named field"
  #t (cmark-options-smart? (cmark-options-with (default-cmark-options) 'smart? #t)))

(test-equal "cmark-options-with leaves other fields alone"
  #f (cmark-options-unsafe-html?
      (cmark-options-with (default-cmark-options) 'smart? #t)))

(test-equal "cmark-options-with preserves a non-default field it did not touch"
  1024
  (cmark-options-max-input-bytes
   (cmark-options-with (make-cmark-options 'max-input-bytes 1024) 'smart? #t)))

(test-equal "cmark-options-with does not mutate its argument"
  #f
  (let ((base (default-cmark-options)))
    (cmark-options-with base 'smart? #t)
    (cmark-options-smart? base)))

(test-equal "cmark-options-with rejects an unknown key"
  'unknown-key
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (cmark-options-with (default-cmark-options) 'nope #t)
    'no-condition))

(test-equal "cmark-options-with rejects a non-options first argument"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (cmark-options-with 'not-an-options-record 'smart? #t)
    'no-condition))

;; --- extensions --------------------------------------------------------
(test-equal "supported-extensions lists the five standard GFM extensions"
  '(autolink strikethrough table tagfilter tasklist)
  (supported-extensions))

(test-equal "extension->native-name maps a symbol to cmark's own spelling"
  "strikethrough" (extension->native-name 'strikethrough))

(test-equal "an unknown extension symbol is rejected at construction"
  'unknown-extension
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'extensions '(table footnotes))
    'no-condition))

(test-equal "a string extension name is rejected -- the public API takes symbols"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'extensions '("table"))
    'no-condition))

(test-equal "an empty extension list is accepted"
  '() (cmark-options-extensions (make-cmark-options 'extensions '())))

;; --- the contradictory pair --------------------------------------------
;; Verified in vendor/cmark-gfm/src/html.c:319-325: these are NOT undefined
;; together -- HARDBREAKS is tested first and NOBREAKS is its else-if, so
;; hardbreaks wins. Rejecting the pair is policy: honouring one of two
;; explicit requests and silently dropping the other is the failure this
;; library refuses.
(test-equal "hardbreaks? and nobreaks? together are rejected"
  'contradictory
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'hardbreaks? #t 'nobreaks? #t)
    'no-condition))

(test-equal "either of the pair alone is accepted"
  '(#t #t)
  (list (cmark-options-hardbreaks? (make-cmark-options 'hardbreaks? #t))
        (cmark-options-nobreaks?   (make-cmark-options 'nobreaks? #t))))

;; The rule must survive functional update, which is the whole reason
;; validate runs on the RESULTING record rather than on the plist.
(test-equal "cmark-options-with cannot reach the contradictory pair either"
  'contradictory
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (cmark-options-with (make-cmark-options 'nobreaks? #t) 'hardbreaks? #t)
    'no-condition))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
make test 2>&1 | tail -20
```

Expected: unbound identifier `cmark-options-with`.

- [ ] **Step 3: Add the contradictory rule to `validate`**

In `src/cmark/gfm/options.sls`, inside `validate`, immediately before the final `o`:

```scheme
    ;; Not a defence against undefined behaviour: html.c:319-325 gives
    ;; hardbreaks precedence over nobreaks, so cmark is well-defined here.
    ;; This is policy -- a caller who set both made a mistake, and silently
    ;; discarding one of their two explicit requests would hide it.
    (when (and (cmark-options-hardbreaks? o) (cmark-options-nobreaks? o))
      (raise (make-cmark-invalid-option 'hardbreaks? 'contradictory)))
```

- [ ] **Step 4: Add `cmark-options-with`**

Append to `src/cmark/gfm/options.sls`, after `make-cmark-options`:

```scheme
  (define (cmark-options-with o . plist)
    (unless (cmark-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    (build (plist->alist plist)
           (cmark-options-extensions o)
           (cmark-options-validate-utf8? o)
           (cmark-options-source-positions? o)
           (cmark-options-hardbreaks? o)
           (cmark-options-nobreaks? o)
           (cmark-options-smart? o)
           (cmark-options-unsafe-html? o)
           (cmark-options-max-input-bytes o))
```

Move the library's closing `)` to after this definition.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0.

- [ ] **Step 6: Watch the contradictory test fail**

```bash
cp src/cmark/gfm/options.sls /tmp/options.sls.bak
# delete the `when ... contradictory` block added in Step 3
$EDITOR src/cmark/gfm/options.sls
make test 2>&1 | grep -c 'contradictory'
cp /tmp/options.sls.bak src/cmark/gfm/options.sls && rm /tmp/options.sls.bak
make test 2>&1 | tail -3
```

Expected: with the block removed, `make test` fails and names *both* "hardbreaks? and nobreaks? together are rejected" and "cmark-options-with cannot reach the contradictory pair either". After restoring, `ALL SUITES PASSED`. Record the observed output for Task 10 (mutation E).

- [ ] **Step 7: Commit**

```bash
git add src/cmark/gfm/options.sls tests/test-options.sps
git commit -m "feat: functional options update and the hardbreaks/nobreaks rejection"
```

---

# Task 4: Native bindings for the remaining renderers and the version string

**Files:**
- Modify: `src/cmark/gfm/private/native.sls`
- Test: `tests/test-native.sps`

**Interfaces:**
- Produces, from `(cmark gfm private native)`: `(render-xml root bits)` → uptr; `(render-commonmark root bits width)` → uptr; `(render-plaintext root bits width)` → uptr; `(runtime-version-string)` → Scheme string; `(shim-compiled-version)` → int; `(shim-runtime-version)` → int. `render-html` and `free-buffer` already exist.

Signatures confirmed in `vendor/cmark-gfm/src/cmark-gfm.h:620-669` and `:791`.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-native.sps`, immediately **before** its `(test-end …)` line:

```scheme
;; --- Stage 2: version string ------------------------------------------
;; Not asserted against a hardcoded "0.29.0.gfm.13", which would only pin the
;; fixture. Decoded from the packed runtime integer using the four-byte
;; layout the Stage 0 spike established (major<<24 | minor<<16 | patch<<8 |
;; gfm), so a binding that returned the wrong string, an empty string, or a
;; stale pointer fails here.
(define (decode-version v)
  (string-append
   (number->string (bitwise-arithmetic-shift-right v 24)) "."
   (number->string (bitwise-and (bitwise-arithmetic-shift-right v 16) #xff)) "."
   (number->string (bitwise-and (bitwise-arithmetic-shift-right v 8) #xff)) ".gfm."
   (number->string (bitwise-and v #xff))))

(test-equal "runtime-version-string agrees with the packed runtime version"
  (decode-version (shim-runtime-version))
  (runtime-version-string))

(test-assert "the compiled and runtime versions are both in the supported range"
  (and (version-supported? (shim-compiled-version))
       (version-supported? (shim-runtime-version))))

;; --- Stage 2: option bits are six DISTINCT bits ------------------------
;; This is the only coverage validate-utf8? can have: the public API takes a
;; Scheme string and string->utf8 always emits valid UTF-8, so
;; CMARK_OPT_VALIDATE_UTF8 has no observable effect on any reachable input
;; and no differential cell can discriminate it (design spec 10.1). Testing
;; the BIT is honest; testing the behaviour would be an assertion that
;; passes either way.
(define (all-distinct? xs)
  (cond ((null? xs) #t)
        ((memv (car xs) (cdr xs)) #f)
        (else (all-distinct? (cdr xs)))))

(test-assert "each of the six option flags sets a distinct bit"
  (all-distinct?
   (list (option-bits #t #f #f #f #f #f)
         (option-bits #f #t #f #f #f #f)
         (option-bits #f #f #t #f #f #f)
         (option-bits #f #f #f #t #f #f)
         (option-bits #f #f #f #f #t #f)
         (option-bits #f #f #f #f #f #t))))

(test-assert "validate-utf8? is wired to a real bit even though its behaviour is unreachable"
  (not (= (option-bits #t #f #f #f #f #f)
          (option-bits #f #f #f #f #f #f))))

(test-equal "all flags off is the default mask, and differs from all flags on"
  #f
  (= (option-bits #f #f #f #f #f #f)
     (option-bits #t #t #t #f #t #t)))
```

Then widen that file's import of `(cmark gfm private native)` if it uses `only` — check line 1-10 and add `runtime-version-string`, `shim-compiled-version`, `shim-runtime-version`, `version-supported?`, `option-bits` to the list if so.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
make test 2>&1 | tail -20
```

Expected: unbound identifier `runtime-version-string`.

- [ ] **Step 3: Add the bindings**

In `src/cmark/gfm/private/native.sls`, add to the `export` list:

```scheme
          runtime-version-string shim-compiled-version shim-runtime-version
          render-xml render-commonmark render-plaintext
```

In the `;; --- cmark bindings ---` section, after the existing `render-html` definition — placement matters, `foreign-procedure` resolves its entry point when evaluated, so these must stay after the `load-shim` definitions:

```scheme
  (define render-xml
    (foreign-procedure "cmark_render_xml" (uptr int) uptr))
  (define render-commonmark
    (foreign-procedure "cmark_render_commonmark" (uptr int int) uptr))
  (define render-plaintext
    (foreign-procedure "cmark_render_plaintext" (uptr int int) uptr))
  ;; Returns a static const char* owned by cmark. Borrowed like every other
  ;; accessor here, so it is declared uptr and copied immediately.
  (define raw-version-string
    (foreign-procedure "cmark_version_string" () uptr))
```

And after `option-bits`:

```scheme
  (define (runtime-version-string) (c-string->string (raw-version-string)))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/cmark/gfm/private/native.sls tests/test-native.sps
git commit -m "feat: bind the remaining cmark renderers and the runtime version string"
```

---

# Task 5: The renderer buffer scope

**Files:**
- Modify: `src/cmark/gfm/private/scope.sls`
- Create: `tests/test-render.sps`

**Interfaces:**
- Consumes: `&cmark-render-failed` (Task 1); `render-html`, `free-buffer`, `count-buffer-new!`, `count-buffer-free!`, `c-string->string`, `live-counts` (Task 4 and Stage 1).
- Produces: `(call-with-render-buffer format make-buffer)` → Scheme string, exported from `(cmark gfm private scope)`. `format` is a symbol used only in the failure condition; `make-buffer` is a thunk returning a `uptr`.

**Why this lives in `scope.sls`:** that file's header declares it the sole owner of native teardown, and that claim is load-bearing. Splitting the renderer buffer into a second library would falsify it.

- [ ] **Step 1: Write the failing test**

Create `tests/test-render.sps`:

```scheme
#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) collect)   ; NOT exit: (rnrs) exports it
        (cmark gfm private native)
        (cmark gfm private conditions)
        (cmark gfm private scope))

(define runner (test-runner-simple))
(test-runner-current runner)

(ensure-native-loaded!)

(test-begin "render")

;; Assigned by the counter-movement test below, which has to observe the
;; buffer counter from INSIDE the render extent -- once the scope exits the
;; buffer is already freed and the count is back to baseline.
(define during-count 0)

;; R6RS has no string-contains?; several assertions below check for a
;; substring of rendered output.
(define (string-contains? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

(define opts (option-bits #t #f #f #f #f #f))
(define gfm-extensions '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

(define (render-html-of markdown)
  (call-with-native-document markdown opts gfm-extensions
    (lambda (h)
      (call-with-render-buffer 'html
        (lambda () (render-html (doc-root h) (doc-option-bits h) (doc-extensions h)))))))

;; --- the buffer produces a real, Scheme-owned string -------------------
(test-equal "a heading renders to HTML"
  "<h1>hi</h1>\n"
  (render-html-of "# hi\n"))

;; A copy, not an alias. If call-with-render-buffer returned something
;; backed by the native buffer, this value would be garbage after the free
;; in its after-thunk and after a GC pass.
(test-equal "the rendered string survives the buffer free and a collection"
  "<p>keep me</p>\n"
  (let ((s (render-html-of "keep me\n")))
    (collect)
    s))

;; --- counter balance and MOVEMENT --------------------------------------
;; live-buffers is the third element of live-counts. Built without
;; -DCHEZ_CMARK_DEBUG_COUNTERS the shim hardcodes 0, so every balance test
;; below would compare 0 to 0 and pass against a shim that counts nothing.
;; This assertion is what makes them mean something: it demands the buffer
;; counter actually MOVE while a buffer is alive.
(test-assert "live-buffers moves while a render buffer is alive"
  (let ((before (live-counts)))
    (call-with-native-document "# hi\n" opts gfm-extensions
      (lambda (h)
        (call-with-render-buffer 'html
          (lambda ()
            (let ((buf (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))
              (set! during-count (caddr (live-counts)))
              buf)))))
    (> during-count (caddr before))))

(test-assert "counters balance after a successful render"
  (let ((before (live-counts)))
    (render-html-of "# hi\n")
    (equal? before (live-counts))))

(test-assert "counters balance after the render scope's body raises"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "# hi\n" opts gfm-extensions
        (lambda (h)
          (call-with-render-buffer 'html
            (lambda ()
              (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))
          (error 'test "deliberate failure after rendering"))))
    (equal? before (live-counts))))

(test-assert "200 renders leave the counters balanced"
  (let ((before (live-counts)))
    (let loop ((n 0))
      (when (< n 200)
        (render-html-of "# hi\n\n| a |\n|---|\n| 1 |\n")
        (loop (+ n 1))))
    (collect)
    (equal? before (live-counts))))

;; --- failure path -------------------------------------------------------
;; A NULL buffer must become a structured condition naming the format, not a
;; crash and not a #f masquerading as a rendered document.
(test-equal "a NULL buffer raises render-failed naming the format"
  'commonmark
  (guard (e ((cmark-render-failed? e) (cmark-render-failed-format e))
            (#t 'wrong-condition))
    (call-with-render-buffer 'commonmark (lambda () 0))
    'no-condition))

(test-assert "counters balance after a NULL buffer is rejected"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-render-buffer 'html (lambda () 0)))
    (equal? before (live-counts))))

;; --- ADR-0005 / ADR-0006 -----------------------------------------------
;; Rendering reads root, bits, and extensions through the CHECKED accessors,
;; so a handle whose scope has exited refuses before any renderer runs. This
;; is what makes parser-outlives-render structural rather than documented.
(test-equal "rendering from an escaped handle raises dead-document"
  'dead-document-raised
  (let ((escaped #f))
    (call-with-native-document "# hi\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (guard (e ((cmark-dead-document? e) 'dead-document-raised)
              (#t 'wrong-condition))
      (call-with-render-buffer 'html
        (lambda () (render-html (doc-root escaped)
                                (doc-option-bits escaped)
                                (doc-extensions escaped))))
      'no-condition)))

(test-end "render")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
make test 2>&1 | tail -20
```

Expected: unbound identifier `call-with-render-buffer`.

- [ ] **Step 3: Implement the buffer scope**

In `src/cmark/gfm/private/scope.sls`, add `call-with-render-buffer` to the `export` list, and append this definition before the library's closing paren:

```scheme
  ;; --- renderer buffer ---------------------------------------------------
  ;; cmark documents renderer results as caller-owned, allocated by cmark's
  ;; own allocator. chez_cmark_free_buffer releases them with that same
  ;; allocator; libc free() must never be used on one.
  ;;
  ;; Two properties here are structural, not documented:
  ;;
  ;;   1. The buffer address never reaches caller-supplied code. make-buffer
  ;;      only invokes a foreign procedure, and the body is a single
  ;;      c-string->string with no user code in it -- so no continuation can
  ;;      be captured inside this extent. That is why ADR-0006's liveness
  ;;      flag is not needed here, and why a caller cannot arrange for it to
  ;;      be needed.
  ;;   2. buf is zeroed immediately after being freed, exactly as release!
  ;;      does, so the after-thunk is idempotent by construction rather than
  ;;      by argument.
  (define (call-with-render-buffer format make-buffer)
    (let ((buf (make-buffer)))
      (when (zero? buf)
        (raise (make-cmark-render-failed format)))
      (count-buffer-new!)
      (dynamic-wind
        (lambda () #f)
        (lambda () (c-string->string buf))
        (lambda ()
          (unless (zero? buf)
            (free-buffer buf)
            (count-buffer-free!)
            (set! buf 0))))))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0. Five suites now run.

- [ ] **Step 5: Run under memory diagnostics**

```bash
make test-memory 2>&1 | tail -20
```

Expected on macOS: no AddressSanitizer report. On Linux: Valgrind reports no definite leaks and exits 0. A `heap-use-after-free` here means the copy is happening after the free — check the order inside `dynamic-wind`.

- [ ] **Step 6: Watch the counter test fail**

```bash
cp src/cmark/gfm/private/scope.sls /tmp/scope.sls.bak
# delete the (count-buffer-free!) line from call-with-render-buffer
$EDITOR src/cmark/gfm/private/scope.sls
make test 2>&1 | tail -20
cp /tmp/scope.sls.bak src/cmark/gfm/private/scope.sls && rm /tmp/scope.sls.bak
make test 2>&1 | tail -3
```

Expected: with the decrement gone, "counters balance after a successful render", "counters balance after the render scope's body raises", and "200 renders leave the counters balanced" all fail by name. After restoring, `ALL SUITES PASSED`. Record for Task 10 (mutation D).

- [ ] **Step 7: Commit**

```bash
git add src/cmark/gfm/private/scope.sls tests/test-render.sps
git commit -m "feat: renderer buffer scope with copy-then-free and balanced counters"
```

---

# Task 6: The four public renderers

**Files:**
- Create: `src/cmark/gfm/render.sls`
- Test: `tests/test-render.sps`

**Interfaces:**
- Consumes: `(cmark gfm options)` accessors and `extension->native-name` (Tasks 2–3); `call-with-native-document`, `call-with-render-buffer`, `doc-root`, `doc-option-bits`, `doc-extensions` (Task 5 and Stage 1); `option-bits`, `render-html`, `render-xml`, `render-commonmark`, `render-plaintext` (Task 4).
- Produces, from `(cmark gfm render)`: `(markdown->html markdown options)`; `(markdown->xml markdown options)`; `(markdown->commonmark markdown options [width])`; `(markdown->plaintext markdown options [width])`. All return Scheme strings.

- [ ] **Step 1: Write the failing tests**

Add `(cmark gfm options)` and `(cmark gfm render)` to the import list of `tests/test-render.sps` — it already defines `string-contains?`, which several of these use — then insert before `(test-end "render")`:

```scheme
;; --- the four renderers -------------------------------------------------
(define plain (make-cmark-options 'extensions '()))

(test-equal "markdown->html renders a heading"
  "<h1>hi</h1>\n" (markdown->html "# hi\n" plain))

(test-equal "markdown->commonmark round-trips a heading"
  "# hi\n" (markdown->commonmark "# hi\n" plain))

(test-equal "markdown->plaintext strips the markup"
  "hi\n" (markdown->plaintext "# hi\n" plain))

(test-assert "markdown->xml emits an XML document"
  (let ((s (markdown->xml "# hi\n" plain)))
    (and (string? s) (> (string-length s) 0))))

;; The extension list reaches the HTML renderer. Without it, a table parses
;; but its extension nodes render as nothing -- so this discriminates the
;; one argument only markdown->html passes.
(test-assert "tables render through markdown->html, which requires the extension list"
  (let ((s (markdown->html "| a |\n|---|\n| 1 |\n" (default-cmark-options))))
    (and (string-contains? s "<table>") (string-contains? s "<td>1</td>"))))

(test-assert "strikethrough renders through markdown->html"
  (string-contains? (markdown->html "~~gone~~\n" (default-cmark-options)) "<del>"))

;; --- width --------------------------------------------------------------
(test-assert "a width argument actually wraps commonmark output"
  (let ((wide   (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain))
        (narrow (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain 10)))
    (not (string=? wide narrow))))

(test-equal "width defaults to 0 (nowrap), matching the CLI"
  (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain 0)
  (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain))

(test-equal "a negative width is rejected"
  'invalid-width
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->commonmark "hi\n" plain -1)
    'no-condition))

(test-equal "an inexact width is rejected"
  'invalid-width
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->plaintext "hi\n" plain 72.0)
    'no-condition))

;; Width is validated BEFORE any native resource is acquired, so a bad width
;; leaves nothing to clean up. Stage 1 shipped the opposite bug for
;; extension names and this is the same class.
(test-assert "counters balance after a bad width is rejected"
  (let ((before (live-counts)))
    (guard (e (#t #t)) (markdown->commonmark "hi\n" plain -1))
    (equal? before (live-counts))))

;; --- options plumbing ---------------------------------------------------
(test-assert "source-positions? #t reaches the HTML renderer"
  (string-contains? (markdown->html "# hi\n" (make-cmark-options 'source-positions? #t
                                                                'extensions '()))
                    "data-sourcepos"))

(test-assert "the default options do NOT emit data-sourcepos (ADR-0008)"
  (not (string-contains? (markdown->html "# hi\n" (default-cmark-options))
                         "data-sourcepos")))

;; --- safe by default (Stage 4 owns hardening; this is the 0.1 regression) --
(test-assert "raw HTML is suppressed by default"
  (string-contains? (markdown->html "<script>alert(1)</script>\n" (default-cmark-options))
                    "<!-- raw HTML omitted -->"))

(test-assert "unsafe-html? #t is required to emit raw HTML"
  (string-contains? (markdown->html "<script>alert(1)</script>\n"
                                    (make-cmark-options 'unsafe-html? #t))
                    "<script>"))

;; --- input validation flows from the options record ---------------------
(test-equal "max-input-bytes from the options record is enforced"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e))
            (#t 'wrong-condition))
    (markdown->html "this is eleven" (make-cmark-options 'max-input-bytes 4))
    'no-condition))

(test-equal "embedded NUL is rejected through the public API"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e))
            (#t 'wrong-condition))
    (markdown->html "a\x0;b" (default-cmark-options))
    'no-condition))

(test-equal "a non-options second argument is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->html "hi\n" 'not-options)
    'no-condition))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
make test 2>&1 | tail -20
```

Expected: `(cmark gfm render)` cannot be found.

- [ ] **Step 3: Create the render library**

Create `src/cmark/gfm/render.sls`:

```scheme
#!r6rs
;;; Direct native renderers.
;;;
;;; Every renderer runs INSIDE call-with-native-document's body, reading the
;;; root, option bits, and extension list through scope.sls's checked
;;; accessors. That is what enforces ADR-0005 -- the parser must outlive the
;;; render call, because cmark_parser_free releases the same syntax-extension
;;; list cmark_render_html walks. No new guard is needed: a dead handle
;;; raises before any renderer is reached.
;;;
;;; Width is an argument here rather than a field of the options record.
;;; markdown->html and markdown->xml are fixed at arity 2, so passing a width
;;; to them is an arity error at the call site instead of a silently ignored
;;; field. That mirrors cmark's own factoring: option bits go to both parser
;;; and renderer, width goes only to some renderers.
(library (cmark gfm render)
  (export markdown->html markdown->commonmark markdown->plaintext markdown->xml)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm private conditions)
          (cmark gfm private native)
          (cmark gfm private scope))

  (define (options->bits o)
    (option-bits (cmark-options-validate-utf8? o)
                 (cmark-options-source-positions? o)
                 (cmark-options-hardbreaks? o)
                 (cmark-options-nobreaks? o)
                 (cmark-options-smart? o)
                 (cmark-options-unsafe-html? o)))

  (define (options->native-names o)
    (map extension->native-name (cmark-options-extensions o)))

  ;; Validated before anything native is acquired, so a bad width leaves no
  ;; resource to clean up. Stage 1 shipped exactly this bug for extension
  ;; names; see tests/test-lifecycle.sps's I1 group.
  (define (check-width w)
    (unless (and (integer? w) (exact? w) (>= w 0))
      (raise (make-cmark-invalid-option 'width 'invalid-width)))
    w)

  (define (check-options o)
    (unless (cmark-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    o)

  ;; make-buffer-for receives the live handle and returns a thunk. Keeping it
  ;; a thunk means the buffer address is produced inside
  ;; call-with-render-buffer and never rests in a variable here.
  (define (render markdown o format make-buffer-for)
    (check-options o)
    (call-with-native-document
     markdown (options->bits o) (options->native-names o)
     (lambda (h) (call-with-render-buffer format (make-buffer-for h)))
     (cmark-options-max-input-bytes o)))

  (define (markdown->html markdown o)
    (render markdown o 'html
            (lambda (h)
              (lambda ()
                (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))))

  (define (markdown->xml markdown o)
    (render markdown o 'xml
            (lambda (h)
              (lambda ()
                (render-xml (doc-root h) (doc-option-bits h))))))

  (define markdown->commonmark
    (case-lambda
      ((markdown o) (markdown->commonmark markdown o 0))
      ((markdown o width)
       (let ((w (check-width width)))
         (render markdown o 'commonmark
                 (lambda (h)
                   (lambda ()
                     (render-commonmark (doc-root h) (doc-option-bits h) w))))))))

  (define markdown->plaintext
    (case-lambda
      ((markdown o) (markdown->plaintext markdown o 0))
      ((markdown o width)
       (let ((w (check-width width)))
         (render markdown o 'plaintext
                 (lambda (h)
                   (lambda ()
                     (render-plaintext (doc-root h) (doc-option-bits h) w)))))))))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0.

If "raw HTML is suppressed by default" fails, read the actual output before changing the assertion — cmark's placeholder text is `<!-- raw HTML omitted -->` in this version, confirmed by:

```bash
printf '<script>alert(1)</script>\n' | build/vendor/src/cmark-gfm
```

- [ ] **Step 5: Run under memory diagnostics**

```bash
make test-memory 2>&1 | tail -20
```

Expected: clean, as in Task 5 Step 5.

- [ ] **Step 6: Watch the extension-list test fail**

```bash
cp src/cmark/gfm/render.sls /tmp/render.sls.bak
# in markdown->html, replace (doc-extensions h) with 0
$EDITOR src/cmark/gfm/render.sls
make test 2>&1 | tail -20
cp /tmp/render.sls.bak src/cmark/gfm/render.sls && rm /tmp/render.sls.bak
make test 2>&1 | tail -3
```

Expected: "tables render through markdown->html, which requires the extension list" fails by name. After restoring, `ALL SUITES PASSED`. Record for Task 10 (mutation B).

- [ ] **Step 7: Commit**

```bash
git add src/cmark/gfm/render.sls tests/test-render.sps
git commit -m "feat: markdown->html, ->commonmark, ->plaintext, and ->xml"
```

---

# Task 7: The public façade and capability inspection

**Files:**
- Create: `src/cmark/gfm.sls`
- Test: `tests/test-render.sps`

**Interfaces:**
- Produces, from `(cmark gfm)`: everything `(cmark gfm options)` and `(cmark gfm render)` export, plus `(cmark-gfm-version)` → string, `(cmark-gfm-version-compatible?)` → boolean, `(cmark-gfm-available-extensions)` → list of symbols, plus every condition predicate and accessor.

`cmark-gfm-available-extensions` **probes** rather than enumerates: `cmark_list_syntax_extensions` returns a `cmark_llist*` needing Scheme-side traversal and its own free, while probing `cmark_find_syntax_extension` adds no allocation to own and reports what is actually usable.

- [ ] **Step 1: Write the failing tests**

Switch `tests/test-render.sps` to import the façade, so the suite exercises the API the way a consumer would. Replace its import form with exactly this — `(cmark gfm)` re-exports the options, the renderers, and every condition, so `(cmark gfm options)`, `(cmark gfm render)`, and `(cmark gfm private conditions)` all drop out; the two private imports that remain are the ones the façade deliberately does not expose:

```scheme
(import (rnrs)
        (srfi :64)
        (only (chezscheme) collect)   ; NOT exit: (rnrs) exports it
        (cmark gfm)
        (cmark gfm private native)    ; option-bits, live-counts, render-html,
                                      ; runtime-version-string
        (cmark gfm private scope))    ; call-with-native-document, doc-*,
                                      ; call-with-render-buffer
```

Then insert before `(test-end "render")`:

```scheme
;; --- capability inspection ---------------------------------------------
(test-equal "cmark-gfm-version reports the loaded library's version string"
  (runtime-version-string) (cmark-gfm-version))

(test-assert "cmark-gfm-version-compatible? is true for the pinned build"
  (eq? #t (cmark-gfm-version-compatible?)))

;; Compared against the expected LIST, not asserted truthy: a probe that
;; returned '() or dropped one extension would still be truthy-ish under a
;; weaker assertion.
(test-equal "all five standard extensions are available in the loaded library"
  '(autolink strikethrough table tagfilter tasklist)
  (cmark-gfm-available-extensions))

;; This is what stops options.sls's symbol->string mapping from being an
;; invariant held by luck. If a native name in that alist were misspelled,
;; find-extension would return NULL for it and it would drop out of this list.
(test-equal "every supported extension symbol maps to a name cmark resolves"
  (supported-extensions)
  (cmark-gfm-available-extensions))

;; --- the façade really re-exports --------------------------------------
(test-equal "the façade exposes the renderers"
  "<h1>hi</h1>\n" (markdown->html "# hi\n" (make-cmark-options 'extensions '())))

(test-assert "the façade exposes the condition predicates"
  (guard (e ((cmark-invalid-option? e) #t) (#t #f))
    (make-cmark-options 'nope #t)))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
make test 2>&1 | tail -20
```

Expected: `(cmark gfm)` cannot be found.

- [ ] **Step 3: Create the façade**

Create `src/cmark/gfm.sls`:

```scheme
#!r6rs
;;; The convenient public API. Consumers import this.
;;;
;;; Conditions are re-exported here on purpose. conditions.sls lives under
;;; private/ as an implementation location, but project plan 12 defines the
;;; condition types as part of the public contract -- a caller cannot handle
;;; failures it has no names for.
(library (cmark gfm)
  (export ;; options
          make-cmark-options default-cmark-options cmark-options-with
          cmark-options?
          cmark-options-extensions
          cmark-options-validate-utf8?
          cmark-options-source-positions?
          cmark-options-hardbreaks?
          cmark-options-nobreaks?
          cmark-options-smart?
          cmark-options-unsafe-html?
          cmark-options-max-input-bytes
          supported-extensions

          ;; renderers
          markdown->html markdown->commonmark markdown->plaintext markdown->xml

          ;; version and capability
          cmark-gfm-version cmark-gfm-version-compatible?
          cmark-gfm-available-extensions

          ;; conditions
          &cmark-error cmark-error?
          &cmark-version-incompatible cmark-version-incompatible?
          cmark-version-incompatible-compiled cmark-version-incompatible-runtime
          &cmark-dead-document cmark-dead-document?
          &cmark-extension-unavailable cmark-extension-unavailable?
          cmark-extension-unavailable-name
          &cmark-invalid-input cmark-invalid-input? cmark-invalid-input-reason
          &cmark-shim-unavailable cmark-shim-unavailable? cmark-shim-unavailable-path
          &cmark-invalid-option cmark-invalid-option?
          cmark-invalid-option-key cmark-invalid-option-reason
          &cmark-render-failed cmark-render-failed? cmark-render-failed-format)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm render)
          (cmark gfm private conditions)
          (cmark gfm private native))

  (define (cmark-gfm-version)
    (ensure-native-loaded!)
    (runtime-version-string))

  (define (cmark-gfm-version-compatible?)
    (version-compatible? (shim-compiled-version) (shim-runtime-version)))

  ;; Probes rather than enumerates. cmark_list_syntax_extensions would hand
  ;; back a cmark_llist* to traverse and free; find-extension returns a
  ;; registry-owned pointer we must NOT free, so this costs no ownership.
  ;; ensure-native-loaded! must run first -- it is what registers them.
  (define (cmark-gfm-available-extensions)
    (ensure-native-loaded!)
    (filter (lambda (sym)
              (not (zero? (find-extension (extension->native-name sym)))))
            (supported-extensions))))
```

Note `extension->native-name` is imported from `(cmark gfm options)` but deliberately **not** re-exported: it is a boundary detail, not part of the public contract.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0.

- [ ] **Step 5: Watch the extension-mapping test fail**

```bash
cp src/cmark/gfm/options.sls /tmp/options.sls.bak
# in extension-names, change "tagfilter" to "tagfiltr"
$EDITOR src/cmark/gfm/options.sls
make test 2>&1 | tail -20
cp /tmp/options.sls.bak src/cmark/gfm/options.sls && rm /tmp/options.sls.bak
make test 2>&1 | tail -3
```

Expected: "all five standard extensions are available in the loaded library" and "every supported extension symbol maps to a name cmark resolves" both fail by name. After restoring, `ALL SUITES PASSED`. Record for Task 10 (mutation H).

- [ ] **Step 6: Commit**

```bash
git add src/cmark/gfm.sls tests/test-render.sps
git commit -m "feat: public façade with version and capability inspection"
```

---

# Task 8: Fixtures and the OFAT differential layer

**Files:**
- Create: `tests/fixtures/core.md`, `tests/fixtures/gfm.md`, `tests/fixtures/smart.md`, `tests/fixtures/hostile.md`
- Create: `tests/test-differential.sps`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `(cmark gfm)` (Task 7).
- Produces: helpers used again in Task 9 — `(run-cli flags fixture)` → bytevector; `(config->flags cfg format)` → string; `(config->options cfg)` → record; `(ours format markdown o)` → bytevector; `(mismatch fixture format our-cfg cli-cfg)` → `#f` or a list describing the divergence.

**A config is a plist** accepted verbatim by `make-cmark-options`, so one value drives both sides of every comparison.

- [ ] **Step 1: Create the fixtures**

`tests/fixtures/core.md`:

```markdown
# Heading one

## Heading two

A paragraph with *emphasis*, **strong**, and `inline code`.
A second line, joined by a soft break.
A third line ending in two spaces  
which is a hard break.

> A block quote
> spanning two lines.

- tight one
- tight two

- loose one

- loose two

1. first
2. second

7. starts at seven

[a link](https://example.com "with a title")

![an image](https://example.com/i.png "image title")

```scheme
(define (f x) x)
```

---
```

`tests/fixtures/gfm.md`:

```markdown
| Left | Center | Right |
|:-----|:------:|------:|
| a    | b      | c     |
| 1    | 2      | 3     |

~~struck through~~

Visit https://example.com for more.

- [x] done
- [ ] pending

<script>alert("tagfilter target")</script>
```

`tests/fixtures/smart.md`:

```markdown
He said "hello" and 'goodbye' -- then paused... and left -- again.

A range: 1--10. An em dash: yes---really.
```

`tests/fixtures/hostile.md`:

```markdown
<script>alert(1)</script>

[click](javascript:alert(1))

[click](JaVaScRiPt:alert(1))

[file](file:///etc/passwd)

![image](data:text/html,<script>alert(1)</script>)

<img src=x onerror=alert(1)>
```

- [ ] **Step 2: Add `CMARK_CLI` to the Makefile**

The CLI must come from the same acquisition path as the library the shim links against; diffing two different builds would pass or fail for irrelevant reasons.

In the `ifeq ($(HAVE_PKG),yes)` branch, after `CMARK_DLLS`, add:

```makefile
  CMARK_CLI    := cmark-gfm
```

In the `else` branch, after its `CMARK_DLLS`, add:

```makefile
  CMARK_CLI    := $(abspath $(VENDOR_BUILD)/src/cmark-gfm)
```

Add it to the `deps-info` recipe:

```makefile
	@echo "cmark-gfm CLI    : $(CMARK_CLI)"
```

And pass it to the suites — in the `test:` recipe, change the inner command to:

```makefile
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) CMARK_CLI=$(CMARK_CLI) $(CHEZ) --program $$t || fail=1; \
```

- [ ] **Step 3: Write the failing test**

Create `tests/test-differential.sps`:

```scheme
#!r6rs
;;; Differential tests against the pinned cmark-gfm CLI.
;;;
;;; What these prove (design spec 7.5): that our option-bit construction and
;;; extension attachment do not alter native semantics. They are NOT a retest
;;; of cmark's parser.
;;;
;;; The load-bearing part is the DISCRIMINATION GUARD in layer 1. A parity
;;; assertion only means something if the flag actually changes output for
;;; that fixture: if --smart produces identical bytes for a document with no
;;; quotes or dashes, the parity check passes whether or not smart? is wired
;;; to CMARK_OPT_SMART at all. So every option first has to prove the CLI's
;;; OWN output moved.
(import (rnrs)
        (srfi :64)
        ;; file-exists? is deliberately absent: (rnrs) already exports it and
        ;; requesting it here too fails the library body with "multiple
        ;; definitions for file-exists?".
        (only (chezscheme) system getenv mkdir)
        (cmark gfm))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "differential")

(define cli (or (getenv "CMARK_CLI") "cmark-gfm"))
(define tmp-dir "tests/tmp")
(define out-path "tests/tmp/diff-out.bin")

(unless (file-exists? tmp-dir) (mkdir tmp-dir))

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

;; --- the CLI must be the same build as the loaded library ---------------
;; A missing or mismatched CLI FAILS this suite. It does not skip it:
;; "skip when unavailable" is how an exit criterion silently stops being
;; enforced. Both supported acquisition paths ship the binary.
(define (cli-version-line)
  (let ((rc (system (string-append cli " --version > " out-path " 2>&1"))))
    (unless (zero? rc)
      (error 'cli-version-line
             "cmark-gfm CLI is not runnable -- set CMARK_CLI or run via make test"
             cli rc))
    (utf8->string (file->bytevector out-path))))

(test-assert "the CLI is runnable and is the same build as the loaded library"
  (string-contains? (cli-version-line)
                    (string-append " " (cmark-gfm-version) " ")))

;; --- running one side of a comparison -----------------------------------
(define (run-cli flags fixture)
  (let* ((cmd (string-append cli " " flags " " fixture " > " out-path " 2>/dev/null"))
         (rc  (system cmd)))
    (unless (zero? rc) (error 'run-cli "CLI invocation failed" cmd rc))
    (file->bytevector out-path)))

(define (config->options cfg) (apply make-cmark-options cfg))

;; Our options record drives the CLI flags too, so the two sides cannot
;; describe different configurations by accident. The CLI does not set
;; CMARK_OPT_VALIDATE_UTF8 by default (vendor/cmark-gfm/src/main.c:185) while
;; our defaults can, so --validate-utf8 is emitted from the record, not
;; assumed.
(define (config->flags cfg format)
  (let ((o (config->options cfg)))
    (string-append
     "--to " (symbol->string format)
     (if (cmark-options-validate-utf8? o)    " --validate-utf8" "")
     (if (cmark-options-source-positions? o) " --sourcepos" "")
     (if (cmark-options-hardbreaks? o)       " --hardbreaks" "")
     (if (cmark-options-nobreaks? o)         " --nobreaks" "")
     (if (cmark-options-smart? o)            " --smart" "")
     (if (cmark-options-unsafe-html? o)      " --unsafe" "")
     (fold-left (lambda (acc e) (string-append acc " -e " (symbol->string e)))
                "" (cmark-options-extensions o)))))

(define (ours format markdown o)
  (string->utf8
   (case format
     ((html)       (markdown->html markdown o))
     ((xml)        (markdown->xml markdown o))
     ((commonmark) (markdown->commonmark markdown o))
     ((plaintext)  (markdown->plaintext markdown o))
     (else (error 'ours "unknown format" format)))))

;; Returns #f when the two agree, or a list naming the divergence. Taking
;; our-cfg and cli-cfg separately is what lets Task 9 seed this detector with
;; a deliberate mismatch and prove it can report anything at all.
(define (mismatch fixture format our-cfg cli-cfg)
  (let* ((md   (utf8->string (file->bytevector fixture)))
         (mine (ours format md (config->options our-cfg)))
         (theirs (run-cli (config->flags cli-cfg format) fixture)))
    (if (bytevector=? mine theirs)
        #f
        (list fixture format our-cfg))))

(define (agrees? fixture format cfg) (not (mismatch fixture format cfg cfg)))

(define (cli-differs? fixture format a b)
  (not (bytevector=? (run-cli (config->flags a format) fixture)
                     (run-cli (config->flags b format) fixture))))

;; --- layer 1: one factor at a time --------------------------------------
;; All-off, no extensions. validate-utf8? is off here and is not given an
;; OFAT cell: its behaviour is structurally unreachable through the public
;; API (design spec 10.1) -- string->utf8 always emits valid UTF-8, so no
;; fixture can make it discriminate. It is covered at the bit level in
;; tests/test-native.sps instead.
;; Configs are built by ONE constructor so no cell can accidentally repeat a
;; key. `extensions` lives in the base, so appending another `extensions` pair
;; would produce a duplicate-key plist -- which make-cmark-options rejects
;; outright, turning every extension cell below into a raised condition rather
;; than a comparison.
(define (cfg exts . kvs)
  (append (list 'validate-utf8? #f 'extensions exts) kvs))

(define BASE (cfg '()))

;; Each option: prove the CLI's own output moved, then prove we match it.
;; The (fixture, format) pair for each is chosen so the flag is observable
;; there; a pair that does not discriminate makes the parity cell empty.
(test-assert "sourcepos -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'source-positions? #t)))
(test-assert "sourcepos -- our output matches the CLI"
  (agrees? "tests/fixtures/core.md" 'html (cfg '() 'source-positions? #t)))

(test-assert "hardbreaks -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'hardbreaks? #t)))
(test-assert "hardbreaks -- our output matches the CLI"
  (agrees? "tests/fixtures/core.md" 'html (cfg '() 'hardbreaks? #t)))

(test-assert "nobreaks -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'nobreaks? #t)))
(test-assert "nobreaks -- our output matches the CLI"
  (agrees? "tests/fixtures/core.md" 'html (cfg '() 'nobreaks? #t)))

(test-assert "smart -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/smart.md" 'html BASE (cfg '() 'smart? #t)))
(test-assert "smart -- our output matches the CLI"
  (agrees? "tests/fixtures/smart.md" 'html (cfg '() 'smart? #t)))

(test-assert "unsafe-html -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/hostile.md" 'html BASE (cfg '() 'unsafe-html? #t)))
(test-assert "unsafe-html -- our output matches the CLI"
  (agrees? "tests/fixtures/hostile.md" 'html (cfg '() 'unsafe-html? #t)))

;; --- layer 1: extensions, one at a time ---------------------------------
;; tagfilter gets unsafe-html? in BOTH sides of its comparison. Under safe
;; mode raw HTML is suppressed wholesale, so tagfilter cannot change anything
;; and its cell would be empty. This is the pairing the discrimination guard
;; is here to force you to find.
(define UNSAFE-BASE (cfg '() 'unsafe-html? #t))

(test-assert "table extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE (cfg '(table))))
(test-assert "table extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(table))))

(test-assert "strikethrough extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE
                (cfg '(strikethrough))))
(test-assert "strikethrough extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(strikethrough))))

(test-assert "autolink extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE (cfg '(autolink))))
(test-assert "autolink extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(autolink))))

(test-assert "tasklist extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE (cfg '(tasklist))))
(test-assert "tasklist extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(tasklist))))

(test-assert "tagfilter extension -- the CLI's own output changes (needs unsafe-html)"
  (cli-differs? "tests/fixtures/gfm.md" 'html UNSAFE-BASE
                (cfg '(tagfilter) 'unsafe-html? #t)))
(test-assert "tagfilter extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(tagfilter) 'unsafe-html? #t)))

;; --- layer 1: every format agrees at the defaults -----------------------
(define DEFAULTS '())

(test-equal "default options agree with the CLI in html"
  #f (mismatch "tests/fixtures/gfm.md" 'html DEFAULTS DEFAULTS))
(test-equal "default options agree with the CLI in xml"
  #f (mismatch "tests/fixtures/gfm.md" 'xml DEFAULTS DEFAULTS))
(test-equal "default options agree with the CLI in commonmark"
  #f (mismatch "tests/fixtures/gfm.md" 'commonmark DEFAULTS DEFAULTS))
(test-equal "default options agree with the CLI in plaintext"
  #f (mismatch "tests/fixtures/gfm.md" 'plaintext DEFAULTS DEFAULTS))

(test-end "differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 4: Run the test**

```bash
make test 2>&1 | tail -30
```

Expected on first run: some cells fail. Work through them one at a time and **read the actual bytes before changing an assertion**:

```bash
build/vendor/src/cmark-gfm --to html --sourcepos tests/fixtures/core.md | head -5
```

The two failure modes to distinguish:
- **A discrimination guard fails** → the fixture does not exercise that option. Fix the *fixture or the pairing*, never the guard. Deleting a guard converts a real gap into a silent one.
- **A parity cell fails** → our flag wiring or extension attachment diverges from the CLI. Fix the code.

- [ ] **Step 5: Verify all cells pass**

```bash
make test 2>&1 | tail -5
```

Expected: `ALL SUITES PASSED`, exit 0. Six suites now run.

- [ ] **Step 6: Watch an option-bits transposition fail**

```bash
cp src/cmark-gfm-shim.c /tmp/shim.c.bak
# in chez_cmark_option_bits, swap the `smart` and `nobreaks` assignments
$EDITOR src/cmark-gfm-shim.c
make test 2>&1 | tail -30
cp /tmp/shim.c.bak src/cmark-gfm-shim.c && rm /tmp/shim.c.bak
make test 2>&1 | tail -3
```

Expected: "smart -- our output matches the CLI" and "nobreaks -- our output matches the CLI" both fail by name, while the bit-distinctness test in `test-native.sps` still passes — which is exactly why both layers exist. After restoring, `ALL SUITES PASSED`. Record for Task 10 (mutation A).

- [ ] **Step 7: Commit**

```bash
git add tests/fixtures tests/test-differential.sps Makefile
git commit -m "test: OFAT differential layer with per-option discrimination guards"
```

---

# Task 9: The cartesian sweep and the memory-test exclusion

**Files:**
- Modify: `tests/test-differential.sps`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `mismatch`, `config->flags`, `config->options` from Task 8.

- [ ] **Step 1: Write the failing tests**

Insert into `tests/test-differential.sps`, immediately **before** `(test-end "differential")`:

```scheme
;; --- layer 2: cartesian sweep -------------------------------------------
;; Every valid boolean combination against every format. No discrimination
;; guard here -- layer 1 owns that. This is bulk parity.
(define bool-keys
  '(validate-utf8? source-positions? hardbreaks? nobreaks? smart? unsafe-html?))

(define (plist-ref plist key)
  (cond ((null? plist) #f)
        ((eq? key (car plist)) (cadr plist))
        (else (plist-ref (cddr plist) key))))

(define (all-boolean-configs)
  (let loop ((keys bool-keys) (acc '(())))
    (if (null? keys)
        acc
        (loop (cdr keys)
              (apply append
                     (map (lambda (cfg)
                            (list (append cfg (list (car keys) #f))
                                  (append cfg (list (car keys) #t))))
                          acc))))))

;; The pair our validator rejects (design spec 3.4) is unreachable through
;; the public API, so it is excluded here rather than expected to fail.
(define (valid-config? cfg)
  (not (and (eq? #t (plist-ref cfg 'hardbreaks?))
            (eq? #t (plist-ref cfg 'nobreaks?)))))

(define valid-configs (filter valid-config? (all-boolean-configs)))

;; Pins the arithmetic: 2^6 = 64 combinations, minus the 16 in which both
;; hardbreaks? and nobreaks? are set.
(test-equal "the sweep covers exactly the 48 valid boolean combinations"
  48 (length valid-configs))

(define sweep-formats '(html xml commonmark plaintext))
(define sweep-fixtures '("tests/fixtures/core.md" "tests/fixtures/gfm.md"))

(define (sweep-mismatches)
  (let ((found '()))
    (for-each
     (lambda (cfg)
       (for-each
        (lambda (fmt)
          (for-each
           (lambda (fx)
             (let ((m (mismatch fx fmt cfg cfg)))
               (when m (set! found (cons m found)))))
           sweep-fixtures))
        sweep-formats))
     valid-configs)
    (reverse found)))

;; SEED FIRST. An "assert the list is empty" test passes trivially against a
;; detector that can only ever return '(). This proves the detector reports
;; something when the two sides genuinely differ: our --smart output against
;; the CLI's non-smart output. If this test fails, every empty result below
;; is meaningless.
(test-assert "the mismatch detector reports a deliberately mismatched cell"
  (list? (mismatch "tests/fixtures/smart.md" 'html
                   (cfg '() 'smart? #t)     ; what WE render
                   (cfg '()))))             ; what the CLI is asked for

;; Compared against '() rather than asserted empty, so a failure names the
;; diverging (fixture, format, config) triples instead of just saying "false".
(test-equal "cartesian sweep: no valid boolean combination diverges from the CLI"
  '() (sweep-mismatches))
```

- [ ] **Step 2: Run the tests**

```bash
make test 2>&1 | tail -30
```

Expected: `ALL SUITES PASSED`, exit 0. Roughly 384 additional CLI invocations, a few seconds.

If the sweep reports triples, read one back by hand before touching anything:

```bash
build/vendor/src/cmark-gfm --to commonmark --smart --unsafe tests/fixtures/core.md | head
```

- [ ] **Step 3: Exclude the differential suite from `test-memory`**

Those subprocesses are not Valgrind-instrumented and add no memory coverage `test-render.sps` does not already provide.

In the `Makefile`, after the `TESTS := $(wildcard tests/test-*.sps)` line:

```makefile
# The differential suite spawns ~400 cmark-gfm subprocesses. Those are separate
# processes and are NOT instrumented by the memory tools, so they add no
# coverage here -- test-render.sps already exercises every native allocation
# this stage introduces. Excluded by name so the omission is visible.
MEMORY_TESTS := $(filter-out tests/test-differential.sps,$(TESTS))
```

Then in the `test-memory:` recipe, replace both `$(TESTS)` occurrences with `$(MEMORY_TESTS)`.

- [ ] **Step 4: Verify the memory target still runs and is clean**

```bash
make test-memory 2>&1 | tail -20
```

Expected: no AddressSanitizer report on macOS; no definite leaks and exit 0 on Linux. Confirm `tests/test-differential.sps` does not appear in the output.

- [ ] **Step 5: Watch the seed test fail**

```bash
cp tests/test-differential.sps /tmp/diff.sps.bak
# in `mismatch`, replace the body's `(if (bytevector=? mine theirs) #f ...)`
# with a bare `#f`
$EDITOR tests/test-differential.sps
make test 2>&1 | tail -20
cp /tmp/diff.sps.bak tests/test-differential.sps && rm /tmp/diff.sps.bak
make test 2>&1 | tail -3
```

Expected: "the mismatch detector reports a deliberately mismatched cell" fails by name, while "cartesian sweep: no valid boolean combination diverges from the CLI" still *passes* — which is precisely the empty-test failure the seed exists to catch. After restoring, `ALL SUITES PASSED`.

- [ ] **Step 6: Commit**

```bash
git add tests/test-differential.sps Makefile
git commit -m "test: cartesian differential sweep with a seeded mismatch detector"
```

---

# Task 10: The Stage 2 mutation log

**Files:**
- Create: `.plans/stage-2-mutation-log.md`

Every mutation must break its named test **through the asserted property**. If a mutation fails for some other reason — a syntax error, an import failure — narrow it until the failure is the one predicted. If no mutation can break an assertion, write down that the property is uncovered and why.

Mutations A, B, D, E, and H were already run and their output recorded in Tasks 3, 5, 6, 7, and 8. Run the remaining three now.

- [ ] **Step 1: Mutation C — free the buffer before copying**

```bash
cp src/cmark/gfm/private/scope.sls /tmp/scope.sls.bak
```

In `call-with-render-buffer`, move the free into the body ahead of the copy:

```scheme
        (lambda () (free-buffer buf) (count-buffer-free!) (c-string->string buf))
```

```bash
make test 2>&1 | tail -20
make test-memory 2>&1 | tail -30
cp /tmp/scope.sls.bak src/cmark/gfm/private/scope.sls && rm /tmp/scope.sls.bak
make test 2>&1 | tail -3
```

Expected: `make test-memory` reports `heap-use-after-free` inside the copy. Record whether `make test` alone also caught it — freed heap that has not been overwritten can read back correctly, so a green `make test` here is a real finding about what the test suite alone can and cannot see, not a failure of the exercise.

- [ ] **Step 2: Mutation F — `cmark-options-with` skips validation**

```bash
cp src/cmark/gfm/options.sls /tmp/options.sls.bak
```

In `cmark-options-with`, replace the `build` call with a direct `%make-cmark-options` call using the same eight arguments, bypassing `validate`.

```bash
make test 2>&1 | tail -20
cp /tmp/options.sls.bak src/cmark/gfm/options.sls && rm /tmp/options.sls.bak
make test 2>&1 | tail -3
```

Expected: "cmark-options-with cannot reach the contradictory pair either" and "cmark-options-with rejects an unknown key" fail by name.

- [ ] **Step 3: Mutation G — flip the `source-positions?` default**

```bash
cp src/cmark/gfm/options.sls /tmp/options.sls.bak
```

In both `default-cmark-options` and `make-cmark-options`, change the third default from `#f` to `#t`.

```bash
make test 2>&1 | tail -30
cp /tmp/options.sls.bak src/cmark/gfm/options.sls && rm /tmp/options.sls.bak
make test 2>&1 | tail -3
```

Expected: "source-positions? defaults to #f", "the default options do NOT emit data-sourcepos (ADR-0008)", and the four "default options agree with the CLI in …" cells all fail by name.

- [ ] **Step 4: Write the log**

Create `.plans/stage-2-mutation-log.md` following the exact structure of `.plans/stage-1-mutation-log.md`: a baseline paragraph (suite count, assertion count, `make test` output, exit code), a summary table with columns `# | Mutation | Change | make test result | Named test(s) that failed | Covered?`, then a prose section per mutation recording the **actual observed output**, not the predicted output. Cover mutations A through H as listed in the design spec §8.3.

Add a final section, **Deliberate coverage gaps**, recording:

- `validate-utf8?` — behaviourally unreachable through the public API because `string->utf8` always emits valid UTF-8. Covered at the bit level in `tests/test-native.sps`; the behavioural property is uncovered by construction. Design spec §10.1.
- `&cmark-extension-unavailable` — unreachable through the public API because unknown extension symbols are rejected at options construction. Retains its Stage 1 private-layer test. Design spec §10.2.
- Any mutation above that no test caught, with the reason.

- [ ] **Step 5: Confirm the tree is clean before committing**

```bash
git status --short
```

Expected: only `.plans/stage-2-mutation-log.md` as untracked. If any source file appears modified, a mutation was left in the tree — restore it.

- [ ] **Step 6: Commit**

```bash
git add .plans/stage-2-mutation-log.md
git commit -m "docs: Stage 2 mutation log with observed evidence per decision"
```

---

# Task 11: Release 0.1

**Files:**
- Create: `.plans/decisions/0008-source-positions-off-for-renderer-releases.md`
- Modify: `Akku.manifest`, `CHANGELOG.md`, `README.org`

- [ ] **Step 1: Write ADR-0008**

Create `.plans/decisions/0008-source-positions-off-for-renderer-releases.md`:

```markdown
# ADR-0008: `source-positions?` defaults off in renderer-only releases

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm 0.1
- **Related:** [Stage 2 design](../2026-08-16-stage-2-renderers-design.md) §3.1, project plan §6.2

## Context

Project plan §6.2 recommends `source-positions?: #t` as a default. That
recommendation was written with the Stage 3 Scheme AST in mind, where source
positions are useful diagnostic metadata attached to nodes.

Release 0.1 has no AST. The flag's only observable effect is markup:
`CMARK_OPT_SOURCEPOS` makes the HTML renderer emit a `data-sourcepos`
attribute on every element (`vendor/cmark-gfm/src/html.c:155` onward), and
adds `sourcepos` attributes to XML output. Verified:

    $ printf '# hi\n\npara\n' | cmark-gfm --sourcepos
    <h1 data-sourcepos="1:1-1:4">hi</h1>
    <p data-sourcepos="3:1-3:4">para</p>

So the plan's recommended default would make `markdown->html` — the headline
procedure of the release — emit attributes most callers do not want.

## Decision

Default `source-positions?` to `#f` for 0.1. Callers who want positions set
`'source-positions? #t` explicitly.

**This is scoped to renderer-only releases, and is not a rejection of source
positions.** We want them for the AST: `markdown->ast` in Stage 3 is exactly
the consumer plan §6.2 had in mind, and a Scheme AST without positions is
worth less than one with them.

## Consequences

- `markdown->html` output at the defaults is clean markup.
- Stage 3 must revisit this rather than inherit it. The likely resolution is
  per-entry-point defaults — positions on for `markdown->ast`, off for the
  renderers — since one global default cannot serve both well.
- If Stage 3 instead changes the shared default to `#t`, that is a
  behavioural change for existing 0.1 callers and needs a CHANGELOG entry and
  a minor version bump.
- Regression: `tests/test-render.sps` asserts both that the default emits no
  `data-sourcepos` and that setting the option explicitly does emit it, so
  neither direction can drift silently.
```

- [ ] **Step 2: Bump the version**

In `Akku.manifest`, change `"0.1.0-alpha"` to `"0.1.0"`.

- [ ] **Step 3: Write the changelog**

Create `CHANGELOG.md` (currently empty):

```markdown
# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [0.1.0] — 2026-08-16

First release. Parsing and direct rendering with safe defaults; the Scheme
AST and the SXML adapter follow in 0.2 and 0.3 (ADR-0007).

### Added

- `(cmark gfm)` — the public API: options, renderers, version and capability
  inspection, and the structured condition types.
- `markdown->html`, `markdown->commonmark`, `markdown->plaintext`, and
  `markdown->xml`. The commonmark and plaintext renderers take an optional
  wrap width; html and xml are fixed at arity 2, because cmark applies width
  only to the renderers that wrap.
- Immutable options: `make-cmark-options`, `default-cmark-options`, and
  `cmark-options-with`. Options are named symbols; cmark's numeric constants
  and string names never appear in the public API.
- All five standard GFM extensions — `autolink`, `strikethrough`, `table`,
  `tagfilter`, `tasklist` — enabled by default.
- `cmark-gfm-version`, `cmark-gfm-version-compatible?`, and
  `cmark-gfm-available-extensions`.

### Security

- HTML rendering is safe by default: raw HTML and unsafe link schemes are
  suppressed unless `'unsafe-html? #t` is set explicitly. There is no global
  switch; the setting belongs to each immutable options object.
- Embedded NUL input is rejected, and input is bounded by `max-input-bytes`
  (5 MiB by default) before parsing.

### Notes

- `source-positions?` defaults to `#f` in this release, diverging from
  project plan §6.2. See ADR-0008 — the AST in 0.2 is the consumer that
  wants positions, and this default is scoped to renderer-only releases.
- `validate-utf8?` is accepted and wired, but has no observable effect on
  input reaching the public API: Scheme strings always encode to valid
  UTF-8. See the Stage 2 design spec §10.1.
- Output is verified byte-for-byte against the pinned `cmark-gfm`
  0.29.0.gfm.13 CLI across all 48 valid option combinations in four formats.
```

- [ ] **Step 4: Document the API in the README**

Append to `README.org`:

```org
* Usage

#+begin_src scheme
(import (cmark gfm))

;; Safe by default: raw HTML and unsafe link schemes are suppressed.
(markdown->html "# Hello\n\n~~struck~~\n" (default-cmark-options))

;; Options are named symbols. Unknown keys, duplicate keys, and unknown
;; extensions are rejected before anything native is allocated.
(markdown->html "<b>raw</b>\n" (make-cmark-options 'unsafe-html? #t))

;; Functional update; the original is unchanged.
(define base (make-cmark-options 'extensions '(table)))
(markdown->html "| a |\n|---|\n| 1 |\n" (cmark-options-with base 'smart? #t))

;; Wrap width applies only to the renderers that wrap. Passing one to
;; markdown->html is an arity error, not a silently ignored setting.
(markdown->commonmark "long paragraph text here\n" base 72)
(markdown->plaintext  "long paragraph text here\n" base 72)
(markdown->xml        "# Hello\n" base)

;; Which native library is loaded, and what it can do.
(cmark-gfm-version)                 ;; => "0.29.0.gfm.13"
(cmark-gfm-version-compatible?)     ;; => #t
(cmark-gfm-available-extensions)    ;; => (autolink strikethrough table tagfilter tasklist)
#+end_src

** Options

| Key                  | Default                                        |
|----------------------+------------------------------------------------|
| ~extensions~         | ~(autolink strikethrough table tagfilter tasklist)~ |
| ~validate-utf8?~     | ~#t~                                           |
| ~source-positions?~  | ~#f~ (see ADR-0008)                            |
| ~hardbreaks?~        | ~#f~                                           |
| ~nobreaks?~          | ~#f~                                           |
| ~smart?~             | ~#f~                                           |
| ~unsafe-html?~       | ~#f~                                           |
| ~max-input-bytes~    | ~5242880~ (5 MiB)                              |

~hardbreaks?~ and ~nobreaks?~ cannot both be set. cmark gives hardbreaks
precedence rather than leaving the combination undefined, so this is a
deliberate policy: honouring one of two explicit requests and silently
dropping the other would hide a caller's mistake.

** Errors

Every failure is a structured condition deriving from ~&cmark-error~, so a
caller can catch the whole family or discriminate precisely.

#+begin_src scheme
(guard (e ((cmark-invalid-option? e)
           (list 'bad-option (cmark-invalid-option-key e)
                             (cmark-invalid-option-reason e)))
          ((cmark-error? e) 'some-other-cmark-failure))
  (markdown->html "# hi\n" (make-cmark-options 'unsaef-html? #t)))
;; => (bad-option unsaef-html? unknown-key)
#+end_src
```

- [ ] **Step 5: Verify the documented examples actually work**

Every example above is a claim. Run them:

```bash
CHEZSCHEMELIBDIRS=src:build/scheme-libs chez --script /dev/stdin <<'EOF'
(import (rnrs) (cmark gfm))
(display (markdown->html "# Hello\n\n~~struck~~\n" (default-cmark-options)))
(display (cmark-gfm-version)) (newline)
(display (cmark-gfm-available-extensions)) (newline)
(display (markdown->commonmark "long paragraph text here\n"
                               (make-cmark-options 'extensions '(table)) 72))
(display (guard (e ((cmark-invalid-option? e)
                    (list 'bad-option (cmark-invalid-option-key e)
                                      (cmark-invalid-option-reason e))))
           (markdown->html "# hi\n" (make-cmark-options 'unsaef-html? #t))))
(newline)
EOF
```

Expected: HTML with `<h1>Hello</h1>` and `<del>struck</del>`, then
`0.29.0.gfm.13`, then the five extension symbols, then the wrapped
commonmark, then `(bad-option unsaef-html? unknown-key)`. Any mismatch means
the README is wrong — fix the README, or the code if the code is wrong.

- [ ] **Step 6: Full verification before release**

```bash
make clean && make build && make test && make test-memory
make check-pins
make HAVE_PKG=no vendor && make HAVE_PKG=no build && make HAVE_PKG=no test
```

Expected: `ALL SUITES PASSED` and exit 0 from both acquisition paths; `pins agree`; no sanitizer report. Do not proceed until every command above has been run and its output read.

- [ ] **Step 7: Commit and tag**

```bash
git add Akku.manifest CHANGELOG.md README.org .plans/decisions/0008-source-positions-off-for-renderer-releases.md
git commit -m "feat: release 0.1.0 — parse and render with safe defaults"
git tag -a v0.1.0 -m "0.1.0: parse and render with safe defaults"
```

Do not push the tag until the branch has been reviewed and merged.

---

## Stage 2 exit gate

Design spec §8.2. Every item needs observed output, not an expectation.

- [ ] Differential layers 1 and 2 green — output matches the pinned CLI across the option matrix
- [ ] `live-buffers` included in every balance assertion, plus the movement test
- [ ] Linux CI `make test-memory` clean under Valgrind
- [ ] `.plans/stage-2-mutation-log.md` complete, with each mutation's actual result recorded and every uncovered property named with a reason
- [ ] Both acquisition paths (`pkg-config` and `HAVE_PKG=no`) build and pass
- [ ] Every README example executed and its real output confirmed
