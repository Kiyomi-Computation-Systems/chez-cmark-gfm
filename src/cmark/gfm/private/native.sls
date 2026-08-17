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
          version-supported? version-compatible?
          resolve-shim-path load-shim
          c-string->string
          option-bits
          live-counts
          count-parser-new! count-parser-free!
          count-root-new!   count-root-free!
          count-buffer-new! count-buffer-free!
          parser-new parser-feed parser-finish parser-free
          node-free find-extension attach-extension
          parser-get-syntax-extensions render-html free-buffer
          runtime-version-string shim-compiled-version shim-runtime-version
          render-xml render-commonmark render-plaintext)
  ;; file-exists? is deliberately absent from this import: (rnrs) already
  ;; exports it (via (rnrs files)), so also importing it from (chezscheme)
  ;; raises "multiple definitions for file-exists? in body" -- the same
  ;; conflict class already documented for `exit` (Task 8).
  (import (rnrs)
          (only (chezscheme)
                load-shared-object foreign-procedure foreign-ref
                file-regular? make-mutex with-mutex getenv)
          (cmark gfm private config)
          (cmark gfm private conditions))

  ;; --- shim resolution --------------------------------------------------
  ;; The override exists because config-in-the-environment is 12-factor. It
  ;; is validated, never searched: an absolute path to an existing regular
  ;; file, or nothing at all. There is no fallback search and the working
  ;; directory is never consulted (design spec 6.2). "Existing" alone is
  ;; not enough: file-exists? is also true of a directory, which would
  ;; otherwise reach load-shared-object directly and escape as a raw
  ;; dlopen error instead of a structured condition -- and the same is
  ;; true of the default, generated path if the built shim is corrupt.
  ;;
  ;; Both steps below (path validation, and wrapping the load itself) are
  ;; ordinary, exported procedures rather than bare expressions, so they
  ;; can be unit-tested directly with synthetic paths from a single
  ;; process. The shim itself still loads exactly once per process either
  ;; way; see tests/test-shim-loading.sps for why the actual default-path
  ;; / override wiring below still needs a subprocess on top of that.
  (define (regular-file? path)
    (and (file-exists? path) (file-regular? path)))

  (define (resolve-shim-path default-path override)
    (cond
      ((not override)
       (if (regular-file? default-path)
           default-path
           (raise (make-cmark-shim-unavailable default-path))))
      ((and (> (string-length override) 0)
            (char=? (string-ref override 0) #\/)
            (regular-file? override))
       override)
      (else (raise (make-cmark-shim-unavailable override)))))

  (define (load-shim path)
    (guard (e (#t (raise (make-cmark-shim-unavailable path))))
      (load-shared-object path)))

  (define shim-file
    (resolve-shim-path shim-path (getenv "CHEZ_CMARK_GFM_SHIM")))

  ;; cmark's own shared objects are loaded EXPLICITLY, and before the shim.
  ;; On Linux the symbols of a dlopen'd library's dependencies are not placed
  ;; in the global namespace, so resolving cmark_* entry points through the
  ;; shim alone fails there -- `no entry for
  ;; "cmark_gfm_core_extensions_ensure_registered"` -- while succeeding on
  ;; macOS, whose loader searches dependencies. CI caught exactly this: green
  ;; on macOS, red on Linux. The Stage 0 spikes loaded both libraries
  ;; explicitly and were right to; this restores that.
  (define cmark-loaded
    (for-each (lambda (path)
                (unless (regular-file? path)
                  (raise (make-cmark-shim-unavailable path)))
                (load-shim path))
              cmark-library-paths))

  ;; A definition, not a bare expression, so it is legal at this position in
  ;; an R6RS library body while still running before every binding below.
  (define shim-loaded (load-shim shim-file))

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
  (define render-xml
    (foreign-procedure "cmark_render_xml" (uptr int) uptr))
  (define render-commonmark
    (foreign-procedure "cmark_render_commonmark" (uptr int int) uptr))
  (define render-plaintext
    (foreign-procedure "cmark_render_plaintext" (uptr int int) uptr))
  ;; Returns a static const char* owned by cmark. Borrowed like every other
  ;; accessor here, so it is declared uptr and copied immediately.
  (define raw-version-string
    (foreign-procedure "cmark_version_string" () uptr))

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

  ;; design spec 6.3: initialisation compares the version the shim was
  ;; COMPILED against to the version cmark_version() reports at RUNTIME. In
  ;; an ordinary build these are identical -- the shim links directly
  ;; against the library its own headers came from -- so any mismatch means
  ;; the two have come apart, e.g. a shim built against one cmark-gfm
  ;; checkout now loading a different library's runtime object because it
  ;; was never rebuilt after an in-place library upgrade. The range check
  ;; is kept alongside equality, not replaced by it: a compiled/runtime
  ;; pair that agrees with itself but both predate what this binding
  ;; supports must still be rejected.
  ;; Compatible when BOTH the compile-time and runtime versions fall inside the
  ;; supported range. Deliberately not `(= compiled runtime)`: the range spans
  ;; 0.29.0.gfm.x, so exact equality would reject a runtime the project declares
  ;; supported and force a shim rebuild on every upstream patch release. Checking
  ;; `compiled` too catches a shim built against an unsupported header, which the
  ;; runtime check alone would miss.
  (define (version-compatible? compiled runtime)
    (and (version-supported? compiled)
         (version-supported? runtime)))

  ;; Idempotent. Fails closed on a compiled/runtime mismatch or an
  ;; out-of-range version.
  (define (ensure-native-loaded!)
    (with-mutex init-mutex
      (unless initialized?
        (let ((compiled (shim-compiled-version))
              (runtime  (shim-runtime-version)))
          (unless (version-compatible? compiled runtime)
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

  (define (runtime-version-string) (c-string->string (raw-version-string)))

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
