#!r6rs
;; PURE SUITE. Imports no library that loads a shared object.
(import (rnrs) (srfi :64) (site slug) (site serializer))

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

(test-end "site")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
