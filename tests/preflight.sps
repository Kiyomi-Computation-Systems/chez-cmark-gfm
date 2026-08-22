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
;; no shared object -- so its predicates are safe to import directly. So is
;; (cmark gfm private discovery), whose own header states the property and
;; whose imports are (rnrs) plus machine-type; version->string comes from
;; there, and importing it here does not drag in the loads described above.
(import (rnrs)
        (only (chezscheme) printf eval environment)
        (only (cmark gfm private discovery) version->string)
        (cmark gfm private conditions))

(guard (e ((cmark-library-unavailable? e)
           (printf "chez-cmark-gfm: no usable libcmark-gfm (~a)\n"
                   (cmark-library-unavailable-reason e))
           ;; 'missing-entry-point is the one reason of the four where the
           ;; library IS installed, IS loadable, and IS inside the supported
           ;; range. The three install lines below are still the remedy -- a
           ;; NEWER cmark-gfm is what fixes it -- but on their own they read
           ;; as "you have not installed it", which is false here and sends
           ;; the reader to a command that reinstalls the very build just
           ;; rejected. Name the file and what it lacks first, the way the
           ;; version-incompatible clause below names the range it rejected.
           (when (eq? 'missing-entry-point (cmark-library-unavailable-reason e))
             (printf "  ~a\n" (cmark-library-unavailable-path e))
             (printf "  loaded and is in range, but has no cmark_gfm_extensions_get_tasklist_item_checked,\n")
             (printf "  which arrived in 0.29.0.gfm.1. A newer cmark-gfm is what fixes this:\n"))
           (printf "  install it with:  apt install cmark-gfm   (Debian/Ubuntu)\n")
           (printf "                    brew install cmark-gfm  (macOS)\n")
           (printf "  or name both libraries in CHEZ_CMARK_GFM_LIBS.\n")
           (exit 1))
          ((cmark-version-incompatible? e)
           ;; DECODED, not raw hex, and the bounds are named. `1D0006` is
           ;; cmark's own integer encoding; nobody reading it can compare it
           ;; to the version their package manager reports, and a range the
           ;; reader is never shown is a range they cannot act on.
           ;; version->string is exported from (cmark gfm private discovery)
           ;; for exactly this. ADR-0014's "name the remedy" principle is what
           ;; the design spec (5) delegates to this program for `not-found`;
           ;; this clause owes the reader the same, and used to give none.
           (let ((supported (cmark-version-incompatible-supported e)))
             (printf "chez-cmark-gfm: found cmark-gfm ~a, outside the supported range\n"
                     (version->string (cmark-version-incompatible-runtime e)))
             (printf "  this binding supports ~a up to and including ~a.\n"
                     (version->string (car supported))
                     (version->string (cdr supported))))
           (printf "  install one inside that range:  apt install cmark-gfm   (Debian/Ubuntu)\n")
           (printf "                                  brew install cmark-gfm  (macOS)\n")
           (printf "  if that IS the package just rejected, build a supported release from\n")
           (printf "  source -- docs/installing.md, \"RHEL, Fedora, and Alpine\", has the cmake recipe --\n")
           (printf "  and name both libraries in CHEZ_CMARK_GFM_LIBS if they land off the\n")
           (printf "  default search path.\n")
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
