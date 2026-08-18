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
