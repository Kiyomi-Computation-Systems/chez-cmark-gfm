# Docs Site Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render `site/index.md` + `docs/*.md` into a Flexoki-themed,
sidebar-and-TOC static site through the library's own `markdown->sxml` →
transform → serialize pipeline, and deploy it to GitHub Pages on a
release-tag push.

**Architecture:** A functional core of pure Chez libraries under `site/`
(slugging, an SXML→HTML serializer, the heading/callout transform, the link
rewriter, the page template) driven by a thin imperative shell
(`build-site.sps`). `render-site` runs in **two passes** — parse+slug every
page to build a global id-registry, then rewrite+template each page against
it — and returns a value `check-site` asserts on without touching disk.

**Tech Stack:** Chez Scheme (R6RS libraries `.sls`, programs `.sps`),
SRFI-64 for tests, `(cmark gfm)` / `(cmark gfm sxml)`, GNU Make, GitHub
Actions.

**Design spec:** `.plans/2026-08-22-docs-site-design.md`

## Global Constraints

- **`docs/` and `.plans/` content are inputs, never rewritten.** The
  generator reads `docs/*.md`; it does not modify them. New code lives under
  `site/`, `tests/`, `.github/workflows/`, and two `.plans/` files.
- **Nothing compiles.** `make site` runs Chez over `.sls`/`.sps`; it adds no
  build step and no generated `config.sls` (ADR-0015).
- **The functional core is pure.** `site/slug.sls`, `serializer.sls`,
  `transform.sls`, `links.sls`, `template.sls` import no library that loads
  a shared object. Only `site/render.sls` (via `(cmark gfm)`) and the shell
  touch native code or the filesystem.
- **SXML uses the caret attribute marker**, not `@`: `(^ (id "x"))`,
  `(a (^ (href "/x")) "l")`. This is the library default (ADR-0013), and the
  serializer and every transform must assume it.
- **`markdown->sxml` output** is `(*TOP* node …)`; headings are
  `(hN "text" …)`, links `(a (^ (href …) …) …)`, code `(code "…")`, fenced
  code `(pre (code "…"))`. Verified in `tests/test-sxml.sps`.
- **Slugs must match GitHub's**, because the docs already contain
  hand-written anchors: `resource-limits`, `what-make-build-does`,
  `supported-versions`, `wrap-width`, `rhel-fedora-and-alpine`.
- **Out-of-site links pin to `$SITE_REF`** —
  `https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/blob/$SITE_REF/<path>`.
  Deploy triggers on `v*` tag push; `SITE_REF` is that tag.
- **Every new check gets a mutation.** Break the guarded thing, watch the
  check fail by name, record it in `.plans/docs-site-mutation-log.md`. A
  check nobody has watched fail is assumed broken (AGENTS.md trap 1).
- **`.PHONY` stays on ONE physical line**, and every `.PHONY` target carries
  a `## ` description on its own line, or the other session's `check-help`
  fails.
- **Lib path.** Tests and programs resolve libraries with
  `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs` (this plan adds
  `site` to the Makefile's `CHEZ_LIBDIRS`).
- **Chez floor 9.5.8**; binary `chez` on macOS, `chezscheme` on
  Debian/Ubuntu. `$(CHEZ)` defaults to `chez`.
- **Conventional Commits**, branch `feat/docs-site` (off the
  `docs/publishing-prep` tip — see spec §12). Every commit ends with the
  trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` on its
  own line after a blank line. (Prior branch commits used `Claude Opus 5`;
  match whatever the repo's trailer check enforces if one does.) The task
  templates below omit the trailer; append it anyway.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `site/slug.sls` | `(site slug)` — GitHub-style slugging and heading-text extraction |
| `site/serializer.sls` | `(site serializer)` — pre-safe SXML→HTML |
| `site/transform.sls` | `(site transform)` — inject heading ids, collect TOC, fold ⚠️ callouts |
| `site/links.sls` | `(site links)` — rewrite `(a)/(img)` targets, report danglers |
| `site/template.sls` | `(site template)` — full-page SXML shell (nav, TOC, head) |
| `site/pages.sls` | `(site pages)` — ordered `(file . nav-label)` list |
| `site/render.sls` | `(site render)` — the two-pass `render-site` core |
| `site/io.sls` | `(site io)` — read inputs, write the built tree |
| `site/index.md` | Authored home page |
| `site/style.css` | Flexoki + font roles, ported from the approved preview |
| `build-site.sps` | Generator entry point (the shell) |
| `tests/test-site.sps` | Pure-core unit suite (slug, serializer, transform, links, template) |
| `tests/test-site-render.sps` | `render-site` integration suite (imports `(cmark gfm)`) |
| `tests/site-check.sps` | The `check-site` gate program |
| `.github/workflows/pages.yml` | Build on `v*` tag, deploy to Pages |
| `.plans/docs-site-mutation-log.md` | Mutation evidence |

**Modified:** `Makefile` (`CHEZ_LIBDIRS`, `site`, `check-site`, `.PHONY`),
`CHANGELOG.md`.

**Not modified:** `.gitignore` — `build/` is already ignored
(`.gitignore:80`), so `build/site/` is covered.

## Interfaces (the whole surface, so tasks read out of order)

```
(site slug)       (slugify str) -> string
                  (heading-text sxml-heading) -> string   ; concat text kids
                  (make-slugger) -> (lambda (str) string) ; dedups -1,-2,…

(site serializer) (sxml->html sxml-node) -> string        ; pre-safe

(site transform)  (transform-body top) -> (values body toc)
                  ; body: (*TOP* …) with (^ (id slug)) on headings and
                  ;   ⚠️-blockquotes rewrapped as (div (^ (class "callout warning")) …)
                  ; toc: list of (level text slug)

(site links)      (rewrite-links body registry page-name ref)
                    -> (values body danglers)
                  ; registry: list of (page-name . (slug …))
                  ; danglers: list of (page-name . target-string)

(site template)   (page->document #:nav pages #:current name
                                   #:title str #:body body #:toc toc) -> (*TOP* (html …))
                  ; positional in Chez: (page->document pages name title body toc)

(site pages)      pages -> (("index.md" . "Home") ("installing.md" . "Installing") …)

(site render)     (render-site inputs ref) -> site-result
                  ; inputs: list of (name . markdown-string), nav order
                  ; site-result fields: pages registry leaked
                  ;   pages:    list of (name . document-sxml)
                  ;   registry: list of (name . (slug …))
                  ;   leaked:   list of (name . target-string)
                  (site-result-pages r) (site-result-registry r) (site-result-leaked r)

(site io)         (read-site-inputs) -> list of (name . markdown-string)
                  (write-site site-result out-dir) -> unit   ; serializes + writes
```

---

### Task 1: Slugging, and the pure test suite

**Files:**
- Create: `site/slug.sls`, `tests/test-site.sps`
- Modify: `Makefile:30` (`CHEZ_LIBDIRS`)

**Interfaces:**
- Consumes: nothing
- Produces: `(site slug)` exporting `slugify`, `heading-text`,
  `make-slugger`

- [ ] **Step 1: Put `site` on the library path**

`Makefile:30`, change:

```make
CHEZ_LIBDIRS := src:tests:$(SRFI_LIBS)
```

to:

```make
CHEZ_LIBDIRS := src:tests:site:$(SRFI_LIBS)
```

- [ ] **Step 2: Write the failing suite**

Create `tests/test-site.sps`. The authored anchors are the oracle — if
`slugify` does not reproduce them, cross-page links dangle (Task 8 proves
this).

```scheme
#!r6rs
;; PURE SUITE. Imports no library that loads a shared object.
(import (rnrs) (srfi :64) (site slug))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site")

;; --- slugify: matches the anchors docs/ already hand-wrote ---------------
(test-equal "spaces to single hyphen, lowercased"
  "resource-limits" (slugify "Resource limits"))
(test-equal "commas dropped, 'and' kept"
  "rhel-fedora-and-alpine" (slugify "RHEL, Fedora, and Alpine"))
(test-equal "backtick code in a heading is stripped to its text"
  "what-make-build-does" (heading-text '(h2 "What " (code "make build") " does")))
(test-equal "the whole heading-to-slug path"
  "what-make-build-does"
  (slugify (heading-text '(h2 "What " (code "make build") " does"))))
(test-equal "runs of spaces and punctuation collapse"
  "wrap-width" (slugify "Wrap  width"))
(test-equal "leading and trailing punctuation trimmed"
  "supported-versions" (slugify "  Supported versions.  "))

;; --- make-slugger: dedups within a page ---------------------------------
(test-equal "duplicate headings get -1, -2 suffixes"
  '("options" "options-1" "options-2")
  (let ((s (make-slugger))) (list (s "Options") (s "Options") (s "Options"))))

(test-end "site")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 3: Run it, watch it fail**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`

Expected: FAIL — `(site slug)` does not exist yet.

- [ ] **Step 4: Implement `site/slug.sls`**

```scheme
#!r6rs
(library (site slug)
  (export slugify heading-text make-slugger)
  (import (rnrs))

  ;; GitHub's heading-anchor algorithm, ASCII subset: lowercase; keep only
  ;; alphanumerics, spaces, and hyphens; collapse space runs to one hyphen;
  ;; trim leading/trailing hyphens.
  (define (slugify str)
    (let* ((lowered (string-downcase str))
           (kept (list->string
                   (filter (lambda (c)
                             (or (char-alphabetic? c) (char-numeric? c)
                                 (char=? c #\space) (char=? c #\-)))
                           (string->list lowered)))))
      (trim-hyphens (spaces->hyphen kept))))

  (define (spaces->hyphen s)
    ;; each maximal run of spaces (or existing hyphens) becomes one hyphen
    (let loop ((cs (string->list s)) (out '()) (in-gap #f))
      (cond
        ((null? cs) (list->string (reverse out)))
        ((or (char=? (car cs) #\space) (char=? (car cs) #\-))
         (loop (cdr cs) (if in-gap out (cons #\- out)) #t))
        (else (loop (cdr cs) (cons (car cs) out) #f)))))

  (define (trim-hyphens s)
    (let* ((n (string-length s))
           (a (let lo ((i 0)) (if (and (< i n) (char=? (string-ref s i) #\-)) (lo (+ i 1)) i)))
           (b (let hi ((j n)) (if (and (> j a) (char=? (string-ref s (- j 1)) #\-)) (hi (- j 1)) j))))
      (substring s a b)))

  ;; Concatenate a heading's text descendants, ignoring the (^ …) attr node
  ;; and inline element tags (code, em, strong, a). SXML strings are text.
  (define (heading-text node)
    (call-with-string-output-port
      (lambda (p)
        (let walk ((n node))
          (cond
            ((string? n) (put-string p n))
            ((pair? n)
             (cond
               ((and (pair? (car n)) (eq? (caar n) '^)) #f) ; skip attrs
               ((symbol? (car n)) (for-each walk (cdr n)))  ; element: skip tag
               (else (for-each walk n))))
            (else #f))))))

  ;; A per-page slug factory that disambiguates collisions GitHub-style.
  (define (make-slugger)
    (let ((seen '()))
      (lambda (str)
        (let* ((base (slugify str))
               (n (cond ((assoc base seen) => cdr) (else 0))))
          (set! seen (cons (cons base (+ n 1))
                           (filter (lambda (kv) (not (string=? (car kv) base))) seen)))
          (if (zero? n) base (string-append base "-" (number->string n))))))))
```

- [ ] **Step 5: Run it, watch it pass**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: PASS — `# of expected passes  7`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add site/slug.sls tests/test-site.sps Makefile
git commit -m "feat(site): GitHub-style slugging for heading anchors

slugify reproduces the anchors docs/ already hand-wrote (resource-limits,
what-make-build-does, rhel-fedora-and-alpine); make-slugger dedups within a
page. Pure library; site/ added to CHEZ_LIBDIRS."
```

---

### Task 2: The pre-safe SXML→HTML serializer

**Files:**
- Create: `site/serializer.sls`
- Modify: `tests/test-site.sps`
- Reference: `tests/sxml-html-serializer.sls` (the proven test-only serializer to adapt)

**Interfaces:**
- Consumes: nothing
- Produces: `(site serializer)` exporting `sxml->html`

- [ ] **Step 1: Confirm the source serializer's dependencies (spec §6 Task 0)**

Run: `head -30 tests/sxml-html-serializer.sls && rg -n '\(import' tests/sxml-html-serializer.sls`

Expected: note every import. If it imports `(sxml serializer)` /
`wak sxml-tools`, those helpers must be **inlined** into
`site/serializer.sls` so `(site serializer)` imports only `(rnrs)`. Record
the finding in the commit message.

- [ ] **Step 2: Write the failing tests (append to `tests/test-site.sps`)**

Add `(site serializer)` to the import list, and add before `(test-end "site")`:

```scheme
;; --- serializer: escaping, void elements, the caret marker --------------
(test-equal "text is escaped on output, not before"
  "<p>a &amp; &lt;b&gt;</p>" (sxml->html '(p "a & <b>")))
(test-equal "attributes render from the caret marker and are quoted"
  "<a href=\"/x\">l</a>" (sxml->html '(a (^ (href "/x")) "l")))
(test-equal "void elements self-close without a body"
  "<hr>" (sxml->html '(hr)))
(test-equal "*TOP* is a fragment: it emits its children only"
  "<h1>a</h1>\n<p>b</p>\n" (sxml->html '(*TOP* (h1 "a") (p "b"))))

;; --- the load-bearing property: <pre> content is never reflowed ---------
(test-equal "indentation inside pre/code is content, preserved byte-for-byte"
  "<pre><code>(define (f x)\n    (g\n      x))\n</code></pre>"
  (sxml->html '(pre (code "(define (f x)\n    (g\n      x))\n"))))
```

- [ ] **Step 3: Run, watch it fail**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: FAIL — `(site serializer)` undefined.

- [ ] **Step 4: Implement `site/serializer.sls`**

Adapt `tests/sxml-html-serializer.sls`. Requirements the tests pin:

- Emit an element's children with **no injected whitespace**; the tree's
  own text is the only text. This is what keeps `<pre>` intact — do not
  pretty-print, ever.
- The attribute list is the `(^ (name value) …)` node when present as the
  first child; render ` name="value"`.
- HTML-escape text nodes and attribute values (`& < > "` and, in
  attributes, `"`), matching `markdown->html`'s escaping.
- Void elements (`area base br col embed hr img input link meta param
  source track wbr`) emit no closing tag and no body.
- `*TOP*` emits its children in order (a fragment), each block-level child
  followed by `\n` to match `markdown->html`'s output.

```scheme
#!r6rs
(library (site serializer)
  (export sxml->html)
  (import (rnrs))

  (define void-tags
    '(area base br col embed hr img input link meta param source track wbr))

  (define (void? tag) (and (memq tag void-tags) #t))

  (define (escape-text s)
    (escape s '((#\& . "&amp;") (#\< . "&lt;") (#\> . "&gt;"))))
  (define (escape-attr s)
    (escape s '((#\& . "&amp;") (#\< . "&lt;") (#\> . "&gt;") (#\" . "&quot;"))))
  (define (escape s table)
    (call-with-string-output-port
      (lambda (p)
        (string-for-each
          (lambda (c) (cond ((assv c table) => (lambda (kv) (put-string p (cdr kv))))
                            (else (put-char p c)))) s))))

  (define (attrs-node? x) (and (pair? x) (pair? (car x)) (eq? (caar x) '^)))

  (define (render-attrs attr-node p)
    ;; attr-node = (^ (name value) …)
    (for-each
      (lambda (a)
        (put-string p " ") (put-string p (symbol->string (car a)))
        (put-string p "=\"") (put-string p (escape-attr (cadr a))) (put-string p "\""))
      (cdr attr-node)))

  (define (sxml->html node)
    (call-with-string-output-port (lambda (p) (emit node p))))

  (define (emit node p)
    (cond
      ((string? node) (put-string p (escape-text node)))
      ((and (pair? node) (eq? (car node) '*TOP*))
       (for-each (lambda (k) (emit k p) (put-string p "\n")) (cdr node)))
      ((pair? node)
       (let* ((tag (car node))
              (rest (cdr node))
              (attr (and (pair? rest) (attrs-node? rest) (car rest)))
              (kids (if attr (cdr rest) rest)))
         (put-string p "<") (put-string p (symbol->string tag))
         (when attr (render-attrs attr p))
         (put-string p ">")
         (unless (void? tag)
           (for-each (lambda (k) (emit k p)) kids)
           (put-string p "</") (put-string p (symbol->string tag)) (put-string p ">"))))
      (else (error 'sxml->html "unrenderable node" node)))))
```

Verify against `tests/sxml-html-serializer.sls` for any block-level
`\n` placement the corpus expects (that file byte-matches `markdown->html`
across 744 examples); match its behaviour where the fixtures above are
silent.

- [ ] **Step 5: Run, watch it pass; commit**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: PASS.

```bash
git add site/serializer.sls tests/test-site.sps
git commit -m "feat(site): pre-safe SXML->HTML serializer

Adapted from tests/sxml-html-serializer.sls; never injects whitespace, so
<pre> content is preserved byte-for-byte -- the corruption docs/sxml.md
warns about. Self-contained: imports (rnrs) only. [Record §6 dep finding.]"
```

---

### Task 3: The heading/callout transform

**Files:**
- Create: `site/transform.sls`
- Modify: `tests/test-site.sps`

**Interfaces:**
- Consumes: `(site slug)` (`heading-text`, `make-slugger`)
- Produces: `(site transform)` exporting `transform-body`; returns
  `(values body toc)` where `toc` is a list of `(level text slug)`

- [ ] **Step 1: Write the failing tests (append to `tests/test-site.sps`)**

Add `(site transform)` to imports; add before `(test-end "site")`:

```scheme
;; --- transform: inject ids on headings, collect the TOC -----------------
(let-values (((body toc)
              (transform-body '(*TOP* (h2 "Node shape") (p "x") (h2 "Node shape")))))
  (test-equal "headings gain a caret id from their slug"
    '(*TOP* (h2 (^ (id "node-shape")) "Node shape") (p "x")
            (h2 (^ (id "node-shape-1")) "Node shape"))
    body)
  (test-equal "the toc lists (level text slug) in document order"
    '((2 "Node shape" "node-shape") (2 "Node shape" "node-shape-1"))
    toc))

;; --- transform: a ⚠️-led blockquote becomes a warning callout -----------
(let-values (((body toc)
              (transform-body '(*TOP* (blockquote (p "⚠️ The AST is untrusted."))))))
  (test-equal "⚠️ blockquotes are rewrapped as a warning callout div"
    '(*TOP* (div (^ (class "callout warning")) (blockquote (p "⚠️ The AST is untrusted."))))
    body))
```

- [ ] **Step 2: Run, watch it fail**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: FAIL — `(site transform)` undefined.

- [ ] **Step 3: Implement `site/transform.sls`**

```scheme
#!r6rs
(library (site transform)
  (export transform-body)
  (import (rnrs) (site slug))

  (define heading-tags '(h1 h2 h3 h4 h5 h6))
  (define (heading-tag? t) (and (memq t heading-tags) #t))
  (define (level tag) (- (char->integer (string-ref (symbol->string tag) 1))
                         (char->integer #\0)))

  ;; A blockquote whose first rendered text starts with the warning sign.
  (define (warning-blockquote? node)
    (and (pair? node) (eq? (car node) 'blockquote)
         (let ((t (heading-text node)))
           (and (positive? (string-length t))
                (char=? (string-ref t 0) #\x26A0)))) )  ; ⚠ U+26A0

  (define (transform-body top)
    (let ((slug (make-slugger)) (toc '()))
      (define (walk node)
        (cond
          ((string? node) node)
          ((and (pair? node) (heading-tag? (car node)))
           (let* ((text (heading-text node))
                  (s (slug text)))
             (set! toc (cons (list (level (car node)) text s) toc))
             (cons (car node) (cons (list '^ (list 'id s)) (cdr node)))))
          ((warning-blockquote? node)
           (list 'div (list '^ (list 'class "callout warning")) node))
          ((pair? node) (cons (car node) (map walk (cdr node))))
          (else node)))
      (let ((body (walk top)))
        (values body (reverse toc))))))
```

- [ ] **Step 4: Run, watch it pass; commit**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: PASS.

```bash
git add site/transform.sls tests/test-site.sps
git commit -m "feat(site): heading-id + TOC transform, with ⚠️ callouts

One tree walk: injects (^ (id slug)) on every heading, collects the TOC as
(level text slug), and rewraps ⚠️-led blockquotes as warning callouts."
```

---

### Task 4: The link rewriter

**Files:**
- Create: `site/links.sls`
- Modify: `tests/test-site.sps`

**Interfaces:**
- Consumes: nothing (operates on SXML + a registry)
- Produces: `(site links)` exporting `rewrite-links`; returns
  `(values body danglers)`, `danglers` a list of `(page-name . target)`

- [ ] **Step 1: Write the failing tests (append to `tests/test-site.sps`)**

Add `(site links)` to imports. `reg` below is the global id-registry; `ref`
is the release tag. The crux test is the last one: a `javascript:` URL that
lives in a **code block** must be left untouched.

```scheme
;; --- links: the rewrite rules -------------------------------------------
(define reg '(("options.md" . ("resource-limits")) ("ast.md" . ("node-shape"))))
(define (rw body page) (let-values (((b d) (rewrite-links body reg page "v2.0.0"))) b))

(test-equal "doc .md link (with anchor) becomes .html, anchor kept"
  '(*TOP* (p (a (^ (href "options.html#resource-limits")) "x")))
  (rw '(*TOP* (p (a (^ (href "options.md#resource-limits")) "x"))) "ast.md"))
(test-equal "bare doc .md link becomes .html"
  '(*TOP* (p (a (^ (href "ast.html")) "x")))
  (rw '(*TOP* (p (a (^ (href "ast.md")) "x"))) "options.md"))
(test-equal "same-page anchor is left as-is"
  '(*TOP* (p (a (^ (href "#node-shape")) "x")))
  (rw '(*TOP* (p (a (^ (href "#node-shape")) "x"))) "ast.md"))
(test-equal "a ../ escape is pinned to the GitHub blob at the ref"
  '(*TOP* (p (a (^ (href "https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/blob/v2.0.0/examples/01-rendering.sps")) "x")))
  (rw '(*TOP* (p (a (^ (href "../examples/01-rendering.sps")) "x"))) "usage.md"))
(test-equal "an absolute URL is untouched"
  '(*TOP* (p (a (^ (href "https://example.com")) "x")))
  (rw '(*TOP* (p (a (^ (href "https://example.com")) "x"))) "ast.md"))
(test-equal "CRUX: a javascript: URL in a code block is NOT a link, untouched"
  '(*TOP* (pre (code "[x](javascript:alert(1))")))
  (rw '(*TOP* (pre (code "[x](javascript:alert(1))"))) "sxml.md"))

;; --- links: danglers are reported ---------------------------------------
(let-values (((b d) (rewrite-links
                      '(*TOP* (a (^ (href "options.md#nonesuch")) "x")) reg "ast.md" "v2.0.0")))
  (test-equal "an anchor absent from the registry is reported as a dangler"
    '(("ast.md" . "options.md#nonesuch")) d))
```

- [ ] **Step 2: Run, watch it fail**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: FAIL — `(site links)` undefined.

- [ ] **Step 3: Implement `site/links.sls`**

Because it walks the SXML tree and only touches `href`/`src` on `(a)`/`(img)`
nodes, code-block text (a plain string child of `(pre (code …))`) can never
be mistaken for a link — the CRUX test passes structurally.

```scheme
#!r6rs
(library (site links)
  (export rewrite-links)
  (import (rnrs))

  (define repo-blob
    "https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/blob/")

  (define (prefix? pre s)
    (and (>= (string-length s) (string-length pre))
         (string=? pre (substring s 0 (string-length pre)))))
  (define (suffix? suf s)
    (let ((ls (string-length s)) (lf (string-length suf)))
      (and (>= ls lf) (string=? suf (substring s (- ls lf) ls)))))

  (define (split-anchor target)
    ;; -> (values path anchor-or-#f)
    (let loop ((i 0))
      (cond ((= i (string-length target)) (values target #f))
            ((char=? (string-ref target i) #\#)
             (values (substring target 0 i) (substring target i (string-length target))))
            (else (loop (+ i 1))))))

  (define (registry-has? registry page slug)
    (cond ((assoc page registry) => (lambda (kv) (and (member slug (cdr kv)) #t)))
          (else #f)))

  ;; Rewrite one href/src. Returns (values new-target dangling?).
  (define (rewrite-target target page registry ref)
    (cond
      ((prefix? "http://" target) (values target #f))
      ((prefix? "https://" target) (values target #f))
      ((prefix? "#" target)                              ; same-page anchor
       (values target (not (registry-has? page (substring target 1 (string-length target))
                                          registry))))
      ((prefix? "../" target)                            ; escape -> GitHub blob
       (values (string-append repo-blob ref "/" (substring target 3 (string-length target))) #f))
      (else
       (let-values (((path anchor) (split-anchor target)))
         (if (suffix? ".md" path)
             (let* ((base (substring path 0 (- (string-length path) 3)))
                    (target-page (string-append base ".md"))
                    (slug (and anchor (substring anchor 1 (string-length anchor)))))
               (values (string-append base ".html" (or anchor ""))
                       (and slug (not (registry-has? target-page slug registry)))))
             (values target #f))))))          ; unrecognised: leave, don't dangle

  (define (rewrite-links body registry page ref)
    (let ((danglers '()))
      (define (attr-map name attr)
        ;; attr = (name value); rewrite href/src values
        (if (and (memq (car attr) '(href src)) (pair? (cdr attr)) (string? (cadr attr)))
            (let-values (((new dangling?) (rewrite-target (cadr attr) page registry ref)))
              (when dangling? (set! danglers (cons (cons page (cadr attr)) danglers)))
              (list (car attr) new))
            attr))
      (define (walk node)
        (cond
          ((string? node) node)
          ((and (pair? node) (pair? (car node)) (eq? (caar node) '^))
           (cons (cons '^ (map (lambda (a) (attr-map (car a) a)) (cdr (car node))))
                 (map walk (cdr node))))
          ((pair? node) (cons (car node) (map walk (cdr node))))
          (else node)))
      ;; walk, treating a leading (^ …) as attributes of the enclosing element
      (define (walk-node node)
        (if (pair? node)
            (let* ((tag (car node)) (rest (cdr node)))
              (if (and (pair? rest) (pair? (car rest)) (eq? (caar rest) '^))
                  (cons tag (cons (cons '^ (map (lambda (a) (attr-map (car a) a)) (cdr (car rest))))
                                  (map walk-node (cdr rest))))
                  (cons tag (map walk-node rest))))
            node))
      (let ((out (walk-node body)))
        (values out (reverse danglers)))))
```

Note: keep only one walker — delete the unused `walk`/`attr` helper if the
implementer finds it redundant; `walk-node` is the one the tests exercise.

- [ ] **Step 4: Run, watch it pass; commit**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: PASS.

```bash
git add site/links.sls tests/test-site.sps
git commit -m "feat(site): tree-level link rewriter

Rewrites .md->.html (anchors kept), ../ escapes to the GitHub blob at
\$SITE_REF, leaves absolute URLs alone, and reports danglers. Operating on
(a)/(img) nodes means a javascript: URL inside a code block is never
touched -- the correctness argument for the SXML path."
```

---

### Task 5: The page template

**Files:**
- Create: `site/template.sls`, `site/pages.sls`
- Modify: `tests/test-site.sps`

**Interfaces:**
- Consumes: nothing (pure SXML assembly)
- Produces: `(site pages)` exporting `pages`; `(site template)` exporting
  `page->document`

- [ ] **Step 1: Create `site/pages.sls`**

```scheme
#!r6rs
(library (site pages)
  (export pages)
  (import (rnrs))
  ;; The nav's single source of order and labels. Task 8 asserts the file
  ;; set here equals docs/*.md (plus the home).
  (define pages
    '(("index.md"      . "Home")
      ("installing.md" . "Installing")
      ("usage.md"      . "Usage")
      ("options.md"    . "Options")
      ("ast.md"        . "The AST")
      ("sxml.md"       . "SXML")
      ("errors.md"     . "Errors")
      ("memory.md"     . "Memory ownership")
      ("building.md"   . "Building"))))
```

- [ ] **Step 2: Write the failing tests (append to `tests/test-site.sps`)**

Add `(site template)` to imports; add before `(test-end "site")`:

```scheme
;; --- template: the shell places nav, current marker, body, and TOC ------
(define doc-out
  (page->document '(("ast.md" . "The AST") ("sxml.md" . "SXML"))
                  "ast.md" "The AST"
                  '(*TOP* (h2 (^ (id "node-shape")) "Node shape"))
                  '((2 "Node shape" "node-shape"))))

(test-assert "the document is rooted at html"
  (and (pair? doc-out) (eq? (car doc-out) '*TOP*)
       (eq? (car (cadr doc-out)) 'html)))
(test-assert "the stylesheet is linked in head"
  (let ((s (sxml->html doc-out)))
    (and (string-contains-sub? s "<link") (string-contains-sub? s "style.css"))))
(test-assert "the current page is marked in the nav"
  (string-contains-sub? (sxml->html doc-out) "aria-current=\"page\""))
(test-assert "the TOC lists the page's headings"
  (string-contains-sub? (sxml->html doc-out) "#node-shape"))
```

Add this helper near the top of the suite (after the imports):

```scheme
(define (string-contains-sub? hay needle)
  (let ((h (string-length hay)) (n (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))
```

and add `(site serializer)` to the suite imports if not already present.

- [ ] **Step 3: Run, watch it fail; then implement `site/template.sls`**

Run first (expect FAIL: `page->document` undefined). Then:

```scheme
#!r6rs
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
```

- [ ] **Step 4: Run, watch it pass; commit**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`
Expected: PASS.

```bash
git add site/template.sls site/pages.sls tests/test-site.sps
git commit -m "feat(site): page template and nav source

page->document builds the full-page SXML: head with stylesheet, sidebar nav
(current page marked), content column, and the On-this-page TOC. Theme is
prefers-color-scheme plus a persisted, load-pinned toggle. site/pages.sls is
the single source of nav order."
```

---

### Task 6: The two-pass render core

**Files:**
- Create: `site/render.sls`, `tests/test-site-render.sps`

**Interfaces:**
- Consumes: `(cmark gfm)` (`markdown->sxml`, `default-cmark-options`),
  `(site transform)`, `(site links)`, `(site template)`, `(site pages)`
- Produces: `(site render)` exporting `render-site`, `site-result?`,
  `site-result-pages`, `site-result-registry`, `site-result-leaked`

- [ ] **Step 1: Write the failing integration suite `tests/test-site-render.sps`**

This suite imports the native library, so it is NOT pure; it runs under
`make test` like the differential suites.

```scheme
#!r6rs
(import (rnrs) (srfi :64) (site render))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-render")

;; Two tiny pages; page A links to a heading on page B. Two-pass resolution
;; is the point: the anchor is only knowable after B is slugged.
(define inputs
  '(("index.md" . "# Home\n\nSee [node shape](ast.md#node-shape).\n")
    ("ast.md"   . "# The AST\n\n## Node shape\n\ntext\n")))

(define r (render-site inputs "v2.0.0"))

(test-equal "every input yields a page"
  '("index.md" "ast.md") (map car (site-result-pages r)))
(test-equal "the registry carries each page's slugs"
  '("node-shape") (cond ((assoc "ast.md" (site-result-registry r)) => cdr) (else 'missing)))
(test-equal "a resolvable cross-page anchor does not dangle"
  '() (site-result-leaked r))

;; Break the target: the anchor now dangles.
(define r2 (render-site
             '(("index.md" . "[x](ast.md#gone)\n") ("ast.md" . "# The AST\n")) "v2.0.0"))
(test-equal "an unresolvable cross-page anchor is reported"
  '(("index.md" . "ast.md#gone")) (site-result-leaked r2))

(test-end "site-render")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run, watch it fail**

Run: `make build && CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site-render.sps`
Expected: FAIL — `(site render)` undefined.

- [ ] **Step 3: Implement `site/render.sls`**

```scheme
#!r6rs
(library (site render)
  (export render-site site-result? site-result-pages
          site-result-registry site-result-leaked)
  (import (rnrs) (cmark gfm) (site transform) (site links)
          (site template) (site pages))

  (define-record-type site-result
    (fields pages registry leaked))

  (define (label-for name)
    (cond ((assoc name pages) => cdr) (else name)))

  ;; Pass 1: parse + slug every page, building the id-registry.
  ;; Pass 2: rewrite links against the full registry, then template.
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
                                  (page->document pages name (label-for name) body* toc))
                            pages-out)
                      (append (reverse dangling) leaked)))))))))
```

- [ ] **Step 4: Run, watch it pass; commit**

Run: `CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site-render.sps`
Expected: PASS.

```bash
git add site/render.sls tests/test-site-render.sps
git commit -m "feat(site): two-pass render-site core

Pass 1 parses and slugs every page into a global id-registry; pass 2
rewrites links against it and templates each page. Returns {pages, registry,
leaked} -- the value check-site asserts on. Integration-tested with a
cross-page anchor, which only resolves because slugging precedes linking."
```

---

### Task 7: The shell, the assets, and `make site`

**Files:**
- Create: `site/io.sls`, `build-site.sps`, `site/index.md`, `site/style.css`
- Modify: `Makefile` (a `site` target, `.PHONY`)

**Interfaces:**
- Consumes: `(site render)`, `(site serializer)`, `(site pages)`
- Produces: `make site` → `build/site/*.html` + `style.css`

- [ ] **Step 1: Port the stylesheet**

Create `site/style.css` from the approved preview artifact
(`docs-preview.html`'s `<style>`). Translate the mock's `#site …` selectors
to the generated markup's classes (`.topbar`, `.layout`, `.side`, `.main`,
`.col`, `.toc`, `.callout`, `.toggle`), and move the theme tokens onto
`:root` / `:root[data-mode="dark"]` (the template sets `data-mode` on
`<html>`). Keep every Flexoki value and font stack from spec §5 verbatim.

- [ ] **Step 2: Author the home page**

Create `site/index.md`: an `# chez-cmark-gfm` H1, a one-paragraph pitch, a
short "A taste" `scheme` code block (drawn from `examples/01-rendering.sps`
so it stays truthful), and a list linking the eight pages
(`[Installing](installing.md)`, …) — those links are rewritten to `.html`
by the same pipeline.

- [ ] **Step 3: Implement `site/io.sls`**

```scheme
#!r6rs
(library (site io)
  (export read-site-inputs write-site)
  (import (rnrs) (site pages) (site render) (site serializer))

  (define (slurp path)
    (call-with-input-file path
      (lambda (p)
        (let loop ((cs '()) (c (get-char p)))
          (if (eof-object? c) (list->string (reverse cs)) (loop (cons c cs) (get-char p)))))))

  (define (source-path name)
    (if (string=? name "index.md") "site/index.md" (string-append "docs/" name)))

  (define (read-site-inputs)
    (map (lambda (entry) (let ((name (car entry))) (cons name (slurp (source-path name)))))
         pages))

  (define (html-name name)
    (string-append (substring name 0 (- (string-length name) 3)) ".html"))

  (define (write-site result out-dir)
    (for-each
      (lambda (pg)
        (call-with-output-file (string-append out-dir "/" (html-name (car pg)))
          (lambda (p) (put-string p "<!doctype html>\n") (put-string p (sxml->html (cdr pg))))
          'truncate))
      (site-result-pages result))))
```

- [ ] **Step 4: Implement `build-site.sps`**

```scheme
#!r6rs
(import (rnrs) (only (chezscheme) getenv) (site io) (site render))

(define ref (or (getenv "SITE_REF") "main"))
(define out (or (getenv "SITE_OUT") "build/site"))

(let ((result (render-site (read-site-inputs) ref)))
  (write-site result out)
  (display "site: wrote ") (display (length (site-result-pages result)))
  (display " pages to ") (display out) (newline))
```

- [ ] **Step 5: Add the `site` target and copy the stylesheet**

In `Makefile`, add beside `examples` (and add `site check-site` to `.PHONY`,
keeping it one physical line):

```make
site: build ## Generate the static docs site into build/site/
	@mkdir -p build/site
	@CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) SITE_REF="$${SITE_REF:-main}" \
	  $(CHEZ) --program build-site.sps
	@cp site/style.css build/site/style.css
	@echo "site: build/site ready (open build/site/index.html)"
```

- [ ] **Step 6: Build it and verify the output**

Run: `make site`

Then:

```bash
ls build/site/*.html | wc -l          # expect 9
test -s build/site/index.html && echo "index non-empty"
test -f build/site/style.css && echo "css copied"
grep -c 'href="ast.html' build/site/index.html   # expect >= 1 (links rewritten)
grep -c '\.md"' build/site/index.html || echo "no raw .md links leaked"
```

Expected: `9`, `index non-empty`, `css copied`, a non-zero rewritten-link
count, and no leaked `.md`.

- [ ] **Step 7: Commit**

```bash
git add site/io.sls build-site.sps site/index.md site/style.css Makefile
git commit -m "feat(site): make site -- build the tree into build/site/

The shell reads site/index.md + docs/*.md, renders through the pipeline,
serializes with the pre-safe serializer, and writes build/site/ (already
gitignored). style.css is ported from the approved preview; index.md is the
authored home. Nothing is compiled."
```

---

### Task 8: `check-site` — the gate and its mutations

**Files:**
- Create: `tests/site-check.sps`, `.plans/docs-site-mutation-log.md`
- Modify: `Makefile` (a `check-site` target, `.PHONY`)

**Interfaces:**
- Consumes: `(site render)`, `(site io)`, `(site pages)`, `(site serializer)`
- Produces: `make check-site`

- [ ] **Step 1: Implement the gate `tests/site-check.sps`**

Asserts the four invariants on `render-site`'s return value (§7), reading
the real inputs. Exits non-zero, by name, on any failure.

```scheme
#!r6rs
(import (rnrs) (only (chezscheme) getenv) (site io) (site render)
        (site pages) (site serializer))

(define (die . parts) (for-each (lambda (x) (display x (current-error-port))) parts)
  (newline (current-error-port)) (exit 1))

(define ref (or (getenv "SITE_REF") "main"))
(define result (render-site (read-site-inputs) ref))

;; (1) nav completeness: (site pages) minus index equals docs/*.md on disk.
(define nav-docs
  (sort string<? (filter (lambda (n) (not (string=? n "index.md"))) (map car pages))))
(define disk-docs
  (sort string<? (filter (lambda (n) (let ((l (string-length n)))
                                       (and (> l 3) (string=? ".md" (substring n (- l 3) l)))))
                         (map (lambda (p) p) (directory-list-md "docs")))))
(unless (equal? nav-docs disk-docs)
  (die "check-site: nav completeness FAILED. pages.sls=" nav-docs " docs/=" disk-docs))

;; (2) anchor resolution: no leaked (unresolved intra-site) links.
(unless (null? (site-result-leaked result))
  (die "check-site: anchor resolution FAILED. danglers=" (site-result-leaked result)))

;; (3) no relative .md leak in the serialized output.
(for-each
  (lambda (pg)
    (let ((html (sxml->html (cdr pg))))
      (when (contains-relative-md? html)
        (die "check-site: a relative .md link leaked into " (car pg)))))
  (site-result-pages result))

;; (4) no <pre> reflow: a deeply-indented code block round-trips.
(let ((probe (sxml->html '(pre (code "a\n        b\n")))))
  (unless (string=? probe "<pre><code>a\n        b\n</code></pre>")
    (die "check-site: <pre> reflow FAILED: " probe)))

(display "check-site: nav, anchors, no .md leak, no <pre> reflow -- all green\n")
(exit 0)
```

Add the two helpers `directory-list-md` (wrap `(only (chezscheme)
directory-list)`) and `contains-relative-md?` (scan for `.md"` occurrences
whose preceding run is not `https://…/blob/…`, i.e. a `href="` that does not
start with `http`). Concretely:

```scheme
(define (directory-list-md dir) ((eval 'directory-list (environment '(chezscheme))) dir))
;; simpler: import directory-list directly in the import list above:
;;   (only (chezscheme) getenv directory-list)
(define (contains-relative-md? html)
  ;; a href/src that is relative (no scheme) and ends the URL in .md
  (let scan ((i 0))
    (cond ((>= i (string-length html)) #f)
          ((and (href-start? html i))
           (let ((url (url-at html (href-value-start html i))))
             (if (and (relative? url) (suffix? ".md" url)) #t (scan (+ i 1)))))
          (else (scan (+ i 1))))))
```

The implementer may replace the scan with a simpler, robust check: since
`build-site.sps` already writes files, have `check-site` instead
`grep`-scan the serialized strings for `href="[^"]*\.md"` where the value
does not start with `http`. Keep whichever is clearer; the mutation in
Step 4 must make it fail.

- [ ] **Step 2: Add the `check-site` target**

```make
check-site: build ## Build the site in memory and assert links, anchors, nav, and no <pre> reflow
	@CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) SITE_REF="$${SITE_REF:-main}" \
	  $(CHEZ) --program tests/site-check.sps
```

Add `site check-site` to the `.PHONY` line (one physical line) if Task 7 did
not already.

- [ ] **Step 3: Run the gate green**

Run: `make check-site`
Expected: `check-site: nav, anchors, no .md leak, no <pre> reflow -- all green`, exit 0.

- [ ] **Step 4: Mutate each invariant; watch it fail; record**

For each, apply the change, run `make check-site`, confirm the named
failure, then revert and confirm green.

1. **nav completeness** — remove one entry (e.g. `("building.md" . "Building")`)
   from `site/pages.sls`. Expect: `nav completeness FAILED` naming the set
   difference.
2. **anchor resolution** — in `site/slug.sls`, make `slugify` keep `.` (drop
   it from the filter). Expect: `anchor resolution FAILED` — e.g.
   `options.md#resource-limits` no longer resolves.
3. **no `.md` leak** — in `site/links.sls`, short-circuit `rewrite-target`
   for `.md` paths to return the target unchanged. Expect: `a relative .md
   link leaked`.
4. **no `<pre>` reflow** — in `site/serializer.sls`, make `emit` put a
   newline+indent before element children. Expect: `<pre> reflow FAILED`.

- [ ] **Step 5: Record the mutations**

Create `.plans/docs-site-mutation-log.md`:

```markdown
# Docs-site mutation log

Evidence that each check added by `.plans/2026-08-22-docs-site-design.md`
can fail. Per AGENTS.md, a test is finished when it has been watched to
fail, not when it passes.

## Mutation A — check-site notices an incomplete nav
**Guards:** every docs/*.md appears in the site nav.
**Mutation:** removed `building.md` from `site/pages.sls`.
**Result:** FAILED — `check-site: nav completeness FAILED …` naming `building.md`.
**Reverted:** yes.

## Mutation B — check-site notices a broken slug algorithm
**Guards:** generated slugs match the anchors docs/ hand-wrote.
**Mutation:** `slugify` kept `.`; "Resource limits" no longer slugged to `resource-limits`.
**Result:** FAILED — `anchor resolution FAILED`, `options.md#resource-limits` dangled.
**Reverted:** yes.

## Mutation C — check-site notices a leaked .md link
**Guards:** no relative `.md` href reaches the HTML.
**Mutation:** disabled the `.md`→`.html` rewrite branch.
**Result:** FAILED — `a relative .md link leaked into …`.
**Reverted:** yes.

## Mutation D — check-site notices <pre> reflow
**Guards:** the serializer never injects whitespace into code.
**Mutation:** `emit` indented element children.
**Result:** FAILED — `<pre> reflow FAILED`, the probe gained indentation.
**Reverted:** yes.
```

- [ ] **Step 6: Commit**

```bash
git add tests/site-check.sps Makefile .plans/docs-site-mutation-log.md
git commit -m "feat(site): check-site gate with four watched mutations

check-site asserts on render-site's return value: nav completeness, anchor
resolution (which proves the slug algorithm against docs/'s own anchors), no
relative .md leak, and no <pre> reflow. Each invariant was broken, watched
to fail by name, and recorded (Mutations A-D)."
```

---

### Task 9: The Pages workflow

**Files:**
- Create: `.github/workflows/pages.yml`

**Interfaces:**
- Consumes: `make check-site`, `make site`
- Produces: a GitHub Pages deployment on `v*` tag push

- [ ] **Step 1: Write the workflow**

```yaml
name: Pages
on:
  push:
    tags: ["v*"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - name: Install Chez and libcmark-gfm
        run: sudo apt-get update && sudo apt-get install -y chezscheme libcmark-gfm-dev libcmark-gfm-extensions-dev
      - name: Vendor Scheme deps
        run: make deps
      - name: Gate the site
        run: make check-site CHEZ=chezscheme SITE_REF="${GITHUB_REF_NAME}"
      - name: Build the site
        run: make site CHEZ=chezscheme SITE_REF="${GITHUB_REF_NAME}"
      - uses: actions/upload-pages-artifact@v3
        with: { path: build/site }
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

Note: `SITE_REF` is `${GITHUB_REF_NAME}` — the tag for a tag push, or the
selected branch/tag for a `workflow_dispatch`. On macOS the binary is
`chez`; CI is Ubuntu, where it is `chezscheme`, hence `CHEZ=chezscheme`.

- [ ] **Step 2: Validate locally what can be validated**

The deploy itself needs GitHub, but the targets it calls must exist and the
YAML must parse:

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/pages.yml')); print('yaml ok')"
for t in check-site site deps; do grep -qE "^$t:" Makefile && echo "ok make $t" || echo "MISS make $t"; done
```

Expected: `yaml ok`, and `ok make check-site` / `site` / `deps`.

- [ ] **Step 3: Confirm the apt package names install Chez + libcmark-gfm**

Cross-check the package names against `docs/installing.md`'s Linux row (the
same ones CI already uses in `ci.yml`). If `ci.yml` names them differently,
match `ci.yml` — it is the proven source.

Run: `rg -n 'apt-get install|libcmark|chezscheme' .github/workflows/ci.yml`

Fix `pages.yml`'s install line to match.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/pages.yml
git commit -m "ci(site): build and deploy the docs site on a release tag

Triggers on v* tag push (SITE_REF = the tag, so out-of-site links pin to
it) and on workflow_dispatch. Gates with check-site before building, then
uploads build/site as a Pages artifact and deploys. libcmark-gfm is
provisioned exactly as ci.yml does."
```

---

### Task 10: CHANGELOG and final verification

**Files:**
- Modify: `CHANGELOG.md`, `.plans/docs-site-mutation-log.md`

- [ ] **Step 1: Run every gate together**

Run:

```bash
make test && make check-site && make site
```

Expected: `ALL SUITES PASSED` (the two `test-site*` suites included),
`check-site … all green`, and `site: build/site ready`. Do not proceed on a
failure — fix it in the task that introduced it.

- [ ] **Step 2: Confirm the pure suite is actually pure**

Run: `CHEZ_CMARK_GFM_LIBS=/nonexistent CHEZSCHEMELIBDIRS=src:tests:site:build/scheme-libs chez --program tests/test-site.sps`

Expected: PASS — `tests/test-site.sps` imports no native library, so a
poisoned `libcmark-gfm` cannot affect it. (If it fails, a native import
crept into one of the pure `site/` modules — remove it.)

- [ ] **Step 3: Add the CHANGELOG entry**

Under `## Unreleased` in `CHANGELOG.md` (create the section if the other
session's branch has not), matching the file's heading style:

```markdown
### Added

- A static documentation site generated from `docs/*.md` and an authored
  `site/index.md`, rendered entirely through `markdown->sxml` → transform →
  serialize and deployed to GitHub Pages. Flexoki theme, sidebar + per-page
  TOC. `make site` builds it into `build/site/` (nothing committed);
  `make check-site` asserts nav completeness, anchor resolution, no `.md`
  leak, and no `<pre>` reflow. `.github/workflows/pages.yml` deploys on a
  `v*` tag.
```

- [ ] **Step 4: Close the mutation log**

Append to `.plans/docs-site-mutation-log.md` a one-line summary table of
Mutations A–D and their outcomes. Any invariant whose mutation did **not**
produce the predicted failure is written down as uncovered, with the reason
(AGENTS.md).

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md .plans/docs-site-mutation-log.md
git commit -m "docs(site): record the docs-site generator in CHANGELOG"
```

---

## Self-Review

**Spec coverage** — spec §1 core → Tasks 3–6; §2 rewriter → Task 4; §3
slugging → Task 1; §4 templating/nav/callouts → Tasks 3,5; §5 styling →
Task 7 (ported); §6 serializer → Task 2; §7 gating → Task 8; §8 build/deploy
→ Tasks 7,9; §9 files → all; §12 coordination → the branch note. No gap.

**Placeholder scan** — the serializer (Task 2) and stylesheet (Task 7) are
"adapt an existing artifact" rather than reproduced verbatim; both name the
exact source and the exact properties their tests pin, which is executable,
not a placeholder.

**Type consistency** — `render-site` returns a `site-result` record
(`-pages`, `-registry`, `-leaked`) used identically in Tasks 6 and 8;
`transform-body` returns `(values body toc)` consumed in Task 6;
`rewrite-links` returns `(values body danglers)` consumed in Task 6;
`page->document`'s five positional args match Tasks 5 and 6; `sxml->html`
is used in Tasks 2, 5, 8.
