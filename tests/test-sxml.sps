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

;; html.c:366-374 -- a STRONG directly inside a STRONG emits neither tag; its
;; children splice into the enclosing one. Pure adapter logic, but until now
;; exercised only through the native shim and the CLI
;; (test-sxml-differential.sps's "nested strong emits one tag" and its
;; siblings), never pinned in this pure suite.
(test-equal "a strong directly inside a strong collapses to one tag"
  '(*TOP* (p (strong "x")))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'strong '()
                                 (list (node 'strong '() (list (text "x"))))))))))

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

;; softbreak's other two policies (html.c:319-325). The default ('newline,
;; pinned above) needs no options argument; these do. Pure adapter logic,
;; but until now exercised only through test-sxml-differential.sps's option
;; sweep.
(test-equal "softbreak 'break renders a br element"
  '(*TOP* (p "a" (br) "b"))
  (markdown-ast->sxml
   (doc (node 'paragraph '()
              (list (text "a") (node 'softbreak '() '()) (text "b"))))
   (make-sxml-options 'softbreak 'break)))

(test-equal "softbreak 'space renders a literal space"
  '(*TOP* (p "a" " " "b"))
  (markdown-ast->sxml
   (doc (node 'paragraph '()
              (list (text "a") (node 'softbreak '() '()) (text "b"))))
   (make-sxml-options 'softbreak 'space)))

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
  '(*TOP* (pre (code (^ (class "language-scheme")) "x\n")))
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

;; The adapter's OWN `else` fallthrough -- a node type this library has
;; simply not mapped -- as opposed to the `extension` case above, which is
;; cmark's own escape hatch for a type it flags as such. Both raise the same
;; condition, so only the reported type string tells them apart; "bogus-type"
;; is not "custom_block" and could not be produced by the extension case,
;; which is what makes this a test of the sibling branch and not a repeat of
;; the one above.
(test-equal "an unmapped node type raises via the else branch, not extension"
  "bogus-type"
  (guard (e ((cmark-unsupported-node? e) (cmark-unsupported-node-type e))
            (#t 'wrong-condition))
    (->sxml (doc (node 'bogus-type '() '())))
    'no-raise))

;; markdown-ast->sxml's own guard on its second argument. Distinct from
;; markdown->sxml's cmark-options? guard in (cmark gfm) -- untestable here,
;; this being the PURE suite -- which test-sxml-differential.sps covers.
(test-equal "markdown-ast->sxml rejects a non-sxml-options second argument"
  '(#f invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (markdown-ast->sxml (doc) (default-cmark-options))
    'no-raise))

;; --- links --------------------------------------------------------------
(define (link url title . kids)
  (node 'link (list (cons 'url url) (cons 'title title)) kids))

;; html.c:392 writes the title attribute only when title.len is non-zero.
;; An empty title="" is a byte difference, not a harmless extra.
(test-equal "an empty title is omitted, a present one is kept"
  '(*TOP* (p (a (^ (href "/x")) "l") (a (^ (href "/y") (title "t")) "m")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "/x" "" (text "l"))
                           (link "/y" "t" (text "m")))))))

;; houdini_escape_href percent-encodes every byte outside HREF_SAFE
;; (src/houdini_href_e.c:32-44). & and ' are left ALONE here -- they are the
;; serializer's half of the split, and encoding them here would produce
;; &amp;amp; on output.
(test-equal "a URL is percent-encoded but ampersand and apostrophe pass through"
  '(*TOP* (p (a (^ (href "/a%20b?x=1&y='z'%C3%A9")) "l")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "/a b?x=1&y='z'é" "" (text "l")))))))

;; src/scanners.re:345-354. re2c single-quoted literals are
;; case-insensitive, so mixed case is caught. A rejected URL yields an EMPTY
;; attribute (html.c:387-391), not a raise and not a removed attribute.
(test-equal "dangerous schemes yield an empty href, in any case"
  '(*TOP* (p (a (^ (href "")) "a") (a (^ (href "")) "b")
             (a (^ (href "")) "c") (a (^ (href "")) "d")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "javascript:alert(1)" "" (text "a"))
                           (link "JaVaScRiPt:alert(1)" "" (text "b"))
                           (link "vbscript:x" "" (text "c"))
                           (link "file:///etc/passwd" "" (text "d")))))))

;; All FOUR allowed subtypes, named in the assertion's own title -- the
;; earlier version of this fixture exercised only two (png, webp) and left
;; the gif and jpeg prefix checks in dangerous-url? untested.
(test-equal "data: is rejected except for the four image subtypes"
  '(*TOP* (p (a (^ (href "")) "html")
             (a (^ (href "data:image/png;base64,AA")) "png")
             (a (^ (href "data:image/gif;base64,AA")) "gif")
             (a (^ (href "data:image/jpeg;base64,AA")) "jpeg")
             (a (^ (href "data:image/webp,x")) "webp")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "data:text/html,<b>" "" (text "html"))
                           (link "data:image/png;base64,AA" "" (text "png"))
                           (link "data:image/gif;base64,AA" "" (text "gif"))
                           (link "data:image/jpeg;base64,AA" "" (text "jpeg"))
                           (link "data:image/webp,x" "" (text "webp")))))))

;; An "empty URL" fixture was tried here and dropped: percent-encode("") is
;; "" exactly as dangerous-url?'s rejection path also yields "", so
;; safe-url("") is "" whichever branch runs and no mutation of the routing
;; decision can move this assertion. Confirmed by mutation (see
;; .plans/stage-5-mutation-log.md, Task 12 Step 0) rather than assumed.
;;
;; Every byte here needs escaping, unlike the mixed fixture above -- this
;; exercises percent-encode's loop with no href-safe byte anywhere in the
;; input.
(test-equal "a URL of entirely unsafe bytes is percent-encoded throughout"
  '(*TOP* (p (a (^ (href "%20%3C%3E")) "l")))
  (->sxml (doc (node 'paragraph '() (list (link " <>" "" (text "l")))))))

;; --- images -------------------------------------------------------------
;; html.c:118-139 -- children render in PLAIN mode into alt: text, code, and
;; html-inline contribute literals; breaks contribute a single space;
;; everything else contributes nothing but is still descended into.
(test-equal "image alt is the flattened plaintext of its children"
  '(*TOP* (p (img (^ (src "/i") (alt "a b c d e")))))
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
  '(*TOP* (p (img (^ (src "/i") (alt "")))
             (img (^ (src "/j") (alt "") (title "t")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "/i") (title . "")) '())
                           (node 'image '((url . "/j") (title . "t")) '()))))))

(test-equal "an image src takes the same dangerous-URL policy"
  '(*TOP* (p (img (^ (src "") (alt "")))))
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
  '(*TOP* (ol (li (p "a"))) (ol (^ (start "3")) (li (p "a"))))
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
  '(*TOP* (ul (li (input (^ (type "checkbox") (checked "") (disabled ""))) " " "a")
              (li (input (^ (type "checkbox") (disabled ""))) " " "b")))
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

;; The mirror image of the above: a table the parser could not itself
;; produce (extensions/table.c:402-403 always synthesises a header row
;; first) but markdown-ast->sxml accepts a caller-built tree, so this is
;; reachable and had no test.
(test-equal "a body-only table emits no thead"
  '(*TOP* (table (tbody (tr (td "a")))))
  (->sxml (doc (table (row #f (cell 'none (text "a")))))))

;; Both accumulators empty from the start -- the fold's base case, distinct
;; from "no body rows" above, where body stays empty but head does not.
;; Unreachable from the parser for the same reason; reachable here.
(test-equal "a table with no rows at all emits neither section"
  '(*TOP* (table))
  (->sxml (doc (node 'table '((columns . 0) (alignments . ())) '()))))

;; A header row anywhere but first is a tree the parser cannot produce, so
;; the adapter refuses it rather than silently normalising it into output
;; cmark would not generate. Reachable only through markdown-ast->sxml on a
;; caller-built or caller-transformed AST.
(test-equal "a header row after the first row is refused"
  'header-row-not-first
  (guard (e ((cmark-malformed-tree? e) (cmark-malformed-tree-reason e))
            (#t 'wrong-condition))
    (->sxml (doc (table (row #t (cell 'none (text "h")))
                        (row #f (cell 'none (text "a")))
                        (row #t (cell 'none (text "h2"))))))
    'no-raise))

(test-equal "two leading header rows are refused"
  'header-row-not-first
  (guard (e ((cmark-malformed-tree? e) (cmark-malformed-tree-reason e))
            (#t 'wrong-condition))
    (->sxml (doc (table (row #t (cell 'none (text "h")))
                        (row #t (cell 'none (text "h2"))))))
    'no-raise))

;; extensions/table.c:806-811 switches on 'l'/'c'/'r' and writes nothing
;; otherwise -- and unlike the XML renderer, it emits align on BODY cells
;; too. That is the one ADR-0010 blind spot this oracle closes.
(test-equal "alignment renders on header and body cells alike, omitted when none"
  '(*TOP* (table (thead (tr (th (^ (align "left")) "h")
                            (th (^ (align "center")) "i")
                            (th "j")))
                 (tbody (tr (td (^ (align "right")) "a")
                            (td "b")
                            (td "c")))))
  (->sxml (doc (table (row #t (cell 'left (text "h"))
                              (cell 'center (text "i"))
                              (cell 'none (text "j")))
                      (row #f (cell 'right (text "a"))
                              (cell 'none (text "b"))
                              (cell 'none (text "c")))))))


;; --- the attribute marker (ADR-0013) ------------------------------------
;; One fixture reaching all six sites that build an attribute list: the
;; code-block class, `ol` start, the tasklist input, a link, an image, and a
;; table cell's align. The two expectations below are written out in full
;; rather than one being derived from the other by a rewrite: a derived
;; expectation would agree with the adapter through whatever the rewrite
;; does, which is the exact mistake this option exists to undo.
(define every-attribute-site
  (doc (node 'code-block '((literal . "x\n") (fence-info . "scheme")) '())
       (ordered 3 #t
                (node 'item '((index . 3) (task? . #t) (checked? . #t))
                      (list (para (link "/x" "" (text "l"))
                                  (node 'image '((url . "/i") (title . ""))
                                        '())))))
       (table (row #t (cell 'left (text "h"))))))

;; ADR-0013: the default is `^`, not the specification's `@`, because both
;; serializers reachable through Akku speak `^` and neither recognises `@`.
(define caret-tree
  '(*TOP*
    (pre (code (^ (class "language-scheme")) "x\n"))
    (ol (^ (start "3"))
        (li (input (^ (type "checkbox") (checked "") (disabled ""))) " "
            (a (^ (href "/x")) "l")
            (img (^ (src "/i") (alt "")))))
    (table (thead (tr (th (^ (align "left")) "h"))))))

;; Identical but for the marker. `@` is spelled \x40; because Chez's #!r6rs
;; reader rejects the bare token (Global Constraints).
(define at-tree
  '(*TOP*
    (pre (code (\x40; (class "language-scheme")) "x\n"))
    (ol (\x40; (start "3"))
        (li (input (\x40; (type "checkbox") (checked "") (disabled ""))) " "
            (a (\x40; (href "/x")) "l")
            (img (\x40; (src "/i") (alt "")))))
    (table (thead (tr (th (\x40; (align "left")) "h"))))))

(test-equal "the default marker is a caret at every attribute site"
  caret-tree (->sxml every-attribute-site))

;; The explicit spelling must reach the same place as the default. A lookup
;; that defaulted correctly but mishandled a supplied value would pass the
;; assertion above and fail here.
(test-equal "attribute-marker caret, spelled explicitly, agrees with the default"
  caret-tree
  (markdown-ast->sxml every-attribute-site
                      (make-sxml-options 'attribute-marker 'caret)))

(test-equal "attribute-marker at emits the specification's marker at every site"
  at-tree
  (markdown-ast->sxml every-attribute-site
                      (make-sxml-options 'attribute-marker 'at)))

(test-end "sxml")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
