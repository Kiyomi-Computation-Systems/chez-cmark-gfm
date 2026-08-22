# The AST

This page assumes `(cmark gfm)` already imports; see
[installing.md](installing.md) if it doesn't yet. Rendering to HTML,
CommonMark, plaintext, or XML is covered in [usage.md](usage.md);
converting this tree to SXML is [sxml.md](sxml.md). Every condition
`markdown->ast` can raise is catalogued in [errors.md](errors.md).

## Parsing

```scheme
(import (cmark gfm))

;; One argument: source positions ON (ADR-0009) — if you asked for a
;; tree instead of markup, positions are usually why.
(define tree (markdown->ast "# Hello\n\n~~struck~~\n"))

(markdown-node-type tree)                      ;; => document
(markdown-node-property
  (car (markdown-node-children tree)) 'level)  ;; => 1

;; Two arguments: your options record, honoured verbatim — including
;; source-positions?, which the one-argument form always turns on.
(markdown->ast "# Hello\n" (make-cmark-options 'source-positions? #f))
```

Called with one argument, `markdown->ast` uses `default-ast-options`:
every field the same as `default-cmark-options` except
`source-positions?`, which is `#t`. Called with two arguments, the
options record you pass is used exactly as given — `default-cmark-options`
included, positions off unless you asked for them yourself. See
[options.md](options.md) for how `default-ast-options` is built and why
the default differs by entry point.

Unlike `markdown->commonmark` and `markdown->plaintext`, `markdown->ast`
takes no width argument — there is only ever one or two arguments.

## Node shape

A node is `(type properties children source)`:

```scheme
(markdown-node-type tree)        ;; a symbol, e.g. 'heading
(markdown-node-properties tree)  ;; an alist, e.g. ((level . 1))
(markdown-node-children tree)    ;; a list of nodes, left to right
(markdown-node-source tree)      ;; a source-position, or #f
```

`source` is `#f` whenever positions weren't requested, and also on a
`softbreak` or `linebreak` node even when they were: cmark never records a
position for either, at any settings, so the AST reports the same absence
those two node types have rather than inventing one. When present, it's a
`source-position` record with four fields: `source-position-start-line`,
`source-position-start-column`, `source-position-end-line`, and
`source-position-end-column`.

Nodes are immutable — there is no setter. `markdown-node-with-properties`
and `markdown-node-with-children` return a *new* node with one field
replaced; the original, and every other node still holding a reference to
it, is untouched. `make-markdown-node` and `make-source-position` build a
node by hand, for code that constructs a tree rather than only inspecting
one — see [`examples/03-ast.sps`](../examples/03-ast.sps).

**The optional default.** `markdown-node-property` reads one property by
key, and takes an optional default consulted only when the key is
genuinely absent:

```scheme
(markdown-node-property node 'checked?)               ;; #f either way
(markdown-node-property node 'checked? 'no-such-key)  ;; 'no-such-key only if truly absent
```

`task?`, `checked?`, `header?`, and `tight?` are ordinary booleans that
are legitimately `#f` on many nodes — an unchecked task item, a body
row, a loose list. Called with two arguments, `markdown-node-property`
collapses "this node has no such property" and "this node has the
property, and it's false" to the same `#f`, because that's what a missing
default resolves to either way — not because the two cases are the same.
A caller who needs to tell them apart supplies a third argument the real
value could never equal:

```scheme
(define (task-item? node)
  (not (eq? (markdown-node-property node 'task? 'absent) 'absent)))
```

Without that distinction, code that branches on `checked?` could silently
treat a `link` node — which has no `checked?` property at all — the
same as an unchecked `item`, instead of telling the two apart. Prefer
`markdown-node-property` over reading `markdown-node-properties` with
`assq` directly for this reason: the default argument is the only place
that distinction is available.

## Properties by node type

| Node type                                 | Properties                                          |
|--------------------------------------------|------------------------------------------------------|
| `heading`                                  | `level`                                              |
| `text` `code` `html-inline` `html-block`   | `literal`                                            |
| `code-block`                               | `literal` `fence-info`                               |
| `link` `image`                             | `url` `title`                                        |
| `list`                                     | `kind` `start` `tight?` `delimiter`                  |
| `item`                                     | `index` `task?` `checked?`                           |
| `table`                                    | `columns` `alignments`                               |
| `table-row`                                | `header?`                                            |
| `table-cell`                               | `alignment`                                          |
| `extension`                                | `native-type`, and `literal` when the node has one   |

`document`, `paragraph`, `blockquote`, `thematic-break`, `softbreak`,
`linebreak`, `emph`, `strong`, and `strikethrough` carry no properties —
their `type` and position in the tree is the whole content.

`extension` is the fallback: a native node type this binding doesn't
recognise by name is preserved rather than dropped, tagged with its
cmark-reported type string under `native-type`. Every node type produced
by the five extensions this binding supports (`autolink`,
`strikethrough`, `table`, `tagfilter`, `tasklist` — see
[options.md](options.md)) already appears in the table above; `autolink`
and `tagfilter` add no node type of their own, so an autolinked URL is an
ordinary `link` node. `extension` exists for a future cmark-gfm adding a
syntax extension this binding hasn't been taught yet, so a document
containing one still parses to a usable tree instead of failing outright.

## Ordinal index

An item's `index` is its *ordinal position*, not the number typed in the
source: its enclosing list's `start` plus its zero-based offset among
that list's items, and `0` for every item of a bullet list (a GFM task
list is a bullet list, so its items index `0` too).

```scheme
(define (indices md)
  (map (lambda (n) (markdown-node-property n 'index))
       (markdown-node-children
         (car (markdown-node-children (markdown->ast md))))))

(indices "1. a\n1. b\n1. c\n")  ;; => (1 2 3)
(indices "1. a\n5. b\n9. c\n")  ;; => (1 2 3)
(indices "- a\n- b\n")          ;; => (0 0)
```

The literal numbers typed in an ordered list (`1`, `5`, `9` above) aren't
recoverable from the AST — only the first one survives, as the list's
own `start` property.

## Traversal

`markdown-node-map` and `markdown-node-fold` are the two traversal
helpers. Both are pure — neither mutates the tree it's given — and both
visit every node.

```scheme
;; Children-first (bottom-up): proc receives a node whose children have
;; already been rewritten, so it can inspect the final subtree.
(markdown-node-map (lambda (n) n) tree)

;; Pre-order: proc receives a node before its children, left to right.
(markdown-node-fold (lambda (n acc) (+ acc 1)) 0 tree)
```

`markdown-node-map` rebuilds every node in the tree on every call,
whether `proc` changes that node or not — there's no shortcut for "this
subtree is unchanged, skip it." Even the identity map above returns a
tree that shares no node, at any depth, with the original (`eq?` fails
everywhere, though `equal?` holds). For a large tree, expect a full copy
on every call, not a diff.

`markdown-node-fold` threads an accumulator through the walk instead of
building a tree, so reach for it when the result isn't itself an AST —
counting nodes, collecting every `literal`, checking that some invariant
holds everywhere.

Both are exercised further in
[`examples/03-ast.sps`](../examples/03-ast.sps); `make examples` runs it
and diffs its output against a pinned expectation, so it can't go stale
silently.

## The AST is untrusted

> **⚠️ The AST is untrusted structured input.** It preserves exactly what
> the document said, including raw HTML and `javascript:` URLs.
> `unsafe-html?` does not affect it — that option is a renderer policy.
> Sanitise when you render, not when you parse.

`markdown->ast` performs no sanitisation at any step. An `html-block` or
`html-inline` node's `literal` is the raw markup as written; a `link` or
`image` node's `url` is the raw URL as written, `javascript:` scheme and
all. `unsafe-html?` (see [options.md](options.md)) governs what
`markdown->html` and the other renderers *emit* — it is consulted
nowhere in this file, and setting it has no effect on any node the tree
contains.

If you walk this tree to build your own output — your own HTML, your
own UI, anything a browser or shell might later interpret — treat every
`literal`, `url`, and `title` exactly as untrusted as the Markdown source
it came from, and sanitise at that point, not before.

## Resource limits

Two ceilings bound the copied tree, independent of `max-input-bytes`:
five megabytes of adversarial Markdown can still parse to millions of
nodes, and a byte limit on the input alone doesn't bound that.

| Key         | Default  | Bounds                            |
|--------------|----------|-------------------------------------|
| `max-nodes` | `250000` | total nodes in the copied tree      |
| `max-depth` | `1000`   | nesting depth of the copied tree    |

Both are checked *during* conversion, not after. `max-depth` is checked
on entry to every node, before any of its children are visited;
`max-nodes` is checked as each node is counted. Exceeding either raises
immediately, before recursing any further, rather than finishing the walk
and checking at the end:

```scheme
(guard (e ((cmark-resource-limit? e)
           (list (cmark-invalid-input-reason e)
                 (cmark-resource-limit-value e))))
  (markdown->ast deeply-nested (make-cmark-options 'max-depth 64)))
;; => (too-deep 64)
```

`&cmark-resource-limit` derives from `&cmark-invalid-input` and carries
the ceiling that was exceeded. It's raised while the native parser and
document are still open; both are freed on the way out regardless, so a
rejected parse leaks nothing — the partially built Scheme tree is simply
dropped.

`max-input-bytes` is a different kind of ceiling: it bounds the UTF-8
byte count handed to the native parser, checked before parsing starts
rather than during conversion. See [options.md](options.md#resource-limits)
for its default and how all three fit together, and
[errors.md](errors.md) for the complete condition hierarchy
`&cmark-resource-limit` belongs to.
