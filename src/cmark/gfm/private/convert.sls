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
  ;;
  ;; column-alignments holds the alignments of the table currently being
  ;; walked, because a cell cannot ask for its own: get_cell_alignment reads
  ;; node->as.cell_index (extensions/table.c:133-139), which is not exported.
  ;; A cell's alignment is therefore its zero-based position among its row's
  ;; children, indexed into this list.
  (define-record-type (convert-ctx %make-convert-ctx convert-ctx?)
    (fields (mutable count) max-nodes max-depth positions?
            (mutable column-alignments)))

  (define (make-convert-ctx max-nodes max-depth positions?)
    (%make-convert-ctx 0 max-nodes max-depth positions? '()))

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
  ;;
  ;; `index` is supplied by the caller, not read from the node, so this takes
  ;; it rather than a node pointer -- see item-index below.
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

  ;; table-columns and table-alignments (extensions/table.c:878-890) test
  ;; node->type and safely return 0/NULL for a non-table node -- not a
  ;; fault. What they lack, unlike get_cell_alignment (table.c:133-139), is
  ;; a guard against a NULL node. Moot here: get_type_string (table.c:526)
  ;; returns "table" only when node->type == CMARK_NODE_TABLE, checked on
  ;; the same node whose type string dispatched us to this branch.
  (define (table-props p)
    (let ((n (table-columns p)))
      (list (cons 'columns n)
            (cons 'alignments
                  (map alignment-byte->symbol
                       (alignment-bytes (table-alignments p) n))))))

  (define (header-row-props p) (list (cons 'header? #t)))
  (define (body-row-props p)   (list (cons 'header? #f)))

  ;; A task item's checked state is meaningful only because its TYPE STRING is
  ;; "tasklist" (extensions/tasklist.c:13-17). tasklist-checked alone cannot
  ;; distinguish an unchecked task from a non-task, so it is consulted only
  ;; after the type string has already established that this is a task item.
  (define (task-item-props p index)
    (list (cons 'index index)
          (cons 'task? #t)
          (cons 'checked? (tasklist-checked p))))

  ;; --- an item's ordinal position ---------------------------------------
  ;; `index` is computed here rather than read from the library.
  ;; cmark_node_get_item_index was added upstream in 0.29.0.gfm.11, above
  ;; this library's declared floor of 0.29.0.gfm.0, so binding it broke the
  ;; import outright on Debian 11/12 and Ubuntu 22.04/24.04 (design spec
  ;; 3.8). Nothing new is needed to replace it: convert-children already
  ;; threads a zero-based sibling offset for table_cell alignment, and the
  ;; node it walks IS the parent list.
  ;;
  ;; This is a REDEFINITION, not a reimplementation. The entry point returned
  ;; node->as.list.start for an item, which the parser sets to the number
  ;; literally typed; this is the item's ordinal position. `1. 1. 1.` was
  ;; (1 1 1) and is now (1 2 3), and the literal numbers are no longer
  ;; recoverable from the AST. cmark's own commonmark/man/plaintext renderers
  ;; overwrite that field with exactly this computation --
  ;; cmark_node_get_list_start(parent) for the first item, previous + 1 after
  ;; (vendor/cmark-gfm/src/render.c:184-192) -- so the ordinal is cmark's own
  ;; rendering semantics rather than an invention here.

  ;; The enclosing list's start, or #f when the parent is not an ordered
  ;; list. #f rather than 0 because the two answers differ: an ordered list
  ;; may itself start at 0, numbering its items 0, 1, 2, while a BULLET list
  ;; numbers every one of its items 0.
  ;;
  ;; Safe to ask of any parent, including a leaf: node.c type-guards both
  ;; accessors, returning CMARK_NO_LIST and 0 unless node->type is
  ;; CMARK_NODE_LIST. That guard is also why the parent has to be asked and
  ;; not the item -- cmark_node_get_list_start on an ITEM answers 0 for every
  ;; list, ordered or not.
  (define (ordered-list-start p)
    (and (= 2 (node-list-type p)) (node-list-start p)))

  ;; 0 for a bullet list -- which is what a GFM task list is, so tasks index
  ;; 0 too -- and for an item whose parent is not a list at all.
  (define (item-index start offset)
    (if start (+ start offset) 0))

  ;; Plan 7.4's default: preserve rather than discard, and never lose children
  ;; or literals. Preservation over a raise means a future cmark that adds a
  ;; node type degrades to a usable AST instead of failing every document
  ;; containing one.
  ;;
  ;; This is the one node type whose key set is not fixed (design spec 3.4):
  ;; the keys of an unknown type cannot be known in advance, so `literal` is
  ;; present only when cmark actually has one. c-string->string is used
  ;; directly rather than copy-required, because here #f is the legitimate
  ;; answer -- an unknown node type may well have no string content.
  (define (extension-props p type-string)
    (let ((literal (c-string->string (node-literal p))))
      (if literal
          (list (cons 'native-type type-string) (cons 'literal literal))
          (list (cons 'native-type type-string)))))

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
     ;; index is supplied positionally by convert-node/index, like table_cell
     ;; alignment below, so these two declare the key but have no extractor
     ;; of their own: an item's ordinal cannot be computed from the item.
     (make-node-entry "item"           'item           '(index task? checked?) #f)
     (make-node-entry "strikethrough" 'strikethrough '() #f)
     (make-node-entry "tasklist"     'item      '(index task? checked?) #f)
     (make-node-entry "table"        'table     '(columns alignments) table-props)
     (make-node-entry "table_header" 'table-row '(header?) header-row-props)
     (make-node-entry "table_row"    'table-row '(header?) body-row-props)
     ;; alignment is supplied positionally by convert-node/index, so this
     ;; entry declares the key but has no extractor of its own.
     (make-node-entry "table_cell"   'table-cell '(alignment) #f)))

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

  ;; The list start is read once per parent, and only when there is a child
  ;; to spend it on: `p` here is every node in the document, the vast
  ;; majority of them leaves, and a childless node must not pay two foreign
  ;; calls to learn it is not a list.
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

  ;; Three node types have a property their own node cannot answer, and all
  ;; three are answered here, from the parent's `start` and the child's
  ;; zero-based `offset`:
  ;;
  ;;   table_cell -- alignment is positional, so the cell's column IS the
  ;;   offset (see the column-alignments note on convert-ctx).
  ;;   item, tasklist -- `index` is the ordinal position in the parent list.
  ;;
  ;; Everything else ignores both.
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

  ;; Both ceilings are checked on entry, before any child is visited, so
  ;; exceeding one raises instead of recursing further. The condition escapes
  ;; through call-with-native-document, whose after-thunk frees the parser and
  ;; root; the partially built Scheme tree is simply dropped.
  ;;
  ;; properties-override is #f for every type except the three whose
  ;; properties cannot be computed from the node alone -- table_cell,
  ;; item, and tasklist -- which convert-node/index supplies.
  (define (with-node p type-string depth ctx properties-override)
    (check-depth! depth ctx)
    (count-node! ctx)
    (let* ((entry (type-string->entry type-string))
           ;; A table publishes its alignments into the context before its
           ;; rows and cells are walked, and restores the previous value
           ;; afterwards so nested tables cannot leak alignments outward.
           ;; cmark cannot nest tables today; the save/restore costs one
           ;; binding and removes the question.
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

  ;; Exported so tests can drive it directly (see the type-string note at
  ;; the top of this file). The three parent-dependent types are refused
  ;; rather than silently producing an alignment-less table-cell or an item
  ;; with no index at all: convert-node/index is the only path that holds
  ;; the parent's list start and the child's offset, which both are drawn
  ;; from.
  (define parent-dependent-type-strings '("table_cell" "item" "tasklist"))

  (define (convert-node p type-string depth ctx)
    (when (member type-string parent-dependent-type-strings)
      (assertion-violation 'convert-node
        "table_cell, item, and tasklist must be converted through convert-node/index, which supplies their parent-dependent properties positionally; direct calls cannot"
        type-string))
    (with-node p type-string depth ctx #f))

  ;; The document root is depth 1; a child is its parent's depth plus one.
  (define (convert-document h ctx)
    (let ((root (doc-root h)))
      (convert-node root (copy-required (node-type-string root)) 1 ctx))))
