#!r6rs
;;; Private FFI layer. This is the ONLY library permitted to hold a native
;;; pointer (design spec 4.1). Nothing here is a supported public API.
;;;
;;; ORDERING NOTE -- this is the subtle part of the file. Chez resolves a
;;; foreign entry point when the `foreign-procedure` expression is
;;; EVALUATED, not when the resulting procedure is first called. Every such
;;; definition below therefore has to run after the shared object is loaded.
;;; Library bodies evaluate their definitions in order, so the load is
;;; written as a definition placed ahead of them. Moving it later fails at
;;; IMPORT time with an unresolved-entry error, not at first use.
(library (cmark gfm private native)
  (export ensure-native-loaded!
          c-string->string
          option-bits
          live-counts
          count-parser-new! count-parser-free!
          count-root-new!   count-root-free!
          count-buffer-new! count-buffer-free!
          parser-new parser-feed parser-finish parser-free
          node-free find-extension attach-extension
          parser-get-syntax-extensions render-html free-buffer)
  ;; file-exists? is deliberately absent from this import: (rnrs) already
  ;; exports it (via (rnrs files)), so also importing it from (chezscheme)
  ;; raises "multiple definitions for file-exists? in body" -- the same
  ;; conflict class already documented for `exit` (Task 8).
  (import (rnrs)
          (only (chezscheme)
                load-shared-object foreign-procedure foreign-ref
                make-mutex with-mutex getenv)
          (cmark gfm private config)
          (cmark gfm private conditions))

  ;; --- shim resolution --------------------------------------------------
  ;; The override exists because config-in-the-environment is 12-factor. It
  ;; is validated, never searched: an absolute path to an existing regular
  ;; file, or nothing at all. There is no fallback search and the working
  ;; directory is never consulted (design spec 6.2).
  (define shim-file
    (let ((override (getenv "CHEZ_CMARK_GFM_SHIM")))
      (cond
        ((not override)
         (if (file-exists? shim-path)
             shim-path
             (raise (make-cmark-shim-unavailable shim-path))))
        ((and (> (string-length override) 0)
              (char=? (string-ref override 0) #\/)
              (file-exists? override))
         override)
        (else (raise (make-cmark-shim-unavailable override))))))

  ;; A definition, not a bare expression, so it is legal at this position in
  ;; an R6RS library body while still running before every binding below.
  (define shim-loaded (load-shared-object shim-file))

  ;; --- shim bindings ----------------------------------------------------
  (define shim-compiled-version
    (foreign-procedure "chez_cmark_shim_compiled_version" () int))
  (define shim-runtime-version
    (foreign-procedure "chez_cmark_runtime_version" () int))
  (define raw-option-bits
    (foreign-procedure "chez_cmark_option_bits" (int int int int int int) int))
  (define free-buffer
    (foreign-procedure "chez_cmark_free_buffer" (uptr) void))

  (define count-parser-new!
    (foreign-procedure "chez_cmark_count_parser_new" () void))
  (define count-parser-free!
    (foreign-procedure "chez_cmark_count_parser_free" () void))
  (define count-root-new!
    (foreign-procedure "chez_cmark_count_root_new" () void))
  (define count-root-free!
    (foreign-procedure "chez_cmark_count_root_free" () void))
  (define count-buffer-new!
    (foreign-procedure "chez_cmark_count_buffer_new" () void))
  (define count-buffer-free!
    (foreign-procedure "chez_cmark_count_buffer_free" () void))

  (define live-parsers (foreign-procedure "chez_cmark_live_parsers" () long))
  (define live-roots   (foreign-procedure "chez_cmark_live_roots" () long))
  (define live-buffers (foreign-procedure "chez_cmark_live_buffers" () long))

  ;; --- cmark bindings ---------------------------------------------------
  ;; Accessors returning `const char *` are declared `uptr`, not `string`,
  ;; and copied explicitly by c-string->string below. See design spec 5.4:
  ;; the conservative form does not depend on marshalling behaviour, and it
  ;; keeps NULL distinguishable from "".
  (define ensure-extensions-registered
    (foreign-procedure "cmark_gfm_core_extensions_ensure_registered" () void))
  (define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
  (define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
  (define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
  (define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
  (define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
  (define find-extension
    (foreign-procedure "cmark_find_syntax_extension" (string) uptr))
  (define attach-extension
    (foreign-procedure "cmark_parser_attach_syntax_extension" (uptr uptr) int))
  (define parser-get-syntax-extensions
    (foreign-procedure "cmark_parser_get_syntax_extensions" (uptr) uptr))
  (define render-html
    (foreign-procedure "cmark_render_html" (uptr int uptr) uptr))

  ;; --- one-time version check and extension registration ----------------
  ;; Chez here is threaded (tarm64osx) and
  ;; cmark_gfm_core_extensions_ensure_registered mutates a global registry,
  ;; so this is serialised. The mutex lives in Scheme rather than C
  ;; deliberately: a C mutex would need pthreads, and POSIX-only APIs are
  ;; barred so Windows stays reachable later (ADR-0004).
  (define init-mutex (make-mutex))
  (define initialized? #f)

  (define (version-supported? runtime)
    (let ((lo (car cmark-supported-version-range))
          (hi (cdr cmark-supported-version-range)))
      (and (>= runtime lo) (<= runtime hi))))

  ;; Idempotent. Fails closed on an out-of-range runtime version.
  (define (ensure-native-loaded!)
    (with-mutex init-mutex
      (unless initialized?
        (let ((compiled (shim-compiled-version))
              (runtime  (shim-runtime-version)))
          (unless (version-supported? runtime)
            (raise (make-cmark-version-incompatible compiled runtime))))
        (ensure-extensions-registered)
        (set! initialized? #t))))

  (define (live-counts)
    (list (live-parsers) (live-roots) (live-buffers)))

  (define (bool->int x) (if x 1 0))

  (define (option-bits validate-utf8? sourcepos? hardbreaks?
                       nobreaks? smart? unsafe-html?)
    (raw-option-bits (bool->int validate-utf8?)
                     (bool->int sourcepos?)
                     (bool->int hardbreaks?)
                     (bool->int nobreaks?)
                     (bool->int smart?)
                     (bool->int unsafe-html?)))

  ;; --- borrowed string copying ------------------------------------------
  ;; Copies immediately into Scheme-owned storage. NULL becomes #f, which is
  ;; deliberately distinct from "": several cmark accessors return NULL when
  ;; called on a node of an incompatible type, and conflating the two would
  ;; invent data that was never in the document.
  (define (c-string->string addr)
    (if (zero? addr)
        #f
        (let scan ((len 0))
          (if (zero? (foreign-ref (quote unsigned-8) addr len))
              (let ((bv (make-bytevector len)))
                (let copy ((i 0))
                  (if (= i len)
                      (utf8->string bv)
                      (begin
                        (bytevector-u8-set! bv i (foreign-ref (quote unsigned-8) addr i))
                        (copy (+ i 1))))))
              (scan (+ len 1)))))))
