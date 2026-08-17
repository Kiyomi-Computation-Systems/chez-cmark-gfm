#!r6rs
;; PURE SUITE. This file must never import a library that loads a shared
;; object. That is what makes every assertion below unable to pass by
;; accident because of native behaviour -- they exercise Scheme values only.
;; `make check-purity` enforces it by running this file with
;; CHEZ_CMARK_GFM_SHIM poisoned; if the import chain ever reaches
;; (cmark gfm private native), that target fails. Check transitive imports
;; before adding one here or to ast.sls.
(import (rnrs)
        (srfi :64)
        (cmark gfm ast))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "ast")

;; --- a small fixture tree ---------------------------------------------
;; # hi
;;
;; word
(define leaf-hi   (make-markdown-node 'text '((literal . "hi")) '() #f))
(define heading   (make-markdown-node 'heading '((level . 1)) (list leaf-hi) #f))
(define leaf-word (make-markdown-node 'text '((literal . "word")) '() #f))
(define para      (make-markdown-node 'paragraph '() (list leaf-word) #f))
(define doc       (make-markdown-node 'document '() (list heading para) #f))

;; --- construction and accessors ----------------------------------------
(test-equal "a node reports its type" 'heading (markdown-node-type heading))
(test-equal "a node reports its properties"
  '((level . 1)) (markdown-node-properties heading))
(test-equal "a node reports its children as a list"
  (list leaf-hi) (markdown-node-children heading))
(test-equal "source is #f when absent" #f (markdown-node-source heading))
(test-equal "markdown-node? accepts a node" #t (markdown-node? heading))
(test-equal "markdown-node? rejects a non-node" #f (markdown-node? '(heading)))
(test-equal "markdown-node? rejects a source-position"
  #f (markdown-node? (make-source-position 1 1 1 4)))

;; --- property lookup ---------------------------------------------------
;; Compared against VALUES, not asserted truthy: a level of 1 and a missing
;; key returning #f are both distinguishable only by comparison, and
;; test-assert would pass on any non-#f whatsoever.
(test-equal "property lookup finds a present key" 1
  (markdown-node-property heading 'level))
(test-equal "property lookup returns #f for an absent key with no default" #f
  (markdown-node-property heading 'url))
(test-equal "property lookup returns the supplied default for an absent key"
  'missing (markdown-node-property heading 'url 'missing))
(test-equal "an explicit default does not override a present key" 1
  (markdown-node-property heading 'level 'missing))
;; A property whose real value is #f must be distinguishable from absence.
;; Seeded deliberately: without this, an implementation using #f internally
;; as its not-found marker would pass every other assertion here.
(test-equal "a present key whose value is #f returns #f, not the default"
  #f
  (markdown-node-property
   (make-markdown-node 'item '((task? . #f)) '() #f) 'task? 'missing))

;; --- source positions ---------------------------------------------------
(define pos (make-source-position 3 5 3 9))
(test-equal "source-position? accepts one" #t (source-position? pos))
(test-equal "start-line"   3 (source-position-start-line pos))
(test-equal "start-column" 5 (source-position-start-column pos))
(test-equal "end-line"     3 (source-position-end-line pos))
(test-equal "end-column"   9 (source-position-end-column pos))
(test-equal "a node carries its position"
  pos
  (markdown-node-source (make-markdown-node 'text '() '() pos)))

;; --- functional update --------------------------------------------------
;; Each of these asserts BOTH the new value and that the original is
;; unchanged. Asserting only the new value would pass against a mutable
;; record with setters, which is exactly the design this rejects.
(test-equal "with-properties replaces the property list"
  '((level . 3))
  (markdown-node-properties (markdown-node-with-properties heading '((level . 3)))))
(test-equal "with-properties leaves the original untouched"
  '((level . 1)) (markdown-node-properties heading))
(test-equal "with-properties preserves type, children, and source"
  (list 'heading (list leaf-hi) #f)
  (let ((n (markdown-node-with-properties heading '((level . 3)))))
    (list (markdown-node-type n) (markdown-node-children n)
          (markdown-node-source n))))
(test-equal "with-children replaces the children"
  (list leaf-word)
  (markdown-node-children (markdown-node-with-children heading (list leaf-word))))
(test-equal "with-children leaves the original untouched"
  (list leaf-hi) (markdown-node-children heading))
(test-equal "with-children preserves type, properties, and source"
  (list 'heading '((level . 1)) #f)
  (let ((n (markdown-node-with-children heading (list leaf-word))))
    (list (markdown-node-type n) (markdown-node-properties n)
          (markdown-node-source n))))

;; --- traversal helpers -------------------------------------------------
;; The ORDER is the contract, so the order is what gets asserted. A helper
;; that visited every node but in the wrong order would satisfy any
;; count-based or set-based assertion, which is why both tests below record a
;; sequence and compare it against an expected list.

;; Pre-order: parent before children, children left to right.
(test-equal "fold visits pre-order, parent before children"
  '(document heading text paragraph text)
  (reverse (markdown-node-fold
            (lambda (n acc) (cons (markdown-node-type n) acc))
            '() doc)))

(test-equal "fold threads the accumulator and counts every node"
  5 (markdown-node-fold (lambda (n acc) (+ acc 1)) 0 doc))

;; Children-first: proc must already see mapped children. proc records, on
;; each parent, the literal it observes on that parent's own first child AT
;; THE MOMENT proc runs on the parent -- checking only the final assembled
;; tree would NOT prove this: markdown-node-with-children always rewraps a
;; node with the fully-recursed children regardless of order, so a proc that
;; never inspects its children (as a naive "does the final tree look right"
;; check would use) cannot tell parent-first from children-first apart. With
;; a parent-first implementation, proc sees the child still in its ORIGINAL
;; state, so the recorded literal would be "hi"/"word" instead of "marked".
(test-equal "map rebuilds children-first, so proc sees mapped children"
  '("marked" "marked")
  (let ((out (markdown-node-map
              (lambda (n)
                (cond
                  ((eq? (markdown-node-type n) 'text)
                   (markdown-node-with-properties n '((literal . "marked"))))
                  ((pair? (markdown-node-children n))
                   (markdown-node-with-properties
                    n `((observed-child-literal
                         . ,(markdown-node-property
                             (car (markdown-node-children n)) 'literal)))))
                  (else n)))
              doc)))
    ;; document -> (heading paragraph), each with one text child
    (map (lambda (block) (markdown-node-property block 'observed-child-literal))
         (markdown-node-children out))))

(test-equal "map can rewrite a node type and keeps the tree shape"
  '(document paragraph text paragraph text)
  (reverse
   (markdown-node-fold
    (lambda (n acc) (cons (markdown-node-type n) acc))
    '()
    (markdown-node-map
     (lambda (n)
       (if (eq? (markdown-node-type n) 'heading)
           (make-markdown-node 'paragraph '() (markdown-node-children n)
                               (markdown-node-source n))
           n))
     doc))))

(test-equal "map leaves the original tree untouched"
  '(document heading text paragraph text)
  (begin
    (markdown-node-map
     (lambda (n) (make-markdown-node 'clobbered '() '() #f))
     doc)
    (reverse (markdown-node-fold
              (lambda (n acc) (cons (markdown-node-type n) acc))
              '() doc))))

(test-equal "map on a leaf applies proc to the leaf itself"
  'rewritten
  (markdown-node-type
   (markdown-node-map (lambda (n) (make-markdown-node 'rewritten '() '() #f))
                      leaf-hi)))

(test-end "ast")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
