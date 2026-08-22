# SXML

This page assumes `(cmark gfm)` already imports; see
[installing.md](installing.md) if it doesn't yet. It covers the adapter, the
full AST→SXML mapping, and choosing a serializer to render the result.
Parsing to the tree the adapter consumes is [ast.md](ast.md); rendering
straight to HTML without an intermediate tree is [usage.md](usage.md). Every
condition named below is catalogued in [errors.md](errors.md).

## Getting started

```scheme
(import (cmark gfm))

;; Parse and convert in one step. Renderer defaults; positions off.
(markdown->sxml "# Hello\n\n[l](/x \"t\")\n")
;; => (*TOP* (h1 "Hello") (p (a (^ (href "/x") (title "t")) "l")))

;; The pure adapter, when you already hold a tree.
(markdown-ast->sxml (markdown->ast "# Hello\n"))
;; => (*TOP* (h1 "Hello"))

;; markdown->sxml takes cmark's options first, the SXML policies second.
(markdown->sxml "para <b>raw</b>\n"
                (default-cmark-options)
                (make-sxml-options 'raw-html 'escape))
;; => (*TOP* (p "para " "<b>" "raw" "</b>"))
```

Two entry points, and **both take an `sxml-options` record** — the pure one
in its second argument, not only `markdown->sxml` in its third:

| Entry point          | Arity                                                           | Parses |
|-----------------------|------------------------------------------------------------------|--------|
| `markdown->sxml`     | `(md)`, `(md cmark-options)`, `(md cmark-options sxml-options)` | yes    |
| `markdown-ast->sxml` | `(tree)`, `(tree sxml-options)`                                 | no     |

So the third block above has an exact pure equivalent, for a tree you
already hold:

```scheme
(markdown-ast->sxml (markdown->ast "para <b>raw</b>\n")
                    (make-sxml-options 'raw-html 'escape))
;; => (*TOP* (p "para " "<b>" "raw" "</b>"))
```

Handing either one the wrong record type — a `cmark-options` where an
`sxml-options` belongs, or the reverse — raises `&cmark-invalid-option` with
key `#f` and reason `invalid-value`, checked before anything is parsed.

`(cmark gfm sxml)` is pure: it imports nothing that can reach a shared
object, and `make check-purity` enforces that by running its suite with
`CHEZ_CMARK_GFM_LIBS` poisoned to a nonexistent path. `markdown->sxml` lives
in `(cmark gfm)` rather than in the adapter precisely because it parses.

## Options

| Key                | Values                      | Default   |
|---------------------|------------------------------|------------|
| `raw-html`         | `omit`, `escape`            | `omit`    |
| `softbreak`        | `newline`, `break`, `space` | `newline` |
| `attribute-marker` | `caret`, `at`               | `caret`   |

`make-sxml-options`, `default-sxml-options`, and `sxml-options-with` mirror
the `cmark-options` trio in [options.md](options.md) exactly — immutable
records, functional update, and the same rejection of unknown keys,
duplicate keys, and unknown values:

```scheme
(sxml-options-raw-html (default-sxml-options))                 ;; => omit
(sxml-options-raw-html
  (sxml-options-with (default-sxml-options) 'raw-html 'escape)) ;; => escape

(make-sxml-options 'raw-htm 'omit)   ;; raises, key raw-htm,  reason unknown-key
(make-sxml-options 'raw-html 'keep)  ;; raises, key raw-html, reason invalid-value
```

`softbreak` is the SXML side of cmark's `hardbreaks?`/`nobreaks?`. Those are
renderer flags on softbreak (`html.c:319-325`) that never reach the parse,
so no AST can carry them and the adapter has no other way to learn them:

```scheme
(markdown->sxml "one\ntwo\n")  ;; => (*TOP* (p "one" "\n" "two"))
;; with 'softbreak 'break      => (*TOP* (p "one" (br) "two"))
;; with 'softbreak 'space      => (*TOP* (p "one" " " "two"))
```

## Why `omit` is the default

**`omit` is the default because it is the policy that does not depend on the
caller's serializer.** Under `omit` an `html-block` or `html-inline` becomes
`(*COMMENT* " raw HTML omitted ")` — cmark's own substitution
(`html.c:259,337`) — so the tree holds no attacker-controlled markup at all,
and the output is safe whatever serializer you chose:

```scheme
(markdown->sxml "<div onclick=\"x\">hi</div>\n")
;; => (*TOP* (*COMMENT* " raw HTML omitted "))
```

Under `escape` the literal is carried through as an ordinary string, and the
safety rests **entirely** on that serializer escaping it:

```scheme
(markdown->sxml "<div onclick=\"x\">hi</div>\n"
                (default-cmark-options)
                (make-sxml-options 'raw-html 'escape))
;; => (*TOP* "<div onclick=\"x\">hi</div>\n")
```

That is a difference in what this library can promise, not a matter of
taste. There is no trusted or unsafe mode and none is planned (ADR-0011):
SXML has no portable raw-markup node, and a caller who needs the literal
reads it from the AST, which preserves it — see [ast.md](ast.md).

## The attribute marker

**The default attribute marker is deliberately not the SXML specification's
`@`.** Both serializers reachable on this platform mark an attribute list
`^` — `wak-sxml-tools` (`sxml-tools/upstream/sxml-tools.scm:44-48`) and
`wak-htmlprag` (`htmlprag/htmlprag.scm:334`) — and neither recognises `@` at
all.

Handed a `@`-marked tree, `srl:sxml->html` does not raise. It treats the
marker as an ordinary element name and nests every attribute pair as child
elements (every `srl:` call on this page comes from
`(import (wak sxml-tools serializer))`, a dev dependency this library does
not itself import):

```scheme
(srl:sxml->html-noindent '(a (\x40; (href "/x")) "l"))
;; => "<a><@><href>/x</href></@>l</a>"

(srl:sxml->html '(a (\x40; (href "/x")) "l"))
;; => "<a><@>\n  <href>/x</href>\n</@>l</a>"
```

Same corruption, once with indentation and once without. Neither reports an
error, and neither is the HTML anyone asked for. Do not assume canonical
SXML here. `'attribute-marker 'at` gives the specification's spelling, for
hand-written pattern matching or for moving a tree to another Scheme. See
ADR-0013.

One reading note. Under `#!r6rs`, Chez's `write` prints that marker as
`\x40;`, because the bare token is not a valid R6RS symbol; `display` prints
`@`. It is the same interned symbol either way, but a written tree looks
like `(*TOP* (p (a (\x40; (href "/x")) "l")))`.

## Options that are refused, and one that is not

`markdown->sxml` raises `&cmark-invalid-option` with reason `not-applicable`
for `unsafe-html?`, `hardbreaks?`, and `nobreaks?`:

```scheme
(markdown->sxml "# hi\n" (make-cmark-options 'unsafe-html? #t))
;; raises &cmark-invalid-option, key unsafe-html?, reason not-applicable
```

All three are cmark **renderer** options. They never reach the parse, so no
AST can carry them, and SXML is a different renderer with its own
policies — `raw-html` and `softbreak` above. Accepting one silently would
discard a setting the caller made explicitly. The cost is real and accepted:
one options record shared with `markdown->html` needs a `cmark-options-with`
line, which makes the divergence in security semantics visible at the call
site rather than invisible.

`source-positions?` is the deliberate exception. It is **accepted and
silently discarded**. Unlike the three above it genuinely does reach the
AST — the parse honours it, at full cost — and it is the adapter that then
drops the positions, per ADR-0011. What that costs a caller is wasted parse
work, not a downgraded policy, so it is not refused:

```scheme
(equal? (markdown->sxml "# hi\n" (make-cmark-options 'source-positions? #t))
        (markdown->sxml "# hi\n"))
;; => #t
```

`markdown->sxml` defaults to `(default-cmark-options)`, where positions are
off, rather than to `(default-ast-options)`: turning them on would pay for
information the output discards (ADR-0009 — see [options.md](options.md) for
how the two default records differ).

## The mapping

Every row is the shape a conforming serializer must render as the cited
cmark output. `^` below is the attribute marker under the default
`attribute-marker: caret`; under `at` it is `@` and nothing else changes.
Citations are line numbers at the pinned submodule revision: bare `html.c`
means `vendor/cmark-gfm/src/html.c`, and every other path is relative to
`vendor/cmark-gfm/`.

| AST node                          | SXML                                                                  | cmark                            |
|------------------------------------|------------------------------------------------------------------------|-----------------------------------|
| `document`                        | `(*TOP* …)`                                                           | —                                |
| `heading` level *n*               | `(h1 …)` … `(h6 …)`                                                   | `html.c:201`                 |
| `paragraph`                       | `(p …)`, or spliced away inside a tight list                          | `html.c:287`                 |
| `text`                            | a string, verbatim                                                    | `html.c:311`                 |
| `emph`                            | `(em …)`                                                              | `html.c:376`                 |
| `strong`                          | `(strong …)`; directly inside a `strong`, spliced away                | `html.c:366` (gfm.10+)       |
| `strikethrough`                   | `(del …)`                                                             | `extensions/strikethrough.c:132` |
| `blockquote`                      | `(blockquote …)`                                                      | `html.c:151`                 |
| `list`, bullet                    | `(ul …)`                                                              | `html.c:170`                 |
| `list`, ordered, start = 1        | `(ol …)`                                                              | `html.c:174`                 |
| `list`, ordered, start ≠ 1        | `(ol (^ (start "N")) …)`                                              | `html.c:178`                 |
| `item`, plain                     | `(li …)`                                                              | `html.c:190`                 |
| `item`, task, checked             | `(li (input (^ (type "checkbox") (checked "") (disabled ""))) " " …)` | `extensions/tasklist.c:125`      |
| `item`, task, unchecked           | the same with **no** `checked` attribute at all                       | `extensions/tasklist.c:127`      |
| `link`                            | `(a (^ (href …) (title …)) …)`                                        | `html.c:384`                 |
| `image`                           | `(img (^ (src …) (alt …) (title …)))`                                 | `html.c:402`                 |
| `code`                            | `(code …)`                                                            | `html.c:329`                 |
| `code-block`, no info             | `(pre (code …))`                                                      | `html.c:218`                 |
| `code-block`, info                | `(pre (code (^ (class "language-X")) …))`                             | `html.c:242`                 |
| `thematic-break`                  | `(hr)`                                                                | `html.c:280`                 |
| `linebreak`                       | `(br)`                                                                | `html.c:315`                 |
| `softbreak`                       | `"\n"`, or `(br)` / `" "` per `softbreak`                             | `html.c:319-325`             |
| `html-inline` / `html-block`      | `(*COMMENT* " raw HTML omitted ")`, or the literal under `escape`     | `html.c:259,337`             |
| `table`                           | `(table (thead …) (tbody …))`, either section absent when empty       | `extensions/table.c:756,774`     |
| `table-row`                       | `(tr …)`                                                              | `extensions/table.c:774`         |
| `table-cell`, header / body       | `(th (^ (align …)) …)` / `(td (^ (align …)) …)`                       | `extensions/table.c:798,807-811` |
| `extension`, or anything unmapped | raises `&cmark-unsupported-node`, carrying the type                   | —                                |

Worked, so the shapes above are not read off a table alone:

```scheme
(markdown->sxml "- [x] done\n- [ ] todo\n")
;; => (*TOP* (ul (li (input (^ (type "checkbox") (checked "") (disabled ""))) " " "done")
;;               (li (input (^ (type "checkbox") (disabled ""))) " " "todo")))

(markdown->sxml "| a | b |\n|:--|--:|\n| 1 | 2 |\n")
;; => (*TOP* (table (thead (tr (th (^ (align "left")) "a") (th (^ (align "right")) "b")))
;;                  (tbody (tr (td (^ (align "left")) "1") (td (^ (align "right")) "2")))))

(markdown->sxml "3. a\n")   ;; => (*TOP* (ol (^ (start "3")) (li "a")))
(markdown->sxml "1. a\n")   ;; => (*TOP* (ol (li "a")))
```

`markdown-ast->sxml` is public and takes an arbitrary tree, so it also
raises `&cmark-malformed-tree` (reason `header-row-not-first`) for a table
whose header row is not the first: cmark's parser cannot produce one, and
reproducing what its renderer would do opens a `thead` inside an open
`tbody`. That is the only structural check the adapter makes. Everything
else about tree shape is caller responsibility — a wrong type in
Scheme-only code raises R6RS `&assertion`, not one of this library's
conditions. See [ast.md](ast.md) for how a hand-built node is meant to look.

## Four details the table compresses

- **A tight list has no `p` elements in its output at all.** `html.c:287-297`
  reads tightness off the paragraph's *grandparent* and emits no `<p>` tags;
  the paragraph's children go straight into the `<li>`. This is not
  "paragraphs that render compactly".

  ```scheme
  (markdown->sxml "- a\n- b\n")     ;; => (*TOP* (ul (li "a") (li "b")))
  (markdown->sxml "- a\n\n- b\n")   ;; => (*TOP* (ul (li (p "a")) (li (p "b"))))
  ```

  Because the test is on the grandparent, one intervening container is
  enough to bring the `<p>` back — a blockquote inside a tight item has a
  paragraph whose grandparent is the *item*, never the list:

  ```scheme
  (markdown->sxml "- > q\n- b\n")
  ;; => (*TOP* (ul (li (blockquote (p "q"))) (li "b")))
  ```

- **`title` and `align` are omitted, never empty.** `html.c:392` writes
  `title` only when it is non-empty, and `extensions/table.c:807-811` writes
  no `align` for an unaligned column. An empty attribute is a byte
  difference. `align` appears on body cells as well as header cells.

- **`class="language-X"` takes the first token of the info string only**
  (`html.c:223-227`). The rest is reachable only through
  `CMARK_OPT_FULL_INFO_STRING`, which this library does not expose.

  ````scheme
  (markdown->sxml "```scheme extra\n(x)\n```\n")
  ;; => (*TOP* (pre (code (^ (class "language-scheme")) "(x)\n")))
  ````

- **An image's `alt` is a flattened string, produced by cmark's own plain
  mode** (`html.c:123-139`), not by the serializer: `text`, `code`, and
  `html-inline` contribute their literals, `linebreak` and `softbreak` a
  single space, every other node nothing while still being descended into.

  ```scheme
  (markdown->sxml "![a *b* `c`](/i.png \"t\")\n")
  ;; => (*TOP* (p (img (^ (src "/i.png") (alt "a b c") (title "t")))))
  ```

## The `strong` splice

**The `strong` splice is the one row with a version qualifier.** cmark
gained that rule in `0.29.0.gfm.10` (upstream `5c75d23`); `gfm.0` through
`gfm.9` emit both tags.

```scheme
(markdown->sxml "**a **b** c**\n")  ;; => (*TOP* (p (strong "a " "b" " c")))
(markdown->sxml "*_foo_*\n")        ;; => (*TOP* (p (em (em "foo"))))
```

`emph` has no such rule (`html.c:376-382`), which is why the second line
keeps both `em` tags. The test in cmark is on the immediate parent alone, so
`__foo, __bar__, baz__` collapses exactly as `****foo****` does.

The mapping above is fixed and deliberately not version-aware, so on a
cmark-gfm older than `0.29.0.gfm.10` `markdown->sxml` splices a `strong`
directly inside a `strong` while that same library's `markdown->html` does
not. Both are self-consistent; they are not consistent with each other. The
alternative — a version-aware adapter — would destroy its determinism and
contradict `make check-purity`, which runs it with no library loaded at all.
Rationale and the platform arithmetic are in
[`.plans/2026-08-21-shimless-ffi-design.md`](../.plans/2026-08-21-shimless-ffi-design.md)
§3.9; [installing.md](installing.md#supported-versions) has the supported
range.

## What the mapping drops

HTML vocabulary cannot express everything the AST holds. `markdown->ast`
remains the interface for all of it:

| Dropped                              | Where it survives                |
|---------------------------------------|-----------------------------------|
| `list` `delimiter` (period vs paren) | [`markdown->ast`](ast.md)        |
| fence info past the first token       | [`markdown->ast`](ast.md)        |
| image child structure                 | [`markdown->ast`](ast.md)        |
| all source positions                  | [`markdown->ast`](ast.md)        |
| raw HTML literals (under `omit`)      | [`markdown->ast`](ast.md)        |

This is ADR-0011, not an oversight. Because the tree carries no metadata
channel, every piece of information the tree carries *about the document* is
information the HTML shows — which is what puts almost all of it under the
byte-for-byte oracle below. Two properties stay outside that oracle and are
tested directly instead: `raw-html: escape`, which cmark has no equivalent
for, and `attribute-marker`, which the test serializer accepts in both
spellings and so normalises away before comparing. The full accounting is in
[`.plans/2026-08-17-stage-5-sxml-design.md`](../.plans/2026-08-17-stage-5-sxml-design.md)
§10.

## URLs

A `link` `href` and an `image` `src` take cmark's own rule, transcribed from
`src/scanners.re:345-354`: a URL is dangerous when it begins `javascript:`,
`vbscript:`, `file:`, or `data:`, matched case-insensitively, with
`data:image/png`, `data:image/gif`, `data:image/jpeg`, and `data:image/webp`
allowed through. A rejected URL yields an **empty** attribute value — not a
raised condition and not a removed attribute — matching `html.c:387-391` and
`html.c:405-409`. There is no customisation hook in 0.3.

```scheme
(markdown->sxml "[x](javascript:alert(1))\n")
;; => (*TOP* (p (a (^ (href "")) "x")))
(markdown->sxml "[x](JaVaScRiPt:alert(1))\n")
;; => (*TOP* (p (a (^ (href "")) "x")))
(markdown->sxml "![x](data:image/png;base64,AAA)\n")
;; => (*TOP* (p (img (^ (src "data:image/png;base64,AAA") (alt "x")))))
```

The adapter percent-encodes every byte outside `HREF_SAFE`
(`src/houdini_href_e.c:32-44`) and **never touches `&` or `'`**. Those two
are entity-escaped by whatever serializer you run; doing both halves in one
place produces `%2520` or `&amp;amp;`, valid HTML carrying the wrong URL.

```scheme
(markdown->sxml "[x](/café)\n")       ;; => (*TOP* (p (a (^ (href "/caf%C3%A9")) "x")))
(markdown->sxml "[x](/a?q=1&r=2)\n")  ;; => (*TOP* (p (a (^ (href "/a?q=1&r=2")) "x")))
(markdown->sxml "[x](/it's)\n")       ;; => (*TOP* (p (a (^ (href "/it's")) "x")))
```

## Serializing: your serializer, not ours

The SXML tree is verified by rendering it through a test-only serializer
written against `vendor/cmark-gfm/src/html.c` and diffing byte-for-byte
against `markdown->html` for the same parse, across all 744 examples of
cmark's own corpus (`spec.txt`, `extensions.txt`, `smart_punct.txt`, and
`regression.txt`), under both attribute markers.

> **That byte-equality is a property of the serializer in
> [`tests/sxml-html-serializer.sls`](../tests/sxml-html-serializer.sls), not
> a promise about your pipeline.** That serializer is test-only. It is not
> exported, not installed, and not something you can import from
> `(cmark gfm)`. A conforming third-party serializer *will* differ.

None of the differences below changes what the document means. Measured
against `wak-sxml-tools`' `srl:sxml->html`, the one this project tests
conformance through:

|                              | cmark            | `srl:sxml->html`                         |
|-------------------------------|-------------------|-------------------------------------------|
| Between blocks               | `\n`             | `\n` plus depth-proportional indentation |
| Two adjacent inline elements | nothing between  | newline and indent injected              |
| `"` in text                  | `&quot;`         | left raw                                 |
| `'` in an `href`             | `&#x27;`         | `&apos;`                                 |
| Childless elements           | `<hr />`         | `<hr>`                                   |
| End of document              | trailing `\n`    | none                                     |

The second row is the one worth knowing: an injected newline between two
adjacent inline elements collapses to a rendered space, so
`<p><strong>a</strong><em>b</em></p>` and
`<p>\n  <strong>a</strong>\n  <em>b</em>\n</p>` do not look the same.

```scheme
(markdown->html "**a***b*\n" (default-cmark-options))
;; => "<p><strong>a</strong><em>b</em></p>\n"
(srl:sxml->html (markdown->sxml "**a***b*\n"))
;; => "<p>\n  <strong>a</strong>\n  <em>b</em>\n</p>"
(srl:sxml->html-noindent (markdown->sxml "**a***b*\n"))
;; => "<p><strong>a</strong><em>b</em></p>"
```

`srl:sxml->html-noindent` avoids the whole indentation family, which is the
first two rows and the reason for the warning below.

> **⚠️ A pretty-printing serializer will corrupt `<pre>` content.** Injected
> indentation inside a code block is content, not formatting.
> `srl:sxml->html` does not do it — it exempts `pre`, `script`, `style`, and
> `textarea`, and any element with a bare-text child, and
> [`tests/test-sxml-portability.sps`](../tests/test-sxml-portability.sps)
> asserts the exact rendering — but that is a property of that serializer,
> checked, not a property of SXML.

````scheme
(markdown->sxml "```\n  indented\n  more\n```\n")
;; => (*TOP* (pre (code "  indented\n  more\n")))
(srl:sxml->html (markdown->sxml "```\n  indented\n  more\n```\n"))
;; => "<pre><code>  indented\n  more\n</code></pre>"
````

That assertion is equality against the whole rendering, not a substring
probe, because a substring probe passes against exactly the corruption it
exists to detect: a serializer that injects four spaces before content that
already begins with two still *contains* the original two.

The `*COMMENT*` node the default `raw-html` policy emits is the other thing
to check in a candidate serializer, since every document containing raw HTML
carries one:

```scheme
(srl:sxml->html (markdown->sxml "<div>raw</div>\n\n# heading\n\npara <b>bold</b> tail\n"))
;; => "<!-- raw HTML omitted -->\n<h1>heading</h1>\n<p>para <!-- raw HTML omitted -->bold<!-- raw HTML omitted --> tail</p>"
```

A serializer that renders it as `<*COMMENT*> raw HTML omitted </*COMMENT*>`,
or that emits `*TOP*` as an element wrapping the whole document, returns a
string rather than raising — so "it did not error" proves nothing here.
Read the output.

`wak-sxml-tools` is a **dev dependency**: `(cmark gfm)` does not import it,
and nothing in this library obliges you to use it. Everything on this page
above the serializing section is true of the tree itself; everything in this
section is true of one particular consumer of it.
