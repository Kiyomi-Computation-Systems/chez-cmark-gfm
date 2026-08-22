#!r6rs
;;; The Scheme option-bit table against its two oracles.
;;;
;;; A C wrapper used to build this mask, so the constants could not drift
;;; from the headers. With the table in Scheme that guarantee becomes a test,
;;; and this is it. Five of the six bits are ALSO covered behaviourally by
;;; tests/test-differential.sps; validate-utf8 is unreachable through the
;;; public API and has no other coverage at all, which is why the header
;;; parity check below is not optional.
(import (rnrs)
        (srfi :64)
        (cmark gfm private native))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "option-bits")

(define HEADER "vendor/cmark-gfm/src/cmark-gfm.h")

;; Reads `#define CMARK_OPT_NAME (1 << N)` and `#define CMARK_OPT_NAME 0`.
;; Deliberately narrow: anything it cannot parse is skipped, and a name that
;; never appears yields #f, which fails the assertion rather than passing
;; vacuously.
(define (header-constant name)
  (and (file-exists? HEADER)
       (let ((needle (string-append "#define " name " ")))
         (call-with-input-file HEADER
           (lambda (port)
             (let loop ()
               (let ((line (get-line port)))
                 (cond
                   ((eof-object? line) #f)
                   ((and (>= (string-length line) (string-length needle))
                         (string=? needle (substring line 0 (string-length needle))))
                    (parse-value (substring line (string-length needle)
                                            (string-length line))))
                   (else (loop))))))))))

(define (parse-value s)
  ;; either "0" or "(1 << N)"
  (let ((digits (lambda (str)
                  (let loop ((i 0) (acc #f))
                    (cond
                      ((= i (string-length str)) acc)
                      ((char<=? #\0 (string-ref str i) #\9)
                       (loop (+ i 1) (+ (* (or acc 0) 10)
                                        (- (char->integer (string-ref str i))
                                           (char->integer #\0)))))
                      ((and acc (char=? (string-ref str i) #\))) acc)
                      ;; Reset, not carry: a non-digit boundary separates the
                      ;; literal "1" being shifted from the shift amount N
                      ;; that follows "<< ". Carrying acc through would
                      ;; concatenate the two digit runs into one number (e.g.
                      ;; "(1 << 17)" reading as 117 instead of 17).
                      (else (loop (+ i 1) #f)))))))
    (if (and (> (string-length s) 0) (char=? #\( (string-ref s 0)))
        (bitwise-arithmetic-shift-left 1 (digits s))
        (digits s))))

(test-assert "the vendored header is present"
  (file-exists? HEADER))

(test-equal "CMARK_OPT_DEFAULT"       (header-constant "CMARK_OPT_DEFAULT")       cmark-opt-default)
(test-equal "CMARK_OPT_SOURCEPOS"     (header-constant "CMARK_OPT_SOURCEPOS")     cmark-opt-sourcepos)
(test-equal "CMARK_OPT_HARDBREAKS"    (header-constant "CMARK_OPT_HARDBREAKS")    cmark-opt-hardbreaks)
(test-equal "CMARK_OPT_NOBREAKS"      (header-constant "CMARK_OPT_NOBREAKS")      cmark-opt-nobreaks)
(test-equal "CMARK_OPT_VALIDATE_UTF8" (header-constant "CMARK_OPT_VALIDATE_UTF8") cmark-opt-validate-utf8)
(test-equal "CMARK_OPT_SMART"         (header-constant "CMARK_OPT_SMART")         cmark-opt-smart)
(test-equal "CMARK_OPT_UNSAFE"        (header-constant "CMARK_OPT_UNSAFE")        cmark-opt-unsafe)

;; Structural properties, kept from tests/test-native.sps. Against a
;; Scheme-defined table these are weak on their own -- they compare the table
;; with itself -- which is exactly why the header parity above carries the
;; real weight.
(test-assert "the six flags set six distinct non-zero bits"
  (let ((flags (list cmark-opt-validate-utf8 cmark-opt-sourcepos
                     cmark-opt-hardbreaks cmark-opt-nobreaks
                     cmark-opt-smart cmark-opt-unsafe)))
    (and (for-all (lambda (f) (> f 0)) flags)
         (= 6 (length flags))
         (= (fold-left bitwise-ior 0 flags)
            (fold-left + 0 flags)))))   ; disjoint iff ior equals sum

(test-assert "option-bits composes by ior"
  (= (option-bits #t #t #f #f #f #f)
     (bitwise-ior (option-bits #t #f #f #f #f #f)
                  (option-bits #f #t #f #f #f #f))))

(test-equal "all flags off is zero" 0 (option-bits #f #f #f #f #f #f))

(test-end "option-bits")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
