# Stage 5 — SXML Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `markdown->sxml` and `markdown-ast->sxml`, converting the Scheme AST into an SXML tree in HTML vocabulary, verified byte-for-byte against cmark's own HTML renderer across its 744-example test corpus.

**Architecture:** A pure transformation (`src/cmark/gfm/sxml.sls`) from `markdown-node` records to SXML lists, importing no library that loads a shared object. A test-only serializer (`tests/sxml-html-serializer.sls`), written against `vendor/cmark-gfm/src/html.c`, renders that tree back to HTML so it can be diffed against `markdown->html`. The convenience entry point `markdown->sxml` lives in `(cmark gfm)`, not in the adapter, so the adapter's purity gate survives.

**Tech Stack:** Chez Scheme 10.4.1+, R6RS libraries, SRFI-64 for tests, `cmark-gfm` 0.29.0.gfm.13 via the existing C shim, `wak-sxml-tools` (MIT) as a test-only dependency.

**Design spec:** [.plans/2026-08-17-stage-5-sxml-design.md](2026-08-17-stage-5-sxml-design.md). ADR-0011 (HTML vocabulary only), ADR-0012 (HTML as the oracle).

## Global Constraints

- **Every `tests/test-*.sps` must end with `(exit (if (zero? (test-runner-fail-count runner)) 0 1))`.** SRFI-64 sets no process exit status; a suite missing that line reports success through real failures. Nothing may be appended after it — it is dead code.
- **Never make `#f` the expected value of an assertion whose actual expression can raise.** SRFI-64's R6RS `%test-evaluate-with-catch` turns any exception into `#f` (`vendor/chez-srfi/%3a64/testing-impl.scm:568-571`), so such an assertion passes when the code under test crashes. Use a sentinel the failure path cannot produce: `(test-equal "…" 'agree (or (compare …) 'agree))`.
- **`0` is truthy in Scheme.** Never use `test-assert` where a value comparison will do.
- **Never let an assertion's meaning depend on argument evaluation order.** Chez evaluates arguments right-to-left in compiled library code, left-to-right when interpreted.
- **Read cmark semantics from `vendor/cmark-gfm/`, never from recall.**
- **A test is finished when you have watched it fail.** Before marking any task done: break the specific decision the assertion guards, run the suite, confirm that assertion fails *by name*, revert, confirm it passes. Record it in `.plans/stage-5-mutation-log.md`.
- **Run from the repo root**, with `make build` already run (it generates the gitignored `src/cmark/gfm/private/config.sls`).
- Single test suite run: `CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/<suite>.sps`
- Full run: `make test`. Purity gate: `make check-purity`. Pin gate: `make check-pins`.

---

## File Structure

| File | Responsibility |
|---|---|
| `src/cmark/gfm/private/conditions.sls` | **Modify** — add `&cmark-unsupported-node` |
| `src/cmark/gfm/options.sls` | **Modify** — add the `sxml-options` record |
| `src/cmark/gfm/sxml.sls` | **Create** — the pure AST→SXML transformation |
| `src/cmark/gfm.sls` | **Modify** — `markdown->sxml`, re-exports |
| `tests/sxml-html-serializer.sls` | **Create** — test-only SXML→HTML, mirrors `src/html.c` |
| `tests/spec-corpus.sls` | **Create** — test-only parser for cmark's spec files |
| `tests/test-sxml.sps` | **Create** — pure unit suite for the adapter |
| `tests/test-sxml-serializer.sps` | **Create** — unit suite for `sxml-html-serializer.sls` |
| `tests/test-sxml-differential.sps` | **Create** — the corpus oracle, both legs |
| `tests/test-sxml-portability.sps` | **Create** — `wak-sxml-tools` conformance and escaping |
| `tests/test-conditions.sps` | **Modify** — cover the new condition |
| `tests/test-options.sps` | **Modify** — cover `make-sxml-options` |
| `Makefile` | **Modify** — `check-purity`, `check-pins`, `deps` |
| `Akku.manifest` | **Modify** — `depends/dev` |

Naming note: `tests/test-sxml-serializer.sps` tests `tests/sxml-html-serializer.sls` (our serializer). The third-party suite is `tests/test-sxml-portability.sps`. The design spec §2 listed the latter under the former's name; the plan's names are authoritative.

---

### Task 1: `&cmark-unsupported-node`

**Files:**
- Modify: `src/cmark/gfm/private/conditions.sls`
- Modify: `src/cmark/gfm.sls`
- Test: `tests/test-conditions.sps`

**Interfaces:**
- Consumes: nothing
- Produces: `&cmark-unsupported-node`, `make-cmark-unsupported-node` (one argument: the native type string), `cmark-unsupported-node?`, `cmark-unsupported-node-type`

- [ ] **Step 1: Write the failing test**

Append to `tests/test-conditions.sps`, **before** its final `(exit …)` line:

```scheme
;; --- &cmark-unsupported-node -------------------------------------------
;; Compared against the carried value, not asserted truthy: the accessor
;; returning the wrong string, or a different condition being raised, must
;; both fail. 'no-raise is a sentinel no success path produces.
(test-equal "unsupported-node carries the native type string"
  "footnote_definition"
  (guard (e ((cmark-unsupported-node? e) (cmark-unsupported-node-type e))
            (#t 'wrong-condition))
    (raise (make-cmark-unsupported-node "footnote_definition"))
    'no-raise))

(test-equal "unsupported-node is a cmark-error"
  #t
  (guard (e ((cmark-error? e) #t) (#t 'wrong-condition))
    (raise (make-cmark-unsupported-node "x"))
    'no-raise))

;; It must NOT derive from &cmark-invalid-input: the document is valid, the
;; adapter is incomplete. A caller catching bad input must not swallow this.
(test-equal "unsupported-node is not invalid-input"
  'not-invalid-input
  (guard (e ((cmark-invalid-input? e) 'wrongly-invalid-input)
            ((cmark-unsupported-node? e) 'not-invalid-input)
            (#t 'wrong-condition))
    (raise (make-cmark-unsupported-node "x"))
    'no-raise))
```

Add `(cmark gfm)` to that suite's imports if it is not already there.

- [ ] **Step 2: Run test to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-conditions.sps
```

Expected: FAIL at import — `unbound variable make-cmark-unsupported-node`.

- [ ] **Step 3: Add the condition type**

In `src/cmark/gfm/private/conditions.sls`, add to the `(export …)` list:

```scheme
          &cmark-unsupported-node make-cmark-unsupported-node
          cmark-unsupported-node? cmark-unsupported-node-type
```

and in the body, after `&cmark-render-failed`:

```scheme
  ;; The SXML adapter has no HTML vocabulary for a node type it does not
  ;; know. Derives from &cmark-error directly, NOT from
  ;; &cmark-invalid-input: the document is well-formed, the adapter is
  ;; incomplete, and a caller guarding bad input must not swallow a gap in
  ;; our own coverage. Project plan 12 asked for this condition; Stage 3
  ;; did not need it because it preserves unknown types as `extension`
  ;; nodes rather than raising.
  (define-condition-type &cmark-unsupported-node &cmark-error
    make-cmark-unsupported-node cmark-unsupported-node?
    (type cmark-unsupported-node-type))
```

- [ ] **Step 4: Re-export from the public facade**

In `src/cmark/gfm.sls`, add to the `(export …)` list under the conditions block:

```scheme
          &cmark-unsupported-node cmark-unsupported-node?
          cmark-unsupported-node-type
```

- [ ] **Step 5: Run test to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-conditions.sps
```

Expected: PASS, `# of expected passes 26`.

- [ ] **Step 6: Mutation — watch it fail**

In a scratch copy outside the repo, change the derivation to
`&cmark-invalid-input`. Run the suite. Confirm **"unsupported-node is not
invalid-input"** fails and reports `wrongly-invalid-input`. Revert; confirm
green. Record in `.plans/stage-5-mutation-log.md`.

- [ ] **Step 7: Commit**

```bash
git add src/cmark/gfm/private/conditions.sls src/cmark/gfm.sls tests/test-conditions.sps .plans/stage-5-mutation-log.md
git commit -m "feat: add &cmark-unsupported-node for node types SXML cannot express"
```

---

### Task 2: `make-sxml-options`

**Files:**
- Modify: `src/cmark/gfm/options.sls`
- Modify: `src/cmark/gfm.sls`
- Test: `tests/test-options.sps`

**Interfaces:**
- Consumes: `make-cmark-invalid-option` from Task 1's library (already present)
- Produces: `make-sxml-options` (plist), `default-sxml-options`, `sxml-options-with`, `sxml-options?`, `sxml-options-raw-html` → symbol `omit` or `escape`

- [ ] **Step 1: Write the failing test**

Append to `tests/test-options.sps`, before its final `(exit …)`:

```scheme
;; --- sxml options -------------------------------------------------------
(test-equal "default raw-html policy is omit"
  'omit (sxml-options-raw-html (default-sxml-options)))

(test-equal "raw-html can be set to escape"
  'escape (sxml-options-raw-html (make-sxml-options 'raw-html 'escape)))

(test-equal "sxml-options-with returns a new record"
  '(omit escape)
  (let ((base (default-sxml-options)))
    (list (sxml-options-raw-html base)
          (sxml-options-raw-html (sxml-options-with base 'raw-html 'escape)))))

(test-equal "an unknown sxml key is rejected"
  '(raw-htlm unknown-key)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (make-sxml-options 'raw-htlm 'escape)
    'no-raise))

(test-equal "a duplicate sxml key is rejected"
  '(raw-html duplicate-key)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (make-sxml-options 'raw-html 'omit 'raw-html 'escape)
    'no-raise))

(test-equal "an unknown raw-html value is rejected"
  '(raw-html invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (make-sxml-options 'raw-html 'trusted)
    'no-raise))

;; sxml-options-with runs the same validation as the constructor, so an
;; invalid value cannot enter through the back door.
(test-equal "sxml-options-with validates too"
  '(raw-html invalid-value)
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e)))
            (#t 'wrong-condition))
    (sxml-options-with (default-sxml-options) 'raw-html 'reject)
    'no-raise))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
```

Expected: FAIL at import — `unbound variable default-sxml-options`.

- [ ] **Step 3: Implement the record**

In `src/cmark/gfm/options.sls`, add to `(export …)`:

```scheme
          make-sxml-options default-sxml-options sxml-options-with
          sxml-options? sxml-options-raw-html
```

and add to the body, after the `cmark-options` definitions:

```scheme
  ;; --- SXML adapter options ----------------------------------------------
  ;; Separate from cmark-options because they govern OUR renderer, not
  ;; cmark's parse. A record rather than a bare symbol argument: it inherits
  ;; the plist validation above, which a symbol cannot have, and a second
  ;; field later costs no arity change at any call site.
  (define-record-type (sxml-options %make-sxml-options sxml-options?)
    (fields raw-html))

  (define sxml-option-keys '(raw-html))

  ;; Deliberately a separate walker from plist->alist rather than a
  ;; parameterised one: sharing would mean threading the key list through,
  ;; and the two key sets must not be able to accept each other's keys.
  (define (sxml-plist->alist plist)
    (let loop ((p plist) (seen '()) (acc '()))
      (cond
        ((null? p) (reverse acc))
        ((null? (cdr p))
         (raise (make-cmark-invalid-option #f 'malformed-plist)))
        (else
         (let ((k (car p)) (v (cadr p)))
           (unless (memq k sxml-option-keys)
             (raise (make-cmark-invalid-option k 'unknown-key)))
           (when (memq k seen)
             (raise (make-cmark-invalid-option k 'duplicate-key)))
           (loop (cddr p) (cons k seen) (cons (cons k v) acc)))))))

  ;; Runs on the RESULTING record so both constructors share one policy,
  ;; exactly as `validate` does for cmark-options.
  (define (validate-sxml o)
    (unless (memq (sxml-options-raw-html o) '(omit escape))
      (raise (make-cmark-invalid-option 'raw-html 'invalid-value)))
    o)

  (define (make-sxml-options . plist)
    (let ((a (sxml-plist->alist plist)))
      (validate-sxml (%make-sxml-options (lookup a 'raw-html 'omit)))))

  (define (default-sxml-options) (make-sxml-options))

  (define (sxml-options-with o . plist)
    (let ((a (sxml-plist->alist plist)))
      (validate-sxml
       (%make-sxml-options
        (lookup a 'raw-html (sxml-options-raw-html o))))))
```

- [ ] **Step 4: Re-export from the public facade**

In `src/cmark/gfm.sls`, add to `(export …)`:

```scheme
          ;; SXML options
          make-sxml-options default-sxml-options sxml-options-with
          sxml-options? sxml-options-raw-html
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
make check-purity
```

Expected: PASS, `# of expected passes 56`; purity still holds.

- [ ] **Step 6: Mutation — watch it fail**

In a scratch copy, delete the `validate-sxml` call from `sxml-options-with`
only. Confirm **"sxml-options-with validates too"** fails while the
constructor tests stay green — that is the assertion proving the back door is
closed. Revert; confirm green. Record it.

- [ ] **Step 7: Commit**

```bash
git add src/cmark/gfm/options.sls src/cmark/gfm.sls tests/test-options.sps .plans/stage-5-mutation-log.md
git commit -m "feat: add sxml-options with the raw-html policy"
```

---

### Task 3: The test-only HTML serializer

**Files:**
- Create: `tests/sxml-html-serializer.sls`
- Test: `tests/test-sxml-serializer.sps`

**Interfaces:**
- Consumes: nothing
- Produces: `(sxml->html tree)` → string. Accepts `(*TOP* child …)`, elements `(tag child …)` or `(tag (@ (name "value") …) child …)`, strings, and `(*COMMENT* "text")`.

This task builds the oracle's other half before any adapter code exists, so
every later adapter task can be checked against cmark immediately rather than
after four tasks of unverified work.

- [ ] **Step 1: Write the failing test**

Create `tests/test-sxml-serializer.sps`:

```scheme
#!r6rs
;; Unit suite for tests/sxml-html-serializer.sls -- our test-only SXML->HTML
;; serializer, written against vendor/cmark-gfm/src/html.c.
;;
;; These expectations are hand-written, which is fine HERE: this suite proves
;; the serializer implements html.c's formatting rules. The untunable
;; property comes in test-sxml-differential.sps, where the serializer is
;; composed with the adapter and judged against cmark's real bytes.
(import (rnrs)
        (srfi :64)
        (sxml-html-serializer))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml-serializer")

;; --- elements and text --------------------------------------------------
(test-equal "a text child is escaped like escape_html"
  "<p>a &amp; b &lt;c&gt; &quot;d&quot;</p>\n"
  (sxml->html '(*TOP* (p "a & b <c> \"d\""))))

;; ' and / are NOT escaped: houdini_escape_html0 escapes them only in secure
;; mode (src/houdini_html_e.c:18-33), and html.c never passes secure = 1.
(test-equal "apostrophe and slash survive unescaped in text"
  "<p>it's a/b</p>\n"
  (sxml->html '(*TOP* (p "it's a/b"))))

(test-equal "inline elements nest without whitespace"
  "<p>a <em>b</em> <strong>c</strong> <del>d</del> <code>e</code></p>\n"
  (sxml->html '(*TOP* (p "a " (em "b") " " (strong "c") " "
                         (del "d") " " (code "e")))))

;; --- attributes ---------------------------------------------------------
(test-equal "attributes render in list order"
  "<p><a href=\"/x\" title=\"t\">l</a></p>\n"
  (sxml->html '(*TOP* (p (a (@ (href "/x") (title "t")) "l")))))

;; href and src take the entity half of houdini_escape_href
;; (src/houdini_href_e.c:64-76): & and ' become entities. Everything else
;; takes escape_html, where ' survives.
(test-equal "href escapes ampersand and apostrophe as entities"
  "<p><a href=\"/a&amp;b&#x27;c\">l</a></p>\n"
  (sxml->html '(*TOP* (p (a (@ (href "/a&b'c")) "l")))))

(test-equal "a non-href attribute leaves apostrophe alone"
  "<p><a href=\"/x\" title=\"it's\">l</a></p>\n"
  (sxml->html '(*TOP* (p (a (@ (href "/x") (title "it's")) "l")))))

;; --- childless elements -------------------------------------------------
(test-equal "hr and br close XHTML-style with a trailing newline"
  "<hr />\n<p>a<br />\nb</p>\n"
  (sxml->html '(*TOP* (hr) (p "a" (br) "\nb"))))

(test-equal "img and input close XHTML-style with no newline"
  "<p><img src=\"/i\" alt=\"a\" /><input type=\"checkbox\" disabled=\"\" /></p>\n"
  (sxml->html '(*TOP* (p (img (@ (src "/i") (alt "a")))
                         (input (@ (type "checkbox") (disabled "")))))))

;; --- block newline placement -------------------------------------------
(test-equal "blockquote and list open tags are followed by a newline"
  "<blockquote>\n<p>a</p>\n</blockquote>\n"
  (sxml->html '(*TOP* (blockquote (p "a")))))

(test-equal "list items close with a newline, open without"
  "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"
  (sxml->html '(*TOP* (ul (li "a") (li "b")))))

(test-equal "ol start renders as an attribute"
  "<ol start=\"3\">\n<li>a</li>\n</ol>\n"
  (sxml->html '(*TOP* (ol (@ (start "3")) (li "a")))))

(test-equal "pre and code nest with no injected whitespace"
  "<pre><code class=\"language-c\">int x;\n</code></pre>\n"
  (sxml->html '(*TOP* (pre (code (@ (class "language-c")) "int x;\n")))))

;; The load-bearing one. cmark_html_render_cr (src/html.h:8-11) emits a
;; newline only when the buffer does not already end in one. A serializer
;; that appends unconditionally agrees on most documents and diverges
;; exactly where two block boundaries meet -- here, </blockquote> already
;; ends in \n, so the following <p> must NOT add a second.
(test-equal "newlines at block boundaries collapse, they do not stack"
  "<blockquote>\n<p>a</p>\n</blockquote>\n<p>b</p>\n"
  (sxml->html '(*TOP* (blockquote (p "a")) (p "b"))))

;; --- tables -------------------------------------------------------------
(test-equal "table sections and cells place newlines like table.c"
  (string-append "<table>\n<thead>\n<tr>\n<th align=\"left\">h</th>\n"
                 "</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n"
                 "</tr>\n</tbody>\n</table>\n")
  (sxml->html '(*TOP* (table (thead (tr (th (@ (align "left")) "h")))
                             (tbody (tr (td "b")))))))

;; --- comments -----------------------------------------------------------
;; html.c:257,265 wraps a raw HTML BLOCK in render_cr on both sides;
;; html.c:335-337 wraps an inline one in nothing. The serializer cannot ask
;; the Markdown, so it decides structurally: a comment whose parent is a
;; block container is a block comment.
(test-equal "a block-level comment gets newlines on both sides"
  "<p>a</p>\n<!-- raw HTML omitted -->\n<p>b</p>\n"
  (sxml->html '(*TOP* (p "a") (*COMMENT* " raw HTML omitted ") (p "b"))))

(test-equal "an inline comment gets none"
  "<p>a<!-- raw HTML omitted -->b</p>\n"
  (sxml->html '(*TOP* (p "a" (*COMMENT* " raw HTML omitted ") "b"))))

(test-end "sxml-serializer")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-serializer.sps
```

Expected: FAIL at import — library `(sxml-html-serializer)` not found.

- [ ] **Step 3: Implement the serializer**

Create `tests/sxml-html-serializer.sls`:

```scheme
#!r6rs
;;; SXML -> HTML, written against vendor/cmark-gfm/src/html.c. TEST ONLY.
;;;
;;; This is one half of ADR-0012's oracle. It is deliberately GENERIC over
;;; the tree: it maps an element name to a tag, an attribute list to
;;; attributes, and consults the static tables below for childless tags and
;;; newline placement. It never inspects the Markdown and holds no node-type
;;; knowledge, so it cannot compensate for an adapter that emits the wrong
;;; element -- a wrong tag is a byte difference, not a serializer that
;;; quietly agrees.
;;;
;;; Not under src/: this ships with the tests, and the library is reachable
;;; because the Makefile puts tests/ on CHEZ_LIBDIRS.
(library (sxml-html-serializer)
  (export sxml->html)
  (import (rnrs))

  ;; --- escaping ----------------------------------------------------------
  ;; houdini_escape_html0 with secure = 0 (src/houdini_html_e.c:18-33).
  ;; Exactly four characters. ' and / are escaped only in secure mode, which
  ;; html.c never requests.
  (define (escape-html s port)
    (string-for-each
     (lambda (c)
       (case c
         ((#\&) (put-string port "&amp;"))
         ((#\<) (put-string port "&lt;"))
         ((#\>) (put-string port "&gt;"))
         ((#\") (put-string port "&quot;"))
         (else  (put-char port c))))
     s))

  ;; The ENTITY half of houdini_escape_href (src/houdini_href_e.c:64-76).
  ;; The percent-encoding half belongs to the adapter, not here: doing both
  ;; in one place would double-encode whichever side ran second.
  (define (escape-href s port)
    (string-for-each
     (lambda (c)
       (case c
         ((#\&)  (put-string port "&amp;"))
         ((#\')  (put-string port "&#x27;"))
         (else   (put-char port c))))
     s))

  (define (href-attribute? name) (memq name '(href src)))

  ;; --- formatting tables -------------------------------------------------
  ;; Every entry is a line of html.c. Changing one to make a test pass is
  ;; changing what cmark does, which the differential will reject.

  ;; Written " />" and given no children (html.c:280-285, 315-317, 402-419;
  ;; extensions/tasklist.c:125-128).
  (define void-tags '(hr br img input))

  ;; Void tags followed by a literal newline: hr (html.c:284) and br
  ;; (html.c:316). img and input are inline and get none.
  (define void-tags-with-newline '(hr br))

  ;; cmark_html_render_cr before the OPEN tag.
  (define cr-before-open
    '(blockquote ul ol li h1 h2 h3 h4 h5 h6 pre p hr
      table thead tbody tr th td))

  ;; cmark_html_render_cr after the open tag (html.c:154,171,176,181 write
  ;; ">\n"; extensions/table.c:780,783 write the tag then render_cr).
  (define cr-after-open '(blockquote ul ol thead tbody))

  ;; cmark_html_render_cr before the CLOSE tag (html.c:158;
  ;; extensions/table.c:765,770,790,793).
  (define cr-before-close '(blockquote table thead tbody tr))

  ;; A literal newline after the close tag (html.c:159,191,197,211,254,301;
  ;; extensions/table.c:772 uses render_cr, same effect at end of table).
  (define newline-after-close
    '(blockquote ul ol li h1 h2 h3 h4 h5 h6 pre p table tbody))

  ;; A *COMMENT* directly inside one of these is a block comment and takes
  ;; render_cr on both sides (html.c:257,265). Anywhere else it is inline
  ;; and takes none (html.c:335-337). Block-level content only ever appears
  ;; in these three containers.
  (define block-comment-parents '(*TOP* blockquote li))

  ;; --- output ------------------------------------------------------------
  (define (attributes? x)
    (and (pair? x) (eq? '@ (car x))))

  (define (write-attributes attrs port)
    (for-each
     (lambda (a)
       (put-char port #\space)
       (put-string port (symbol->string (car a)))
       (put-string port "=\"")
       (if (href-attribute? (car a))
           (escape-href (cadr a) port)
           (escape-html (cadr a) port))
       (put-char port #\"))
     (cdr attrs)))

  (define (sxml->html tree)
    ;; Chunks accumulate in reverse and are joined once. render_cr's "only if
    ;; the buffer does not already end in a newline" rule needs one bit of
    ;; history, not the buffer itself, so last-newline? carries it -- which
    ;; keeps this linear instead of re-copying a growing string per emit.
    (let ((chunks '()) (last-newline? #f))
      (define (emit s)
        (when (positive? (string-length s))
          (set! chunks (cons s chunks))
          (set! last-newline?
                (char=? #\newline (string-ref s (- (string-length s) 1))))))
      ;; The (pair? chunks) guard is html.c's `html->size &&`: no newline is
      ;; emitted before anything has been written.
      (define (emit-cr)
        (when (and (pair? chunks) (not last-newline?)) (emit "\n")))
      (define (with-port proc)
        (let-values (((port get) (open-string-output-port)))
          (proc port)
          (emit (get))))

      (define (walk node parent)
        (cond
          ((string? node) (with-port (lambda (p) (escape-html node p))))
          ((and (pair? node) (eq? '*COMMENT* (car node)))
           (let ((block? (memq parent block-comment-parents)))
             (when block? (emit-cr))
             (emit "<!--") (emit (cadr node)) (emit "-->")
             (when block? (emit-cr))))
          ((and (pair? node) (eq? '*TOP* (car node)))
           (for-each (lambda (c) (walk c '*TOP*)) (cdr node)))
          ((pair? node)
           (let* ((tag  (car node))
                  (rest (cdr node))
                  (attrs (and (pair? rest) (attributes? (car rest))
                              (car rest)))
                  (kids (if attrs (cdr rest) rest))
                  (name (symbol->string tag)))
             (when (memq tag cr-before-open) (emit-cr))
             (emit "<") (emit name)
             (when attrs (with-port (lambda (p) (write-attributes attrs p))))
             (cond
               ((memq tag void-tags)
                (emit " />")
                (when (memq tag void-tags-with-newline) (emit "\n")))
               (else
                (emit ">")
                (when (memq tag cr-after-open) (emit-cr))
                (for-each (lambda (c) (walk c tag)) kids)
                (when (memq tag cr-before-close) (emit-cr))
                (emit "</") (emit name) (emit ">")
                (when (memq tag newline-after-close) (emit "\n"))))))
          (else (assertion-violation 'sxml->html "not an SXML node" node))))

      (walk tree #f)
      (apply string-append (reverse chunks)))))
```

- [ ] **Step 4: Run test to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-serializer.sps
```

Expected: PASS, `# of expected passes 16`.

- [ ] **Step 5: Mutation — watch it fail**

In a scratch copy, change `emit-cr` to emit `"\n"` unconditionally. Confirm
**"newlines at block boundaries collapse, they do not stack"** fails and the
others stay green. Revert; confirm green. Then remove `href` from
`href-attribute?` and confirm **"href escapes ampersand and apostrophe as
entities"** fails while **"a non-href attribute leaves apostrophe alone"**
stays green. Record both.

- [ ] **Step 6: Commit**

```bash
git add tests/sxml-html-serializer.sls tests/test-sxml-serializer.sps .plans/stage-5-mutation-log.md
git commit -m "test: add the SXML->HTML serializer that mirrors src/html.c"
```

---

### Task 4: The adapter — local block and inline nodes

**Files:**
- Create: `src/cmark/gfm/sxml.sls`
- Test: `tests/test-sxml.sps` (create), `tests/test-sxml-differential.sps` (create)
- Modify: `Makefile` (`check-purity`)

**Interfaces:**
- Consumes: `sxml-options-raw-html` (Task 2), `make-cmark-unsupported-node` (Task 1), the `(cmark gfm ast)` accessors
- Produces: `(markdown-ast->sxml ast)` and `(markdown-ast->sxml ast sxml-opts)` → an SXML tree rooted at `*TOP*`

Lists, tables, links, and images are **not** in this task — they land in
Tasks 5–7. This task establishes the dispatch and the node types whose
mapping is purely local.

- [ ] **Step 1: Write the failing pure test**

Create `tests/test-sxml.sps`:

```scheme
#!r6rs
;; PURE SUITE. This file must never import a library that loads a shared
;; object. `make check-purity` enforces it by running this file with
;; CHEZ_CMARK_GFM_SHIM poisoned. Check transitive imports before adding one
;; here or to sxml.sls.
(import (rnrs)
        (srfi :64)
        (cmark gfm ast)
        (cmark gfm options)
        (cmark gfm private conditions)
        (cmark gfm sxml))

(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "sxml")

(define (node type props kids) (make-markdown-node type props kids #f))
(define (text s) (node 'text (list (cons 'literal s)) '()))
(define (doc . kids) (node 'document '() kids))
(define (->sxml n) (markdown-ast->sxml n))

;; --- document root ------------------------------------------------------
(test-equal "a document becomes *TOP*"
  '(*TOP*) (->sxml (doc)))

;; --- headings -----------------------------------------------------------
(test-equal "heading level picks the tag"
  '(*TOP* (h1 "a") (h6 "b"))
  (->sxml (doc (node 'heading '((level . 1)) (list (text "a")))
               (node 'heading '((level . 6)) (list (text "b"))))))

;; --- text and inline containers ----------------------------------------
;; The literal is carried VERBATIM. Escaping is the serializer's job, and an
;; adapter that escaped here would double-escape on output.
(test-equal "a text literal is carried unescaped"
  '(*TOP* (p "a & <b>"))
  (->sxml (doc (node 'paragraph '() (list (text "a & <b>"))))))

(test-equal "inline containers map to their HTML tags"
  '(*TOP* (p (em "e") (strong "s") (del "d") (code "c")))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'emph '() (list (text "e")))
                           (node 'strong '() (list (text "s")))
                           (node 'strikethrough '() (list (text "d")))
                           (node 'code '((literal . "c")) '()))))))

(test-equal "blockquote wraps its blocks"
  '(*TOP* (blockquote (p "a")))
  (->sxml (doc (node 'blockquote '()
                     (list (node 'paragraph '() (list (text "a"))))))))

;; --- breaks -------------------------------------------------------------
;; html.c:319 -- a softbreak is a NEWLINE CHARACTER in the output, not an
;; element. It is content from cmark's inline stream, which is why it is the
;; one piece of whitespace that belongs in the tree.
(test-equal "softbreak is a newline string, linebreak is a br element"
  '(*TOP* (p "a" "\n" "b" (br) "c"))
  (->sxml (doc (node 'paragraph '()
                     (list (text "a") (node 'softbreak '() '()) (text "b")
                           (node 'linebreak '() '()) (text "c"))))))

(test-equal "thematic break is a childless hr"
  '(*TOP* (hr)) (->sxml (doc (node 'thematic-break '() '()))))

;; --- code blocks --------------------------------------------------------
(test-equal "a code block with no info has a bare code element"
  '(*TOP* (pre (code "x\n")))
  (->sxml (doc (node 'code-block '((literal . "x\n") (fence-info . "")) '()))))

;; html.c:223-227 scans the info string to the first whitespace; the
;; remainder is reachable only through CMARK_OPT_FULL_INFO_STRING, which
;; this library does not expose.
(test-equal "only the first token of the fence info becomes the class"
  '(*TOP* (pre (code (@ (class "language-scheme")) "x\n")))
  (->sxml (doc (node 'code-block
                     '((literal . "x\n") (fence-info . "scheme linenos=3"))
                     '()))))

;; --- raw HTML -----------------------------------------------------------
(test-equal "omit replaces raw HTML with cmark's comment"
  '(*TOP* (*COMMENT* " raw HTML omitted ")
          (p (*COMMENT* " raw HTML omitted ")))
  (->sxml (doc (node 'html-block '((literal . "<div>\n")) '())
               (node 'paragraph '()
                     (list (node 'html-inline '((literal . "<b>")) '()))))))

(test-equal "escape carries the literal through as text"
  '(*TOP* "<div>\n" (p "<b>"))
  (markdown-ast->sxml
   (doc (node 'html-block '((literal . "<div>\n")) '())
        (node 'paragraph '()
              (list (node 'html-inline '((literal . "<b>")) '()))))
   (make-sxml-options 'raw-html 'escape)))

;; --- unknown node types -------------------------------------------------
(test-equal "an extension node raises, carrying its native type"
  "footnote_definition"
  (guard (e ((cmark-unsupported-node? e) (cmark-unsupported-node-type e))
            (#t 'wrong-condition))
    (->sxml (doc (node 'extension '((native-type . "footnote_definition")) '())))
    'no-raise))

(test-end "sxml")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
```

Expected: FAIL at import — library `(cmark gfm sxml)` not found.

- [ ] **Step 3: Implement the adapter**

Create `src/cmark/gfm/sxml.sls`:

```scheme
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
                      (list '@ (list 'class (string-append "language-" info)))
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
```

- [ ] **Step 4: Run the pure test to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
```

Expected: PASS, `# of expected passes 12`.

- [ ] **Step 5: Add the suite to the purity gate**

In `Makefile`, change the `check-purity` loop line from

```make
	for t in tests/test-options.sps tests/test-ast.sps; do \
```

to

```make
	for t in tests/test-options.sps tests/test-ast.sps tests/test-sxml.sps; do \
```

Run:

```bash
make check-purity
```

Expected: three "purity holds" lines.

- [ ] **Step 6: Write the differential smoke test**

Create `tests/test-sxml-differential.sps`. It grows through Tasks 5–7 and 10;
this is its first form.

```scheme
#!r6rs
;;; The SXML tree verified against cmark's own HTML rendering of the same
;;; parse (ADR-0012).
;;;
;;; The load-bearing property is that the expectation is produced by cmark,
;;; so "adjust it until it passes" is not available. The serializer in
;;; tests/sxml-html-serializer.sls is generic over the tree and holds no
;;; node-type knowledge, so it cannot compensate for an adapter that emits
;;; the wrong element.
(import (rnrs)
        (srfi :64)
        (cmark gfm)
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

(test-end "sxml-differential")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 7: Run the differential to verify it passes**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: PASS, `# of expected passes 9`. If "raw html agrees" fails, the
`*COMMENT*` block-versus-inline rule in the serializer is wrong — compare
against `html.c:256-266` and `html.c:335-340`, not against the test.

- [ ] **Step 8: Mutation — watch it fail**

In a scratch copy of `sxml.sls`, map `strikethrough` to `s` instead of `del`.
Confirm **"emphasis agrees"** fails in the differential and reports both
strings, and that the serializer's own suite stays green — that is the proof
the serializer cannot compensate. Revert. Then change `first-token` to return
the whole string and confirm **"only the first token of the fence info
becomes the class"** and **"code blocks agree"** both fail. Revert; confirm
green. Record both.

- [ ] **Step 9: Commit**

```bash
git add src/cmark/gfm/sxml.sls tests/test-sxml.sps tests/test-sxml-differential.sps Makefile .plans/stage-5-mutation-log.md
git commit -m "feat: add the SXML adapter for local block and inline nodes"
```

---

### Task 5: Links, images, and the URL policy

**Files:**
- Modify: `src/cmark/gfm/sxml.sls`
- Test: `tests/test-sxml.sps`, `tests/test-sxml-differential.sps`

**Interfaces:**
- Consumes: `node->sxml` dispatch from Task 4
- Produces: `link` → `(a (@ (href …) (title …)) …)`, `image` → `(img (@ (src …) (alt …) (title …)))`. `title` is present only when non-empty.

- [ ] **Step 1: Write the failing pure tests**

Append to `tests/test-sxml.sps`, before `(test-end "sxml")`:

```scheme
;; --- links --------------------------------------------------------------
(define (link url title . kids)
  (node 'link (list (cons 'url url) (cons 'title title)) kids))

;; html.c:392 writes the title attribute only when title.len is non-zero.
;; An empty title="" is a byte difference, not a harmless extra.
(test-equal "an empty title is omitted, a present one is kept"
  '(*TOP* (p (a (@ (href "/x")) "l") (a (@ (href "/y") (title "t")) "m")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "/x" "" (text "l"))
                           (link "/y" "t" (text "m")))))))

;; houdini_escape_href percent-encodes every byte outside HREF_SAFE
;; (src/houdini_href_e.c:32-44). & and ' are left ALONE here -- they are the
;; serializer's half of the split, and encoding them here would produce
;; &amp;amp; on output.
(test-equal "a URL is percent-encoded but ampersand and apostrophe pass through"
  '(*TOP* (p (a (@ (href "/a%20b?x=1&y='z'%C3%A9")) "l")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "/a b?x=1&y='z'é" "" (text "l")))))))

;; src/scanners.re:345-354. re2c single-quoted literals are
;; case-insensitive, so mixed case is caught. A rejected URL yields an EMPTY
;; attribute (html.c:387-391), not a raise and not a removed attribute.
(test-equal "dangerous schemes yield an empty href, in any case"
  '(*TOP* (p (a (@ (href "")) "a") (a (@ (href "")) "b")
             (a (@ (href "")) "c") (a (@ (href "")) "d")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "javascript:alert(1)" "" (text "a"))
                           (link "JaVaScRiPt:alert(1)" "" (text "b"))
                           (link "vbscript:x" "" (text "c"))
                           (link "file:///etc/passwd" "" (text "d")))))))

(test-equal "data: is rejected except for the four image subtypes"
  '(*TOP* (p (a (@ (href "")) "html")
             (a (@ (href "data:image/png;base64,AA")) "png")
             (a (@ (href "data:image/webp,x")) "webp")))
  (->sxml (doc (node 'paragraph '()
                     (list (link "data:text/html,<b>" "" (text "html"))
                           (link "data:image/png;base64,AA" "" (text "png"))
                           (link "data:image/webp,x" "" (text "webp")))))))

;; --- images -------------------------------------------------------------
;; html.c:118-139 -- children render in PLAIN mode into alt: text, code, and
;; html-inline contribute literals; breaks contribute a single space;
;; everything else contributes nothing but is still descended into.
(test-equal "image alt is the flattened plaintext of its children"
  '(*TOP* (p (img (@ (src "/i") (alt "a b c d e")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "/i") (title . ""))
                                 (list (text "a ")
                                       (node 'emph '() (list (text "b")))
                                       (text " ")
                                       (node 'code '((literal . "c")) '())
                                       (node 'softbreak '() '())
                                       (node 'html-inline '((literal . "d")) '())
                                       (text " e"))))))))

(test-equal "an image title is omitted when empty and kept when present"
  '(*TOP* (p (img (@ (src "/i") (alt "")))
             (img (@ (src "/j") (alt "") (title "t")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "/i") (title . "")) '())
                           (node 'image '((url . "/j") (title . "t")) '()))))))

(test-equal "an image src takes the same dangerous-URL policy"
  '(*TOP* (p (img (@ (src "") (alt "")))))
  (->sxml (doc (node 'paragraph '()
                     (list (node 'image '((url . "javascript:x") (title . ""))
                                 '()))))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
```

Expected: FAIL — `&cmark-unsupported-node` raised for `link`, since Task 4's
`else` branch catches unmapped types.

- [ ] **Step 3: Implement URLs, links, and images**

In `src/cmark/gfm/sxml.sls`, add before `node->sxml`:

```scheme
  ;; --- URLs --------------------------------------------------------------
  ;; HREF_SAFE, transcribed from src/houdini_href_e.c:32-44. Every other
  ;; byte becomes %XX. & and ' are NOT handled here: houdini_escape_href
  ;; writes them as HTML entities, which is serialization, not a property of
  ;; the value. Doing both halves in one place double-encodes whichever ran
  ;; second (design spec 5.3).
  ;; Transcribed from the TABLE BYTES, not from the comment above them -- the
  ;; comment lists a slightly different set. Safe: alphanumeric plus
  ;;   ! # $ % ( ) * + , - . / : ; = ? @ _ ~
  ;; & and ' are absent from the table because houdini handles them
  ;; specially; they are included HERE so they pass through untouched for
  ;; the serializer to entity-escape.
  (define href-safe-extra
    (string->list "!#$%()*+,-./:;=?@_~&'"))

  (define (href-safe-byte? b)
    (let ((c (integer->char b)))
      (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9)
          (memv c href-safe-extra))))

  (define hex "0123456789ABCDEF")

  (define (percent-encode s)
    (let-values (((port get) (open-string-output-port)))
      (let ((bv (string->utf8 s)))
        (do ((i 0 (+ i 1))) ((= i (bytevector-length bv)))
          (let ((b (bytevector-u8-ref bv i)))
            (if (href-safe-byte? b)
                (put-char port (integer->char b))
                (begin (put-char port #\%)
                       (put-char port (string-ref hex (div b 16)))
                       (put-char port (string-ref hex (mod b 16))))))))
      (get)))

  ;; ASCII-only on purpose. string-downcase is Unicode-aware and can change
  ;; a string's LENGTH, which would misalign the prefix tests below; scheme
  ;; names are ASCII, so this is both correct and total.
  (define (ascii-downcase s)
    (string-map (lambda (c)
                  (if (char<=? #\A c #\Z)
                      (integer->char (+ 32 (char->integer c)))
                      c))
                s))

  (define (prefix? p s)
    (and (>= (string-length s) (string-length p))
         (string=? p (substring s 0 (string-length p)))))

  ;; src/scanners.re:345-354. The data:image allowlist is checked FIRST,
  ;; exactly as re2c orders the rules, so data:image/png survives the
  ;; data: rejection that follows it.
  (define (dangerous-url? url)
    (let ((u (ascii-downcase url)))
      (cond
        ((or (prefix? "data:image/png"  u) (prefix? "data:image/gif"  u)
             (prefix? "data:image/jpeg" u) (prefix? "data:image/webp" u))
         #f)
        ((or (prefix? "javascript:" u) (prefix? "vbscript:" u)
             (prefix? "file:" u) (prefix? "data:" u))
         #t)
        (else #f))))

  ;; A rejected URL yields an empty value, matching html.c:387-391 and
  ;; html.c:405-409. Not a raise: this mirrors cmark's renderer, and a
  ;; document with one bad link should still convert.
  (define (safe-url url)
    (if (dangerous-url? url) "" (percent-encode url)))

  ;; --- image alt ---------------------------------------------------------
  ;; html.c:122-139, plain mode.
  (define (plain-text n port)
    (case (markdown-node-type n)
      ((text code html-inline) (put-string port (prop n 'literal)))
      ((softbreak linebreak)   (put-char port #\space))
      (else
       ;; Contributes nothing itself, but its children still render --
       ;; the plain-mode branch returns before the element markup, it does
       ;; not skip the subtree.
       (for-each (lambda (c) (plain-text c port))
                 (markdown-node-children n)))))

  (define (alt-text n)
    (let-values (((port get) (open-string-output-port)))
      (for-each (lambda (c) (plain-text c port)) (markdown-node-children n))
      (get)))

  (define (maybe-title title)
    (if (string=? "" title) '() (list (list 'title title))))
```

and add these cases to `node->sxml`, before the `(extension)` case:

```scheme
      ((link)
       (cons 'a
             (cons (cons '@ (cons (list 'href (safe-url (prop n 'url)))
                                  (maybe-title (prop n 'title))))
                   (children->sxml n raw-html))))
      ((image)
       (list 'img
             (cons '@ (cons (list 'src (safe-url (prop n 'url)))
                            (cons (list 'alt (alt-text n))
                                  (maybe-title (prop n 'title)))))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
make check-purity
```

Expected: PASS, `# of expected passes 19`.

- [ ] **Step 5: Extend the differential**

In `tests/test-sxml-differential.sps`, add before `(test-end …)`:

```scheme
(agrees "links agree"   "[a](/x) [b](/y \"t\") [c](/a%20b?x=1&y=2)\n")
(agrees "autolinks agree" "<https://example.com/a?b=1&c=2> and www.example.com\n")
(agrees "unsafe links agree"
        "[a](javascript:alert(1)) [b](JaVaScRiPt:x) [c](file:///etc/passwd)\n")
(agrees "data urls agree"
        "![a](data:image/png;base64,AA) [b](data:text/html,<b>)\n")
(agrees "images agree" "![*a* `b`](/i \"t\") ![](/j)\n")
(agrees "non-ascii urls agree" "[a](/café/naïve) [b](/a b)\n")
```

- [ ] **Step 6: Run the differential**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: PASS, `# of expected passes 15`.

- [ ] **Step 7: Mutation — watch it fail**

Three, in a scratch copy:

1. Percent-encode `&` as well (remove it from `href-safe-extra`). Confirm
   **"a URL is percent-encoded but ampersand and apostrophe pass through"**
   and **"links agree"** both fail.
2. Move the `data:image` allowlist branch *after* the `data:` rejection.
   Confirm **"data: is rejected except for the four image subtypes"** fails
   and reports an empty href for the png.
3. Delete the `else` branch of `plain-text` (so nested nodes contribute
   nothing). Confirm **"image alt is the flattened plaintext of its
   children"** fails and **"images agree"** fails.

Revert each; confirm green. Record all three.

- [ ] **Step 8: Commit**

```bash
git add src/cmark/gfm/sxml.sls tests/test-sxml.sps tests/test-sxml-differential.sps .plans/stage-5-mutation-log.md
git commit -m "feat: map links and images, with cmark's URL policy and alt flattening"
```

---

### Task 6: Lists, list items, and task items

**Files:**
- Modify: `src/cmark/gfm/sxml.sls`
- Test: `tests/test-sxml.sps`, `tests/test-sxml-differential.sps`

**Interfaces:**
- Consumes: `node->sxml` dispatch
- Produces: `list` → `(ul …)` or `(ol …)` / `(ol (@ (start "N")) …)`; `item` → `(li …)`, with a leading checkbox when `task?`

- [ ] **Step 1: Write the failing pure tests**

Append to `tests/test-sxml.sps`, before `(test-end "sxml")`:

```scheme
;; --- lists --------------------------------------------------------------
(define (li . kids)
  (node 'item '((index . 1) (task? . #f) (checked? . #f)) kids))

(define (bullet tight? . items)
  (node 'list (list (cons 'kind 'bullet) (cons 'start 1)
                    (cons 'tight? tight?) (cons 'delimiter 'none))
        items))

(define (ordered start tight? . items)
  (node 'list (list (cons 'kind 'ordered) (cons 'start start)
                    (cons 'tight? tight?) (cons 'delimiter 'period))
        items))

(define (para . kids) (node 'paragraph '() kids))

;; html.c:174-183 -- start is written only when it is not 1.
(test-equal "ol start is emitted only when it is not one"
  '(*TOP* (ol (li (p "a"))) (ol (@ (start "3")) (li (p "a"))))
  (->sxml (doc (ordered 1 #f (li (para (text "a"))))
               (ordered 3 #f (li (para (text "a")))))))

;; html.c:287-297 -- a paragraph whose GRANDPARENT list is tight emits no
;; <p> at all; its children go straight into the <li>. A tight list is not a
;; list that renders compactly, it is a list with no paragraph elements.
(test-equal "a tight list has no p elements, a loose one does"
  '(*TOP* (ul (li "a")) (ul (li (p "a"))))
  (->sxml (doc (bullet #t (li (para (text "a"))))
               (bullet #f (li (para (text "a")))))))

;; Tightness comes from the ENCLOSING list only. A loose list nested inside a
;; tight one keeps its paragraphs.
(test-equal "tightness does not leak into a nested list"
  '(*TOP* (ul (li "a" (ul (li (p "b"))))))
  (->sxml (doc (bullet #t (li (para (text "a"))
                              (bullet #f (li (para (text "b")))))))))

;; extensions/tasklist.c:124-128. Note the attribute ORDER and that an
;; unchecked box has no checked attribute at all. The trailing space cmark
;; writes after "/>" is a text node here.
(test-equal "task items get a disabled checkbox, checked ones get the attribute"
  '(*TOP* (ul (li (input (@ (type "checkbox") (checked "") (disabled ""))) " " "a")
              (li (input (@ (type "checkbox") (disabled ""))) " " "b")))
  (->sxml (doc (bullet #t
                       (node 'item '((index . 1) (task? . #t) (checked? . #t))
                             (list (para (text "a"))))
                       (node 'item '((index . 2) (task? . #t) (checked? . #f))
                             (list (para (text "b"))))))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
```

Expected: FAIL — `&cmark-unsupported-node` for `list`.

- [ ] **Step 3: Implement lists**

Tightness has to reach the paragraph two levels down, so `node->sxml` gains a
`tight?` parameter. In `src/cmark/gfm/sxml.sls`, change every
`node->sxml` / `children->sxml` call to thread it:

```scheme
  (define (children->sxml n raw-html tight?)
    (map (lambda (c) (node->sxml c raw-html tight?))
         (markdown-node-children n)))

  (define (element tag n raw-html tight?)
    (cons tag (children->sxml n raw-html tight?)))
```

Update the existing cases to pass `tight?` through unchanged, then add:

```scheme
      ((list)
       (let ((kids (children->sxml n raw-html (prop n 'tight?)))
             (start (prop n 'start)))
         (if (eq? 'ordered (prop n 'kind))
             (if (= 1 start)
                 (cons 'ol kids)
                 (cons 'ol (cons (list '@ (list 'start (number->string start)))
                                 kids)))
             (cons 'ul kids))))
      ((item)
       (let ((kids (children->sxml n raw-html tight?)))
         (cons 'li
               (if (prop n 'task?)
                   (cons (list 'input
                               (cons '@
                                     (cons '(type "checkbox")
                                           (append
                                            (if (prop n 'checked?)
                                                '((checked ""))
                                                '())
                                            '((disabled ""))))))
                         (cons " " kids))
                   kids))))
```

and change the `paragraph` case to honour tightness:

```scheme
      ((paragraph)
       ;; html.c:287-297: inside a tight list the paragraph contributes its
       ;; children directly, with no element of its own. `tight?` is the
       ;; enclosing LIST's flag, threaded down through the item, because a
       ;; paragraph cannot see its own grandparent here.
       (if tight?
           (cons 'splice (children->sxml n raw-html tight?))
           (element 'p n raw-html tight?)))
```

A spliced paragraph returns a marker rather than a value, so
`children->sxml` must flatten it. Replace `children->sxml` with:

```scheme
  (define (children->sxml n raw-html tight?)
    (let loop ((cs (markdown-node-children n)) (acc '()))
      (if (null? cs)
          (reverse acc)
          (let ((s (node->sxml (car cs) raw-html tight?)))
            (loop (cdr cs)
                  (if (and (pair? s) (eq? 'splice (car s)))
                      (append (reverse (cdr s)) acc)
                      (cons s acc)))))))
```

Finally, `markdown-ast->sxml` calls `node->sxml` with `tight?` `#f`:

```scheme
       (node->sxml ast (sxml-options-raw-html o) #f)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
make check-purity
```

Expected: PASS, `# of expected passes 23`.

- [ ] **Step 5: Extend the differential**

```scheme
(agrees "tight lists agree"   "- a\n- b\n- c\n")
(agrees "loose lists agree"   "- a\n\n- b\n\n- c\n")
(agrees "ordered lists agree" "1. a\n2. b\n\n3) c\n4) d\n")
(agrees "ol start agrees"     "5. a\n6. b\n")
(agrees "nested lists agree"  "- a\n  - b\n\n    c\n- d\n")
(agrees "task lists agree"    "- [ ] a\n- [x] b\n- c\n")
(agrees "loose task lists agree" "- [ ] a\n\n- [x] b\n")
```

- [ ] **Step 6: Run the differential**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: PASS, `# of expected passes 22`.

- [ ] **Step 7: Mutation — watch it fail**

1. Make `tight?` propagate from the list to *all* descendants rather than
   stopping at a nested list (pass the outer `tight?` into the nested
   `list` case). Confirm **"tightness does not leak into a nested list"**
   and **"nested lists agree"** both fail.
2. Emit `(checked "")` unconditionally in the item case. Confirm **"task
   items get a disabled checkbox…"** and **"task lists agree"** both fail.
3. Emit `(@ (start "1"))` for every ordered list. Confirm **"ol start is
   emitted only when it is not one"** and **"ordered lists agree"** fail.

Revert each; confirm green. Record all three.

- [ ] **Step 8: Commit**

```bash
git add src/cmark/gfm/sxml.sls tests/test-sxml.sps tests/test-sxml-differential.sps .plans/stage-5-mutation-log.md
git commit -m "feat: map lists, tight-list paragraph elision, and task items"
```

---

### Task 7: Tables

**Files:**
- Modify: `src/cmark/gfm/sxml.sls`
- Test: `tests/test-sxml.sps`, `tests/test-sxml-differential.sps`

**Interfaces:**
- Consumes: `node->sxml` dispatch
- Produces: `table` → `(table (thead (tr …)) (tbody (tr …) …))`, with `thead` and `tbody` present only when they have rows

- [ ] **Step 1: Write the failing pure tests**

Append to `tests/test-sxml.sps`, before `(test-end "sxml")`:

```scheme
;; --- tables -------------------------------------------------------------
(define (cell align . kids)
  (node 'table-cell (list (cons 'alignment align)) kids))

(define (row header? . cells)
  (node 'table-row (list (cons 'header? header?)) cells))

(define (table . rows)
  (node 'table (list (cons 'columns (length (markdown-node-children (car rows))))
                     (cons 'alignments '()))
        rows))

;; extensions/table.c:774-797. A header row opens and closes thead around
;; itself; the first non-header row opens tbody, which stays open to the end
;; of the table. This is the only structural regrouping in the mapping --
;; the AST is flat and HTML is nested.
(test-equal "header rows go in thead, body rows share one tbody"
  '(*TOP* (table (thead (tr (th "h")))
                 (tbody (tr (td "a")) (tr (td "b")))))
  (->sxml (doc (table (row #t (cell 'none (text "h")))
                      (row #f (cell 'none (text "a")))
                      (row #f (cell 'none (text "b")))))))

(test-equal "a table with no body rows emits no tbody"
  '(*TOP* (table (thead (tr (th "h")))))
  (->sxml (doc (table (row #t (cell 'none (text "h")))))))

;; extensions/table.c:806-811 switches on 'l'/'c'/'r' and writes nothing
;; otherwise -- and unlike the XML renderer, it emits align on BODY cells
;; too. That is the one ADR-0010 blind spot this oracle closes.
(test-equal "alignment renders on header and body cells alike, omitted when none"
  '(*TOP* (table (thead (tr (th (@ (align "left")) "h")
                            (th (@ (align "center")) "i")
                            (th "j")))
                 (tbody (tr (td (@ (align "right")) "a")
                            (td "b")
                            (td "c")))))
  (->sxml (doc (table (row #t (cell 'left (text "h"))
                              (cell 'center (text "i"))
                              (cell 'none (text "j")))
                      (row #f (cell 'right (text "a"))
                              (cell 'none (text "b"))
                              (cell 'none (text "c")))))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
```

Expected: FAIL — `&cmark-unsupported-node` for `table`.

- [ ] **Step 3: Implement tables**

Add to `src/cmark/gfm/sxml.sls`, before `node->sxml`:

```scheme
  ;; --- tables ------------------------------------------------------------
  ;; A fold over the row list, not a per-node rewrite: the AST is flat
  ;; (table -> row(header?) -> cell) and HTML is nested. extensions/table.c
  ;; :774-797 -- a header row opens and closes <thead> around itself; the
  ;; first non-header row opens <tbody>, which stays open until the table
  ;; ends. Either section is absent when it has no rows.
  (define (table->sxml n raw-html)
    (let loop ((rows (markdown-node-children n)) (head '()) (body '()))
      (cond
        ((null? rows)
         (cons 'table
               (append
                (if (null? head) '() (list (cons 'thead (reverse head))))
                (if (null? body) '() (list (cons 'tbody (reverse body)))))))
        (else
         (let* ((r (car rows))
                (header? (markdown-node-property r 'header?))
                (tr (cons 'tr (map (lambda (c) (cell->sxml c header? raw-html))
                                   (markdown-node-children r)))))
           (if header?
               (loop (cdr rows) (cons tr head) body)
               (loop (cdr rows) head (cons tr body))))))))

  (define (cell->sxml c header? raw-html)
    (let ((tag   (if header? 'th 'td))
          (align (markdown-node-property c 'alignment))
          ;; A cell holds inlines only, so tightness cannot reach here.
          (kids  (children->sxml c raw-html #f)))
      (if (memq align '(left center right))
          (cons tag (cons (list '@ (list 'align (symbol->string align)))
                          kids))
          (cons tag kids))))
```

and add to `node->sxml`, before the `(extension)` case:

```scheme
      ((table) (table->sxml n raw-html))
```

`table-row` and `table-cell` deliberately get **no** top-level case:
`table->sxml` consumes them, and a row reached any other way is a
malformed tree that should raise rather than render.

- [ ] **Step 4: Run tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml.sps
make check-purity
```

Expected: PASS, `# of expected passes 26`.

- [ ] **Step 5: Extend the differential**

```scheme
(agrees "tables agree"
        "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n")
(agrees "table alignment agrees"
        "| l | c | r | n |\n|:--|:-:|--:|---|\n| 1 | 2 | 3 | 4 |\n")
(agrees "header-only tables agree" "| a | b |\n| --- | --- |\n")
(agrees "tables with inline content agree"
        "| *a* | `b` |\n| --- | --- |\n| [c](/x) | ~~d~~ |\n")
(agrees "tables adjacent to blocks agree"
        "para\n\n| a |\n| --- |\n| 1 |\n\npara\n")
```

- [ ] **Step 6: Run the differential**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: PASS, `# of expected passes 27`.

- [ ] **Step 7: Mutation — watch it fail**

1. Open a new `tbody` per body row (emit one `(tbody (tr …))` per row).
   Confirm **"header rows go in thead, body rows share one tbody"** and
   **"tables agree"** both fail.
2. Emit `align` only when `header?` is true — the XML renderer's behaviour.
   Confirm **"alignment renders on header and body cells alike…"** and
   **"table alignment agrees"** both fail. This is the assertion that proves
   the ADR-0010 blind spot is actually closed.
3. Emit an empty `(tbody)` when there are no body rows. Confirm **"a table
   with no body rows emits no tbody"** and **"header-only tables agree"**
   fail.

Revert each; confirm green. Record all three.

- [ ] **Step 8: Commit**

```bash
git add src/cmark/gfm/sxml.sls tests/test-sxml.sps tests/test-sxml-differential.sps .plans/stage-5-mutation-log.md
git commit -m "feat: map tables, regrouping flat rows into thead and tbody"
```

---

### Task 8: `markdown->sxml`

**Files:**
- Modify: `src/cmark/gfm.sls`
- Test: `tests/test-options.sps`, `tests/test-sxml-differential.sps`

**Interfaces:**
- Consumes: `markdown->ast` (existing), `markdown-ast->sxml` (Task 4)
- Produces: `(markdown->sxml md)`, `(markdown->sxml md cmark-opts)`, `(markdown->sxml md cmark-opts sxml-opts)`

- [ ] **Step 1: Write the failing test**

Append to `tests/test-options.sps`, before its final `(exit …)`:

```scheme
;; --- markdown->sxml rejects unsafe-html? --------------------------------
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
```

Note: this suite imports `(cmark gfm)`, which loads native code, so it is
**not** in the purity gate. `tests/test-sxml.sps` is the pure one.

- [ ] **Step 2: Run test to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
```

Expected: FAIL at import — `unbound variable markdown->sxml`.

- [ ] **Step 3: Implement it**

In `src/cmark/gfm.sls`, add `(cmark gfm sxml)` to the imports, add
`markdown->sxml` to the exports next to `markdown->ast`, and add to the body:

```scheme
  ;; Lives here rather than in sxml.sls because it parses: putting it there
  ;; would pull (cmark gfm private native) into that library's import chain
  ;; and forfeit `make check-purity`.
  ;;
  ;; Defaults to default-cmark-options, NOT default-ast-options: positions
  ;; never reach SXML (ADR-0011), so turning CMARK_OPT_SOURCEPOS on would
  ;; cost a flag in the parse for information the output discards. That is
  ;; ADR-0009's per-entry-point principle pointing the other way from
  ;; markdown->ast.
  (define markdown->sxml
    (case-lambda
      ((md) (markdown->sxml md (default-cmark-options) (default-sxml-options)))
      ((md o) (markdown->sxml md o (default-sxml-options)))
      ((md o so)
       (unless (cmark-options? o)
         (raise (make-cmark-invalid-option #f 'invalid-value)))
       ;; Checked before anything native is acquired, so a rejected call
       ;; leaves no resource to clean up.
       (when (cmark-options-unsafe-html? o)
         (raise (make-cmark-invalid-option 'unsafe-html? 'not-applicable)))
       (markdown-ast->sxml (markdown->ast md o) so))))
```

`make-cmark-invalid-option` is already reachable — `(cmark gfm private
conditions)` is in this library's imports.

- [ ] **Step 4: Run tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-options.sps
make check-purity
```

Expected: PASS, `# of expected passes 58`; purity still holds for all three
pure suites.

- [ ] **Step 5: Assert positions have no effect**

In `tests/test-sxml-differential.sps`, add before `(test-end …)`:

```scheme
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
```

- [ ] **Step 6: Run the differential**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: PASS, `# of expected passes 29`.

- [ ] **Step 7: Mutation — watch it fail**

Change the `unsafe-html?` guard to test key presence rather than value (raise
whenever the caller passed the key at all). Confirm **"markdown->sxml accepts
an explicit unsafe-html? #f"** fails while **"markdown->sxml rejects
unsafe-html?"** stays green. Revert; confirm green. Record it.

- [ ] **Step 8: Commit**

```bash
git add src/cmark/gfm.sls tests/test-options.sps tests/test-sxml-differential.sps .plans/stage-5-mutation-log.md
git commit -m "feat: add markdown->sxml, rejecting unsafe-html? as not applicable"
```

---

### Task 9: The corpus parser

**Files:**
- Create: `tests/spec-corpus.sls`
- Test: `tests/test-sxml-differential.sps`

**Interfaces:**
- Consumes: nothing
- Produces: `(spec-examples path)` → list of strings, the Markdown side of each example

Five details, all read from `vendor/cmark-gfm/test/spec_tests.py:89-120`, and
each of which silently corrupts the corpus if missed.

- [ ] **Step 1: Write the failing test**

Add to `tests/test-sxml-differential.sps` — imports first:

```scheme
        (spec-corpus)
        (only (chezscheme) getenv)
```

then before `(test-end …)`:

```scheme
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: FAIL at import — library `(spec-corpus)` not found.

- [ ] **Step 3: Implement the parser**

Create `tests/spec-corpus.sls`:

```scheme
#!r6rs
;;; Parses cmark's own spec files into their Markdown examples. TEST ONLY.
;;;
;;; Transcribed from vendor/cmark-gfm/test/spec_tests.py:89-120. Five
;;; details, each of which corrupts the corpus silently if missed:
;;;
;;;   1. The opening fence is EXACTLY 32 backticks followed by " example".
;;;      A looser pattern matches fenced code blocks inside the prose.
;;;   2. The closing fence is a line that strips to exactly 32 backticks.
;;;   3. The separator is a line that strips to exactly ".".
;;;   4. Lines are compared STRIPPED but accumulated RAW, newline included.
;;;   5. U+2192 (RIGHT ARROW) stands for a tab and must be replaced. Miss
;;;      this and the tab examples still pass the differential, because both
;;;      sides receive the same wrong input.
;;;
;;; The per-example extension labels after " example" are deliberately
;;; ignored, and `disabled` examples are deliberately KEPT. Both matter only
;;; to a harness comparing against the file's expected HTML; ours compares
;;; against the pinned library, so every example is a usable input.
(library (spec-corpus)
  (export spec-examples)
  (import (rnrs))

  (define fence (make-string 32 #\`))
  (define open-prefix (string-append fence " example"))

  (define (strip s)
    (let* ((n (string-length s))
           (start (let loop ((i 0))
                    (if (and (< i n) (char-whitespace? (string-ref s i)))
                        (loop (+ i 1)) i)))
           (end (let loop ((i n))
                  (if (and (> i start) (char-whitespace? (string-ref s (- i 1))))
                      (loop (- i 1)) i))))
      (substring s start end)))

  (define (prefix? p s)
    (and (>= (string-length s) (string-length p))
         (string=? p (substring s 0 (string-length p)))))

  (define (arrows->tabs s)
    (string-map (lambda (c) (if (char=? c #\x2192) #\tab c)) s))

  (define (read-lines path)
    (let ((p (open-file-input-port path (file-options)
                                   (buffer-mode block)
                                   (make-transcoder (utf-8-codec) (eol-style none)))))
      (let loop ((acc '()))
        (let ((l (get-line p)))
          (if (eof-object? l)
              (begin (close-port p) (reverse acc))
              (loop (cons (string-append l "\n") acc)))))))

  (define (spec-examples path)
    (let loop ((lines (read-lines path)) (state 'text) (cur '()) (out '()))
      (cond
        ((null? lines) (reverse out))
        (else
         (let* ((raw (car lines))
                (l   (strip raw))
                (rest (cdr lines)))
           (cond
             ((prefix? open-prefix l) (loop rest 'markdown '() out))
             ((string=? fence l)
              (loop rest 'text '()
                    (if (eq? state 'text)
                        out
                        (cons (arrows->tabs (apply string-append (reverse cur)))
                              out))))
             ((and (string=? "." l) (eq? state 'markdown))
              ;; The HTML side is read and discarded: our oracle is the
              ;; pinned library, not the file. Switching state rather than
              ;; skipping keeps the state machine identical to
              ;; spec_tests.py's, which is what makes the counts match.
              (loop rest 'html cur out))
             ((eq? state 'markdown) (loop rest state (cons raw cur) out))
             (else (loop rest state cur out)))))))))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-differential.sps
```

Expected: PASS, `# of expected passes 31`. If the counts are `(0 0 0 0)`, the
suite is being run from somewhere other than the repo root — `corpus-dir` is
relative.

- [ ] **Step 5: Mutation — watch it fail**

1. Change `fence` to 31 backticks. Confirm **"the corpus parser finds every
   example"** fails with counts other than `(672 30 16 26)`.
2. Delete the `arrows->tabs` call. Confirm **"tab arrows are translated to
   tabs"** fails. Note that no *differential* assertion fails — that is
   exactly why this assertion exists.

Revert each; confirm green. Record both.

- [ ] **Step 6: Commit**

```bash
git add tests/spec-corpus.sls tests/test-sxml-differential.sps .plans/stage-5-mutation-log.md
git commit -m "test: parse cmark's 744-example spec corpus"
```

---

### Task 10: The full corpus differential

**Files:**
- Modify: `tests/test-sxml-differential.sps`

**Interfaces:**
- Consumes: `spec-examples` (Task 9), `sxml->html` (Task 3), `markdown->sxml` (Task 8)
- Produces: nothing consumed downstream

- [ ] **Step 1: Write the corpus sweep and the CLI leg**

Add to `tests/test-sxml-differential.sps`, before `(test-end …)`:

```scheme
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
;; failing input and both renderings, which is what a debugger needs.
(define (sweep examples o)
  (let loop ((es examples) (i 0))
    (cond
      ((null? es) 'agree)
      ((divergence (car es) o) => (lambda (d) (cons i (cons (car es) d))))
      (else (loop (cdr es) (+ i 1))))))

(test-equal "every corpus example agrees in-process"
  'agree (sweep all-examples opts))

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

(test-equal "every fixture agrees under every option configuration"
  'agree
  (let loop ((os option-matrix))
    (if (null? os)
        'agree
        (let ((r (sweep fixtures (car os))))
          (if (eq? 'agree r) (loop (cdr os)) r)))))

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

(define (cli-flags o)
  (apply string-append
         "--to html "
         (map (lambda (x) (string-append "-e " (symbol->string x) " "))
              (cmark-options-extensions o))))

(define (write-file path s)
  (let ((p (open-file-output-port path (file-options no-fail)
                                  (buffer-mode block)
                                  (make-transcoder (utf-8-codec)))))
    (put-string p s)
    (close-port p)))

(define (cli-html md o)
  (write-file in-path md)
  (utf8->string
   (capture-command (string-append cli " " (cli-flags o) " " in-path)
                    out-path)))

(define (cli-divergence md o)
  (let ((a (ours md o)) (b (cli-html md o)))
    (if (string=? a b) #f (list 'ours a 'cli b))))

(test-equal "the CLI comparator can detect a difference"
  #t
  (not (string=? (ours "# hi\n" opts) (cli-html "*hi*\n" opts))))

(test-equal "every fixture agrees against the pinned CLI"
  'agree
  (let loop ((fs fixtures))
    (cond ((null? fs) 'agree)
          ((cli-divergence (car fs) opts) => (lambda (d) d))
          (else (loop (cdr fs))))))
```

Add `(cmark-testing)` to the suite's imports for `capture-command`, and
`mkdir` from `(chezscheme)` with a `tests/tmp/` guard mirroring
`tests/test-ast-differential.sps`.

- [ ] **Step 2: Run and expect real divergences**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs CMARK_CLI="$(make -s deps-info | sed -n 's/^cmark-gfm CLI *: //p')" chez --program tests/test-sxml-differential.sps
```

Expected on the first run: **FAIL**, on one or more corpus examples. This is
the point of the task. For each failure, read the reported `ours` and
`theirs`, find the governing lines in `vendor/cmark-gfm/src/html.c` or
`vendor/cmark-gfm/extensions/`, and fix `src/cmark/gfm/sxml.sls` or
`tests/sxml-html-serializer.sls` to match cmark.

**Do not adjust the assertion.** The expectation is produced by cmark; if it
disagrees, we are wrong. Likely areas, in order of probability: entity and
backslash handling in text literals, `<pre>` content with no trailing
newline, nested block containers meeting at a boundary, and autolinks with
non-ASCII.

- [ ] **Step 3: Iterate until green**

Repeat Step 2 until all assertions pass. Commit each fix separately with a
message naming the cmark behaviour it matched, e.g.
`fix: match html.c:236 escaping of the fence info token`.

- [ ] **Step 4: Run the whole suite**

```bash
make test
make check-purity
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Mutation — watch it fail**

1. Make `divergence` always return `#f`. Confirm **"the comparator can detect
   a difference"** fails. This is the guard that stops every other assertion
   in the suite from being vacuous.
2. Make `cli-divergence` always return `#f`. Confirm **"the CLI comparator
   can detect a difference"** fails.
3. Drop `-e table` from `cli-flags`. Confirm **"every fixture agrees against
   the pinned CLI"** fails — proving the CLI leg actually exercises the
   extension list rather than accepting whatever the CLI defaults to.

Revert each; confirm green. Record all three.

- [ ] **Step 6: Commit**

```bash
git add tests/test-sxml-differential.sps .plans/stage-5-mutation-log.md
git commit -m "test: run the full 744-example corpus differential, both legs"
```

---

### Task 11: `wak-sxml-tools` and the portability suite

**Files:**
- Modify: `Akku.manifest`, `Makefile`, `.gitmodules`
- Create: `vendor/wak-sxml-tools` (submodule), `tests/test-sxml-portability.sps`

**Interfaces:**
- Consumes: `markdown->sxml` (Task 8)
- Produces: nothing consumed downstream

- [ ] **Step 1: Add the submodule**

```bash
git submodule add https://gitlab.com/wak/wak-sxml-tools.git vendor/wak-sxml-tools
```

Then record the same commit in `Akku.manifest` under `depends/dev`, and move
`chez-srfi` there too — neither is imported by `(cmark gfm)`:

```scheme
(akku-package ("chez-cmark-gfm" "0.3.0")
  (synopsis "CommonMark and GitHub Flavored Markdown for Chez Scheme")
  (authors "Kiyomi Computation Systems LLC")
  (license "BSD-3-Clause")
  (depends/dev ("chez-srfi" "^0.0.0-akku.181.7879b52")
               ("wak-sxml-tools" "^0.0.0-akku.1.5c14730")))
```

Run `akku lock` if it works on this host; otherwise hand-edit `Akku.lock` to
match, since `make check-pins` compares the two.

- [ ] **Step 2: Link it into the build tree**

In `Makefile`, next to `SRFI_SRC`:

```make
SXMLT_SRC    := vendor/wak-sxml-tools
```

and in the `deps` target, after the chez-srfi block:

```make
	git submodule update --init $(SXMLT_SRC)
	mkdir -p $(SRFI_LIBS)/wak
	ln -sfn $(abspath $(SXMLT_SRC))/wak/sxml-tools $(abspath $(SRFI_LIBS))/wak/sxml-tools
```

Verify the upstream layout first — if the libraries do not sit under
`wak/sxml-tools/`, adjust the link target to whatever directory holds
`serializer.sls`:

```bash
find vendor/wak-sxml-tools -name 'serializer*'
```

- [ ] **Step 3: Extend `check-pins`**

`check-pins` currently reads one submodule and one `Akku.lock` line. Generalise
its body to loop over both pairs:

```make
check-pins:
	@fail=0; \
	for pair in "$(SRFI_SRC):chez-srfi" "$(SXMLT_SRC):wak-sxml-tools"; do \
	  src=$${pair%%:*}; name=$${pair##*:}; \
	  rec=$$(git ls-files -s $$src | awk '{print $$2}'); \
	  lock=$$(sed -n "/$$name/,/^$$/s/.*akku\.[0-9]*\.\([a-f0-9]*\)_repack.*/\1/p" Akku.lock | head -1); \
	  if [ -z "$$rec" ] || [ -z "$$lock" ]; then \
	    echo "check-pins: could not read both pins for $$name (submodule='$$rec' lock='$$lock')" >&2; \
	    fail=1; continue; \
	  fi; \
	  case "$$rec" in \
	    "$$lock"*) echo "pins agree: $$name $$lock" ;; \
	    *) echo "PIN DRIFT: $$name submodule $$rec but Akku.lock names $$lock." >&2; \
	       fail=1 ;; \
	  esac; \
	done; \
	exit $$fail
```

Run:

```bash
make check-pins
```

Expected: two "pins agree" lines.

- [ ] **Step 4: Write the portability suite**

Create `tests/test-sxml-portability.sps`:

```scheme
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
```

- [ ] **Step 5: Run it**

```bash
make deps
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-sxml-portability.sps
```

Expected: PASS, `# of expected passes 5`. If `srl:sxml->html` is not the
exported name, run `grep -rn 'srl:sxml->' vendor/wak-sxml-tools/` and use the
actual one — do not weaken an assertion to accommodate a missing binding.

- [ ] **Step 6: Mutation — watch it fail**

Make the adapter escape text literals itself (apply an HTML escape in the
`text` case). Confirm **"a script tag in a text node comes out escaped"**
fails, reporting `&amp;lt;script&amp;gt;` — double-escaped. This is the
assertion proving literals are carried verbatim and escaping belongs to the
serializer. Revert; confirm green. Record it.

- [ ] **Step 7: Commit**

```bash
git add .gitmodules vendor/wak-sxml-tools Akku.manifest Akku.lock Makefile tests/test-sxml-portability.sps .plans/stage-5-mutation-log.md
git commit -m "test: verify SXML conformance and escaping through wak-sxml-tools"
```

---

### Task 12: Documentation and release

**Files:**
- Modify: `README.org`, `CHANGELOG.md`, `AGENTS.md`
- Verify: `.plans/stage-5-mutation-log.md`

- [ ] **Step 1: Add the README section**

In `README.org`, after the AST section, add an SXML section covering: the two
entry points with a worked example; the mapping table from design spec §4.1;
the `raw-html` policies with `omit` as the default and *why* (under `omit`
there is nothing to escape, so the output is safe whatever serializer the
caller chose); that `unsafe-html?` is rejected; that positions and the §4.3
properties live in `markdown->ast`; and the delta table:

| | cmark | Typical serializer |
|---|---|---|
| Between blocks | `\n` | nothing |
| `"` in text | `&quot;` | `"` |
| `'` in an `href` | `&#x27;` | `'` |
| Childless elements | `<hr />` | `<hr>` or `<hr></hr>` |

with the sentence that byte-equality is a property of the differential, not a
promise about the caller's pipeline, and a warning that a pretty-printing
serializer will corrupt `<pre>` content.

- [ ] **Step 2: Add the CHANGELOG entry**

Add a `## [0.3.0] — 2026-08-17` section to `CHANGELOG.md` with **Added**,
**Security**, and **Notes**, following the 0.2.0 entry's shape. Security must
state that `omit` is the default because it is the policy that does not
depend on the caller's serializer, and that the URL rule is cmark's own from
`src/scanners.re:345-354` including the `data:image` carve-out.

- [ ] **Step 3: Record Stage 5's traps in AGENTS.md**

Add to the "Traps this repo has already hit" list any trap discovered during
Tasks 4–10 that is not already there. Candidates to check against what
actually happened: the percent-encode/entity-escape split double-encoding;
`cmark_html_render_cr` collapsing rather than appending; the corpus parser's
32-backtick fence and U+2192 tab arrows, where a wrong parser leaves the
differential green because both sides get the same wrong input.

Only record traps that actually bit. A speculative entry dilutes the list.

- [ ] **Step 4: Verify the mutation log is complete**

Every assertion added in Tasks 1–11 must appear in
`.plans/stage-5-mutation-log.md` with the mutation that broke it and the name
it failed under. Cross-check against design spec §8.3's table. Any assertion
with no mutation is either rewritten or recorded there as uncovered, with the
reason — leaving it silent is the exact failure the rule exists to prevent.

- [ ] **Step 5: Full verification**

```bash
make test && make check-purity && make check-pins && make test-memory
```

Expected: all green. `make test-memory` is not a formality — `markdown->sxml`
parses, and that path must stay clean.

- [ ] **Step 6: Commit and open the PR**

```bash
git add README.org CHANGELOG.md AGENTS.md .plans/stage-5-mutation-log.md
git commit -m "docs: document the SXML adapter and release 0.3"
git push -u origin feat/stage-5-sxml
gh pr create --title "Stage 5: the SXML adapter (release 0.3)" --body "..."
```

---

## Self-Review

**Spec coverage.** Design spec §2 → Tasks 1–4, 8, 11. §3 → Tasks 1, 2, 8.
§4.1 → Tasks 4–7. §4.2.1 → Task 6. §4.2.2 → Task 7. §4.2.3 → Task 5.
§4.3 → documented in Task 12. §5.1 → Task 4. §5.2 → Task 5. §5.3 → Tasks 3
and 5, split across the serializer and the adapter as the spec requires.
§5.4 → Task 8 Step 5. §6.1–6.5 → Tasks 3, 9, 10. §6.6 → Task 11. §7 →
Task 11. §8.1 → Tasks 4–11. §8.2 → Task 12 Step 5. §8.3 → the mutation steps
throughout, verified in Task 12 Step 4. §9 → Tasks 4 (`check-purity`), 11
(`check-pins`), 8 and 9 (the no-effect and example-count assertions). §10 →
`'escape` carries direct assertions in Tasks 4 and 11 with no differential
coverage, as the spec records. §11 → Task 12 Step 1. §12 → Task 12.

**Two spec corrections this plan makes.** The design spec §2.1 says the
adapter imports "only `(rnrs)` and `(cmark gfm ast)`"; it also needs
`(cmark gfm options)` and `(cmark gfm private conditions)`, both of which are
pure — `(import (rnrs))` and nothing else — so the purity gate is unaffected.
And §4.1's task-item row shows only the checked form; an unchecked item has
**no** `checked` attribute at all (`extensions/tasklist.c:127`).

**Type consistency.** `markdown-ast->sxml` is arity 1–2 throughout;
`markdown->sxml` is 1–3. `sxml-options-raw-html` returns a symbol in
`{omit, escape}` in Tasks 2, 4, and 11. `sxml->html` takes one argument and
returns a string in Tasks 3, 4, 10. `spec-examples` takes a path and returns
a list of strings in Tasks 9 and 10. `node->sxml` gains its third parameter
in Task 6 and every earlier call site is updated in the same step.

**Known risk.** Task 10 is the only task expected to fail on first run, and
it is the one where the plan cannot predict the fixes — the corpus will
surface divergences that hand-written fixtures did not. That is the task
doing the real work, and Step 3 is deliberately an iterate-until-green loop
rather than a fixed list of edits.
