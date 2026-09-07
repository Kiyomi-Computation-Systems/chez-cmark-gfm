#!r6rs
;;; Direct native renderers.
;;;
;;; Render inside call-with-native-document: freeing the parser also frees the
;;; syntax-extension list consumed by cmark_render_html.
;;;
;;; Width is an argument only to renderers that support it.
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

  ;; Validate before acquiring native resources.
  (define (check-width w)
    (unless (and (integer? w) (exact? w) (>= w 0))
      (raise (make-cmark-invalid-option 'width 'invalid-width)))
    w)

  (define (check-options o)
    (unless (cmark-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    o)

  ;; The thunk creates the buffer inside its cleanup scope.
  (define (render markdown o format make-buffer-for)
    (check-options o)
    (call-with-native-document
     markdown (options->bits o) (options->native-names o)
     (lambda (h) (call-with-render-buffer format (make-buffer-for h)))
     (cmark-options-max-input-bytes o)))

  ;; markdown->html : string cmark-options -> string
  (define (markdown->html markdown o)
    (render markdown o 'html
            (lambda (h)
              (lambda ()
                (render-html (doc-root h) (doc-option-bits h) (doc-extensions h))))))

  ;; markdown->xml : string cmark-options -> string
  (define (markdown->xml markdown o)
    (render markdown o 'xml
            (lambda (h)
              (lambda ()
                (render-xml (doc-root h) (doc-option-bits h))))))

  ;; markdown->commonmark : string cmark-options [exact-nonnegative-integer] -> string
  (define markdown->commonmark
    (case-lambda
      ((markdown o) (markdown->commonmark markdown o 0))
      ((markdown o width)
       (let ((w (check-width width)))
         (render markdown o 'commonmark
                 (lambda (h)
                   (lambda ()
                     (render-commonmark (doc-root h) (doc-option-bits h) w))))))))

  ;; markdown->plaintext : string cmark-options [exact-nonnegative-integer] -> string
  (define markdown->plaintext
    (case-lambda
      ((markdown o) (markdown->plaintext markdown o 0))
      ((markdown o width)
       (let ((w (check-width width)))
         (render markdown o 'plaintext
                 (lambda (h)
                   (lambda ()
                     (render-plaintext (doc-root h) (doc-option-bits h) w)))))))))
