# Stage 6 — Packaging, Documentation, and Release (1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship release 1.0 — an unbuilt tree that diagnoses itself, six runnable examples gated so no public export can go undocumented, a stress suite that catches accumulation, and the documentation plan §14/§16 require.

**Architecture:** No parsing, rendering, or mapping behavior changes; 1.0 freezes the API. A checked-in `fallback/` copy of `(cmark gfm private config)` is shadowed by the generated one in `src/` via `CHEZSCHEMELIBDIRS` ordering, so a tree that was never built raises `&cmark-shim-unavailable` with reason `'not-built` instead of a bare loader error. The one public-API change is an additive `reason` accessor on that condition.

**Tech Stack:** Chez Scheme (R6RS libraries), SRFI-64 for suites, GNU Make, C99 shim, GitHub Actions.

**Spec:** [.plans/2026-08-18-stage-6-packaging-design.md](2026-08-18-stage-6-packaging-design.md)

## Global Constraints

Every task's requirements implicitly include these.

- **Chez floor is 9.5.8**, established by test (Ubuntu CI), not assumption. macOS dev/CI runs 10.4.1. Never write "10.4.1 or later".
- **cmark-gfm** `0.29.0.gfm.x`, pinned `0.29.0.gfm.13`, range `(#x001d0000 . #x001dffff)`.
- **Every `tests/test-*.sps` MUST end with its own exit line:** `(exit (if (zero? (test-runner-fail-count runner)) 0 1))`. SRFI-64 sets no process exit status, so a suite missing it always reports success. Anything after that line is dead code.
- **`tests/test-*.sps` is a wildcard** (`Makefile:88`). Every new suite joins `make test` *and* `make test-memory` (`MEMORY_TESTS`, `Makefile:123`) automatically. Budget its runtime for Valgrind, which is ~100× slower.
- **Never make `#f` or mere truthiness an expected value.** SRFI-64 turns any exception in the actual expression into `#f`, and `0` is truthy in Scheme. Use a sentinel no failure path produces, and end a `guard` body with `'no-condition` so a non-raising body cannot satisfy the assertion.
- **Never expect a value the success path can also produce.** Verified live while writing this plan: deleting *every* rejection from `resolve-shim-path` left `tests/test-native.sps` at 54/54, exit 0.
- **Mutation discipline (AGENTS.md):** no new assertion is done until you have watched it fail. Copy the code under test outside the repo, break the one decision the assertion guards, confirm it fails *by name*, revert, confirm it passes. State the evidence when reporting. §Task 13 collects the required mutations.
- **`(rnrs)` already exports `file-exists?`, `with-input-from-file`, `exit`, `call-with-input-file`.** Also importing any of them from `(chezscheme)` raises "multiple definitions … in body" at import time.
- **Chez resolves a library from the FIRST `CHEZSCHEMELIBDIRS` entry that has it.** Verified: two dirs both defining `(demo probe)`, `a:b` → `from-A`, `b:a` → `from-B`.
- **`chez --program` exits 255 on an uncaught exception, 0 clean.** Verified.
- **A `guard` cannot catch shim resolution failure in-process.** Verified: `(guard (e (...)) (ensure-native-loaded!))` with a poisoned shim path still printed an uncaught report. Library instantiation happens at import, before the guard's extent. Any test of resolution wiring needs a subprocess.
- **Chez's uncaught-condition report DOES print field values**, e.g. `reason: not-built`. Verified. Grepping a child's stderr for a reason symbol is sound.
- **README additions stay terse.** In-depth documentation is deliberately deferred to a later `docs/` tree. State contracts; point at the design spec and ADRs for rationale.
- **Conventional Commits.** Use `rg`, not `grep`.

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `src/cmark/gfm/private/conditions.sls` | MODIFY — `reason` field on `&cmark-shim-unavailable` | 1 |
| `src/cmark/gfm/private/native.sls` | MODIFY — reasons at 4 raise sites; `'not-built` clause | 1, 2 |
| `src/cmark/gfm.sls` | MODIFY — export `cmark-shim-unavailable-reason` | 1 |
| `tests/test-native.sps` | MODIFY — replace 4 empty assertions with `(path reason)` pairs | 1 |
| `fallback/cmark/gfm/private/config.sls` | CREATE — checked-in sentinel config | 2 |
| `tests/test-fallback-config.sps` | CREATE — subprocess: fallback fires, and `src` shadows it | 2 |
| `tests/check-config.sps` | CREATE — fallback vs generated agreement checker | 3 |
| `examples/0{1..6}-*.sps` | CREATE — six runnable programs | 4, 5 |
| `examples/expected/0{1..6}.out` | CREATE — golden output | 4, 5 |
| `tests/test-example-coverage.sps` | CREATE — export-coverage gate | 6 |
| `examples/coverage-exemptions.scm` | CREATE — declared-uncoverable exports, with reasons | 6 |
| `tests/test-stress.sps` | CREATE — accumulation across iterations | 7 |
| `packaging/debian-prereqs.txt` | CREATE — single copy of the prerequisite list | 8 |
| `README.org` | MODIFY — matrix, ownership, linking, licensing, Akku caveat | 8, 9 |
| `NOTICE` | CREATE — cmark-gfm license notice | 9 |
| `.github/workflows/ci.yml` | MODIFY — check-config, matrix check, clean-install job | 3, 8, 10 |
| `Makefile` | MODIFY — `CHEZ_LIBDIRS`, `examples`, `check-config`, stress iterations | 2, 3, 4, 7 |
| `.plans/decisions/0014-fallback-config-shadowing.md` | CREATE — ADR | 12 |
| `Akku.manifest`, `CHANGELOG.md` | MODIFY — 1.0.0 | 12 |

---

### Task 1: `reason` on `&cmark-shim-unavailable`

Four distinct resolution failures are currently indistinguishable to a caller, and the four assertions that claim to test them are empty. This task fixes both at once: the assertions become `(list path reason)`, a shape the success path cannot produce, because `resolve-shim-path` returns a bare path string on success.

**Files:**
- Modify: `src/cmark/gfm/private/conditions.sls:84-86`
- Modify: `src/cmark/gfm/private/native.sls:69,74,77,94`
- Modify: `src/cmark/gfm.sls` (export list, beside `cmark-shim-unavailable-path`)
- Test: `tests/test-native.sps:183-210`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `(make-cmark-shim-unavailable path reason)` — 2 arity, was 1. `(cmark-shim-unavailable-reason c)` → symbol, one of `not-built` | `missing` | `invalid-override` | `load-failed`. Task 2 adds the `not-built` producer.

- [ ] **Step 1: Write the failing tests**

Replace the four existing assertions at `tests/test-native.sps:183-210` with these. Note both defences: the expected value is a two-element list, and each `guard` body ends in `'no-condition`.

```scheme
;; --- reason discriminates the four resolution failures -------------------
;; Asserting (list path reason) rather than the path alone is deliberate, and
;; is a fix, not a flourish. resolve-shim-path RETURNS the path it accepts, so
;; an assertion expecting just the path is satisfied by the success path:
;; verified by deleting every rejection from resolve-shim-path, after which
;; this suite still reported 54 expected passes and exit 0. A two-element list
;; is a value no success path here produces, and the trailing 'no-condition
;; closes the other half -- a guard returns its body's value when nothing
;; raises.
(define (shim-failure thunk)
  (guard (e ((cmark-shim-unavailable? e)
             (list (cmark-shim-unavailable-path e)
                   (cmark-shim-unavailable-reason e))))
    (thunk)
    'no-condition))

(test-equal "a directory override is rejected as invalid-override"
  (list a-real-directory 'invalid-override)
  (shim-failure (lambda () (resolve-shim-path "/irrelevant/default" a-real-directory))))

(test-equal "a directory as the default path, with no override, is missing"
  (list a-real-directory 'missing)
  (shim-failure (lambda () (resolve-shim-path a-real-directory #f))))

(test-equal "a non-absolute override is rejected as invalid-override"
  (list "relative/path.dylib" 'invalid-override)
  (shim-failure (lambda () (resolve-shim-path a-real-non-library-file "relative/path.dylib"))))

(test-equal "a nonexistent override is rejected as invalid-override"
  (list "/no/such/path.dylib" 'invalid-override)
  (shim-failure (lambda () (resolve-shim-path a-real-non-library-file "/no/such/path.dylib"))))

(test-assert "a valid absolute, existing, regular-file override is accepted"
  (string=? a-real-non-library-file
            (resolve-shim-path "/irrelevant/default" a-real-non-library-file)))

(test-equal "load-shim wraps a real dlopen failure as load-failed"
  (list a-real-non-library-file 'load-failed)
  (shim-failure (lambda () (load-shim a-real-non-library-file))))
```

- [ ] **Step 2: Run to verify it fails**

```bash
make build && CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-native.sps
```

Expected: FAIL. `cmark-shim-unavailable-reason` is unbound, so the suite dies at import with `Exception: variable cmark-shim-unavailable-reason is not bound`.

- [ ] **Step 3: Add the field**

In `src/cmark/gfm/private/conditions.sls`, replace lines 84-86:

```scheme
  ;; Raised when the shim cannot be resolved or loaded. path is the path that
  ;; failed, or #f when no path was ever configured. reason is a symbol:
  ;;   'not-built        -- the fallback config is in force; no `make build`
  ;;   'missing          -- the generated default path is not a regular file
  ;;   'invalid-override -- CHEZ_CMARK_GFM_SHIM is set but is not an absolute
  ;;                        path to an existing regular file
  ;;   'load-failed      -- load-shared-object raised on a validated file
  ;;
  ;; 'invalid-override deliberately covers three causes (empty string, not
  ;; absolute, absolute but absent) because resolve-shim-path's single `else`
  ;; branch already conflates them. Splitting it would restructure the load
  ;; path this release exists to freeze; recorded in the design spec 11.
  (define-condition-type &cmark-shim-unavailable &cmark-error
    make-cmark-shim-unavailable cmark-shim-unavailable?
    (path   cmark-shim-unavailable-path)
    (reason cmark-shim-unavailable-reason))
```

Add `cmark-shim-unavailable-reason` to that library's `export` list, on the line that currently reads `cmark-shim-unavailable? cmark-shim-unavailable-path`:

```scheme
          &cmark-shim-unavailable make-cmark-shim-unavailable
          cmark-shim-unavailable? cmark-shim-unavailable-path
          cmark-shim-unavailable-reason
```

- [ ] **Step 4: Pass the reason at all four raise sites**

In `src/cmark/gfm/private/native.sls`:

```scheme
;; line 69, inside resolve-shim-path's no-override branch
           (raise (make-cmark-shim-unavailable default-path 'missing))))
;; line 74, the else branch
      (else (raise (make-cmark-shim-unavailable override 'invalid-override)))))
;; line 77, inside load-shim
    (guard (e (#t (raise (make-cmark-shim-unavailable path 'load-failed))))
;; line 94, inside cmark-loaded's regular-file? check
                  (raise (make-cmark-shim-unavailable path 'missing)))
```

- [ ] **Step 5: Re-export from the public library**

In `src/cmark/gfm.sls`, change the conditions export line:

```scheme
          &cmark-shim-unavailable cmark-shim-unavailable? cmark-shim-unavailable-path
          cmark-shim-unavailable-reason
```

- [ ] **Step 6: Run the tests**

```bash
make test
```

Expected: PASS, `ALL SUITES PASSED`. `test-native.sps` reports 55 expected passes (was 54 — five assertions replaced six, plus the new `load-failed` one; confirm the count rather than assuming it).

- [ ] **Step 7: Commit**

```bash
git add src/cmark/gfm/private/conditions.sls src/cmark/gfm/private/native.sls src/cmark/gfm.sls tests/test-native.sps
git commit -m "feat: discriminate shim-unavailable failures with a reason field

Four resolution failures shared one condition with one field, so a caller
could not tell a missing build from a bad CHEZ_CMARK_GFM_SHIM. Mirrors
&cmark-invalid-option's key+reason pair.

The four assertions guarding these rejections were empty: each expected
exactly the path resolve-shim-path returns on success. Deleting every
rejection left the suite at 54/54, exit 0. Asserting (path reason) is a
shape the success path cannot produce."
```

---

### Task 2: The fallback config

**Files:**
- Create: `fallback/cmark/gfm/private/config.sls`
- Create: `tests/test-fallback-config.sps`
- Modify: `src/cmark/gfm/private/native.sls` (`resolve-shim-path`, line 64)
- Modify: `Makefile:87` (`CHEZ_LIBDIRS`)

**Interfaces:**
- Consumes: `make-cmark-shim-unavailable` (2 arity) and reason `'not-built` from Task 1.
- Produces: the `fallback/` directory, which every later task puts on `CHEZSCHEMELIBDIRS` *after* `src`. Reuses the existing `tests/shim-load-probe.sps` unchanged.

- [ ] **Step 1: Write the failing test**

Create `tests/test-fallback-config.sps`:

```scheme
#!r6rs
;;; The fallback config: what an unbuilt tree does.
;;;
;;; Two properties, and the second matters as much as the first:
;;;   1. With no generated config on the path, importing the library raises
;;;      &cmark-shim-unavailable with reason 'not-built -- not Chez's bare
;;;      "library (cmark gfm private config) not found".
;;;   2. With a real built src/ ahead of fallback/, the fallback is NOT used.
;;;      If that ordering were ever reversed, every native suite would break
;;;      in a confusing way; this asserts the ordering directly.
;;;
;;; Subprocesses are mandatory, not stylistic. native.sls resolves the shim
;;; during library instantiation, which happens at import -- before any
;;; in-process `guard` extent begins. Verified: a guard wrapped directly
;;; around (ensure-native-loaded!) with a poisoned shim path does not catch
;;; the condition; it escapes uncaught. tests/test-shim-loading.sps documents
;;; the same finding and is the pattern this file follows.
;;;
;;; Reading the child's stderr is sound because Chez's uncaught-condition
;;; report prints record field values, one per line -- verified directly:
;;; a two-field condition prints "path: #f" and "reason: not-built".
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv system)
        (cmark-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

(define chez-executable (or (getenv "CHEZ") "chez"))
(define probe-script "tests/shim-load-probe.sps")
(define unbuilt-src "tests/tmp/unbuilt-src")
(define stderr-capture "tests/tmp/fallback-probe-stderr.txt")

(system "mkdir -p tests/tmp")

;; A copy of src/ with the generated config removed -- i.e. exactly what a
;; fresh clone or a `make clean` leaves behind. Copied rather than mutated
;; so the real tree is never touched.
(system (string-append "rm -rf " unbuilt-src
                       " && mkdir -p " unbuilt-src
                       " && cp -R src/cmark " unbuilt-src "/cmark"
                       " && rm -f " unbuilt-src "/cmark/gfm/private/config.sls"))

(define (read-whole-file path)
  (let ((bv (file->bytevector path)))
    (utf8->string bv)))

;; Runs the probe with an explicit libdirs and no ambient shim override.
(define (run-probe libdirs)
  (let ((cmd (string-append
              "unset CHEZ_CMARK_GFM_SHIM; "
              "CHEZSCHEMELIBDIRS=\"" libdirs "\" "
              chez-executable " --script \"" probe-script "\" "
              "2>\"" stderr-capture "\"")))
    (let ((code (system cmd)))
      (values code (read-whole-file stderr-capture)))))

(test-begin "fallback-config")

;; --- 1. an unbuilt tree names its own remedy ---------------------------
(let-values (((code stderr) (run-probe (string-append unbuilt-src ":fallback"))))
  (test-assert "an unbuilt tree fails closed"
    (not (zero? code)))
  (test-assert "an unbuilt tree raises cmark-shim-unavailable, not a loader error"
    (string-contains? stderr "cmark-shim-unavailable"))
  (test-assert "an unbuilt tree reports reason not-built"
    (string-contains? stderr "not-built"))
  ;; The bug this whole task exists to remove. Asserted absent, because
  ;; "raises something" is not the property -- "raises a condition instead of
  ;; a missing-file report" is.
  (test-assert "an unbuilt tree does NOT report a missing library"
    (not (string-contains? stderr "library (cmark gfm private config) not found"))))

;; --- 2. a built src/ shadows the fallback ------------------------------
(let-values (((code stderr) (run-probe "src:fallback")))
  (test-equal "a built src/ ahead of fallback/ loads the real shim (exit 0)"
    0 code))

(test-end "fallback-config")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-fallback-config.sps
```

Expected: FAIL on the first three assertions. `fallback/` does not exist yet, so the child reports `library (cmark gfm private config) not found` — which is precisely what the fourth assertion forbids, so that one fails too. Exactly four failures.

- [ ] **Step 3: Create the fallback config**

```bash
mkdir -p fallback/cmark/gfm/private
```

Create `fallback/cmark/gfm/private/config.sls`:

```scheme
#!r6rs
;;; Fallback build configuration -- in force ONLY when no build has happened.
;;;
;;; `make build` generates the real (cmark gfm private config) into src/, and
;;; the Makefile puts src ahead of fallback on CHEZSCHEMELIBDIRS. Chez resolves
;;; a library from the FIRST entry that has it, so this file is reached only
;;; when the generated one is absent -- a fresh clone, or after `make clean`.
;;; Unlike the generated file, this one is checked in and holds no
;;; machine-specific path.
;;;
;;; shim-path is #f rather than a string, and that is the entire mechanism. No
;;; build can produce a non-string here, so resolve-shim-path can tell "never
;;; built" from "built, but the shim has since gone missing" without either
;;; case having to guess. A plausible-looking fake path could not: it would be
;;; indistinguishable from a real path that had been deleted.
;;;
;;; cmark-library-paths is empty, with a documented consequence: in an unbuilt
;;; tree CHEZ_CMARK_GFM_SHIM still overrides and loads a prebuilt shim, which
;;; works on macOS but fails on Linux, whose loader does not put a dlopen'd
;;; library's dependencies in the global symbol namespace. See ADR-0014.
(library (cmark gfm private config)
  (export shim-path cmark-library-paths cmark-supported-version-range)
  (import (rnrs))
  (define shim-path #f)
  (define cmark-library-paths '())
  ;; Must stay equal to the Makefile's generated value; `make check-config`
  ;; enforces that.
  (define cmark-supported-version-range '(#x001d0000 . #x001dffff)))
```

- [ ] **Step 4: Add the `not-built` clause**

In `src/cmark/gfm/private/native.sls`, `resolve-shim-path` (line 64) gains one leading `cond` clause. The `(not override)` guard is load-bearing: an explicit `CHEZ_CMARK_GFM_SHIM` must still win in an unbuilt tree.

```scheme
  (define (resolve-shim-path default-path override)
    (cond
      ;; The fallback config's sentinel: shim-path is #f because no build has
      ;; run, so there is no path to report. Guarded on (not override) so an
      ;; explicit CHEZ_CMARK_GFM_SHIM still wins in an unbuilt tree.
      ((and (not override) (not (string? default-path)))
       (raise (make-cmark-shim-unavailable #f 'not-built)))
      ((not override)
       (if (regular-file? default-path)
           default-path
           (raise (make-cmark-shim-unavailable default-path 'missing))))
      ((and (> (string-length override) 0)
            (char=? (string-ref override 0) #\/)
            (regular-file? override))
       override)
      (else (raise (make-cmark-shim-unavailable override 'invalid-override)))))
```

- [ ] **Step 5: Put `fallback` on the library path, after `src`**

In `Makefile`, replace line 87:

```make
# src FIRST, fallback SECOND, and the order is the mechanism: Chez resolves a
# library from the first entry that has it, so the generated
# src/cmark/gfm/private/config.sls shadows fallback/'s checked-in sentinel
# whenever a build has happened. Reversing these two makes every native suite
# fail with reason 'not-built against a perfectly good build.
# tests/test-fallback-config.sps asserts the ordering directly.
CHEZ_LIBDIRS := src:fallback:tests:$(SRFI_LIBS)
```

- [ ] **Step 6: Run the tests**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-fallback-config.sps && make test
```

Expected: the suite reports 5 expected passes, then `ALL SUITES PASSED`.

- [ ] **Step 7: Commit**

```bash
git add fallback tests/test-fallback-config.sps src/cmark/gfm/private/native.sls Makefile
git commit -m "feat: make an unbuilt tree name its own remedy

An unbuilt tree failed with 'library (cmark gfm private config) not found',
which names no cause and no fix, because the generated config is gitignored.
A checked-in fallback shadowed by src/ on CHEZSCHEMELIBDIRS turns that into
&cmark-shim-unavailable with reason 'not-built.

shim-path is #f, not a fake path: no build can produce a non-string, so
'never built' stays distinguishable from 'shim deleted since'."
```

---

### Task 3: `make check-config`

Two files now declare `(cmark gfm private config)` and nothing notices them diverging. That is the shape of bug `check-pins` exists for — and the shape AGENTS.md records as having been violated in the same commit that wrote it down as a comment.

**Files:**
- Create: `tests/check-config.sps`
- Modify: `Makefile` (new target, `.PHONY` at line 125)
- Modify: `.github/workflows/ci.yml` (one step in each of the two existing jobs)

**Interfaces:**
- Consumes: `fallback/cmark/gfm/private/config.sls` from Task 2.
- Produces: `make check-config`. Exits 0 on agreement, 1 with a diagnostic naming the disagreement.

- [ ] **Step 1: Write the checker**

Create `tests/check-config.sps`. It compares datums, not text, so `'(x)` and `(quote (x))` are equal and formatting is irrelevant. Not named `test-*.sps`, deliberately: it needs a *built* tree, and `make test`'s wildcard must not pick it up.

```scheme
#!r6rs
;;; make check-config -- the checked-in fallback config and the generated one
;;; must stay interchangeable in everything that is not deliberately
;;; machine-specific.
;;;
;;; Deliberately NOT named tests/test-*.sps: `make test`'s wildcard would pick
;;; it up, and this needs a built tree to have anything to compare against.
;;; tests/check-prod.sps is the same arrangement.
;;;
;;; Compares read datums rather than file text, so '(x) and (quote (x)) are
;;; equal, and indentation and comments are irrelevant.
(import (rnrs))

(define generated "src/cmark/gfm/private/config.sls")
(define fallback  "fallback/cmark/gfm/private/config.sls")

(define (read-library path)
  (unless (file-exists? path)
    (display (string-append "check-config: " path " is missing;"
                            " run `make build` first\n")
             (current-error-port))
    (exit 1))
  (call-with-input-file path read))

;; (library <name> (export . names) (import . specs) . body)
(define (library-name form) (cadr form))
(define (library-exports form) (cdr (caddr form)))
(define (library-body form) (cddddr form))

(define (definition-value form name)
  (let loop ((fs (library-body form)))
    (cond
      ((null? fs)
       (display (string-append "check-config: no definition of "
                               (symbol->string name) " found\n")
                (current-error-port))
       (exit 1))
      ((and (pair? (car fs))
            (eq? (car (car fs)) 'define)
            (eq? (cadr (car fs)) name))
       (caddr (car fs)))
      (else (loop (cdr fs))))))

(define (subset? a b) (for-all (lambda (x) (memq x b)) a))
(define (same-set? a b) (and (subset? a b) (subset? b a)))

(define g (read-library generated))
(define f (read-library fallback))

(define failures '())
(define (fail! msg) (set! failures (cons msg failures)))

(unless (equal? (library-name g) (library-name f))
  (fail! "the two files declare different library names"))

(unless (same-set? (library-exports g) (library-exports f))
  (fail! "the two files export different names"))

(unless (equal? (definition-value g 'cmark-supported-version-range)
                (definition-value f 'cmark-supported-version-range))
  (fail! "cmark-supported-version-range differs between the two files"))

(if (null? failures)
    (begin
      (display "check-config: fallback and generated config agree\n")
      (exit 0))
    (begin
      (display "check-config: FAILED\n" (current-error-port))
      (for-each (lambda (m)
                  (display (string-append "  - " m "\n") (current-error-port)))
                (reverse failures))
      (display (string-append
                "\nBoth files declare (cmark gfm private config). The generated one\n"
                "is written by the Makefile recipe; the fallback is checked in at\n"
                (string-append fallback ".\n")
                "Bring them back into agreement -- a consumer of an unbuilt tree\n"
                "sees the fallback, and it must be substitutable.\n")
               (current-error-port))
      (exit 1)))
```

- [ ] **Step 2: Run it to verify it passes on a good tree**

```bash
make build && chez --program tests/check-config.sps
```

Expected: `check-config: fallback and generated config agree`, exit 0.

- [ ] **Step 3: Verify it fails when they diverge**

Confirm the check has teeth before wiring it up. Change the fallback's version range, run, revert:

```bash
sed -i.bak 's/#x001dffff/#x001effff/' fallback/cmark/gfm/private/config.sls
chez --program tests/check-config.sps; echo "exit=$?"
mv fallback/cmark/gfm/private/config.sls.bak fallback/cmark/gfm/private/config.sls
```

Expected: `check-config: FAILED` naming `cmark-supported-version-range differs`, `exit=1`. Then confirm it passes again.

- [ ] **Step 4: Add the Make target**

Append to `Makefile`:

```make
# The fallback config (fallback/) and the generated one (src/) both declare
# (cmark gfm private config). Nothing else would notice them diverging, and a
# divergence is invisible until a consumer imports an unbuilt tree -- so this
# is a check, not a comment. Depends on `build` because it has nothing to
# compare against until the generated file exists.
check-config: build
	$(CHEZ) --program tests/check-config.sps
```

Add `check-config` to `.PHONY` at line 125:

```make
.PHONY: all build deps check-pins check-purity check-prod check-config examples dev test test-memory vendor clean prod deps-info
```

(`examples` is added here now so Task 4 does not have to touch this line again.)

- [ ] **Step 5: Wire it into CI**

In `.github/workflows/ci.yml`, in the **linux** job, immediately after the `Build (vendored path)` step:

```yaml
      # Two files declare (cmark gfm private config): the generated one and
      # fallback/'s checked-in sentinel. They must stay substitutable, and
      # only a built tree has both to compare.
      - name: Check the fallback config agrees with the generated one
        run: make HAVE_PKG=no check-config
```

In the **macos** job, extend the existing `Build and test (pkg-config path)` step:

```yaml
      - name: Build and test (pkg-config path)
        run: |
          make build
          make check-config
          make test
```

- [ ] **Step 6: Commit**

```bash
git add tests/check-config.sps Makefile .github/workflows/ci.yml
git commit -m "test: enforce fallback and generated config agreement

Two files now declare (cmark gfm private config) and nothing noticed them
diverging. Compares library name, export set, and version range as read
datums. Confirmed to fail on a changed range before being wired into CI."
```

---

### Task 4: `make examples` and the first example

**Files:**
- Create: `examples/01-rendering.sps`
- Create: `examples/expected/01.out`
- Modify: `Makefile` (new `examples` target)

**Interfaces:**
- Consumes: `fallback/` from Task 2.
- Produces: `make examples` — runs every `examples/*.sps` and diffs against `examples/expected/<basename>.out`. Task 5's five examples need no Makefile change. The convention: example `NN-name.sps` pairs with expected file `NN.out`.

- [ ] **Step 1: Write the example**

Create `examples/01-rendering.sps`:

```scheme
#!r6rs
;;; Rendering Markdown in four output formats.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/01-rendering.sps
;;; or run every example and check its output:  make examples
(import (rnrs) (cmark gfm))

(define doc "# Title\n\nA ~~struck~~ word and a <b>raw</b> tag.\n")

(define (show label text)
  (display label) (newline)
  (display text)
  (newline))

;; Safe by default. Raw HTML is replaced by a comment, not passed through --
;; there is no option you have to remember to set.
(show "html:" (markdown->html doc (default-cmark-options)))

;; Unsafe rendering is available, and has to be asked for by name.
(show "html, unsafe:" (markdown->html doc (make-cmark-options 'unsafe-html? #t)))

;; The two wrapping renderers take a width. markdown->html does not, and
;; passing one to it is an arity error rather than a silently ignored setting.
(show "commonmark, width 20:" (markdown->commonmark doc (default-cmark-options) 20))
(show "plaintext, width 20:"  (markdown->plaintext  doc (default-cmark-options) 20))

;; XML is cmark's own AST serialization.
(show "xml:" (markdown->xml doc (default-cmark-options)))
```

- [ ] **Step 2: Run it and confirm the two properties that matter**

```bash
make build
CHEZSCHEMELIBDIRS=src:fallback chez --program examples/01-rendering.sps
```

Expected output begins:

```text
html:
<h1>Title</h1>
<p>A <del>struck</del> word and a <!-- raw HTML omitted -->raw<!-- raw HTML omitted --> tag.</p>

html, unsafe:
<h1>Title</h1>
<p>A <del>struck</del> word and a <b>raw</b> tag.</p>
```

Before saving it as golden output, confirm both properties by eye — a golden file generated from behavior and then asserted against that behavior proves nothing on its own:

1. The safe render contains `raw HTML omitted` and **no** `<b>`.
2. The unsafe render contains `<b>raw</b>`.
3. `commonmark, width 20:` wraps — `A ~~struck~~ word` and `and a <b>raw</b>` are on separate lines.

- [ ] **Step 3: Save the expected output**

```bash
mkdir -p examples/expected
CHEZSCHEMELIBDIRS=src:fallback chez --program examples/01-rendering.sps > examples/expected/01.out
rg -c 'raw HTML omitted' examples/expected/01.out
rg -c '<b>raw</b>' examples/expected/01.out
```

Expected: both counts are non-zero (2 and 2 respectively — the safe render has two omission comments, and `<b>raw</b>` appears in both the unsafe HTML and the CommonMark round-trip).

- [ ] **Step 4: Add the Make target**

Append to `Makefile`:

```make
EXAMPLES := $(wildcard examples/*.sps)

# CHEZSCHEMELIBDIRS is src:fallback and NOTHING ELSE, deliberately. No
# build/scheme-libs, no chez-srfi, no wak-*. The 0.3.0 CHANGELOG claims a
# consumer of this package acquires no dev dependency; an example that
# reached one would break this target, which is the only way that claim
# stays true rather than merely written down.
#
# Each examples/NN-name.sps pairs with examples/expected/NN.out. Keeps going
# after a failure so one stale example cannot hide the others.
examples: build
	@fail=0; \
	for e in $(EXAMPLES); do \
	  base=$$(basename $$e .sps); \
	  exp=examples/expected/$$(echo $$base | cut -d- -f1).out; \
	  echo "=== $$e ==="; \
	  if [ ! -f $$exp ]; then \
	    echo "MISSING expected output: $$exp" >&2; fail=1; continue; \
	  fi; \
	  if CHEZSCHEMELIBDIRS=src:fallback $(CHEZ) --program $$e > tests/tmp/$$base.out 2>&1; then \
	    if diff -u $$exp tests/tmp/$$base.out; then \
	      echo "ok"; \
	    else \
	      echo "OUTPUT CHANGED: $$e" >&2; fail=1; \
	    fi; \
	  else \
	    echo "EXAMPLE FAILED TO RUN: $$e" >&2; \
	    cat tests/tmp/$$base.out >&2; fail=1; \
	  fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "ALL EXAMPLES PASSED"; \
	else echo "EXAMPLES FAILED"; fi; \
	exit $$fail
```

`examples` is already in `.PHONY` from Task 3 Step 4. The target writes to `tests/tmp/`, which `make deps` already creates; add a `mkdir -p tests/tmp` guard as the target's first line:

```make
examples: build
	@mkdir -p tests/tmp; \
	fail=0; \
```

- [ ] **Step 5: Run it**

```bash
make examples
```

Expected: `=== examples/01-rendering.sps ===`, `ok`, `ALL EXAMPLES PASSED`, exit 0.

- [ ] **Step 6: Verify the target has teeth**

```bash
printf 'garbage\n' >> examples/expected/01.out
make examples; echo "exit=$?"
git checkout examples/expected/01.out
```

Expected: a diff, `OUTPUT CHANGED`, `EXAMPLES FAILED`, `exit=1`. Then confirm `make examples` passes again after the revert.

- [ ] **Step 7: Verify the no-dev-dependency claim is enforced**

This is the mutation that proves the target's central claim. Add a dev-dependency import to the example, confirm it breaks, then revert:

```bash
sed -i.bak 's/(import (rnrs) (cmark gfm))/(import (rnrs) (cmark gfm) (srfi :64))/' examples/01-rendering.sps
make examples; echo "exit=$?"
mv examples/01-rendering.sps.bak examples/01-rendering.sps
```

Expected: `EXAMPLE FAILED TO RUN` with a library-not-found error naming `(srfi :64)`, `exit=1`. Then confirm it passes again.

- [ ] **Step 8: Commit**

```bash
git add examples Makefile
git commit -m "feat: add make examples with the first runnable example

Runs every examples/*.sps and diffs against its expected output, with
CHEZSCHEMELIBDIRS=src:fallback and nothing else -- so an example that
reached a dev dependency breaks the build. Confirmed by adding an
(srfi :64) import and watching it fail."
```

---

### Task 5: The remaining five examples

**Files:**
- Create: `examples/02-options.sps`, `examples/expected/02.out`
- Create: `examples/03-ast.sps`, `examples/expected/03.out`
- Create: `examples/04-sxml.sps`, `examples/expected/04.out`
- Create: `examples/05-errors.sps`, `examples/expected/05.out`
- Create: `examples/06-capabilities.sps`, `examples/expected/06.out`

**Interfaces:**
- Consumes: `make examples` from Task 4, and its `NN-name.sps` ↔ `NN.out` convention.
- Produces: coverage of the remaining public exports, which Task 6's gate depends on. Task 6 will fail until these exist.

For each of the five: write the file, run it with `CHEZSCHEMELIBDIRS=src:fallback chez --program examples/NN-*.sps`, read the output to confirm it demonstrates what the file claims, save it to `examples/expected/NN.out`, then run `make examples`.

- [ ] **Step 1: `examples/02-options.sps`**

```scheme
#!r6rs
;;; Options are immutable records built from named symbols.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/02-options.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

;; Every extension cmark-gfm ships, all on by default.
(line "supported-extensions: " (supported-extensions))
(line "default extensions:   " (cmark-options-extensions (default-cmark-options)))

;; Named keys. Unknown keys, duplicate keys, and unknown extensions are
;; rejected before anything native is allocated -- see 05-errors.sps.
(define tables-only (make-cmark-options 'extensions '(table)))
(line "tables only:          " (cmark-options-extensions tables-only))

;; Functional update. The original record is untouched.
(define smart-tables (cmark-options-with tables-only 'smart? #t))
(line "updated smart?:       " (cmark-options-smart? smart-tables))
(line "original smart?:      " (cmark-options-smart? tables-only))
(line "extensions carried:   " (cmark-options-extensions smart-tables))

;; The resource limits, which apply to parsing rather than rendering.
(line "max-input-bytes:      " (cmark-options-max-input-bytes (default-cmark-options)))
(line "max-nodes:            " (cmark-options-max-nodes (default-cmark-options)))
(line "max-depth:            " (cmark-options-max-depth (default-cmark-options)))

;; The remaining renderer flags, shown as defaults.
(line "validate-utf8?:       " (cmark-options-validate-utf8? (default-cmark-options)))
(line "source-positions?:    " (cmark-options-source-positions? (default-cmark-options)))
(line "hardbreaks?:          " (cmark-options-hardbreaks? (default-cmark-options)))
(line "nobreaks?:            " (cmark-options-nobreaks? (default-cmark-options)))
(line "unsafe-html?:         " (cmark-options-unsafe-html? (default-cmark-options)))
(line "is an options record: " (cmark-options? (default-cmark-options)))

;; Smart punctuation, so the option above has a visible effect.
(display (markdown->html "\"quoted\" -- dashed\n" (make-cmark-options 'smart? #t)))
```

- [ ] **Step 2: `examples/03-ast.sps`**

```scheme
#!r6rs
;;; The Scheme AST. Every object here is Scheme-owned: no native pointer
;;; escapes, and the tree stays valid after the native document is gone.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/03-ast.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

;; One argument turns source positions ON (ADR-0009): if you asked for a tree
;; rather than markup, positions are usually why.
(define tree (markdown->ast "# Title\n\nSome *emphasis* here.\n"))

(line "root type:     " (markdown-node-type tree))
(line "is a node:     " (markdown-node? tree))
(line "child count:   " (length (markdown-node-children tree)))
(line "properties:    " (markdown-node-properties tree))

(define heading (car (markdown-node-children tree)))
(line "first child:   " (markdown-node-type heading))
(line "heading level: " (markdown-node-property heading 'level))

(define pos (markdown-node-source heading))
(line "source pos?:   " (source-position? pos))
(line "start line:    " (source-position-start-line pos))
(line "start column:  " (source-position-start-column pos))
(line "end line:      " (source-position-end-line pos))
(line "end column:    " (source-position-end-column pos))

;; Two arguments take an options record. default-ast-options is the one-arg
;; default; passing default-cmark-options instead turns positions off.
(define no-pos (markdown->ast "# Title\n" (default-cmark-options)))
(line "positions off: " (markdown-node-source
                         (car (markdown-node-children no-pos))))
(line "ast defaults:  " (cmark-options-source-positions? (default-ast-options)))

;; Fold counts nodes; map rebuilds the tree. Both are pure.
(line "node count:    " (markdown-node-fold (lambda (n acc) (+ acc 1)) 0 tree))

(define shouted
  (markdown-node-map
   (lambda (n)
     (if (eq? (markdown-node-type n) 'text)
         (markdown-node-with-properties
          n (list (cons 'literal (string-upcase (markdown-node-property n 'literal)))))
         n))
   tree))
(line "mapped text:   " (markdown-node-property
                         (car (markdown-node-children
                               (car (markdown-node-children shouted))))
                         'literal))

;; Building nodes by hand, for anything that constructs rather than inspects.
(define built
  (make-markdown-node 'text (list (cons 'literal "made")) '()
                      (make-source-position 1 1 1 4)))
(line "built literal: " (markdown-node-property built 'literal))
(line "replaced kids: " (length (markdown-node-children
                                 (markdown-node-with-children tree (list built)))))
```

- [ ] **Step 3: `examples/04-sxml.sps`**

```scheme
#!r6rs
;;; SXML output. A tree in HTML vocabulary that a conforming serializer
;;; renders as an HTML fragment -- not a whole page.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/04-sxml.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

(define doc "A [link](/x) and a <b>raw</b> tag.\n")

;; One argument: default options both sides.
(line "default:        " (markdown->sxml doc))

;; raw-html defaults to 'omit -- the policy that does not depend on which
;; serializer you use, because the tree then holds no markup to escape.
(line "raw-html omit:  " (sxml-options-raw-html (default-sxml-options)))
(line "escape instead: " (markdown->sxml doc (default-cmark-options)
                                         (make-sxml-options 'raw-html 'escape)))

;; The attribute marker defaults to caret, NOT the SXML spec's @, because
;; both serializers reachable on this platform mark attributes ^ and neither
;; recognises @ at all. See ADR-0013.
(line "marker default: " (sxml-options-attribute-marker (default-sxml-options)))
(line "with @ marker:  " (markdown->sxml doc (default-cmark-options)
                                         (make-sxml-options 'attribute-marker 'at)))

;; What a softbreak becomes. cmark's own hardbreaks?/nobreaks? are renderer
;; options that never reach a parse, so they cannot be carried on an AST.
(line "softbreak:      " (sxml-options-softbreak (default-sxml-options)))
(line "as a space:     " (markdown->sxml "one\ntwo\n" (default-cmark-options)
                                         (make-sxml-options 'softbreak 'space)))
(line "is sxml opts:   " (sxml-options? (default-sxml-options)))
(line "functional upd: " (sxml-options-raw-html
                          (sxml-options-with (default-sxml-options)
                                             'raw-html 'escape)))

;; The pure half, for a tree you already have. No native code involved.
(line "from an AST:    " (markdown-ast->sxml (markdown->ast doc (default-cmark-options))))
(line "with options:   " (markdown-ast->sxml
                          (markdown->ast doc (default-cmark-options))
                          (make-sxml-options 'raw-html 'escape)))

;; A dangerous URL becomes an empty attribute value -- cmark's own rule,
;; not one this library invented.
(line "unsafe url:     " (markdown->sxml "[x](javascript:alert(1))\n"))
```

- [ ] **Step 4: `examples/05-errors.sps`**

```scheme
#!r6rs
;;; Every failure is a structured condition deriving from &cmark-error, so a
;;; caller can catch the whole family or discriminate precisely.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/05-errors.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

;; A misspelled key. Rejected before any native resource is allocated.
(line "typo key:       "
      (guard (e ((cmark-invalid-option? e)
                 (list (cmark-invalid-option-key e)
                       (cmark-invalid-option-reason e))))
        (markdown->html "# hi\n" (make-cmark-options 'unsaef-html? #t))
        'no-condition))

;; An extension cmark-gfm does not have.
(line "bad extension:  "
      (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
        (make-cmark-options 'extensions '(nosuchextension))
        'no-condition))

;; hardbreaks? and nobreaks? contradict each other; cmark gives one
;; precedence, so honouring one and dropping the other silently would hide
;; a caller's mistake.
(line "contradiction:  "
      (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
        (make-cmark-options 'hardbreaks? #t 'nobreaks? #t)
        'no-condition))

;; Embedded NUL. UTF-8 text cannot contain one, so this is rejected input
;; rather than a rendering failure.
(line "embedded NUL:   "
      (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
        (markdown->html "a\x0;b" (default-cmark-options))
        'no-condition))

;; A resource limit. The value carried is the limit that was hit.
(line "depth limit:    "
      (guard (e ((cmark-resource-limit? e)
                 (list (cmark-invalid-input-reason e)
                       (cmark-resource-limit-value e))))
        (markdown->ast (make-string 40 #\>) (make-cmark-options 'max-depth 4))
        'no-condition))

;; A tree the parser never produces, handed to the SXML adapter directly.
(line "malformed tree: "
      (guard (e ((cmark-malformed-tree? e) (cmark-malformed-tree-reason e)))
        (markdown-ast->sxml
         (make-markdown-node
          'table (list (cons 'columns 1) (cons 'alignments '(none))) 
          (list (make-markdown-node
                 'table-row (list (cons 'header? #f))
                 (list (make-markdown-node 'table-cell '() '() #f)) #f))
          #f))
        'no-condition))

;; Catching the family rather than a member. Every condition above also
;; satisfies cmark-error?.
(line "whole family:   "
      (guard (e ((cmark-error? e) 'caught-as-cmark-error))
        (markdown->html "# hi\n" (make-cmark-options 'bogus? #t))
        'no-condition))

;; The predicates and accessors for conditions this example cannot trigger
;; through the public API are listed in examples/coverage-exemptions.scm with
;; the reason each is unreachable.
(line "predicates:     "
      (list (cmark-version-incompatible? 'not-a-condition)
            (cmark-extension-unavailable? 'not-a-condition)
            (cmark-shim-unavailable? 'not-a-condition)
            (cmark-render-failed? 'not-a-condition)
            (cmark-unsupported-node? 'not-a-condition)))
```

**Note on Step 4:** the `malformed tree` and `depth limit` cases must be run and confirmed to actually raise before their output is saved. If either returns `no-condition`, the fixture is wrong — fix the fixture, do not save the passing-looking output. The `'no-condition` sentinel exists precisely so this is visible.

- [ ] **Step 5: `examples/06-capabilities.sps`**

```scheme
#!r6rs
;;; Which native library is loaded, and what it can do.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/06-capabilities.sps
;;;
;;; Prints properties rather than the version string itself: the version is
;;; whatever cmark-gfm this machine has, and a golden file naming it would
;;; break on any machine with a different patch release.
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

(line "version is a string:  " (string? (cmark-gfm-version)))
(line "version is non-empty: " (> (string-length (cmark-gfm-version)) 0))
(line "compatible:           " (cmark-gfm-version-compatible?))
(line "available extensions: " (cmark-gfm-available-extensions))
```

- [ ] **Step 6: Generate and check each expected file**

```bash
for e in examples/0[2-6]-*.sps; do
  n=$(basename $e .sps | cut -d- -f1)
  CHEZSCHEMELIBDIRS=src:fallback chez --program $e > examples/expected/$n.out || echo "FAILED: $e"
done
rg -n 'no-condition' examples/expected/05.out || echo "good: every error case actually raised"
```

Expected: no `FAILED` lines, and `no-condition` appears nowhere in `05.out`. A `no-condition` there means that example's fixture did not trigger the failure it claims to demonstrate — fix the fixture and regenerate.

- [ ] **Step 7: Run the full target**

```bash
make examples
```

Expected: six `ok` lines, `ALL EXAMPLES PASSED`.

- [ ] **Step 8: Commit**

```bash
git add examples
git commit -m "docs: add examples for options, AST, SXML, errors, and capabilities

Six runnable programs now cover the public API. 05-errors.sps ends every
guard body with 'no-condition so a fixture that fails to raise is visible
in the output rather than passing quietly. 06-capabilities.sps asserts
properties of the version string rather than its value, so the golden file
does not pin one machine's cmark patch release."
```

---

### Task 6: The export-coverage gate

**Files:**
- Create: `tests/test-example-coverage.sps`
- Create: `examples/coverage-exemptions.scm`
- Modify: `Makefile:244` (`check-purity` suite list)

**Interfaces:**
- Consumes: all six examples from Tasks 4-5.
- Produces: a gate that fails when `(cmark gfm)` gains an export no example uses. Pure Scheme — no shared object, so it joins `check-purity`.

- [ ] **Step 1: Write the exemption list**

Create `examples/coverage-exemptions.scm`:

```scheme
;; Public exports of (cmark gfm) that no example can exercise, each with the
;; reason it is unreachable. NOT a convenience list: tests/test-example-
;; coverage.sps fails if an entry here is actually used by an example (stale)
;; or is not exported at all (typo), so an entry cannot quietly become an
;; excuse. AGENTS.md requires an uncoverable property to be written down
;; rather than left silent.
;;
;; Format: (identifier "reason")
((&cmark-error
  "A condition TYPE name. R6RS condition types are not first-class values a
   caller can reference; only the predicate and accessors are usable, and
   05-errors.sps uses cmark-error?.")
 (&cmark-version-incompatible
  "Condition type name, as above.")
 (&cmark-dead-document
  "Condition type name, as above.")
 (&cmark-extension-unavailable
  "Condition type name, as above.")
 (&cmark-invalid-input
  "Condition type name, as above.")
 (&cmark-shim-unavailable
  "Condition type name, as above.")
 (&cmark-invalid-option
  "Condition type name, as above.")
 (&cmark-render-failed
  "Condition type name, as above.")
 (&cmark-resource-limit
  "Condition type name, as above.")
 (&cmark-unsupported-node
  "Condition type name, as above.")
 (&cmark-malformed-tree
  "Condition type name, as above.")
 (cmark-dead-document?
  "Raised only from private scope.sls (lines 40 and 157) when a document is
   used after its scope closes. No public entry point can produce it: every
   public renderer and parser opens and closes its own scope. Genuinely
   unreachable, not merely awkward.")
 (cmark-version-incompatible-compiled
  "Accessor on a condition raised only when the runtime cmark-gfm is outside
   the supported range. An example cannot arrange that without a second,
   deliberately-wrong native library.")
 (cmark-version-incompatible-runtime
  "As above.")
 (cmark-extension-unavailable-name
  "Accessor on a condition raised only when cmark-gfm's registry lacks an
   extension the options record accepted. Unreachable while the pinned
   version ships all five.")
 (cmark-shim-unavailable-path
  "Accessor on a condition raised at import time, before any example code
   runs -- see tests/test-fallback-config.sps, which needs a subprocess for
   exactly this reason.")
 (cmark-shim-unavailable-reason
  "As above.")
 (cmark-render-failed-format
  "Accessor on a condition raised only when a cmark renderer returns NULL,
   which the pinned version does not do for valid input.")
 (cmark-unsupported-node-type
  "Accessor on a condition raised only for a node type the adapter does not
   know. Unreachable while the adapter covers every type the parser emits."))
```

- [ ] **Step 2: Write the failing test**

Create `tests/test-example-coverage.sps`:

```scheme
#!r6rs
;;; Every public export of (cmark gfm) appears in a runnable example.
;;;
;;; This is the gate behind milestone 6's exit criterion -- "a clean machine
;;; exercises every public API from the documentation alone". Adding an export
;;; without documenting it breaks the build.
;;;
;;; Examples are read as DATUMS, not scanned as text. A text scan is satisfied
;;; by an identifier that appears only inside a comment, which documents
;;; nothing; `read` discards comments by construction. One residual gap is
;;; accepted and recorded in the design spec 11: an identifier inside a string
;;; literal still counts. Closing that needs a scope analyzer.
;;;
;;; Pure: imports no library that reaches a shared object, so it runs under
;;; `make check-purity` with CHEZ_CMARK_GFM_SHIM poisoned.
(import (rnrs) (srfi :64))

(define runner (test-runner-simple))
(test-runner-current runner)

(define public-library "src/cmark/gfm.sls")
(define exemptions-file "examples/coverage-exemptions.scm")
(define example-files
  '("examples/01-rendering.sps"
    "examples/02-options.sps"
    "examples/03-ast.sps"
    "examples/04-sxml.sps"
    "examples/05-errors.sps"
    "examples/06-capabilities.sps"))

(define (read-datum path) (call-with-input-file path read))

;; (library <name> (export . names) (import . specs) . body)
(define (library-exports form) (cdr (caddr form)))

(define exports (library-exports (read-datum public-library)))

;; Every symbol appearing anywhere in a datum tree.
(define (symbols-in datum acc)
  (cond
    ((symbol? datum) (if (memq datum acc) acc (cons datum acc)))
    ((pair? datum) (symbols-in (car datum) (symbols-in (cdr datum) acc)))
    ((vector? datum) (symbols-in (vector->list datum) acc))
    (else acc)))

;; Read every datum in a file, not just the first.
(define (file-symbols path acc)
  (call-with-input-file path
    (lambda (port)
      (let loop ((acc acc))
        (let ((d (read port)))
          (if (eof-object? d) acc (loop (symbols-in d acc))))))))

(define used
  (let loop ((fs example-files) (acc '()))
    (if (null? fs) acc (loop (cdr fs) (file-symbols (car fs) acc)))))

(define exemptions (map car (read-datum exemptions-file)))

(test-begin "example-coverage")

;; --- 1. every export is used, or explicitly exempt ---------------------
;; Asserts the offending NAMES, not a count: a failure has to say which
;; export is undocumented, or the next person cannot act on it. '() is a
;; value the failing path cannot produce, since it lists symbols.
(test-equal "every public export appears in an example or is exempt"
  '()
  (let loop ((es exports) (missing '()))
    (cond
      ((null? es) (reverse missing))
      ((or (memq (car es) used) (memq (car es) exemptions))
       (loop (cdr es) missing))
      (else (loop (cdr es) (cons (car es) missing))))))

;; --- 2. no exemption is stale ------------------------------------------
(test-equal "no exemption names an identifier an example actually uses"
  '()
  (let loop ((xs exemptions) (stale '()))
    (cond
      ((null? xs) (reverse stale))
      ((memq (car xs) used) (loop (cdr xs) (cons (car xs) stale)))
      (else (loop (cdr xs) stale)))))

;; --- 3. no exemption is a typo -----------------------------------------
(test-equal "every exemption names a real export"
  '()
  (let loop ((xs exemptions) (bogus '()))
    (cond
      ((null? xs) (reverse bogus))
      ((memq (car xs) exports) (loop (cdr xs) bogus))
      (else (loop (cdr xs) (cons (car xs) bogus))))))

;; --- 4. the reader found something at all ------------------------------
;; Seeds the guard against the whole suite passing vacuously: if a path were
;; wrong, `used` and `exports` would both be empty and assertions 1-3 would
;; all pass on empty lists.
(test-assert "the export list is non-empty"
  (> (length exports) 50))
(test-assert "the examples yielded symbols"
  (> (length used) 50))

(test-end "example-coverage")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 3: Run it**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps
```

Expected: PASS, 5 expected passes. If assertion 1 fails, it names the undocumented exports — add each to the relevant example (preferred) or to the exemption list *with a real reason*. Do not pad the exemption list to get green.

- [ ] **Step 4: Verify the gate has teeth — three mutations**

```bash
# (a) an export used by no example
sed -i.bak 's/          supported-extensions/          supported-extensions\n          a-brand-new-export/' src/cmark/gfm.sls
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps; echo "exit=$?"
mv src/cmark/gfm.sls.bak src/cmark/gfm.sls

# (b) a stale exemption -- markdown->html is used by 01
sed -i.bak 's/^((&cmark-error/((markdown->html "bogus reason")\n (\&cmark-error/' examples/coverage-exemptions.scm
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps; echo "exit=$?"
mv examples/coverage-exemptions.scm.bak examples/coverage-exemptions.scm

# (c) an exemption for something not exported
sed -i.bak 's/^((&cmark-error/((not-an-export "typo")\n (\&cmark-error/' examples/coverage-exemptions.scm
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-example-coverage.sps; echo "exit=$?"
mv examples/coverage-exemptions.scm.bak examples/coverage-exemptions.scm
```

Expected: (a) fails naming `a-brand-new-export`; (b) fails naming `markdown->html` as stale; (c) fails naming `not-an-export`. Each `exit=1`. Then confirm a clean run passes.

Mutation (a) will also make `make build` fail, because `gfm.sls` exports an unbound identifier — that is fine, it is a scratch mutation, but run the coverage suite directly as shown rather than through `make test`.

- [ ] **Step 5: Add it to check-purity**

In `Makefile`, line 244, add the suite to the purity list:

```make
	for t in tests/test-options.sps tests/test-ast.sps tests/test-sxml.sps tests/test-example-coverage.sps; do \
```

- [ ] **Step 6: Run everything**

```bash
make test && make check-purity
```

Expected: `ALL SUITES PASSED`, then four `purity holds` lines.

- [ ] **Step 7: Commit**

```bash
git add tests/test-example-coverage.sps examples/coverage-exemptions.scm Makefile
git commit -m "test: gate every public export on appearing in an example

Reads gfm.sls's export list and each example as datums -- not as text, so a
mention inside a comment does not count. Exemptions carry reasons and are
themselves checked for staleness and typos. Confirmed to fail on an
undocumented export, a stale exemption, and a misspelled one."
```

---

### Task 7: The stress suite

**Files:**
- Create: `tests/test-stress.sps`
- Modify: `Makefile` (lower iterations under `test-memory`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing later tasks depend on. Reads `CMARK_STRESS_ITERATIONS` from the environment, default 50.

- [ ] **Step 1: Write the suite**

Create `tests/test-stress.sps`:

```scheme
#!r6rs
;;; Stress: accumulation, which nothing else here tests.
;;;
;;; Every counter assertion elsewhere in the suite is single-shot. A leak of
;;; one buffer per call satisfies all of them and fails this on iteration two.
;;; That is plan 17's renderer-buffer-leak risk, tested across iterations
;;; rather than once.
;;;
;;; Limit BOUNDARIES are deliberately not retested here. They are already
;;; covered: depth at tests/test-convert.sps:266-269 and again through the
;;; options record at 571-576, node count at 275-283, and max-input-bytes at
;;; tests/test-lifecycle.sps:211-221. Re-asserting them would add runtime and
;;; no coverage. The pathological documents below run UNDER the limits, so
;;; they exercise robustness rather than rejection.
;;;
;;; Iteration count comes from the environment (12-factor). It must stay low
;;; by default: this file joins MEMORY_TESTS automatically, and Valgrind is
;;; roughly two orders of magnitude slower.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv)
        (cmark gfm)
        (cmark gfm private native))

(define runner (test-runner-simple))
(test-runner-current runner)

(define iterations
  (let ((raw (getenv "CMARK_STRESS_ITERATIONS")))
    (or (and raw (string->number raw)) 50)))

(define opts (default-cmark-options))

;; Documents that are awkward but legal. Depth 100 and this node count are
;; well inside the defaults (max-depth 1000, max-nodes 250000).
(define deep-quotes
  (string-append (apply string-append
                        (map (lambda (i) "> ") (iota 100)))
                 "deep\n"))
(define deep-emphasis
  (string-append (make-string 60 #\*) "x" (make-string 60 #\*) "\n"))
(define wide-table
  (string-append
   "| " (apply string-append (map (lambda (i) "h | ") (iota 40))) "\n"
   "| " (apply string-append (map (lambda (i) "--- | ") (iota 40))) "\n"
   "| " (apply string-append (map (lambda (i) "c | ") (iota 40))) "\n"))
(define long-line
  (string-append (apply string-append (map (lambda (i) "word ") (iota 4000))) "\n"))

(define documents (list deep-quotes deep-emphasis wide-table long-line))

;; Every public path that acquires a native resource.
(define (exercise-all doc)
  (markdown->html       doc opts)
  (markdown->commonmark doc opts 72)
  (markdown->plaintext  doc opts 72)
  (markdown->xml        doc opts)
  (markdown->ast        doc opts)
  (markdown->sxml       doc opts))

;; live-counts is exported by (cmark gfm private native) and already returns
;; (list (live-parsers) (live-roots) (live-buffers)) -- native.sls:278. Do not
;; redefine it here; tests/test-lifecycle.sps calls the same procedure, so a
;; second spelling would drift from it.

(test-begin "stress")

;; A seeded control. If the counters were unavailable -- a prod shim freezes
;; them at zero -- every assertion below would pass vacuously, so establish
;; that they MOVE before asserting that they return.
(test-assert "the counters are instrumented in this build"
  (let ((before (live-counts)))
    (and (equal? before '(0 0 0))
         (begin (exercise-all "# probe\n") #t))))

(test-equal "counters are zero before the loop"
  '(0 0 0) (live-counts))

;; The point of the suite: nothing accumulates. Checked after EVERY iteration,
;; not just at the end, so a failure names the iteration it first appeared in.
(test-equal "no native resource accumulates across iterations"
  'balanced
  (let loop ((i 0))
    (cond
      ((= i iterations) 'balanced)
      (else
       (for-each exercise-all documents)
       (if (equal? (live-counts) '(0 0 0))
           (loop (+ i 1))
           (list 'leaked-at-iteration i (live-counts)))))))

(test-equal "counters are zero after the loop"
  '(0 0 0) (live-counts))

(test-end "stress")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

**Note:** `live-counts` comes from `(cmark gfm private native)` (defined at `native.sls:278`, exported at `native.sls:18`) and returns a three-element list — parsers, roots, buffers. `tests/test-lifecycle.sps` calls the same procedure; that is the one to use.

- [ ] **Step 2: Run it**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-stress.sps
```

Expected: PASS, 4 expected passes. Time it — if it exceeds a few seconds, lower the default iteration count.

- [ ] **Step 3: Verify it catches a leak**

The mutation this suite exists for. In a scratch copy outside the repo, remove one `free-buffer` call from the render path, then run against it:

```bash
S=/tmp/stress-mutation
rm -rf $S && mkdir -p $S && cp -R src $S/src
rg -n 'free-buffer' $S/src/cmark/gfm/private/scope.sls
# Comment out the single free-buffer call the render path makes, then:
CHEZSCHEMELIBDIRS=$S/src:fallback:tests:build/scheme-libs chez --program tests/test-stress.sps; echo "exit=$?"
rm -rf $S
```

Expected: FAIL on `no native resource accumulates across iterations`, whose actual value is `(leaked-at-iteration 0 (0 0 N))` naming the iteration and the counter. `exit=1`. This is the assertion's whole purpose — do not proceed until you have seen it fail this way.

- [ ] **Step 4: Lower the iteration count under Valgrind**

In `Makefile`, in the `test-memory` Linux branch, add the variable to the loop's environment:

```make
	@for t in $(MEMORY_TESTS); do \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) CMARK_CLI=$(CMARK_CLI) \
	    CMARK_STRESS_ITERATIONS=2 valgrind --error-exitcode=9 \
	    --leak-check=full --show-leak-kinds=definite \
	    $(CHEZ) --program $$t || exit 1; \
	done
```

Do the same for the macOS ASan branch's loop (around line 402), adding `CMARK_STRESS_ITERATIONS=2` to that command's environment.

- [ ] **Step 5: Run the memory target**

```bash
make test-memory
```

Expected: passes, and the stress suite does not dominate the runtime. On macOS this is ASan only and supports no leak claim (ADR-0003).

- [ ] **Step 6: Commit**

```bash
git add tests/test-stress.sps Makefile
git commit -m "test: assert nothing accumulates across repeated renders

Every counter assertion here was single-shot, so a per-call leak of one
buffer passed all of them. Checks the live counts after every iteration,
reporting which iteration first leaked. Confirmed to fail with
(leaked-at-iteration 0 ...) against a shim missing one free-buffer call.

Iteration count is CMARK_STRESS_ITERATIONS, dropped to 2 under the memory
targets where Valgrind is ~100x slower."
```

---

### Task 8: The support matrix and its check

**Files:**
- Create: `packaging/debian-prereqs.txt`
- Modify: `README.org:14-25` (Prerequisites)
- Modify: `.github/workflows/ci.yml` (a check step in each of the two existing jobs)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `packaging/debian-prereqs.txt`, which Task 10's clean-install job installs from.

- [ ] **Step 1: Write the prerequisite list**

Create `packaging/debian-prereqs.txt`:

```text
# Debian/Ubuntu packages needed to build and test chez-cmark-gfm.
# ONE copy, deliberately: README.org points at this file instead of
# restating the list, and .github/workflows/ci.yml installs from it. A list
# in two places drifts; a list in one place cannot.
# Lines starting with # and blank lines are ignored.
chezscheme
cmake
pkg-config
build-essential
```

Note `valgrind` is absent: it is needed by the memory job, not to build or use the library. The linux CI job installs it separately.

- [ ] **Step 2: Replace the README prerequisites**

In `README.org`, replace the Chez bullet at line 16. Keep this terse — depth belongs in a later `docs/` tree.

```org
** Prerequisites

- *Chez Scheme* 9.5.8 or later. The binary is ~chez~ on macOS and
  ~chezscheme~ on Debian/Ubuntu.
- *cmark-gfm*, in the ~0.29.0.gfm.x~ range, pinned to ~0.29.0.gfm.13~.
- On Debian/Ubuntu, the packages in [[file:packaging/debian-prereqs.txt][packaging/debian-prereqs.txt]] — the same
  list CI installs from. On macOS: ~brew install chezscheme cmark-gfm cmake pkg-config~.

*** Supported matrix

Two rows, because two rows are what CI proves. Both acquisition paths
(ADR-0001) are exercised on each.

| Platform              | Chez   | Memory evidence                  |
|-----------------------+--------+----------------------------------|
| macOS/ARM64 (Homebrew)| 10.4.1 | ASan only — *no leak claim*      |
| Linux/x86-64 (apt)    | 9.5.8  | Valgrind clean                   |

The floor is *9.5.8*, established by test rather than assumption: earlier
revisions of this file said "10.4.1 or later", which recorded one
developer's machine and was never verified. LeakSanitizer does not exist on
macOS/ARM64, so only the Linux row can support a leak claim (ADR-0003).

A CI step asserts this table against the versions each job actually ran, so
a runner-image bump fails the build until the table is updated rather than
letting the claim go stale.
```

Then update the `cmark-gfm` bullet's existing prose about `cmark-supported-version-range` to sit under it unchanged — do not delete that detail, only the Chez claim changes.

- [ ] **Step 3: Add the CI matrix check to the linux job**

In `.github/workflows/ci.yml`, in the **linux** job, after the existing `Report versions` step:

```yaml
      # The README matrix decays silently the moment a runner image bumps
      # Chez. This makes that a build failure instead. Deliberately asserts
      # agreement with what THIS run used -- it does not pin a version, which
      # would fight the "recorded rather than asserted" note above.
      - name: Check the README matrix names the Chez this job ran
        run: |
          set -eu
          actual=$( (chezscheme --version 2>&1 || scheme --version 2>&1) | tr -d '[:space:]')
          echo "this job ran Chez: $actual"
          if ! rg -qF "| Linux/x86-64 (apt)    | $actual" README.org; then
            echo "::error::README.org's matrix does not name Chez $actual for the Linux row."
            echo "Update the 'Supported matrix' table in README.org to match, or"
            echo "pin the toolchain. The documented floor must be one CI actually ran."
            rg -n 'Linux/x86-64' README.org || true
            exit 1
          fi
```

- [ ] **Step 4: Add the equivalent to the macos job**

```yaml
      - name: Check the README matrix names the Chez this job ran
        run: |
          set -eu
          actual=$(chez --version 2>&1 | tr -d '[:space:]')
          echo "this job ran Chez: $actual"
          if ! rg -qF "| macOS/ARM64 (Homebrew)| $actual" README.org; then
            echo "::error::README.org's matrix does not name Chez $actual for the macOS row."
            echo "Update the 'Supported matrix' table in README.org to match."
            rg -n 'macOS/ARM64' README.org || true
            exit 1
          fi
```

- [ ] **Step 5: Verify the check locally against your own machine**

```bash
chez --version
rg -n 'macOS/ARM64' README.org
```

Confirm the version string in the table matches your `chez --version` output exactly, allowing for the whitespace stripping. If it does not, fix the table — this is the check working, before CI ever runs it. `rg` is required (not `grep`) per the repo convention, and `rg -F` is a literal match so the table's `|` characters need no escaping.

- [ ] **Step 6: Commit**

```bash
git add packaging/debian-prereqs.txt README.org .github/workflows/ci.yml
git commit -m "docs: replace the unverified Chez floor with the CI-proven matrix

README claimed 'Chez Scheme 10.4.1 or later', which recorded one machine's
version and was never tested; the tested floor is 9.5.8 (design spec 1.2).
A CI step now asserts the table against the Chez each job actually ran, so a
runner-image bump fails the build instead of quietly invalidating the claim.

Prerequisites live in packaging/debian-prereqs.txt with exactly one copy,
which the README points at and CI installs from."
```

---

### Task 9: Ownership, linking, licensing, and the Akku caveat

**Files:**
- Create: `NOTICE`
- Modify: `README.org` (three new sections)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the NOTICE file**

Plan §14 requires license notices for the binding *and* its native dependency.

```bash
{
  echo "chez-cmark-gfm"
  echo "=============="
  echo
  echo "Copyright (c) 2026, Kiyomi Computation Systems LLC."
  echo "Licensed under the BSD 3-Clause License; see LICENSE."
  echo
  echo
  echo "This package binds cmark-gfm, which carries its own license."
  echo "cmark-gfm is not distributed with this package: it is either found"
  echo "via pkg-config or built from the pinned vendor/cmark-gfm submodule"
  echo "(ADR-0001). Its notice is reproduced here in full."
  echo
  echo "cmark-gfm"
  echo "---------"
  echo
  cat vendor/cmark-gfm/COPYING
} > NOTICE
head -20 NOTICE
```

Expected: the header, then `Copyright (c) 2014, John MacFarlane`. If `vendor/cmark-gfm/COPYING` is absent, run `git submodule update --init --recursive` first.

- [ ] **Step 2: Add the ownership section to README.org**

Insert after the `Usage` section's options table. Terse — the contract, not the rationale.

```org
** Memory ownership

The contract a caller depends on. Rationale is in the design spec §5.

- ~markdown->ast~ returns *only Scheme-owned objects*. No native pointer is
  reachable from the result, and the tree stays valid after the native
  document is freed.
- Every borrowed native string is copied before the document it came from is
  cleaned up.
- A native document is dead outside its own scope; touching one raises
  ~&cmark-dead-document~. No public entry point exposes a live document, so
  a caller cannot reach that condition.
- Renderer buffers are copied into Scheme strings and freed exactly once, on
  the success and the failure path alike.
- Parsers, roots, and extension-list containers have one owner each and are
  freed exactly once.
```

- [ ] **Step 3: Add the linking section to README.org**

Insert immediately after the `Build` section. Plan §14 requires this and the README has never had it.

```org
** Static versus dynamic linking

Both acquisition paths link *dynamically*, and there is no static option.

The vendored path builds ~cmark-gfm~ as shared libraries and links the shim
against them with an explicit ~-Wl,-rpath~ to each — an absolute path
recorded at build time, not a system-path search (plan §10.7).

Static linking is *impossible* here, not merely unchosen. ~cmark-gfm~ builds
its static archives with ~CMAKE_C_VISIBILITY_PRESET hidden~ and
~CMARK_GFM_STATIC_DEFINE~, which hides every cmark symbol from whatever links
them; ADR-0002 puts AST traversal in Scheme, so Scheme resolves cmark's entry
points directly at runtime via ~foreign-procedure~. A statically-linked shim
exports none of them. See ADR-0001, amended.
```

- [ ] **Step 4: Add the install-and-packaging note to README.org**

Insert after the `Build` section's existing `HAVE_PKG=no` block.

```org
** Installing

Clone and build. That is the supported install for this release:

#+begin_src sh
git clone --recursive <repo> && cd chez-cmark-gfm && make build
#+end_src

then put ~src~ and ~fallback~ on Chez's library path:
~CHEZSCHEMELIBDIRS=src:fallback~.

~Akku.manifest~ declares this package's libraries and its (development-only)
dependencies, and ~Akku.lock~ is committed. *Akku is not a supported install
path yet:* it distributes Scheme source and cannot build the native shim, so
an ~akku install~ leaves a tree that has no compiled shim and no generated
~config.sls~. Such a tree fails with ~&cmark-shim-unavailable~ and reason
~not-built~ — which names the remedy rather than reporting a missing library —
and ~make build~ in a cloned tree is the remedy. See ADR-0014.

One asymmetry worth knowing if you point ~CHEZ_CMARK_GFM_SHIM~ at a prebuilt
shim in an *unbuilt* tree: it works on macOS and fails on Linux, whose loader
does not put a dlopen'd library's dependencies in the global symbol
namespace, and the fallback configuration names no cmark libraries to load
first.
```

- [ ] **Step 5: Verify the README still exports and reads cleanly**

```bash
rg -n '10\.4\.1 or later' README.org && echo "STALE CLAIM STILL PRESENT" || echo "good: unverified floor is gone"
rg -c '^\*\* ' README.org
```

Expected: `good: unverified floor is gone`. The section count rises by three from Task 8's baseline.

- [ ] **Step 6: Commit**

```bash
git add NOTICE README.org
git commit -m "docs: document ownership, linking, licensing, and the install path

Closes three plan 14 requirements the README had never met: the static
versus dynamic linking behavior (static is impossible, not unchosen -- see
ADR-0001 amended), a license notice for the native dependency, and the
memory-ownership contract.

States plainly that Akku is not yet a supported install path, and what an
unbuilt tree does instead."
```

---

### Task 10: The clean-machine CI job

**Files:**
- Modify: `.github/workflows/ci.yml` (one new job)

**Interfaces:**
- Consumes: `packaging/debian-prereqs.txt` (Task 8), `make examples` (Task 4), the fallback config (Task 2).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the job**

Append to `.github/workflows/ci.yml`, at the same indentation as the existing `linux` and `macos` jobs. Note the ordering: the prerequisite list lives in the repository, so checkout has to come before the step that reads it, and a bare container has no `git` until one is installed.

```yaml
  clean-install:
    name: clean machine (documented steps only)
    runs-on: ubuntu-latest
    # A bare container, NOT the runner image. ubuntu-latest arrives with a
    # toolchain, git, and build tools already present, so building there
    # proves nothing about a clean machine -- which is exactly what
    # milestone 6's exit criterion is about. This job runs only what the
    # README tells a reader to run.
    container: ubuntu:24.04
    steps:
      # A bare container has no git, so checkout cannot run yet. This is the
      # only thing installed that the README does not list, and it is needed
      # to obtain the repository at all rather than to build it.
      - name: Bootstrap enough to check out
        run: |
          set -eu
          apt-get update -qq
          apt-get install -y --no-install-recommends git ca-certificates

      - uses: actions/checkout@v4
        with:
          submodules: recursive

      # The SAME list README.org points readers at -- one copy, so this
      # cannot drift from the documentation. Must follow checkout, which is
      # what puts the file on disk.
      - name: Install the documented prerequisites
        run: |
          set -eu
          apt-get install -y --no-install-recommends \
            $(grep -v '^#' packaging/debian-prereqs.txt | grep -v '^$' | tr '\n' ' ')

      - name: Report versions
        run: |
          echo "chez: $(chezscheme --version 2>&1)"
          echo "cc:   $(cc --version | head -1)"

      # Before building anything: an unbuilt tree must name its own remedy.
      # This is the one place that runs on a machine which is GENUINELY
      # unbuilt rather than synthetically so.
      - name: An unbuilt tree raises not-built, not a missing library
        run: |
          set -eu
          if CHEZSCHEMELIBDIRS=src:fallback chezscheme --script tests/shim-load-probe.sps \
               > probe.out 2> probe.err; then
            echo "::error::an unbuilt tree loaded the shim; it must not"
            exit 1
          fi
          cat probe.err
          grep -q 'cmark-shim-unavailable' probe.err || {
            echo "::error::an unbuilt tree did not raise cmark-shim-unavailable"; exit 1; }
          grep -q 'not-built' probe.err || {
            echo "::error::an unbuilt tree did not report reason not-built"; exit 1; }
          if grep -q 'library (cmark gfm private config) not found' probe.err; then
            echo "::error::an unbuilt tree still reports a missing library"
            exit 1
          fi

      # CHEZ=chezscheme because Debian names the binary that way and the
      # Makefile defaults to `chez`.
      - name: Build, exactly as the README says
        run: make CHEZ=chezscheme build

      # No `make deps`, deliberately. The examples must run with
      # CHEZSCHEMELIBDIRS=src:fallback and no dev dependency whatsoever;
      # omitting deps here is what makes that falsifiable.
      - name: Run every documented example
        run: make CHEZ=chezscheme examples
```

- [ ] **Step 2: Confirm the job's own assumptions**

Three things in that job are easy to get wrong and cheap to check before pushing:

```bash
rg -n 'shim-load-probe' Makefile tests/test-shim-loading.sps | head -3
test -f packaging/debian-prereqs.txt && echo "prereqs list present"
grep -v '^#' packaging/debian-prereqs.txt | grep -v '^$' | tr '\n' ' '
```

Expected: `tests/shim-load-probe.sps` exists and is not matched by `make test`'s `tests/test-*.sps` wildcard (its name deliberately does not start with `test-`); the prereqs file is present; and the package list expands to `chezscheme cmake pkg-config build-essential`.

- [ ] **Step 3: Reproduce the job locally before pushing**

CI feedback loops are slow, and this job has several ways to fail that have nothing to do with the library. Run it in Docker first if available:

```bash
docker run --rm -v "$PWD:/w" -w /w ubuntu:24.04 bash -c '
  set -eu
  apt-get update -qq
  apt-get install -y --no-install-recommends git ca-certificates >/dev/null
  apt-get install -y --no-install-recommends \
    $(grep -v "^#" packaging/debian-prereqs.txt | grep -v "^$" | tr "\n" " ") >/dev/null
  chezscheme --version
  CHEZSCHEMELIBDIRS=src:fallback chezscheme --script tests/shim-load-probe.sps 2>&1 | head -6
'
```

Expected: the Chez version, then an uncaught `&cmark-shim-unavailable` report containing `reason: not-built`. Note the mounted tree may already contain a built `config.sls` from your host — run `make clean` first, or accept that this local reproduction only checks the prerequisites install and skip to CI for the unbuilt-tree assertion.

If Docker is unavailable, say so when reporting and rely on CI.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: execute the documented install on a genuinely clean machine

Milestone 6's exit criterion is that a clean machine installs and exercises
every public API from the documentation alone. This job runs only what the
README says, in a bare ubuntu:24.04 container rather than the runner image,
which arrives with a toolchain already present.

It never runs make deps, which is what makes 'a consumer needs no dev
dependency' falsifiable, and it asserts the unbuilt-tree diagnostic on a
machine that is genuinely unbuilt."
```

---

### Task 11: The plan §16 acceptance audit

Plan §16's fifteen criteria are the stated bar for 1.0 and have never been checked as a set. This task turns the design spec's `verify` rows into evidence.

**Files:**
- Modify: `.plans/2026-08-18-stage-6-packaging-design.md` §8 (the audit table)

**Interfaces:**
- Consumes: everything from Tasks 1-10.
- Produces: a completed audit. **Any criterion found unmet becomes new work in this stage** — add a task for it rather than shipping past it.

- [ ] **Step 1: Establish a clean baseline**

```bash
make clean && make build && make deps && make check-pins && make check-config \
  && make check-purity && make test && make examples
```

Expected: every target green, `ALL SUITES PASSED`, `ALL EXAMPLES PASSED`.

- [ ] **Step 2: Locate the evidence for each criterion**

For each of the fifteen rows in the design spec's §8 table, find the assertion that proves it and record the file and line. Use `rg`. For example:

```bash
rg -n 'unsafe' tests/test-render.sps | head            # criterion 3
rg -n 'live-|counter' tests/test-lifecycle.sps | head  # criteria 4, 7
rg -n 'after|post-free|freed' tests/test-ast.sps | head # criterion 5
rg -n 'embedded-nul' tests/test-lifecycle.sps          # criterion 8
rg -n 'javascript:|data:' tests/test-sxml.sps | head   # criterion 11
rg -n 'version-incompatible' tests/test-native.sps     # criterion 12
```

- [ ] **Step 3: Rewrite the table with evidence, not expectations**

Replace each `verify` in the design spec's §8 table with either an exact `file:line` citation, or `UNMET` and one sentence saying what is missing. Change the table's preamble from "Rows marked `verify` are unconfirmed at design time" to a statement of what the audit found, and date it.

Criterion 14 is met by Task 8. Criterion 8's documentation half — "UTF-8 handling is documented" — needs a README check: confirm UTF-8 behavior is stated, and add a terse sentence if it is not.

- [ ] **Step 4: Handle any unmet criterion**

If a criterion has no assertion behind it, do not paper over it. Add a task to this plan that writes the missing test, with its own mutation, and report the gap when you report this task. That is the audit doing its job.

- [ ] **Step 5: Commit**

```bash
git add .plans/2026-08-18-stage-6-packaging-design.md
git commit -m "docs: complete the plan 16 acceptance-criteria audit

Each of the fifteen 1.0 criteria now cites the assertion that proves it, or
is marked UNMET with what is missing. Replaces the design-time expectations
with what the code actually shows."
```

---

### Task 12: Release 1.0.0

**Files:**
- Create: `.plans/decisions/0014-fallback-config-shadowing.md`
- Modify: `Akku.manifest`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Tasks 1-11 complete and green.
- Produces: release 1.0.0.

- [ ] **Step 1: Write ADR-0014**

Create `.plans/decisions/0014-fallback-config-shadowing.md`:

```markdown
# ADR-0014: Ship a checked-in fallback config, shadowed by the generated one

- **Status:** Accepted
- **Date:** 2026-08-18
- **Scope:** chez-cmark-gfm 1.0
- **Related:** [Stage 6 design](../2026-08-18-stage-6-packaging-design.md) · ADR-0001, ADR-0002

## Context

`make build` generates `src/cmark/gfm/private/config.sls`, holding the shim's absolute
path, the cmark shared-object paths, and the supported version range. It is gitignored
and carries a "do not commit" banner, because every value in it is machine-specific.

A tree that has not been built therefore fails at import with:

```text
Exception: library (cmark gfm private config) not found
```

which names no cause and no remedy, and is not a condition a caller can `guard`. It is
also what any future `akku install` would produce, since Akku distributes Scheme source
and cannot run a C compiler.

## Decision

Check in a second `(cmark gfm private config)` under `fallback/`, and put `src` ahead of
`fallback` on `CHEZSCHEMELIBDIRS`. Chez resolves a library from the first entry that has
it, so the generated file shadows the fallback whenever a build has happened.

The fallback's `shim-path` is `#f` — not a string. No build can produce a non-string
there, so `resolve-shim-path` distinguishes "never built" from "built, but the shim has
since gone missing" without either case guessing. `&cmark-shim-unavailable` gains a
`reason` field, and the fallback's case is `'not-built`.

Two alternatives were rejected:

- **Commit `config.sls` and let `make build` overwrite it.** Zero mechanism, and
  `CHEZSCHEMELIBDIRS=src` would stay as documented. But every build then leaves a
  modified tracked file holding a machine-specific absolute path, and `make clean`
  becomes `git checkout`. This repo has already lost a submodule pin to that class of
  accident, which is why `check-pins` exists; a second one is not worth the saved
  directory.
- **Read the configuration at runtime**, with no generated library at all. This is the
  right eventual shape and is recorded below as the successor, but it rewrites the load
  path Stage 1 built and Valgrind-proved, in the release meant to freeze the API.

## Consequences

- Two files declare `(cmark gfm private config)`, and nothing else would notice them
  diverging. `make check-config` compares library name, export set, and version range,
  and runs in CI right after `make build`.
- The documented library path gains an entry: `CHEZSCHEMELIBDIRS=src:fallback`.
- Reversing those two entries breaks every native suite against a good build.
  `tests/test-fallback-config.sps` asserts the ordering directly.
- The fallback names no cmark libraries, so `CHEZ_CMARK_GFM_SHIM` in an unbuilt tree
  works on macOS and fails on Linux, whose loader does not put a dlopen'd library's
  dependencies in the global symbol namespace. Documented in the README, not fixed.
- Akku installation becomes *diagnosable* rather than supported. 1.0 claims clone plus
  `make build` and nothing more.

## Successor

Making an Akku install actually work means configuration read at runtime rather than
generated into the source tree: shim path and cmark library paths from the environment
or a config file, resolved and validated at load time. That is a second config
mechanism with its own security surface — it loads shared objects named by the
environment — and it deserves its own ADR and its own stage rather than a bolt-on here.
```

- [ ] **Step 2: Bump the manifest**

In `Akku.manifest`, change the version:

```scheme
(akku-package ("chez-cmark-gfm" "1.0.0")
```

- [ ] **Step 3: Write the CHANGELOG entry**

Prepend to `CHANGELOG.md` after the header, matching the existing entries' voice — each states what changed and *why*, with the reasoning that is not recoverable from the diff.

```markdown
## [1.0.0] — 2026-08-18

Packaging, documentation, and release. No parsing, rendering, or mapping
behavior changed: 1.0 freezes the API. The one public-API change is additive.

### Added

- **`examples/`** — six runnable programs covering rendering, options, the
  AST, SXML, the condition family, and capability inspection. `make examples`
  runs each and diffs its output. It sets `CHEZSCHEMELIBDIRS=src:fallback` and
  nothing else, so an example that reached a dev dependency breaks the build —
  which is what keeps 0.3.0's "a consumer acquires neither" true rather than
  merely written down.
- **`tests/test-example-coverage.sps`** — fails when `(cmark gfm)` gains an
  export that appears in no example. It reads the export list and each example
  as *datums*, not text, so an identifier mentioned only in a comment does not
  count. Exemptions carry a reason each and are themselves checked for
  staleness and typos; today they cover the condition type names, which are not
  first-class values, and the accessors on conditions no public entry point can
  raise.
- **`tests/test-stress.sps`** — asserts the live parser, root, and buffer
  counts return to zero after *every* iteration of a repeated
  parse/render/AST/SXML loop. Every counter assertion before this was
  single-shot, so a per-call leak of one buffer satisfied all of them.
  `CMARK_STRESS_ITERATIONS` tunes the count; the memory targets drop it to 2.
- **`fallback/cmark/gfm/private/config.sls`** — a checked-in configuration,
  shadowed by the generated one whenever a build has happened. See below.
- **`NOTICE`** — the binding's BSD-3 alongside cmark-gfm's own BSD-2, which
  plan §14 requires and this repository lacked.
- **A clean-machine CI job** in a bare `ubuntu:24.04` container that runs only
  the steps the README documents. It never runs `make deps`.
- **`make check-config`** and **`make examples`**.

### Changed

- **`&cmark-shim-unavailable` carries a `reason`**: `not-built`, `missing`,
  `invalid-override`, or `load-failed`. Four distinct failures previously
  shared one field, so a caller could not tell a missing build from a bad
  `CHEZ_CMARK_GFM_SHIM`. Additive for existing `guard` clauses. Mirrors
  `&cmark-invalid-option`'s `key` + `reason` pair.
- **An unbuilt tree now names its own remedy.** It used to fail with
  `library (cmark gfm private config) not found`, which names no cause and is
  not a condition; it now raises `&cmark-shim-unavailable` with reason
  `not-built`. The fallback's `shim-path` is `#f` rather than a plausible fake
  path, because no build can produce a non-string there — which is what keeps
  "never built" distinguishable from "shim deleted since". See ADR-0014.
- **`CHEZSCHEMELIBDIRS` is now `src:fallback`.** The order is the mechanism:
  Chez resolves a library from the first entry that has it.
- **The documented Chez floor is 9.5.8, not 10.4.1.** The old claim recorded
  one developer's machine and was never tested; 9.5.8 is what Ubuntu CI runs
  green under Valgrind. A CI step now asserts the README matrix against the
  version each job actually ran, so a runner-image bump fails the build rather
  than letting the claim go stale.

### Fixed

- **Four empty assertions in `tests/test-native.sps`.** Each expected exactly
  the path `resolve-shim-path` *returns on success*, so all four passed against
  code with every rejection deleted — verified: 54 of 54, exit 0. They now
  assert `(path reason)`, a shape no success path here produces, and each
  `guard` body ends in `'no-condition`.

### Documentation

- The supported platform/Chez/cmark matrix, the memory-ownership contract, and
  the static-versus-dynamic linking behavior (static linking is *impossible*
  here, not merely unchosen — cmark's static archives hide every symbol that
  ADR-0002 requires Scheme to resolve at runtime). All three are plan §14
  requirements the README had never met.
- Prerequisites live in `packaging/debian-prereqs.txt` in exactly one copy,
  which the README points at and CI installs from.
- Akku is documented as *not yet* a supported install path, with what an
  unbuilt tree does instead. README additions are deliberately terse; in-depth
  documentation is deferred to a `docs/` tree.
```

- [ ] **Step 4: Run everything from clean**

```bash
make clean && make build && make deps && make check-pins && make check-config \
  && make check-purity && make test && make examples && make test-memory
```

Expected: all green. Do not proceed on a single failure.

- [ ] **Step 5: Commit and open the PR**

```bash
git add .plans/decisions/0014-fallback-config-shadowing.md Akku.manifest CHANGELOG.md
git commit -m "chore: release 1.0.0

Milestone 6. ADR-0014 records the fallback-config decision and names
runtime-read configuration as its successor."
git push -u origin feat/stage-6-packaging-release
gh pr create --title "Stage 6: packaging, documentation, and release (1.0)" --body "$(cat <<'BODY'
Milestone 6 per ADR-0007. No parsing, rendering, or mapping behavior changed;
1.0 freezes the API. The one public-API change is an additive `reason`
accessor on `&cmark-shim-unavailable`.

## What this fixes

An unbuilt tree failed with `library (cmark gfm private config) not found` —
no cause, no remedy, not a condition. It now raises `&cmark-shim-unavailable`
with reason `not-built`.

Four assertions in `tests/test-native.sps` were empty: each expected exactly
the path `resolve-shim-path` returns on success. Deleting every rejection left
the suite at 54/54, exit 0.

The README claimed a Chez floor of 10.4.1 that was never tested. The tested
floor is 9.5.8.

## What now cannot regress silently

- `make check-config` — the fallback and generated configs must agree
- `tests/test-example-coverage.sps` — no public export without an example
- `tests/test-stress.sps` — nothing accumulates across repeated renders
- `make examples` — examples run with no dev dependency on the path
- a CI matrix check — the documented versions are the ones CI ran
- a clean-machine job — the documented install works from nothing

## Verification

`make clean && make build && make deps && make check-pins && make check-config
&& make check-purity && make test && make examples && make test-memory`, plus
each new assertion watched failing under its own mutation (AGENTS.md).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

- [ ] **Step 6: Close out, after review and merge**

The closing ritual, all four parts, in order. A squash merge leaves the branch unreachable by ancestry, so `git branch -d` refuses it — diff against `main` first to confirm nothing unique is being dropped, then use `-D`.

```bash
git checkout main && git pull
git diff main feat/stage-6-packaging-release --stat   # expect: empty
git branch -D feat/stage-6-packaging-release
```

Then the tags. `v0.1.0` is the only tag today, against three shipped CHANGELOG releases, so the two missing ones are added retroactively at their release commits before 1.0.0:

```bash
git tag v0.2.0 d26aea9
git tag v0.3.0 ad0d853
git tag v1.0.0
git push origin v0.2.0 v0.3.0 v1.0.0
```

No Akku archive publish, and no GitHub Release — both deliberately out of scope.

Finally, reflect: a retrospective on the stage, not a summary of what was done.

---

### Task 13: Mutation evidence

AGENTS.md: a test is finished when you have watched it fail. This task is the collection point — every mutation below must have been run, and its predicted failure observed, before 1.0 ships. Several are specified inside their own tasks; this table is the checklist.

- [ ] **Step 1: Confirm each mutation was run and produced the predicted, named failure**

| Mutation | Must break | Task |
|---|---|---|
| Delete every rejection in `resolve-shim-path` | the four `(path reason)` assertions — **already run: 54/54 before the fix, so this is the regression baseline** | 1 |
| Fallback `shim-path` `#f` → a real built shim path | `an unbuilt tree reports reason not-built` | 2 |
| Delete `resolve-shim-path`'s `not-built` clause | same assertion, via a loader error | 2 |
| `CHEZ_LIBDIRS` reordered to `fallback:src` | `a built src/ ahead of fallback/ loads the real shim` | 2 |
| Remove one export from the fallback config | `make check-config` | 3 |
| Change the fallback's version-range literal | `make check-config` — **run in Task 3 Step 3** | 3 |
| Append a line to an expected output file | `make examples` — **run in Task 4 Step 6** | 4 |
| Add `(srfi :64)` to an example's imports | `make examples` — **run in Task 4 Step 7** | 4 |
| Add an export with no example | coverage assertion 1, naming it — **Task 6 Step 4a** | 6 |
| Exempt an identifier an example uses | coverage assertion 2 — **Task 6 Step 4b** | 6 |
| Exempt a non-existent export | coverage assertion 3 — **Task 6 Step 4c** | 6 |
| Skip one `free-buffer` in the render path | `no native resource accumulates` — **Task 7 Step 3** | 7 |
| Edit one README matrix version | the CI matrix check | 8 |

- [ ] **Step 2: Record any mutation that could not break its assertion**

If any mutation above produces no failure, the assertion is empty. Rewrite it, or record in the mutation log that the property is uncovered and why. Leaving it silent is the exact failure that rule exists to prevent.

- [ ] **Step 3: Write the mutation log**

Following `.plans/stage-5-mutation-log.md`, record each mutation, the exact command run, the observed failure, and the confirmation that it passed again after reverting.

```bash
git add .plans/stage-6-mutation-log.md
git commit -m "test: record Stage 6 mutation evidence"
```
