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

(test-end "ast")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
