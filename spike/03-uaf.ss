;; Stage 0 spike: demonstrate the ADR-0005 use-after-free.
;;
;; cmark_parser_free() calls cmark_llist_free() on parser->syntax_extensions,
;; which is the SAME list cmark_render_html() receives. Freeing the parser
;; before rendering therefore hands the renderer a dangling list.
;;
;; Usage: chez --script spike/03-uaf.ss <core.dylib> <ext.dylib> [buggy|correct]
;;
;; NOTE: every definition below sits at TOP LEVEL, not inside a `let`. Chez
;; rejects a `define` that follows an expression within a body ("invalid
;; context for definition"); at top level the interleaving is legal, and the
;; shared objects still load before any foreign-procedure is evaluated.

(define core (cadr (command-line)))
(define exts (caddr (command-line)))
(define mode (string->symbol (cadddr (command-line))))
(load-shared-object core)
(load-shared-object exts)

(define ensure-registered
  (foreign-procedure "cmark_gfm_core_extensions_ensure_registered" () void))
(define find-extension
  (foreign-procedure "cmark_find_syntax_extension" (string) uptr))
(define attach-extension
  (foreign-procedure "cmark_parser_attach_syntax_extension" (uptr uptr) int))
(define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
(define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
(define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
(define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
(define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
(define get-extensions
  (foreign-procedure "cmark_parser_get_syntax_extensions" (uptr) uptr))
(define render-html
  (foreign-procedure "cmark_render_html" (uptr int uptr) uptr))
(define c-free (foreign-procedure "free" (uptr) void))

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

;; A table forces the renderer to consult the extension list.
(define markdown "| a | b |\n|---|---|\n| 1 | 2 |\n")

(ensure-registered)

(define p (parser-new 0))

(define table-ext (find-extension "table"))
(when (zero? table-ext) (error 'spike "table extension missing"))
(attach-extension p table-ext)

(define bytes (string->utf8 markdown))
(parser-feed p bytes (bytevector-length bytes))

(define root (parser-finish p))
(define ext-list (get-extensions p))

(case mode
  ((buggy)
   ;; WRONG: this is plan 8.2's ordering. ext-list now dangles.
   (parser-free p)
   (let ((buf (render-html root 0 ext-list)))
     (printf "~a" (c-string->string buf))
     (c-free buf))
   (node-free root))
  ((correct)
   ;; RIGHT: parser outlives the render (ADR-0005).
   (let ((buf (render-html root 0 ext-list)))
     (printf "~a" (c-string->string buf))
     (c-free buf))
   (node-free root)
   (parser-free p))
  (else (error 'spike "mode must be buggy or correct")))

(printf "done: ~a\n" mode)
