#!r6rs
(import (rnrs)
        (srfi :64)
        (cmark gfm private discovery))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "discovery")

(define RANGE '(#x001d0000 . #x001dffff))

;; --- version encoding round-trips against cmark's own scheme -----------
;; #x001D000D is what cmark_version() returns for 0.29.0.gfm.13; the encode
;; here must agree with it or every range check is meaningless.
(test-equal "encode matches cmark_version" #x001D000D (encode-version 0 29 0 13))
(test-equal "version->string" "0.29.0.gfm.13" (version->string #x001D000D))
(test-equal "parse round-trips" #x001D000D (parse-version-string "0.29.0.gfm.13"))
(test-assert "four components is not a version" (not (parse-version-string "0.29.0.13")))
(test-assert "missing gfm literal rejected" (not (parse-version-string "0.29.0.xyz.13")))
(test-assert "non-numeric component rejected" (not (parse-version-string "0.29.0.gfm.x")))

;; --- names ------------------------------------------------------------
(test-equal "linux core name" "libcmark-gfm.so.0.29.0.gfm.13"
  (core-library-name #x001D000D 'linux))
(test-equal "linux extensions name" "libcmark-gfm-extensions.so.0.29.0.gfm.13"
  (extensions-library-name #x001D000D 'linux))
(test-equal "macos core name" "libcmark-gfm.0.29.0.gfm.13.dylib"
  (core-library-name #x001D000D 'macos))
(test-equal "macos extensions name" "libcmark-gfm-extensions.0.29.0.gfm.13.dylib"
  (extensions-library-name #x001D000D 'macos))

;; The core prefix must not swallow the extensions file. On both platforms the
;; character after "libcmark-gfm" is what separates them.
(test-assert "core shape does not match extensions file (linux)"
  (not (library-file-version "libcmark-gfm-extensions.so.0.29.0.gfm.13" 'core 'linux)))
(test-assert "core shape does not match extensions file (macos)"
  (not (library-file-version "libcmark-gfm-extensions.0.29.0.gfm.13.dylib" 'core 'macos)))

;; Unversioned names are invisible to the search ON PURPOSE (spec 3.7): this
;; is one of three things keeping macOS's shared-cache copy unreachable.
(test-assert "unversioned .so is not a candidate"
  (not (library-file-version "libcmark-gfm.so" 'core 'linux)))
(test-assert "unversioned .dylib is not a candidate"
  (not (library-file-version "libcmark-gfm.dylib" 'core 'macos)))

;; --- selection, against synthetic listings ----------------------------
(define (fs-list alist) (lambda (d) (cond ((assoc d alist) => cdr) (else '()))))
(define (fs-dir? alist) (lambda (d) (and (assoc d alist) #t)))
(define (sel alist dirs)
  (let-values (((status payload)
                (select-cmark-libraries (fs-list alist) (fs-dir? alist)
                                        dirs RANGE 'linux)))
    (list status payload)))
(define (pair-at v)
  (list (string-append "libcmark-gfm.so." v)
        (string-append "libcmark-gfm-extensions.so." v)))
(define (found-at d v)
  (list 'found (cons (string-append d "/libcmark-gfm.so." v)
                     (string-append d "/libcmark-gfm-extensions.so." v))))

(test-equal "empty directory" '(not-found #f) (sel '(("/a")) '("/a")))
(test-equal "absent directory" '(not-found #f) (sel '() '("/a")))
(test-equal "core without extensions is not a pair" '(not-found #f)
  (sel '(("/a" "libcmark-gfm.so.0.29.0.gfm.13")) '("/a")))
(test-equal "extensions without core is not a pair" '(not-found #f)
  (sel '(("/a" "libcmark-gfm-extensions.so.0.29.0.gfm.13")) '("/a")))
(test-equal "matched pair is found" (found-at "/a" "0.29.0.gfm.13")
  (sel (list (cons "/a" (pair-at "0.29.0.gfm.13"))) '("/a")))

;; Both of these fail if version comparison is lexical rather than numeric.
;; "9" sorts above "13" as a string, so this is not a hypothetical.
(test-equal "gfm.6 and gfm.13 -> 13" (found-at "/a" "0.29.0.gfm.13")
  (sel (list (cons "/a" (append (pair-at "0.29.0.gfm.6")
                                (pair-at "0.29.0.gfm.13")))) '("/a")))
(test-equal "gfm.9 and gfm.13 -> 13" (found-at "/a" "0.29.0.gfm.13")
  (sel (list (cons "/a" (append (pair-at "0.29.0.gfm.9")
                                (pair-at "0.29.0.gfm.13")))) '("/a")))

;; The double-load hazard (spec 3.1 clause 4): the extensions library carries a
;; DT_NEEDED on the core's FULL versioned SONAME, so a mismatched pair would
;; pull a second cmark core into the process.
(test-equal "skewed core/extensions versions do not pair" '(not-found #f)
  (sel '(("/a" "libcmark-gfm.so.0.29.0.gfm.13"
               "libcmark-gfm-extensions.so.0.29.0.gfm.6")) '("/a")))
(test-equal "unversioned pair does not qualify" '(not-found #f)
  (sel '(("/a" "libcmark-gfm.so" "libcmark-gfm-extensions.so")) '("/a")))

;; A paired-but-unsupported version must say so by name rather than reporting
;; "nothing found", which would send the user looking for a missing package.
(test-equal "only 0.30 present -> out-of-range"
  (list 'out-of-range (encode-version 0 30 0 0))
  (sel (list (cons "/a" (pair-at "0.30.0.gfm.0"))) '("/a")))

(test-equal "first directory with a pair wins" (found-at "/a" "0.29.0.gfm.6")
  (sel (list (cons "/a" (pair-at "0.29.0.gfm.6"))
             (cons "/b" (pair-at "0.29.0.gfm.13"))) '("/a" "/b")))
(test-equal "unpaired first directory falls through" (found-at "/b" "0.29.0.gfm.13")
  (sel (list (cons "/a" '("libcmark-gfm.so.0.29.0.gfm.13"))
             (cons "/b" (pair-at "0.29.0.gfm.13"))) '("/a" "/b")))

;; --- candidate directories --------------------------------------------
(define (no-list d) '())
(define (no-dir d) #f)
(test-equal "macos candidates"
  '("/opt/homebrew/lib" "/usr/local/lib" "/opt/local/lib")
  (default-candidate-directories 'macos "tarm64osx" no-list no-dir))
(test-equal "linux x86_64 triple"
  '("/usr/local/lib" "/usr/lib/x86_64-linux-gnu" "/usr/lib" "/usr/lib64")
  (default-candidate-directories 'linux "ta6le" no-list no-dir))
(test-equal "linux arm64 triple"
  '("/usr/local/lib" "/usr/lib/aarch64-linux-gnu" "/usr/lib" "/usr/lib64")
  (default-candidate-directories 'linux "tarm64le" no-list no-dir))
(test-equal "unknown machine enumerates /usr/lib subdirectories"
  '("/usr/local/lib" "/usr/lib/aarch64-linux-gnu" "/usr/lib/x86_64-linux-musl"
    "/usr/lib" "/usr/lib64")
  (default-candidate-directories 'linux "zz99"
    (lambda (d) '("x86_64-linux-musl" "not-a-triple" "aarch64-linux-gnu"))
    (lambda (d) (string=? d "/usr/lib"))))

;; --- override ---------------------------------------------------------
(define (ov s . rf)
  (let-values (((status payload)
                (parse-library-override s (if (null? rf) (lambda (p) #t) (car rf)))))
    (list status payload)))
(define OK '(ok ("/a/libcmark-gfm.so" . "/a/libcmark-gfm-extensions.so")))

(test-equal "unset override"  '(invalid #f) (ov #f))
(test-equal "empty override"  '(invalid #f) (ov ""))
(test-equal "one entry"       '(invalid #f) (ov "/a/libcmark-gfm.so"))
(test-equal "three entries"   '(invalid #f)
  (ov "/a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so:/c"))
(test-equal "relative path"   '(invalid #f)
  (ov "a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so"))
(test-equal "two cores"       '(invalid #f)
  (ov "/a/libcmark-gfm.so:/b/libcmark-gfm.so"))
(test-equal "two extensions"  '(invalid #f)
  (ov "/a/libcmark-gfm-extensions.so:/b/libcmark-gfm-extensions.so"))
(test-equal "in order" OK (ov "/a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so"))
;; Order must NOT matter: classification is by basename, so a swapped variable
;; is not a footgun (spec 3.5).
(test-equal "swapped order normalises" OK
  (ov "/a/libcmark-gfm-extensions.so:/a/libcmark-gfm.so"))
(test-equal "nonexistent file" '(invalid #f)
  (ov "/a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so" (lambda (p) #f)))

;; Classification reads the BASENAME only. Matching the whole path lets a
;; directory name decide which library is which: the second case below is
;; accepted as valid with the pair REVERSED under whole-path matching, which
;; loads the core as the extensions library and vice versa.
(test-equal "a directory named ...cmark-gfm-extensions... does not reclassify the core"
  '(ok ("/opt/cmark-gfm-extensions-build/libcmark-gfm.so"
        . "/opt/other/libcmark-gfm-extensions.so"))
  (ov "/opt/cmark-gfm-extensions-build/libcmark-gfm.so:/opt/other/libcmark-gfm-extensions.so"))

(test-equal "neither basename identifies itself -> refused, never guessed"
  '(invalid #f)
  (ov "/home/u/cmark-gfm-extensions-cache/renamed-core.so:/home/u/other/renamed-ext.so"))

(test-end "discovery")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
