#!r6rs
;;; The native-to-Scheme AST copy -- the imperative shell.
;;;
;;; Dispatch on type strings: extension node enums are assigned at runtime.
;;; Copy every borrowed string while call-with-native-document is alive; the
;;; returned tree must contain no native pointers.
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

  ;; column-alignments holds the alignments of the table currently being
  ;; walked, because a cell cannot ask for its own: get_cell_alignment reads
  ;; node->as.cell_index (extensions/table.c:133-139), which is not exported.
  ;; A cell's alignment is therefore its zero-based position among its row's
  ;; children, indexed into this list.
  (define-record-type (convert-ctx %make-convert-ctx convert-ctx?)
    (fields (mutable count) max-nodes max-depth positions?
            (mutable column-alignments)))

  ;; make-convert-ctx : exact-positive-integer exact-positive-integer boolean
  ;;                    -> convert-ctx
  (define (make-convert-ctx max-nodes max-depth positions?)
    (%make-convert-ctx 0 max-nodes max-depth positions? '()))

  ;; c-string->string maps NULL to #f. For every property the table declares,
  ;; NULL is invalid; do not turn it into a documented string property.
  (define (copy-required addr)
    (let ((s (c-string->string addr)))
      (or s (raise (make-cmark-error)))))

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

  ;; Keep item keys uniform. index is computed from the parent, not the item.
  (define (plain-item-props index)
    (list (cons 'index index)
          (cons 'task? #f)
          (cons 'checked? #f)))

  ;; Alignment bytes are ASCII: 0 (none), 'l', 'c', 'r'
  ;; (vendor/cmark-gfm/extensions/table.c:387-391).
  (define (alignment-byte->symbol b)
    (cond ((= b 108) 'left)      ; #\l
          ((= b 99)  'center)    ; #\c
          ((= b 114) 'right)     ; #\r
          (else 'none)))

  ;; These accessors do not guard NULL; dispatch has already established that
  ;; p is a table node.
  (define (table-props p)
    (let ((n (table-columns p)))
      (list (cons 'columns n)
            (cons 'alignments
                  (map alignment-byte->symbol
                       (alignment-bytes (table-alignments p) n))))))

  (define (header-row-props p) (list (cons 'header? #t)))
  (define (body-row-props p)   (list (cons 'header? #f)))

  ;; tasklist-checked cannot distinguish unchecked from non-task; call it only
  ;; after the type string establishes a task item.
  (define (task-item-props p index)
    (list (cons 'index index)
          (cons 'task? #t)
          (cons 'checked? (tasklist-checked p))))

  ;; cmark_node_get_item_index is newer than the supported ABI and exposes the
  ;; literal marker, not the rendered ordinal. Derive the ordinal from the
  ;; parent list start and sibling offset, matching cmark's renderers.

  ;; #f means non-ordered; 0 is a valid ordered-list start. Query the parent:
  ;; node-list-start on an item returns 0 regardless of its list.
  (define (ordered-list-start p)
    (and (= 2 (node-list-type p)) (node-list-start p)))

  ;; Bullet and task-list items use index 0.
  (define (item-index start offset)
    (if start (+ start offset) 0))

  ;; Preserve unknown types as extension nodes. Their literal is optional, so
  ;; NULL is legitimate here rather than an error.
  (define (extension-props p type-string)
    (let ((literal (c-string->string (node-literal p))))
      (if literal
          (list (cons 'native-type type-string) (cons 'literal literal))
          (list (cons 'native-type type-string)))))

  ;; Type string, AST type, declared property keys, and optional extractor.
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
     ;; Parent-dependent properties are supplied by convert-node/index.
     (make-node-entry "item"           'item           '(index task? checked?) #f)
     (make-node-entry "strikethrough" 'strikethrough '() #f)
     (make-node-entry "tasklist"     'item      '(index task? checked?) #f)
     (make-node-entry "table"        'table     '(columns alignments) table-props)
     (make-node-entry "table_header" 'table-row '(header?) header-row-props)
     (make-node-entry "table_row"    'table-row '(header?) body-row-props)
     (make-node-entry "table_cell"   'table-cell '(alignment) #f)))

  ;; type-string->entry : string -> (or node-entry #f)
  (define (type-string->entry ts)
    (let loop ((es node-table))
      (cond ((null? es) #f)
            ((string=? ts (node-entry-type-string (car es))) (car es))
            (else (loop (cdr es))))))

  (define (node-table-type-strings)
    (map node-entry-type-string node-table))

  ;; Return #f when cmark reports no position. Without CMARK_OPT_SOURCEPOS some
  ;; inline positions are wrong, so use the same flag that controlled parsing.
  (define (node-source p ctx)
    (and (convert-ctx-positions? ctx)
         (let ((sl (node-start-line p)))
           (and (not (zero? sl))
                (make-source-position sl
                                      (node-start-column p)
                                      (node-end-line p)
                                      (node-end-column p))))))

  (define (check-depth! depth ctx)
    (when (> depth (convert-ctx-max-depth ctx))
      (raise (make-cmark-resource-limit 'too-deep (convert-ctx-max-depth ctx)))))

  (define (count-node! ctx)
    (convert-ctx-count-set! ctx (+ 1 (convert-ctx-count ctx)))
    (when (> (convert-ctx-count ctx) (convert-ctx-max-nodes ctx))
      (raise (make-cmark-resource-limit 'too-many-nodes
                                       (convert-ctx-max-nodes ctx)))))

  ;; Read list metadata only for parents that actually have children.
  (define (convert-children p depth ctx)
    (let ((first-child (node-first-child p)))
      (if (zero? first-child)
          '()
          (let ((start (ordered-list-start p)))
            (let loop ((c first-child) (i 0) (acc '()))
              (if (zero? c)
                  (reverse acc)
                  (loop (node-next c) (+ i 1)
                        (cons (convert-node/index
                               c (copy-required (node-type-string c))
                               depth start i ctx)
                              acc))))))))

  ;; Cell alignment and item index are positional properties supplied by the
  ;; parent and the child's zero-based offset.
  (define (convert-node/index p type-string depth start offset ctx)
    (cond
      ((string=? type-string "table_cell")
       (let ((aligns (convert-ctx-column-alignments ctx)))
         (with-node p type-string depth ctx
                    (list (cons 'alignment
                                (if (< offset (length aligns))
                                    (list-ref aligns offset)
                                    'none))))))
      ((string=? type-string "item")
       (with-node p type-string depth ctx
                  (plain-item-props (item-index start offset))))
      ((string=? type-string "tasklist")
       (with-node p type-string depth ctx
                  (task-item-props p (item-index start offset))))
      (else (convert-node p type-string depth ctx))))

  ;; Check limits before recursion. properties-override is used only for the
  ;; parent-dependent cell, item, and task-list properties.
  (define (with-node p type-string depth ctx properties-override)
    (check-depth! depth ctx)
    (count-node! ctx)
    (let* ((entry (type-string->entry type-string))
           ;; Restore the outer table's alignments after walking children.
           (saved (convert-ctx-column-alignments ctx))
           (props (or properties-override
                      (if entry
                          (let ((extract (node-entry-extractor entry)))
                            (if extract (extract p) '()))
                          (extension-props p type-string)))))
      (when (string=? type-string "table")
        (convert-ctx-column-alignments-set!
         ctx (cdr (assq 'alignments props))))
      (let ((children (convert-children p (+ depth 1) ctx))
            (source (node-source p ctx)))
        (convert-ctx-column-alignments-set! ctx saved)
        (make-markdown-node (if entry (node-entry-type entry) 'extension)
                            props children source))))

  ;; Direct conversion cannot supply parent-dependent properties.
  (define parent-dependent-type-strings '("table_cell" "item" "tasklist"))

  ;; convert-node : uptr string exact-positive-integer convert-ctx -> markdown-node
  (define (convert-node p type-string depth ctx)
    (when (member type-string parent-dependent-type-strings)
      (assertion-violation 'convert-node
        "table_cell, item, and tasklist must be converted through convert-node/index, which supplies their parent-dependent properties positionally; direct calls cannot"
        type-string))
    (with-node p type-string depth ctx #f))

  ;; convert-document : native-doc convert-ctx -> markdown-node
  ;; The document root has depth 1.
  (define (convert-document h ctx)
    (let ((root (doc-root h)))
      (convert-node root (copy-required (node-type-string root)) 1 ctx))))
