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
