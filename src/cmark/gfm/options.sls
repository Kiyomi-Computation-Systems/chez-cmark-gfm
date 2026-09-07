#!r6rs
;;; Immutable options. Keep this library's transitive imports free of native
;;; code. Wrap width is a renderer argument, not a parser option.
(library (cmark gfm options)
  (export make-cmark-options default-cmark-options cmark-options-with
          cmark-options?
          cmark-options-extensions
          cmark-options-validate-utf8?
          cmark-options-source-positions?
          cmark-options-hardbreaks?
          cmark-options-nobreaks?
          cmark-options-smart?
          cmark-options-unsafe-html?
          cmark-options-max-input-bytes
          cmark-options-max-nodes
          cmark-options-max-depth
          default-ast-options
          supported-extensions
          extension->native-name
          make-sxml-options default-sxml-options sxml-options-with
          sxml-options? sxml-options-raw-html sxml-options-softbreak
          sxml-options-attribute-marker)
  (import (rnrs)
          (cmark gfm private limits)
          (cmark gfm private conditions))

  ;; Keep public symbols decoupled from cmark's native string names.
  (define extension-names
    '((autolink      . "autolink")
      (strikethrough . "strikethrough")
      (table         . "table")
      (tagfilter     . "tagfilter")
      (tasklist      . "tasklist")))

  ;; supported-extensions : -> (listof symbol)
  (define (supported-extensions) (map car extension-names))

  ;; extension->native-name : symbol -> string
  (define (extension->native-name sym)
    (let ((hit (assq sym extension-names)))
      (if hit
          (cdr hit)
          (raise (make-cmark-invalid-option 'extensions 'unknown-extension)))))

  (define default-extensions '(autolink strikethrough table tagfilter tasklist))

  (define-record-type (cmark-options %make-cmark-options cmark-options?)
    (fields extensions
            validate-utf8?
            source-positions?
            hardbreaks?
            nobreaks?
            smart?
            unsafe-html?
            max-input-bytes
            max-nodes
            max-depth))

  (define option-keys
    '(extensions validate-utf8? source-positions? hardbreaks?
      nobreaks? smart? unsafe-html? max-input-bytes max-nodes max-depth))

  ;; Reject malformed and duplicate keys instead of silently choosing a value.
  (define (plist->alist plist valid-keys)
    (let loop ((p plist) (seen '()) (acc '()))
      (cond
        ((null? p) (reverse acc))
        ((null? (cdr p))
         (raise (make-cmark-invalid-option #f 'malformed-plist)))
        (else
         (let ((k (car p)) (v (cadr p)))
           (unless (memq k valid-keys)
             (raise (make-cmark-invalid-option k 'unknown-key)))
           (when (memq k seen)
             (raise (make-cmark-invalid-option k 'duplicate-key)))
           (loop (cddr p) (cons k seen) (cons (cons k v) acc)))))))

  (define (lookup alist key default)
    (let ((hit (assq key alist)))
      (if hit (cdr hit) default)))

  (define (check-boolean key v)
    (unless (boolean? v)
      (raise (make-cmark-invalid-option key 'invalid-value))))

  ;; Validate the resulting record so construction and update share policy.
  (define (validate o)
    (check-boolean 'validate-utf8?    (cmark-options-validate-utf8? o))
    (check-boolean 'source-positions? (cmark-options-source-positions? o))
    (check-boolean 'hardbreaks?       (cmark-options-hardbreaks? o))
    (check-boolean 'nobreaks?         (cmark-options-nobreaks? o))
    (check-boolean 'smart?            (cmark-options-smart? o))
    (check-boolean 'unsafe-html?      (cmark-options-unsafe-html? o))
    (for-each
     (lambda (pair)
       (let ((key (car pair)) (n ((cdr pair) o)))
         (unless (and (integer? n) (exact? n) (positive? n))
           (raise (make-cmark-invalid-option key 'invalid-value)))))
     (list (cons 'max-input-bytes cmark-options-max-input-bytes)
           (cons 'max-nodes       cmark-options-max-nodes)
           (cons 'max-depth       cmark-options-max-depth)))
    (let ((xs (cmark-options-extensions o)))
      (unless (list? xs)
        (raise (make-cmark-invalid-option 'extensions 'invalid-value)))
      (for-each
       (lambda (x)
         (unless (symbol? x)
           (raise (make-cmark-invalid-option 'extensions 'invalid-value)))
         (unless (assq x extension-names)
           (raise (make-cmark-invalid-option 'extensions 'unknown-extension))))
       xs))
    ;; cmark gives hardbreaks precedence, but accepting both would hide a
    ;; contradictory request.
    (when (and (cmark-options-hardbreaks? o) (cmark-options-nobreaks? o))
      (raise (make-cmark-invalid-option 'hardbreaks? 'contradictory)))
    o)

  (define (build a
                 d-extensions d-validate-utf8? d-source-positions?
                 d-hardbreaks? d-nobreaks? d-smart? d-unsafe-html?
                 d-max-input-bytes d-max-nodes d-max-depth)
    (validate
     (%make-cmark-options
      (lookup a 'extensions        d-extensions)
      (lookup a 'validate-utf8?    d-validate-utf8?)
      (lookup a 'source-positions? d-source-positions?)
      (lookup a 'hardbreaks?       d-hardbreaks?)
      (lookup a 'nobreaks?         d-nobreaks?)
      (lookup a 'smart?            d-smart?)
      (lookup a 'unsafe-html?      d-unsafe-html?)
      (lookup a 'max-input-bytes   d-max-input-bytes)
      (lookup a 'max-nodes         d-max-nodes)
      (lookup a 'max-depth         d-max-depth))))

  ;; default-cmark-options : -> cmark-options
  ;; Delegate to the constructor so defaults have one definition.
  (define (default-cmark-options)
    (make-cmark-options))

  ;; default-ast-options : -> cmark-options
  ;; AST defaults enable source positions; renderer defaults do not.
  (define (default-ast-options)
    (cmark-options-with (make-cmark-options) 'source-positions? #t))

  ;; make-cmark-options : (symbol object)* -> cmark-options
  (define (make-cmark-options . plist)
    (build (plist->alist plist option-keys)
           default-extensions #t #f #f #f #f #f
           default-max-input-bytes default-max-nodes default-max-depth))

  ;; cmark-options-with : cmark-options (symbol object)* -> cmark-options
  ;; Functional update through the same validation path as construction.
  (define (cmark-options-with o . plist)
    (unless (cmark-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    (build (plist->alist plist option-keys)
           (cmark-options-extensions o)
           (cmark-options-validate-utf8? o)
           (cmark-options-source-positions? o)
           (cmark-options-hardbreaks? o)
           (cmark-options-nobreaks? o)
           (cmark-options-smart? o)
           (cmark-options-unsafe-html? o)
           (cmark-options-max-input-bytes o)
           (cmark-options-max-nodes o)
           (cmark-options-max-depth o)))

  ;; SXML policies are separate because they do not affect cmark parsing.
  (define-record-type (sxml-options %make-sxml-options sxml-options?)
    (fields raw-html softbreak attribute-marker))

  ;; The softbreak value directly names its rendering, avoiding contradictory
  ;; booleans. The default attribute marker is `caret`: the available Akku
  ;; serializers silently misrender `@`. Values name markers because bare `@`
  ;; is not a valid #!r6rs symbol token.
  (define sxml-option-keys '(raw-html softbreak attribute-marker))

  ;; Validate the resulting record so construction and update share policy.
  (define (validate-sxml o)
    (unless (memq (sxml-options-raw-html o) '(omit escape))
      (raise (make-cmark-invalid-option 'raw-html 'invalid-value)))
    (unless (memq (sxml-options-softbreak o) '(newline break space))
      (raise (make-cmark-invalid-option 'softbreak 'invalid-value)))
    (unless (memq (sxml-options-attribute-marker o) '(caret at))
      (raise (make-cmark-invalid-option 'attribute-marker 'invalid-value)))
    o)

  ;; make-sxml-options : (symbol object)* -> sxml-options
  (define (make-sxml-options . plist)
    (let ((a (plist->alist plist sxml-option-keys)))
      (validate-sxml (%make-sxml-options (lookup a 'raw-html 'omit)
                                        (lookup a 'softbreak 'newline)
                                        (lookup a 'attribute-marker 'caret)))))

  ;; default-sxml-options : -> sxml-options
  (define (default-sxml-options) (make-sxml-options))

  ;; sxml-options-with : sxml-options (symbol object)* -> sxml-options
  (define (sxml-options-with o . plist)
    (unless (sxml-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    (let ((a (plist->alist plist sxml-option-keys)))
      (validate-sxml
       (%make-sxml-options
        (lookup a 'raw-html  (sxml-options-raw-html o))
        (lookup a 'softbreak (sxml-options-softbreak o))
        (lookup a 'attribute-marker (sxml-options-attribute-marker o)))))))
