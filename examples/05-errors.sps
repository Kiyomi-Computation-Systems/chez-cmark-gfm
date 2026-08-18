#!r6rs
;;; Every failure is a structured condition deriving from &cmark-error, so a
;;; caller can catch the whole family or discriminate precisely.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src:fallback chez --program examples/05-errors.sps
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

;; A misspelled key. Rejected before any native resource is allocated.
(line "typo key:       "
      (guard (e ((cmark-invalid-option? e)
                 (list (cmark-invalid-option-key e)
                       (cmark-invalid-option-reason e))))
        (markdown->html "# hi\n" (make-cmark-options 'unsaef-html? #t))
        'no-condition))

;; An extension cmark-gfm does not have.
(line "bad extension:  "
      (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
        (make-cmark-options 'extensions '(nosuchextension))
        'no-condition))

;; hardbreaks? and nobreaks? contradict each other; cmark gives one
;; precedence, so honouring one and dropping the other silently would hide
;; a caller's mistake.
(line "contradiction:  "
      (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
        (make-cmark-options 'hardbreaks? #t 'nobreaks? #t)
        'no-condition))

;; Embedded NUL. UTF-8 text cannot contain one, so this is rejected input
;; rather than a rendering failure.
(line "embedded NUL:   "
      (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
        (markdown->html "a\x0;b" (default-cmark-options))
        'no-condition))

;; A resource limit. The value carried is the limit that was hit.
(line "depth limit:    "
      (guard (e ((cmark-resource-limit? e)
                 (list (cmark-invalid-input-reason e)
                       (cmark-resource-limit-value e))))
        (markdown->ast (make-string 40 #\>) (make-cmark-options 'max-depth 4))
        'no-condition))

;; A tree the parser never produces: cmark always makes a table's header row
;; the first row, if it has one at all (table.c only ever marks the row
;; synthesised when the table block opens as the header). Handed to the SXML
;; adapter directly -- here the header row is second, not first.
(line "malformed tree: "
      (guard (e ((cmark-malformed-tree? e) (cmark-malformed-tree-reason e)))
        (markdown-ast->sxml
         (make-markdown-node
          'table (list (cons 'columns 1) (cons 'alignments '(none)))
          (list (make-markdown-node
                 'table-row (list (cons 'header? #f))
                 (list (make-markdown-node 'table-cell '() '() #f)) #f)
                (make-markdown-node
                 'table-row (list (cons 'header? #t))
                 (list (make-markdown-node 'table-cell '() '() #f)) #f))
          #f))
        'no-condition))

;; Catching the family rather than a member. Every condition above also
;; satisfies cmark-error?.
(line "whole family:   "
      (guard (e ((cmark-error? e) 'caught-as-cmark-error))
        (markdown->html "# hi\n" (make-cmark-options 'bogus? #t))
        'no-condition))

;; The predicates and accessors for conditions this example cannot trigger
;; through the public API are listed in examples/coverage-exemptions.scm, each
;; with the reason it is unreachable. Calling them on a non-condition just to
;; make them appear here would satisfy the coverage gate while teaching a
;; reader nothing, which is the opposite of what the gate is for.
