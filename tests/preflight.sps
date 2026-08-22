#!r6rs
;;; `make build` in 2.0. There is nothing to compile, so build answers the
;;; question the install contract actually raises: is this machine set up, and
;;; which library would be loaded?
;;;
;;; WHY eval/environment INSTEAD OF A PLAIN IMPORT -- do not "simplify" this
;;; back. (cmark gfm private native) loads the shared objects in its LIBRARY
;;; BODY, and an R6RS program instantiates every library it imports BEFORE its
;;; own body runs. Importing it at the top of this file therefore raises
;;; &cmark-library-unavailable before the guard below is ever entered, which makes
;;; the guard -- and the install advice that is this program's whole reason to
;;; exist -- unreachable code. Verified: with a plain import,
;;; `CHEZ_CMARK_GFM_LIBS=/nonexistent` printed a raw "Exception occurred with
;;; condition components" dump and exited 255. `environment` and `eval` are
;;; ordinary procedure calls, so the load happens INSIDE the guard's dynamic
;;; extent and the condition is catchable.
;; `exit` comes from (rnrs), NOT (chezscheme) -- importing it from both raises
;; "multiple definitions for exit in body". See Global Constraints.
;; (cmark gfm private conditions) is pure -- it imports only (rnrs) and reaches
;; no shared object -- so its predicates are safe to import directly.
(import (rnrs)
        (only (chezscheme) printf eval environment)
        (cmark gfm private conditions))

(guard (e ((cmark-library-unavailable? e)
           (printf "chez-cmark-gfm: no usable libcmark-gfm (~a)\n"
                   (cmark-library-unavailable-reason e))
           (printf "  install it with:  apt install cmark-gfm   (Debian/Ubuntu)\n")
           (printf "                    brew install cmark-gfm  (macOS)\n")
           (printf "  or name both libraries in CHEZ_CMARK_GFM_LIBS.\n")
           (exit 1))
          ((cmark-version-incompatible? e)
           (printf "chez-cmark-gfm: found cmark-gfm ~x, outside the supported range\n"
                   (cmark-version-incompatible-runtime e))
           (exit 1))
          (else
           ;; Catch-all: e.g. an unreadable candidate directory, where
           ;; file-directory? is true for a chmod 000 directory and
           ;; directory-list then raises unwrapped. Without this clause the
           ;; guard re-raises and the raw Chez condition dump is exactly
           ;; what this program exists to prevent.
           (printf "chez-cmark-gfm: unexpected error while locating libcmark-gfm\n")
           (printf "  install it with:  apt install cmark-gfm   (Debian/Ubuntu)\n")
           (printf "                    brew install cmark-gfm  (macOS)\n")
           (printf "  or name both libraries in CHEZ_CMARK_GFM_LIBS.\n")
           (printf "  raw condition: ~a\n" e)
           (exit 1)))
  ;; Reads resolved-libraries -- the value native.sls's own instantiation
  ;; already computed and dlopen'd -- rather than calling
  ;; resolve-cmark-libraries a second time. A second call would repeat the
  ;; directory scan and, in principle, could derive a different answer than
  ;; what was actually loaded; reading the binding instead guarantees this
  ;; printout names the real thing.
  (let* ((env (environment '(cmark gfm) '(cmark gfm private native)))
         (libs (eval 'resolved-libraries env)))
    (printf "cmark-gfm ~a\n" (eval '(cmark-gfm-version) env))
    (printf "  core: ~a\n" (car libs))
    (printf "  ext:  ~a\n" (cdr libs))
    (exit 0)))
