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

(test-end "conditions")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
