#!r6rs
;;; The fallback config: what an unbuilt tree does.
;;;
;;; Two properties, and the second matters as much as the first:
;;;   1. With no generated config on the path, importing the library raises
;;;      &cmark-shim-unavailable with reason 'not-built -- not Chez's bare
;;;      "library (cmark gfm private config) not found".
;;;   2. With a real built src/ ahead of fallback/, the fallback is NOT used.
;;;      If that ordering were ever reversed, every native suite would break
;;;      in a confusing way -- but THIS suite covers the documented order
;;;      only: that the fallback engages when nothing ahead of it has a
;;;      config (section 1 below), and that a built src/ shadows it once
;;;      there is one (section 2 below). It does not exercise the reversed
;;;      order failing against a good build; that rests on the other native
;;;      suites breaking collaterally instead. See ADR-0014.
;;;
;;; Subprocesses are mandatory, not stylistic. native.sls resolves the shim
;;; during library instantiation, which happens at import -- before any
;;; in-process `guard` extent begins. Verified: a guard wrapped directly
;;; around (ensure-native-loaded!) with a poisoned shim path does not catch
;;; the condition; it escapes uncaught. tests/test-shim-loading.sps documents
;;; the same finding and is the pattern this file follows.
;;;
;;; Reading the child's stderr is sound because Chez's uncaught-condition
;;; report prints record field values, one per line -- verified directly:
;;; a two-field condition prints "path: #f" and "reason: not-built".
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv system)
        (cmark-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

(define chez-executable (or (getenv "CHEZ") "chez"))
(define probe-script "tests/shim-load-probe.sps")
(define unbuilt-src "tests/tmp/unbuilt-src")
(define stderr-capture "tests/tmp/fallback-probe-stderr.txt")

(system "mkdir -p tests/tmp")

;; A copy of src/ with the generated config removed -- i.e. exactly what a
;; fresh clone or a `make clean` leaves behind. Copied rather than mutated
;; so the real tree is never touched.
(system (string-append "rm -rf " unbuilt-src
                       " && mkdir -p " unbuilt-src
                       " && cp -R src/cmark " unbuilt-src "/cmark"
                       " && rm -f " unbuilt-src "/cmark/gfm/private/config.sls"))

(define (read-whole-file path)
  (let ((bv (file->bytevector path)))
    (utf8->string bv)))

;; Runs the probe with an explicit libdirs and no ambient shim override.
(define (run-probe libdirs)
  (let ((cmd (string-append
              "unset CHEZ_CMARK_GFM_SHIM; "
              "CHEZSCHEMELIBDIRS=\"" libdirs "\" "
              chez-executable " --script \"" probe-script "\" "
              "2>\"" stderr-capture "\"")))
    (let ((code (system cmd)))
      (values code (read-whole-file stderr-capture)))))

(test-begin "fallback-config")

;; --- 1. an unbuilt tree names its own remedy ---------------------------
(let-values (((code stderr) (run-probe (string-append unbuilt-src ":fallback"))))
  (test-assert "an unbuilt tree fails closed"
    (not (zero? code)))
  (test-assert "an unbuilt tree raises cmark-shim-unavailable, not a loader error"
    (string-contains? stderr "cmark-shim-unavailable"))
  (test-assert "an unbuilt tree reports reason not-built"
    (string-contains? stderr "not-built"))
  ;; The bug this whole task exists to remove. Asserted absent, because
  ;; "raises something" is not the property -- "raises a condition instead of
  ;; a missing-file report" is.
  (test-assert "an unbuilt tree does NOT report a missing library"
    (not (string-contains? stderr "library (cmark gfm private config) not found"))))

;; --- 2. a built src/ shadows the fallback ------------------------------
(let-values (((code stderr) (run-probe "src:fallback")))
  (test-equal "a built src/ ahead of fallback/ loads the real shim (exit 0)"
    0 code))

(test-end "fallback-config")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
