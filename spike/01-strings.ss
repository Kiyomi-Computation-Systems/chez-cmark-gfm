;; Stage 0 spike: determine how Chez marshals `const char *` returns.
;; Three questions:
;;   (a) does the `string` return type COPY, or alias native memory?
;;   (b) does it decode UTF-8 correctly?
;;   (c) what happens when the C function returns NULL?
;; Usage: chez --script spike/01-strings.ss /abs/path/to/libcmark-gfm.dylib
;;
;; NOTE: every definition below sits at TOP LEVEL, not inside a `let`. Chez
;; rejects a `define` that follows an expression within a body ("invalid
;; context for definition"); at top level the interleaving is legal, and the
;; shared object still loads before any foreign-procedure is evaluated.

(define lib (cadr (command-line)))
(load-shared-object lib)

;; --- helpers -------------------------------------------------------
;; Manual, unambiguous copy from a raw address. This is the fallback
;; the design specifies (spec 5.4) if `string` proves unsafe.
(define (c-string->string addr)
  (if (zero? addr)
      #f
      (let scan ((len 0))
        (if (zero? (foreign-ref 'unsigned-8 addr len))
            (let ((bv (make-bytevector len)))
              (let copy ((i 0))
                (if (= i len)
                    (utf8->string bv)
                    (begin
                      (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 addr i))
                      (copy (+ i 1))))))
            (scan (+ len 1))))))

;; --- bindings ------------------------------------------------------
(define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
(define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
(define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
(define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
(define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
(define first-child   (foreign-procedure "cmark_node_first_child" (uptr) uptr))

;; The SAME accessor bound two ways, so the results can be compared.
(define literal-as-string (foreign-procedure "cmark_node_get_literal" (uptr) string))
(define literal-as-uptr   (foreign-procedure "cmark_node_get_literal" (uptr) uptr))
;; get_literal returns NULL for a paragraph node -- that is question (c).
(define type-as-uptr      (foreign-procedure "cmark_node_get_type_string" (uptr) uptr))

;; --- probe ---------------------------------------------------------
;; Non-ASCII on purpose: em-dash and a CJK character exercise UTF-8.
(define md   (string->utf8 "Hello \x2014;world \x4e16;\x754c;\n"))
(define p    (parser-new 0))
(parser-feed p md (bytevector-length md))
(define root (parser-finish p))
(define para (first-child root))
(define text (first-child para))

(printf "--- (b) UTF-8 decoding ---\n")
(let ((via-string (literal-as-string text))
      (via-uptr   (c-string->string (literal-as-uptr text))))
  (printf "via `string` type : ~s\n" via-string)
  (printf "via manual copy   : ~s\n" via-uptr)
  (printf "identical?        : ~a\n" (equal? via-string via-uptr)))

(printf "\n--- (c) NULL handling ---\n")
;; A paragraph node has no literal; the accessor returns NULL.
(printf "manual copy of NULL : ~s\n" (c-string->string (literal-as-uptr para)))
(printf "`string` type on NULL: ")
(flush-output-port)
(printf "~s\n"
        (guard (e (#t (list 'raised (condition/report-string e))))
          (literal-as-string para)))

(printf "\n--- (a) copy vs alias ---\n")
;; Capture BEFORE the tree is freed, then read AFTER. If `string`
;; copied, the value survives intact. If it aliased, this is a
;; use-after-free and the value is garbage or the process crashes.
(define captured (literal-as-string text))
(define node-type (c-string->string (type-as-uptr text)))
(printf "node type          : ~s\n" node-type)
(parser-free p)
(node-free root)
(collect)
(printf "after free         : ~s\n" captured)
(printf "still correct?     : ~a\n"
        (equal? captured "Hello \x2014;world \x4e16;\x754c;"))
