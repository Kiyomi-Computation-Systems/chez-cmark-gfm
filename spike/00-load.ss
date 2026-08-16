;; Stage 0 spike: prove load-shared-object and version reporting.
;; Usage: chez --script spike/00-load.ss /abs/path/to/libcmark-gfm.dylib;;
;; NOTE: every definition below sits at TOP LEVEL, not inside a `let`. Chez
;; rejects a `define` that follows an expression within a body ("invalid
;; context for definition"); at top level the interleaving is legal, and the
;; shared object still loads before any foreign-procedure is evaluated.

(define lib (cadr (command-line)))
(load-shared-object lib)

(define cmark-version
  (foreign-procedure "cmark_version" () int))
(define cmark-version-string
  (foreign-procedure "cmark_version_string" () string))

(define v (cmark-version))

(printf "cmark_version()        = ~d (0x~x)\n" v v)
(printf "cmark_version_string() = ~a\n" (cmark-version-string))
;; CMARK_GFM_VERSION packs FOUR bytes, not three:
;;   (major << 24) | (minor << 16) | (patch << 8) | gfm
;; For 0.29.0.gfm.13 that is 0x001D000D. Decoding it as a three-field
;; version yields a misleading "29.0.13".
(printf "decoded                = ~d.~d.~d.gfm.~d\n"
        (bitwise-arithmetic-shift-right v 24)
        (bitwise-and (bitwise-arithmetic-shift-right v 16) #xff)
        (bitwise-and (bitwise-arithmetic-shift-right v 8) #xff)
        (bitwise-and v #xff))
