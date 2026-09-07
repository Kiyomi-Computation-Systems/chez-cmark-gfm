#!r6rs
;;; Private FFI layer and the only library allowed to hold native pointers.
;;;
;;; Chez resolves foreign-procedure entry points when their definitions are
;;; evaluated. Preserve this order: resolve paths, load core then extensions,
;;; bind cmark_version, enforce the version range, then bind everything else.
;;; Missing symbols within the accepted range still fail at import except for
;;; raw-tasklist-checked, whose known compatibility hole is guarded.
(library (cmark gfm private native)
  (export ensure-native-loaded!
          version-supported? version-compatible?
          resolve-cmark-libraries cmark-supported-version-range
          resolved-libraries
          c-string->string
          option-bits
          cmark-opt-default cmark-opt-sourcepos cmark-opt-hardbreaks
          cmark-opt-nobreaks cmark-opt-validate-utf8 cmark-opt-smart
          cmark-opt-unsafe
          live-counts
          count-parser-new! count-parser-free!
          count-root-new!   count-root-free!
          count-buffer-new! count-buffer-free!
          parser-new parser-feed parser-finish parser-free
          node-free find-extension attach-extension
          parser-get-syntax-extensions render-html free-buffer
          allocator-slots
          runtime-version-string cmark-runtime-version
          render-xml render-commonmark render-plaintext
          node-first-child node-next node-type-string node-literal
          node-heading-level node-list-type node-list-delim node-list-start
          node-list-tight node-fence-info
          node-url node-title
          node-start-line node-start-column node-end-line node-end-column
          table-columns table-alignments table-row-is-header tasklist-checked
          alignment-bytes)
  ;; (rnrs) already exports file-exists?; importing Chez's copy conflicts.
  (import (rnrs)
          (only (chezscheme)
                load-shared-object foreign-procedure foreign-ref foreign-sizeof
                file-regular? file-directory? directory-list
                make-mutex with-mutex getenv)
          (cmark gfm private discovery)
          (cmark gfm private conditions))

  ;; Fixes cmark's major/minor at 0.29 and leaves the patch and gfm-patch
  ;; numbers free. A runtime library outside this range raises
  ;; &cmark-version-incompatible before any parse happens.
  (define cmark-supported-version-range '(#x001d0000 . #x001dffff))

  ;; Load absolute paths only. A leafname on macOS can resolve to Apple's
  ;; unrelated dyld-cache copy. Require a regular file because file-exists?
  ;; also accepts directories, which would leak a raw dlopen error.
  (define (regular-file? path)
    (and (file-exists? path) (file-regular? path)))

  (define (resolve-cmark-libraries override)
    (if override
        (let-values (((status payload) (parse-library-override override regular-file?)))
          (if (eq? status 'ok)
              payload
              (raise (make-cmark-library-unavailable override 'invalid-override))))
        (let* ((platform (current-platform))
               (candidates (default-candidate-directories
                             platform (current-machine) directory-names directory?)))
          (let-values (((status payload)
                        (select-cmark-libraries directory-names directory?
                                                candidates
                                                cmark-supported-version-range
                                                platform)))
            (cond
              ((eq? status 'found) payload)
              ((eq? status 'out-of-range)
               (raise (make-cmark-version-incompatible
                       cmark-supported-version-range payload)))
              (else
               (raise (make-cmark-library-unavailable #f 'not-found))))))))

  ;; directory-list yields names; some Chez versions yield (name . type) pairs.
  (define (directory-names dir)
    (map (lambda (entry) (if (pair? entry) (car entry) entry))
         (directory-list dir)))

  (define (directory? path) (file-directory? path))

  (define (load-library path)
    (guard (e (#t (raise (make-cmark-library-unavailable path 'load-failed))))
      (load-shared-object path)))

  (define resolved-libraries
    (resolve-cmark-libraries (getenv "CHEZ_CMARK_GFM_LIBS")))

  ;; Definitions preserve evaluation order. Load core first so the extensions
  ;; library can resolve it from Linux's global symbol namespace.
  (define core-loaded (load-library (car resolved-libraries)))
  (define extensions-loaded (load-library (cdr resolved-libraries)))

  ;; Keep this as the only binding before the version gate.
  (define cmark-runtime-version (foreign-procedure "cmark_version" () int))

  (define (version-supported? runtime)
    (let ((lo (car cmark-supported-version-range))
          (hi (cdr cmark-supported-version-range)))
      (and (>= runtime lo) (<= runtime hi))))

  (define (version-compatible? runtime) (version-supported? runtime))

  ;; R6RS library bodies cannot put an expression before later definitions, so
  ;; this load-bearing gate must itself be a definition. It also checks explicit
  ;; overrides, whose filenames are not version-parsed.
  (define version-checked
    (let ((runtime (cmark-runtime-version)))
      (if (version-supported? runtime)
          runtime
          (raise (make-cmark-version-incompatible
                  cmark-supported-version-range runtime)))))

  ;; cmark_mem stores calloc, realloc, and free in that order. Renderer buffers
  ;; must use the third pointer; libc free is not interchangeable. Chez accepts
  ;; that integer address as a foreign-procedure entry point.
  (define default-mem-allocator
    (foreign-procedure "cmark_get_default_mem_allocator" () uptr))

  (define (allocator-slots)
    (let ((mem (default-mem-allocator))
          (w (foreign-sizeof 'void*)))
      (list (foreign-ref 'uptr mem 0)
            (foreign-ref 'uptr mem w)
            (foreign-ref 'uptr mem (* 2 w)))))

  (define free-buffer
    (foreign-procedure (caddr (allocator-slots)) (uptr) void))

  ;; unsigned-8, not int: the entry point returns C _Bool, which occupies
  ;; only the low byte of the return register with the upper bits unspecified.
  ;; Declaring int would read unspecified bits.
  ;;
  ;; Probe this symbol rather than inferring it from cmark_version: distributions
  ;; backport it independently. Guard evaluation to turn a missing entry point
  ;; into a structured error naming the extensions library.
  (define raw-tasklist-checked
    (guard (e (#t (raise (make-cmark-library-unavailable
                          (cdr resolved-libraries) 'missing-entry-point))))
      (foreign-procedure "cmark_gfm_extensions_get_tasklist_item_checked"
                         (uptr) unsigned-8)))

  (define (tasklist-checked node) (not (zero? (raw-tasklist-checked node))))

  ;; Count this library's acquisitions, not total C-heap allocations.
  (define live-parser-count 0)
  (define live-root-count 0)
  (define live-buffer-count 0)

  (define (count-parser-new!)  (set! live-parser-count (+ live-parser-count 1)))
  (define (count-parser-free!) (set! live-parser-count (- live-parser-count 1)))
  (define (count-root-new!)    (set! live-root-count   (+ live-root-count 1)))
  (define (count-root-free!)   (set! live-root-count   (- live-root-count 1)))
  (define (count-buffer-new!)  (set! live-buffer-count (+ live-buffer-count 1)))
  (define (count-buffer-free!) (set! live-buffer-count (- live-buffer-count 1)))

  (define (live-counts)
    (list live-parser-count live-root-count live-buffer-count))

  ;; Accessors returning `const char *` are declared `uptr`, not `string`,
  ;; then copied explicitly so NULL remains distinguishable from "".
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
  ;; Static cmark-owned string; copy it immediately.
  (define raw-version-string
    (foreign-procedure "cmark_version_string" () uptr))

  ;; Several string accessors return NULL for incompatible node types; keep
  ;; them as uptr and copy at the call site.
  (define node-first-child
    (foreign-procedure "cmark_node_first_child" (uptr) uptr))
  (define node-next     (foreign-procedure "cmark_node_next" (uptr) uptr))
  (define node-type-string
    (foreign-procedure "cmark_node_get_type_string" (uptr) uptr))
  (define node-literal  (foreign-procedure "cmark_node_get_literal" (uptr) uptr))
  (define node-fence-info
    (foreign-procedure "cmark_node_get_fence_info" (uptr) uptr))
  (define node-url      (foreign-procedure "cmark_node_get_url" (uptr) uptr))
  (define node-title    (foreign-procedure "cmark_node_get_title" (uptr) uptr))

  (define node-heading-level
    (foreign-procedure "cmark_node_get_heading_level" (uptr) int))
  (define node-list-type
    (foreign-procedure "cmark_node_get_list_type" (uptr) int))
  (define node-list-delim
    (foreign-procedure "cmark_node_get_list_delim" (uptr) int))
  (define node-list-start
    (foreign-procedure "cmark_node_get_list_start" (uptr) int))
  (define node-list-tight
    (foreign-procedure "cmark_node_get_list_tight" (uptr) int))
  (define node-start-line
    (foreign-procedure "cmark_node_get_start_line" (uptr) int))
  (define node-start-column
    (foreign-procedure "cmark_node_get_start_column" (uptr) int))
  (define node-end-line
    (foreign-procedure "cmark_node_get_end_line" (uptr) int))
  (define node-end-column
    (foreign-procedure "cmark_node_get_end_column" (uptr) int))

  ;; These live in libcmark-gfm-extensions. They resolve only because
  ;; extensions-loaded explicitly loads it after core on Linux.
  ;;
  ;; table-columns and table-alignments dereference node->type with no NULL
  ;; guard, so call them only after confirming the node is a table.
  (define table-columns
    (foreign-procedure "cmark_gfm_extensions_get_table_columns" (uptr) unsigned-16))
  (define table-alignments
    (foreign-procedure "cmark_gfm_extensions_get_table_alignments" (uptr) uptr))
  (define table-row-is-header
    (foreign-procedure "cmark_gfm_extensions_get_table_row_is_header" (uptr) int))

  ;; Copy a borrowed uint8_t array. NULL means no alignments, represented by
  ;; zero bytes.
  (define (alignment-bytes addr count)
    (let loop ((i (- count 1)) (acc (quote ())))
      (cond
        ((negative? i) acc)
        ((zero? addr) (loop (- i 1) (cons 0 acc)))
        (else (loop (- i 1)
                    (cons (foreign-ref (quote unsigned-8) addr i) acc))))))

  ;; Extension registration mutates global state; serialize it. A Scheme mutex
  ;; avoids a POSIX-only native dependency.
  (define init-mutex (make-mutex))
  (define initialized? #f)

  ;; version-checked is the import-time gate; repeat the invariant at the
  ;; public initialization boundary before mutating the registry.
  (define (ensure-native-loaded!)
    (with-mutex init-mutex
      (unless initialized?
        (let ((runtime (cmark-runtime-version)))
          (unless (version-supported? runtime)
            (raise (make-cmark-version-incompatible
                    cmark-supported-version-range runtime))))
        (ensure-extensions-registered)
        (set! initialized? #t))))

  ;; Values from cmark-gfm.h are not contiguous; UNSAFE is bit 17.
  (define cmark-opt-default       0)
  (define cmark-opt-sourcepos     (bitwise-arithmetic-shift-left 1 1))
  (define cmark-opt-hardbreaks    (bitwise-arithmetic-shift-left 1 2))
  (define cmark-opt-nobreaks      (bitwise-arithmetic-shift-left 1 4))
  (define cmark-opt-validate-utf8 (bitwise-arithmetic-shift-left 1 9))
  (define cmark-opt-smart         (bitwise-arithmetic-shift-left 1 10))
  (define cmark-opt-unsafe        (bitwise-arithmetic-shift-left 1 17))

  (define (option-bits validate-utf8? sourcepos? hardbreaks?
                       nobreaks? smart? unsafe-html?)
    (let ((add (lambda (acc on? bit) (if on? (bitwise-ior acc bit) acc))))
      (add (add (add (add (add (add cmark-opt-default
                                    validate-utf8? cmark-opt-validate-utf8)
                               sourcepos?    cmark-opt-sourcepos)
                          hardbreaks?   cmark-opt-hardbreaks)
                     nobreaks?     cmark-opt-nobreaks)
                smart?        cmark-opt-smart)
           unsafe-html?  cmark-opt-unsafe)))

  (define (runtime-version-string) (c-string->string (raw-version-string)))

  ;; Copies immediately into Scheme-owned storage. NULL becomes #f, which is
  ;; distinct from "" because incompatible-node accessors can return NULL.
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
