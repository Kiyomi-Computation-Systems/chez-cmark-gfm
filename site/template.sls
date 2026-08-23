#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site template)
  (export page->document)
  (import (rnrs))

  (define (nav-item current)
    (lambda (entry)
      (let ((file (car entry)) (label (cdr entry)))
        (if (string=? file current)
            `(a (^ (href ,(md->html-name file)) (class "on") (aria-current "page")) ,label)
            `(a (^ (href ,(md->html-name file))) ,label)))))

  (define (md->html-name file)
    (string-append (substring file 0 (- (string-length file) 3)) ".html"))

  (define (toc-item entry)
    `(a (^ (href ,(string-append "#" (caddr entry)))) ,(cadr entry)))

  ;; theme: prefers-color-scheme + a persisted toggle (localStorage). Pinned
  ;; on load so the CSS and the label never disagree (see the preview bug).
  ;;
  ;; This string is emitted verbatim inside a <script> element by the
  ;; pre-safe serializer (site serializer), which HTML-escapes every text
  ;; node -- including a script's. Browsers do NOT decode entities inside
  ;; <script>, so this string must never contain '<', '>', or '&': written
  ;; with === and nested ternaries instead of &&/</> so it survives
  ;; serialization byte-for-byte. Do not introduce any of those characters
  ;; here without giving the serializer script-awareness first.
  (define theme-script
    (string-append
     "(function(){var r=document.documentElement,b=document.getElementById('theme'),"
     "l=document.getElementById('theme-label');function m(){var s=localStorage.getItem('theme');"
     "return s?s:(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');}"
     "function a(x){r.setAttribute('data-mode',x);localStorage.setItem('theme',x);"
     "l.textContent=x==='dark'?'Light mode':'Dark mode';}a(m());"
     "b.addEventListener('click',function(){a(r.getAttribute('data-mode')==='dark'?'light':'dark');});})();"))

  (define (page->document nav current title body toc)
    `(*TOP*
      (html
       (head
        (meta (^ (charset "utf-8")))
        (meta (^ (name "viewport") (content "width=device-width, initial-scale=1")))
        (title ,title)
        (link (^ (rel "stylesheet") (href "style.css"))))
       (body
        (div (^ (class "topbar"))
             (button (^ (id "theme") (class "toggle") (aria-label "Toggle theme"))
                     (span (^ (id "theme-label")) "Dark mode")))
        (div (^ (class "layout"))
             (aside (^ (class "side"))
                    (a (^ (class "mark") (href "index.html")) "chez-cmark-gfm")
                    (nav ,@(map (nav-item current) nav)))
             (main (^ (class "main"))
                   (div (^ (class "col")) ,@(cdr body)))   ; splice *TOP* children
             (aside (^ (class "toc"))
                    (div (^ (class "lbl")) "On this page")
                    ,@(map toc-item toc)))
        (script ,theme-script)))))
  )
