#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) collect)   ; NOT exit: (rnrs) exports it
        (cmark gfm)
        (cmark gfm private native)    ; option-bits, live-counts, render-html,
                                      ; runtime-version-string
        (cmark gfm private scope))    ; call-with-native-document, doc-*,
                                      ; call-with-render-buffer

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

;; --- the four renderers -------------------------------------------------
(define plain (make-cmark-options 'extensions '()))

(test-equal "markdown->html renders a heading"
  "<h1>hi</h1>\n" (markdown->html "# hi\n" plain))

(test-equal "markdown->commonmark round-trips a heading"
  "# hi\n" (markdown->commonmark "# hi\n" plain))

(test-equal "markdown->plaintext strips the markup"
  "hi\n" (markdown->plaintext "# hi\n" plain))

;; Not merely "a non-empty string" -- that would pass for literally any
;; output. Checked against the shape cmark actually emits, confirmed with
;; `cmark-gfm --to xml`.
(test-assert "markdown->xml emits a CommonMark XML document"
  (let ((s (markdown->xml "# hi\n" plain)))
    (and (string-contains? s "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
         (string-contains? s "<document xmlns=\"http://commonmark.org/xml/1.0\">")
         (string-contains? s "<heading level=\"1\">")
         (string-contains? s "<text xml:space=\"preserve\">hi</text>"))))

;; Extension NODE rendering (tables, strikethrough, tasklists) dispatches
;; through each node's own ->extension pointer, set at PARSE time when
;; call-with-native-document attaches the extension list to the parser
;; (vendor/cmark-gfm/src/html.c:142-144). It does NOT go through the
;; `extensions` argument render-html receives, so this test cannot and does
;; not discriminate that argument -- see the test below for the one thing
;; that argument actually controls. What this test does verify: that
;; markdown->html's extension SYMBOLS reach the parser at all --
;; options->native-names converts them and call-with-native-document
;; attaches them, so a table parses into extension nodes and those nodes
;; render.
(test-assert "tables render through markdown->html, given the default extension set"
  (let ((s (markdown->html "| a |\n|---|\n| 1 |\n" (default-cmark-options))))
    (and (string-contains? s "<table>") (string-contains? s "<td>1</td>"))))

(test-assert "strikethrough renders through markdown->html"
  (string-contains? (markdown->html "~~gone~~\n" (default-cmark-options)) "<del>"))

;; What the `extensions` argument passed to render-html actually controls:
;; cmark_render_html (vendor/cmark-gfm/src/html.c:480-485) filters it down
;; to extensions with an html_filter_func -- tagfilter
;; (vendor/cmark-gfm/extensions/tagfilter.c) is the ONLY extension that sets
;; one. The filtered list becomes renderer.filter_extensions, consulted only
;; when unsafe-html? is on, to defang dangerous raw tags such as <script> by
;; escaping its leading '<' to '&lt;'. Drop this argument (e.g.
;; markdown->html's `(doc-extensions h)` mutated to `0`) and table,
;; strikethrough, and tasklist output are untouched -- only this collapses.
;;
;; Verified against the pinned CLI: `cmark-gfm --unsafe -e tagfilter` on
;; "<script>alert(1)</script>" emits "&lt;script>alert(1)&lt;/script>" --
;; only the opening '<' is escaped, not the closing one, so the expected
;; substring below is "&lt;script>", not "&lt;script&gt;".
(test-assert "tagfilter's <script> defanging under unsafe-html? requires the extension list reaching render-html"
  (string-contains? (markdown->html "<script>alert(1)</script>\n"
                                    (make-cmark-options 'unsafe-html? #t))
                    "&lt;script>"))

;; --- width --------------------------------------------------------------
(test-assert "a width argument actually wraps commonmark output"
  (let ((wide   (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain))
        (narrow (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain 10)))
    (not (string=? wide narrow))))

(test-equal "width defaults to 0 (nowrap), matching the CLI"
  (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain 0)
  (markdown->commonmark "aaa bbb ccc ddd eee fff\n" plain))

(test-equal "a negative width is rejected"
  'invalid-width
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->commonmark "hi\n" plain -1)
    'no-condition))

(test-equal "an inexact width is rejected"
  'invalid-width
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->plaintext "hi\n" plain 72.0)
    'no-condition))

;; Width is validated BEFORE any native resource is acquired, so a bad width
;; leaves nothing to clean up. Stage 1 shipped the opposite bug for
;; extension names and this is the same class.
(test-assert "counters balance after a bad width is rejected"
  (let ((before (live-counts)))
    (guard (e (#t #t)) (markdown->commonmark "hi\n" plain -1))
    (equal? before (live-counts))))

;; --- options plumbing ---------------------------------------------------
(test-assert "source-positions? #t reaches the HTML renderer"
  (string-contains? (markdown->html "# hi\n" (make-cmark-options 'source-positions? #t
                                                                'extensions '()))
                    "data-sourcepos"))

(test-assert "the default options do NOT emit data-sourcepos (ADR-0008)"
  (not (string-contains? (markdown->html "# hi\n" (default-cmark-options))
                         "data-sourcepos")))

;; --- safe by default (Stage 4 owns hardening; this is the 0.1 regression) --
(test-assert "raw HTML is suppressed by default"
  (string-contains? (markdown->html "<script>alert(1)</script>\n" (default-cmark-options))
                    "<!-- raw HTML omitted -->"))

;; Verified against the CLI: in safe mode cmark empties the href rather than
;; dropping the anchor.
(test-assert "a javascript: link has its href emptied by default"
  (string-contains? (markdown->html "[c](javascript:alert(1))\n" (default-cmark-options))
                    "<a href=\"\">c</a>"))

;; extensions '() isolates the property under test. With the DEFAULT
;; extension set, the tagfilter extension defangs <script> (escaping its
;; leading '<' to '&lt;') REGARDLESS of unsafe-html?, so an un-isolated probe
;; cannot tell "unsafe-html? plumbing works" apart from "tagfilter ran".
;; Verified directly against this binding: with the default extensions,
;; (markdown->html "<script>alert(1)</script>\n" (make-cmark-options
;; 'unsafe-html? #t)) produces "&lt;script>alert(1)&lt;/script>\n" -- not the
;; brief's predicted "<script>...". Confirmed against the CLI too:
;; `--unsafe -e tagfilter` still yields '&lt;script>...'; only with tagfilter
;; absent does --unsafe restore literal '<script>'.
(test-assert "unsafe-html? #t is required to emit raw HTML"
  (string-contains? (markdown->html "<script>alert(1)</script>\n"
                                    (make-cmark-options 'unsafe-html? #t
                                                         'extensions '()))
                    "<script>"))

;; --- input validation flows from the options record ---------------------
(test-equal "max-input-bytes from the options record is enforced"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e))
            (#t 'wrong-condition))
    (markdown->html "this is eleven" (make-cmark-options 'max-input-bytes 4))
    'no-condition))

(test-equal "embedded NUL is rejected through the public API"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e))
            (#t 'wrong-condition))
    (markdown->html "a\x0;b" (default-cmark-options))
    'no-condition))

(test-equal "a non-options second argument is rejected"
  'invalid-value
  (guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e))
            (#t 'wrong-condition))
    (markdown->html "hi\n" 'not-options)
    'no-condition))

;; --- capability inspection ---------------------------------------------
(test-equal "cmark-gfm-version reports the loaded library's version string"
  (runtime-version-string) (cmark-gfm-version))

(test-assert "cmark-gfm-version-compatible? is true for the pinned build"
  (eq? #t (cmark-gfm-version-compatible?)))

;; Compared against the expected LIST, not asserted truthy: a probe that
;; returned '() or dropped one extension would still be truthy-ish under a
;; weaker assertion.
(test-equal "all five standard extensions are available in the loaded library"
  '(autolink strikethrough table tagfilter tasklist)
  (cmark-gfm-available-extensions))

;; This is what stops options.sls's symbol->string mapping from being an
;; invariant held by luck. If a native name in that alist were misspelled,
;; find-extension would return NULL for it and it would drop out of this list.
(test-equal "every supported extension symbol maps to a name cmark resolves"
  (supported-extensions)
  (cmark-gfm-available-extensions))

;; --- the façade really re-exports --------------------------------------
(test-equal "the façade exposes the renderers"
  "<h1>hi</h1>\n" (markdown->html "# hi\n" (make-cmark-options 'extensions '())))

(test-assert "the façade exposes the condition predicates"
  (guard (e ((cmark-invalid-option? e) #t) (#t #f))
    (make-cmark-options 'nope #t)))

(test-end "render")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
