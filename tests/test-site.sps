#!r6rs
;; PURE SUITE. Imports no library that loads a shared object.
(import (rnrs) (srfi :64) (site slug) (site serializer) (site transform) (site links)
        (site template))

(define (string-contains-sub? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site")

;; --- slugify: matches the anchors docs/ already hand-wrote ---------------
(test-equal "spaces to single hyphen, lowercased"
  "resource-limits" (slugify "Resource limits"))
(test-equal "commas dropped, 'and' kept"
  "rhel-fedora-and-alpine" (slugify "RHEL, Fedora, and Alpine"))
(test-equal "backtick code in a heading is stripped to its text"
  "What make build does" (heading-text '(h2 "What " (code "make build") " does")))
(test-equal "the whole heading-to-slug path"
  "what-make-build-does"
  (slugify (heading-text '(h2 "What " (code "make build") " does"))))
(test-equal "runs of spaces and punctuation collapse"
  "wrap-width" (slugify "Wrap  width"))
(test-equal "leading and trailing punctuation trimmed"
  "supported-versions" (slugify "  Supported versions.  "))

;; --- make-slugger: dedups within a page ---------------------------------
(test-equal "duplicate headings get -1, -2 suffixes"
  '("options" "options-1" "options-2")
  (let ((s (make-slugger))) (list (s "Options") (s "Options") (s "Options"))))

(test-equal "heading-text skips the ^ attr node and inline tags"
  "Some text" (heading-text '(h2 (^ (id "foo")) "Some " (code "text"))))

;; --- serializer: escaping, void elements, the caret marker --------------
(test-equal "text is escaped on output, not before"
  "<p>a &amp; &lt;b&gt;</p>" (sxml->html '(p "a & <b>")))
(test-equal "attributes render from the caret marker and are quoted"
  "<a href=\"/x\">l</a>" (sxml->html '(a (^ (href "/x")) "l")))
(test-equal "void elements self-close without a body"
  "<hr>" (sxml->html '(hr)))
(test-equal "*TOP* is a fragment: it emits its children only"
  "<h1>a</h1>\n<p>b</p>\n" (sxml->html '(*TOP* (h1 "a") (p "b"))))

;; --- the load-bearing property: <pre> content is never reflowed ---------
(test-equal "indentation inside pre/code is content, preserved byte-for-byte"
  "<pre><code>(define (f x)\n    (g\n      x))\n</code></pre>"
  (sxml->html '(pre (code "(define (f x)\n    (g\n      x))\n"))))

(test-equal "a *COMMENT* node renders as an HTML comment, not a bogus tag"
  "<!-- raw HTML omitted -->" (sxml->html '(*COMMENT* " raw HTML omitted ")))

;; --- transform: inject ids on headings, collect the TOC -----------------
(let-values (((body toc)
              (transform-body '(*TOP* (h2 "Node shape") (p "x") (h2 "Node shape")))))
  (test-equal "headings gain a caret id from their slug"
    '(*TOP* (h2 (^ (id "node-shape")) "Node shape") (p "x")
            (h2 (^ (id "node-shape-1")) "Node shape"))
    body)
  (test-equal "the toc lists (level text slug) in document order"
    '((2 "Node shape" "node-shape") (2 "Node shape" "node-shape-1"))
    toc))

;; --- transform: a ⚠️-led blockquote becomes a warning callout -----------
(let-values (((body toc)
              (transform-body '(*TOP* (blockquote (p "⚠️ The AST is untrusted."))))))
  (test-equal "⚠️ blockquotes are rewrapped as a warning callout div"
    '(*TOP* (div (^ (class "callout warning")) (blockquote (p "⚠️ The AST is untrusted."))))
    body))

;; --- links: the rewrite rules -------------------------------------------
(define reg '(("options.md" . ("resource-limits")) ("ast.md" . ("node-shape"))))
(define (rw body page) (let-values (((b d) (rewrite-links body reg page "v2.0.0"))) b))

(test-equal "doc .md link (with anchor) becomes .html, anchor kept"
  '(*TOP* (p (a (^ (href "options.html#resource-limits")) "x")))
  (rw '(*TOP* (p (a (^ (href "options.md#resource-limits")) "x"))) "ast.md"))
(test-equal "bare doc .md link becomes .html"
  '(*TOP* (p (a (^ (href "ast.html")) "x")))
  (rw '(*TOP* (p (a (^ (href "ast.md")) "x"))) "options.md"))
(test-equal "same-page anchor is left as-is"
  '(*TOP* (p (a (^ (href "#node-shape")) "x")))
  (rw '(*TOP* (p (a (^ (href "#node-shape")) "x"))) "ast.md"))
(test-equal "a ../ escape is pinned to the GitHub blob at the ref"
  '(*TOP* (p (a (^ (href "https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/blob/v2.0.0/examples/01-rendering.sps")) "x")))
  (rw '(*TOP* (p (a (^ (href "../examples/01-rendering.sps")) "x"))) "usage.md"))
(test-equal "an absolute URL is untouched"
  '(*TOP* (p (a (^ (href "https://example.com")) "x")))
  (rw '(*TOP* (p (a (^ (href "https://example.com")) "x"))) "ast.md"))
(test-equal "CRUX: a javascript: URL in a code block is NOT a link, untouched"
  '(*TOP* (pre (code "[x](javascript:alert(1))")))
  (rw '(*TOP* (pre (code "[x](javascript:alert(1))"))) "sxml.md"))
(test-equal "CRUX: href on a non-a/img element is left untouched (structural gate)"
  '(*TOP* (span (^ (href "options.md")) "x"))
  (rw '(*TOP* (span (^ (href "options.md")) "x")) "ast.md"))

;; --- links: danglers are reported ---------------------------------------
(let-values (((b d) (rewrite-links
                      '(*TOP* (a (^ (href "options.md#nonesuch")) "x")) reg "ast.md" "v2.0.0")))
  (test-equal "an anchor absent from the registry is reported as a dangler"
    '(("ast.md" . "options.md#nonesuch")) d))

(let-values (((b d) (rewrite-links
                      '(*TOP* (a (^ (href "missing.md")) "x")) reg "ast.md" "v2.0.0")))
  (test-equal "a bare .md link to a page absent from the registry is a dangler"
    '(("ast.md" . "missing.md")) d))

(let-values (((b d) (rewrite-links
                      '(*TOP* (a (^ (href "options.md")) "x")) reg "ast.md" "v2.0.0")))
  (test-equal "a bare .md link to a page present in the registry is NOT a dangler (regression)"
    '() d))

(let-values (((b d) (rewrite-links
                      '(*TOP* (a (^ (href "missing.md#foo")) "x")) reg "ast.md" "v2.0.0")))
  (test-equal "an anchored .md link to a page absent from the registry is a dangler"
    '(("ast.md" . "missing.md#foo")) d))

;; --- template: the shell places nav, current marker, body, and TOC ------
(define doc-out
  (page->document '(("ast.md" . "The AST") ("sxml.md" . "SXML"))
                  "ast.md" "The AST"
                  '(*TOP* (h2 (^ (id "node-shape")) "Node shape"))
                  '((2 "Node shape" "node-shape"))
                  '("options.md" . "Options") '("sxml.md" . "SXML")))

(test-assert "the document is rooted at html"
  (and (pair? doc-out) (eq? (car doc-out) '*TOP*)
       (eq? (car (cadr doc-out)) 'html)))
(test-assert "the stylesheet is linked in head"
  (let ((s (sxml->html doc-out)))
    (and (string-contains-sub? s "<link") (string-contains-sub? s "style.css"))))
(test-assert "the current page is marked in the nav"
  (string-contains-sub? (sxml->html doc-out) "aria-current=\"page\""))
(test-assert "the TOC lists the page's headings"
  (string-contains-sub? (sxml->html doc-out) "#node-shape"))
(test-assert "CRUX: the embedded theme script survives serialization unescaped"
  ;; The serializer HTML-escapes every text node, including a <script>'s.
  ;; Browsers do not decode entities inside <script>, so if the script ever
  ;; grew a '<', '>', or '&' it would come out corrupted. It doesn't
  ;; contain any (=== and nested ternaries stand in for </>/&&), so no
  ;; escape entity should appear anywhere in the rendered document.
  (let ((s (sxml->html doc-out)))
    (and (string-contains-sub? s "<script>(function(){var r=document.documentElement")
         (not (string-contains-sub? s "&amp;"))
         (not (string-contains-sub? s "&lt;"))
         (not (string-contains-sub? s "&gt;")))))

;; --- template: mode-toggle icon and prev/next footer nav ----------------
(test-assert "the mode toggle carries the knob icon"
  (string-contains-sub? (sxml->html doc-out) "class=\"knob\""))
(test-assert "the footer nav links the previous and next pages"
  (let ((s (sxml->html doc-out)))
    (and (string-contains-sub? s "class=\"pagenav\"")
         (string-contains-sub? s "href=\"options.html\"")
         (string-contains-sub? s "href=\"sxml.html\"")
         (string-contains-sub? s "class=\"next\""))))
(test-assert "a page with no neighbours (the home page) has no footer nav"
  (not (string-contains-sub?
        (sxml->html (page->document '(("index.md" . "Home")) "index.md" "Home"
                                    '(*TOP* (h1 "Home")) '() #f #f))
        "class=\"pagenav\"")))

(test-end "site")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
