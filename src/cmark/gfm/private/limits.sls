#!r6rs
;;; Pure resource limits shared by options and the native scope. Keep them here
;;; so the options import graph remains free of native code.
(library (cmark gfm private limits)
  (export default-max-input-bytes default-max-nodes default-max-depth)
  (import (rnrs))

  ;; Bounds the UTF-8 bytevector allocated before native parsing.
  (define default-max-input-bytes (* 5 1024 1024))

  ;; Input bytes do not bound node count: compact Markdown can produce millions
  ;; of Scheme objects.
  (define default-max-nodes 250000)

  ;; Bounds recursive traversal independently of input size and node count.
  (define default-max-depth 1000))
