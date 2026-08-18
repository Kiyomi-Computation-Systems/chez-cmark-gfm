#!r6rs
(import (rnrs)          ; note: (rnrs) already exports `exit` via
        (srfi :64)      ; (rnrs programs) -- importing it from
        (cmark gfm private native)    ; (chezscheme) too is a conflict
        (cmark gfm private conditions)
        (cmark gfm private scope)
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

;; --- I3: every option flag must move an independent, non-zero bit -----
;; The composition test above only ever exercises positions 1 and 2
;; (validate-utf8, sourcepos) together. A shim where sourcepos aliased
;; validate-utf8, or where hardbreaks/nobreaks/smart/unsafe_html did
;; nothing at all -- including the security-relevant unsafe_html flag --
;; would still pass every assertion above this one.
(define (pairwise-distinct? lst)
  (or (null? lst)
      (and (for-all (lambda (y) (not (= (car lst) y))) (cdr lst))
           (pairwise-distinct? (cdr lst)))))

(test-assert "each of the six option flags sets a distinct, non-zero bit"
  (let ((flags (list (option-bits #t #f #f #f #f #f)    ; validate-utf8
                      (option-bits #f #t #f #f #f #f)    ; sourcepos
                      (option-bits #f #f #t #f #f #f)    ; hardbreaks
                      (option-bits #f #f #f #t #f #f)    ; nobreaks
                      (option-bits #f #f #f #f #t #f)    ; smart
                      (option-bits #f #f #f #f #f #t)))) ; unsafe_html
    (and (for-all (lambda (x) (> x 0)) flags)
         (pairwise-distinct? flags))))

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

;; A gfm patch bump under a shim compiled against an earlier patch must be
;; ACCEPTED -- the supported range is 0.29.0.gfm.x, so rejecting it would
;; contradict the range the project publishes.
(test-assert "version-compatible? accepts a gfm patch bump inside the range"
  (version-compatible? #x001d000d #x001d000e))

;; ...but a shim built against an unsupported header is rejected even when the
;; runtime is fine. This is what checking `compiled` buys over checking runtime
;; alone; without it this assertion passes vacuously.
(test-assert "version-compatible? rejects a compiled version outside the range"
  (not (version-compatible? #x001c0000 #x001d000d)))

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

;; --- reason discriminates the four resolution failures -------------------
;; Asserting (list path reason) rather than the path alone is deliberate, and
;; is a fix, not a flourish. resolve-shim-path RETURNS the path it accepts, so
;; an assertion expecting just the path is satisfied by the success path:
;; verified by deleting every rejection from resolve-shim-path, after which
;; this suite still reported 54 expected passes and exit 0. A two-element list
;; is a value no success path here produces, and the trailing 'no-condition
;; closes the other half -- a guard returns its body's value when nothing
;; raises.
(define (shim-failure thunk)
  (guard (e ((cmark-shim-unavailable? e)
             (list (cmark-shim-unavailable-path e)
                   (cmark-shim-unavailable-reason e))))
    (thunk)
    'no-condition))

(test-equal "a directory override is rejected as invalid-override"
  (list a-real-directory 'invalid-override)
  (shim-failure (lambda () (resolve-shim-path "/irrelevant/default" a-real-directory))))

(test-equal "a directory as the default path, with no override, is missing"
  (list a-real-directory 'missing)
  (shim-failure (lambda () (resolve-shim-path a-real-directory #f))))

(test-equal "a non-absolute override is rejected as invalid-override"
  (list "relative/path.dylib" 'invalid-override)
  (shim-failure (lambda () (resolve-shim-path a-real-non-library-file "relative/path.dylib"))))

(test-equal "a nonexistent override is rejected as invalid-override"
  (list "/no/such/path.dylib" 'invalid-override)
  (shim-failure (lambda () (resolve-shim-path a-real-non-library-file "/no/such/path.dylib"))))

(test-assert "a valid absolute, existing, regular-file override is accepted"
  (string=? a-real-non-library-file
            (resolve-shim-path "/irrelevant/default" a-real-non-library-file)))

(test-equal "load-shim wraps a real dlopen failure as load-failed"
  (list a-real-non-library-file 'load-failed)
  (shim-failure (lambda () (load-shim a-real-non-library-file))))

;; --- Stage 2: version string ------------------------------------------
;; Not asserted against a hardcoded "0.29.0.gfm.13", which would only pin the
;; fixture. Decoded from the packed runtime integer using the four-byte
;; layout the Stage 0 spike established (major<<24 | minor<<16 | patch<<8 |
;; gfm), so a binding that returned the wrong string, an empty string, or a
;; stale pointer fails here.
(define (decode-version v)
  (string-append
   (number->string (bitwise-arithmetic-shift-right v 24)) "."
   (number->string (bitwise-and (bitwise-arithmetic-shift-right v 16) #xff)) "."
   (number->string (bitwise-and (bitwise-arithmetic-shift-right v 8) #xff)) ".gfm."
   (number->string (bitwise-and v #xff))))

(test-equal "runtime-version-string agrees with the packed runtime version"
  (decode-version (shim-runtime-version))
  (runtime-version-string))

(test-assert "the compiled and runtime versions are both in the supported range"
  (and (version-supported? (shim-compiled-version))
       (version-supported? (shim-runtime-version))))

;; --- Stage 2: option bits are six DISTINCT bits ------------------------
;; This is the only coverage validate-utf8? can have: the public API takes a
;; Scheme string and string->utf8 always emits valid UTF-8, so
;; CMARK_OPT_VALIDATE_UTF8 has no observable effect on any reachable input
;; and no differential cell can discriminate it (design spec 10.1). Testing
;; the BIT is honest; testing the behaviour would be an assertion that
;; passes either way.
(define (all-distinct? xs)
  (cond ((null? xs) #t)
        ((memv (car xs) (cdr xs)) #f)
        (else (all-distinct? (cdr xs)))))

(test-assert "each of the six option flags sets a distinct bit"
  (all-distinct?
   (list (option-bits #t #f #f #f #f #f)
         (option-bits #f #t #f #f #f #f)
         (option-bits #f #f #t #f #f #f)
         (option-bits #f #f #f #t #f #f)
         (option-bits #f #f #f #f #t #f)
         (option-bits #f #f #f #f #f #t))))

(test-assert "validate-utf8? is wired to a real bit even though its behaviour is unreachable"
  (not (= (option-bits #t #f #f #f #f #f)
          (option-bits #f #f #f #f #f #f))))

(test-equal "all flags off is the default mask, and differs from all flags on"
  #f
  (= (option-bits #f #f #f #f #f #f)
     (option-bits #t #t #t #f #t #t)))

;; --- Stage 3: node accessors -------------------------------------------
;; Driven through call-with-native-document rather than a bare parser so the
;; teardown rules of ADR-0005 and ADR-0006 keep applying to every probe here.
(define (with-root markdown exts proc)
  (call-with-native-document
   markdown (option-bits #f #t #f #f #f #f) exts
   (lambda (h) (proc (doc-root h)))))

;; Walk a path of zero-based child indices down from a node.
(define (walk node path)
  (if (null? path)
      node
      (let loop ((n (node-first-child node)) (i (car path)))
        (if (zero? i)
            (walk n (cdr path))
            (loop (node-next n) (- i 1))))))

(define (type-at markdown exts path)
  (with-root markdown exts
             (lambda (root) (c-string->string (node-type-string (walk root path))))))

(test-equal "the root's type string is document"
  "document" (type-at "# hi\n" '() '()))
(test-equal "a heading's type string is heading"
  "heading" (type-at "# hi\n" '() '(0)))
(test-equal "node-next reaches the second block, not the first"
  "paragraph" (type-at "# hi\n\npara\n" '() '(1)))
(test-equal "a heading's child is a text node"
  "text" (type-at "# hi\n" '() '(0 0)))

(test-equal "node-heading-level reads the level"
  3 (with-root "### three\n" '() (lambda (r) (node-heading-level (walk r '(0))))))
(test-equal "node-literal copies the text"
  "hi" (with-root "# hi\n" '()
         (lambda (r) (c-string->string (node-literal (walk r '(0 0)))))))
(test-equal "node-url and node-title read a link"
  '("http://e.example/" "T")
  (with-root "[x](http://e.example/ \"T\")\n" '()
    (lambda (r)
      (let ((link (walk r '(0 0))))
        (list (c-string->string (node-url link))
              (c-string->string (node-title link)))))))
(test-equal "node-fence-info reads a fence info string"
  "scheme"
  (with-root "```scheme\n(+ 1 2)\n```\n" '()
    (lambda (r) (c-string->string (node-fence-info (walk r '(0)))))))
;; Empty, not #f: cmark returns "" for a code block with no info string and
;; NULL only for a node that is not a code block (src/cmark-gfm.h). Conflating
;; the two would invent data, so the distinction is asserted.
(test-equal "an indented code block has an empty, not absent, fence info"
  ""
  (with-root "    indented\n" '()
    (lambda (r) (c-string->string (node-fence-info (walk r '(0)))))))

;; 2 = CMARK_ORDERED_LIST, 1 = CMARK_PERIOD_DELIM. The numbers stay here in
;; layer 2; convert.sls maps them to symbols.
(test-equal "list accessors read kind, start, delim, and tightness"
  '(2 3 1 1)
  (with-root "3. one\n4. two\n" '()
    (lambda (r)
      (let ((l (walk r '(0))))
        (list (node-list-type l) (node-list-start l)
              (node-list-delim l) (node-list-tight l))))))
(test-equal "a bullet list reports kind 1 and start 0"
  '(1 0)
  (with-root "- one\n" '()
    (lambda (r)
      (let ((l (walk r '(0))))
        (list (node-list-type l) (node-list-start l))))))
(test-equal "node-item-index reads the second item's index"
  4 (with-root "3. one\n4. two\n" '()
      (lambda (r) (node-item-index (walk r '(0 1))))))

(test-equal "position accessors read the paragraph's span"
  '(3 1 3 4)
  (with-root "# hi\n\npara\n" '()
    (lambda (r)
      (let ((p (walk r '(1))))
        (list (node-start-line p) (node-start-column p)
              (node-end-line p) (node-end-column p))))))

;; --- extension accessors ------------------------------------------------
;; These three live in libcmark-gfm-extensions, not libcmark-gfm. They resolve
;; only because native.sls loads both shared objects explicitly, ahead of the
;; shim; if that ever regressed these would fail at IMPORT time on Linux while
;; still passing on macOS, whose loader searches dependencies.
(define table-md "| a | b |\n|:--|--:|\n| 1 | 2 |\n")

(test-equal "a table's type string is table"
  "table" (type-at table-md '("table") '(0)))
(test-equal "a header row's type string is table_header, not table_row"
  "table_header" (type-at table-md '("table") '(0 0)))
(test-equal "a body row's type string is table_row"
  "table_row" (type-at table-md '("table") '(0 1)))

(test-equal "table-columns counts the columns"
  2 (with-root table-md '("table") (lambda (r) (table-columns (walk r '(0))))))
;; 108 = 'l', 114 = 'r' (vendor/cmark-gfm/extensions/table.c:387-391).
(test-equal "table-alignments yields one byte per column"
  '(108 114)
  (with-root table-md '("table")
    (lambda (r)
      (let ((t (walk r '(0))))
        (alignment-bytes (table-alignments t) (table-columns t))))))
(test-equal "table-row-is-header agrees with the type string"
  '(1 0)
  (with-root table-md '("table")
    (lambda (r)
      (list (table-row-is-header (walk r '(0 0)))
            (table-row-is-header (walk r '(0 1)))))))

;; A task item's type string is "tasklist", which is the ONLY way to tell a
;; task item from a plain one: get_tasklist_item_checked returns false both
;; for an unchecked task and for a non-task
;; (vendor/cmark-gfm/extensions/tasklist.c:30-40).
(define task-md "- [x] done\n- [ ] todo\n")
(test-equal "a task item's type string is tasklist"
  "tasklist" (type-at task-md '("tasklist") '(0 0)))
(test-equal "a plain item's type string is item"
  "item" (type-at "- plain\n" '("tasklist") '(0 0)))
(test-equal "tasklist-checked distinguishes checked from unchecked"
  '(1 0)
  (with-root task-md '("tasklist")
    (lambda (r)
      (list (tasklist-checked (walk r '(0 0)))
            (tasklist-checked (walk r '(0 1)))))))
;; The shim wrapper's reason for existing: the underlying entry point returns
;; C _Bool, whose upper return-register bits are unspecified. Values other
;; than exactly 1 and 0 above would be the symptom.
(test-equal "tasklist-checked returns exactly 1 or 0, never a stray bit pattern"
  #t
  (with-root task-md '("tasklist")
    (lambda (r) (and (memv (tasklist-checked (walk r '(0 0))) '(0 1)) #t))))

;; alignment-bytes must not read through a NULL pointer.
(test-equal "alignment-bytes yields zeros for a NULL array"
  '(0 0 0) (alignment-bytes 0 3))
(test-equal "alignment-bytes yields the empty list for zero columns"
  '() (alignment-bytes 0 0))

(test-end "native")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
