# Usage

This page assumes `(cmark gfm)` already imports; see
[installing.md](installing.md) if it doesn't yet.

## Getting started

```scheme
(import (cmark gfm))

;; Safe by default: raw HTML and unsafe link schemes are suppressed.
(markdown->html "# Hello\n\n~~struck~~\n" (default-cmark-options))
```

Every renderer takes a `cmark-options` record as its second argument.
`(default-cmark-options)` is the one every example on this page starts
from — its ten fields are the whole subject of [options.md](options.md).

Options are named symbols, passed as a plist, not positional arguments and
not a mutable struct:

```scheme
;; Unknown keys, duplicate keys, and unknown extensions are rejected before
;; anything native is allocated.
(markdown->html "<b>raw</b>\n" (make-cmark-options 'unsafe-html? #t))
```

`make-cmark-options` returns a new, immutable record. To change one field of
an existing record, use `cmark-options-with` — it rebuilds from the
original's current values plus your overrides, and the original stays
exactly as it was:

```scheme
(define base (make-cmark-options 'extensions '(table)))
(markdown->html "| a |\n|---|\n| 1 |\n" (cmark-options-with base 'smart? #t))
;; base still has smart? #f -- cmark-options-with returned a third record.
```

The blocks above are adapted from
[`examples/01-rendering.sps`](../examples/01-rendering.sps) and
[`examples/02-options.sps`](../examples/02-options.sps). `make examples` runs
every file under `examples/` and diffs its output against a pinned
expectation, so those two files cannot go stale silently — but these
adapted copies are not re-checked against them, so verify by eye if either
file changes.

Parsing to a Scheme-owned tree is [ast.md](ast.md); converting to SXML is
[sxml.md](sxml.md). Every condition any entry point on this page can raise
is catalogued in [errors.md](errors.md).

## The renderers

Four entry points, all taking the Markdown source first and a
`cmark-options` record second:

| Entry point            | Arity                                  | Wraps |
|-------------------------|-----------------------------------------|-------|
| `markdown->html`       | `(md options)`                         | no    |
| `markdown->xml`        | `(md options)`                         | no    |
| `markdown->commonmark` | `(md options)`, or `(md options width)` | yes   |
| `markdown->plaintext`  | `(md options)`, or `(md options width)` | yes   |

```scheme
(markdown->commonmark "long paragraph text here\n" base 72)
(markdown->plaintext  "long paragraph text here\n" base 72)
(markdown->xml        "# Hello\n" base)
```

`markdown->html` and `markdown->xml` are defined at a fixed arity of two.
`markdown->commonmark` and `markdown->plaintext` are `case-lambda`s that
accept either two or three arguments — see [Wrap width](#wrap-width) for
what the third one means, and what happens if you hand it to the wrong
renderer.

## Wrap width

Width is a **positional argument to the renderer**, not a field of
`cmark-options`. That follows cmark's own split: option bits
(`validate-utf8?`, `hardbreaks?`, and the rest) govern both the parser and
the renderer, but width only ever applies to some renderers, so it lives
outside the record the parser and every renderer otherwise share.

- On `markdown->commonmark` and `markdown->plaintext`, width is optional.
  Leaving it out is equivalent to passing `0`, which cmark treats as "do not
  wrap" — the two forms produce byte-identical output.
- `markdown->html` and `markdown->xml` have no width clause at all.
  **Passing a third argument to either is a plain Scheme
  wrong-number-of-arguments error** — not `&cmark-invalid-option`, and not a
  setting that gets silently ignored. There is nowhere for it to go.
- A width that *is* accepted positionally but is negative or inexact raises
  one of this library's own conditions instead, checked before any native
  resource is acquired:

  ```scheme
  (guard (e ((cmark-invalid-option? e)
             (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e))))
    (markdown->commonmark "hi\n" base -1))
  ;; => (width invalid-width)
  ```

See [errors.md](errors.md) for `&cmark-invalid-option` and every other
condition this library raises.

## Which library is loaded

Three calls report on the native library itself, independent of anything
passed to a renderer:

```scheme
(cmark-gfm-version)                 ;; => "0.29.0.gfm.13"
(cmark-gfm-version-compatible?)     ;; => #t
(cmark-gfm-available-extensions)    ;; => (autolink strikethrough table tagfilter tasklist)
```

`cmark-gfm-version` and `cmark-gfm-version-compatible?` report on whatever
`(import (cmark gfm))` already found — the same discovery
[`make build`](installing.md#what-make-build-does) runs as a standalone
preflight, available here as a procedure instead of a command's exit code.

`cmark-gfm-available-extensions` is not the same thing as
`supported-extensions`. `supported-extensions` is pure: it names the five
extensions this binding knows how to translate to and from cmark's own
strings, with no native call involved, and it's the list `make-cmark-options`
checks an `'extensions` entry against. `cmark-gfm-available-extensions`
instead probes the *loaded* library and returns only the subset actually
registered there.

The two coincide on the library this machine loaded. Nothing guarantees
that on every host: `make-cmark-options` accepting an extension symbol only
means this binding knows the name, not that the library on a given machine
has it registered. That's checked separately, per extension, when a
document is parsed — a genuinely missing one raises
`&cmark-extension-unavailable` naming it (see [errors.md](errors.md)).
