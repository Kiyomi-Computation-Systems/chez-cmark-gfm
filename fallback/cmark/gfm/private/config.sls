#!r6rs
;;; Fallback build configuration -- in force ONLY when no build has happened.
;;;
;;; `make build` generates the real (cmark gfm private config) into src/, and
;;; the Makefile puts src ahead of fallback on CHEZSCHEMELIBDIRS. Chez resolves
;;; a library from the FIRST entry that has it, so this file is reached only
;;; when the generated one is absent -- a fresh clone, or after `make clean`.
;;; Unlike the generated file, this one is checked in and holds no
;;; machine-specific path.
;;;
;;; shim-path is #f rather than a string, and that is the entire mechanism. No
;;; build can produce a non-string here, so resolve-shim-path can tell "never
;;; built" from "built, but the shim has since gone missing" without either
;;; case having to guess. A plausible-looking fake path could not: it would be
;;; indistinguishable from a real path that had been deleted.
;;;
;;; cmark-library-paths is empty, with a documented consequence: in an unbuilt
;;; tree CHEZ_CMARK_GFM_SHIM still overrides and loads a prebuilt shim, which
;;; works on macOS but fails on Linux, whose loader does not put a dlopen'd
;;; library's dependencies in the global symbol namespace. See ADR-0014.
(library (cmark gfm private config)
  (export shim-path cmark-library-paths cmark-supported-version-range)
  (import (rnrs))
  (define shim-path #f)
  (define cmark-library-paths '())
  ;; Must stay equal to the Makefile's generated value; `make check-config`
  ;; enforces that.
  (define cmark-supported-version-range '(#x001d0000 . #x001dffff)))
