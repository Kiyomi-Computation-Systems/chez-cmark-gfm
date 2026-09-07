#!r6rs
;;; Public API. Conditions are re-exported so callers can handle every public
;;; failure without importing a private library.
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
          sxml-options-attribute-marker

          ;; renderers
          markdown->html markdown->commonmark markdown->plaintext markdown->xml

          ;; AST
          markdown->ast
          ;; SXML
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

          ;; resource limits
          cmark-options-max-nodes cmark-options-max-depth
          default-ast-options

          ;; version and capability
          cmark-gfm-version cmark-gfm-version-compatible?
          cmark-gfm-available-extensions

          ;; conditions
          &cmark-error cmark-error?
          &cmark-version-incompatible cmark-version-incompatible?
          cmark-version-incompatible-supported cmark-version-incompatible-runtime
          &cmark-dead-document cmark-dead-document?
          &cmark-extension-unavailable cmark-extension-unavailable?
          cmark-extension-unavailable-name
          &cmark-invalid-input cmark-invalid-input? cmark-invalid-input-reason
          &cmark-library-unavailable cmark-library-unavailable?
          cmark-library-unavailable-path cmark-library-unavailable-reason
          &cmark-invalid-option cmark-invalid-option?
          cmark-invalid-option-key cmark-invalid-option-reason
          &cmark-render-failed cmark-render-failed? cmark-render-failed-format

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

  ;; markdown->sxml : string [cmark-options [sxml-options]] -> sxml
  ;; Source positions default off because SXML does not retain them.
  (define markdown->sxml
    (case-lambda
      ((md) (markdown->sxml md (default-cmark-options) (default-sxml-options)))
      ((md o) (markdown->sxml md o (default-sxml-options)))
      ((md o so)
       (unless (cmark-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       ;; These cmark renderer options cannot affect the AST. Reject them
       ;; before allocation; SXML rendering policy belongs to sxml-options.
       (when (cmark-options-unsafe-html? o)
         (raise (make-cmark-invalid-option 'unsafe-html? 'not-applicable)))
       (when (cmark-options-hardbreaks? o)
         (raise (make-cmark-invalid-option 'hardbreaks? 'not-applicable)))
       (when (cmark-options-nobreaks? o)
         (raise (make-cmark-invalid-option 'nobreaks? 'not-applicable)))
       ;; source-positions? is accepted because it affects parsing, though the
       ;; SXML conversion ultimately discards the positions.
       (markdown-ast->sxml (markdown->ast md o) so))))

  ;; cmark-gfm-version : -> string
  ;; Do not call ensure-native-loaded!: callers need the version even when it
  ;; is incompatible.
  (define (cmark-gfm-version)
    (runtime-version-string))

  ;; cmark-gfm-version-compatible? : -> boolean
  (define (cmark-gfm-version-compatible?)
    (version-compatible? (cmark-runtime-version)))

  ;; cmark-gfm-available-extensions : -> (listof symbol)
  ;; Probe registry-owned pointers after registration; never free them.
  (define (cmark-gfm-available-extensions)
    (ensure-native-loaded!)
    (filter (lambda (sym)
              (not (zero? (find-extension (extension->native-name sym)))))
            (supported-extensions))))
