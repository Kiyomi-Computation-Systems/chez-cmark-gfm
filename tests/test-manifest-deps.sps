#!r6rs
;;; Plan 16, criterion 15: the core library has no dependency on a
;;; documentation-site framework. True today by construction -- Akku.manifest
;;; names two Scheme libraries and nothing else -- but nothing was checking
;;; it, which is exactly the shape of bug check-pins and check-config already
;;; exist for: two things that must agree, with nothing noticing if they stop.
;;;
;;; Two assertions, not one, and they guard different regressions:
;;;   1. No declared dependency's name matches a known documentation-site
;;;      tool. This is what the criterion is actually ABOUT -- naming the
;;;      class of thing that must never appear.
;;;   2. The declared set is exactly the current known-good set. This is
;;;      strictly stronger and catches everything (1) would miss (an
;;;      unanticipated dependency of any other kind), the same total-drift
;;;      posture check-pins takes for the submodule/lock pair.
;;;
;;; Read as DATA, not scanned as text, for the same reason
;;; test-example-coverage.sps reads gfm.sls that way: a text scan is satisfied
;;; by a name that appears only in a comment, which documents nothing.
;;;
;;; Pure: imports only (rnrs), so it runs under `make check-purity` with
;;; CHEZ_CMARK_GFM_SHIM poisoned.
(import (rnrs) (srfi :64))

(define runner (test-runner-simple))
(test-runner-current runner)

(define manifest-path "Akku.manifest")

;; Akku.manifest opens with a #!r6rs pragma line, exactly like gfm.sls, and
;; (like test-example-coverage.sps's file-symbols) more than one top-level
;; datum follows it -- (import ...) THEN (akku-package ...). Loop to EOF and
;; keep the one whose head is akku-package, rather than assuming it is first.
(define (find-package-form path)
  (call-with-input-file path
    (lambda (port)
      (let loop ()
        (let ((d (read port)))
          (cond
            ((eof-object? d)
             (error 'find-package-form "no akku-package form found" path))
            ((and (pair? d) (eq? (car d) 'akku-package)) d)
            (else (loop))))))))

;; (akku-package (name version) (key ...) ...) -- depends/depends-dev are
;; optional clauses among the rest; each entry is (pkg-name version-constraint).
(define (clause form key)
  (cond
    ((assq key (cddr form)) => cdr)
    (else '())))

(define package-form (find-package-form manifest-path))

(define (dep-names key)
  (map car (clause package-form key)))

(define all-deps
  (append (dep-names 'depends) (dep-names 'depends/dev)))

;; Substring match, case-insensitive-by-construction (package names on Akku
;; are conventionally lowercase already) -- catches "sphinx" whether it shows
;; up as a bare name or, e.g., "chez-sphinx".
(define doc-site-markers
  '("sphinx" "mkdocs" "docusaurus" "jekyll" "hugo" "gatsby" "vitepress"
    "docsify" "gitbook" "docsaurus" "antora" "docfx" "hexo"))

(define (contains-substring? hay needle)
  (let ((hl (string-length hay)) (nl (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nl) hl) #f)
            ((string=? needle (substring hay i (+ i nl))) #t)
            (else (loop (+ i 1)))))))

(define (names-a-doc-site-tool? name)
  (exists (lambda (marker) (contains-substring? name marker)) doc-site-markers))

(test-begin "manifest-deps")

;; SEED FIRST: prove the marker check can fire at all, against a synthetic
;; name, before trusting it never fires against the real manifest. An
;; always-#f predicate would pass the real assertion below vacuously.
(test-assert "the doc-site marker check fires on a synthetic offender"
  (names-a-doc-site-tool? "chez-mkdocs-bridge"))

(test-equal "no declared dependency names a documentation-site tool"
  '()
  (filter names-a-doc-site-tool? all-deps))

;; Stronger and independent of the marker list above: the whole set must be
;; exactly what is expected today. Update this list in the SAME commit as any
;; deliberate new dependency -- that is the point, not friction to route
;; around.
(test-equal "the declared dependency set is exactly the current known-good set"
  '("chez-srfi" "wak-sxml-tools")
  (list-sort string<? all-deps))

(test-end "manifest-deps")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
