#!r6rs
;; check-prod.sps: fail if the built shim carries -DCHEZ_CMARK_DEBUG_COUNTERS.
;;
;; A prod shim hardcodes chez_cmark_live_* to return 0 (src/cmark-gfm-shim.c),
;; so live-counts stays (0 0 0) even while a parsed document is live. A dev
;; shim counts the live parser and root, so the counters move during the
;; scope. This is tests/test-lifecycle.sps's "live-counts moves during a
;; scope" discriminator pointed the other way: that assertion gates the dev
;; artifact, this program gates the prod one. `make prod` runs it after the
;; link, so a prod build that still counts fails the build instead of
;; shipping (the pre-fix `make prod` did exactly that: its config.sls step
;; re-entered make and relinked the shim with dev flags).
;;
;; Deliberately named OUTSIDE the tests/test-*.sps wildcard: `make test`
;; must not run it, because it demands the opposite artifact from the dev
;; suite's discriminator.
;;
;; Frozen-at-zero counters observed DURING a live scope, from a parse that
;; succeeded, is a value only a counters-free shim can produce: a dev shim
;; has at least one live parser and root at that instant, a failed parse
;; raises into the guard, and a scope body that never ran leaves the 'unset
;; sentinel in place. (AGENTS.md: expect a value only success can produce.)
(import (rnrs)
        (cmark gfm private native)
        (cmark gfm private scope))

(guard (e (#t (display "check-prod: FAIL: probe raised before it could observe the counters:")
              (newline)
              (write e)
              (newline)
              (exit 1)))
  (ensure-native-loaded!)
  (let ((opts (option-bits #t #t #f #f #f #f))
        (extensions '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))
        (during 'unset))
    (call-with-native-document "# check-prod\n" opts extensions
      (lambda (h) (set! during (live-counts))))
    (cond
      ((equal? during '(0 0 0))
       (display "check-prod: PASS: counters frozen at (0 0 0) during a live scope; shim is a prod (counters-free) build")
       (newline)
       (exit 0))
      ((pair? during)
       (display "check-prod: FAIL: counters moved during a live scope: ")
       (write during)
       (newline)
       (display "The shim was linked with dev flags (-DCHEZ_CMARK_DEBUG_COUNTERS).")
       (newline)
       (exit 1))
      (else
       (display "check-prod: FAIL: scope body never ran; nothing was observed")
       (newline)
       (exit 1)))))
