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

  (define (children->sxml n raw-html)
    (map (lambda (c) (node->sxml c raw-html)) (markdown-node-children n)))

  (define (element tag n raw-html)
    (cons tag (children->sxml n raw-html)))

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

  (define (node->sxml n raw-html)
    (case (markdown-node-type n)
      ((document)   (cons '*TOP* (children->sxml n raw-html)))
      ((paragraph)  (element 'p n raw-html))
      ((blockquote) (element 'blockquote n raw-html))
      ((emph)       (element 'em n raw-html))
      ((strong)     (element 'strong n raw-html))
      ((strikethrough) (element 'del n raw-html))
      ((heading)
       (cons (string->symbol
              (string-append "h" (number->string (prop n 'level))))
             (children->sxml n raw-html)))
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
                   (children->sxml n raw-html))))
      ((image)
       (list 'img
             (cons '\x40; (cons (list 'src (safe-url (prop n 'url)))
                            (cons (list 'alt (alt-text n))
                                  (maybe-title (prop n 'title)))))))
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
       (node->sxml ast (sxml-options-raw-html o))))))
