#!r6rs
;;; Parses cmark's own spec files into their Markdown examples. TEST ONLY.
;;;
;;; Transcribed from vendor/cmark-gfm/test/spec_tests.py:89-120. Five
;;; details, each of which corrupts the corpus silently if missed:
;;;
;;;   1. The opening fence is EXACTLY 32 backticks followed by " example".
;;;      A looser pattern matches fenced code blocks inside the prose.
;;;   2. The closing fence is a line that strips to exactly 32 backticks.
;;;   3. The separator is a line that strips to exactly ".".
;;;   4. Lines are compared STRIPPED but accumulated RAW, newline included.
;;;   5. U+2192 (RIGHT ARROW) stands for a tab and must be replaced. Miss
;;;      this and the tab examples still pass the differential, because both
;;;      sides receive the same wrong input.
;;;
;;; The per-example extension labels after " example" are deliberately
;;; ignored, and `disabled` examples are deliberately KEPT. Both matter only
;;; to a harness comparing against the file's expected HTML; ours compares
;;; against the pinned library, so every example is a usable input.
(library (spec-corpus)
  (export spec-examples)
  (import (rnrs))

  (define fence (make-string 32 #\`))
  (define open-prefix (string-append fence " example"))

  (define (strip s)
    (let* ((n (string-length s))
           (start (let loop ((i 0))
                    (if (and (< i n) (char-whitespace? (string-ref s i)))
                        (loop (+ i 1)) i)))
           (end (let loop ((i n))
                  (if (and (> i start) (char-whitespace? (string-ref s (- i 1))))
                      (loop (- i 1)) i))))
      (substring s start end)))

  (define (prefix? p s)
    (and (>= (string-length s) (string-length p))
         (string=? p (substring s 0 (string-length p)))))

  (define (arrows->tabs s)
    (list->string
     (map (lambda (c) (if (char=? c #\x2192) #\tab c)) (string->list s))))

  (define (read-lines path)
    (let ((p (open-file-input-port path (file-options)
                                   (buffer-mode block)
                                   (make-transcoder (utf-8-codec) (eol-style none)))))
      (let loop ((acc '()))
        (let ((l (get-line p)))
          (if (eof-object? l)
              (begin (close-port p) (reverse acc))
              (loop (cons (string-append l "\n") acc)))))))

  (define (spec-examples path)
    (let loop ((lines (read-lines path)) (state 'text) (cur '()) (out '()))
      (cond
        ((null? lines) (reverse out))
        (else
         (let* ((raw (car lines))
                (l   (strip raw))
                (rest (cdr lines)))
           (cond
             ((prefix? open-prefix l) (loop rest 'markdown '() out))
             ((string=? fence l)
              (loop rest 'text '()
                    (if (eq? state 'text)
                        out
                        (cons (arrows->tabs (apply string-append (reverse cur)))
                              out))))
             ((and (string=? "." l) (eq? state 'markdown))
              ;; The HTML side is read and discarded: our oracle is the
              ;; pinned library, not the file. Switching state rather than
              ;; skipping keeps the state machine identical to
              ;; spec_tests.py's, which is what makes the counts match.
              (loop rest 'html cur out))
             ((eq? state 'markdown) (loop rest state (cons raw cur) out))
             (else (loop rest state cur out)))))))))
