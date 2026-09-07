#!r6rs
;;; Native document lifecycle.
;;;
;;; This is the sole owner of native teardown. The parser must outlive
;;; rendering because freeing it also frees the renderer's extension list.
;;; dynamic-wind handles escape but not continuation re-entry after teardown;
;;; checked accessors reject that re-entry through the alive? flag.
(library (cmark gfm private scope)
  (export call-with-native-document
          call-with-render-buffer
          native-doc?
          doc-root doc-parser doc-extensions doc-option-bits
          validate-markdown-input
          default-max-input-bytes)
  (import (rnrs)
          (cmark gfm private native)
          (cmark gfm private limits)
          (cmark gfm private conditions))

  (define-record-type native-doc
    (fields (mutable parser)
            (mutable root)
            (mutable alive?)
            option-bits                 ; immutable; retained for rendering
            (mutable extensions)))

  ;; Never expose unchecked native fields outside this library.
  (define (check-alive h)
    (unless (and (native-doc? h) (native-doc-alive? h))
      (raise (make-cmark-dead-document))))

  (define (doc-root h)        (check-alive h) (native-doc-root h))
  (define (doc-parser h)      (check-alive h) (native-doc-parser h))
  (define (doc-extensions h)  (check-alive h) (native-doc-extensions h))
  (define (doc-option-bits h) (check-alive h) (native-doc-option-bits h))

  ;; Embedded NUL would truncate later C-string reads. Measure the allocation
  ;; limit in UTF-8 bytes, matching the byte count passed to cmark.
  (define (validate-markdown-input markdown max-bytes)
    (unless (string? markdown)
      (raise (make-cmark-invalid-input 'not-a-string)))
    (let loop ((i 0))
      (cond
        ((= i (string-length markdown))
         (let ((bv (string->utf8 markdown)))
           (if (> (bytevector-length bv) max-bytes)
               (raise (make-cmark-resource-limit 'too-large max-bytes))
               bv)))
        ((char=? #\nul (string-ref markdown i))
         (raise (make-cmark-invalid-input 'embedded-nul)))
        (else (loop (+ i 1))))))

  ;; Validate names before parser allocation; find-extension's FFI type error
  ;; would otherwise escape before dynamic-wind establishes cleanup.
  (define (validate-extension-names names)
    (for-each
     (lambda (name)
       (unless (string? name)
         (raise (make-cmark-invalid-input 'extension-name-not-a-string))))
     names)
    names)

  ;; Create the handle before attaching extensions so release! can clean up an
  ;; attachment failure.
  (define (acquire! bytes option-bits extension-names)
    (ensure-native-loaded!)
    (let ((p (parser-new option-bits)))
      (when (zero? p)
        (raise (make-cmark-error)))
      (count-parser-new!)
      (let ((h (make-native-doc p 0 #t option-bits 0)))
        (for-each
         (lambda (name)
           (let ((ext (find-extension name)))
             (when (zero? ext)
               ;; dynamic-wind is not established yet.
               (release! h)
               (raise (make-cmark-extension-unavailable name)))
             ;; attach-extension always returns 1; the NULL check is the only
             ;; failure channel.
             (attach-extension p ext)))
         extension-names)
        (parser-feed p bytes (bytevector-length bytes))
        (let ((root (parser-finish p)))
          (when (zero? root)
            (release! h)
            (raise (make-cmark-error)))
          (count-root-new!)
          (native-doc-root-set! h root)
          ;; Borrowed from the parser; valid only while the parser lives.
          (native-doc-extensions-set! h (parser-get-syntax-extensions p))
          h))))

  ;; Clear alive? first and zero freed pointers to make cleanup idempotent.
  (define (release! h)
    (when (native-doc-alive? h)
      (native-doc-alive?-set! h #f)
      ;; The extension list is borrowed from the parser; never free it here.
      (native-doc-extensions-set! h 0)
      (let ((root (native-doc-root h)))
        (unless (zero? root)
          (node-free root)
          (count-root-free!)
          (native-doc-root-set! h 0)))
      (let ((p (native-doc-parser h)))
        (unless (zero? p)
          ;; Free the parser last; it owns the extension list.
          (parser-free p)
          (count-parser-free!)
          (native-doc-parser-set! h 0)))))

  ;; call-with-native-document : string integer (listof string) procedure
  ;;                             [exact-positive-integer] -> object
  (define call-with-native-document
    (case-lambda
      ((markdown option-bits extension-names proc)
       (call-with-native-document markdown option-bits extension-names proc
                                   default-max-input-bytes))
      ((markdown option-bits extension-names proc max-bytes)
       (let* ((bytes (validate-markdown-input markdown max-bytes))
              (names (validate-extension-names extension-names))
              (h (acquire! bytes option-bits names)))
         (dynamic-wind
           (lambda ()
             ;; A captured continuation can re-enter after teardown.
             (unless (native-doc-alive? h)
               (raise (make-cmark-dead-document))))
           (lambda () (proc h))
           (lambda () (release! h)))))))

  ;; Renderer buffers are caller-owned but allocated by cmark; libc free is
  ;; invalid. The address never reaches caller code, and zeroing it after free
  ;; makes cleanup idempotent.
  (define (call-with-render-buffer format make-buffer)
    (let ((buf (make-buffer)))
      (when (zero? buf)
        (raise (make-cmark-render-failed format)))
      (count-buffer-new!)
      (dynamic-wind
        (lambda () #f)
        (lambda () (c-string->string buf))
        (lambda ()
          (unless (zero? buf)
            (free-buffer buf)
            (count-buffer-free!)
            (set! buf 0)))))))
