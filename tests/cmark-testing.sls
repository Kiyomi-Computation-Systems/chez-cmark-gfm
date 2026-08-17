#!r6rs
;;; Helpers shared by the two differential suites.
;;;
;;; Only genuinely generic operations live here: read a file, find a
;;; substring, run a command and capture its bytes. Suite-specific logic --
;;; notably each suite's options-to-CLI-flags mapping -- stays in the suite,
;;; because the two differ (Stage 2's is per-format, Stage 3's is xml-only)
;;; and coupling them would stop either from changing independently.
;;;
;;; This library is test-only and deliberately NOT under src/. It is reachable
;;; because the Makefile puts tests/ on CHEZ_LIBDIRS.
(library (cmark-testing)
  (export file->bytevector string-contains? capture-command)
  (import (rnrs)
          (only (chezscheme) system))

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

  ;; Runs cmd with stdout redirected to out-path, then returns the captured
  ;; bytes. A non-zero exit is an ERROR, not an empty result: a silently
  ;; empty capture would make a byte comparison pass against a CLI that
  ;; never ran.
  ;;
  ;; merge-stderr? exists because redirection order matters and callers
  ;; cannot fix it from inside the command string: "cmd 2>&1 > out
  ;; 2>/dev/null" sends stderr to the terminal, not the file, because 2>&1
  ;; duplicates whatever stdout is at that moment. The version probe wants
  ;; both streams, because a loader or link failure reports on stderr and is
  ;; the whole diagnostic.
  (define capture-command
    (case-lambda
      ((cmd out-path) (capture-command cmd out-path #f))
      ((cmd out-path merge-stderr?)
       (let ((rc (system (string-append cmd " > " out-path
                                        (if merge-stderr? " 2>&1" " 2>/dev/null")))))
         (unless (zero? rc)
           (error 'capture-command "command failed" cmd rc))
         (file->bytevector out-path))))))
