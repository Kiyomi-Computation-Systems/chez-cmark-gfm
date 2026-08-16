;; Stage 0 spike: prove load-shared-object and version reporting.
;; Usage: chez --script spike/00-load.ss /abs/path/to/libcmark-gfm.dylib

(let ((lib (cadr (command-line))))
  (load-shared-object lib)

  (define cmark-version
    (foreign-procedure "cmark_version" () int))
  (define cmark-version-string
    (foreign-procedure "cmark_version_string" () string))

  (let ((v (cmark-version)))
    (printf "cmark_version()        = ~d (0x~x)\n" v v)
    (printf "cmark_version_string() = ~a\n" (cmark-version-string))
    ;; Version is encoded (major << 16) | (minor << 8) | patch.
    (printf "decoded                = ~d.~d.~d\n"
            (bitwise-arithmetic-shift-right v 16)
            (bitwise-and (bitwise-arithmetic-shift-right v 8) #xff)
            (bitwise-and v #xff))))
