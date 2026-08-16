;; Stage 0 spike: attach all five GFM extensions, parse, traverse, free.
;; Usage: chez --script spike/02-parse.ss /abs/core.dylib /abs/extensions.dylib
;;
;; NOTE: every definition below sits at TOP LEVEL, not inside a `let`. Chez
;; rejects a `define` that follows an expression within a body ("invalid
;; context for definition"); at top level the interleaving is legal, and the
;; shared objects still load before any foreign-procedure is evaluated.

(define core (cadr (command-line)))
(define exts (caddr (command-line)))
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
(define first-child   (foreign-procedure "cmark_node_first_child" (uptr) uptr))
(define node-next     (foreign-procedure "cmark_node_next" (uptr) uptr))
(define type-string   (foreign-procedure "cmark_node_get_type_string" (uptr) uptr))

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

(define extension-names '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

;; A document exercising every extension at once.
(define markdown
  (string-append
   "# Heading\n\n"
   "Visit https://example.com for ~~old~~ new info.\n\n"
   "| Fruit | Qty |\n|---|---:|\n| apple | 3 |\n\n"
   "- [x] done\n- [ ] pending\n\n"
   "<script>alert(1)</script>\n"))

(ensure-registered)

(define p (parser-new 0))

;; Attach every extension, failing loudly if any is missing.
(for-each
 (lambda (name)
   (let ((ext (find-extension name)))
     (when (zero? ext)
       (error 'spike "extension not found" name))
     (let ((rc (attach-extension p ext)))
       (printf "attach ~a -> rc=~d\n" name rc))))
 extension-names)

(define bytes (string->utf8 markdown))
(parser-feed p bytes (bytevector-length bytes))

(define root (parser-finish p))

;; Depth-first walk printing the type of every node.
(let walk ((node (first-child root)) (depth 0))
  (unless (zero? node)
    (printf "~a~a\n"
            (make-string (* 2 depth) #\space)
            (c-string->string (type-string node)))
    (walk (first-child node) (+ depth 1))
    (walk (node-next node) depth)))

;; Teardown per ADR-0005: root first, parser LAST.
(node-free root)
(parser-free p)
(printf "\nOK: parsed, traversed, freed\n")
