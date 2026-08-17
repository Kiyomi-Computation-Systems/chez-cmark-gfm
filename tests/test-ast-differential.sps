#!r6rs
;;; The AST verified against cmark's own serialization of the same parse.
;;;
;;; cmark_render_xml walks the very tree markdown->ast copies, so re-rendering
;;; our Scheme AST into that dialect and diffing byte-for-byte is a near-total
;;; oracle: a wrong heading level, a dropped child, a mislabelled table header,
;;; a missing fence info, or a bad source position all surface as a byte
;;; difference.
;;;
;;; The load-bearing property is that this serializer CANNOT be tuned to
;;; accommodate a converter bug. It is written against
;;; vendor/cmark-gfm/src/xml.c and judged against cmark's real bytes, so
;;; "adjust the expectation until it passes" is not available -- the
;;; expectation is produced by cmark.
;;;
;;; Three properties are invisible to this oracle and are asserted directly in
;;; tests/test-convert.sps instead: item index, table columns, and alignment on
;;; body cells (design spec 8.3).
(import (rnrs)
        (srfi :64)
        (cmark gfm)
        ;; file-exists? is deliberately absent: (rnrs) already exports it and
        ;; requesting it here too fails the library body with "multiple
        ;; definitions for file-exists?".
        (only (chezscheme) getenv mkdir)
        (cmark-testing))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "ast-differential")

;; --- cmark's XML dialect ------------------------------------------------

;; houdini_escape_html0 with secure = 0 (src/houdini_html_e.c:32-60). Exactly
;; four characters; ' and / are deliberately NOT escaped, because that
;; function only escapes them in secure mode and xml.c passes 0.
(define (xml-escape s)
  (let-values (((port get) (open-string-output-port)))
    (string-for-each
     (lambda (c)
       (case c
         ((#\&) (put-string port "&amp;"))
         ((#\<) (put-string port "&lt;"))
         ((#\>) (put-string port "&gt;"))
         ((#\") (put-string port "&quot;"))
         (else  (put-char port c))))
     s)
    (get)))

;; Our node type back to cmark's element name. The two conditionals are where
;; the AST's uniform key sets pay off: a task item and a header row are
;; ordinary nodes carrying a boolean, and the boolean picks the element name.
(define (node->type-string n)
  (case (markdown-node-type n)
    ((document) "document")
    ((paragraph) "paragraph")
    ((blockquote) "block_quote")
    ((thematic-break) "thematic_break")
    ((softbreak) "softbreak")
    ((linebreak) "linebreak")
    ((emph) "emph")
    ((strong) "strong")
    ((strikethrough) "strikethrough")
    ((heading) "heading")
    ((text) "text")
    ((code) "code")
    ((html-inline) "html_inline")
    ((html-block) "html_block")
    ((code-block) "code_block")
    ((link) "link")
    ((image) "image")
    ((list) "list")
    ((item) (if (markdown-node-property n 'task?) "tasklist" "item"))
    ((table) "table")
    ((table-row) (if (markdown-node-property n 'header?)
                     "table_header" "table_row"))
    ((table-cell) "table_cell")
    ((extension) (markdown-node-property n 'native-type))
    (else (error 'node->type-string "unmapped node type"
                 (markdown-node-type n)))))

;; The five types xml.c renders as literal text rather than as a container.
(define (literal-type? ts)
  (and (member ts '("text" "code" "html_block" "html_inline" "code_block")) #t))

(define (sourcepos-attribute n)
  (let ((p (markdown-node-source n)))
    (if p
        (string-append " sourcepos=\""
                       (number->string (source-position-start-line p)) ":"
                       (number->string (source-position-start-column p)) "-"
                       (number->string (source-position-end-line p)) ":"
                       (number->string (source-position-end-column p)) "\"")
        "")))

;; xml.c:55-59: the extension's attribute function runs before the type
;; switch, so these come first. in-header? is threaded down the walk because
;; align is emitted only for a cell whose PARENT row is a header
;; (extensions/table.c:661) and a cell cannot see its parent from our AST.
(define (extension-attributes n ts in-header?)
  (cond
    ((string=? ts "tasklist")
     (if (markdown-node-property n 'checked?)
         " completed=\"true\"" " completed=\"false\""))
    ((and (string=? ts "table_cell") in-header?)
     (let ((a (markdown-node-property n 'alignment)))
       (if (memq a '(left center right))
           (string-append " align=\"" (symbol->string a) "\"")
           "")))
    (else "")))

(define (type-attributes n ts)
  (cond
    ((string=? ts "document") " xmlns=\"http://commonmark.org/xml/1.0\"")
    ((string=? ts "list")
     (string-append
      (if (eq? 'ordered (markdown-node-property n 'kind))
          (string-append
           " type=\"ordered\" start=\""
           (number->string (markdown-node-property n 'start)) "\""
           (case (markdown-node-property n 'delimiter)
             ((paren)  " delim=\"paren\"")
             ((period) " delim=\"period\"")
             (else "")))
          " type=\"bullet\"")
      " tight=\"" (if (markdown-node-property n 'tight?) "true" "false") "\""))
    ((string=? ts "heading")
     (string-append " level=\""
                    (number->string (markdown-node-property n 'level)) "\""))
    ((string=? ts "code_block")
     (let ((info (markdown-node-property n 'fence-info)))
       (if (> (string-length info) 0)
           (string-append " info=\"" (xml-escape info) "\"")
           "")))
    ((or (string=? ts "link") (string=? ts "image"))
     (string-append " destination=\""
                    (xml-escape (markdown-node-property n 'url)) "\""
                    " title=\""
                    (xml-escape (markdown-node-property n 'title)) "\""))
    (else "")))

;; Two spaces per level, capped at MAX_INDENT = 40 (src/xml.c:14, :28-32).
;; Dropping the cap makes every document nested deeper than 20 levels diverge.
(define (emit-indent port depth)
  (let ((n (min (* 2 depth) 40)))
    (let loop ((i 0))
      (unless (= i n) (put-char port #\space) (loop (+ i 1))))))

(define (serialize port n depth in-header?)
  (let* ((ts (node->type-string n))
         (kids (markdown-node-children n)))
    (emit-indent port depth)
    (put-string port "<")
    (put-string port ts)
    (put-string port (sourcepos-attribute n))
    (put-string port (extension-attributes n ts in-header?))
    (put-string port (type-attributes n ts))
    (cond
      ((literal-type? ts)
       (put-string port " xml:space=\"preserve\">")
       (put-string port (xml-escape (markdown-node-property n 'literal)))
       (put-string port "</")
       (put-string port ts)
       (put-string port ">\n"))
      ((pair? kids)
       (put-string port ">\n")
       ;; A row sets the flag for its cells; anything else passes it through.
       (let ((hdr (cond ((string=? ts "table_header") #t)
                        ((string=? ts "table_row") #f)
                        (else in-header?))))
         (for-each (lambda (k) (serialize port k (+ depth 1) hdr)) kids))
       (emit-indent port depth)
       (put-string port "</")
       (put-string port ts)
       (put-string port ">\n"))
      (else (put-string port " />\n")))))

(define (ast->xml tree)
  (let-values (((port get) (open-string-output-port)))
    (put-string port "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    (put-string port "<!DOCTYPE document SYSTEM \"CommonMark.dtd\">\n")
    (serialize port tree 0 #f)
    (get)))

;; --- leg one: in-process, same options on both sides --------------------
;; markdown->xml is cmark's renderer over the same input and the same option
;; record, so the only thing that can differ is our copy of the tree.
;;
;; Taking our-o and their-o separately is what lets the guard below seed this
;; detector with a deliberate mismatch and prove it can report anything at all
;; -- the same reason tests/test-differential.sps's `mismatch` is shaped this
;; way. With a single options record the detector can never report a
;; difference when the code is correct, so a guard that reimplemented the
;; comparison inline would not exercise it: verified, hardcoding this
;; procedure to #f left all 62 assertions green.
(define divergence
  (case-lambda
    ((markdown o) (divergence markdown o o))
    ((markdown our-o their-o)
     (let ((mine (ast->xml (markdown->ast markdown our-o)))
           (theirs (markdown->xml markdown their-o)))
       (if (string=? mine theirs) #f (list mine theirs))))))

(define positions (make-cmark-options 'source-positions? #t))
(define no-positions (make-cmark-options 'source-positions? #f))

;; --- the detector must be able to report a difference at all ------------
;; Without this, every agreement assertion below could be passing because
;; divergence always returns #f. Seeded by asking OUR side for source
;; positions while cmark's side gets none, on the same document -- the
;; two-options form exists so this guard can manufacture that mismatch.
(test-equal "the comparison detects a real difference when one exists"
  #t
  (if (divergence "# hi\n" positions no-positions) #t #f))

;; --- agreement, one construct at a time ---------------------------------
;; 'agree, not #f, because SRFI-64 evaluates this expression inside
;; (guard (ex (else #F)) ...) -- so with #f as the expected value, an
;; exception raised anywhere in here (notably capture-command's raise on a
;; non-zero CLI exit) would be indistinguishable from a clean agreement.
;; Verified: a CLI that answered --version and then failed on every fixture
;; left this suite reporting 79/79. The `or` keeps the divergence list itself
;; as the actual value when the two really differ, so a failure still prints
;; which bytes moved.
(define (check name markdown)
  (test-equal (string-append "in-process XML agrees: " name)
    'agree (or (divergence markdown no-positions) 'agree))
  (test-equal (string-append "in-process XML agrees with positions: " name)
    'agree (or (divergence markdown positions) 'agree)))

(check "an empty document" "")
(check "headings of every level"
       "# a\n\n## b\n\n### c\n\n#### d\n\n##### e\n\n###### f\n")
(check "a setext heading" "title\n=====\n")
(check "paragraphs and soft breaks" "one\ntwo\n\nthree\n")
(check "a hard break" "one\\\ntwo\n")
(check "emphasis and strong" "*a* **b** ***c***\n")
(check "inline code, including a multi-line span" "`a` and `b\nc` end\n")
(check "a fenced code block with info" "```scheme\n(+ 1 2)\n```\n")
(check "a fenced code block without info" "```\nplain\n```\n")
(check "an indented code block" "    indented\n")
(check "a thematic break" "a\n\n---\n\nb\n")
(check "a block quote, including nesting" "> a\n>\n> > b\n")
(check "a bullet list" "- a\n- b\n")
(check "a tight ordered list with an offset start" "3. a\n4. b\n")
(check "a paren-delimited ordered list" "1) a\n2) b\n")
(check "a loose list" "- a\n\n- b\n")
(check "links with and without titles"
       "[a](u) [b](v \"t\") [c](<sp ace> \"q\")\n")
(check "images" "![a](u) ![b](v \"t\")\n")
(check "raw block and inline HTML" "<div>\nx\n</div>\n\na <b>c</b> d\n")
(check "characters the XML escaper must handle" "a & b < c > d \" e ' f / g\n")
(check "a reference link" "[a][ref]\n\n[ref]: u \"t\"\n")

;; The escaping set is the whole point of one of those cases, so it also gets
;; a direct assertion: ' and / must NOT be escaped, because xml.c passes
;; secure = 0.
(test-equal "the escaper handles exactly the four characters cmark escapes"
  "&amp;&lt;&gt;&quot;'/"
  (xml-escape "&<>\"'/"))

;; --- extensions ---------------------------------------------------------
(define with-exts
  (make-cmark-options 'extensions '(autolink strikethrough table tagfilter
                                    tasklist)))
(define with-exts+pos
  (cmark-options-with with-exts 'source-positions? #t))

(define (check-ext name markdown)
  (test-equal (string-append "in-process XML agrees: " name)
    'agree (or (divergence markdown with-exts) 'agree))
  (test-equal (string-append "in-process XML agrees with positions: " name)
    'agree (or (divergence markdown with-exts+pos) 'agree)))

(check-ext "strikethrough" "~~a~~\n")
(check-ext "an autolink" "http://e.example/ and www.example.org\n")
(check-ext "a table with every alignment"
           "| a | b | c | d |\n|:--|--:|:-:|---|\n| 1 | 2 | 3 | 4 |\n")
(check-ext "a table with one column" "| a |\n|---|\n| 1 |\n")
(check-ext "a table with inline markup in cells"
           "| *a* | `b` |\n|-----|-----|\n| ~~c~~ | [d](u) |\n")
(check-ext "a task list, checked and unchecked" "- [x] a\n- [ ] b\n")
(check-ext "a task list mixed with plain items" "- [x] a\n- plain\n- [ ] b\n")
(check-ext "tagfilter's suppression is a renderer concern, not an AST one"
           "<title>x</title>\n")

;; --- the indentation cap ------------------------------------------------
;; MAX_INDENT is 40, so indentation stops growing past 20 levels. A serializer
;; without the cap agrees on every fixture above and diverges only here.
(define (nested-quotes n) (string-append (make-string n #\>) " deep\n"))

(test-equal "in-process XML agrees at 25 levels of nesting, past MAX_INDENT"
  'agree (or (divergence (nested-quotes 25) no-positions) 'agree))
(test-equal "in-process XML agrees at 25 levels with positions"
  'agree (or (divergence (nested-quotes 25) positions) 'agree))

;; --- leg two: the pinned CLI --------------------------------------------
;; The in-process leg compares our serializer against cmark's renderer inside
;; one process. If both were wrong in the same way -- say, our AST and our
;; reading of xml.c drifted together -- that leg would still pass. The CLI is
;; an independent witness.
(define cli (or (getenv "CMARK_CLI") "cmark-gfm"))
(define tmp-dir "tests/tmp")
(define out-path "tests/tmp/ast-diff-out.bin")
(define fixture-path "tests/tmp/ast-diff-in.md")

(unless (file-exists? tmp-dir) (mkdir tmp-dir))

;; A missing or mismatched CLI FAILS this suite. It does not skip it: "skip
;; when unavailable" is how an exit criterion silently stops being enforced.
;; Both supported acquisition paths ship the binary.
;;
;; merge-stderr? = #t: a link or dyld failure reports on stderr, and that is
;; the whole diagnostic when this probe fails.
(test-equal "the CLI is the same build as the loaded library"
  #t
  (string-contains?
   (utf8->string (capture-command (string-append cli " --version") out-path #t))
   (string-append " " (cmark-gfm-version) " ")))

;; The flags come from the options record, so the two sides cannot describe
;; different configurations by accident. --to xml is fixed: this suite has one
;; format. Not shared with test-differential.sps's version, which is
;; per-format -- see this task's preamble.
(define (options->flags o)
  (string-append
   "--to xml"
   (if (cmark-options-validate-utf8? o)    " --validate-utf8" "")
   (if (cmark-options-source-positions? o) " --sourcepos" "")
   (if (cmark-options-hardbreaks? o)       " --hardbreaks" "")
   (if (cmark-options-nobreaks? o)         " --nobreaks" "")
   (if (cmark-options-smart? o)            " --smart" "")
   (if (cmark-options-unsafe-html? o)      " --unsafe" "")
   (fold-left (lambda (acc e) (string-append acc " -e " (symbol->string e)))
              "" (cmark-options-extensions o))))

(define (write-fixture markdown)
  (let ((p (open-file-output-port fixture-path (file-options no-fail))))
    (put-bytevector p (string->utf8 markdown))
    (close-port p)))

(define (cli-xml markdown o)
  (write-fixture markdown)
  (utf8->string
   (capture-command (string-append cli " " (options->flags o) " " fixture-path)
                    out-path)))

;; Two options records for the same reason the in-process leg takes them: a
;; detector given one record can never report a difference when the code is
;; correct, so its guard has to seed it with a deliberate mismatch -- and the
;; guard must call the detector itself. Reimplementing the comparison inline
;; leaves a hardcoded detector undetected; that shipped once and was caught
;; only by hardcoding it.
(define cli-divergence
  (case-lambda
    ((markdown o) (cli-divergence markdown o o))
    ((markdown our-o their-o)
     (let ((mine (ast->xml (markdown->ast markdown our-o)))
           (theirs (cli-xml markdown their-o)))
       (if (string=? mine theirs) #f (list mine theirs))))))

;; Same guard as the in-process leg, and it calls the detector.
(test-equal "the CLI comparison detects a real difference when one exists"
  #t
  (if (cli-divergence "# hi\n" positions no-positions) #t #f))

(define (check-cli name markdown o)
  (test-equal (string-append "CLI XML agrees: " name)
    'agree (or (cli-divergence markdown o) 'agree)))

;; The committed fixtures, which is what makes this leg a corpus test rather
;; than a restatement of the cases above. hostile.md is included because an
;; AST must preserve exactly what it parsed -- raw HTML and dangerous URLs
;; included -- and this is where that is proved rather than asserted.
(define (fixture->string path) (utf8->string (file->bytevector path)))

(for-each
 (lambda (path)
   (for-each
    (lambda (o)
      (check-cli (string-append path " " (if (cmark-options-source-positions? o)
                                             "with positions" "without positions"))
                 (fixture->string path) o))
    (list with-exts with-exts+pos)))
 '("tests/fixtures/core.md"
   "tests/fixtures/gfm.md"
   "tests/fixtures/smart.md"
   "tests/fixtures/hostile.md"))

;; Every construct from the in-process leg, re-verified against the CLI.
(check-cli "a table with every alignment"
           "| a | b | c | d |\n|:--|--:|:-:|---|\n| 1 | 2 | 3 | 4 |\n"
           with-exts+pos)
(check-cli "a task list, checked and unchecked" "- [x] a\n- [ ] b\n" with-exts+pos)
(check-cli "a multi-line inline code span" "`a\nb` end\n" with-exts+pos)
(check-cli "25 levels of nesting, past MAX_INDENT"
           (nested-quotes 25) with-exts+pos)
(check-cli "the XML escaper's four characters"
           "a & b < c > d \" e ' f / g\n" with-exts+pos)

;; Discrimination guard, same requirement test-differential.sps's layer 1
;; imposes on every option: a parity assertion means nothing unless the flag
;; actually moves the CLI's OWN output for this fixture.
(test-equal "smart punctuation -- the CLI's own output changes"
  #t
  (not (string=? (cli-xml "\"quoted\" -- dashed --- and 'single'\n" with-exts+pos)
                 (cli-xml "\"quoted\" -- dashed --- and 'single'\n"
                          (cmark-options-with with-exts+pos 'smart? #t)))))

;; smart? changes the text literals cmark produces, so the AST must carry the
;; smart-punctuation forms. Verified against the CLI's own --smart output.
(check-cli "smart punctuation reaches the AST's literals"
           "\"quoted\" -- dashed --- and 'single'\n"
           (cmark-options-with with-exts+pos 'smart? #t))

;; unsafe-html? is a RENDERER policy and must not change the AST at all
;; (design spec 3.5). The XML renderer ignores it, so both settings must
;; produce identical output -- which is what proves the AST preserved the raw
;; HTML rather than suppressing it.
(test-equal "unsafe-html? does not change the AST"
  #t
  (string=? (ast->xml (markdown->ast (fixture->string "tests/fixtures/hostile.md")
                                     with-exts+pos))
            (ast->xml (markdown->ast (fixture->string "tests/fixtures/hostile.md")
                                     (cmark-options-with with-exts+pos
                                                         'unsafe-html? #t)))))

(test-end "ast-differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
