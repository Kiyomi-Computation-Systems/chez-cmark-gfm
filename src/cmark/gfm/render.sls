#!r6rs
;;; Direct native renderers.
;;;
;;; Every renderer runs INSIDE call-with-native-document's body, reading the
;;; root, option bits, and extension list through scope.sls's checked
;;; accessors. That is what enforces ADR-0005 -- the parser must outlive the
;;; render call, because cmark_parser_free releases the same syntax-extension
;;; list cmark_render_html walks. No new guard is needed: a dead handle
;;; raises before any renderer is reached.
;;;
;;; Width is an argument here rather than a field of the options record.
;;; markdown->html and markdown->xml are fixed at arity 2, so passing a width
;;; to them is an arity error at the call site instead of a silently ignored
;;; field. That mirrors cmark's own factoring: option bits go to both parser
;;; and renderer, width goes only to some renderers.
(library (cmark gfm render)
  (export markdown->html markdown->commonmark markdown->plaintext markdown->xml)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm private conditions)
          (cmark gfm private native)
          (cmark gfm private scope))

  (define (options->bits o)
    (option-bits (cmark-options-validate-utf8? o)
                 (cmark-options-source-positions? o)
                 (cmark-options-hardbreaks? o)
                 (cmark-options-nobreaks? o)
                 (cmark-options-smart? o)
                 (cmark-options-unsafe-html? o)))

  (define (options->native-names o)
    (map extension->native-name (cmark-options-extensions o)))

  ;; Validated before anything native is acquired, so a bad width leaves no
  ;; resource to clean up. Stage 1 shipped exactly this bug for extension
  ;; names; see tests/test-lifecycle.sps's I1 group.
  (define (check-width w)
    (unless (and (integer? w) (exact? w) (>= w 0))
      (raise (make-cmark-invalid-option 'width 'invalid-width)))
    w)

  (define (check-options o)
    (unless (cmark-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    o)

  ;; make-buffer-for receives the live handle and returns a thunk. Keeping it
  ;; a thunk means the buffer address is produced inside
  ;; call-with-render-buffer and never rests in a variable here.
  (define (render markdown o format make-buffer-for)
    (check-options o)
    (call-with-native-document
     markdown (options->bits o) (options->native-names o)
     (lambda (h) (call-with-render-buffer format (make-buffer-for h)))
     (cmark-options-max-input-bytes o)))

  (define (markdown->html markdown o)
    (render markdown o 'html
            (lambda (h)
              (lambda ()
                (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))))

  (define (markdown->xml markdown o)
    (render markdown o 'xml
            (lambda (h)
              (lambda ()
                (render-xml (doc-root h) (doc-option-bits h))))))

  (define markdown->commonmark
    (case-lambda
      ((markdown o) (markdown->commonmark markdown o 0))
      ((markdown o width)
       (let ((w (check-width width)))
         (render markdown o 'commonmark
                 (lambda (h)
                   (lambda ()
                     (render-commonmark (doc-root h) (doc-option-bits h) w))))))))

  (define markdown->plaintext
    (case-lambda
      ((markdown o) (markdown->plaintext markdown o 0))
      ((markdown o width)
       (let ((w (check-width width)))
         (render markdown o 'plaintext
                 (lambda (h)
                   (lambda ()
                     (render-plaintext (doc-root h) (doc-option-bits h) w)))))))))
