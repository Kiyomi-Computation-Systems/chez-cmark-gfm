#!r6rs
;;; The native-to-Scheme AST copy -- the imperative shell.
;;;
;;; This is the only library that walks a native tree. Three rules govern it:
;;;
;;;   1. Dispatch on cmark_node_get_type_string, never on the node-type enum.
;;;      The extension node types are assigned at RUNTIME by
;;;      cmark_syntax_extension_add_node (extensions/table.c:871-873), so
;;;      their numeric values are not constants at all.
;;;
;;;   2. Every borrowed string is copied at the moment of read. There is no
;;;      lazy read: the tree must be fully materialised before the enclosing
;;;      call-with-native-document scope exits, because that is what makes the
;;;      result valid after teardown.
;;;
;;;   3. This library takes PRIMITIVES, never the options record. Layer 2 must
;;;      not import layer 3; parse.sls unpacks the record, exactly as
;;;      render.sls unpacks option bits.
;;;
;;; convert-node takes the type string as an ARGUMENT rather than reading it
;;; from the node. That is deliberate: it is the only way to exercise the
;;; unknown-type branch, which cmark cannot be made to produce through this
;;; library's options (design spec 7).
(library (cmark gfm private convert)
  (export convert-document convert-node make-convert-ctx
          type-string->entry
          node-entry-type node-entry-keys node-entry-extractor
          node-table-type-strings)
  (import (rnrs)
          (cmark gfm ast)
          (cmark gfm private native)
          (cmark gfm private scope)
          (cmark gfm private conditions))

  ;; --- conversion context ----------------------------------------------
  ;; count is mutable and threaded by reference rather than returned, so the
  ;; recursion stays a plain tree walk instead of a state-passing fold.
  (define-record-type (convert-ctx %make-convert-ctx convert-ctx?)
    (fields (mutable count) max-nodes max-depth positions?))

  (define (make-convert-ctx max-nodes max-depth positions?)
    (%make-convert-ctx 0 max-nodes max-depth positions?))

  ;; --- borrowed strings -------------------------------------------------
  ;; c-string->string maps NULL to #f. For every property the table declares,
  ;; the accessor is called only on a node type that supports it, so NULL is
  ;; unreachable -- but writing #f where a string is documented would be a
  ;; silent lie about the document's contents, so this raises instead. The
  ;; unreachability is recorded as a deliberate gap (design spec 12).
  (define (copy-required addr)
    (let ((s (c-string->string addr)))
      (or s (raise (make-cmark-error)))))

  ;; --- property extractors ---------------------------------------------
  ;; One procedure per shape, shared where the shape is shared, so there is
  ;; one place to fix each mapping.
  (define (literal-props p)
    (list (cons 'literal (copy-required (node-literal p)))))

  (define (heading-props p)
    (list (cons 'level (node-heading-level p))))

  (define (code-block-props p)
    (list (cons 'literal (copy-required (node-literal p)))
          (cons 'fence-info (copy-required (node-fence-info p)))))

  (define (link-props p)
    (list (cons 'url (copy-required (node-url p)))
          (cons 'title (copy-required (node-title p)))))

  ;; cmark's numeric list constants stop here: 1 = CMARK_BULLET_LIST,
  ;; 2 = CMARK_ORDERED_LIST; 1 = CMARK_PERIOD_DELIM, 2 = CMARK_PAREN_DELIM.
  (define (list-props p)
    (list (cons 'kind (if (= 2 (node-list-type p)) 'ordered 'bullet))
          (cons 'start (node-list-start p))
          (cons 'tight? (not (zero? (node-list-tight p))))
          (cons 'delimiter
                (case (node-list-delim p)
                  ((1) 'period)
                  ((2) 'paren)
                  (else 'none)))))

  ;; Uniform key set with the task variant below (design spec 3.4): a
  ;; consumer never branches on key presence, and the key-set check compares a
  ;; fixed set rather than a conditional one.
  (define (plain-item-props p)
    (list (cons 'index (node-item-index p))
          (cons 'task? #f)
          (cons 'checked? #f)))

  ;; --- the table --------------------------------------------------------
  ;; type string -> node type, declared property keys, extractor (#f for
  ;; propertyless types). The declared keys are DATA so the suite can assert
  ;; that what an extractor produces is exactly what the table promises.
  ;; Four fields: the cmark type string (the dispatch key), the node-type
  ;; symbol the AST uses, the declared property keys, and the extractor.
  (define-record-type (node-entry make-node-entry node-entry?)
    (fields type-string type keys extractor))

  (define node-table
    (list
     (make-node-entry "document"       'document       '() #f)
     (make-node-entry "paragraph"      'paragraph      '() #f)
     (make-node-entry "block_quote"    'blockquote     '() #f)
     (make-node-entry "thematic_break" 'thematic-break '() #f)
     (make-node-entry "softbreak"      'softbreak      '() #f)
     (make-node-entry "linebreak"      'linebreak      '() #f)
     (make-node-entry "emph"           'emph           '() #f)
     (make-node-entry "strong"         'strong         '() #f)
     (make-node-entry "heading"        'heading        '(level) heading-props)
     (make-node-entry "text"           'text           '(literal) literal-props)
     (make-node-entry "code"           'code           '(literal) literal-props)
     (make-node-entry "html_inline"    'html-inline    '(literal) literal-props)
     (make-node-entry "html_block"     'html-block     '(literal) literal-props)
     (make-node-entry "code_block"     'code-block     '(literal fence-info)
                      code-block-props)
     (make-node-entry "link"           'link           '(url title) link-props)
     (make-node-entry "image"          'image          '(url title) link-props)
     (make-node-entry "list"           'list           '(kind start tight? delimiter)
                      list-props)
     (make-node-entry "item"           'item           '(index task? checked?)
                      plain-item-props)))

  (define (type-string->entry ts)
    (let loop ((es node-table))
      (cond ((null? es) #f)
            ((string=? ts (node-entry-type-string (car es))) (car es))
            (else (loop (cdr es))))))

  (define (node-table-type-strings)
    (map node-entry-type-string node-table))

  ;; --- source positions -------------------------------------------------
  ;; Only when requested, and only when cmark actually has one: xml.c:48
  ;; guards its own sourcepos attribute with start_line != 0, and the AST
  ;; reports the same absence as #f rather than inventing 0:0-0:0. Positions
  ;; obtained from a parse WITHOUT CMARK_OPT_SOURCEPOS are not merely absent
  ;; but wrong (inlines.c:292-296 skips a correction that propagates to later
  ;; inlines), which is why this is gated on the same flag that was parsed
  ;; with, never on a separate switch.
  (define (node-source p ctx)
    (and (convert-ctx-positions? ctx)
         (let ((sl (node-start-line p)))
           (and (not (zero? sl))
                (make-source-position sl
                                      (node-start-column p)
                                      (node-end-line p)
                                      (node-end-column p))))))

  ;; --- the walk ---------------------------------------------------------
  (define (check-depth! depth ctx)
    (when (> depth (convert-ctx-max-depth ctx))
      (raise (make-cmark-resource-limit 'too-deep (convert-ctx-max-depth ctx)))))

  (define (count-node! ctx)
    (convert-ctx-count-set! ctx (+ 1 (convert-ctx-count ctx)))
    (when (> (convert-ctx-count ctx) (convert-ctx-max-nodes ctx))
      (raise (make-cmark-resource-limit 'too-many-nodes
                                       (convert-ctx-max-nodes ctx)))))

  (define (convert-children p depth ctx)
    (let loop ((c (node-first-child p)) (acc '()))
      (if (zero? c)
          (reverse acc)
          (loop (node-next c)
                (cons (convert-node c (copy-required (node-type-string c))
                                    depth ctx)
                      acc)))))

  ;; Both ceilings are checked on entry, before any child is visited, so
  ;; exceeding one raises instead of recursing further. The condition escapes
  ;; through call-with-native-document, whose after-thunk frees the parser and
  ;; root; the partially built Scheme tree is simply dropped.
  (define (convert-node p type-string depth ctx)
    (check-depth! depth ctx)
    (count-node! ctx)
    (let ((entry (type-string->entry type-string))
          (children (convert-children p (+ depth 1) ctx))
          (source (node-source p ctx)))
      (make-markdown-node (node-entry-type entry)
                          (let ((extract (node-entry-extractor entry)))
                            (if extract (extract p) '()))
                          children
                          source)))

  ;; The document root is depth 1; a child is its parent's depth plus one.
  (define (convert-document h ctx)
    (let ((root (doc-root h)))
      (convert-node root (copy-required (node-type-string root)) 1 ctx))))
