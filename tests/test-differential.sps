#!r6rs
;;; Differential tests against the pinned cmark-gfm CLI.
;;;
;;; What these prove (design spec 7.5): that our option-bit construction and
;;; extension attachment do not alter native semantics. They are NOT a retest
;;; of cmark's parser.
;;;
;;; The load-bearing part is the DISCRIMINATION GUARD in layer 1. A parity
;;; assertion only means something if the flag actually changes output for
;;; that fixture: if --smart produces identical bytes for a document with no
;;; quotes or dashes, the parity check passes whether or not smart? is wired
;;; to CMARK_OPT_SMART at all. So every option first has to prove the CLI's
;;; OWN output moved.
(import (rnrs)
        (srfi :64)
        ;; file-exists? is deliberately absent: (rnrs) already exports it and
        ;; requesting it here too fails the library body with "multiple
        ;; definitions for file-exists?".
        (only (chezscheme) system getenv mkdir)
        (cmark gfm))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "differential")

(define cli (or (getenv "CMARK_CLI") "cmark-gfm"))
(define tmp-dir "tests/tmp")
(define out-path "tests/tmp/diff-out.bin")

(unless (file-exists? tmp-dir) (mkdir tmp-dir))

(define (file->bytevector path)
  (let* ((p (open-file-input-port path))
         (bv (get-bytevector-all p)))
    (close-port p)
    (if (eof-object? bv) (make-bytevector 0) bv)))

(define (string-contains? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

;; --- the CLI must be the same build as the loaded library ---------------
;; A missing or mismatched CLI FAILS this suite. It does not skip it:
;; "skip when unavailable" is how an exit criterion silently stops being
;; enforced. Both supported acquisition paths ship the binary.
(define (cli-version-line)
  (let ((rc (system (string-append cli " --version > " out-path " 2>&1"))))
    (unless (zero? rc)
      (error 'cli-version-line
             "cmark-gfm CLI is not runnable -- set CMARK_CLI or run via make test"
             cli rc))
    (utf8->string (file->bytevector out-path))))

(test-assert "the CLI is runnable and is the same build as the loaded library"
  (string-contains? (cli-version-line)
                    (string-append " " (cmark-gfm-version) " ")))

;; --- running one side of a comparison -----------------------------------
(define (run-cli flags fixture)
  (let* ((cmd (string-append cli " " flags " " fixture " > " out-path " 2>/dev/null"))
         (rc  (system cmd)))
    (unless (zero? rc) (error 'run-cli "CLI invocation failed" cmd rc))
    (file->bytevector out-path)))

(define (config->options cfg) (apply make-cmark-options cfg))

;; Our options record drives the CLI flags too, so the two sides cannot
;; describe different configurations by accident. The CLI does not set
;; CMARK_OPT_VALIDATE_UTF8 by default (vendor/cmark-gfm/src/main.c:185) while
;; our defaults can, so --validate-utf8 is emitted from the record, not
;; assumed.
(define (config->flags cfg format)
  (let ((o (config->options cfg)))
    (string-append
     "--to " (symbol->string format)
     (if (cmark-options-validate-utf8? o)    " --validate-utf8" "")
     (if (cmark-options-source-positions? o) " --sourcepos" "")
     (if (cmark-options-hardbreaks? o)       " --hardbreaks" "")
     (if (cmark-options-nobreaks? o)         " --nobreaks" "")
     (if (cmark-options-smart? o)            " --smart" "")
     (if (cmark-options-unsafe-html? o)      " --unsafe" "")
     (fold-left (lambda (acc e) (string-append acc " -e " (symbol->string e)))
                "" (cmark-options-extensions o)))))

(define (ours format markdown o)
  (string->utf8
   (case format
     ((html)       (markdown->html markdown o))
     ((xml)        (markdown->xml markdown o))
     ((commonmark) (markdown->commonmark markdown o))
     ((plaintext)  (markdown->plaintext markdown o))
     (else (error 'ours "unknown format" format)))))

;; Returns #f when the two agree, or a list naming the divergence. Taking
;; our-cfg and cli-cfg separately is what lets Task 9 seed this detector with
;; a deliberate mismatch and prove it can report anything at all.
(define (mismatch fixture format our-cfg cli-cfg)
  (let* ((md   (utf8->string (file->bytevector fixture)))
         (mine (ours format md (config->options our-cfg)))
         (theirs (run-cli (config->flags cli-cfg format) fixture)))
    (if (bytevector=? mine theirs)
        #f
        (list fixture format our-cfg))))

(define (agrees? fixture format cfg) (not (mismatch fixture format cfg cfg)))

(define (cli-differs? fixture format a b)
  (not (bytevector=? (run-cli (config->flags a format) fixture)
                     (run-cli (config->flags b format) fixture))))

;; --- layer 1: one factor at a time --------------------------------------
;; All-off, no extensions. validate-utf8? is off here and is not given an
;; OFAT cell: its behaviour is structurally unreachable through the public
;; API (design spec 10.1) -- string->utf8 always emits valid UTF-8, so no
;; fixture can make it discriminate. It is covered at the bit level in
;; tests/test-native.sps instead.
;; Configs are built by ONE constructor so no cell can accidentally repeat a
;; key. `extensions` lives in the base, so appending another `extensions` pair
;; would produce a duplicate-key plist -- which make-cmark-options rejects
;; outright, turning every extension cell below into a raised condition rather
;; than a comparison.
(define (cfg exts . kvs)
  (append (list 'validate-utf8? #f 'extensions exts) kvs))

(define BASE (cfg '()))

;; Each option: prove the CLI's own output moved, then prove we match it.
;; The (fixture, format) pair for each is chosen so the flag is observable
;; there; a pair that does not discriminate makes the parity cell empty.
(test-assert "sourcepos -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'source-positions? #t)))
(test-assert "sourcepos -- our output matches the CLI"
  (agrees? "tests/fixtures/core.md" 'html (cfg '() 'source-positions? #t)))

(test-assert "hardbreaks -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'hardbreaks? #t)))
(test-assert "hardbreaks -- our output matches the CLI"
  (agrees? "tests/fixtures/core.md" 'html (cfg '() 'hardbreaks? #t)))

(test-assert "nobreaks -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'nobreaks? #t)))
(test-assert "nobreaks -- our output matches the CLI"
  (agrees? "tests/fixtures/core.md" 'html (cfg '() 'nobreaks? #t)))

(test-assert "smart -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/smart.md" 'html BASE (cfg '() 'smart? #t)))
(test-assert "smart -- our output matches the CLI"
  (agrees? "tests/fixtures/smart.md" 'html (cfg '() 'smart? #t)))

(test-assert "unsafe-html -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/hostile.md" 'html BASE (cfg '() 'unsafe-html? #t)))
(test-assert "unsafe-html -- our output matches the CLI"
  (agrees? "tests/fixtures/hostile.md" 'html (cfg '() 'unsafe-html? #t)))

;; --- layer 1: extensions, one at a time ---------------------------------
;; tagfilter gets unsafe-html? in BOTH sides of its comparison. Under safe
;; mode raw HTML is suppressed wholesale, so tagfilter cannot change anything
;; and its cell would be empty. This is the pairing the discrimination guard
;; is here to force you to find.
(define UNSAFE-BASE (cfg '() 'unsafe-html? #t))

(test-assert "table extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE (cfg '(table))))
(test-assert "table extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(table))))

(test-assert "strikethrough extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE
                (cfg '(strikethrough))))
(test-assert "strikethrough extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(strikethrough))))

(test-assert "autolink extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE (cfg '(autolink))))
(test-assert "autolink extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(autolink))))

(test-assert "tasklist extension -- the CLI's own output changes"
  (cli-differs? "tests/fixtures/gfm.md" 'html BASE (cfg '(tasklist))))
(test-assert "tasklist extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(tasklist))))

(test-assert "tagfilter extension -- the CLI's own output changes (needs unsafe-html)"
  (cli-differs? "tests/fixtures/gfm.md" 'html UNSAFE-BASE
                (cfg '(tagfilter) 'unsafe-html? #t)))
(test-assert "tagfilter extension -- our output matches the CLI"
  (agrees? "tests/fixtures/gfm.md" 'html (cfg '(tagfilter) 'unsafe-html? #t)))

;; --- layer 1: every format agrees at the defaults -----------------------
(define DEFAULTS '())

(test-equal "default options agree with the CLI in html"
  #f (mismatch "tests/fixtures/gfm.md" 'html DEFAULTS DEFAULTS))
(test-equal "default options agree with the CLI in xml"
  #f (mismatch "tests/fixtures/gfm.md" 'xml DEFAULTS DEFAULTS))
(test-equal "default options agree with the CLI in commonmark"
  #f (mismatch "tests/fixtures/gfm.md" 'commonmark DEFAULTS DEFAULTS))
(test-equal "default options agree with the CLI in plaintext"
  #f (mismatch "tests/fixtures/gfm.md" 'plaintext DEFAULTS DEFAULTS))

(test-end "differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
