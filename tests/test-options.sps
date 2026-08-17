#!r6rs
;; PURE SUITE. This file must never import a library that loads a shared
;; object. That is what makes every assertion below unable to pass by
;; accident because of native behaviour. If you add an import here, check
;; its transitive imports first.
(import (rnrs)
        (srfi :64)
        (cmark gfm options)
        (cmark gfm private conditions))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "options")

;; --- defaults ---------------------------------------------------------
;; Compared field by field against expected VALUES, not asserted truthy:
;; every boolean default here is #f, and #f is the one Scheme value that
;; test-assert would catch -- but 'extensions and 'max-input-bytes are not
;; booleans, so a uniform value comparison is the only form that
;; discriminates all eight.
(test-equal "default extensions are the five standard GFM extensions"
  '(autolink strikethrough table tagfilter tasklist)
  (cmark-options-extensions (default-cmark-options)))

(test-equal "validate-utf8? defaults to #t"
  #t (cmark-options-validate-utf8? (default-cmark-options)))

;; ADR-0008: OFF for renderer-only releases. Flipping this default to #t
;; makes markdown->html emit data-sourcepos on every element.
(test-equal "source-positions? defaults to #f"
  #f (cmark-options-source-positions? (default-cmark-options)))

(test-equal "hardbreaks? defaults to #f"
  #f (cmark-options-hardbreaks? (default-cmark-options)))

(test-equal "nobreaks? defaults to #f"
  #f (cmark-options-nobreaks? (default-cmark-options)))

(test-equal "smart? defaults to #f"
  #f (cmark-options-smart? (default-cmark-options)))

(test-equal "unsafe-html? defaults to #f"
  #f (cmark-options-unsafe-html? (default-cmark-options)))

(test-equal "max-input-bytes defaults to 5 MiB"
  5242880 (cmark-options-max-input-bytes (default-cmark-options)))

;; --- plist construction ------------------------------------------------
(test-equal "a supplied key overrides its default"
  #t (cmark-options-smart? (make-cmark-options 'smart? #t)))

(test-equal "an unsupplied key keeps its default"
  #f (cmark-options-unsafe-html? (make-cmark-options 'smart? #t)))

(test-equal "two keys can be supplied at once"
  '(#t #t)
  (let ((o (make-cmark-options 'smart? #t 'unsafe-html? #t)))
    (list (cmark-options-smart? o) (cmark-options-unsafe-html? o))))

(test-equal "an empty plist yields the defaults"
  #f (cmark-options-smart? (make-cmark-options)))

;; --- plist rejection ---------------------------------------------------
;; Each guard returns a distinct sentinel in all three outcomes -- expected
;; condition, wrong condition, nothing raised -- and is compared against the
;; expected value. A bare test-assert here would pass on a no-raise
;; fall-through, which is the trap this repo has already shipped.
(test-equal "an odd-length plist is rejected"
  'malformed-plist
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart?)
    'no-condition))

(test-equal "an odd-length plist reports no key"
  #f
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (make-cmark-options 'smart?)))

(test-equal "an unknown key is rejected"
  'unknown-key
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'unsaef-html? #t)
    'no-condition))

(test-equal "an unknown key is named in the condition"
  'unsaef-html?
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (make-cmark-options 'unsaef-html? #t)))

(test-equal "a duplicate key is rejected rather than last-wins"
  'duplicate-key
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart? #t 'smart? #f)
    'no-condition))

(test-equal "a non-boolean value for a boolean key is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart? 'yes)
    'no-condition))

;; 0 is truthy in Scheme, so this is the value most likely to slip past a
;; sloppy check.
(test-equal "0 is rejected as a boolean value"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'smart? 0)
    'no-condition))

(test-equal "a non-positive max-input-bytes is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'max-input-bytes 0)
    'no-condition))

(test-equal "an inexact max-input-bytes is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'max-input-bytes 1024.0)
    'no-condition))

(test-equal "a positive exact max-input-bytes is accepted"
  1024 (cmark-options-max-input-bytes (make-cmark-options 'max-input-bytes 1024)))

;; --- functional update -------------------------------------------------
(test-equal "cmark-options-with overrides the named field"
  #t (cmark-options-smart? (cmark-options-with (default-cmark-options) 'smart? #t)))

(test-equal "cmark-options-with leaves other fields alone"
  #f (cmark-options-unsafe-html?
      (cmark-options-with (default-cmark-options) 'smart? #t)))

(test-equal "cmark-options-with preserves a non-default field it did not touch"
  1024
  (cmark-options-max-input-bytes
   (cmark-options-with (make-cmark-options 'max-input-bytes 1024) 'smart? #t)))

(test-equal "cmark-options-with does not mutate its argument"
  #f
  (let ((base (default-cmark-options)))
    (cmark-options-with base 'smart? #t)
    (cmark-options-smart? base)))

(test-equal "cmark-options-with rejects an unknown key"
  'unknown-key
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (cmark-options-with (default-cmark-options) 'nope #t)
    'no-condition))

(test-equal "cmark-options-with rejects a non-options first argument"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (cmark-options-with 'not-an-options-record 'smart? #t)
    'no-condition))

;; --- extensions --------------------------------------------------------
(test-equal "supported-extensions lists the five standard GFM extensions"
  '(autolink strikethrough table tagfilter tasklist)
  (supported-extensions))

(test-equal "extension->native-name maps a symbol to cmark's own spelling"
  "strikethrough" (extension->native-name 'strikethrough))

(test-equal "an unknown extension symbol is rejected at construction"
  'unknown-extension
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'extensions '(table footnotes))
    'no-condition))

(test-equal "a string extension name is rejected -- the public API takes symbols"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'extensions '("table"))
    'no-condition))

(test-equal "an empty extension list is accepted"
  '() (cmark-options-extensions (make-cmark-options 'extensions '())))

;; --- the contradictory pair --------------------------------------------
;; Verified in vendor/cmark-gfm/src/html.c:319-325: these are NOT undefined
;; together -- HARDBREAKS is tested first and NOBREAKS is its else-if, so
;; hardbreaks wins. Rejecting the pair is policy: honouring one of two
;; explicit requests and silently dropping the other is the failure this
;; library refuses.
(test-equal "hardbreaks? and nobreaks? together are rejected"
  'contradictory
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (make-cmark-options 'hardbreaks? #t 'nobreaks? #t)
    'no-condition))

(test-equal "either of the pair alone is accepted"
  '(#t #t)
  (list (cmark-options-hardbreaks? (make-cmark-options 'hardbreaks? #t))
        (cmark-options-nobreaks?   (make-cmark-options 'nobreaks? #t))))

;; The rule must survive functional update, which is the whole reason
;; validate runs on the RESULTING record rather than on the plist.
(test-equal "cmark-options-with cannot reach the contradictory pair either"
  'contradictory
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (cmark-options-with (make-cmark-options 'nobreaks? #t) 'hardbreaks? #t)
    'no-condition))

(test-end "options")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
