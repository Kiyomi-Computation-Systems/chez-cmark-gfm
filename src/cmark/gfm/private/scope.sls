#!r6rs
;;; Native document lifecycle.
;;;
;;; This library is the SOLE owner of native teardown. Two invariants matter
;;; more than anything else here:
;;;
;;;   1. The parser outlives rendering (ADR-0005). cmark_parser_free calls
;;;      cmark_llist_free on parser->syntax_extensions, which is the same
;;;      list cmark_render_html receives -- so freeing the parser first
;;;      leaves the renderer holding a dangling list.
;;;
;;;   2. dynamic-wind alone is not enough (ADR-0006). It handles non-local
;;;      escape, but a continuation captured inside the body and reinvoked
;;;      after teardown would re-enter with freed pointers. The alive? flag
;;;      plus checked accessors turn that into a condition.
(library (cmark gfm private scope)
  (export call-with-native-document
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
            option-bits                 ; immutable; for the renderer (design spec 5.1)
            (mutable extensions)))

  ;; --- checked accessors ----------------------------------------------
  ;; Nothing outside this library reads a field directly, and nothing
  ;; inside it reads one without going through here.
  (define (check-alive h)
    (unless (and (native-doc? h) (native-doc-alive? h))
      (raise (make-cmark-dead-document))))

  (define (doc-root h)        (check-alive h) (native-doc-root h))
  (define (doc-parser h)      (check-alive h) (native-doc-parser h))
  (define (doc-extensions h)  (check-alive h) (native-doc-extensions h))
  (define (doc-option-bits h) (check-alive h) (native-doc-option-bits h))

  ;; --- input validation ------------------------------------------------
  ;; Embedded NUL is rejected because downstream accessors return
  ;; NUL-terminated C strings and would silently truncate. The size limit is
  ;; measured in BYTES after encoding, never in characters: it is the only
  ;; pre-allocation defence, and cmark is fed a byte count.
  (define (validate-markdown-input markdown max-bytes)
    (unless (string? markdown)
      (raise (make-cmark-invalid-input 'not-a-string)))
    (let loop ((i 0))
      (cond
        ((= i (string-length markdown))
         (let ((bv (string->utf8 markdown)))
           (if (> (bytevector-length bv) max-bytes)
               (raise (make-cmark-invalid-input 'too-large))
               bv)))
        ((char=? #\nul (string-ref markdown i))
         (raise (make-cmark-invalid-input 'embedded-nul)))
        (else (loop (+ i 1))))))

  ;; extension-names has to be validated before any native resource is
  ;; acquired. find-extension's FFI binding is declared (string): a
  ;; non-string element would otherwise reach it from inside acquire!'s
  ;; for-each, which runs after count-parser-new! and before dynamic-wind
  ;; is established -- raising there leaks the parser and surfaces a raw
  ;; Chez FFI type error instead of a structured condition. Checking every
  ;; element up front means a bad name is rejected before anything at all
  ;; is allocated, so there is nothing for release! to clean up.
  (define (validate-extension-names names)
    (for-each
     (lambda (name)
       (unless (string? name)
         (raise (make-cmark-invalid-input 'extension-name-not-a-string))))
     names)
    names)

  ;; --- acquisition ------------------------------------------------------
  ;; Ordering matters: the handle is created BEFORE extensions are attached,
  ;; so that if attachment fails the release path already has the parser to
  ;; free. Building the handle late would leak the parser on that path.
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
               ;; Free before raising: the scope's after-thunk has not been
               ;; established yet, so cleanup is this procedure's duty.
               (release! h)
               (raise (make-cmark-extension-unavailable name)))
             ;; The return value is not an error channel:
             ;; cmark_parser_attach_syntax_extension has a single `return 1`
             ;; and cannot fail. The real failure mode is the NULL check above.
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

  ;; --- release ----------------------------------------------------------
  ;; Idempotent by construction: alive? is cleared FIRST, so a second call
  ;; (cleanup triggered during cleanup) does nothing. Each pointer is nulled
  ;; immediately after being freed.
  (define (release! h)
    (when (native-doc-alive? h)
      (native-doc-alive?-set! h #f)
      ;; Reverse acquisition order. The extension list is borrowed from the
      ;; parser and must NOT be freed here.
      (native-doc-extensions-set! h 0)
      (let ((root (native-doc-root h)))
        (unless (zero? root)
          (node-free root)
          (count-root-free!)
          (native-doc-root-set! h 0)))
      (let ((p (native-doc-parser h)))
        (unless (zero? p)
          ;; LAST, per ADR-0005.
          (parser-free p)
          (count-parser-free!)
          (native-doc-parser-set! h 0)))))

  ;; --- the scope --------------------------------------------------------
  ;; max-bytes is optional and defaults to default-max-input-bytes, so
  ;; existing 4-argument callers keep the design spec 5.5 pre-allocation
  ;; defence rather than losing it silently.
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
             ;; Re-entry via a captured continuation lands here. The document
             ;; is gone and cannot be rebuilt, so refuse rather than proceed.
             (unless (native-doc-alive? h)
               (raise (make-cmark-dead-document))))
           (lambda () (proc h))
           (lambda () (release! h))))))))
