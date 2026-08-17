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
          cmark-version-incompatible-compiled
          cmark-version-incompatible-runtime

          &cmark-dead-document make-cmark-dead-document cmark-dead-document?

          &cmark-extension-unavailable make-cmark-extension-unavailable
          cmark-extension-unavailable? cmark-extension-unavailable-name

          &cmark-invalid-input make-cmark-invalid-input
          cmark-invalid-input? cmark-invalid-input-reason

          &cmark-shim-unavailable make-cmark-shim-unavailable
          cmark-shim-unavailable? cmark-shim-unavailable-path

          &cmark-invalid-option make-cmark-invalid-option
          cmark-invalid-option? cmark-invalid-option-key
          cmark-invalid-option-reason

          &cmark-render-failed make-cmark-render-failed
          cmark-render-failed? cmark-render-failed-format)
  (import (rnrs))

  (define-condition-type &cmark-error &error
    make-cmark-error cmark-error?)

  ;; Raised at initialisation when the shim's compile-time version and the
  ;; runtime library disagree beyond the supported range. Fails closed.
  (define-condition-type &cmark-version-incompatible &cmark-error
    make-cmark-version-incompatible cmark-version-incompatible?
    (compiled cmark-version-incompatible-compiled)
    (runtime  cmark-version-incompatible-runtime))

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

  (define-condition-type &cmark-shim-unavailable &cmark-error
    make-cmark-shim-unavailable cmark-shim-unavailable?
    (path cmark-shim-unavailable-path))

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
    (format cmark-render-failed-format)))
