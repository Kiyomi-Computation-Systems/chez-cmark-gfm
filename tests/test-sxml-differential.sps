#!r6rs
;;; The SXML tree verified against cmark's own HTML rendering of the same
;;; parse (ADR-0012).
;;;
;;; The load-bearing property is that the expectation is produced by cmark,
;;; so "adjust it until it passes" is not available. The serializer in
;;; tests/sxml-html-serializer.sls is generic over the tree and holds no
;;; node-type knowledge, so it cannot compensate for an adapter that emits
;;; the wrong element.
;;;
;;; (cmark gfm sxml) is imported directly, alongside (cmark gfm): markdown-
;;; ast->sxml is not yet re-exported from (cmark gfm) -- that wiring is
;;; Task 8's markdown->sxml, not this task's -- so importing only (cmark gfm)
;;; as Task 4's brief literally shows would leave markdown-ast->sxml unbound.
(import (rnrs)
        (srfi :64)
        (cmark gfm)
        (cmark gfm sxml)
        (sxml-html-serializer)
        (spec-corpus)
        (only (chezscheme) getenv))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml-differential")

;; Both sides get the SAME options record. Positions never reach SXML, so
;; the AST entry point must not be allowed to default them on here.
(define opts (default-cmark-options))

;; Our renderer is configured from the SAME record cmark's is. hardbreaks?
;; and nobreaks? are cmark RENDERER flags on SOFTBREAK (html.c:319-325) that
;; never reach the parse, so no AST can carry them: handing markdown->ast the
;; record and markdown-ast->sxml nothing would leave our renderer running the
;; default while cmark's ran the flag, and the two would differ for a reason
;; that is ours, not cmark's. This is the in-process counterpart of the CLI
;; leg's -e flags -- one options record, each renderer told what it says.
(define (sxml-opts-for o)
  (make-sxml-options
   'softbreak (cond ((cmark-options-hardbreaks? o) 'break)
                    ((cmark-options-nobreaks? o)   'space)
                    (else                          'newline))))

(define (ours md o)
  (sxml->html (markdown-ast->sxml (markdown->ast md o) (sxml-opts-for o))))
(define (theirs md o) (markdown->html md o))

;; Returns #f when the two agree, or a pair for the report. Callers wrap it
;; in (or … 'agree): SRFI-64 turns a raise in the actual expression into #f,
;; so expecting #f here would pass against a crash.
(define (divergence md o)
  (let ((a (ours md o)) (b (theirs md o)))
    (if (string=? a b) #f (list 'ours a 'theirs b))))

;; Proves the comparator can report a difference at all. Without this, a
;; comparator that always returned #f would make every assertion below pass
;; against anything.
(test-equal "the comparator can detect a difference"
  #t
  (let ((a (ours "# hi\n" opts)) (b (theirs "*hi*\n" opts)))
    (not (string=? a b))))

(define (agrees name md)
  (test-equal name 'agree (or (divergence md opts) 'agree)))

(agrees "headings agree"      "# one\n\n###### six\n")
(agrees "paragraphs agree"    "a & b <c> \"d\" it's\n")
(agrees "emphasis agrees"     "*e* **s** ~~d~~ `c`\n")

;; html.c:366-374 -- a STRONG whose DIRECT PARENT is also a STRONG emits NO
;; tags at all; its children render straight into the enclosing <strong>.
;; The test is on the parent alone, so it fires whether the inner strong is
;; an only child or has siblings. cmark has no matching rule for EMPH
;; (html.c:376-382), which is why *_foo_* keeps both <em> tags while
;; ****foo**** collapses to one <strong>. Found by running the spec corpus
;; through this oracle; the hand-written fixtures had missed it entirely.
(agrees "nested strong emits one tag"        "****foo****\n")
(agrees "triply nested strong emits one tag" "******foo******\n")
(agrees "an inner strong with siblings is spliced too" "__foo, __bar__, baz__\n")
(agrees "a strong under an em under a strong" "_____foo_____\n")
(agrees "nested em is NOT collapsed"         "*_foo_*\n")
(agrees "blockquotes agree"   "> quoted\n>\n> twice\n")
(agrees "breaks agree"        "a\nb  \nc\n\n---\n")

;; html.c:319-325 -- hardbreaks? and nobreaks? are cmark RENDERER flags, and
;; SOFTBREAK is the only node they touch: entering one, cmark writes
;; "<br />\n" under HARDBREAKS, a space under NOBREAKS, and "\n" otherwise.
;; LINEBREAK is unconditional (html.c:315-317), which is what the third case
;; below pins. Neither flag reaches the parse -- CMARK_OPT_HARDBREAKS and
;; CMARK_OPT_NOBREAKS appear only in the renderers and main.c, never in
;; blocks.c or inlines.c -- so the AST cannot carry them and OUR renderer has
;; to be told, exactly as the CLI leg has to be told the extension list.
;; Found by the option sweep; every fixture above uses the default.
(define (agrees-under name md o)
  (test-equal name 'agree (or (divergence md o) 'agree)))

(agrees-under "hardbreaks? turns a softbreak into <br />" "a\nb\n"
              (make-cmark-options 'hardbreaks? #t))
(agrees-under "nobreaks? turns a softbreak into a space" "a\nb\n"
              (make-cmark-options 'nobreaks? #t))
(agrees-under "hardbreaks? leaves a real linebreak alone" "a  \nb\n"
              (make-cmark-options 'hardbreaks? #t))
(agrees "code blocks agree"   "```scheme linenos\n(f x)\n```\n\n    indented\n")
(agrees "raw html agrees"     "<div>\nblock\n</div>\n\npara <b>inline</b> end\n")
(agrees "adjacent blocks agree" "> a\n\nb\n\n> c\n\n---\n\nd\n")

(agrees "links agree"   "[a](/x) [b](/y \"t\") [c](/a%20b?x=1&y=2)\n")
(agrees "autolinks agree" "<https://example.com/a?b=1&c=2> and www.example.com\n")
(agrees "unsafe links agree"
        "[a](javascript:alert(1)) [b](JaVaScRiPt:x) [c](file:///etc/passwd)\n")
(agrees "data urls agree"
        "![a](data:image/png;base64,AA) [b](data:text/html,<b>)\n")
(agrees "images agree" "![*a* `b`](/i \"t\") ![](/j)\n")
(agrees "non-ascii urls agree" "[a](/café/naïve) [b](/a b)\n")

(agrees "tight lists agree"   "- a\n- b\n- c\n")
(agrees "loose lists agree"   "- a\n\n- b\n\n- c\n")
(agrees "ordered lists agree" "1. a\n2. b\n\n3) c\n4) d\n")
(agrees "ol start agrees"     "5. a\n6. b\n")
(agrees "nested lists agree"  "- a\n  - b\n\n    c\n- d\n")
(agrees "task lists agree"    "- [ ] a\n- [x] b\n- c\n")
(agrees "loose task lists agree" "- [ ] a\n\n- [x] b\n")

;; Beyond Task 6's brief: html.c:288-289 keys tightness on the paragraph's
;; grandparent being the LIST NODE ITSELF, not merely reachable through one.
;; A blockquote directly inside a tight item breaks that chain -- the
;; paragraph's grandparent is the item, never a list -- so its <p> must
;; survive even though the enclosing list is tight. Caught only by running
;; this fixture through cmark directly (a scratch probe, not this file) and
;; comparing against a first implementation that threaded tight? through
;; blockquote unchanged, which spliced the <p> and disagreed with cmark.
;; Recorded here as a permanent fixture so the fix cannot silently regress.
(agrees "a blockquote in a tight item keeps its own <p>" "- > q\n- b\n")

(agrees "tables agree"
        "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n")
(agrees "table alignment agrees"
        "| l | c | r | n |\n|:--|:-:|--:|---|\n| 1 | 2 | 3 | 4 |\n")
(agrees "header-only tables agree" "| a | b |\n| --- | --- |\n")
(agrees "tables with inline content agree"
        "| *a* | `b` |\n| --- | --- |\n| [c](/x) | ~~d~~ |\n")
(agrees "tables adjacent to blocks agree"
        "para\n\n| a |\n| --- |\n| 1 |\n\npara\n")

;; ADR-0011: positions are not carried, so the flag must not change the
;; output. Compared against a rendered string, not a boolean: a comparison
;; that always said "same" would pass here regardless.
(test-equal "source-positions? does not change the SXML"
  #t
  (let ((on  (make-cmark-options 'source-positions? #t))
        (off (make-cmark-options 'source-positions? #f))
        (md  "# h\n\n| a |\n| --- |\n| 1 |\n\n- [x] t\n"))
    (string=? (ours md on) (ours md off))))

;; extensions/tagfilter.c:58 registers only an html_filter_func -- no
;; postprocess, no block or inline handler -- so it cannot reach the AST.
(test-equal "tagfilter does not change the SXML"
  #t
  (let ((with    (make-cmark-options 'extensions '(tagfilter)))
        (without (make-cmark-options 'extensions '()))
        (md      "<title>x</title>\n\npara <iframe>y</iframe> end\n"))
    (string=? (ours md with) (ours md without))))

;; markdown->sxml (Task 8's entry point) belongs here rather than in
;; tests/test-options.sps: that suite is a PURE SUITE, and reaching
;; markdown->sxml needs (cmark gfm), which loads native code on import
;; alone, before any assertion runs. This file already imports (cmark gfm)
;; for markdown->ast, so no new import is needed.
;;
;; unsafe-html? is a cmark RENDERER policy. It cannot reach SXML -- the
;; adapter takes only the AST, which does not carry it -- so accepting it
;; silently would discard a security option the caller set explicitly.
(test-equal "markdown->sxml rejects unsafe-html?"
  '(unsafe-html? not-applicable)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (markdown->sxml "# hi\n" (make-cmark-options 'unsafe-html? #t))
    'no-raise))

;; The check is on the VALUE, not the key's presence: an explicit #f is the
;; default and must pass.
(test-equal "markdown->sxml accepts an explicit unsafe-html? #f"
  '(*TOP* (h1 "hi"))
  (markdown->sxml "# hi\n" (make-cmark-options 'unsafe-html? #f)))

;; --- the corpus ---------------------------------------------------------
(define corpus-dir "vendor/cmark-gfm/test/")

(define (corpus name) (spec-examples (string-append corpus-dir name)))

;; A parser that silently matched nothing would make every corpus assertion
;; below pass against no work at all. These counts come from
;; `grep -c '^`\{32\} example'` on the pinned submodule.
(test-equal "the corpus parser finds every example"
  '(672 30 16 26)
  (map (lambda (n) (length (corpus n)))
       '("spec.txt" "extensions.txt" "smart_punct.txt" "regression.txt")))

;; spec_tests.py:109 replaces U+2192 with a tab in both sides. Without it,
;; every tab-significant example parses as a right-arrow character and the
;; differential still passes -- both sides get the same wrong input.
(test-equal "tab arrows are translated to tabs"
  #t
  (let ((all (apply string-append (corpus "spec.txt"))))
    (and (not (memv #\x2192 (string->list all)))
         (memv #\tab (string->list all))
         #t)))

(test-end "sxml-differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
