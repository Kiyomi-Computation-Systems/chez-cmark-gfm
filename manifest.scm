;;; Development environment for chez-cmark-gfm (ADR-0018).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and
;;; runs this manifest in a container. Plain `guix shell` also loads this
;;; file, but against whatever Guix you have pulled: the unpinned path.

(use-modules (guix packages)
             (guix profiles)
             (guix search-paths)
             (guix gexp)
             (guix build-system trivial)
             ((guix licenses) #:prefix license:))

;; Installs nothing. Its search paths set two variables from the profile, so
;; every make target works with no argument:
;;
;; CHEZ -- the Makefile's `CHEZ ?= chez` honours it. Guix names the binary
;; `scheme`, and the alias has to be the binary itself: a `chez` wrapper
;; script satisfies `make test` but hides Chez from Valgrind, which traces
;; the shell and lets the exec'd Chez run uninstrumented. (A `chez` symlink
;; is no better: Chez derives its boot-file name from the invoked name and
;; aborts looking for chez.boot.)
;;
;; CHEZ_CMARK_GFM_LIBS -- discovery never searches a Guix profile
;; (ADR-0016). Under scripts/guix-env's --emulate-fhs it finds the pair at
;; /usr/lib, but only this names the store path, and plain `guix shell` has
;; no /usr/lib at all. The pattern matches only the versioned files: the
;; unversioned symlinks would make four entries, which
;; parse-library-override rejects as invalid-override.
(define chez-cmark-gfm-dev-env
  (package
    (name "chez-cmark-gfm-dev-env")
    (version "0")
    (source #f)
    (build-system trivial-build-system)
    (arguments (list #:builder #~(mkdir #$output)))
    (native-search-paths
     (list (search-path-specification
            (variable "CHEZ")
            (files '("bin/scheme"))
            (file-type 'regular)
            (separator #f))
           (search-path-specification
            (variable "CHEZ_CMARK_GFM_LIBS")
            (files '("lib"))
            (file-type 'regular)
            (file-pattern "^libcmark-gfm(-extensions)?\\.so\\.[0-9]"))))
    (home-page "https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm")
    (synopsis "Environment variables for developing chez-cmark-gfm")
    (description "Sets @env{CHEZ} and @env{CHEZ_CMARK_GFM_LIBS} from the
profile it is installed in.")
    (license license:bsd-3)))

(concatenate-manifests
 (list
  (packages->manifest (list chez-cmark-gfm-dev-env))
  (specifications->manifest
   '("chez-scheme" "cmark-gfm"
     ;; What the Makefile shells out to. The container has nothing else.
     "bash" "coreutils" "make" "git" "grep" "sed" "gawk" "findutils"
     "diffutils" "nss-certs"
     "cmake" "gcc-toolchain"            ; make vendor
     "valgrind"))))                     ; make test-memory
