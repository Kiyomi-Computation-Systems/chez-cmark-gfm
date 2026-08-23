#!r6rs
;; NATIVE SUITE: imports (cmark gfm), which loads a shared object -- unlike
;; tests/test-site.sps, this is NOT pure. Run it like the repo's other
;; native suites:
;;   CHEZSCHEMELIBDIRS=src:tests:.:build/scheme-libs chez --program tests/test-site-render.sps
(import (rnrs) (srfi :64) (site render) (site serializer))

(define (string-contains-sub? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-render")

;; Two tiny pages; page A links to a heading on page B. Two-pass resolution
;; is the point: the anchor is only knowable after B is slugged.
(define inputs
  '(("index.md" . "# Home\n\nSee [node shape](ast.md#node-shape).\n")
    ("ast.md"   . "# The AST\n\n## Node shape\n\ntext\n")))

(define r (render-site inputs "v2.0.0"))

(test-equal "every input yields a page"
  '("index.md" "ast.md") (map car (site-result-pages r)))

;; The id-registry carries EVERY heading's slug, h1 through h6 -- every
;; heading is a linkable anchor target, so cross-page anchor resolution
;; must be able to see the h1 too. ast.md has two headings, "# The AST"
;; (slug "the-ast") and "## Node shape" (slug "node-shape"), so both are
;; in the registry, in document order. (This corrects the task brief's
;; sample expectation of '("node-shape"), which omitted the h1 slug.)
(test-equal "the registry carries every one of a page's heading slugs, including its h1"
  '("the-ast" "node-shape")
  (cond ((assoc "ast.md" (site-result-registry r)) => cdr) (else 'missing)))

(test-equal "a resolvable cross-page anchor does not dangle"
  '() (site-result-leaked r))

;; The registry (all headings) is not the same list as the rendered "On
;; this page" rail (sections only, level > 1): the rail must show ast.md's
;; h2 but must NOT turn its own h1 page title into a rail entry. Checked
;; on the actual rendered-and-serialized document, not the internal toc,
;; so this exercises render-site's wiring into (site template) end to end.
;; The leading '#' is what distinguishes a rail link (href="#the-ast")
;; from the content heading's own bare id="the-ast" attribute -- the latter
;; has no '#' and would be present regardless of the rail filter.
(let ((ast-doc (cond ((assoc "ast.md" (site-result-pages r)) => cdr)
                      (else (error 'test-site-render "ast.md page missing")))))
  (let ((html (sxml->html ast-doc)))
    (test-assert "the rail links the h2 anchor"
      (string-contains-sub? html "#node-shape"))
    (test-assert "the rail does NOT link the h1 anchor (page title is not a rail entry)"
      (not (string-contains-sub? html "#the-ast")))))

;; Break the target: the anchor now dangles.
(define r2 (render-site
             '(("index.md" . "[x](ast.md#gone)\n") ("ast.md" . "# The AST\n")) "v2.0.0"))
(test-equal "an unresolvable cross-page anchor is reported"
  '(("index.md" . "ast.md#gone")) (site-result-leaked r2))

(test-end "site-render")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
