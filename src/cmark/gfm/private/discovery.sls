#!r6rs
;;; Runtime resolution of the cmark shared objects.
;;;
;;; Keep this module pure by passing filesystem operations as arguments.
;;; Automatic discovery accepts only versioned core/extension pairs with the
;;; same version in the same directory.
(library (cmark gfm private discovery)
  (export encode-version version->string parse-version-string
          library-file-version core-library-name extensions-library-name
          current-platform current-machine default-candidate-directories
          select-cmark-libraries parse-library-override)
  (import (rnrs)
          (only (chezscheme) machine-type))

  ;; cmark_version() uses this encoding.
  ;; encode-version : exact-integer exact-integer exact-integer exact-integer
  ;;                  -> exact-integer
  (define (encode-version major minor patch gfm)
    (+ (* major #x1000000) (* minor #x10000) (* patch #x100) gfm))

  ;; version->string : exact-integer -> string
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

  ;; Return #f for non-numeric input because callers filter directory listings.
  (define (numeric-string->integer s)
    (and (> (string-length s) 0)
         (let loop ((i 0) (acc 0))
           (cond
             ((= i (string-length s)) acc)
             ((char<=? #\0 (string-ref s i) #\9)
              (loop (+ i 1) (+ (* acc 10) (- (char->integer (string-ref s i))
                                             (char->integer #\0)))))
             (else #f)))))

  ;; parse-version-string : string -> (or exact-integer #f)
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

  ;; The separator prevents the core prefix from matching extension files.
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

  ;; library-file-version : string symbol symbol -> (or exact-integer #f)
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

  ;; Scan one machine-derived triple; trying every multiarch directory risks
  ;; loading the wrong architecture.
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

  ;; machine-type's leading `t` marks a threaded build, not the architecture.
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

  ;; Compare numerically: lexical order puts gfm.9 above gfm.13.
  (define (maximum lst)
    (fold-left (lambda (a b) (if (> b a) b a)) (car lst) (cdr lst)))

  (define (path-join dir name) (string-append dir "/" name))

  ;; select-cmark-libraries : procedure procedure list pair symbol
  ;;                          -> (values symbol object)
  ;; Status is 'found, 'not-found, or 'out-of-range.
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

  ;; Classify by basename; directory names may also contain
  ;; "cmark-gfm-extensions" and would swap the pair.
  (define (basename p)
    (let loop ((i (- (string-length p) 1)))
      (cond
        ((< i 0) p)
        ((char=? #\/ (string-ref p i)) (substring p (+ i 1) (string-length p)))
        (else (loop (- i 1))))))

  (define (extensions-path? p)
    (substring-search "cmark-gfm-extensions" (basename p)))

  ;; parse-library-override : (or string #f) procedure -> (values symbol object)
  ;; Overrides may use unversioned symlinks; runtime version checking follows
  ;; the load. Entry order is irrelevant because basenames identify each role.
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
