#!r6rs
;;; SXML -> HTML, written against vendor/cmark-gfm/src/html.c. TEST ONLY.
;;;
;;; This is one half of ADR-0012's oracle. It is deliberately GENERIC over
;;; the tree: it maps an element name to a tag, an attribute list to
;;; attributes, and consults the static tables below for childless tags and
;;; newline placement. It never inspects the Markdown and holds no node-type
;;; knowledge, so it cannot compensate for an adapter that emits the wrong
;;; element -- a wrong tag is a byte difference, not a serializer that
;;; quietly agrees.
;;;
;;; Not under src/: this ships with the tests, and the library is reachable
;;; because the Makefile puts tests/ on CHEZ_LIBDIRS.
(library (sxml-html-serializer)
  (export sxml->html)
  (import (rnrs))

  ;; --- escaping ----------------------------------------------------------
  ;; houdini_escape_html0 with secure = 0 (src/houdini_html_e.c:18-33).
  ;; Exactly four characters. ' and / are escaped only in secure mode, which
  ;; html.c never requests.
  (define (escape-html s port)
    (string-for-each
     (lambda (c)
       (case c
         ((#\&) (put-string port "&amp;"))
         ((#\<) (put-string port "&lt;"))
         ((#\>) (put-string port "&gt;"))
         ((#\") (put-string port "&quot;"))
         (else  (put-char port c))))
     s))

  ;; The ENTITY half of houdini_escape_href (src/houdini_href_e.c:64-76).
  ;; The percent-encoding half belongs to the adapter, not here: doing both
  ;; in one place would double-encode whichever side ran second.
  (define (escape-href s port)
    (string-for-each
     (lambda (c)
       (case c
         ((#\&)  (put-string port "&amp;"))
         ((#\')  (put-string port "&#x27;"))
         (else   (put-char port c))))
     s))

  (define (href-attribute? name) (memq name '(href src)))

  ;; --- formatting tables -------------------------------------------------
  ;; Every entry is a line of html.c. Changing one to make a test pass is
  ;; changing what cmark does, which the differential will reject.

  ;; Written " />" and given no children (html.c:280-285, 315-317, 402-419;
  ;; extensions/tasklist.c:125-128).
  (define void-tags '(hr br img input))

  ;; Void tags followed by a literal newline: hr (html.c:284) and br
  ;; (html.c:316). img and input are inline and get none.
  (define void-tags-with-newline '(hr br))

  ;; cmark_html_render_cr before the OPEN tag.
  (define cr-before-open
    '(blockquote ul ol li h1 h2 h3 h4 h5 h6 pre p hr
      table thead tbody tr th td))

  ;; cmark_html_render_cr after the open tag (html.c:154,171,176,181 write
  ;; ">\n"; extensions/table.c:780,783 write the tag then render_cr).
  (define cr-after-open '(blockquote ul ol thead tbody))

  ;; cmark_html_render_cr before the CLOSE tag (html.c:158;
  ;; extensions/table.c:765,770,790,793).
  (define cr-before-close '(blockquote table thead tbody tr))

  ;; A literal newline after the close tag (html.c:159,191,197,211,254,301;
  ;; extensions/table.c:772 uses render_cr, same effect at end of table).
  (define newline-after-close
    '(blockquote ul ol li h1 h2 h3 h4 h5 h6 pre p table tbody))

  ;; A *COMMENT* directly inside one of these is a block comment and takes
  ;; render_cr on both sides (html.c:257,265). Anywhere else it is inline
  ;; and takes none (html.c:335-337). Block-level content only ever appears
  ;; in these three containers.
  (define block-comment-parents '(*TOP* blockquote li))

  ;; --- output ------------------------------------------------------------
  ;; BOTH markers open an attribute list (ADR-0013). '^ is what the adapter
  ;; emits by default, because it is what wak-sxml-tools and wak-htmlprag
  ;; read; '\x40; is what it emits under 'attribute-marker 'at, the SXML
  ;; specification's own spelling. Accepting either is what lets one
  ;; serializer judge both dialects, so test-sxml-differential.sps can run
  ;; its corpus sweep once per marker instead of covering one with the
  ;; oracle and the other with a handful of assertions.
  ;;
  ;; \x40; is R6RS's inline hex escape for '@' -- see the matching comment in
  ;; test-sxml-serializer.sps: Chez's strict #!r6rs reader, which `chez
  ;; --program` enforces on every file it loads (including this one), rejects
  ;; a bare '@' token. \x40; reads as the exact same interned symbol.
  ;;
  ;; This is a two-element memq, not a wildcard: a tree marked with some
  ;; THIRD symbol must still serialize as an element, because that is what it
  ;; is. The serializer stays generic over the tree either way -- it learns
  ;; no node-type knowledge here, only one extra spelling of one marker.
  (define (attributes? x)
    (and (pair? x) (memq (car x) '(^ \x40;)) #t))

  (define (write-attributes attrs port)
    (for-each
     (lambda (a)
       (put-char port #\space)
       (put-string port (symbol->string (car a)))
       (put-string port "=\"")
       (if (href-attribute? (car a))
           (escape-href (cadr a) port)
           (escape-html (cadr a) port))
       (put-char port #\"))
     (cdr attrs)))

  (define (sxml->html tree)
    ;; Chunks accumulate in reverse and are joined once. render_cr's "only if
    ;; the buffer does not already end in a newline" rule needs one bit of
    ;; history, not the buffer itself, so last-newline? carries it -- which
    ;; keeps this linear instead of re-copying a growing string per emit.
    (let ((chunks '()) (last-newline? #f))
      (define (emit s)
        (when (positive? (string-length s))
          (set! chunks (cons s chunks))
          (set! last-newline?
                (char=? #\newline (string-ref s (- (string-length s) 1))))))
      ;; The (pair? chunks) guard is html.c's `html->size &&`: no newline is
      ;; emitted before anything has been written.
      (define (emit-cr)
        (when (and (pair? chunks) (not last-newline?)) (emit "\n")))
      (define (with-port proc)
        (let-values (((port get) (open-string-output-port)))
          (proc port)
          (emit (get))))

      (define (walk node parent)
        (cond
          ((string? node) (with-port (lambda (p) (escape-html node p))))
          ((and (pair? node) (eq? '*COMMENT* (car node)))
           (let ((block? (memq parent block-comment-parents)))
             (when block? (emit-cr))
             (emit "<!--") (emit (cadr node)) (emit "-->")
             (when block? (emit-cr))))
          ((and (pair? node) (eq? '*TOP* (car node)))
           (for-each (lambda (c) (walk c '*TOP*)) (cdr node)))
          ((pair? node)
           (let* ((tag  (car node))
                  (rest (cdr node))
                  (attrs (and (pair? rest) (attributes? (car rest))
                              (car rest)))
                  (kids (if attrs (cdr rest) rest))
                  (name (symbol->string tag)))
             (when (memq tag cr-before-open) (emit-cr))
             (emit "<") (emit name)
             (when attrs (with-port (lambda (p) (write-attributes attrs p))))
             (cond
               ((memq tag void-tags)
                (emit " />")
                (when (memq tag void-tags-with-newline) (emit "\n")))
               (else
                (emit ">")
                (when (memq tag cr-after-open) (emit-cr))
                (for-each (lambda (c) (walk c tag)) kids)
                (when (memq tag cr-before-close) (emit-cr))
                (emit "</") (emit name) (emit ">")
                (when (memq tag newline-after-close) (emit "\n"))))))
          (else (assertion-violation 'sxml->html "not an SXML node" node))))

      (walk tree #f)
      (apply string-append (reverse chunks)))))
