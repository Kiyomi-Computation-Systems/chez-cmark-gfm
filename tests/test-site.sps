#!r6rs
;; PURE SUITE. Imports no library that loads a shared object.
(import (rnrs) (srfi :64) (site slug) (site serializer) (site transform) (site links))

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

;; --- links: danglers are reported ---------------------------------------
(let-values (((b d) (rewrite-links
                      '(*TOP* (a (^ (href "options.md#nonesuch")) "x")) reg "ast.md" "v2.0.0")))
  (test-equal "an anchor absent from the registry is reported as a dangler"
    '(("ast.md" . "options.md#nonesuch")) d))

(test-end "site")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
