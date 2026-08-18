#!r6rs
;;; The AST -> SXML adapter -- the functional core.
;;;
;;; Imports no library that loads a shared object, directly or transitively:
;;; (cmark gfm ast), (cmark gfm options), and (cmark gfm private conditions)
;;; are all pure. That is what lets tests/test-sxml.sps run with no shared
;;; object loaded, so no assertion in it can pass by accident because of
;;; native behaviour. `make check-purity` enforces it.
;;;
;;; The tree carries HTML VOCABULARY ONLY (ADR-0011). List delimiter, item
;;; index, fence info past the first token, image child structure, and all
;;; source positions are dropped here; markdown->ast remains the interface
;;; for them. That is what makes ADR-0012's oracle total.
;;;
;;; Literals are carried VERBATIM. Escaping belongs to whatever serializer
;;; the caller runs; escaping here would double-escape on output.
(library (cmark gfm sxml)
  (export markdown-ast->sxml)
  (import (rnrs)
          (cmark gfm ast)
          (cmark gfm options)
          (cmark gfm private conditions))

  (define (prop n key) (markdown-node-property n key))

  ;; tight? is the enclosing LIST's flag (html.c:287-297 reads it off a
  ;; paragraph's GRANDPARENT), threaded through every call so it can reach a
  ;; paragraph two levels down. A spliced paragraph (see the `paragraph`
  ;; case below) returns a `splice` marker instead of a value; this is the
  ;; one place that must flatten it back into the surrounding child list.
  (define (children->sxml n raw-html tight?)
    (let loop ((cs (markdown-node-children n)) (acc '()))
      (if (null? cs)
          (reverse acc)
          (let ((s (node->sxml (car cs) raw-html tight?)))
            (loop (cdr cs)
                  (if (and (pair? s) (eq? 'splice (car s)))
                      (append (reverse (cdr s)) acc)
                      (cons s acc)))))))

  (define (element tag n raw-html tight?)
    (cons tag (children->sxml n raw-html tight?)))

  ;; The first whitespace-delimited token of the info string, per
  ;; html.c:223-227.
  (define (first-token s)
    (let loop ((i 0))
      (cond ((>= i (string-length s)) s)
            ((memv (string-ref s i) '(#\space #\tab #\newline #\return))
             (substring s 0 i))
            (else (loop (+ i 1))))))

  (define (code-block->sxml n)
    (let ((literal (prop n 'literal))
          (info    (first-token (prop n 'fence-info))))
      (list 'pre
            (if (string=? "" info)
                (list 'code literal)
                (list 'code
                      (list '\x40; (list 'class (string-append "language-" info)))
                      literal)))))

  ;; html.c:259,337 -- the SAME comment for a block and an inline. Which one
  ;; it was is recoverable from the tree position, which is how the
  ;; serializer decides its newlines.
  (define (raw-html->sxml n raw-html)
    (if (eq? 'escape raw-html)
        (prop n 'literal)
        (list '*COMMENT* " raw HTML omitted ")))

  ;; --- URLs --------------------------------------------------------------
  ;; HREF_SAFE, transcribed from src/houdini_href_e.c:32-44. Every other
  ;; byte becomes %XX. & and ' are NOT handled here: houdini_escape_href
  ;; writes them as HTML entities, which is serialization, not a property of
  ;; the value. Doing both halves in one place double-encodes whichever ran
  ;; second (design spec 5.3).
  ;; Transcribed from the TABLE BYTES, not from the comment above them -- the
  ;; comment lists a slightly different set. Safe: alphanumeric plus
  ;;   ! # $ % ( ) * + , - . / : ; = ? @ _ ~
  ;; & and ' are absent from the table because houdini handles them
  ;; specially; they are included HERE so they pass through untouched for
  ;; the serializer to entity-escape.
  (define href-safe-extra
    (string->list "!#$%()*+,-./:;=?@_~&'"))

  (define (href-safe-byte? b)
    (let ((c (integer->char b)))
      (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9)
          (memv c href-safe-extra))))

  (define hex "0123456789ABCDEF")

  (define (percent-encode s)
    (let-values (((port get) (open-string-output-port)))
      (let ((bv (string->utf8 s)))
        (do ((i 0 (+ i 1))) ((= i (bytevector-length bv)))
          (let ((b (bytevector-u8-ref bv i)))
            (if (href-safe-byte? b)
                (put-char port (integer->char b))
                (begin (put-char port #\%)
                       (put-char port (string-ref hex (div b 16)))
                       (put-char port (string-ref hex (mod b 16))))))))
      (get)))

  ;; ASCII-only on purpose. string-downcase is Unicode-aware and can change
  ;; a string's LENGTH, which would misalign the prefix tests below; scheme
  ;; names are ASCII, so this is both correct and total.
  ;;
  ;; Built from string->list/map/list->string rather than string-map: plain
  ;; (rnrs) binds string-for-each but NOT string-map (confirmed against
  ;; Chez -- string-map raises "unbound identifier"), and mutable-string
  ;; operations such as string-set! live in the separate (rnrs
  ;; mutable-strings) library, not in the (rnrs) union either. string->list,
  ;; map, and list->string are all plain (rnrs) and already in use above for
  ;; href-safe-extra.
  (define (ascii-downcase s)
    (list->string
     (map (lambda (c)
            (if (char<=? #\A c #\Z)
                (integer->char (+ 32 (char->integer c)))
                c))
          (string->list s))))

  (define (prefix? p s)
    (and (>= (string-length s) (string-length p))
         (string=? p (substring s 0 (string-length p)))))

  ;; src/scanners.re:345-354. The data:image allowlist is checked FIRST,
  ;; exactly as re2c orders the rules, so data:image/png survives the
  ;; data: rejection that follows it.
  (define (dangerous-url? url)
    (let ((u (ascii-downcase url)))
      (cond
        ((or (prefix? "data:image/png"  u) (prefix? "data:image/gif"  u)
             (prefix? "data:image/jpeg" u) (prefix? "data:image/webp" u))
         #f)
        ((or (prefix? "javascript:" u) (prefix? "vbscript:" u)
             (prefix? "file:" u) (prefix? "data:" u))
         #t)
        (else #f))))

  ;; A rejected URL yields an empty value, matching html.c:387-391 and
  ;; html.c:405-409. Not a raise: this mirrors cmark's renderer, and a
  ;; document with one bad link should still convert.
  (define (safe-url url)
    (if (dangerous-url? url) "" (percent-encode url)))

  ;; --- image alt ---------------------------------------------------------
  ;; html.c:122-139, plain mode.
  (define (plain-text n port)
    (case (markdown-node-type n)
      ((text code html-inline) (put-string port (prop n 'literal)))
      ((softbreak linebreak)   (put-char port #\space))
      (else
       ;; Contributes nothing itself, but its children still render --
       ;; the plain-mode branch returns before the element markup, it does
       ;; not skip the subtree.
       (for-each (lambda (c) (plain-text c port))
                 (markdown-node-children n)))))

  (define (alt-text n)
    (let-values (((port get) (open-string-output-port)))
      (for-each (lambda (c) (plain-text c port)) (markdown-node-children n))
      (get)))

  (define (maybe-title title)
    (if (string=? "" title) '() (list (list 'title title))))

  ;; --- tables ------------------------------------------------------------
  ;; A fold over the row list, not a per-node rewrite: the AST is flat
  ;; (table -> row(header?) -> cell) and HTML is nested. extensions/table.c
  ;; :774-797 -- a header row opens and closes <thead> around itself; the
  ;; first non-header row opens <tbody>, which stays open until the table
  ;; ends. Either section is absent when it has no rows.
  (define (table->sxml n raw-html)
    (let loop ((rows (markdown-node-children n)) (i 0) (head '()) (body '()))
      (cond
        ((null? rows)
         (cons 'table
               (append
                (if (null? head) '() (list (cons 'thead (reverse head))))
                (if (null? body) '() (list (cons 'tbody (reverse body)))))))
        (else
         (let* ((r (car rows))
                (header? (markdown-node-property r 'header?)))
           ;; The parser cannot produce a header row anywhere but first:
           ;; extensions/table.c:402-403 sets is_header exactly once, on the
           ;; row synthesised when the table block opens, and every later row
           ;; is calloc'd false (table.c:447). markdown-ast->sxml is public
           ;; and takes an arbitrary tree, though, so a caller who built or
           ;; rewrote one can hand us an order the parser never makes.
           ;;
           ;; Raising beats both alternatives. Bucketing every header row into
           ;; one merged thead is silently NOT what cmark does -- table.c
           ;; :777-780,792-795 opens and closes a thead around each header row,
           ;; with no accumulation guard like tbody's need_closing_table_body.
           ;; And reproducing cmark exactly is worse still: its header-after-
           ;; body output opens a thead while a tbody is still open, which is
           ;; not well-formed HTML.
           (when (and header? (positive? i))
             (raise (make-cmark-malformed-tree 'header-row-not-first)))
           ;; Bound after the guard, not before it: rendering a row we are
           ;; about to reject wastes the work, and an unsupported node inside
           ;; that row would raise first and mask the more specific diagnosis.
           (let ((tr (cons 'tr (map (lambda (c) (cell->sxml c header? raw-html))
                                    (markdown-node-children r)))))
             (if header?
                 (loop (cdr rows) (+ i 1) (cons tr head) body)
                 (loop (cdr rows) (+ i 1) head (cons tr body)))))))))

  (define (cell->sxml c header? raw-html)
    (let ((tag   (if header? 'th 'td))
          (align (markdown-node-property c 'alignment))
          ;; A cell holds inlines only, so tightness cannot reach here.
          (kids  (children->sxml c raw-html #f)))
      (if (memq align '(left center right))
          (cons tag (cons (list '\x40; (list 'align (symbol->string align)))
                          kids))
          (cons tag kids))))

  ;; tight? is #f at every call except the one the `list` and `item` cases
  ;; make for their own children -- see the comment on children->sxml.
  (define (node->sxml n raw-html tight?)
    (case (markdown-node-type n)
      ((document)   (cons '*TOP* (children->sxml n raw-html tight?)))
      ((paragraph)
       ;; html.c:287-297: inside a tight list the paragraph contributes its
       ;; children directly, with no element of its own. `tight?` is the
       ;; enclosing LIST's flag, threaded down through the item, because a
       ;; paragraph cannot see its own grandparent here.
       (if tight?
           (cons 'splice (children->sxml n raw-html tight?))
           (element 'p n raw-html tight?)))
      ;; NOT `tight?` -- html.c:288-289 requires the paragraph's grandparent
      ;; to BE the list node itself. Once a blockquote sits between an item
      ;; and a paragraph, that paragraph's grandparent is the item, never a
      ;; list, so cmark always gives it a <p>. Confirmed empirically: cmark
      ;; renders "- > q\n- b\n" (a tight list) as
      ;; "<blockquote>\n<p>q</p>\n</blockquote>", not
      ;; "<blockquote>\nq\n</blockquote>". Threading the incoming tight?
      ;; through unchanged, as every other container in this dispatch does,
      ;; would splice that paragraph and disagree with cmark.
      ((blockquote) (element 'blockquote n raw-html #f))
      ((emph)       (element 'em n raw-html tight?))
      ((strong)     (element 'strong n raw-html tight?))
      ((strikethrough) (element 'del n raw-html tight?))
      ((heading)
       (cons (string->symbol
              (string-append "h" (number->string (prop n 'level))))
             (children->sxml n raw-html tight?)))
      ((text)       (prop n 'literal))
      ((code)       (list 'code (prop n 'literal)))
      ((code-block) (code-block->sxml n))
      ((thematic-break) '(hr))
      ((linebreak)  '(br))
      ((softbreak)  "\n")
      ((html-block html-inline) (raw-html->sxml n raw-html))
      ((link)
       (cons 'a
             (cons (cons '\x40; (cons (list 'href (safe-url (prop n 'url)))
                                  (maybe-title (prop n 'title))))
                   (children->sxml n raw-html tight?))))
      ((image)
       (list 'img
             (cons '\x40; (cons (list 'src (safe-url (prop n 'url)))
                            (cons (list 'alt (alt-text n))
                                  (maybe-title (prop n 'title)))))))
      ((list)
       ;; A list's children never inherit tightness from an outer list --
       ;; only its OWN tight? property governs the items directly inside
       ;; it. That is what keeps tightness from leaking into a nested list.
       (let ((kids (children->sxml n raw-html (prop n 'tight?)))
             (start (prop n 'start)))
         (if (eq? 'ordered (prop n 'kind))
             (if (= 1 start)
                 (cons 'ol kids)
                 (cons 'ol (cons (list '\x40; (list 'start (number->string start)))
                                 kids)))
             (cons 'ul kids))))
      ((item)
       ;; extensions/tasklist.c:124-128: a checked box carries type, checked,
       ;; disabled in that order; an UNCHECKED box has no checked attribute
       ;; at all -- emitting checked="" unconditionally is a byte
       ;; difference, not a harmless default.
       (let ((kids (children->sxml n raw-html tight?)))
         (cons 'li
               (if (prop n 'task?)
                   (cons (list 'input
                               (cons '\x40;
                                     (cons '(type "checkbox")
                                           (append
                                            (if (prop n 'checked?)
                                                '((checked ""))
                                                '())
                                            '((disabled ""))))))
                         (cons " " kids))
                   kids))))
      ((table) (table->sxml n raw-html))
      ((extension)
       (raise (make-cmark-unsupported-node (prop n 'native-type))))
      (else
       ;; A node type this library produces but the adapter has not mapped.
       ;; Reported through the same condition rather than silently dropped.
       (raise (make-cmark-unsupported-node
               (symbol->string (markdown-node-type n)))))))

  (define markdown-ast->sxml
    (case-lambda
      ((ast) (markdown-ast->sxml ast (default-sxml-options)))
      ((ast o)
       (unless (sxml-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       (node->sxml ast (sxml-options-raw-html o) #f)))))
