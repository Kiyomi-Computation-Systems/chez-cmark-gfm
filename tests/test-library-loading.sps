#!r6rs
;;; Resolution behaviour that needs a real process, not synthetic listings.
;;; tests/test-discovery.sps covers the selection algorithm; this covers the
;;; wiring: that an override wins, that an invalid one raises instead of
;;; falling back, and that the default path finds a real library here.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv system current-directory)
        (cmark gfm)
        (cmark gfm private native)
        (cmark gfm private conditions)
        (cmark-testing))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "library-loading")

;; The default path must have worked, or nothing below could run.
(test-assert "the default candidate search resolved a usable library"
  (string? (markdown->html "# x\n" (default-cmark-options))))

(test-assert "the loaded library is inside the supported range"
  (cmark-gfm-version-compatible?))

;; An invalid override raises and does NOT quietly fall back to the search.
;; Falling back would mean a typo in the variable silently loads a different
;; library than the one the user named.
(define (override-error str)
  (guard (e ((cmark-library-unavailable? e) (cmark-library-unavailable-reason e))
            (#t 'wrong-condition))
    (resolve-cmark-libraries str)
    'no-raise))

(test-equal "relative path override"    'invalid-override (override-error "a:b"))
(test-equal "single entry override"     'invalid-override (override-error "/usr/lib/libcmark-gfm.so"))
(test-equal "empty override"            'invalid-override (override-error ""))
(test-equal "nonexistent files"         'invalid-override
  (override-error "/nonexistent/libcmark-gfm.so:/nonexistent/libcmark-gfm-extensions.so"))

;; --- 'load-failed needs a subprocess -----------------------------------
;; The other two reasons are raised by resolve-cmark-libraries, which this
;; process can call directly. 'load-failed is raised by load-library, which
;; runs in native.sls's LIBRARY BODY -- so it fires at import, before any
;; in-process guard here could be entered. It needs a fresh process whose
;; import fails, with stderr captured.
;;
;; The two decoy files must PASS validation to reach the load: absolute paths,
;; existing regular files, and basenames that classify one as core and one as
;; extensions. They are not shared objects, so load-shared-object raises and
;; load-library converts that into reason 'load-failed.
;;
;; The paths must be ABSOLUTE: parse-library-override rejects a relative path
;; as 'invalid-override before load-library is ever reached, which would
;; silently test the wrong reason. current-directory prefixes them at runtime
;; so this does not depend on where the suite happens to be invoked from.
(define decoy-core
  (string-append (current-directory) "/tests/tmp/libcmark-gfm.so"))
(define decoy-ext
  (string-append (current-directory) "/tests/tmp/libcmark-gfm-extensions.so"))

(system "mkdir -p tests/tmp")
(for-each (lambda (p)
            (call-with-port (open-file-output-port p (file-options no-fail))
              (lambda (out) (put-bytevector out (string->utf8 "not a shared object\n")))))
          (list decoy-core decoy-ext))

;; capture-command raises when the command's exit status is non-zero -- the
;; right behaviour for every OTHER caller of it, where a non-zero exit means
;; a broken CLI probe. Here it is the opposite: the subprocess is SUPPOSED to
;; die (an uncaught &cmark-library-unavailable escaping at import time), so its
;; non-zero exit is expected and guarded away rather than left to propagate.
;; The shell redirection into out-path has already happened by the time
;; system() returns, regardless of the exit code, so the file holds the
;; right bytes either way; it is read back separately below. merge-stderr?
;; must be #t (verified empirically): Chez's uncaught-condition dump goes to
;; stderr, not stdout, and that dump is the only place 'load-failed appears.
(let ((out "tests/tmp/load-failed-stderr.txt"))
  (guard (e (#t #f))
    (capture-command
     (string-append "CHEZ_CMARK_GFM_LIBS=" decoy-core ":" decoy-ext
                    " CHEZSCHEMELIBDIRS=" (or (getenv "CHEZSCHEMELIBDIRS") "src:tests:build/scheme-libs")
                    " " (or (getenv "CHEZ") "chez")
                    " --program tests/load-failed-probe.sps")
     out
     #t))
  (let ((text (utf8->string (file->bytevector out))))
    (test-assert "a validated-but-unloadable library raises reason load-failed"
      (string-contains? text "load-failed"))))

;; --- 'missing-entry-point, the in-range library that lacks a symbol -----
;; Design spec 3.10. cmark_gfm_extensions_get_tasklist_item_checked first
;; shipped in 0.29.0.gfm.1; unpatched upstream 0.29.0.gfm.0 does not have it,
;; yet reports a version well inside the supported range, so the version gate
;; cannot see the difference and a floor cannot be raised without also
;; rejecting Debian 11's patched gfm.0. native.sls guards that one binding
;; instead. This asserts the guard actually converts the failure.
;;
;; The decoy extensions library is a SYMLINK TO THE RESOLVED CORE LIBRARY,
;; and that is the whole trick. Nothing is compiled and nothing is committed:
;; the core is a real shared object, so it loads; it reports a version inside
;; the range, so version-checked passes; and it does not export any
;; cmark_gfm_extensions_* symbol, so the first extensions binding native.sls
;; evaluates -- raw-tasklist-checked, which precedes every other one -- fails
;; exactly as it would on an unpatched gfm.0. Verified: with the guard
;; removed this same command prints
;;   Exception in foreign-procedure: no entry for
;;   "cmark_gfm_extensions_get_tasklist_item_checked"
;; so both assertions below fail. They are not decoration.
;;
;; No suffix on the decoy name, deliberately: parse-library-override does no
;; version or extension parsing at all, and dlopen by absolute path does not
;; care, so this needs no macOS/Linux branch. What the basename MUST contain
;; is "cmark-gfm-extensions", or it classifies as a second core and the
;; override is rejected as 'invalid-override before any load happens.
(define decoy-ext-symbolless
  (string-append (current-directory) "/tests/tmp/libcmark-gfm-extensions.decoy"))

(system (string-append "ln -sf " (car resolved-libraries) " " decoy-ext-symbolless))

(let ((out "tests/tmp/missing-entry-point-stderr.txt"))
  (guard (e (#t #f))
    (capture-command
     (string-append "CHEZ_CMARK_GFM_LIBS=" (car resolved-libraries)
                    ":" decoy-ext-symbolless
                    " CHEZSCHEMELIBDIRS=" (or (getenv "CHEZSCHEMELIBDIRS") "src:tests:build/scheme-libs")
                    " " (or (getenv "CHEZ") "chez")
                    " --program tests/load-failed-probe.sps")
     out
     #t))
  (let ((text (utf8->string (file->bytevector out))))
    (test-assert "an in-range library missing the tasklist entry point raises missing-entry-point"
      (string-contains? text "missing-entry-point"))
    ;; The condition is only half the claim. The other half is that the raw
    ;; foreign-procedure error no longer escapes -- that is what the guard
    ;; buys, and asserting only the reason above would still pass if both
    ;; were somehow printed.
    (test-assert "the raw foreign-procedure error does not escape"
      (not (string-contains? text "no entry for")))
    ;; The path must name the EXTENSIONS library, not the core. Both are
    ;; loaded, both are real files, and a cdr/car slip would be invisible to
    ;; the two assertions above while sending the reader to the wrong file.
    (test-assert "the condition names the extensions library, not the core"
      (string-contains? text "libcmark-gfm-extensions.decoy"))))

(test-end "library-loading")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
