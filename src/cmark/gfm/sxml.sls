#!r6rs
;;; Pure AST-to-SXML adapter. Keep its transitive imports free of native code.
;;; The result carries HTML vocabulary, not lossless Markdown structure.
;;; Preserve literals verbatim; the serializer owns escaping.
(library (cmark gfm sxml)
  (export markdown-ast->sxml)
  (import (rnrs)
          (cmark gfm ast)
          (cmark gfm options)
          (cmark gfm private conditions))

  (define (prop n key) (markdown-node-property n key))

  ;; Compute one attribute marker per document. Spell @ as \x40; because the
  ;; #!r6rs reader rejects it as a bare symbol token. The available Akku
  ;; serializers require ^ and silently misrender @.
  (define (marker opts)
    (if (eq? 'at (sxml-options-attribute-marker opts)) '\x40; '^))

  ;; tight? belongs to the enclosing list and reaches paragraphs through list
  ;; items. parent-type controls only direct-parent rules such as nested strong.
  ;; Flatten the internal splice marker here and nowhere else.
  (define (children->sxml n opts mark tight?)
    (let ((parent-type (markdown-node-type n)))
      (let loop ((cs (markdown-node-children n)) (acc '()))
        (if (null? cs)
            (reverse acc)
            (let ((s (node->sxml (car cs) opts mark tight? parent-type)))
              (loop (cdr cs)
                    (if (and (pair? s) (eq? 'splice (car s)))
                        (append (reverse (cdr s)) acc)
                        (cons s acc))))))))

  (define (element tag n opts mark tight?)
    (cons tag (children->sxml n opts mark tight?)))

  ;; cmark uses only the first whitespace-delimited info token as the class.
  (define (first-token s)
    (let loop ((i 0))
      (cond ((>= i (string-length s)) s)
            ((memv (string-ref s i) '(#\space #\tab #\newline #\return))
             (substring s 0 i))
            (else (loop (+ i 1))))))

  (define (code-block->sxml n mark)
    (let ((literal (prop n 'literal))
          (info    (first-token (prop n 'fence-info))))
      (list 'pre
            (if (string=? "" info)
                (list 'code literal)
                (list 'code
                      (list mark (list 'class (string-append "language-" info)))
                      literal)))))

  ;; Block and inline raw HTML use the same omission marker.
  (define (raw-html->sxml n opts)
    (if (eq? 'escape (sxml-options-raw-html opts))
        (prop n 'literal)
        (list '*COMMENT* " raw HTML omitted ")))

  ;; Match cmark's HREF_SAFE bytes. Leave & and ' for the serializer to
  ;; entity-escape; percent-encoding them here would double-encode output.
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

  ;; URL schemes are ASCII. Unicode downcasing can change string length and is
  ;; unnecessary here; string-map is not part of (rnrs).
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

  ;; Check the data:image allowlist before the broader data: rejection; unlike
  ;; cmark's longest-match scanner, cond is first-match.
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

  ;; Match cmark by replacing dangerous URLs with "" rather than raising.
  (define (safe-url url)
    (if (dangerous-url? url) "" (percent-encode url)))

  ;; Image alt text uses cmark's plain-text traversal.
  (define (plain-text n port)
    (case (markdown-node-type n)
      ((text code html-inline) (put-string port (prop n 'literal)))
      ((softbreak linebreak)   (put-char port #\space))
      (else
       ;; Unknown containers contribute their children but no markup.
       (for-each (lambda (c) (plain-text c port))
                 (markdown-node-children n)))))

  (define (alt-text n)
    (let-values (((port get) (open-string-output-port)))
      (for-each (lambda (c) (plain-text c port)) (markdown-node-children n))
      (get)))

  (define (maybe-title title)
    (if (string=? "" title) '() (list (list 'title title))))

  ;; The AST has flat rows; SXML groups them into optional thead and tbody.
  (define (table->sxml n opts mark)
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
           ;; The parser can mark only the first row as a header. Reject a
           ;; caller-built later header instead of emitting malformed HTML.
           (when (and header? (positive? i))
             (raise (make-cmark-malformed-tree 'header-row-not-first)))
           ;; Validate before rendering so the specific shape error wins.
           (let ((tr (cons 'tr (map (lambda (c) (cell->sxml c header? opts mark))
                                    (markdown-node-children r)))))
             (if header?
                 (loop (cdr rows) (+ i 1) (cons tr head) body)
                 (loop (cdr rows) (+ i 1) head (cons tr body)))))))))

  (define (cell->sxml c header? opts mark)
    (let ((tag   (if header? 'th 'td))
          (align (markdown-node-property c 'alignment))
          ;; Cells contain inlines, so list tightness does not apply.
          (kids  (children->sxml c opts mark #f)))
      (if (memq align '(left center right))
          (cons tag (cons (list mark (list 'align (symbol->string align)))
                          kids))
          (cons tag kids))))

  ;; parent-type is #f at the root. tight? applies only while traversing a
  ;; list's item/paragraph path.
  (define (node->sxml n opts mark tight? parent-type)
    (case (markdown-node-type n)
      ((document)   (cons '*TOP* (children->sxml n opts mark tight?)))
      ((paragraph)
       ;; Tight-list paragraphs splice their children instead of emitting p.
       (if tight?
           (cons 'splice (children->sxml n opts mark tight?))
           (element 'p n opts mark tight?)))
      ;; Blockquotes break the direct list-item/paragraph relationship, so do
      ;; not propagate tightness into them.
      ((blockquote) (element 'blockquote n opts mark #f))
      ((emph)       (element 'em n opts mark tight?))
      ;; cmark splices a strong node whose direct parent is strong. Emph does
      ;; not have this rule.
      ((strong)
       (if (eq? 'strong parent-type)
           (cons 'splice (children->sxml n opts mark tight?))
           (element 'strong n opts mark tight?)))
      ((strikethrough) (element 'del n opts mark tight?))
      ((heading)
       (cons (string->symbol
              (string-append "h" (number->string (prop n 'level))))
             (children->sxml n opts mark tight?)))
      ((text)       (prop n 'literal))
      ((code)       (list 'code (prop n 'literal)))
      ((code-block) (code-block->sxml n mark))
      ((thematic-break) '(hr))
      ((linebreak)  '(br))
      ;; Only softbreak uses this policy; linebreak is always br.
      ((softbreak)
       (case (sxml-options-softbreak opts)
         ((break) '(br))
         ((space) " ")
         (else    "\n")))
      ((html-block html-inline) (raw-html->sxml n opts))
      ((link)
       (cons 'a
             (cons (cons mark (cons (list 'href (safe-url (prop n 'url)))
                                    (maybe-title (prop n 'title))))
                   (children->sxml n opts mark tight?))))
      ((image)
       (list 'img
             (cons mark (cons (list 'src (safe-url (prop n 'url)))
                              (cons (list 'alt (alt-text n))
                                    (maybe-title (prop n 'title)))))))
      ((list)
       ;; Nested lists use their own tightness, never the outer list's.
       (let ((kids (children->sxml n opts mark (prop n 'tight?)))
             (start (prop n 'start)))
         (if (eq? 'ordered (prop n 'kind))
             ;; Omit the default start=1 attribute, matching cmark.
             (if (= 1 start)
                 (cons 'ol kids)
                 (cons 'ol (cons (list mark (list 'start (number->string start)))
                                 kids)))
             (cons 'ul kids))))
      ((item)
       ;; Unchecked task boxes omit the checked attribute entirely.
       (let ((kids (children->sxml n opts mark tight?)))
         (cons 'li
               (if (prop n 'task?)
                   (cons (list 'input
                               (cons mark
                                     (cons '(type "checkbox")
                                           (append
                                            (if (prop n 'checked?)
                                                '((checked ""))
                                                '())
                                            '((disabled ""))))))
                         (cons " " kids))
                   kids))))
      ((table) (table->sxml n opts mark))
      ((extension)
       (raise (make-cmark-unsupported-node (prop n 'native-type))))
      (else
       ;; Never silently drop an unmapped AST node.
       (raise (make-cmark-unsupported-node
               (symbol->string (markdown-node-type n)))))))

  ;; markdown-ast->sxml : markdown-node -> sxml
  ;; markdown-ast->sxml : markdown-node sxml-options -> sxml
  ;; Caller-built trees are otherwise trusted as well-typed. The one explicit
  ;; shape check rejects a non-leading table header, which would make malformed
  ;; HTML; ordinary record mismatches may raise R6RS assertion conditions.
  (define markdown-ast->sxml
    (case-lambda
      ((ast) (markdown-ast->sxml ast (default-sxml-options)))
      ((ast o)
       (unless (sxml-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       (node->sxml ast o (marker o) #f #f)))))
