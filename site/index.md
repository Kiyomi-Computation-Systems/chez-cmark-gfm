# chez-cmark-gfm

An R6RS binding to [cmark-gfm](https://github.com/github/cmark-gfm), GitHub's
own C implementation of CommonMark plus its GitHub Flavored Markdown
extensions — tables, strikethrough, autolinks, and task lists. Nothing is
generated and nothing is compiled: importing `(cmark gfm)` locates a
matching `cmark-gfm` shared library already on the machine and loads it.
Render straight to HTML, CommonMark, plain text, or an XML dump of the
parse tree, or ask for the tree itself — as an immutable Scheme AST, or as
SXML you can walk and rewrite. Raw HTML and dangerous URL schemes are
neutralised by default, the same way on every entry point; unsafe
rendering has to be requested by name.

## A taste

```scheme
(import (rnrs) (cmark gfm))

(define doc "# Title\n\nA ~~struck~~ word and a <b>raw</b> tag.\n")

;; Safe by default. Raw HTML is replaced by a comment, not passed through --
;; there is no option you have to remember to set.
(markdown->html doc (default-cmark-options))
```

## Read next

- [Installing](installing.md) — get Chez Scheme and a system `cmark-gfm` in place.
- [Usage](usage.md) — the four render functions, and the options record they all take.
- [Options](options.md) — every parser and render option, and what each one changes.
- [The AST](ast.md) — the immutable parse tree `markdown->ast` returns, and its node properties.
- [SXML](sxml.md) — the AST as a walkable, serializable SXML tree.
- [Errors](errors.md) — the condition hierarchy: what raises, what doesn't, and why.
- [Memory ownership](memory.md) — the contract across the native/Scheme boundary.
- [Building](building.md) — building `cmark-gfm` and this library's own test suites from source.
