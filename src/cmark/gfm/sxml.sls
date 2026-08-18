#!r6rs
;;; The AST -> SXML adapter -- the functional core.
;;;
;;; Imports no library that loads a shared object, directly or transitively:
;;; (cmark gfm ast), (cmark gfm options), and (cmark gfm private conditions)
;;; are all pure. That is what lets tests/test-sxml.sps run with no shared
;;; object loaded, so no assertion in it can pass by accident because of
;;; native behaviour. `make check-purity` enforces it.
;;;
;;; The tree carries HTML VOCABULARY ONLY (ADR-0011). List delimiter, item
;;; index, fence info past the first token, image child structure, and all
;;; source positions are dropped here; markdown->ast remains the interface
;;; for them. That is what makes ADR-0012's oracle total.
;;;
;;; Literals are carried VERBATIM. Escaping belongs to whatever serializer
;;; the caller runs; escaping here would double-escape on output.
(library (cmark gfm sxml)
  (export markdown-ast->sxml)
  (import (rnrs)
          (cmark gfm ast)
          (cmark gfm options)
          (cmark gfm private conditions))

  (define (prop n key) (markdown-node-property n key))

  (define (children->sxml n raw-html)
    (map (lambda (c) (node->sxml c raw-html)) (markdown-node-children n)))

  (define (element tag n raw-html)
    (cons tag (children->sxml n raw-html)))

  ;; The first whitespace-delimited token of the info string, per
  ;; html.c:223-227.
  (define (first-token s)
    (let loop ((i 0))
      (cond ((>= i (string-length s)) s)
            ((memv (string-ref s i) '(#\space #\tab #\newline #\return))
             (substring s 0 i))
            (else (loop (+ i 1))))))

  (define (code-block->sxml n)
    (let ((literal (prop n 'literal))
          (info    (first-token (prop n 'fence-info))))
      (list 'pre
            (if (string=? "" info)
                (list 'code literal)
                (list 'code
                      (list '\x40; (list 'class (string-append "language-" info)))
                      literal)))))

  ;; html.c:259,337 -- the SAME comment for a block and an inline. Which one
  ;; it was is recoverable from the tree position, which is how the
  ;; serializer decides its newlines.
  (define (raw-html->sxml n raw-html)
    (if (eq? 'escape raw-html)
        (prop n 'literal)
        (list '*COMMENT* " raw HTML omitted ")))

  (define (node->sxml n raw-html)
    (case (markdown-node-type n)
      ((document)   (cons '*TOP* (children->sxml n raw-html)))
      ((paragraph)  (element 'p n raw-html))
      ((blockquote) (element 'blockquote n raw-html))
      ((emph)       (element 'em n raw-html))
      ((strong)     (element 'strong n raw-html))
      ((strikethrough) (element 'del n raw-html))
      ((heading)
       (cons (string->symbol
              (string-append "h" (number->string (prop n 'level))))
             (children->sxml n raw-html)))
      ((text)       (prop n 'literal))
      ((code)       (list 'code (prop n 'literal)))
      ((code-block) (code-block->sxml n))
      ((thematic-break) '(hr))
      ((linebreak)  '(br))
      ((softbreak)  "\n")
      ((html-block html-inline) (raw-html->sxml n raw-html))
      ((extension)
       (raise (make-cmark-unsupported-node (prop n 'native-type))))
      (else
       ;; A node type this library produces but the adapter has not mapped.
       ;; Reported through the same condition rather than silently dropped.
       (raise (make-cmark-unsupported-node
               (symbol->string (markdown-node-type n)))))))

  (define markdown-ast->sxml
    (case-lambda
      ((ast) (markdown-ast->sxml ast (default-sxml-options)))
      ((ast o)
       (unless (sxml-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       (node->sxml ast (sxml-options-raw-html o))))))
