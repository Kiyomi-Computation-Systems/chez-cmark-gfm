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
  (export default-max-input-bytes default-max-nodes default-max-depth)
  (import (rnrs))

  ;; design spec 5.5: the only pre-allocation defence. 5 MiB comfortably
  ;; covers real Markdown while still bounding the UTF-8 bytevector that
  ;; validate-markdown-input allocates.
  (define default-max-input-bytes (* 5 1024 1024))

  ;; design spec 6.1: max-input-bytes does NOT bound this. Five MiB of
  ;; "*a*\n" repeated parses to millions of nodes, so without a separate
  ;; ceiling the Scheme-side allocation is unbounded even at the input limit.
  ;; 250000 is roughly two orders of magnitude above realistic documents and
  ;; keeps the copied tree in the tens of megabytes.
  (define default-max-nodes 250000)

  ;; What makes recursive traversal safe (design spec 5.1). Chez's stack is
  ;; heap-allocated and segmented, so recursion depth is bounded by memory
  ;; rather than a small frame limit -- but the bound has to be enforced
  ;; rather than assumed, and 1000 is far past any non-adversarial Markdown.
  (define default-max-depth 1000))
