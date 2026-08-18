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

;; --- links --------------------------------------------------------------
(define (link url title . kids)
  (node 'link (list (cons 'url url) (cons 'title title)) kids))

;; html.c:392 writes the title attribute only when title.len is non-zero.
;; An empty title="" is a byte difference, not a harmless extra.
(test-equal "an empty title is omitted, a present one is kept"
  '(*TOP* (p (a (\x40; (href "/x")) "l") (a (\x40; (href "/y") (title "t")) "m")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "/x" "" (text "l"))
                           (link "/y" "t" (text "m")))))))

;; houdini_escape_href percent-encodes every byte outside HREF_SAFE
;; (src/houdini_href_e.c:32-44). & and ' are left ALONE here -- they are the
;; serializer's half of the split, and encoding them here would produce
;; &amp;amp; on output.
(test-equal "a URL is percent-encoded but ampersand and apostrophe pass through"
  '(*TOP* (p (a (\x40; (href "/a%20b?x=1&y='z'%C3%A9")) "l")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "/a b?x=1&y='z'é" "" (text "l")))))))

;; src/scanners.re:345-354. re2c single-quoted literals are
;; case-insensitive, so mixed case is caught. A rejected URL yields an EMPTY
;; attribute (html.c:387-391), not a raise and not a removed attribute.
(test-equal "dangerous schemes yield an empty href, in any case"
  '(*TOP* (p (a (\x40; (href "")) "a") (a (\x40; (href "")) "b")
             (a (\x40; (href "")) "c") (a (\x40; (href "")) "d")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "javascript:alert(1)" "" (text "a"))
                           (link "JaVaScRiPt:alert(1)" "" (text "b"))
                           (link "vbscript:x" "" (text "c"))
                           (link "file:///etc/passwd" "" (text "d")))))))

(test-equal "data: is rejected except for the four image subtypes"
  '(*TOP* (p (a (\x40; (href "")) "html")
             (a (\x40; (href "data:image/png;base64,AA")) "png")
             (a (\x40; (href "data:image/webp,x")) "webp")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "data:text/html,<b>" "" (text "html"))
                           (link "data:image/png;base64,AA" "" (text "png"))
                           (link "data:image/webp,x" "" (text "webp")))))))

;; --- images -------------------------------------------------------------
;; html.c:118-139 -- children render in PLAIN mode into alt: text, code, and
;; html-inline contribute literals; breaks contribute a single space;
;; everything else contributes nothing but is still descended into.
(test-equal "image alt is the flattened plaintext of its children"
  '(*TOP* (p (img (\x40; (src "/i") (alt "a b c d e")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "/i") (title . ""))
                                 (list (text "a ")
                                       (node 'emph '() (list (text "b")))
                                       (text " ")
                                       (node 'code '((literal . "c")) '())
                                       (node 'softbreak '() '())
                                       (node 'html-inline '((literal . "d")) '())
                                       (text " e"))))))))

(test-equal "an image title is omitted when empty and kept when present"
  '(*TOP* (p (img (\x40; (src "/i") (alt "")))
             (img (\x40; (src "/j") (alt "") (title "t")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "/i") (title . "")) '())
                           (node 'image '((url . "/j") (title . "t")) '()))))))

(test-equal "an image src takes the same dangerous-URL policy"
  '(*TOP* (p (img (\x40; (src "") (alt "")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "javascript:x") (title . ""))
                                 '()))))))

;; --- lists --------------------------------------------------------------
(define (li . kids)
  (node 'item '((index . 1) (task? . #f) (checked? . #f)) kids))

(define (bullet tight? . items)
  (node 'list (list (cons 'kind 'bullet) (cons 'start 1)
                    (cons 'tight? tight?) (cons 'delimiter 'none))
        items))

(define (ordered start tight? . items)
  (node 'list (list (cons 'kind 'ordered) (cons 'start start)
                    (cons 'tight? tight?) (cons 'delimiter 'period))
        items))

(define (para . kids) (node 'paragraph '() kids))

;; html.c:174-183 -- start is written only when it is not 1.
(test-equal "ol start is emitted only when it is not one"
  '(*TOP* (ol (li (p "a"))) (ol (\x40; (start "3")) (li (p "a"))))
  (->sxml (doc (ordered 1 #f (li (para (text "a"))))
               (ordered 3 #f (li (para (text "a")))))))

;; html.c:287-297 -- a paragraph whose GRANDPARENT list is tight emits no
;; <p> at all; its children go straight into the <li>. A tight list is not a
;; list that renders compactly, it is a list with no paragraph elements.
(test-equal "a tight list has no p elements, a loose one does"
  '(*TOP* (ul (li "a")) (ul (li (p "a"))))
  (->sxml (doc (bullet #t (li (para (text "a"))))
               (bullet #f (li (para (text "a")))))))

;; Tightness comes from the ENCLOSING list only. A loose list nested inside a
;; tight one keeps its paragraphs.
(test-equal "tightness does not leak into a nested list"
  '(*TOP* (ul (li "a" (ul (li (p "b"))))))
  (->sxml (doc (bullet #t (li (para (text "a"))
                              (bullet #f (li (para (text "b")))))))))

;; extensions/tasklist.c:124-128. Note the attribute ORDER and that an
;; unchecked box has no checked attribute at all. The trailing space cmark
;; writes after "/>" is a text node here.
(test-equal "task items get a disabled checkbox, checked ones get the attribute"
  '(*TOP* (ul (li (input (\x40; (type "checkbox") (checked "") (disabled ""))) " " "a")
              (li (input (\x40; (type "checkbox") (disabled ""))) " " "b")))
  (->sxml (doc (bullet #t
                       (node 'item '((index . 1) (task? . #t) (checked? . #t))
                             (list (para (text "a"))))
                       (node 'item '((index . 2) (task? . #t) (checked? . #f))
                             (list (para (text "b"))))))))

;; --- tables -------------------------------------------------------------
(define (cell align . kids)
  (node 'table-cell (list (cons 'alignment align)) kids))

(define (row header? . cells)
  (node 'table-row (list (cons 'header? header?)) cells))

(define (table . rows)
  (node 'table (list (cons 'columns (length (markdown-node-children (car rows))))
                     (cons 'alignments '()))
        rows))

;; extensions/table.c:774-797. A header row opens and closes thead around
;; itself; the first non-header row opens tbody, which stays open to the end
;; of the table. This is the only structural regrouping in the mapping --
;; the AST is flat and HTML is nested.
(test-equal "header rows go in thead, body rows share one tbody"
  '(*TOP* (table (thead (tr (th "h")))
                 (tbody (tr (td "a")) (tr (td "b")))))
  (->sxml (doc (table (row #t (cell 'none (text "h")))
                      (row #f (cell 'none (text "a")))
                      (row #f (cell 'none (text "b")))))))

(test-equal "a table with no body rows emits no tbody"
  '(*TOP* (table (thead (tr (th "h")))))
  (->sxml (doc (table (row #t (cell 'none (text "h")))))))

;; extensions/table.c:806-811 switches on 'l'/'c'/'r' and writes nothing
;; otherwise -- and unlike the XML renderer, it emits align on BODY cells
;; too. That is the one ADR-0010 blind spot this oracle closes.
(test-equal "alignment renders on header and body cells alike, omitted when none"
  '(*TOP* (table (thead (tr (th (\x40; (align "left")) "h")
                            (th (\x40; (align "center")) "i")
                            (th "j")))
                 (tbody (tr (td (\x40; (align "right")) "a")
                            (td "b")
                            (td "c")))))
  (->sxml (doc (table (row #t (cell 'left (text "h"))
                              (cell 'center (text "i"))
                              (cell 'none (text "j")))
                      (row #f (cell 'right (text "a"))
                              (cell 'none (text "b"))
                              (cell 'none (text "c")))))))

(test-end "sxml")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
