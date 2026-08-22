#!r6rs
;;; Which native library is loaded, and what it can do.
;;;
;;; Run it:
;;;   CHEZSCHEMELIBDIRS=src chez --program examples/06-capabilities.sps
;;;
;;; Prints properties rather than the version string itself: the version is
;;; whatever cmark-gfm this machine has, and a golden file naming it would
;;; break on any machine with a different patch release.
(import (rnrs) (cmark gfm))

(define (line . parts)
  (for-each display parts) (newline))

(line "version is a string:  " (string? (cmark-gfm-version)))
(line "version is non-empty: " (> (string-length (cmark-gfm-version)) 0))
(line "compatible:           " (cmark-gfm-version-compatible?))
(line "available extensions: " (cmark-gfm-available-extensions))
