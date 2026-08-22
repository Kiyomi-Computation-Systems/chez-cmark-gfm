#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) call/1cc collect)  ; NOT exit: (rnrs) exports it
        (cmark gfm)                    ; markdown->html, default-cmark-options,
                                        ; for the unconditional counters probe
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
;; The balance assertions below compare before against after, so they all pass
;; against counters that never count anything: (0 0 0) equals (0 0 0). This is
;; the assertion that makes them mean what they claim -- it demands the counters
;; actually MOVE while a document is live.
(test-assert "live-counts moves during a scope: at least one live parser and root while the body runs"
  (let ((before (live-counts)))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h)
        (let ((during (live-counts)))
          (and (> (car during) (car before))      ; live-parsers
               (> (cadr during) (cadr before)))))))) ; live-roots

;; markdown->html is the only path exercised in this file that moves the buffer
;; counter; the call-with-native-document assertions below never allocate one.
(test-assert "counters balance across markdown->html"
  (let ((before (live-counts)))
    (markdown->html "# x\n" (default-cmark-options))
    (equal? before (live-counts))))

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

;; The four accessors are checked independently and compared as a list
;; rather than folded together with `and`, so a single accessor whose
;; liveness check is broken shows up as a mismatch at its own position
;; instead of being masked by the others' truthy results.
(test-equal "every checked accessor rejects a dead handle"
  '(dead-document-raised dead-document-raised dead-document-raised dead-document-raised)
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
       'no-condition-raised)
     (guard (e ((cmark-dead-document? e) 'dead-document-raised)
               (#t 'wrong-condition-raised))
       (doc-option-bits escaped)
       'no-condition-raised))))

;; --- I7: native-doc carries option-bits for the renderer (design spec 5.1)
(test-equal "doc-option-bits returns the option bits the document was created with"
  opts
  (call-with-native-document "# hello\n" opts gfm-extensions
    (lambda (h) (doc-option-bits h))))

;; Different option-bits values must read back distinctly -- otherwise this
;; could pass by accident if doc-option-bits ignored its argument and
;; returned some other constant.
(test-assert "doc-option-bits distinguishes two different option-bits values"
  (let ((opts-a (option-bits #t #f #f #f #f #f))
        (opts-b (option-bits #f #f #f #f #f #t)))
    (and (not (= opts-a opts-b))
         (= opts-a (call-with-native-document "hi" opts-a gfm-extensions
                     (lambda (h) (doc-option-bits h))))
         (= opts-b (call-with-native-document "hi" opts-b gfm-extensions
                     (lambda (h) (doc-option-bits h)))))))

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

;; --- I1: a non-string extension name must fail closed -------------------
;; find-extension's FFI binding is declared (string). Before this was
;; fixed, a non-string element (e.g. the symbol 'table instead of "table")
;; reached it from inside acquire!'s for-each -- after count-parser-new!
;; and before dynamic-wind was established -- raising a raw Chez FFI type
;; error and leaking the parser (counters went (0 0 0) -> (1 0 0), and the
;; condition was not cmark-error?). extension-names is now validated
;; before the parser is even created.
(test-equal "a non-string extension name is rejected as invalid input, not a raw FFI error"
  'extension-name-not-a-string
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (call-with-native-document "hi" opts '(table)
      (lambda (h) h))))

(test-assert "a non-string extension name is caught as a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (call-with-native-document "hi" opts '(table)
      (lambda (h) h))))

(test-assert "counters return to baseline after a non-string extension name is rejected"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "hi" opts '(table)
        (lambda (h) h)))
    (equal? before (live-counts))))

;; --- I5: max-input-bytes is enforced, not disabled -----------------------
;; scope.sls used to pass (greatest-fixnum) to validate-markdown-input
;; regardless of what call-with-native-document was given, so design spec
;; 5.5's "only pre-allocation defence" never actually fired.
(test-equal "an explicit max-bytes argument rejects an oversized document inside the scope"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (call-with-native-document "this is eleven" opts gfm-extensions
      (lambda (h) h)
      10)))

(test-assert "counters balance after an explicit max-bytes argument rejects the input"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "this is eleven" opts gfm-extensions
        (lambda (h) h)
        10))
    (equal? before (live-counts))))

;; The 4-argument form (what every test above this line uses) must ALSO
;; enforce a real limit by default, not silently fall back to something
;; unbounded -- that silent fallback was the actual defect.
(test-equal "the default max-input-bytes rejects a document over 5 MiB with no explicit limit"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (call-with-native-document (make-string (+ default-max-input-bytes 1) #\a)
                                opts gfm-extensions
      (lambda (h) h))))

(test-assert "counters balance after the default max-input-bytes rejects an oversized document"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document (make-string (+ default-max-input-bytes 1) #\a)
                                  opts gfm-extensions
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
