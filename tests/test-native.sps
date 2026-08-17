#!r6rs
(import (rnrs)          ; note: (rnrs) already exports `exit` via
        (srfi :64)      ; (rnrs programs) -- importing it from
        (cmark gfm private native)    ; (chezscheme) too is a conflict
        (cmark gfm private conditions)
        ;; foreign-alloc / foreign-set! / foreign-free build and mutate
        ;; real C buffers for the c-string->string tests below. current-
        ;; directory anchors the synthetic absolute paths used by the
        ;; shim-path-validation tests below. None of these names collide
        ;; with an (rnrs) export, so unlike file-exists? and exit above,
        ;; this import needs no `only` justification beyond keeping the
        ;; list minimal.
        (only (chezscheme) foreign-alloc foreign-set! foreign-free
              current-directory))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "native")

;; This only proves a second call does not raise -- it is NOT a test of
;; the init-mutex/initialized? guard's existence or correctness. Chez here
;; is single-threaded within one process, and the underlying C call
;; (cmark_gfm_core_extensions_ensure_registered) is itself idempotent and
;; safe to invoke repeatedly with no guard at all, so this assertion would
;; pass identically against a native.sls with no guard whatsoever. Genuine
;; discrimination would require a concurrency test (two threads racing
;; ensure-native-loaded!), which is out of reach for a single-threaded
;; SRFI-64 script. Recorded here so a later reader does not mistake this
;; for coverage of the mutex.
(test-assert "repeated ensure-native-loaded! calls do not raise"
  (begin (ensure-native-loaded!) (ensure-native-loaded!) #t))

;; NULL must be distinguishable from the empty string. Several cmark
;; accessors return NULL for nodes of an incompatible type, and conflating
;; that with "" would silently invent data.
(test-equal "c-string->string maps NULL to #f" #f (c-string->string 0))

;; The other direction of the same distinction: a real, non-NULL buffer
;; whose first byte already terminates the string must decode to "", never
;; to #f. Getting this backwards would be just as wrong as the NULL case
;; above -- it would report "this accessor does not apply" for a node that
;; legitimately has an empty value.
(let ((buf (foreign-alloc 1)))
  (foreign-set! 'unsigned-8 buf 0 0)
  (test-equal "c-string->string maps a zero-length buffer to \"\", not #f"
    ""
    (c-string->string buf))
  (foreign-free buf))

;; Multi-byte UTF-8 must decode by codepoint, not by byte. "cafe" with a
;; combining/accented e (U+00E9) encodes as the 5 bytes 63 61 66 C3 A9,
;; followed here by a NUL terminator; the result must be a 4-character
;; Scheme string, not 5 (raw bytes) and not mojibake (wrong codepoint).
;; The expected value is built from integer->char rather than written as a
;; literal so the test does not depend on this source file's own encoding.
(let ((buf (foreign-alloc 6))
      (expected (string #\c #\a #\f (integer->char #xe9))))
  (foreign-set! 'unsigned-8 buf 0 #x63)   ; c
  (foreign-set! 'unsigned-8 buf 1 #x61)   ; a
  (foreign-set! 'unsigned-8 buf 2 #x66)   ; f
  (foreign-set! 'unsigned-8 buf 3 #xc3)   ; UTF-8 lead byte of U+00E9
  (foreign-set! 'unsigned-8 buf 4 #xa9)   ; UTF-8 trail byte of U+00E9
  (foreign-set! 'unsigned-8 buf 5 0)      ; NUL terminator
  (test-equal "c-string->string decodes multi-byte UTF-8 into the right number of characters"
    expected
    (c-string->string buf))
  (foreign-free buf))

;; The single most important property in this file: the conversion must
;; copy, not alias. cmark's accessors return borrowed pointers into
;; buffers whose lifetime the caller does not control; if c-string->string
;; ever returned something that kept reading through the original
;; pointer instead of a self-contained copy, every AST string would be a
;; latent use-after-free.
(let ((buf (foreign-alloc 3)))
  (foreign-set! 'unsigned-8 buf 0 (char->integer #\h))
  (foreign-set! 'unsigned-8 buf 1 (char->integer #\i))
  (foreign-set! 'unsigned-8 buf 2 0)
  (let ((s (c-string->string buf)))
    ;; Mutate the source buffer after conversion. A real copy is already
    ;; fully independent of `buf` by this point, so `s` must not change.
    (foreign-set! 'unsigned-8 buf 0 (char->integer #\X))
    (foreign-set! 'unsigned-8 buf 1 (char->integer #\X))
    (test-equal "c-string->string copies: mutating the source buffer after conversion leaves the result unchanged"
      "hi"
      s))
  (foreign-free buf))

(test-assert "option-bits sets a bit for validate-utf8"
  (> (option-bits #t #f #f #f #f #f) 0))

(test-assert "option-bits with everything off is zero"
  (= 0 (option-bits #f #f #f #f #f #f)))

(test-assert "option-bits composes distinct flags"
  (let ((a (option-bits #t #f #f #f #f #f))
        (b (option-bits #f #t #f #f #f #f)))
    (= (option-bits #t #t #f #f #f #f) (bitwise-ior a b))))

;; Seeded deliberately: assert a NON-empty starting shape so the test
;; cannot pass by accident if live-counts returned something degenerate.
(test-equal "live-counts reports three counters"
  3
  (length (live-counts)))

(test-assert "live-counts starts balanced at zero"
  (for-all zero? (live-counts)))

;; --- I4: compiled-vs-runtime version comparison -------------------------
;; ensure-native-loaded! runs at most once per process (init-mutex plus
;; the initialized? guard), against the real, matching shim and library,
;; which always succeeds -- so its raise path is untested by anything
;; that calls it. version-compatible? is the pure predicate it now gates
;; on; calling it directly with synthetic values exercises both the
;; compiled/runtime equality check and the range check independently,
;; with no need for an actually mismatched library.
(test-assert "version-supported? accepts both ends of the configured range"
  (and (version-supported? #x001d0000)
       (version-supported? #x001dffff)))

(test-assert "version-supported? rejects a version below the range"
  (not (version-supported? #x001c0000)))

(test-assert "version-supported? rejects a version above the range"
  (not (version-supported? #x001e0000)))

(test-assert "version-compatible? accepts equal compiled/runtime versions inside the range"
  (version-compatible? #x001d000d #x001d000d))

(test-assert "version-compatible? rejects a compiled/runtime mismatch even though both are in range"
  (not (version-compatible? #x001d0000 #x001d0001)))

(test-assert "version-compatible? rejects an equal compiled/runtime pair outside the range"
  (not (version-compatible? #x001c0000 #x001c0000)))

;; --- I2: shim-path validation and load wrapping -------------------------
;; native.sls's own shim-file/shim-loaded top-level bindings run once per
;; process (see tests/test-shim-loading.sps for subprocess coverage of
;; that actual default-path/override wiring). resolve-shim-path and
;; load-shim are the reusable procedures behind them, and are callable
;; directly here, any number of times, with synthetic paths -- including
;; a real dlopen call in the load-shim case, which is safe to repeat
;; against a bogus path even after the real shim has already loaded.
(define a-real-directory (current-directory))
(define a-real-non-library-file
  (string-append (current-directory) "/Makefile"))

(test-equal "resolve-shim-path rejects a directory given as an override"
  a-real-directory
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (resolve-shim-path "/irrelevant/default" a-real-directory)))

(test-equal "resolve-shim-path rejects a directory as the default path when there is no override"
  a-real-directory
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (resolve-shim-path a-real-directory #f)))

(test-equal "resolve-shim-path rejects a non-absolute override"
  "relative/path.dylib"
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (resolve-shim-path a-real-non-library-file "relative/path.dylib")))

(test-equal "resolve-shim-path rejects a nonexistent override"
  "/no/such/path.dylib"
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (resolve-shim-path a-real-non-library-file "/no/such/path.dylib")))

(test-assert "resolve-shim-path accepts a valid absolute, existing, regular-file override"
  (equal? a-real-non-library-file
          (resolve-shim-path "/irrelevant/default" a-real-non-library-file)))

(test-equal "load-shim wraps a real dlopen failure in cmark-shim-unavailable, carrying the path"
  a-real-non-library-file
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (load-shim a-real-non-library-file)))

(test-end "native")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
