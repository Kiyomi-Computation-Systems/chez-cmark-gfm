# chez-cmark-gfm

An R6RS binding to [cmark-gfm](https://github.com/github/cmark-gfm), GitHub's
own C implementation of CommonMark plus its GitHub Flavored Markdown
extensions — tables, strikethrough, autolinks, and task lists.

Render straight to HTML, CommonMark, plain text, or an XML dump of the
parse tree, or ask for the tree itself — as an immutable [Scheme AST](ast.md), or as
[SXML](sxml.md) you can walk and rewrite. Raw HTML and dangerous URL schemes are
neutralised by default, unsafe rendering has to be requested.

💡 These HTML pages were generated from [Markdown](../docs) and manipulated as SXML.

Nothing is generated and nothing is compiled: importing `(cmark gfm)` locates a
matching `cmark-gfm` shared library already on the machine and loads it.

## A taste

```scheme
(import (rnrs) (cmark gfm))

(define doc "A ~~struck~~ word and a <b>raw</b> tag.\n")

;; Safe by default: raw HTML becomes a comment, with no flag to remember.
(markdown->html doc (default-cmark-options))
;; => "<p>A <del>struck</del> word and a <!-- raw HTML omitted -->raw<!-- raw HTML omitted --> tag.</p>\n"

;; The other behaviour exists, and has to be asked for by name.
(markdown->html doc (make-cmark-options 'unsafe-html? #t))
;; => "<p>A <del>struck</del> word and a <b>raw</b> tag.</p>\n"

;; SXML in HTML vocabulary, for the serializer of your choosing.
(markdown->sxml "A [link](/x) and a <b>raw</b> tag.\n")
;; => (*TOP* (p "A " (a (^ (href "/x")) "link") " and a "
;;               (*COMMENT* " raw HTML omitted ") "raw"
;;               (*COMMENT* " raw HTML omitted ") " tag."))
```

## Read next

- [Installing](installing.md) — get Chez Scheme and a system `cmark-gfm` in place.
- [Usage](usage.md) — the four render functions, and the options record they all take.
- [API reference](reference.md) — every public module and exported binding.
- [Options](options.md) — every parser and render option, and what each one changes.
- [The AST](ast.md) — the immutable parse tree `markdown->ast` returns, and its node properties.
- [SXML](sxml.md) — the AST as a walkable, serializable SXML tree.
- [Errors](errors.md) — the condition hierarchy: what raises, what doesn't, and why.
- [Memory ownership](memory.md) — the contract across the native/Scheme boundary.
- [Building](building.md) — building `cmark-gfm` and this library's own test suites from source.
