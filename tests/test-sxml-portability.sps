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
;;; Every assertion here runs the tree markdown->sxml ACTUALLY EMITS, with
;;; no transformation in between. That is the only construction under which
;;; the conformance claim means anything: an earlier version of this suite
;;; rewrote the adapter's '\x40; markers to '^ before handing them over, and
;;; so proved that a rewritten tree was acceptable while saying nothing
;;; about the tree the library produces.
;;;
;;; The rewrite is gone because the marker is now an option (ADR-0013),
;;; defaulting to '^ -- which is what this lineage actually reads.
;;; wak-sxml-tools spells the attribute-list marker '^ throughout
;;; (sxml-tools/upstream/sxml-tools.scm:44-48,
;;; upstream/serializer.scm:215,246, whose own comments call it "the SXML
;;; 3.0 aux-list"), as does wak-htmlprag (htmlprag/htmlprag.scm:334,1351,
;;; 1485), and neither contains a \x40; escape anywhere. Handed a
;;; '\x40;-marked tree, srl:sxml->html does not raise: it treats '\x40; as
;;; an ordinary element name and nests the attribute pairs as child
;;; elements, so (a (\x40; (href "/x")) "l") serializes to
;;; "<a><@>\n  <href>/x</href>\n</@>l</a>". Silent, and wrong.
(import (rnrs)
        (srfi :64)
        (cmark gfm)
        (wak sxml-tools serializer))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml-portability")

(define (render md . opt)
  (srl:sxml->html (apply markdown->sxml md opt)))

;; --- conformance --------------------------------------------------------
;; Asserted on the WHOLE rendering. The earlier form ran a document
;; exercising every mapped node type through srl:sxml->html and expected the
;; sentinel 'accepted, meaning only "this tree came back as a string" -- and
;; that is precisely the trap in AGENTS.md's list: a serializer that does not
;; know a construct does not reject it, it renders it wrong. Every mangling
;; worth fearing here returns a string. `(*COMMENT* " raw HTML omitted ")`
;; serialized as `<*COMMENT*> raw HTML omitted </*COMMENT*>` is a string; a
;; `*TOP*` emitted as an element wrapping the whole document is a string.
;; Acceptance could not see either, so it was not testing conformance, only
;; that nothing raised.
;;
;; The two constructs under test are not incidental to this library. A
;; `*COMMENT*` is what the DEFAULT raw-html policy emits -- `omit`,
;; reproducing html.c:259 and html.c:337 -- so every document containing raw
;; HTML carries one, and `*TOP*` is the root of every tree markdown->sxml
;; returns. A serializer mishandling either mishandles everything we produce.
;;
;; The document is small on purpose, because the expectation has to be read
;; to be worth anything: a block `*COMMENT*` from the html-block, two inline
;; ones from the `<b>` and `</b>` html-inlines, and two further top-level
;; blocks so `*TOP*` is a real container rather than a single-child wrapper.
;; The string was produced by running srl:sxml->html and then checked by
;; reading it against docs/sxml.md's table of documented deltas: `\n` between
;; blocks with no indentation at depth 1, NO indentation injected inside the
;; `<p>` (srl exempts an element with a bare-text child, the same rule the
;; `pre` assertion below depends on), and no trailing newline. `*TOP*`
;; contributes no tag of its own, which is the half acceptance could not see.
(test-equal "a *TOP* with block and inline comments serializes to HTML"
  (string-append
   "<!-- raw HTML omitted -->\n"
   "<h1>heading</h1>\n"
   "<p>para <!-- raw HTML omitted -->bold<!-- raw HTML omitted --> tail</p>")
  (render "<div>raw</div>\n\n# heading\n\npara <b>bold</b> tail\n"))

;; --- escaping: the security claim ---------------------------------------
;; Asserted on BOTH the absence of the dangerous form and the presence of the
;; escaped one. Absence alone passes against empty output.
(define (contains? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

;; Named "raw-html: escape", not "a text node ...": this content arrives at
;; the adapter as an html-inline node, not a text node -- <script> matches
;; cmark's raw-HTML-tag grammar, so it is raw-html->sxml, not the `text`
;; case, that runs here. The old name pointed a future failure at the wrong
;; function. (The implementer's own mutation log for this task records the
;; same finding.)
(test-equal "raw-html: escape"
  '(#f #t)
  (let ((out (render "A <script>alert(1)</script> B\n"
                     (default-cmark-options)
                     (make-sxml-options 'raw-html 'escape))))
    (list (contains? out "<script>") (contains? out "&lt;script&gt;"))))

;; The genuine `text`-node case the assertion above was misnamed for: "<"
;; here is not a valid HTML tag opener (a "<" followed by a space matches no
;; cmark raw-HTML-tag pattern), so cmark keeps it as literal text and this
;; reaches node->sxml's `text` case, carried verbatim into the tree per
;; sxml.sls's own header comment. Verified directly against markdown->ast
;; before writing this fixture (a single `text` node, literal "a < b"), not
;; assumed from the markdown alone -- confirmed empirically since guessing
;; wrong here is exactly how the assertion above got misnamed in the first
;; place. Costs two lines and pins double-escaping-freedom *through*
;; third-party code, which is the only thing this suite exists to do; the
;; 744-example differential already catches a double-escape in the `text`
;; case, but never through a serializer this project does not control.
(test-equal "text: a literal needing escaping survives to the serializer"
  '(#f #t)
  (let ((out (render "a < b\n")))
    (list (contains? out "a < b") (contains? out "a &lt; b"))))

(test-equal "a quote in an attribute value comes out escaped"
  '(#f #t)
  (let ((out (render "[l](/x \"a\\\"b\")\n")))
    (list (contains? out "title=\"a\"b\"") (contains? out "&quot;"))))

;; --- whitespace ---------------------------------------------------------
;; A pretty-printing serializer would corrupt pre content. This asserts the
;; chosen one does not, which is what lets the README promise it.
;;
;; Asserted on the WHOLE rendering, not on a `contains?` probe for
;; "  indented\n". That earlier form was vacuous, found by mutation in Task
;; 12 Step 4: with srl:sxml->html turned into an unconditional pretty-printer
;; (its "pre"/"script"/"style"/"textarea" exemption removed AND its
;; bare-text-child rule neutered, in a scratch copy of the vendored
;; upstream/serializer.scm -- neither edit alone is enough), the output
;; becomes "<pre>\n  <code>\n      indented\n\tтаb\n\n  </code>\n</pre>".
;; The injected indent is FOUR spaces immediately before the content's own
;; two, so "  indented\n" is still a substring of the corrupted output and
;; the probe passed against exactly the corruption it existed to detect.
;; Equality against the full string cannot: it fails on the injected
;; newlines and indents anywhere in or around the pre.
(test-equal "pre content survives with no injected indentation"
  "<pre><code>  indented\n\tтаb\n</code></pre>"
  (render "```\n  indented\n\tтаb\n```\n"))

(test-end "sxml-portability")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
