#!r6rs
;;; Immutable, Scheme-owned Markdown AST. Keep this library's transitive
;;; imports free of native code.
;;;
;;; AST content is untrusted: raw HTML and dangerous URLs are preserved.
;;; Apply security policy when rendering, not while parsing.
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

  ;; Diagnostic metadata, not a security boundary.
  (define-record-type (source-position make-source-position source-position?)
    (fields start-line start-column end-line end-column))

  ;; Children are a list; properties are an immutable alist. A generic record
  ;; lets unknown extension nodes survive conversion.
  (define-record-type (markdown-node make-markdown-node markdown-node?)
    (fields type properties children source))

  ;; markdown-node-property : markdown-node symbol [object] -> object
  ;; Use the explicit default to distinguish absence from a stored #f.
  (define markdown-node-property
    (case-lambda
      ((node key) (markdown-node-property node key #f))
      ((node key default)
       (let ((hit (assq key (markdown-node-properties node))))
         (if hit (cdr hit) default)))))

  ;; markdown-node-with-properties : markdown-node alist -> markdown-node
  (define (markdown-node-with-properties node properties)
    (make-markdown-node (markdown-node-type node)
                        properties
                        (markdown-node-children node)
                        (markdown-node-source node)))

  ;; markdown-node-with-children : markdown-node (listof markdown-node) -> markdown-node
  (define (markdown-node-with-children node children)
    (make-markdown-node (markdown-node-type node)
                        (markdown-node-properties node)
                        children
                        (markdown-node-source node)))

  ;; markdown-node-map : (markdown-node -> markdown-node) markdown-node -> markdown-node
  ;; Bottom-up: proc receives a node whose children are already mapped.
  (define (markdown-node-map proc node)
    (proc (markdown-node-with-children
           node
           (map (lambda (child) (markdown-node-map proc child))
                (markdown-node-children node)))))

  ;; markdown-node-fold : (markdown-node object -> object) object markdown-node
  ;;                      -> object
  ;; Pre-order: parent before children, children left to right.
  (define (markdown-node-fold proc seed node)
    (fold-left (lambda (acc child) (markdown-node-fold proc acc child))
               (proc node seed)
               (markdown-node-children node))))
