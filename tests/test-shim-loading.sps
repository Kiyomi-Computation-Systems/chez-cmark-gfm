#!r6rs
;;; I2: shim-path validation and load-shared-object wrapping.
;;;
;;; native.sls's shim-file/shim-loaded top-level bindings run exactly once
;;; per process (see tests/shim-load-probe.sps for why -- library
;;; instantiation is deferred until first use, and that first use cannot
;;; be guarded from inside the same process). There is no way to exercise
;;; a second, different CHEZ_CMARK_GFM_SHIM value in this process once it
;;; has resolved the shim once, so this suite spawns a fresh chez
;;; subprocess per scenario instead.
;;;
;;; This is deliberately POSIX-shell-dependent (relies on /bin/sh via
;;; `system`, and on shell env-var-prefix and redirection syntax), on the
;;; same footing as `make test-memory`'s existing Valgrind/DYLD_INSERT_
;;; LIBRARIES machinery (gated by UNAME_S in the Makefile). Windows
;;; support is already deferred beyond v1 (ADR-0004); revisit this file
;;; if that changes.
;;;
;;; What a subprocess exit code alone CANNOT show: whether a failure was
;;; the structured &cmark-shim-unavailable condition design spec 6.2
;;; requires, or a raw dlopen error escaping uncaught -- both produce the
;;; same non-zero exit from Chez's default top-level exception handler.
;;; So each failing case also greps the child's captured stderr for
;;; Chez's default condition report, which does name the condition type
;;; for a record-based condition like this one (confirmed directly: a
;;; raw dlopen failure prints "Exception: (while loading ...) dlopen(...)",
;;; while (raise (make-cmark-shim-unavailable path 'missing)) uncaught
;;; prints "Exception occurred with condition components: 0. &cmark-shim-
;;; unavailable: ..."). make-cmark-shim-unavailable is 2-arg (path reason);
;;; the reason field post-dates this comment's original 1-arg example. The
;;; in-process tests in tests/test-native.sps
;;; additionally call resolve-shim-path and load-shim directly, which is
;;; the more precise way to check condition types; this suite exists to
;;; confirm the real default-path/override wiring in native.sls actually
;;; uses them, end to end, in a genuinely fresh process.
(import (rnrs)
        (srfi :64)
        (cmark gfm private config)   ; shim-path: a known-good absolute path
        (only (chezscheme) getenv system current-directory))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

;; --- subprocess plumbing --------------------------------------------
(define chez-executable (or (getenv "CHEZ") "chez"))
;; "src:.akku/lib" duplicates the Makefile's CHEZ_LIBDIRS so this suite
;; also works when run directly (not just via `make test`, which already
;; has CHEZSCHEMELIBDIRS set and would be inherited).
(define chez-libdirs (or (getenv "CHEZSCHEMELIBDIRS") "src:.akku/lib"))
(define probe-script "tests/shim-load-probe.sps")
(define stderr-capture "tests/tmp/shim-load-probe-stderr.txt")

(system "mkdir -p tests/tmp")

(define (shell-quote s) (string-append "\"" s "\""))

(define (read-whole-file path)
  (call-with-port (open-file-input-port path)
    (lambda (p)
      (let ((bv (get-bytevector-all p)))
        (if (eof-object? bv) "" (utf8->string bv))))))

(define (contains? haystack needle)
  (let ((hlen (string-length haystack)) (nlen (string-length needle)))
    (let loop ((i 0))
      (cond
        ((> (+ i nlen) hlen) #f)
        ((string=? (substring haystack i (+ i nlen)) needle) #t)
        (else (loop (+ i 1)))))))

;; Runs tests/shim-load-probe.sps in a fresh subprocess with
;; CHEZ_CMARK_GFM_SHIM bound to shim-override, or explicitly unset when
;; shim-override is #f (never left to whatever the ambient environment
;; happens to have). Returns two values: the child's exit code, and its
;; captured stderr text.
(define (run-probe shim-override)
  (let* ((prefix
          (string-append
           "unset CHEZ_CMARK_GFM_SHIM; "
           "CHEZSCHEMELIBDIRS=" (shell-quote chez-libdirs) " "
           (if shim-override
               (string-append "CHEZ_CMARK_GFM_SHIM="
                               (shell-quote shim-override) " ")
               "")))
         (cmd (string-append prefix chez-executable
                              " --script " (shell-quote probe-script)
                              " 2>" (shell-quote stderr-capture))))
    (let ((code (system cmd)))
      (values code (read-whole-file stderr-capture)))))

(test-begin "shim-loading")

;; --- positive controls: these must still succeed -----------------------
(let-values (((code stderr) (run-probe #f)))
  (test-equal "no override: the default, generated shim path loads (exit 0)"
    0 code))

(let-values (((code stderr) (run-probe shim-path)))
  (test-equal "a valid absolute override loads (exit 0)"
    0 code))

;; --- I2: the cases that used to escape as raw dlopen errors -------------
(let-values (((code stderr) (run-probe (current-directory))))
  (test-assert "a directory override fails closed (non-zero exit)"
    (not (zero? code)))
  (test-assert "a directory override raises cmark-shim-unavailable, not a raw dlopen error"
    (contains? stderr "cmark-shim-unavailable")))

(let-values (((code stderr) (run-probe (string-append (current-directory) "/Makefile"))))
  (test-assert "a non-library regular-file override fails closed (non-zero exit)"
    (not (zero? code)))
  (test-assert "a non-library regular-file override raises cmark-shim-unavailable, not a raw dlopen error"
    (contains? stderr "cmark-shim-unavailable")))

;; --- regression guards: these already worked before this fix ------------
(let-values (((code stderr) (run-probe "/no/such/path.dylib")))
  (test-assert "a nonexistent override still fails closed"
    (not (zero? code)))
  (test-assert "a nonexistent override still raises cmark-shim-unavailable"
    (contains? stderr "cmark-shim-unavailable")))

(let-values (((code stderr) (run-probe "relative/path.dylib")))
  (test-assert "a non-absolute override still fails closed"
    (not (zero? code)))
  (test-assert "a non-absolute override still raises cmark-shim-unavailable"
    (contains? stderr "cmark-shim-unavailable")))

(test-end "shim-loading")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
