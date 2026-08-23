#!r6rs
;; NOT pure: reads and writes files. The imperative shell around the pure
;; (site render) pipeline -- this library owns the only filesystem access
;; the site generator makes.
(library (site io)
  (export read-site-inputs write-site)
  (import (rnrs) (site pages) (site render) (site serializer))

  (define (slurp path)
    (call-with-input-file path
      (lambda (p)
        (let loop ((cs '()) (c (get-char p)))
          (if (eof-object? c) (list->string (reverse cs)) (loop (cons c cs) (get-char p)))))))

  ;; Every page but the home page lives under docs/; the home page is
  ;; authored beside the generator itself, not in the docs/ reference set.
  (define (source-path name)
    (if (string=? name "index.md") "site/index.md" (string-append "docs/" name)))

  ;; (site pages)'s `pages` is the single source of order AND file set --
  ;; read every source in that order, into (name . markdown-string) pairs.
  (define (read-site-inputs)
    (map (lambda (entry) (let ((name (car entry))) (cons name (slurp (source-path name)))))
         pages))

  (define (html-name name)
    (string-append (substring name 0 (- (string-length name) 3)) ".html"))

  ;; `make site` reruns into a `build/site` that may already hold a
  ;; previous run's output, so every write must overwrite rather than fail
  ;; when the target already exists. (file-options no-fail), with no
  ;; `no-truncate`, both permits and truncates on an existing file --
  ;; verified empirically (a second, shorter write leaves no trailing bytes
  ;; from the first). Writing goes through a binary port and explicit
  ;; `string->utf8` rather than a textual port's transcoder, mirroring
  ;; tests/test-ast-differential.sps's write-fixture and
  ;; tests/test-sxml-differential.sps's write-file: a transcoder can
  ;; translate line endings on the way to disk (native eol-style is CRLF on
  ;; Windows), which for those suites would corrupt a byte-exact fixture,
  ;; and here would make the shipped HTML depend on the host that built it.
  (define (write-site result out-dir)
    (for-each
      (lambda (pg)
        (let ((p (open-file-output-port
                   (string-append out-dir "/" (html-name (car pg)))
                   (file-options no-fail))))
          (put-bytevector p (string->utf8 (string-append "<!doctype html>\n" (sxml->html (cdr pg)))))
          (close-port p)))
      (site-result-pages result))))
