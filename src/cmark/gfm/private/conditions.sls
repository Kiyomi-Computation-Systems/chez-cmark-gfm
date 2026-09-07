#!r6rs
;;; Structured conditions for chez-cmark-gfm.
;;; All derive from &cmark-error so callers can catch the family or a subtype.
(library (cmark gfm private conditions)
  (export &cmark-error make-cmark-error cmark-error?

          &cmark-version-incompatible make-cmark-version-incompatible
          cmark-version-incompatible?
          cmark-version-incompatible-supported
          cmark-version-incompatible-runtime

          &cmark-dead-document make-cmark-dead-document cmark-dead-document?

          &cmark-extension-unavailable make-cmark-extension-unavailable
          cmark-extension-unavailable? cmark-extension-unavailable-name

          &cmark-invalid-input make-cmark-invalid-input
          cmark-invalid-input? cmark-invalid-input-reason

          &cmark-resource-limit make-cmark-resource-limit
          cmark-resource-limit? cmark-resource-limit-value

          &cmark-library-unavailable make-cmark-library-unavailable
          cmark-library-unavailable? cmark-library-unavailable-path
          cmark-library-unavailable-reason

          &cmark-invalid-option make-cmark-invalid-option
          cmark-invalid-option? cmark-invalid-option-key
          cmark-invalid-option-reason

          &cmark-render-failed make-cmark-render-failed
          cmark-render-failed? cmark-render-failed-format

          &cmark-unsupported-node make-cmark-unsupported-node
          cmark-unsupported-node? cmark-unsupported-node-type

          &cmark-malformed-tree make-cmark-malformed-tree
          cmark-malformed-tree? cmark-malformed-tree-reason)
  (import (rnrs))

  (define-condition-type &cmark-error &error
    make-cmark-error cmark-error?)

  ;; A discovered or loaded library is outside the supported range.
  (define-condition-type &cmark-version-incompatible &cmark-error
    make-cmark-version-incompatible cmark-version-incompatible?
    (supported cmark-version-incompatible-supported)
    (runtime   cmark-version-incompatible-runtime))

  ;; A checked native handle was used after teardown.
  (define-condition-type &cmark-dead-document &cmark-error
    make-cmark-dead-document cmark-dead-document?)

  (define-condition-type &cmark-extension-unavailable &cmark-error
    make-cmark-extension-unavailable cmark-extension-unavailable?
    (name cmark-extension-unavailable-name))

  ;; reason: 'embedded-nul, 'too-large, 'not-a-string, or
  ;; 'extension-name-not-a-string.
  (define-condition-type &cmark-invalid-input &cmark-error
    make-cmark-invalid-input cmark-invalid-input?
    (reason cmark-invalid-input-reason))

  ;; A valid input exceeded a configured ceiling. reason is 'too-large,
  ;; 'too-many-nodes, or 'too-deep; value is the configured limit.
  (define-condition-type &cmark-resource-limit &cmark-invalid-input
    make-cmark-resource-limit cmark-resource-limit?
    (value cmark-resource-limit-value))

  ;; The cmark shared objects could not be resolved or loaded.
  ;;   'not-found        -- no candidate directory held a matched core +
  ;;                        extensions pair at a supported version, and
  ;;                        CHEZ_CMARK_GFM_LIBS was not set. `path` is #f:
  ;;                        there is no single path to name.
  ;;   'invalid-override -- CHEZ_CMARK_GFM_LIBS is set but is not two absolute
  ;;                        paths to existing regular files, one core and one
  ;;                        extensions library
  ;;   'load-failed      -- load-shared-object raised on a validated path
  ;;   'missing-entry-point -- the library loaded and its version is inside the
  ;;                        supported range, but it predates an entry point
  ;;                        this binding requires. `path` names the shared
  ;;                        object that should have held the symbol.
  ;;
  ;; 'invalid-override covers every malformed override because the remedy is
  ;; always to name both libraries by absolute path.
  (define-condition-type &cmark-library-unavailable &cmark-error
    make-cmark-library-unavailable cmark-library-unavailable?
    (path   cmark-library-unavailable-path)
    (reason cmark-library-unavailable-reason))

  ;; key is a field name, or #f for the argument list as a whole. reason:
  ;; 'malformed-plist, 'unknown-key,
  ;; 'duplicate-key, 'invalid-value, 'unknown-extension, 'contradictory,
  ;; 'invalid-width.
  (define-condition-type &cmark-invalid-option &cmark-error
    make-cmark-invalid-option cmark-invalid-option?
    (key    cmark-invalid-option-key)
    (reason cmark-invalid-option-reason))

  ;; A cmark renderer returned NULL. format is one of:
  ;; 'html, 'xml, 'commonmark, 'plaintext.
  (define-condition-type &cmark-render-failed &cmark-error
    make-cmark-render-failed cmark-render-failed?
    (format cmark-render-failed-format))

  ;; The SXML adapter lacks HTML vocabulary for a valid AST node type. This is
  ;; an adapter gap, not invalid input.
  (define-condition-type &cmark-unsupported-node &cmark-error
    make-cmark-unsupported-node cmark-unsupported-node?
    (type cmark-unsupported-node-type))

  ;; A caller-built or rewritten AST has a shape the parser cannot produce.
  (define-condition-type &cmark-malformed-tree &cmark-error
    make-cmark-malformed-tree cmark-malformed-tree?
    (reason cmark-malformed-tree-reason)))
