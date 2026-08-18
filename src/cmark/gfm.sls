#!r6rs
;;; The convenient public API. Consumers import this.
;;;
;;; Conditions are re-exported here on purpose. conditions.sls lives under
;;; private/ as an implementation location, but project plan 12 defines the
;;; condition types as part of the public contract -- a caller cannot handle
;;; failures it has no names for.
(library (cmark gfm)
  (export ;; options
          make-cmark-options default-cmark-options cmark-options-with
          cmark-options?
          cmark-options-extensions
          cmark-options-validate-utf8?
          cmark-options-source-positions?
          cmark-options-hardbreaks?
          cmark-options-nobreaks?
          cmark-options-smart?
          cmark-options-unsafe-html?
          cmark-options-max-input-bytes
          supported-extensions

          ;; SXML options
          make-sxml-options default-sxml-options sxml-options-with
          sxml-options? sxml-options-raw-html sxml-options-softbreak

          ;; renderers
          markdown->html markdown->commonmark markdown->plaintext markdown->xml

          ;; AST
          markdown->ast
          ;; SXML convenience entry point and the pure adapter it wraps --
          ;; design spec 2.2 lists both as public; without this re-export
          ;; the adapter is reachable only via (cmark gfm sxml) directly.
          markdown->sxml markdown-ast->sxml
          make-markdown-node markdown-node?
          markdown-node-type markdown-node-properties
          markdown-node-children markdown-node-source
          markdown-node-property
          markdown-node-with-properties markdown-node-with-children
          markdown-node-map markdown-node-fold
          make-source-position source-position?
          source-position-start-line source-position-start-column
          source-position-end-line   source-position-end-column

          ;; new options
          cmark-options-max-nodes cmark-options-max-depth
          default-ast-options

          ;; version and capability
          cmark-gfm-version cmark-gfm-version-compatible?
          cmark-gfm-available-extensions

          ;; conditions
          &cmark-error cmark-error?
          &cmark-version-incompatible cmark-version-incompatible?
          cmark-version-incompatible-compiled cmark-version-incompatible-runtime
          &cmark-dead-document cmark-dead-document?
          &cmark-extension-unavailable cmark-extension-unavailable?
          cmark-extension-unavailable-name
          &cmark-invalid-input cmark-invalid-input? cmark-invalid-input-reason
          &cmark-shim-unavailable cmark-shim-unavailable? cmark-shim-unavailable-path
          &cmark-invalid-option cmark-invalid-option?
          cmark-invalid-option-key cmark-invalid-option-reason
          &cmark-render-failed cmark-render-failed? cmark-render-failed-format

          ;; new condition
          &cmark-resource-limit cmark-resource-limit?
          cmark-resource-limit-value

          &cmark-unsupported-node cmark-unsupported-node?
          cmark-unsupported-node-type

          &cmark-malformed-tree cmark-malformed-tree?
          cmark-malformed-tree-reason)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm render)
          (cmark gfm ast)
          (cmark gfm parse)
          (cmark gfm sxml)
          (cmark gfm private conditions)
          (cmark gfm private native))

  ;; Lives here rather than in sxml.sls because it parses: putting it there
  ;; would pull (cmark gfm private native) into that library's import chain
  ;; and forfeit `make check-purity`.
  ;;
  ;; Defaults to default-cmark-options, NOT default-ast-options: positions
  ;; never reach SXML (ADR-0011), so turning CMARK_OPT_SOURCEPOS on would
  ;; cost a flag in the parse for information the output discards. That is
  ;; ADR-0009's per-entry-point principle pointing the other way from
  ;; markdown->ast.
  (define markdown->sxml
    (case-lambda
      ((md) (markdown->sxml md (default-cmark-options) (default-sxml-options)))
      ((md o) (markdown->sxml md o (default-sxml-options)))
      ((md o so)
       (unless (cmark-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       ;; Checked before anything native is acquired, so a rejected call
       ;; leaves no resource to clean up.
       ;;
       ;; All three are cmark RENDERER options. Verified: CMARK_OPT_UNSAFE,
       ;; CMARK_OPT_HARDBREAKS, and CMARK_OPT_NOBREAKS appear only in
       ;; cmark-gfm.h, main.c, and the five renderers -- never in blocks.c,
       ;; inlines.c, or parser.h. So none of them can reach the AST, and SXML
       ;; is a different renderer with its own policies: raw-html and
       ;; softbreak on the sxml-options record. Accepting one silently would
       ;; discard a setting the caller made explicitly.
       (when (cmark-options-unsafe-html? o)
         (raise (make-cmark-invalid-option 'unsafe-html? 'not-applicable)))
       (when (cmark-options-hardbreaks? o)
         (raise (make-cmark-invalid-option 'hardbreaks? 'not-applicable)))
       (when (cmark-options-nobreaks? o)
         (raise (make-cmark-invalid-option 'nobreaks? 'not-applicable)))
       (markdown-ast->sxml (markdown->ast md o) so))))

  ;; Deliberately does NOT call ensure-native-loaded!. runtime-version-string
  ;; needs no initialisation: its foreign procedure is bound as soon as
  ;; native.sls's library body loads the shared object, which has already
  ;; happened by the time any code in this library runs. ensure-native-loaded!
  ;; adds only the version-compatibility check and extension registration on
  ;; top of that -- and the compatibility check is exactly what a caller
  ;; reaches for this procedure to diagnose. Calling it here would make
  ;; cmark-gfm-version raise &cmark-version-incompatible on the one runtime it
  ;; exists to report on, instead of answering the question asked.
  (define (cmark-gfm-version)
    (runtime-version-string))

  (define (cmark-gfm-version-compatible?)
    (version-compatible? (shim-compiled-version) (shim-runtime-version)))

  ;; Probes rather than enumerates. cmark_list_syntax_extensions would hand
  ;; back a cmark_llist* to traverse and free; find-extension returns a
  ;; registry-owned pointer we must NOT free, so this costs no ownership.
  ;; ensure-native-loaded! must run first -- it is what registers them.
  (define (cmark-gfm-available-extensions)
    (ensure-native-loaded!)
    (filter (lambda (sym)
              (not (zero? (find-extension (extension->native-name sym)))))
            (supported-extensions))))
