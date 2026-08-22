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

(test-end "library-loading")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
