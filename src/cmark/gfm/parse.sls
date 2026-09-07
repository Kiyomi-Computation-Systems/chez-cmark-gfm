#!r6rs
;;; Public Markdown-to-AST entry point.
;;;
;;; Attach positions only when CMARK_OPT_SOURCEPOS was used for parsing;
;;; cmark can otherwise report inaccurate inline end positions.
(library (cmark gfm parse)
  (export markdown->ast)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm private conditions)
          (cmark gfm private native)
          (cmark gfm private scope)
          (cmark gfm private convert))

  (define (options->bits o)
    (option-bits (cmark-options-validate-utf8? o)
                 (cmark-options-source-positions? o)
                 (cmark-options-hardbreaks? o)
                 (cmark-options-nobreaks? o)
                 (cmark-options-smart? o)
                 (cmark-options-unsafe-html? o)))

  ;; markdown->ast : string -> markdown-node
  ;; markdown->ast : string cmark-options -> markdown-node
  (define markdown->ast
    (case-lambda
      ((markdown) (markdown->ast markdown (default-ast-options)))
      ((markdown o)
       ;; Reject bad options before acquiring native resources.
       (unless (cmark-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       (call-with-native-document
        markdown
        (options->bits o)
        (map extension->native-name (cmark-options-extensions o))
        (lambda (h)
          (convert-document h (make-convert-ctx
                               (cmark-options-max-nodes o)
                               (cmark-options-max-depth o)
                               (cmark-options-source-positions? o))))
        (cmark-options-max-input-bytes o))))))
