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
;;;
;;; That same property is why the VERSION GATE sits where it does. Because
;;; every `foreign-procedure` below resolves at import, a library that lacks
;;; any one of those symbols aborts the import with a raw
;;;   Exception in foreign-procedure: no entry for "..."
;;; and `ensure-native-loaded!` -- which runs at first USE -- is never
;;; reached, so its version check cannot diagnose what went wrong. Therefore
;;; `cmark_version` is bound ALONE, straight after the loads, and checked
;;; there, before the bulk of the bindings are created. These run in this
;;; order and none of them may move:
;;;   resolved-libraries -> the two loads -> cmark_version ->
;;;   the supported-range check -> everything else.
;;; NOTE what this does and does not buy. It converts an out-of-RANGE library
;;; into &cmark-version-incompatible on both resolution paths. It cannot help
;;; a library that is IN range but missing a symbol bound below: that still
;;; dies raw, at whichever definition it cannot satisfy. Keeping
;;; cmark-supported-version-range honest about the symbols actually bound here
;;; is a review obligation, not something this gate enforces (design spec 3.8
;;; is the worked example).
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
  ;; file-exists? is deliberately absent from this import: (rnrs) already
  ;; exports it (via (rnrs files)), so also importing it from (chezscheme)
  ;; raises "multiple definitions for file-exists? in body" -- the same
  ;; conflict class already documented for `exit` (Task 8).
  (import (rnrs)
          (only (chezscheme)
                load-shared-object foreign-procedure foreign-ref foreign-sizeof
                file-regular? file-directory? directory-list
                make-mutex with-mutex getenv)
          (cmark gfm private discovery)
          (cmark gfm private conditions))

  ;; --- library resolution ------------------------------------------------
  ;; Fixes cmark's major/minor at 0.29 and leaves the patch and gfm-patch
  ;; numbers free. A runtime library outside this range raises
  ;; &cmark-version-incompatible before any parse happens.
  (define cmark-supported-version-range '(#x001d0000 . #x001dffff))

  ;; ABSOLUTE PATHS ONLY, NEVER LEAFNAMES. `(load-shared-object
  ;; "libcmark-gfm.dylib")` resolves to macOS's own copy in the dyld shared
  ;; cache at /usr/lib/libcmark-gfm.dylib -- a different build, with no headers
  ;; shipped anywhere, that Apple may change on any OS update, and which
  ;; currently reports the same version as the pinned one so nothing would
  ;; notice. Three properties keep it unreachable: it has no filesystem entry,
  ;; its name is unversioned, and there is no extensions library beside it.
  ;; Do not "simplify" this into a soname fallback.
  ;;
  ;; "Existing" alone is not enough: file-exists? is also true of a
  ;; directory, and a directory handed to load-shared-object escapes as a
  ;; raw dlopen error instead of a structured condition. file-regular? is
  ;; what rules a directory out, so do not simplify this into file-exists?
  ;; alone.
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

  ;; These two are DEFINITIONS, not expressions, so they run before every
  ;; foreign-procedure definition below -- see the ORDERING NOTE at the top of
  ;; this file. Core before extensions: on Linux the symbols of a dlopen'd
  ;; library's dependencies are not placed in the global namespace, so the
  ;; extensions library must find an already-loaded core.
  (define core-loaded (load-library (car resolved-libraries)))
  (define extensions-loaded (load-library (cdr resolved-libraries)))

  ;; --- version, straight from the library, and the gate it feeds --------
  ;; ALONE here, ahead of every other foreign-procedure in this body: see the
  ;; ORDERING NOTE at the top of the file for why the position is load-bearing
  ;; rather than stylistic.
  (define cmark-runtime-version (foreign-procedure "cmark_version" () int))

  (define (version-supported? runtime)
    (let ((lo (car cmark-supported-version-range))
          (hi (cdr cmark-supported-version-range)))
      (and (>= runtime lo) (<= runtime hi))))

  ;; There is no compile step any more, so there is no compiled-vs-runtime skew
  ;; to detect: the only question is whether the library we loaded is one this
  ;; binding supports. version-compatible? is retained as a one-argument alias
  ;; so callers and tests keep a single name for the question.
  (define (version-compatible? runtime) (version-supported? runtime))

  ;; A DEFINITION, not a bare expression, for the same R6RS reason the two
  ;; loads above are definitions: a library body may not place an expression
  ;; among the definitions that follow it. The bound value is never read --
  ;; binding it is only what lets the check occupy this exact position -- so
  ;; do not "tidy" it into a bare `(unless (version-supported? ...) (raise ...))`.
  ;;
  ;; This is the check that makes &cmark-version-incompatible reachable at all
  ;; for an unsupported library. It fires on BOTH resolution paths, including
  ;; the CHEZ_CMARK_GFM_LIBS override, where discovery does no filename
  ;; version parsing whatsoever (discovery.sls's parse-library-override).
  (define version-checked
    (let ((runtime (cmark-runtime-version)))
      (if (version-supported? runtime)
          runtime
          (raise (make-cmark-version-incompatible
                  cmark-supported-version-range runtime)))))

  ;; --- buffer release through cmark's own allocator ---------------------
  ;; cmark_get_default_mem_allocator returns a pointer to
  ;; struct cmark_mem { calloc; realloc; free; } -- three function pointers in
  ;; that order. The third is the ONLY correct way to release a renderer
  ;; buffer; libc free() is not equivalent and cmark's own header says so.
  ;;
  ;; Chez accepts an integer address where a name string normally goes, which
  ;; is what makes calling through a struct member possible at all. The offset
  ;; is an ABI assumption, checked by tests/test-native.sps "allocator exposes
  ;; three distinct non-null function pointers".
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

  ;; --- tasklist checked state -------------------------------------------
  ;; `unsigned-8`, not `int`: the entry point returns C _Bool, which occupies
  ;; only the low byte of the return register with the upper bits unspecified.
  ;; Declaring `int` would read whatever happens to be there. This is the job
  ;; a C wrapper used to do, done by the type declaration instead.
  (define raw-tasklist-checked
    (foreign-procedure "cmark_gfm_extensions_get_tasklist_item_checked"
                       (uptr) unsigned-8))

  (define (tasklist-checked node) (not (zero? (raw-tasklist-checked node))))

  ;; --- allocation counters ----------------------------------------------
  ;; Always on. Three fixnum increments per document is not a cost worth a
  ;; build mode, and the C versions existed only so a prod build could compile
  ;; them out -- which is what `make prod` and the flavor machinery were for.
  ;; These count acquisitions THIS library makes; they were never a measure of
  ;; the C heap. tests/test-lifecycle.sps reads them to prove pairing.
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

  ;; --- Stage 3: node accessors ------------------------------------------
  ;; Every `const char *` return is declared uptr and copied by
  ;; c-string->string at the call site, per the Stage 1 rule: the
  ;; conservative form does not depend on marshalling behaviour, and it keeps
  ;; NULL distinguishable from "". Several of these accessors return NULL for
  ;; a node of an incompatible type, so that distinction carries meaning.
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

  ;; --- extension accessors ----------------------------------------------
  ;; These live in libcmark-gfm-extensions. They resolve only because
  ;; extensions-loaded above loads that shared object explicitly, after the
  ;; core: on Linux a dlopened library's dependencies are not placed in the
  ;; global symbol namespace, so a missing explicit load fails HERE, at import
  ;; time, and only on Linux.
  ;;
  ;; table-columns and table-alignments dereference node->type with no NULL
  ;; guard (vendor/cmark-gfm/extensions/table.c:878-890), so a caller must
  ;; have confirmed the node is a table first. convert.sls calls them only
  ;; from inside the "table" branch of its dispatch table, which makes that
  ;; structural rather than a documented promise.
  (define table-columns
    (foreign-procedure "cmark_gfm_extensions_get_table_columns" (uptr) unsigned-16))
  (define table-alignments
    (foreign-procedure "cmark_gfm_extensions_get_table_alignments" (uptr) uptr))
  (define table-row-is-header
    (foreign-procedure "cmark_gfm_extensions_get_table_row_is_header" (uptr) int))

  ;; Copies `count` bytes out of a borrowed uint8_t array. Kept here rather
  ;; than in convert.sls so foreign-ref appears in exactly one library. A NULL
  ;; array yields all zeros -- "no alignment set" -- instead of faulting.
  (define (alignment-bytes addr count)
    (let loop ((i (- count 1)) (acc (quote ())))
      (cond
        ((negative? i) acc)
        ((zero? addr) (loop (- i 1) (cons 0 acc)))
        (else (loop (- i 1)
                    (cons (foreign-ref (quote unsigned-8) addr i) acc))))))

  ;; --- one-time version check and extension registration ----------------
  ;; Chez here is threaded (tarm64osx) and
  ;; cmark_gfm_core_extensions_ensure_registered mutates a global registry,
  ;; so this is serialised. The mutex lives in Scheme rather than C
  ;; deliberately: a C mutex would need pthreads, and POSIX-only APIs are
  ;; barred so Windows stays reachable later (ADR-0004).
  (define init-mutex (make-mutex))
  (define initialized? #f)

  ;; The version check below is the SECOND one, not the primary gate: the
  ;; library body already refused an out-of-range library at instantiation
  ;; (version-checked, above), so any caller that gets this far has already
  ;; passed. Under that ordering this one cannot fire -- same library, same
  ;; constant, same answer -- and it is kept anyway, deliberately: it costs one
  ;; foreign call once per process behind a mutex that is taken regardless, and
  ;; it keeps the invariant attached to the procedure the public API actually
  ;; calls instead of resting entirely on this body's statement order. What it
  ;; must NOT be mistaken for is coverage: it is not what diagnoses an
  ;; unsupported library, and it never was -- that is version-checked's job.
  (define (ensure-native-loaded!)
    (with-mutex init-mutex
      (unless initialized?
        (let ((runtime (cmark-runtime-version)))
          (unless (version-supported? runtime)
            (raise (make-cmark-version-incompatible
                    cmark-supported-version-range runtime))))
        (ensure-extensions-registered)
        (set! initialized? #t))))

  ;; cmark's option bits, transcribed from vendor/cmark-gfm/src/cmark-gfm.h.
  ;; tests/test-option-bits.sps asserts every one of these against that header;
  ;; five of the six are additionally covered behaviourally by
  ;; tests/test-differential.sps. Do not "tidy" these into a sequence -- the
  ;; values are not contiguous (UNSAFE is bit 17, not bit 5).
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
