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
(test-assert "the handle is dead after the scope exits"
  (let ((escaped #f))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (guard (e ((cmark-dead-document? e) #t) (#t #f))
      (doc-root escaped))))

(test-assert "every checked accessor rejects a dead handle"
  (let ((escaped #f))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (and (guard (e ((cmark-dead-document? e) #t) (#t #f)) (doc-root escaped))
         (guard (e ((cmark-dead-document? e) #t) (#t #f)) (doc-parser escaped))
         (guard (e ((cmark-dead-document? e) #t) (#t #f)) (doc-extensions escaped)))))

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
