#!r6rs
;;; Resolution behaviour that needs a real process, not synthetic listings.
;;; tests/test-discovery.sps covers the selection algorithm; this covers the
;;; wiring: that an override wins, that an invalid one raises instead of
;;; falling back, and that the default path finds a real library here.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv)
        (cmark gfm)
        (cmark gfm private native)
        (cmark gfm private conditions))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "library-loading")

;; The default path must have worked, or nothing below could run.
(test-assert "the default candidate search resolved a usable library"
  (string? (markdown->html "# x\n" (default-cmark-options))))

(test-assert "the loaded library is inside the supported range"
  (cmark-gfm-version-compatible?))

;; An invalid override raises and does NOT quietly fall back to the search.
;; Falling back would mean a typo in the variable silently loads a different
;; library than the one the user named.
(define (override-error str)
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-reason e))
            (#t 'wrong-condition))
    (resolve-cmark-libraries str)
    'no-raise))

(test-equal "relative path override"    'invalid-override (override-error "a:b"))
(test-equal "single entry override"     'invalid-override (override-error "/usr/lib/libcmark-gfm.so"))
(test-equal "empty override"            'invalid-override (override-error ""))
(test-equal "nonexistent files"         'invalid-override
  (override-error "/nonexistent/libcmark-gfm.so:/nonexistent/libcmark-gfm-extensions.so"))

(test-end "library-loading")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
