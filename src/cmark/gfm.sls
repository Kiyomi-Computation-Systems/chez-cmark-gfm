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

          ;; renderers
          markdown->html markdown->commonmark markdown->plaintext markdown->xml

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
          &cmark-render-failed cmark-render-failed? cmark-render-failed-format)
  (import (rnrs)
          (cmark gfm options)
          (cmark gfm render)
          (cmark gfm private conditions)
          (cmark gfm private native))

  (define (cmark-gfm-version)
    (ensure-native-loaded!)
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
