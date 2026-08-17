#!r6rs
;;; markdown->ast -- the public AST entry point.
;;;
;;; This library exists so that the public procedure is layer 3. convert.sls
;;; is layer 2 and must not import the options record; parse.sls unpacks the
;;; record into primitives, exactly as render.sls unpacks it into option bits.
;;;
;;; The arity is the API. (markdown->ast md) uses default-ast-options, whose
;;; only difference from default-cmark-options is source-positions? #t; the
;;; two-argument form honours the caller's record verbatim. That is ADR-0009's
;;; per-entry-point default, delivered as ordinary data rather than as a third
;;; "unset" state inside the options record.
;;;
;;; Positions are governed by the SAME flag the parse used, never by a
;;; separate switch. CMARK_OPT_SOURCEPOS is not merely a rendering flag: with
;;; it off, cmark skips a correction (vendor/cmark-gfm/src/inlines.c:292-296)
;;; that leaves multi-line code spans and raw inline HTML with wrong end
;;; positions, and the error propagates to later inlines in the same block. So
;;; positions are attached only when they were parsed correctly.
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

  (define markdown->ast
    (case-lambda
      ((markdown) (markdown->ast markdown (default-ast-options)))
      ((markdown o)
       ;; Checked before anything native is acquired, so a bad argument leaves
       ;; no resource to clean up -- the bug Stage 1 shipped for extension
       ;; names and Stage 2 for width.
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
