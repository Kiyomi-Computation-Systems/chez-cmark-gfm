#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) call/1cc collect)  ; NOT exit: (rnrs) exports it
        (cmark gfm private native)
        (cmark gfm private conditions)
        (cmark gfm private scope))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(ensure-native-loaded!)

(test-begin "lifecycle")

(define opts (option-bits #t #t #f #f #f #f))
(define gfm-extensions '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

;; --- input validation -------------------------------------------------
(test-equal "embedded NUL is rejected"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (validate-markdown-input "a\x0;b" 1000)))

(test-equal "oversized input is rejected"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (validate-markdown-input "hello world" 4)))

;; The limit is on BYTES, not characters. This 3-character string is 7
;; bytes in UTF-8, so a 5-byte limit must reject it. If the implementation
;; measured characters it would wrongly accept, so this test discriminates.
(test-equal "the limit counts bytes, not characters"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (validate-markdown-input "\x4e16;\x754c;!" 5)))

(test-assert "valid input returns a bytevector of the right length"
  (let ((bv (validate-markdown-input "hi" 100)))
    (and (bytevector? bv) (= 2 (bytevector-length bv)))))

;; --- balanced teardown ------------------------------------------------
(test-assert "counters balance after a successful scope"
  (let ((before (live-counts)))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (doc-root h)))
    (equal? before (live-counts))))

(test-assert "counters balance after the body raises"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "# hello\n" opts gfm-extensions
        (lambda (h) (error 'test "deliberate failure"))))
    (equal? before (live-counts))))

;; A continuation escape must still free. dynamic-wind's after-thunk is
;; what makes this work; without it this test leaks.
(test-assert "counters balance after a non-local escape"
  (let ((before (live-counts)))
    (call/1cc
     (lambda (k)
       (call-with-native-document "# hello\n" opts gfm-extensions
         (lambda (h) (k 'escaped)))))
    (equal? before (live-counts))))

;; --- liveness (ADR-0006) ---------------------------------------------
;; A guard whose body never raises simply returns the body's own value.
;; release! zeroes freed fields to 0, and 0 is truthy in Scheme, so
;; comparing that fall-through value for truthiness would not discriminate
;; a checked accessor from an unchecked one. Each guard clause below is
;; rewritten to return a distinguishable sentinel symbol in all three
;; outcomes -- condition raised, wrong condition raised, nothing raised --
;; and the assertions compare against the expected sentinel, never a
;; truthiness.
(test-eq "the handle is dead after the scope exits"
  'dead-document-raised
  (let ((escaped #f))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (guard (e ((cmark-dead-document? e) 'dead-document-raised)
              (#t 'wrong-condition-raised))
      (doc-root escaped)
      'no-condition-raised)))

;; The three accessors are checked independently and compared as a list
;; rather than folded together with `and`, so a single accessor whose
;; liveness check is broken shows up as a mismatch at its own position
;; instead of being masked by the others' truthy results.
(test-equal "every checked accessor rejects a dead handle"
  '(dead-document-raised dead-document-raised dead-document-raised)
  (let ((escaped #f))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (list
     (guard (e ((cmark-dead-document? e) 'dead-document-raised)
               (#t 'wrong-condition-raised))
       (doc-root escaped)
       'no-condition-raised)
     (guard (e ((cmark-dead-document? e) 'dead-document-raised)
               (#t 'wrong-condition-raised))
       (doc-parser escaped)
       'no-condition-raised)
     (guard (e ((cmark-dead-document? e) 'dead-document-raised)
               (#t 'wrong-condition-raised))
       (doc-extensions escaped)
       'no-condition-raised))))

;; --- extension failure ------------------------------------------------
(test-equal "a missing extension is named in the condition"
  "no-such-extension"
  (guard (e ((cmark-extension-unavailable? e)
             (cmark-extension-unavailable-name e)))
    (call-with-native-document "x" opts '("no-such-extension")
      (lambda (h) h))))

(test-assert "counters balance after extension attachment fails"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "x" opts '("no-such-extension")
        (lambda (h) h)))
    (equal? before (live-counts))))

;; --- repetition -------------------------------------------------------
(test-assert "100 scopes leave the counters balanced"
  (let ((before (live-counts)))
    (let loop ((n 0))
      (when (< n 100)
        (call-with-native-document "# hi\n\n| a |\n|---|\n| 1 |\n"
                                   opts gfm-extensions
          (lambda (h) (doc-root h)))
        (loop (+ n 1))))
    (collect)
    (equal? before (live-counts))))

(test-end "lifecycle")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
