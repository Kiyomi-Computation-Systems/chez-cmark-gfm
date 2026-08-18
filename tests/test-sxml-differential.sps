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
        (sxml-html-serializer))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml-differential")

;; Both sides get the SAME options record. Positions never reach SXML, so
;; the AST entry point must not be allowed to default them on here.
(define opts (default-cmark-options))

(define (ours md o) (sxml->html (markdown-ast->sxml (markdown->ast md o))))
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
(agrees "blockquotes agree"   "> quoted\n>\n> twice\n")
(agrees "breaks agree"        "a\nb  \nc\n\n---\n")
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

(test-end "sxml-differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
