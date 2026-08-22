#!r6rs
;;; Stress: accumulation, which nothing else here tests.
;;;
;;; Every counter assertion elsewhere in the suite is single-shot. A leak of
;;; one buffer per call satisfies all of them and fails this on iteration two.
;;; That is plan 17's renderer-buffer-leak risk, tested across iterations
;;; rather than once.
;;;
;;; Limit BOUNDARIES are deliberately not retested here. They are already
;;; covered: depth at tests/test-convert.sps:266-269 and again through the
;;; options record at 571-576, node count at 275-283, and max-input-bytes at
;;; tests/test-lifecycle.sps:211-221. Re-asserting them would add runtime and
;;; no coverage. The pathological documents below run UNDER the limits, so
;;; they exercise robustness rather than rejection.
;;;
;;; Iteration count comes from the environment (12-factor). It must stay low
;;; by default: this file joins MEMORY_TESTS automatically, and Valgrind is
;;; roughly two orders of magnitude slower.
(import (rnrs)
        (srfi :64)
        ;; iota is not in (rnrs); getenv is not in (rnrs) either -- both are
        ;; chezscheme extensions. NOT exit: (rnrs) already exports it.
        (only (chezscheme) getenv iota)
        (cmark gfm)
        (cmark gfm private native)
        ;; For call-with-native-document, which the seeded control needs: no
        ;; public entry point exposes a live document, by design.
        (cmark gfm private scope))

;; Native extension NAMES, which call-with-native-document wants -- not the
;; option record's symbols. Same list as tests/test-lifecycle.sps:20.
(define gfm-extension-names
  '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

(define runner (test-runner-simple))
(test-runner-current runner)

;; Unset or unparseable: the low-by-default 50. Parsed but not a positive
;; integer -- 0 is truthy in Scheme, so (or (and raw (string->number raw)) 50)
;; previously let CMARK_STRESS_ITERATIONS=0 through as 0 itself, which turns
;; the loop below into a zero-iteration no-op that still reports 4/4, exit 0
;; without checking a single counter after a single call; a negative value
;; made the loop's (= i iterations) test never true, looping forever. Clamped
;; up to 1 instead: a caller who sets a non-positive count still gets a
;; suite that actually exercises the loop body at least once, rather than
;; one that silently either skips it or never returns.
(define iterations
  (let* ((raw (getenv "CMARK_STRESS_ITERATIONS"))
         (n (and raw (string->number raw))))
    (cond
      ((not n) 50)
      ((and (integer? n) (>= n 1)) n)
      (else 1))))

(define opts (default-cmark-options))

;; call-with-native-document's option-bits argument is the raw integer
;; cmark_parser_new wants (native.sls's option-bits procedure), not the
;; cmark-options record -- (cmark gfm) never hands that record to the native
;; layer directly. render.sls and parse.sls each unpack it this same way
;; before their own call-with-native-document call; the seeded control below
;; reaches call-with-native-document directly (that is the whole reason this
;; file imports private/scope), so it has to do the same unpacking. Every
;; other call in this file goes through markdown->html and friends, which
;; already do it internally, so opts is passed to those verbatim.
(define (options->bits o)
  (option-bits (cmark-options-validate-utf8? o)
               (cmark-options-source-positions? o)
               (cmark-options-hardbreaks? o)
               (cmark-options-nobreaks? o)
               (cmark-options-smart? o)
               (cmark-options-unsafe-html? o)))

;; Documents that are awkward but legal. Depth 100 and this node count are
;; well inside the defaults (max-depth 1000, max-nodes 250000).
(define deep-quotes
  (string-append (apply string-append
                        (map (lambda (i) "> ") (iota 100)))
                 "deep\n"))
(define deep-emphasis
  (string-append (make-string 60 #\*) "x" (make-string 60 #\*) "\n"))
(define wide-table
  (string-append
   "| " (apply string-append (map (lambda (i) "h | ") (iota 40))) "\n"
   "| " (apply string-append (map (lambda (i) "--- | ") (iota 40))) "\n"
   "| " (apply string-append (map (lambda (i) "c | ") (iota 40))) "\n"))
(define long-line
  (string-append (apply string-append (map (lambda (i) "word ") (iota 4000))) "\n"))

(define documents (list deep-quotes deep-emphasis wide-table long-line))

;; Every public path that acquires a native resource.
(define (exercise-all doc)
  (markdown->html       doc opts)
  (markdown->commonmark doc opts 72)
  (markdown->plaintext  doc opts 72)
  (markdown->xml        doc opts)
  (markdown->ast        doc opts)
  (markdown->sxml       doc opts))

;; live-counts is exported by (cmark gfm private native) and already returns
;; (list (live-parsers) (live-roots) (live-buffers)) -- native.sls:283. Do not
;; redefine it here; tests/test-lifecycle.sps calls the same procedure, so a
;; second spelling would drift from it.

(test-begin "stress")

;; A seeded control, and it must demand the counters MOVE -- not merely that
;; they start at zero. The counters are plain Scheme set!s (native.sls) and
;; always on, but "starts at (0 0 0)" and "returns to (0 0 0)" are satisfied
;; just as well by a genuinely broken live-buffers getter (frozen, or wired
;; to the wrong counter) as by a working one -- so without checking all three
;; for MOVEMENT, such a getter would pass this control and every assertion
;; below it vacuously. Same shape and same reason as
;; tests/test-lifecycle.sps:53, which is where this pattern comes from;
;; reaching a live document needs (cmark gfm private scope), because no
;; public entry point exposes one.
;;
;; live-parsers and live-roots move for free inside call-with-native-
;; document's own scope, but live-buffers does not -- no renderer buffer is
;; allocated by parsing alone (scope.sls's call-with-render-buffer is what
;; counts one, and only render.sls's renderers call it). So this control
;; renders through the live handle directly, using the same primitives
;; call-with-render-buffer composes (render-html, count-buffer-new!,
;; free-buffer, count-buffer-free!, all exported by native.sls and already
;; imported here), to observe the counter between allocation and free rather
;; than only before and after -- call-with-render-buffer's own dynamic-wind
;; frees before returning, so nothing outside it ever sees the buffer alive.
(test-assert "the counters actually move while a document is live"
  (let ((before (live-counts)))
    (call-with-native-document "# probe\n" (options->bits opts) gfm-extension-names
      (lambda (h)
        (let* ((during-doc (live-counts))
               (buf (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))
          (and (not (zero? buf))
               (begin
                 (count-buffer-new!)
                 (let ((during-buf (live-counts)))
                   (free-buffer buf)
                   (count-buffer-free!)
                   (and (> (car during-doc)   (car before))    ; live-parsers
                        (> (cadr during-doc)  (cadr before))    ; live-roots
                        (> (caddr during-buf) (caddr before))))))))))) ; live-buffers

(test-equal "counters are zero before the loop"
  '(0 0 0) (live-counts))

;; The point of the suite: nothing accumulates. Checked after EVERY iteration,
;; not just at the end, so a failure names the iteration it first appeared in.
;;
;; What this assertion reads is live-counts -- the paired Scheme-side
;; counters each resource's after-thunk increments/decrements alongside its
;; real native call (e.g. free-buffer/count-buffer-free! at
;; scope.sls:187-188) -- not real allocator state. A dropped free whose
;; paired count is ALSO dropped is caught here: that is the realistic
;; regression shape, a whole cleanup block deleted in a refactor, taking
;; free and count together. A dropped free whose paired count survives is
;; NOT caught: the counters still return to (0 0 0) while the real
;; allocation leaks. That uncaught case is exactly what `make test-memory`
;; (Valgrind on Linux, ASan on macOS) exists to catch -- which is why the
;; release treats sanitizer, leak, stress, and conformance as four distinct
;; legs, not one subsuming the others.
(test-equal "no native resource accumulates across iterations"
  'balanced
  (let loop ((i 0))
    (cond
      ((= i iterations) 'balanced)
      (else
       (for-each exercise-all documents)
       (if (equal? (live-counts) '(0 0 0))
           (loop (+ i 1))
           (list 'leaked-at-iteration i (live-counts)))))))

(test-equal "counters are zero after the loop"
  '(0 0 0) (live-counts))

(test-end "stress")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
