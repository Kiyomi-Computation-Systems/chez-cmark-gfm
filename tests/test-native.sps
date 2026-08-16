#!r6rs
(import (rnrs)          ; note: (rnrs) already exports `exit` via
        (srfi :64)      ; (rnrs programs) -- importing it from
        (cmark gfm private native))   ; (chezscheme) too is a conflict

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "native")

(test-assert "loading is idempotent"
  (begin (ensure-native-loaded!) (ensure-native-loaded!) #t))

;; NULL must be distinguishable from the empty string. Several cmark
;; accessors return NULL for nodes of an incompatible type, and conflating
;; that with "" would silently invent data.
(test-equal "c-string->string maps NULL to #f" #f (c-string->string 0))

(test-assert "option-bits sets a bit for validate-utf8"
  (> (option-bits #t #f #f #f #f #f) 0))

(test-assert "option-bits with everything off is zero"
  (= 0 (option-bits #f #f #f #f #f #f)))

(test-assert "option-bits composes distinct flags"
  (let ((a (option-bits #t #f #f #f #f #f))
        (b (option-bits #f #t #f #f #f #f)))
    (= (option-bits #t #t #f #f #f #f) (bitwise-ior a b))))

;; Seeded deliberately: assert a NON-empty starting shape so the test
;; cannot pass by accident if live-counts returned something degenerate.
(test-equal "live-counts reports three counters"
  3
  (length (live-counts)))

(test-assert "live-counts starts balanced at zero"
  (for-all zero? (live-counts)))

(test-end "native")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
