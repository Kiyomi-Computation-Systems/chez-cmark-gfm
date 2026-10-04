#!r6rs
;;; memory-gate-sabotage.sps -- a PLANTED memory defect. Not a suite.
;;;
;;; `make check-memory-gate` runs this program through the real
;;; `make test-memory` recipe and requires that recipe to FAIL, with the memory
;;; tool's own report of the planted defect in its log. A gate nobody has
;;; watched fail is a comment: until 2026-09-28 the macOS arm ran its suites
;;; under `sh -c`, SIP stripped DYLD_INSERT_LIBRARIES on the way in, and no
;;; suite ever loaded ASan, yet every run was green (ADR-0003, amended
;;; 2026-09-28).
;;;
;;; Deliberately NOT named tests/test-*.sps: that wildcard feeds TESTS and
;;; MEMORY_TESTS, and this program must never run as part of either gate.
;;;
;;; CHEZ_CMARK_GFM_SABOTAGE picks the defect. Each one runs clean WITHOUT a
;;; memory tool -- check-memory-gate proves that first, by requiring exit 0 and
;;; the final "planted" line from a plain run -- so a red gate can only mean
;;; the tool saw the defect:
;;;
;;;   store-overrun  one byte past a 23-byte foreign block, written by a Scheme
;;;                  store (foreign-set!). Valgrind sees it. ASan cannot:
;;;                  Chez's generated code is not instrumented.
;;;   libc-overrun   one byte past a 29-byte foreign block, written by libc's
;;;                  memset. Valgrind sees it, and so does ASan's memset
;;;                  interceptor, which makes it the macOS arm's witness.
;;;   leak           777 bytes allocated and never freed. Valgrind only: the
;;;                  macOS arm makes no leak claim (no LeakSanitizer on arm64).
;;;   possible-leak  555 bytes whose only reference is an interior pointer,
;;;                  kept as raw bytes in a live bytevector. Memcheck scans the
;;;                  Scheme heap, so it classifies the block "possibly lost".
;;;                  Not a defect the gate must catch: it checks that the gate
;;;                  never fails on a leak kind it does not display.
;;;
;;; The sizes are sentinels. The tool's report names them, and nothing else in
;;; the run overruns or loses a block of exactly these sizes.
(import (chezscheme))

(define mode (getenv "CHEZ_CMARK_GFM_SABOTAGE"))

;; Live until exit, so its bytes stay in the heap memcheck scans.
(define interior-pointer-holder (make-bytevector 16 0))

(define (say what)
  (display "memory-gate-sabotage: ")
  (display what)
  (display " ")
  (display mode)
  (newline)
  (flush-output-port (current-output-port)))

;; memset is not a foreign entry until libc is loaded, on either platform.
(define (libc-memset)
  (let* ((mt (symbol->string (machine-type)))
         (n (string-length mt)))
    (load-shared-object
     (if (and (>= n 3) (string=? "osx" (substring mt (- n 3) n)))
         "libc.dylib"
         "libc.so.6")))
  (foreign-procedure "memset" (uptr int size_t) uptr))

(say "planting")
(cond
  ((equal? mode "store-overrun")
   (let ((p (foreign-alloc 23)))
     (foreign-set! 'unsigned-8 p 23 1)
     (foreign-free p)))
  ((equal? mode "libc-overrun")
   (let* ((memset (libc-memset))
          (p (foreign-alloc 29)))
     (memset p 0 30)
     (foreign-free p)))
  ((equal? mode "leak")
   (foreign-alloc 777))
  ((equal? mode "possible-leak")
   (let ((p (foreign-alloc 555)))
     (bytevector-u64-native-set! interior-pointer-holder 8 (+ p 8))))
  (else
   (display "memory-gate-sabotage: set CHEZ_CMARK_GFM_SABOTAGE to store-overrun, libc-overrun, leak or possible-leak\n"
            (current-error-port))
   (exit 2)))
(say "planted")
(exit 0)
