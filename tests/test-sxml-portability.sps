#!r6rs
;;; What a THIRD-PARTY serializer proves that ours cannot (design spec 6.6).
;;;
;;; Two things, both structural. That the tree is conforming SXML a tool
;;; written to the specification accepts -- not merely something our own
;;; serializer handles. And that escaping ACTUALLY HAPPENS: plan 10.4's
;;; "emit text nodes as Scheme strings for serializer escaping" is a claim
;;; about somebody else's code, and testing it with our own serializer
;;; proves nothing about it. Under raw-html: escape that is the adapter's
;;; entire security claim.
;;;
;;; wak-sxml-tools is MIT and descends from the same Lizorkin/Kiselyov
;;; lineage as the SXML specification. It is a DEV dependency: (cmark gfm)
;;; does not import it.
;;;
;;; wak-sxml-tools's OWN dialect of that lineage spells the attribute-list
;;; marker '^ (a caret), not '@ -- confirmed against
;;; vendor/wak-sxml-tools/sxml-tools/upstream/serializer.scm, whose own
;;; comments call it "the SXML 3.0 aux-list" at lines 263, 432, and
;;; 841-845, every one testing (eq? (car node) '^). '@ is not a valid
;;; R6RS identifier on its own (it is not in R6RS's <special-initial> set,
;;; which is exactly why THIS project's own tree spells it '\x40; --
;;; Global Constraints, "SXML's @ attribute marker must be written \x40;
;;; in source"); '^ is. wak-sxml-tools's R6RS portification made the
;;; portable choice; this project's ADR-0011 made the spec-literal one.
;;; Both are real SXML; they disagree on one token. attrs->caret bridges
;;; them, here, in this test-only file -- src/cmark/gfm/sxml.sls is
;;; untouched, and every existing suite that checks '\x40; keeps doing so.
;;;
;;; Without this bridge, srl:sxml->html does not raise on an '\x40;-marked
;;; attribute list -- it treats '\x40; as an ordinary element name and
;;; nests the attribute pairs as child elements instead of attributes
;;; (confirmed empirically: (a (\x40; (href "/x")) "l") serializes to
;;; "<a><@><href>/x</href></@>l</a>", not "<a href=\"/x\">l</a>"). That
;;; would make "a quote in an attribute value comes out escaped" fail for
;;; real, because the title text then lands in ELEMENT content -- escaped
;;; by srl:string->char-data, which handles only & < > -- rather than in
;;; an ATTRIBUTE value, escaped by srl:string->html-att, which also
;;; handles " and '. This is not a missing binding to work around; it is a
;;; second, real SXML dialect this suite must speak to ask its question at
;;; all, exactly as tests/sxml-html-serializer.sls exists to speak html.c's.
(import (rnrs)
        (srfi :64)
        (cmark gfm)
        (wak sxml-tools serializer))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml-portability")

;; Rewrites every ('\x40; (key val) ...) attribute list in TREE to
;; ('^ (key val) ...), leaving everything else -- including the attribute
;; pairs themselves, always flat (key string) pairs in this adapter's
;; output, never nested SXML -- untouched. '\x40; is only ever a marker in
;; second-child position (markdown-node table 4.1; see src/cmark/gfm/sxml.sls),
;; so a shallow structural check is enough; no tag-name allowlist is needed.
(define (attrs->caret tree)
  (cond
    ((not (pair? tree)) tree)
    ((and (pair? (cdr tree)) (pair? (cadr tree)) (eq? (caadr tree) '\x40;))
     (cons (car tree)
           (cons (cons '^ (cdr (cadr tree)))
                 (map attrs->caret (cddr tree)))))
    (else (cons (car tree) (map attrs->caret (cdr tree))))))

(define (render md . opt)
  (srl:sxml->html (attrs->caret (apply markdown->sxml md opt))))

;; --- conformance --------------------------------------------------------
;; A tree the serializer rejects raises, which SRFI-64 would turn into #f --
;; so the expectation is a sentinel, never #f.
(define (accepts? md)
  (guard (e (#t 'rejected))
    (if (string? (render md)) 'accepted 'not-a-string)))

(test-equal "a document exercising every mapped node type is accepted"
  'accepted
  (accepts? (string-append
             "# h\n\n> q\n\n- [x] t\n- b\n\n1. o\n\n`c` *e* **s** ~~d~~\n\n"
             "[l](/x \"t\") ![i](/j)\n\n```scheme\n(f)\n```\n\n"
             "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n---\n\npara <b>raw</b>\n")))

;; --- escaping: the security claim ---------------------------------------
;; Asserted on BOTH the absence of the dangerous form and the presence of the
;; escaped one. Absence alone passes against empty output.
(define (contains? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

(test-equal "a script tag in a text node comes out escaped"
  '(#f #t)
  (let ((out (render "A <script>alert(1)</script> B\n"
                     (default-cmark-options)
                     (make-sxml-options 'raw-html 'escape))))
    (list (contains? out "<script>") (contains? out "&lt;script&gt;"))))

(test-equal "a quote in an attribute value comes out escaped"
  '(#f #t)
  (let ((out (render "[l](/x \"a\\\"b\")\n")))
    (list (contains? out "title=\"a\"b\"") (contains? out "&quot;"))))

;; --- whitespace ---------------------------------------------------------
;; A pretty-printing serializer would corrupt pre content. This asserts the
;; chosen one does not, which is what lets the README promise it.
(test-equal "pre content survives with no injected indentation"
  #t
  (contains? (render "```\n  indented\n\tтаb\n```\n") "  indented\n"))

(test-end "sxml-portability")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
