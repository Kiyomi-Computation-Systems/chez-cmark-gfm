#!r6rs
;;; Structured conditions for chez-cmark-gfm.
;;;
;;; Every failure the binding can produce is one of these, so callers never
;;; see a raw foreign-interface error. All of them derive from &cmark-error,
;;; which lets a caller catch the whole family or discriminate precisely.
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

  ;; Raised when a resolved library's version falls outside the range this
  ;; binding supports -- either a candidate directory's encoded version, at
  ;; discovery time, or the loaded library's own runtime version, at first
  ;; use via ensure-native-loaded!. Fails closed.
  (define-condition-type &cmark-version-incompatible &cmark-error
    make-cmark-version-incompatible cmark-version-incompatible?
    (supported cmark-version-incompatible-supported)
    (runtime   cmark-version-incompatible-runtime))

  ;; Raised when a native handle is touched after its scope was torn down.
  ;; This is what converts a use-after-free into an ordinary error (ADR-0006).
  (define-condition-type &cmark-dead-document &cmark-error
    make-cmark-dead-document cmark-dead-document?)

  (define-condition-type &cmark-extension-unavailable &cmark-error
    make-cmark-extension-unavailable cmark-extension-unavailable?
    (name cmark-extension-unavailable-name))

  ;; reason is a symbol: 'embedded-nul, 'too-large, 'not-a-string,
  ;; 'extension-name-not-a-string.
  (define-condition-type &cmark-invalid-input &cmark-error
    make-cmark-invalid-input cmark-invalid-input?
    (reason cmark-invalid-input-reason))

  ;; A resource ceiling, not malformed input. Derives from
  ;; &cmark-invalid-input rather than from &cmark-error directly so that 0.1
  ;; callers guarding cmark-invalid-input? on an oversized document keep
  ;; working unchanged (design spec 6.2), while new code can catch the whole
  ;; class of "the input was fine, the budget was too small" -- the one input
  ;; failure where retrying with a larger limit is a sensible response.
  ;;
  ;; One added field, not two. A `limit` field naming the category would be
  ;; one-to-one redundant with the inherited `reason`, and two fields that
  ;; must agree forever is the invariant limits.sls's header argues against.
  ;; reason discriminates ('too-large, 'too-many-nodes, 'too-deep); value
  ;; carries what reason cannot -- the ceiling as configured by the caller.
  (define-condition-type &cmark-resource-limit &cmark-invalid-input
    make-cmark-resource-limit cmark-resource-limit?
    (value cmark-resource-limit-value))

  ;; Raised when the cmark shared objects cannot be resolved or loaded.
  ;;   'not-found        -- no candidate directory held a matched core +
  ;;                        extensions pair at a supported version, and
  ;;                        CHEZ_CMARK_GFM_LIBS was not set. `path` is #f:
  ;;                        there is no single path to name.
  ;;   'invalid-override -- CHEZ_CMARK_GFM_LIBS is set but is not two absolute
  ;;                        paths to existing regular files, one core and one
  ;;                        extensions library
  ;;   'load-failed      -- load-shared-object raised on a validated path
  ;;
  ;; 'invalid-override deliberately covers several causes at once (wrong entry
  ;; count, a relative path, an absent file, two libraries of the same kind)
  ;; because the remedy is identical for all of them: name both libraries, by
  ;; absolute path.
  (define-condition-type &cmark-library-unavailable &cmark-error
    make-cmark-library-unavailable cmark-library-unavailable?
    (path   cmark-library-unavailable-path)
    (reason cmark-library-unavailable-reason))

  ;; Raised by the options layer before any native resource exists. key is a
  ;; field name, or #f when the problem is the argument list as a whole
  ;; (odd length). reason is a symbol: 'malformed-plist, 'unknown-key,
  ;; 'duplicate-key, 'invalid-value, 'unknown-extension, 'contradictory,
  ;; 'invalid-width.
  (define-condition-type &cmark-invalid-option &cmark-error
    make-cmark-invalid-option cmark-invalid-option?
    (key    cmark-invalid-option-key)
    (reason cmark-invalid-option-reason))

  ;; Raised when a cmark renderer returns NULL. format is a symbol:
  ;; 'html, 'xml, 'commonmark, 'plaintext.
  (define-condition-type &cmark-render-failed &cmark-error
    make-cmark-render-failed cmark-render-failed?
    (format cmark-render-failed-format))

  ;; The SXML adapter has no HTML vocabulary for a node type it does not
  ;; know. Derives from &cmark-error directly, NOT from
  ;; &cmark-invalid-input: the document is well-formed, the adapter is
  ;; incomplete, and a caller guarding bad input must not swallow a gap in
  ;; our own coverage. Project plan 12 asked for this condition; Stage 3
  ;; did not need it because it preserves unknown types as `extension`
  ;; nodes rather than raising.
  (define-condition-type &cmark-unsupported-node &cmark-error
    make-cmark-unsupported-node cmark-unsupported-node?
    (type cmark-unsupported-node-type))

  ;; A tree handed to markdown-ast->sxml that the parser itself could never
  ;; produce -- e.g. a table row order only a caller-built or -rewritten AST
  ;; can create (design spec 3.4). Derives from &cmark-error directly, NOT
  ;; from &cmark-invalid-input: conditions.sls:62-63 documents that type's
  ;; reasons as a closed set about raw Markdown text and option values, and
  ;; &cmark-unsupported-node was kept out of that family for the same
  ;; reason above -- a caller guarding bad documents must not silently
  ;; swallow a structurally ill-shaped tree, any more than it should swallow
  ;; a coverage gap in the adapter. Neither is "the document was bad".
  (define-condition-type &cmark-malformed-tree &cmark-error
    make-cmark-malformed-tree cmark-malformed-tree?
    (reason cmark-malformed-tree-reason)))
