#!r6rs
;;; The Scheme AST. Every object here is Scheme-owned: no native pointer
;;; escapes, and the tree stays valid after the native document is gone.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/03-ast.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

;; One argument turns source positions ON (ADR-0009): if you asked for a tree
;; rather than markup, positions are usually why.
(define tree (markdown->ast "# Title\n\nSome *emphasis* here.\n"))

(line "root type:     " (markdown-node-type tree))
(line "is a node:     " (markdown-node? tree))
(line "child count:   " (length (markdown-node-children tree)))
(line "properties:    " (markdown-node-properties tree))

(define heading (car (markdown-node-children tree)))
(line "first child:   " (markdown-node-type heading))
(line "heading level: " (markdown-node-property heading 'level))

(define pos (markdown-node-source heading))
(line "source pos?:   " (source-position? pos))
(line "start line:    " (source-position-start-line pos))
(line "start column:  " (source-position-start-column pos))
(line "end line:      " (source-position-end-line pos))
(line "end column:    " (source-position-end-column pos))

;; Two arguments take an options record. default-ast-options is the one-arg
;; default; passing default-cmark-options instead turns positions off.
(define no-pos (markdown->ast "# Title\n" (default-cmark-options)))
(line "positions off: " (markdown-node-source
                         (car (markdown-node-children no-pos))))
(line "ast defaults:  " (cmark-options-source-positions? (default-ast-options)))

;; Fold counts nodes; map rebuilds the tree. Both are pure.
(line "node count:    " (markdown-node-fold (lambda (n acc) (+ acc 1)) 0 tree))

(define shouted
  (markdown-node-map
   (lambda (n)
     (if (eq? (markdown-node-type n) 'text)
         (markdown-node-with-properties
          n (list (cons 'literal (string-upcase (markdown-node-property n 'literal)))))
         n))
   tree))
(line "mapped text:   " (markdown-node-property
                         (car (markdown-node-children
                               (car (markdown-node-children shouted))))
                         'literal))

;; Building nodes by hand, for anything that constructs rather than inspects.
(define built
  (make-markdown-node 'text (list (cons 'literal "made")) '()
                      (make-source-position 1 1 1 4)))
(line "built literal: " (markdown-node-property built 'literal))
(line "replaced kids: " (length (markdown-node-children
                                 (markdown-node-with-children tree (list built)))))
