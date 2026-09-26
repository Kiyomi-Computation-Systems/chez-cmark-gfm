;;; Development environment for chez-cmark-gfm (ADR-0018).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and
;;; runs this manifest in a container. Plain `guix shell` also loads this
;;; file, but against whatever Guix you have pulled: the unpinned path.

(use-modules (guix packages)
             (guix profiles)
             (guix gexp)
             (guix build-system trivial)
             ((guix licenses) #:prefix license:)
             (guix search-paths)
             (gnu packages bash)
             (gnu packages chez)
             (gnu packages markup))

;; A script, not a symlink: Chez derives its boot-file name from the name
;; it was invoked by, so a `chez` symlink looks for chez.boot and aborts.
(define chez-command
  (package
    (name "chez-command")
    (version (package-version chez-scheme))
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:builder
      #~(let ((bin (string-append #$output "/bin")))
          (mkdir #$output)
          (mkdir bin)
          (call-with-output-file (string-append bin "/chez")
            (lambda (port)
              (format port "#!~a~%exec ~a \"$@\"~%"
                      #$(file-append bash-minimal "/bin/sh")
                      #$(file-append chez-scheme "/bin/scheme"))))
          (chmod (string-append bin "/chez") #o555))))
    (home-page "https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm")
    (synopsis "@command{chez} for the Makefile's default @code{CHEZ}")
    (description "Runs Guix's @command{scheme} under the name the
chez-cmark-gfm Makefile expects.")
    (license license:bsd-3)))

;; Discovery never searches a Guix profile (ADR-0016), so the environment
;; names the pair through the documented override. The pattern matches only
;; the versioned files: the unversioned symlinks would make four entries,
;; which parse-library-override rejects as invalid-override. Adding a search
;; path leaves cmark-gfm's store item unchanged, so substitutes still apply.
(define cmark-gfm/chez-search-path
  (package
    (inherit cmark-gfm)
    (native-search-paths
     (list (search-path-specification
            (variable "CHEZ_CMARK_GFM_LIBS")
            (files '("lib"))
            (file-type 'regular)
            (file-pattern "^libcmark-gfm(-extensions)?\\.so\\.[0-9]"))))))

(concatenate-manifests
 (list
  (packages->manifest (list chez-command cmark-gfm/chez-search-path))
  (specifications->manifest
   '("chez-scheme"
     ;; What the Makefile shells out to. The container has nothing else.
     "bash" "coreutils" "make" "git" "grep" "sed" "gawk" "findutils"
     "diffutils" "nss-certs"
     "cmake" "gcc-toolchain"            ; make vendor
     "valgrind"                         ; make test-memory
     "openssh" "github-cli" "gnupg"))))  ; push, PRs, commit signing
