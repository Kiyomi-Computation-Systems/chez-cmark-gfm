#!r6rs
(import (rnrs)
        (srfi :64)
        (cmark gfm private conditions))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "conditions")

;; Each condition must be catchable both as itself and as the base type,
;; so callers can choose their granularity.
(test-assert "version-incompatible is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-equal "version-incompatible carries the compiled version"
  #x001d0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-compiled e)))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-equal "version-incompatible carries the runtime version"
  #x001e0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-runtime e)))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-assert "dead-document is distinguishable from version-incompatible"
  (guard (e ((cmark-version-incompatible? e) #f)
            ((cmark-dead-document? e) #t)
            (#t #f))
    (raise (make-cmark-dead-document))))

(test-equal "extension-unavailable names the extension"
  "table"
  (guard (e ((cmark-extension-unavailable? e)
             (cmark-extension-unavailable-name e)))
    (raise (make-cmark-extension-unavailable "table"))))

(test-equal "invalid-input carries a reason"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (raise (make-cmark-invalid-input 'embedded-nul))))

(test-equal "shim-unavailable carries the attempted path"
  "/nope/libchezcmarkgfm.dylib"
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (raise (make-cmark-shim-unavailable "/nope/libchezcmarkgfm.dylib"))))

;; Every condition must also be catchable as the base type, so a caller can
;; choose its granularity. Without these, deriving one of them from &error
;; directly -- a plausible copy-paste slip -- would break no test.
(test-assert "dead-document is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-dead-document))))

(test-assert "extension-unavailable is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-extension-unavailable "table"))))

(test-assert "invalid-input is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-invalid-input 'embedded-nul))))

(test-assert "shim-unavailable is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-shim-unavailable "/nope/libchezcmarkgfm.dylib"))))

;; --- Stage 2: invalid option ------------------------------------------
;; key is #f for whole-plist problems (odd length), a symbol otherwise.
(test-equal "invalid-option carries the offending key"
  'smart?
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-equal "invalid-option carries the reason"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-equal "invalid-option accepts #f as the key for whole-plist problems"
  #f
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-key e)))
    (raise (make-cmark-invalid-option #f 'malformed-plist))))

(test-assert "invalid-option is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

(test-assert "invalid-option is distinguishable from invalid-input"
  (guard (e ((cmark-invalid-input? e) #f)
            ((cmark-invalid-option? e) #t)
            (#t #f))
    (raise (make-cmark-invalid-option 'smart? 'invalid-value))))

;; --- Stage 2: renderer failure ----------------------------------------
(test-equal "render-failed names the format that failed"
  'commonmark
  (guard (e ((cmark-render-failed? e) (cmark-render-failed-format e)))
    (raise (make-cmark-render-failed 'commonmark))))

(test-assert "render-failed is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-render-failed 'html))))

(test-end "conditions")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
