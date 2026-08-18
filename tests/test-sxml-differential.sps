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
        ;; file-exists? is deliberately NOT requested from (chezscheme):
        ;; (rnrs) already exports it, and asking for it twice fails the
        ;; program body with "multiple definitions for file-exists?" --
        ;; the same trap tests/test-ast-differential.sps records.
        (only (chezscheme) getenv mkdir)
        (cmark-testing))

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
;; leg's -e flags.
;;
;; Derives softbreak only, not the whole record: unsafe-html? has no
;; sxml-options equivalent to derive raw-html into (see the comment above
;; cli-flags below), so this function cannot and does not attempt to tell
;; the sxml renderer everything the cmark-options record says -- only the
;; one field that has somewhere to go.
(define (sxml-opts-for o m)
  (make-sxml-options
   'attribute-marker m
   'softbreak (cond ((cmark-options-hardbreaks? o) 'break)
                    ((cmark-options-nobreaks? o)   'space)
                    (else                          'newline))))

;; ADR-0013's two dialects. The sweeps below run once per entry, so the
;; oracle is total for BOTH rather than covering one with 744 examples and
;; the other with a handful of hand-written assertions. Everything reachable
;; from an attribute list -- the href policy, the alt flattening, table
;; alignment, the tasklist input -- is then judged against cmark's own bytes
;; under either marker, and tests/sxml-html-serializer.sls accepts both so
;; one serializer serves both legs.
(define markers '(caret at))

;; Every non-sweep assertion in this file uses the default marker, which is
;; what a caller who sets nothing gets; the marker only ever varies through
;; the sweeps. Derived from the library's own default rather than restated
;; as the literal 'caret: if that default ever changed, a hardcoded copy
;; here would desync silently, and every non-sweep assertion in this file
;; would keep passing while no longer exercising what a caller who sets
;; nothing actually gets.
(define default-marker (sxml-options-attribute-marker (default-sxml-options)))

(define ours
  (case-lambda
    ((md o)   (ours md o default-marker))
    ((md o m) (sxml->html (markdown-ast->sxml (markdown->ast md o)
                                              (sxml-opts-for o m))))))
(define (theirs md o) (markdown->html md o))

;; Returns #f when the two agree, or a pair for the report. Callers wrap it
;; in (or … 'agree): SRFI-64 turns a raise in the actual expression into #f,
;; so expecting #f here would pass against a crash.
;;
;; The marker leads rather than trails: with it last, (md o m) and the
;; existing (md our-o their-o) would be the same arity and case-lambda could
;; not tell a marker from a second options record.
(define divergence-under
  (case-lambda
    ((m md o) (divergence-under m md o o))
    ((m md our-o their-o)
     (let ((a (ours md our-o m)) (b (theirs md their-o)))
       (if (string=? a b) #f (list 'ours a 'theirs b))))))

(define divergence
  (case-lambda
    ((md o)             (divergence-under default-marker md o))
    ((md our-o their-o) (divergence-under default-marker md our-o their-o))))

;; A markdown document whose rendering depends on the extension list, used
;; by both legs' discrimination guards below.
(define table-md "| a |\n| --- |\n| 1 |\n")

;; Proves the comparator can report a difference at all. Without this, a
;; comparator that always returned #f would make every assertion below pass
;; against anything.
;;
;; It CALLS divergence rather than inlining string=? on two hand-picked
;; renderings, because the inlined form proves only that two different
;; documents render differently -- it never runs the comparator, so a
;; comparator hardcoded to "equal" survives it and leaves every assertion in
;; this file vacuous. Given one options record the comparator cannot report a
;; difference while the code is correct, so the mismatch is seeded from the
;; two records instead: same shape as tests/test-ast-differential.sps's, and
;; the reason its case-lambda exists.
(test-equal "the comparator can detect a difference"
  #t
  (if (divergence table-md opts (make-cmark-options 'extensions '())) #t #f))

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
;; ****foo**** collapses to one <strong>. Found by the corpus sweep below,
;; which the hand-written fixtures above had missed entirely.
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
;; Found by the option sweep below; every fixture above uses the default.
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
;; tests/test-options.sps: that suite is a PURE SUITE, and CALLING
;; markdown->sxml runs (cmark gfm)'s native code, parsing through the shim.
;; Not because importing (cmark gfm) alone would do that -- it would not:
;; Chez instantiates a library's body only when a binding it defines is
;; actually referenced, so an import with no reference to what it exports is
;; invisible to check-purity, same as the caveat check-purity's own Makefile
;; comment records. What disqualifies this file from the pure suite is that
;; the assertions below actually CALL markdown->sxml. This file already
;; imports (cmark gfm) for markdown->ast, so no new import is needed.
;;
;; unsafe-html? is a cmark RENDERER policy. It cannot reach SXML -- the
;; adapter takes only the AST, which does not carry it -- so accepting it
;; silently would discard a security option the caller set explicitly.
(test-equal "markdown->sxml rejects hardbreaks?"
  '(hardbreaks? not-applicable)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (markdown->sxml "a\nb\n" (make-cmark-options 'hardbreaks? #t))
    'no-raise))

(test-equal "markdown->sxml rejects nobreaks?"
  '(nobreaks? not-applicable)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (markdown->sxml "a\nb\n" (make-cmark-options 'nobreaks? #t))
    'no-raise))

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

;; markdown->sxml's OWN guard on its second argument -- distinct from
;; markdown-ast->sxml's sxml-options? guard, pinned in the pure suite. Two
;; record types with matching-shaped APIs coexist here (cmark-options and
;; sxml-options), so passing the wrong one at the wrong position is a
;; realistic caller error.
(test-equal "markdown->sxml rejects a non-cmark-options second argument"
  '(#f invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (markdown->sxml "hi\n" (default-sxml-options))
    'no-raise))

;; --- the corpus ---------------------------------------------------------
;; The vendored WORKING TREE, not $(CMARK_CLI). This is the only read of it
;; anywhere under tests/ -- every other suite reaches cmark through the CLI
;; or the shim, both of which the pkg-config acquisition path (ADR-0001)
;; satisfies with no submodule checked out at all. `make deps` therefore
;; initialises vendor/cmark-gfm too, checkout only.
;;
;; The guard below exists because the failure without it is illegible.
;; `all-examples` is built at TOP LEVEL, outside any test- form, so a missing
;; file raises &i/o-file-does-not-exist out of open-file-input-port and kills
;; the program before SRFI-64 reports anything -- naming the reader, not the
;; missing checkout. One stat and a sentence turn that into the actual
;; diagnosis. spec.txt stands for all four: they arrive and leave together,
;; as one submodule's working tree.
(define corpus-dir "vendor/cmark-gfm/test/")

(unless (file-exists? (string-append corpus-dir "spec.txt"))
  (display (string-append
            "tests/test-sxml-differential.sps: cmark's example corpus is not in "
            corpus-dir "\n"
            "The vendor/cmark-gfm submodule is not checked out. Run:\n"
            "    git submodule update --init vendor/cmark-gfm\n"
            "or `make deps`, which does exactly that (no build required --\n"
            "this suite reads test/*.txt only).\n")
           (current-error-port))
  (exit 1))

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

;; --- the whole corpus, in-process --------------------------------------
;; All 744 examples run with the full default extension set, so table,
;; tasklist, and strikethrough nodes are actually exercised. Per-example
;; extension labels and `disabled` markers are ignored: they matter only to
;; a harness comparing against the file's expected HTML.
(define all-examples
  (append (corpus "spec.txt") (corpus "extensions.txt")
          (corpus "smart_punct.txt") (corpus "regression.txt")))

;; One assertion for the whole sweep rather than 744, so a failure names the
;; first divergent example instead of drowning the report. The result is the
;; example's index, the failing input, and both renderings, which is what a
;; debugger needs.
;;
;; `compare` is the leg's comparator, already closed over its options record
;; and its marker. Passing it in rather than hardcoding `divergence` is what
;; lets the in-process and CLI legs share one driver and one report shape.
(define (sweep compare examples)
  (let loop ((es examples) (i 0))
    (cond
      ((null? es) 'agree)
      ((compare (car es)) => (lambda (d) (cons i (cons (car es) d))))
      (else (loop (cdr es) (+ i 1))))))

;; Runs `leg` once per marker, stopping at the first that disagrees and
;; naming it. The marker is named HERE rather than inside each comparator so
;; there is one place it can come from, and so a leg's own report shape --
;; index, input, both renderings -- stays exactly what it was.
(define (per-marker leg)
  (let loop ((ms markers))
    (cond
      ((null? ms) 'agree)
      (else
       (let ((r (leg (car ms))))
         (if (eq? 'agree r) (loop (cdr ms)) (cons 'marker (cons (car ms) r))))))))

;; Without this, a driver that iterated an empty list, or only the default,
;; would leave every sweep below passing while covering one dialect or none
;; -- and the twin sweeps would be the same run twice. The probe fails for
;; `at` only, so this also pins that `at` is reached and that the marker
;; reaches the report. It returns a LIST, as every real leg does, because the
;; report is built by consing onto it.
(test-equal "the per-marker driver runs both markers and names the failing one"
  '(marker at probe-failed)
  (per-marker (lambda (m) (if (eq? 'at m) '(probe-failed) 'agree))))

;; The probe above does not close the gap it claims to: a `markers` of
;; `'(at)` alone -- caret silently dropped -- would make the SAME leg
;; produce this exact same `(marker at probe-failed)` report, since the leg
;; never fails for caret and nothing above checks caret was ever reached at
;; all. That would leave the corpus sweeps below covering one dialect while
;; this comment claims to guard against exactly that. This second probe
;; asserts the actual VISIT ORDER through a mutable accumulator, independent
;; of what the driver returns, so a shortened or reordered `markers` fails
;; here even when every leg it is given always agrees.
(test-equal "the per-marker driver visits both markers, in order"
  '(caret at)
  (let ((visited '()))
    (per-marker (lambda (m) (set! visited (cons m visited)) 'agree))
    (reverse visited)))

(test-equal "every corpus example agrees in-process, under both markers"
  'agree
  (per-marker (lambda (m)
                (sweep (lambda (md) (divergence-under m md opts))
                       all-examples))))

;; No corpus example may reach the adapter's unmapped-type branch. If one
;; does, that is a finding about our node coverage, not a pass.
(test-equal "no corpus example raises unsupported-node"
  'none
  (let loop ((es all-examples))
    (cond
      ((null? es) 'none)
      (else
       (guard (e ((cmark-unsupported-node? e)
                  (list 'unsupported (cmark-unsupported-node-type e) (car es))))
         (ours (car es) opts)
         (loop (cdr es)))))))

;; --- option sweep -------------------------------------------------------
;; Every option with a cmark equivalent, over the four fixtures. Both sides
;; get the same record, so any divergence is ours.
(define fixture-files
  '("tests/fixtures/core.md" "tests/fixtures/gfm.md"
    "tests/fixtures/smart.md" "tests/fixtures/hostile.md"))

(define (file->string path)
  (let* ((p (open-file-input-port path (file-options) (buffer-mode block)
                                  (make-transcoder (utf-8-codec) (eol-style none))))
         (s (get-string-all p)))
    (close-port p)
    (if (eof-object? s) "" s)))

(define fixtures (map file->string fixture-files))

(define option-matrix
  (list (make-cmark-options)
        (make-cmark-options 'hardbreaks? #t)
        (make-cmark-options 'nobreaks? #t)
        (make-cmark-options 'smart? #t)
        (make-cmark-options 'extensions '())
        (make-cmark-options 'extensions '(table))
        (make-cmark-options 'extensions '(tasklist))
        (make-cmark-options 'extensions '(strikethrough))
        (make-cmark-options 'extensions '(autolink))
        (make-cmark-options 'extensions '(tagfilter))))

;; The configuration's index joins the report: with ten records and four
;; fixtures, "some fixture disagreed" is not enough to start from.
(test-equal "every fixture agrees under every option configuration, under both markers"
  'agree
  (per-marker
   (lambda (m)
     (let loop ((os option-matrix) (i 0))
       (if (null? os)
           'agree
           (let ((r (sweep (lambda (md) (divergence-under m md (car os)))
                           fixtures)))
             (if (eq? 'agree r)
                 (loop (cdr os) (+ i 1))
                 (cons 'options (cons i r)))))))))

;; --- the CLI leg --------------------------------------------------------
;; Not redundant with the in-process leg. Our SXML path and markdown->html
;; both consume a document parsed through OUR shim, so a wrong option bit or
;; a missing extension corrupts the parse feeding both sides -- they would
;; agree while both being wrong. The pinned CLI is the independent witness
;; that the parse was configured correctly (ADR-0012).
(define cli (or (getenv "CMARK_CLI") "cmark-gfm"))
(define tmp-dir "tests/tmp/")
(define in-path  (string-append tmp-dir "sxml-diff-in.md"))
(define out-path (string-append tmp-dir "sxml-diff-out.bin"))

(unless (file-exists? tmp-dir) (mkdir tmp-dir))

;; Every PARSE-level option with a cmark CLI equivalent, mirroring
;; tests/test-ast-differential.sps's options->flags. Before this, only the
;; extension list was translated -- harmless while this leg is only ever
;; called with `opts` (the defaults) below, but running it over
;; option-matrix, as the in-process leg already does, would have reported a
;; false divergence for hardbreaks?/nobreaks?/smart?/validate-utf8? and
;; blamed the adapter for a bug in this harness instead.
;;
;; --unsafe is deliberately NOT translated. unsafe-html? has no SXML-side
;; equivalent: sxml-opts-for above never derives raw-html from it, and
;; markdown->sxml's own public guard refuses the option outright (it is not
;; "not yet translated", it is "not applicable"). Adding --unsafe here would
;; not create an agreement point between `ours` and the CLI -- cmark would
;; render raw HTML verbatim while the adapter still only omits or escapes
;; it -- so a divergence there would be a real, expected policy difference,
;; not evidence of a translation bug like the four flags above.
(define (cli-flags o)
  (apply string-append
         "--to html "
         (if (cmark-options-hardbreaks? o)    "--hardbreaks " "")
         (if (cmark-options-nobreaks? o)      "--nobreaks " "")
         (if (cmark-options-smart? o)         "--smart " "")
         (if (cmark-options-validate-utf8? o) "--validate-utf8 " "")
         (map (lambda (x) (string-append "-e " (symbol->string x) " "))
              (cmark-options-extensions o))))

;; A direct pin on the flag-string builder, cheaper than a CLI round trip and
;; exercising exactly the mapping the fix above adds. This leg never varies
;; these four flags in practice (it is only ever called with `opts` below),
;; so nothing else in this file would notice a regression here.
(test-equal "cli-flags translates every parse-level boolean cmark understands"
  '("--to html " "--to html --hardbreaks " "--to html --nobreaks "
    "--to html --smart " "--to html --validate-utf8 ")
  (list (cli-flags (make-cmark-options 'extensions '() 'validate-utf8? #f))
        (cli-flags (make-cmark-options 'extensions '() 'validate-utf8? #f
                                        'hardbreaks? #t))
        (cli-flags (make-cmark-options 'extensions '() 'validate-utf8? #f
                                        'nobreaks? #t))
        (cli-flags (make-cmark-options 'extensions '() 'validate-utf8? #f
                                        'smart? #t))
        (cli-flags (make-cmark-options 'extensions '() 'validate-utf8? #t))))

;; Binary, not text: a transcoder's eol-style is either explicit or "native",
;; and this file's own file->string above reads with `eol-style none` --
;; native and none do not always agree (Windows' native is crlf), so a
;; transcoder-based write here could translate line endings on the way to
;; disk in a way the read side never undoes, corrupting a fixture around a
;; CR byte for a harness reason having nothing to do with the adapter.
;; tests/test-ast-differential.sps:338-341's write-fixture takes exactly
;; this form for exactly this reason; mirrored here.
(define (write-file path s)
  (let ((p (open-file-output-port path (file-options no-fail))))
    (put-bytevector p (string->utf8 s))
    (close-port p)))

(define (cli-html md o)
  (write-file in-path md)
  (utf8->string
   (capture-command (string-append cli " " (cli-flags o) " " in-path)
                    out-path)))

;; Marker-leading for the same reason divergence-under is.
(define cli-divergence-under
  (case-lambda
    ((m md o) (cli-divergence-under m md o o))
    ((m md our-o their-o)
     (let ((a (ours md our-o m)) (b (cli-html md their-o)))
       (if (string=? a b) #f (list 'ours a 'cli b))))))

(define cli-divergence
  (case-lambda
    ((md o)             (cli-divergence-under default-marker md o))
    ((md our-o their-o) (cli-divergence-under default-marker md our-o their-o))))

;; Calls cli-divergence itself rather than inlining string=?, so the guard
;; exercises the comparator's branch polarity and not merely the fact that
;; two different documents render differently. Task 4's in-process guard has
;; the same shape and is corrected alongside this one.
;;
;; The mismatch is an EXTENSION mismatch, not two different documents: with
;; one options record both sides get the same input and the same flags, so a
;; correct implementation makes them equal and the guard could never pass.
;; Seeding it from the CLI's record also proves cli-flags actually reaches
;; the subprocess -- drop -e table there and this fires as well.
(test-equal "the CLI comparator can detect a difference"
  #t
  (if (cli-divergence table-md opts (make-cmark-options 'extensions '())) #t #f))

(test-equal "every fixture agrees against the pinned CLI, under both markers"
  'agree
  (per-marker (lambda (m)
                (sweep (lambda (md) (cli-divergence-under m md opts))
                       fixtures))))


(test-end "sxml-differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
