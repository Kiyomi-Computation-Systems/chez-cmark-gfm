#!r6rs
;;; Pure resource limits, shared between the public options layer and the
;;; private native scope.
;;;
;;; This library exists so the constant has exactly ONE definition. options.sls
;;; must not import scope.sls (which would load the shared object and destroy
;;; the property that the options suite runs with no native code), and
;;; duplicating the value in both would let the two drift silently. Removing
;;; the invariant beats asserting it.
(library (cmark gfm private limits)
  (export default-max-input-bytes)
  (import (rnrs))

  ;; design spec 5.5: the only pre-allocation defence. 5 MiB comfortably
  ;; covers real Markdown while still bounding the UTF-8 bytevector that
  ;; validate-markdown-input allocates.
  (define default-max-input-bytes (* 5 1024 1024)))
