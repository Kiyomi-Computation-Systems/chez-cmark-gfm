#!r6rs
;;; The native-to-Scheme AST copy.
;;;
;;; These suites drive convert.sls directly, through
;;; call-with-native-document, because markdown->ast does not exist yet
;;; (Task 9) and because driving layer 2 directly is what keeps the lifecycle
;;; rules of ADR-0005 and ADR-0006 in force around every probe.
(import (rnrs)
        (srfi :64)
        (cmark gfm ast)
        (cmark gfm private native)
        (cmark gfm private scope)
        (cmark gfm private convert)
        (cmark gfm private conditions))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "convert")

;; --- drivers ------------------------------------------------------------
(define ast-of
  (case-lambda
    ((markdown) (ast-of markdown #f (quote ())))
    ((markdown positions?) (ast-of markdown positions? (quote ())))
    ((markdown positions? exts)
     (call-with-native-document
      markdown (option-bits #f positions? #f #f #f #f) exts
      (lambda (h)
        (convert-document h (make-convert-ctx 250000 1000 positions?)))))))

(define (ast-of/limits markdown max-nodes max-depth)
  (call-with-native-document
   markdown (option-bits #f #f #f #f #f #f) (quote ())
   (lambda (h) (convert-document h (make-convert-ctx max-nodes max-depth #f)))))

;; A compact, directly comparable rendering: type, properties, children.
(define (shape n)
  (list (markdown-node-type n)
        (markdown-node-properties n)
        (map shape (markdown-node-children n))))

(define (nodes-of-type tree type)
  (reverse (markdown-node-fold
            (lambda (n acc)
              (if (eq? (markdown-node-type n) type) (cons n acc) acc))
            (quote ()) tree)))

(define (first-of-type tree type) (car (nodes-of-type tree type)))

;; --- the whole tree, exactly ---------------------------------------------
;; Compared as a complete structure rather than by spot-checking accessors: a
;; converter that dropped a child, duplicated one, or nested them one level
;; wrong would satisfy any per-node assertion while failing this.
(test-equal "a heading and a paragraph convert to the exact expected tree"
  '(document ()
    ((heading ((level . 1)) ((text ((literal . "hi")) ())))
     (paragraph () ((text ((literal . "para")) ())))))
  (shape (ast-of "# hi\n\npara\n")))

(test-equal "inline emphasis nests inside the paragraph"
  '(document ()
    ((paragraph ()
      ((text ((literal . "a ")) ())
       (emph () ((text ((literal . "b")) ())))
       (text ((literal . " c")) ())))))
  (shape (ast-of "a *b* c\n")))

(test-equal "strong, code, and breaks convert"
  '(strong code softbreak linebreak)
  (map markdown-node-type
       (list (first-of-type (ast-of "**b**\n") 'strong)
             (first-of-type (ast-of "`c`\n") 'code)
             (first-of-type (ast-of "a\nb\n") 'softbreak)
             (first-of-type (ast-of "a\\\nb\n") 'linebreak))))

(test-equal "a block quote wraps its paragraph"
  '(blockquote () ((paragraph () ((text ((literal . "q")) ())))))
  (shape (first-of-type (ast-of "> q\n") 'blockquote)))

(test-equal "a thematic break is a childless node with no properties"
  '(thematic-break () ())
  (shape (first-of-type (ast-of "---\n") 'thematic-break)))

;; --- per-type properties -------------------------------------------------
(test-equal "heading level is copied"
  4 (markdown-node-property (first-of-type (ast-of "#### h\n") 'heading) 'level))

(test-equal "a fenced code block carries literal and fence info"
  '("(+ 1 2)\n" "scheme")
  (let ((n (first-of-type (ast-of "```scheme\n(+ 1 2)\n```\n") 'code-block)))
    (list (markdown-node-property n 'literal)
          (markdown-node-property n 'fence-info))))
;; Empty string, not #f: cmark distinguishes "no info string" from "not a code
;; block", and so must the AST.
(test-equal "an indented code block has an empty fence info"
  ""
  (markdown-node-property
   (first-of-type (ast-of "    x\n") 'code-block) 'fence-info))

(test-equal "a link carries url and title"
  '("http://e.example/" "T")
  (let ((n (first-of-type (ast-of "[x](http://e.example/ \"T\")\n") 'link)))
    (list (markdown-node-property n 'url)
          (markdown-node-property n 'title))))
(test-equal "a link with no title carries an empty title, not #f"
  "" (markdown-node-property
      (first-of-type (ast-of "[x](http://e.example/)\n") 'link) 'title))
(test-equal "an image carries url and title"
  '("i.png" "alt")
  (let ((n (first-of-type (ast-of "![x](i.png \"alt\")\n") 'image)))
    (list (markdown-node-property n 'url)
          (markdown-node-property n 'title))))

(test-equal "raw HTML is preserved verbatim in both positions"
  '("<div>\n" "<b>")
  (list (markdown-node-property
         (first-of-type (ast-of "<div>\n") 'html-block) 'literal)
        (markdown-node-property
         (first-of-type (ast-of "a <b> c\n") 'html-inline) 'literal)))

;; --- lists and items ----------------------------------------------------
;; The numeric cmark constants are mapped to symbols HERE, in layer 3's data,
;; not carried through as integers.
(test-equal "an ordered list maps kind, start, delimiter, and tightness"
  '((kind . ordered) (start . 3) (tight? . #t) (delimiter . period))
  (markdown-node-properties (first-of-type (ast-of "3. a\n4. b\n") 'list)))
(test-equal "a paren-delimited ordered list maps the delimiter"
  'paren
  (markdown-node-property (first-of-type (ast-of "1) a\n") 'list) 'delimiter))
(test-equal "a bullet list maps kind bullet and no delimiter"
  '((kind . bullet) (start . 0) (tight? . #t) (delimiter . none))
  (markdown-node-properties (first-of-type (ast-of "- a\n") 'list)))
;; The three-argument form with a sentinel is load-bearing here, not verbosity:
;; markdown-node-property's two-argument form returns #f for an ABSENT key, and
;; #f is also the correct value for a loose list -- so without the sentinel this
;; assertion passes identically whether tight? was computed correctly or never
;; produced at all. Verified: deleting the tight? pair from list-props leaves the
;; two-argument form green.
(test-equal "a loose list reports tight? #f"
  #f (markdown-node-property (first-of-type (ast-of "- a\n\n- b\n") 'list)
                             'tight? 'absent))

;; index is one of the three properties cmark's XML never emits, so the
;; differential harness of Tasks 10-11 cannot see it. It is asserted directly
;; here or it is not covered at all (design spec 8.3).
(test-equal "item index is copied for every item in an offset ordered list"
  '(3 4 5)
  (map (lambda (n) (markdown-node-property n 'index))
       (nodes-of-type (ast-of "3. a\n4. b\n5. c\n") 'item)))
(test-equal "a plain item is not a task and is not checked"
  '((index . 0) (task? . #f) (checked? . #f))
  (markdown-node-properties (first-of-type (ast-of "- a\n") 'item)))

;; --- key sets are exactly what the table declares ------------------------
;; This is project plan 7.3's property table turned into an executable check.
;; An extractor that invents a key, renames one, or forgets one fails here by
;; name -- which is what makes the generic property lookup safe without a
;; named accessor per property.
(define (key-set-mismatches tree)
  (reverse
   (markdown-node-fold
    (lambda (n acc)
      (let* ((ts (node-type->type-string-for-test n))
             (entry (and ts (type-string->entry ts))))
        (if (not entry)
            acc
            (let ((declared (list-sort symbol<? (node-entry-keys entry)))
                  (actual (list-sort symbol<?
                                     (map car (markdown-node-properties n)))))
              (if (equal? declared actual)
                  acc
                  (cons (list (markdown-node-type n) declared actual) acc))))))
    (quote ()) tree)))

;; The test's OWN mapping from node type back to a type string, written
;; independently of convert.sls's table. If it read the table it would be
;; comparing the table against itself.
(define (node-type->type-string-for-test n)
  (case (markdown-node-type n)
    ((document) "document") ((paragraph) "paragraph")
    ((blockquote) "block_quote") ((thematic-break) "thematic_break")
    ((softbreak) "softbreak") ((linebreak) "linebreak")
    ((emph) "emph") ((strong) "strong")
    ((heading) "heading") ((text) "text") ((code) "code")
    ((html-inline) "html_inline") ((html-block) "html_block")
    ((code-block) "code_block") ((link) "link") ((image) "image")
    ((list) "list")
    ((item) (if (markdown-node-property n 'task?) "tasklist" "item"))
    (else #f)))

(define (symbol<? a b) (string<? (symbol->string a) (symbol->string b)))

(test-equal "every core node's key set is exactly what the table declares"
  (quote ())
  (key-set-mismatches
   (ast-of (string-append
            "# h\n\npara with *emph* and `code` and <b>html</b>\n\n"
            "> quote\n\n---\n\n```scheme\nx\n```\n\n    indented\n\n"
            "3. a\n4. b\n\n- bullet\n\n<div>\n\n"
            "[l](u \"t\") ![i](v \"w\")\n\nsoft\nbreak\n"))))

;; --- the table covers every reachable core type -------------------------
;; The expected list is derived independently from cmark's node-type enum
;; (vendor/cmark-gfm/src/cmark-gfm.h), not from the table. Comparing the table
;; against itself would prove nothing.
(test-equal "the table has an entry for every reachable core type string"
  (quote ())
  (filter (lambda (ts) (not (type-string->entry ts)))
          '("document" "block_quote" "list" "item" "code_block" "html_block"
            "paragraph" "heading" "thematic_break"
            "text" "softbreak" "linebreak" "code" "html_inline"
            "emph" "strong" "link" "image")))

;; --- the tree outlives the native document ------------------------------
;; M3's exit criterion. The tree is returned OUT of the scope, so every
;; assertion below runs after the parser and root have been freed. Reading a
;; literal here would be a use-after-free if any string had been borrowed
;; rather than copied.
(define escaped (ast-of "# hi\n\n[l](http://e.example/ \"T\")\n"))

(test-equal "literals are readable after the native document is gone"
  '("hi" "l")
  (map (lambda (n) (markdown-node-property n 'literal))
       (nodes-of-type escaped 'text)))
(test-equal "a url is readable after the native document is gone"
  "http://e.example/"
  (markdown-node-property (first-of-type escaped 'link) 'url))
(test-equal "every native allocation was released"
  '(0 0 0) (live-counts))

;; Structural proof that no pointer escaped: a borrowed pointer would show up
;; as an integer where a string is documented.
(test-equal "every string-valued property really is a string"
  (quote ())
  (reverse
   (markdown-node-fold
    (lambda (n acc)
      (fold-left
       (lambda (acc pair)
         (if (and (memq (car pair) '(literal url title fence-info))
                  (not (string? (cdr pair))))
             (cons (list (markdown-node-type n) (car pair) (cdr pair)) acc)
             acc))
       acc (markdown-node-properties n)))
    (quote ()) escaped)))

;; --- resource limits ----------------------------------------------------
;; n leading '>' characters produce n nested block quotes, so the document
;; holds 1 + n + 1 + 1 nodes (document, quotes, paragraph, text) at a maximum
;; depth of n + 3. Both numbers are computed from that structure rather than
;; hardcoded, so the tests say why they use the values they use.
(define (nested n) (string-append (make-string n #\>) " x\n"))

(test-equal "a document exactly at the depth limit converts"
  'document (markdown-node-type (ast-of/limits (nested 7) 250000 10)))
(test-equal "one level past the depth limit raises too-deep"
  '(too-deep 10)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (ast-of/limits (nested 8) 250000 10)
    'no-condition))
(test-equal "a document exactly at the node limit converts"
  'document (markdown-node-type (ast-of/limits (nested 7) 10 1000)))
(test-equal "one node past the node limit raises too-many-nodes"
  '(too-many-nodes 10)
  (guard (e ((cmark-resource-limit? e)
             (list (cmark-invalid-input-reason e) (cmark-resource-limit-value e)))
            (#t 'wrong-condition))
    (ast-of/limits (nested 8) 10 1000)
    'no-condition))
;; The failure path is also a memory test: the condition escapes through
;; call-with-native-document, whose after-thunk must still free the parser and
;; root on the way out (design spec 6.3).
(test-equal "a limit failure leaves no native allocation behind"
  '(0 0 0)
  (begin
    (guard (e ((cmark-resource-limit? e) #t))
      (ast-of/limits (nested 400) 10 1000))
    (live-counts)))

;; --- GFM extension node types -------------------------------------------
(define all-exts '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))
(define (ext-ast markdown) (ast-of markdown #f all-exts))

(define table-md "| a | b | c |\n|:--|--:|---|\n| 1 | 2 | 3 |\n")

(test-equal "strikethrough converts and keeps its child"
  '(strikethrough () ((text ((literal . "s")) ())))
  (shape (first-of-type (ext-ast "~~s~~\n") 'strikethrough)))

;; An autolink becomes an ordinary link node (project plan 7.3), so there is
;; no autolink node type to map.
(test-equal "an autolink becomes an ordinary link node"
  "http://e.example/"
  (markdown-node-property
   (first-of-type (ext-ast "http://e.example/\n") 'link) 'url))

;; columns is one of the three properties cmark's XML never emits, so the
;; differential harness cannot see it (design spec 8.3). Asserted here.
(test-equal "a table reports its column count and per-column alignments"
  '((columns . 3) (alignments . (left right none)))
  (markdown-node-properties (first-of-type (ext-ast table-md) 'table)))

(test-equal "the header row and the body row are both table-row nodes"
  '(table-row table-row)
  (map markdown-node-type (nodes-of-type (ext-ast table-md) 'table-row)))
(test-equal "header? distinguishes the two rows"
  '(#t #f)
  (map (lambda (n) (markdown-node-property n 'header?))
       (nodes-of-type (ext-ast table-md) 'table-row)))

;; Body-cell alignment is the third XML blind spot: table.c:661 emits align=
;; only for cells whose parent row is a header. Both rows are asserted here so
;; the body row is not silently uncovered.
(test-equal "header cells carry their column's alignment"
  '(left right none)
  (map (lambda (n) (markdown-node-property n 'alignment))
       (markdown-node-children
        (car (nodes-of-type (ext-ast table-md) 'table-row)))))
(test-equal "body cells carry the same alignments as the header"
  '(left right none)
  (map (lambda (n) (markdown-node-property n 'alignment))
       (markdown-node-children
        (cadr (nodes-of-type (ext-ast table-md) 'table-row)))))

;; Task detection comes from the type string, because
;; get_tasklist_item_checked cannot distinguish an unchecked task from a
;; non-task (tasklist.c:30-40). All three cases are asserted together, since
;; that is the discrimination a single-case test would miss.
;; Sentinel defaults for the same reason as the loose-list assertion in Task 6:
;; the plain item's expected pair is (#f . #f), which a two-argument lookup would
;; also produce if plain-item-props stopped emitting either key at all.
(test-equal "checked, unchecked, and plain items are all distinguished"
  '((#t . #t) (#t . #f) (#f . #f))
  (map (lambda (n) (cons (markdown-node-property n 'task? 'absent)
                         (markdown-node-property n 'checked? 'absent)))
       (nodes-of-type (ext-ast "- [x] done\n- [ ] todo\n\n* plain\n") 'item)))

(test-equal "a task item still carries its index"
  0 (markdown-node-property
     (first-of-type (ext-ast "- [x] done\n") 'item) 'index))

;; Two independent channels for the same fact: the type string
;; (table.c:523-535) and the extension accessor. Redundancy turned into a
;; cross-check for one assertion's worth of effort.
(test-equal "header? agrees with cmark's own row accessor on every row"
  (quote ())
  (call-with-native-document
   table-md (option-bits #f #f #f #f #f #f) all-exts
   (lambda (h)
     (let* ((tree (convert-document h (make-convert-ctx 250000 1000 #f)))
            (ours (map (lambda (n) (markdown-node-property n 'header?))
                       (nodes-of-type tree 'table-row)))
            ;; walk to the table's rows natively: document -> table -> rows
            (table (node-first-child (doc-root h)))
            (theirs (let loop ((r (node-first-child table)) (acc (quote ())))
                      (if (zero? r)
                          (reverse acc)
                          (loop (node-next r)
                                (cons (not (zero? (table-row-is-header r)))
                                      acc))))))
       (if (equal? ours theirs) (quote ()) (list ours theirs))))))

;; --- key sets and coverage for the extension types ----------------------
(test-equal "the table has an entry for every reachable extension type string"
  (quote ())
  (filter (lambda (ts) (not (type-string->entry ts)))
          '("strikethrough" "tasklist" "table" "table_header" "table_row"
            "table_cell")))

(test-equal "the table covers exactly the 24 reachable type strings and no more"
  24 (length (node-table-type-strings)))

(test-equal "extension nodes' key sets are exactly what the table declares"
  (quote ())
  (let ((tree (ext-ast (string-append table-md "\n~~s~~\n\n- [x] a\n- [ ] b\n"))))
    (reverse
     (markdown-node-fold
      (lambda (n acc)
        (let* ((ts (case (markdown-node-type n)
                     ((strikethrough) "strikethrough")
                     ((table) "table")
                     ((table-row) (if (markdown-node-property n 'header?)
                                      "table_header" "table_row"))
                     ((table-cell) "table_cell")
                     ((item) (if (markdown-node-property n 'task?)
                                 "tasklist" "item"))
                     (else #f)))
               (entry (and ts (type-string->entry ts))))
          (if (not entry)
              acc
              (let ((declared (list-sort symbol<? (node-entry-keys entry)))
                    (actual (list-sort symbol<?
                                       (map car (markdown-node-properties n)))))
                (if (equal? declared actual)
                    acc
                    (cons (list (markdown-node-type n) declared actual) acc))))))
      (quote ()) tree))))

(test-equal "extension trees also outlive the native document"
  '("s" "a" "b")
  (let ((escaped-ext (ext-ast "~~s~~\n\n- [x] a\n- [ ] b\n")))
    (map (lambda (n) (markdown-node-property n 'literal))
         (nodes-of-type escaped-ext 'text))))
(test-equal "extension conversion released every native allocation"
  '(0 0 0) (live-counts))

(test-end "convert")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
