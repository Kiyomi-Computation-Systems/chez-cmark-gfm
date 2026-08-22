#!r6rs
;;; `make build` in 2.0. There is nothing to compile, so build answers the
;;; question the install contract actually raises: is this machine set up, and
;;; which library would be loaded?
;;;
;;; WHY eval/environment INSTEAD OF A PLAIN IMPORT -- do not "simplify" this
;;; back. (cmark gfm private native) loads the shared objects in its LIBRARY
;;; BODY, and an R6RS program instantiates every library it imports BEFORE its
;;; own body runs. Importing it at the top of this file therefore raises
;;; &cmark-shim-unavailable before the guard below is ever entered, which makes
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
        (only (chezscheme) printf getenv eval environment)
        (cmark gfm private conditions))

(guard (e ((cmark-shim-unavailable? e)
           (printf "chez-cmark-gfm: no usable libcmark-gfm (~a)\n"
                   (cmark-shim-unavailable-reason e))
           (printf "  install it with:  apt install cmark-gfm   (Debian/Ubuntu)\n")
           (printf "                    brew install cmark-gfm  (macOS)\n")
           (printf "  or name both libraries in CHEZ_CMARK_GFM_LIBS.\n")
           (exit 1))
          ((cmark-version-incompatible? e)
           (printf "chez-cmark-gfm: found cmark-gfm ~x, outside the supported range\n"
                   (cmark-version-incompatible-runtime e))
           (exit 1)))
  ;; The override is spliced as a literal rather than quoted: getenv yields a
  ;; string or #f, both self-evaluating, and `env` carries only the two cmark
  ;; libraries' exports -- not (rnrs)'s, so `quote` is not bound inside it.
  (let* ((env (environment '(cmark gfm) '(cmark gfm private native)))
         (libs (eval `(resolve-cmark-libraries ,(getenv "CHEZ_CMARK_GFM_LIBS")) env)))
    (printf "cmark-gfm ~a\n" (eval '(cmark-gfm-version) env))
    (printf "  core: ~a\n" (car libs))
    (printf "  ext:  ~a\n" (cdr libs))
    (exit 0)))
