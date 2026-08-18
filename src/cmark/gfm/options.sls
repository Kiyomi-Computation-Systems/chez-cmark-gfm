#!r6rs
;;; Immutable parser options -- the functional core.
;;;
;;; This library imports NO native library, not even transitively. That is
;;; deliberate: it means tests/test-options.sps runs with no shared object
;;; loaded, so no assertion in it can pass by accident because of native
;;; behaviour. Check the transitive imports before adding one.
;;;
;;; Options describe PARSING. Wrap width is a renderer argument and lives in
;;; (cmark gfm render), because in cmark's own factoring option bits go to
;;; both the parser and the renderer while width goes only to some renderers.
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

  ;; The public spelling of an extension is a SYMBOL; cmark's own spelling is
  ;; a string. They coincide today for all five, and this alist is what stops
  ;; that coincidence from becoming an invariant held by luck. Task 7 asserts
  ;; every native name here resolves through cmark_find_syntax_extension.
  (define extension-names
    '((autolink      . "autolink")
      (strikethrough . "strikethrough")
      (table         . "table")
      (tagfilter     . "tagfilter")
      (tasklist      . "tasklist")))

  (define (supported-extensions) (map car extension-names))

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

  ;; Walks the plist, rejecting structural problems before any value is read.
  ;; A duplicate key is an error rather than last-wins: silently honouring one
  ;; of two conflicting instructions is the failure mode this library exists
  ;; to prevent.
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

  ;; Runs on the RESULTING record, so both constructors share one policy and
  ;; cmark-options-with cannot slip past a check the base object passed.
  ;; Returns the record so it can be used in tail position.
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
    ;; Not a defence against undefined behaviour: html.c:319-325 gives
    ;; hardbreaks precedence over nobreaks, so cmark is well-defined here.
    ;; This is policy -- a caller who set both made a mistake, and silently
    ;; discarding one of their two explicit requests would hide it.
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

  ;; ADR-0008: source-positions? is #f, diverging from project plan 6.2.
  ;; 0.1 has no AST, so the flag's only observable effect is data-sourcepos
  ;; attributes in HTML and sourcepos in XML.
  ;;
  ;; Delegates to make-cmark-options with an empty plist instead of
  ;; restating the eight positional defaults here: make-cmark-options's call
  ;; to build below is then the ONE place those values are written, so a
  ;; future default change cannot desync the two constructors the way it
  ;; could when each called %make-cmark-options with its own copy of the
  ;; tuple (Task 2 review).
  (define (default-cmark-options)
    (make-cmark-options))

  ;; ADR-0009 and design spec 4.2: markdown->ast's per-entry-point default.
  ;; Positions are worth having in an AST and are not worth having in
  ;; rendered markup, and one shared default cannot serve both -- so the
  ;; entry point picks, by arity, rather than the record carrying a third
  ;; "unset" state that every validation path would have to handle.
  ;;
  ;; Built by functional update from make-cmark-options rather than by
  ;; restating the default tuple, so a future change to any other default
  ;; cannot desync the two constructors.
  (define (default-ast-options)
    (cmark-options-with (make-cmark-options) 'source-positions? #t))

  (define (make-cmark-options . plist)
    (build (plist->alist plist option-keys)
           default-extensions #t #f #f #f #f #f
           default-max-input-bytes default-max-nodes default-max-depth))

  ;; Functional update. Rebuilds from o's current field values plus plist's
  ;; overrides through the same build/validate path as construction, so
  ;; every rule validate enforces -- including the contradictory-pair check
  ;; above -- applies to the result and cannot be bypassed by starting from
  ;; an existing record instead of a fresh plist.
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

  ;; --- SXML adapter options ----------------------------------------------
  ;; Separate from cmark-options because they govern OUR renderer, not
  ;; cmark's parse. A record rather than a bare symbol argument: it inherits
  ;; the plist validation above, which a symbol cannot have, and a second
  ;; field later costs no arity change at any call site.
  (define-record-type (sxml-options %make-sxml-options sxml-options?)
    (fields raw-html softbreak attribute-marker))

  ;; softbreak is the SXML side of cmark's hardbreaks?/nobreaks? RENDERER
  ;; flags (html.c:319-325). They are not parse options -- CMARK_OPT_HARDBREAKS
  ;; and CMARK_OPT_NOBREAKS appear only in the renderers and main.c, never in
  ;; blocks.c or inlines.c -- so the AST cannot carry them and the adapter has
  ;; no other way to learn them. Spelled as what a softbreak BECOMES rather
  ;; than as two booleans, because cmark's own pair is mutually exclusive with
  ;; a precedence rule (html.c:320 wins over html.c:322) and a three-valued
  ;; field cannot express the contradictory state at all.
  ;; attribute-marker is ADR-0013. The SXML specification marks an attribute
  ;; list with `@`, but both serializers reachable through Akku --
  ;; wak-sxml-tools (sxml-tools/upstream/sxml-tools.scm:44-48,
  ;; upstream/serializer.scm:215,246) and wak-htmlprag
  ;; (htmlprag/htmlprag.scm:334,1351,1485) -- use `^`, and neither contains a
  ;; \x40; escape anywhere, so neither can consume a `@`-marked tree at all.
  ;; It fails SILENTLY, turning the attribute list into bogus child elements.
  ;; The default is therefore `caret`, the dialect this platform can actually
  ;; render; `at` is the specification's spelling, for callers pattern-
  ;; matching SXML by hand or moving trees to another Scheme.
  ;;
  ;; The values NAME the marker rather than being it: `@` cannot be written
  ;; as a symbol literal in #!r6rs source, so a caller writing #!r6rs could
  ;; not spell the option value if the value were the marker itself.
  (define sxml-option-keys '(raw-html softbreak attribute-marker))

  ;; Reuses plist->alist, which takes its key list as a parameter. Each
  ;; caller supplies only its own, so the two option families still cannot
  ;; accept each other's keys -- and there is one copy of the walk to fix
  ;; rather than two to keep in sync.

  ;; Runs on the RESULTING record so both constructors share one policy,
  ;; exactly as `validate` does for cmark-options.
  (define (validate-sxml o)
    (unless (memq (sxml-options-raw-html o) '(omit escape))
      (raise (make-cmark-invalid-option 'raw-html 'invalid-value)))
    (unless (memq (sxml-options-softbreak o) '(newline break space))
      (raise (make-cmark-invalid-option 'softbreak 'invalid-value)))
    (unless (memq (sxml-options-attribute-marker o) '(caret at))
      (raise (make-cmark-invalid-option 'attribute-marker 'invalid-value)))
    o)

  (define (make-sxml-options . plist)
    (let ((a (plist->alist plist sxml-option-keys)))
      (validate-sxml (%make-sxml-options (lookup a 'raw-html 'omit)
                                        (lookup a 'softbreak 'newline)
                                        (lookup a 'attribute-marker 'caret)))))

  (define (default-sxml-options) (make-sxml-options))

  (define (sxml-options-with o . plist)
    ;; Guards its first argument exactly as cmark-options-with does. Two
    ;; record types with matching APIs now coexist, so passing the wrong one
    ;; is a realistic caller error, and it must surface as this library's own
    ;; condition rather than as a bare R6RS assertion from the accessor.
    (unless (sxml-options? o)
      (raise (make-cmark-invalid-option #f 'invalid-value)))
    (let ((a (plist->alist plist sxml-option-keys)))
      (validate-sxml
       (%make-sxml-options
        (lookup a 'raw-html  (sxml-options-raw-html o))
        (lookup a 'softbreak (sxml-options-softbreak o))
        (lookup a 'attribute-marker (sxml-options-attribute-marker o)))))))
