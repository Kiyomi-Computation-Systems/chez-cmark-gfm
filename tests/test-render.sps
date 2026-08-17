#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) collect)   ; NOT exit: (rnrs) exports it
        (cmark gfm private native)
        (cmark gfm private conditions)
        (cmark gfm private scope))

(define runner (test-runner-simple))
(test-runner-current runner)

(ensure-native-loaded!)

(test-begin "render")

;; R6RS has no string-contains?; several assertions below check for a
;; substring of rendered output.
(define (string-contains? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

(define opts (option-bits #t #f #f #f #f #f))
(define gfm-extensions '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

(define (render-html-of markdown)
  (call-with-native-document markdown opts gfm-extensions
    (lambda (h)
      (call-with-render-buffer 'html
        (lambda () (render-html (doc-root h) (doc-option-bits h) (doc-extensions h)))))))

;; --- the buffer produces a real, Scheme-owned string -------------------
(test-equal "a heading renders to HTML"
  "<h1>hi</h1>\n"
  (render-html-of "# hi\n"))

;; A copy, not an alias. If call-with-render-buffer returned something
;; backed by the native buffer, this value would be garbage after the free
;; in its after-thunk and after a GC pass.
(test-equal "the rendered string survives the buffer free and a collection"
  "<p>keep me</p>\n"
  (let ((s (render-html-of "keep me\n")))
    (collect)
    s))

;; --- counter balance and MOVEMENT --------------------------------------
;; live-buffers is the third element of live-counts. Built WITHOUT
;; -DCHEZ_CMARK_DEBUG_COUNTERS the shim hardcodes chez_cmark_live_buffers to
;; return 0 (src/cmark-gfm-shim.c), so every balance test below would compare
;; 0 to 0 and pass against a shim that counts nothing at all.
;;
;; Movement is asserted at the PRIMITIVE level, not from inside a render.
;; call-with-render-buffer runs no caller code inside its extent -- that is
;; the safety property this task is built around -- so there is nowhere for a
;; test to observe the counter mid-flight, and a thunk passed as make-buffer
;; runs BEFORE count-buffer-new! is reached. This form fails against a
;; counters-free shim and passes against a counting one, which is all the
;; balance tests below need in order to mean anything.
(test-assert "the buffer counter actually moves"
  (let ((before (caddr (live-counts))))
    (count-buffer-new!)
    (let ((during (caddr (live-counts))))
      (count-buffer-free!)
      (and (> during before)
           (= before (caddr (live-counts)))))))

(test-assert "counters balance after a successful render"
  (let ((before (live-counts)))
    (render-html-of "# hi\n")
    (equal? before (live-counts))))

(test-assert "counters balance after the render scope's body raises"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "# hi\n" opts gfm-extensions
        (lambda (h)
          (call-with-render-buffer 'html
            (lambda ()
              (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))
          (error 'test "deliberate failure after rendering"))))
    (equal? before (live-counts))))

;; What the two balance tests above catch on their own: deleting EITHER
;; count-buffer-new! or count-buffer-free! breaks them. Without new! the
;; counter goes negative (buffer allocated uncounted, then counted on free);
;; without free! it climbs. Only deleting BOTH would still balance -- and
;; "the buffer counter actually moves" is what rules that out.
(test-assert "200 renders leave the counters balanced"
  (let ((before (live-counts)))
    (let loop ((n 0))
      (when (< n 200)
        (render-html-of "# hi\n\n| a |\n|---|\n| 1 |\n")
        (loop (+ n 1))))
    (collect)
    (equal? before (live-counts))))

;; --- failure path -------------------------------------------------------
;; A NULL buffer must become a structured condition naming the format, not a
;; crash and not a #f masquerading as a rendered document.
(test-equal "a NULL buffer raises render-failed naming the format"
  'commonmark
  (guard (e ((cmark-render-failed? e) (cmark-render-failed-format e))
            (#t 'wrong-condition))
    (call-with-render-buffer 'commonmark (lambda () 0))
    'no-condition))

(test-assert "counters balance after a NULL buffer is rejected"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-render-buffer 'html (lambda () 0)))
    (equal? before (live-counts))))

;; --- ADR-0005 / ADR-0006 -----------------------------------------------
;; Rendering reads root, bits, and extensions through the CHECKED accessors,
;; so a handle whose scope has exited refuses before any renderer runs. This
;; is what makes parser-outlives-render structural rather than documented.
(test-equal "rendering from an escaped handle raises dead-document"
  'dead-document-raised
  (let ((escaped #f))
    (call-with-native-document "# hi\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (guard (e ((cmark-dead-document? e) 'dead-document-raised)
              (#t 'wrong-condition))
      (call-with-render-buffer 'html
        (lambda () (render-html (doc-root escaped)
                                (doc-option-bits escaped)
                                (doc-extensions escaped))))
      'no-condition)))

(test-end "render")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
