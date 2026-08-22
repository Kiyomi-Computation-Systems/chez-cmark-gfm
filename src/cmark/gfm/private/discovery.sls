#!r6rs
;;; Runtime resolution of the cmark shared objects.
;;;
;;; PURE. Imports nothing that can reach a shared object, and takes its
;;; filesystem access as arguments, so every branch below is unit-testable
;;; against synthetic listings with no files on disk. That is the same reason
;;; resolve-shim-path was an exported procedure rather than a bare expression.
;;;
;;; Only VERSIONED filenames are candidates, and core and extensions must pair
;;; at the SAME version in the SAME directory. Three separate hazards depend on
;;; that rule; see the design spec 3.1 before relaxing any part of it.
(library (cmark gfm private discovery)
  (export encode-version version->string parse-version-string
          library-file-version core-library-name extensions-library-name
          current-platform current-machine default-candidate-directories
          select-cmark-libraries parse-library-override)
  (import (rnrs)
          (only (chezscheme) machine-type))

  ;; cmark's own encoding: cmark_version() returns exactly this.
  (define (encode-version major minor patch gfm)
    (+ (* major #x1000000) (* minor #x10000) (* patch #x100) gfm))

  (define (version->string v)
    (string-append
     (number->string (div v #x1000000)) "."
     (number->string (mod (div v #x10000) #x100)) "."
     (number->string (mod (div v #x100) #x100)) ".gfm."
     (number->string (mod v #x100))))

  (define (string-split s ch)
    (let loop ((i 0) (start 0) (acc '()))
      (cond
        ((= i (string-length s)) (reverse (cons (substring s start i) acc)))
        ((char=? (string-ref s i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
        (else (loop (+ i 1) start acc)))))

  ;; #f rather than an error for any non-numeric input: callers are filtering
  ;; directory listings, where a non-match is ordinary, not exceptional.
  (define (numeric-string->integer s)
    (and (> (string-length s) 0)
         (let loop ((i 0) (acc 0))
           (cond
             ((= i (string-length s)) acc)
             ((char<=? #\0 (string-ref s i) #\9)
              (loop (+ i 1) (+ (* acc 10) (- (char->integer (string-ref s i))
                                             (char->integer #\0)))))
             (else #f)))))

  (define (parse-version-string s)
    (let ((parts (string-split s #\.)))
      (and (= 5 (length parts))
           (string=? "gfm" (list-ref parts 3))
           (let ((m (numeric-string->integer (list-ref parts 0)))
                 (n (numeric-string->integer (list-ref parts 1)))
                 (p (numeric-string->integer (list-ref parts 2)))
                 (g (numeric-string->integer (list-ref parts 4))))
             (and m n p g
                  (< m 256) (< n 256) (< p 256) (< g 256)
                  (encode-version m n p g))))))

  (define (string-prefix? p s)
    (and (>= (string-length s) (string-length p))
         (string=? p (substring s 0 (string-length p)))))

  (define (string-suffix? q s)
    (and (>= (string-length s) (string-length q))
         (string=? q (substring s (- (string-length s) (string-length q))
                                (string-length s)))))

  (define (base-name kind)
    (if (eq? kind 'core) "libcmark-gfm" "libcmark-gfm-extensions"))

  ;; The separator is what keeps the core shape from matching the extensions
  ;; file: "libcmark-gfm." does not prefix "libcmark-gfm-extensions...".
  (define (name-prefix kind platform)
    (string-append (base-name kind) (if (eq? platform 'linux) ".so." ".")))

  (define (name-suffix platform)
    (if (eq? platform 'linux) "" ".dylib"))

  (define (core-library-name v platform)
    (string-append (name-prefix 'core platform) (version->string v)
                   (name-suffix platform)))

  (define (extensions-library-name v platform)
    (string-append (name-prefix 'extensions platform) (version->string v)
                   (name-suffix platform)))

  ;; -> encoded version, or #f when `name` is not a versioned library of `kind`
  (define (library-file-version name kind platform)
    (let ((p (name-prefix kind platform))
          (q (name-suffix platform)))
      (and (string-prefix? p name)
           (string-suffix? q name)
           (>= (string-length name) (+ (string-length p) (string-length q)))
           (parse-version-string
            (substring name (string-length p)
                       (- (string-length name) (string-length q)))))))

  (define (current-machine) (symbol->string (machine-type)))

  (define (current-platform)
    (if (string-suffix? "osx" (current-machine)) 'macos 'linux))

  (define (default-candidate-directories platform machine list-dir dir?)
    (if (eq? platform 'macos)
        '("/opt/homebrew/lib" "/usr/local/lib" "/opt/local/lib")
        (append '("/usr/local/lib")
                (linux-triple-directories machine list-dir dir?)
                '("/usr/lib" "/usr/lib64"))))

  ;; One derived triple rather than every triple present: on a multiarch box,
  ;; scanning all of them would eventually attempt a wrong-architecture load,
  ;; and there is deliberately no fall-through on load failure.
  (define (linux-triple-directories stem list-dir dir?)
    (cond
      ((known-triple stem) => (lambda (t) (list (string-append "/usr/lib/" t))))
      (else
       (if (dir? "/usr/lib")
           (map (lambda (d) (string-append "/usr/lib/" d))
                (list-sort string<?
                           (filter (lambda (d)
                                     (or (string-suffix? "-linux-gnu" d)
                                         (string-suffix? "-linux-musl" d)))
                                   (list-dir "/usr/lib"))))
           '()))))

  ;; machine-type is like ta6le / tarm64le; the leading `t` marks a threaded
  ;; build and is not part of the architecture.
  (define (known-triple stem)
    (let ((arch (if (string-prefix? "t" stem)
                    (substring stem 1 (string-length stem))
                    stem)))
      (let loop ((table '(("a6" . "x86_64-linux-gnu")
                          ("arm64" . "aarch64-linux-gnu")
                          ("i3" . "i386-linux-gnu")
                          ("ppc64le" . "powerpc64le-linux-gnu")
                          ("rv64" . "riscv64-linux-gnu"))))
        (cond
          ((null? table) #f)
          ((string-prefix? (caar table) arch) (cdar table))
          (else (loop (cdr table)))))))

  (define (versions-of names kind platform)
    (let loop ((ns names) (acc '()))
      (cond
        ((null? ns) acc)
        ((library-file-version (car ns) kind platform)
         => (lambda (v) (loop (cdr ns) (cons v acc))))
        (else (loop (cdr ns) acc)))))

  (define (intersect a b) (filter (lambda (x) (memv x b)) a))

  ;; Numeric, not lexical. "libcmark-gfm.so.0.29.0.gfm.9" sorts ABOVE
  ;; "...gfm.13" as a string, which would select the older library.
  (define (maximum lst)
    (fold-left (lambda (a b) (if (> b a) b a)) (car lst) (cdr lst)))

  (define (path-join dir name) (string-append dir "/" name))

  ;; -> (values 'found (core . ext)) | (values 'not-found #f)
  ;;  | (values 'out-of-range encoded-version)
  ;;
  ;; Two values rather than one overloaded return: a success pair and an
  ;; out-of-range pair would otherwise be told apart only by the car's type.
  (define (select-cmark-libraries list-dir dir? candidates range platform)
    (let ((lo (car range)) (hi (cdr range)))
      (let loop ((dirs candidates) (seen '()))
        (if (null? dirs)
            (if (null? seen)
                (values 'not-found #f)
                (values 'out-of-range (maximum seen)))
            (let ((d (car dirs)))
              (if (not (dir? d))
                  (loop (cdr dirs) seen)
                  (let* ((names (list-dir d))
                         (both (intersect (versions-of names 'core platform)
                                          (versions-of names 'extensions platform)))
                         (ok (filter (lambda (v) (and (>= v lo) (<= v hi))) both)))
                    (cond
                      ((pair? ok)
                       (let ((v (maximum ok)))
                         (values 'found
                                 (cons (path-join d (core-library-name v platform))
                                       (path-join d (extensions-library-name v platform))))))
                      ((pair? both) (loop (cdr dirs) (append both seen)))
                      (else (loop (cdr dirs) seen))))))))))

  (define (absolute? p)
    (and (> (string-length p) 0) (char=? #\/ (string-ref p 0))))

  (define (substring-search needle hay)
    (let ((n (string-length needle)) (h (string-length hay)))
      (let loop ((i 0))
        (cond
          ((> (+ i n) h) #f)
          ((string=? needle (substring hay i (+ i n))) #t)
          (else (loop (+ i 1)))))))

  ;; Classify by BASENAME, not the whole path. A core library sitting in a
  ;; directory whose name happens to contain "cmark-gfm-extensions" would
  ;; otherwise be classified as the extensions library and silently swapped
  ;; with its partner -- both files exist and both are absolute, so nothing
  ;; downstream would notice. Demonstrated: whole-path matching accepts
  ;; "/home/u/cmark-gfm-extensions-cache/renamed-core.so:/home/u/other/renamed-ext.so"
  ;; as valid with the pair reversed.
  (define (basename p)
    (let loop ((i (- (string-length p) 1)))
      (cond
        ((< i 0) p)
        ((char=? #\/ (string-ref p i)) (substring p (+ i 1) (string-length p)))
        (else (loop (- i 1))))))

  (define (extensions-path? p)
    (substring-search "cmark-gfm-extensions" (basename p)))

  ;; -> (values 'ok (core . ext)) | (values 'invalid #f)
  ;;
  ;; No version parsing: an explicit override may legitimately name the
  ;; unversioned symlinks from a -dev package. Selection is the user's;
  ;; verification is still ours, via cmark_version() after the load.
  ;;
  ;; Order in the variable does not matter -- each entry is classified by
  ;; basename -- so a swapped value is not a silent misload.
  (define (parse-library-override str regular-file?)
    (if (or (not str) (string=? str ""))
        (values 'invalid #f)
        (let ((parts (string-split str #\:)))
          (if (not (= 2 (length parts)))
              (values 'invalid #f)
              (let ((a (car parts)) (b (cadr parts)))
                (if (not (and (absolute? a) (absolute? b)
                              (regular-file? a) (regular-file? b)))
                    (values 'invalid #f)
                    (let ((a-ext? (extensions-path? a))
                          (b-ext? (extensions-path? b)))
                      (cond
                        ((and b-ext? (not a-ext?)) (values 'ok (cons a b)))
                        ((and a-ext? (not b-ext?)) (values 'ok (cons b a)))
                        (else (values 'invalid #f)))))))))))
