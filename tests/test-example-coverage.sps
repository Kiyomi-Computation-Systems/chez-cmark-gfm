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
