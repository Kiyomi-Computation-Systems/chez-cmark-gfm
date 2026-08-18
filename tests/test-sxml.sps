#!r6rs
;; PURE SUITE. This file must never import a library that loads a shared
;; object. `make check-purity` enforces it by running this file with
;; CHEZ_CMARK_GFM_SHIM poisoned. Check transitive imports before adding one
;; here or to sxml.sls.
(import (rnrs)
        (srfi :64)
        (cmark gfm ast)
        (cmark gfm options)
        (cmark gfm private conditions)
        (cmark gfm sxml))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml")

(define (node type props kids) (make-markdown-node type props kids #f))
(define (text s) (node 'text (list (cons 'literal s)) '()))
(define (doc . kids) (node 'document '() kids))
(define (->sxml n) (markdown-ast->sxml n))

;; --- document root ------------------------------------------------------
(test-equal "a document becomes *TOP*"
  '(*TOP*) (->sxml (doc)))

;; --- headings -----------------------------------------------------------
(test-equal "heading level picks the tag"
  '(*TOP* (h1 "a") (h6 "b"))
  (->sxml (doc (node 'heading '((level . 1)) (list (text "a")))
               (node 'heading '((level . 6)) (list (text "b"))))))

;; --- text and inline containers ----------------------------------------
;; The literal is carried VERBATIM. Escaping is the serializer's job, and an
;; adapter that escaped here would double-escape on output.
(test-equal "a text literal is carried unescaped"
  '(*TOP* (p "a & <b>"))
  (->sxml (doc (node 'paragraph '() (list (text "a & <b>"))))))

(test-equal "inline containers map to their HTML tags"
  '(*TOP* (p (em "e") (strong "s") (del "d") (code "c")))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'emph '() (list (text "e")))
                           (node 'strong '() (list (text "s")))
                           (node 'strikethrough '() (list (text "d")))
                           (node 'code '((literal . "c")) '()))))))

(test-equal "blockquote wraps its blocks"
  '(*TOP* (blockquote (p "a")))
  (->sxml (doc (node 'blockquote '()
                     (list (node 'paragraph '() (list (text "a"))))))))

;; --- breaks -------------------------------------------------------------
;; html.c:319 -- a softbreak is a NEWLINE CHARACTER in the output, not an
;; element. It is content from cmark's inline stream, which is why it is the
;; one piece of whitespace that belongs in the tree.
(test-equal "softbreak is a newline string, linebreak is a br element"
  '(*TOP* (p "a" "\n" "b" (br) "c"))
  (->sxml (doc (node 'paragraph '()
                     (list (text "a") (node 'softbreak '() '()) (text "b")
                           (node 'linebreak '() '()) (text "c"))))))

(test-equal "thematic break is a childless hr"
  '(*TOP* (hr)) (->sxml (doc (node 'thematic-break '() '()))))

;; --- code blocks --------------------------------------------------------
(test-equal "a code block with no info has a bare code element"
  '(*TOP* (pre (code "x\n")))
  (->sxml (doc (node 'code-block '((literal . "x\n") (fence-info . "")) '()))))

;; html.c:223-227 scans the info string to the first whitespace; the
;; remainder is reachable only through CMARK_OPT_FULL_INFO_STRING, which
;; this library does not expose.
(test-equal "only the first token of the fence info becomes the class"
  '(*TOP* (pre (code (\x40; (class "language-scheme")) "x\n")))
  (->sxml (doc (node 'code-block
                     '((literal . "x\n") (fence-info . "scheme linenos=3"))
                     '()))))

;; --- raw HTML -----------------------------------------------------------
(test-equal "omit replaces raw HTML with cmark's comment"
  '(*TOP* (*COMMENT* " raw HTML omitted ")
          (p (*COMMENT* " raw HTML omitted ")))
  (->sxml (doc (node 'html-block '((literal . "<div>\n")) '())
               (node 'paragraph '()
                     (list (node 'html-inline '((literal . "<b>")) '()))))))

(test-equal "escape carries the literal through as text"
  '(*TOP* "<div>\n" (p "<b>"))
  (markdown-ast->sxml
   (doc (node 'html-block '((literal . "<div>\n")) '())
        (node 'paragraph '()
              (list (node 'html-inline '((literal . "<b>")) '()))))
   (make-sxml-options 'raw-html 'escape)))

;; --- unknown node types -------------------------------------------------
;; "custom_block" is a string cmark genuinely produces
;; (vendor/cmark-gfm/src/node.c:238-295) for a node type this adapter does
;; not map. Do NOT use "footnote_definition": cmark_node_get_type_string has
;; no case for footnote nodes at all and falls through to "<unknown>", so
;; that string only looks real.
(test-equal "an extension node raises, carrying its native type"
  "custom_block"
  (guard (e ((cmark-unsupported-node? e) (cmark-unsupported-node-type e))
            (#t 'wrong-condition))
    (->sxml (doc (node 'extension '((native-type . "custom_block")) '())))
    'no-raise))

(test-end "sxml")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
