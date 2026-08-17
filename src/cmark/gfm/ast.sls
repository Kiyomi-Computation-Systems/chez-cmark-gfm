#!r6rs
;;; The Scheme-owned Markdown AST -- the functional core.
;;;
;;; This library imports ONLY (rnrs). No native library, not even
;;; transitively, which is what makes tests/test-ast.sps run with no shared
;;; object loaded and therefore unable to pass by accident because of native
;;; behaviour. `make check-purity` enforces it. Check transitive imports
;;; before adding one.
;;;
;;; SECURITY: a node tree is UNTRUSTED STRUCTURED INPUT. Parsing preserves
;;; exactly what the document said, including raw HTML literals and
;;; javascript: URLs; no sanitisation happens during conversion, and
;;; unsafe-html? has no effect here -- that option is a renderer policy
;;; (project plan 10.3, and 17 names "users assume AST content is sanitized"
;;; as a project risk). Sanitise at the point of rendering, not here.
;;;
;;; Nodes are immutable. Every field is read-only and the two update helpers
;;; return new nodes, so a caller cannot corrupt a tree another caller holds.
;;; An accessor applied to a non-node raises R6RS &assertion from the record
;;; accessor itself; this library adds no checking layer, because a wrong type
;;; here is a programming error in Scheme-only code, not one of the native or
;;; option failures &cmark-error exists to describe.
(library (cmark gfm ast)
  (export make-markdown-node markdown-node?
          markdown-node-type markdown-node-properties
          markdown-node-children markdown-node-source
          markdown-node-property
          markdown-node-with-properties markdown-node-with-children
          markdown-node-map markdown-node-fold

          make-source-position source-position?
          source-position-start-line source-position-start-column
          source-position-end-line   source-position-end-column)
  (import (rnrs))

  ;; Diagnostic metadata, not a security boundary. cmark's positions for
  ;; some inline and extension constructs have known limitations (project
  ;; plan 7.2).
  (define-record-type (source-position make-source-position source-position?)
    (fields start-line start-column end-line end-column))

  ;; Generic rather than one record per node type, so an extension node type
  ;; needs no new record definition and no new export (project plan 7.1).
  ;; Children are a LIST: the traversal helpers are the intended access path
  ;; and neither wants random access. Properties are an immutable ALIST: no
  ;; node type carries more than four, so a mapping structure would cost more
  ;; than it saves, and an alist compares directly in tests.
  (define-record-type (markdown-node make-markdown-node markdown-node?)
    (fields type properties children source))

  ;; The default argument is not decoration. Several properties have #f as a
  ;; legitimate VALUE (task?, checked?, header?, tight?), so a lookup that
  ;; returned #f for both "absent" and "present and false" would be unable to
  ;; express the difference. assq distinguishes them; the default is only
  ;; consulted when the key is genuinely absent.
  (define markdown-node-property
    (case-lambda
      ((node key) (markdown-node-property node key #f))
      ((node key default)
       (let ((hit (assq key (markdown-node-properties node))))
         (if hit (cdr hit) default)))))

  (define (markdown-node-with-properties node properties)
    (make-markdown-node (markdown-node-type node)
                        properties
                        (markdown-node-children node)
                        (markdown-node-source node)))

  (define (markdown-node-with-children node children)
    (make-markdown-node (markdown-node-type node)
                        (markdown-node-properties node)
                        children
                        (markdown-node-source node)))

  ;; Children-first (bottom-up): proc receives a node whose children have
  ;; already been mapped, so a rewrite can inspect its final subtree. Both
  ;; orders here are asserted by test rather than merely documented -- an
  ;; ordering guarantee stated only in a comment does not enforce itself.
  ;;
  ;; Recursive, like the converter, and for the same reason: it runs on trees
  ;; already bounded by max-depth, so no separate limit applies.
  (define (markdown-node-map proc node)
    (proc (markdown-node-with-children
           node
           (map (lambda (child) (markdown-node-map proc child))
                (markdown-node-children node)))))

  ;; Pre-order: parent before children, children left to right.
  (define (markdown-node-fold proc seed node)
    (fold-left (lambda (acc child) (markdown-node-fold proc acc child))
               (proc node seed)
               (markdown-node-children node))))
