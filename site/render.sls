#!r6rs
;; NOT pure: imports (cmark gfm), which loads a shared object. This is the
;; integration point where the pure site/* libraries meet the native parser.
(library (site render)
  (export render-site site-result? site-result-pages
          site-result-registry site-result-leaked)
  (import (rnrs) (cmark gfm) (site transform) (site links)
          (site template) (site pages))

  (define-record-type site-result
    (fields pages registry leaked))

  (define (label-for name)
    (cond ((assoc name pages) => cdr) (else name)))

  ;; The id-registry and the rendered "On this page" rail are built from the
  ;; SAME toc but are not the same list. transform-body's toc covers every
  ;; heading level, h1 through h6, because every heading is a legitimate
  ;; anchor target -- a cross-page link to `page.md#the-page-title` (its h1)
  ;; must resolve just as one to `page.md#some-section` does. The rail,
  ;; though, lists sections under "On this page"; it must not turn the
  ;; page's own h1 title into an entry linking to itself. So: the registry
  ;; keeps every slug, and only the copy handed to page->document is
  ;; filtered to level > 1.
  (define (rail-toc toc) (filter (lambda (entry) (> (car entry) 1)) toc))

  ;; Pass 1: parse + slug every page, building the id-registry.
  ;; Pass 2: rewrite links against the full registry, then template.
  ;;
  ;; Pass 1 is a plain `map` over `inputs` -- safe despite R6RS leaving
  ;; map's evaluation order unspecified, because each call to
  ;; `transform-body` creates its OWN slugger (site/transform.sls) with no
  ;; state shared across pages; page order in the output is `map`'s
  ;; structural guarantee, independent of application order. Pass 2 cannot
  ;; use `map`: it accumulates `leaked` danglers across pages via `rewrite-
  ;; links`'s per-page result, so it is an explicit left-to-right `let loop`
  ;; instead, the same discipline (site transform) and (site links) each
  ;; apply internally for their own accumulators.
  (define (render-site inputs ref)
    (let* ((parsed                                   ; pass 1
            (map (lambda (in)
                   (let-values (((body toc)
                                 (transform-body (markdown->sxml (cdr in)
                                                                  (default-cmark-options)))))
                     (list (car in) body toc (map caddr toc))))  ; caddr = slug
                 inputs))
           (registry (map (lambda (pg) (cons (car pg) (cadddr pg))) parsed)))
      (let loop ((ps parsed) (pages-out '()) (leaked '()))     ; pass 2
        (if (null? ps)
            (make-site-result (reverse pages-out) registry (reverse leaked))
            (let* ((pg (car ps)) (name (car pg)) (body (cadr pg)) (toc (caddr pg)))
              (let-values (((body* dangling) (rewrite-links body registry name ref)))
                (loop (cdr ps)
                      (cons (cons name
                                  (page->document pages name (label-for name)
                                                   body* (rail-toc toc)))
                            pages-out)
                      (append (reverse dangling) leaked)))))))))
