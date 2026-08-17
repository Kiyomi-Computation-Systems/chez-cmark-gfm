# ADR-0009: Source-position defaults belong to the entry point, not the record

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.2
- **Related:** [ADR-0008](0008-source-positions-off-for-renderer-releases.md), [Stage 3 design](../2026-08-17-stage-3-ast-design.md) §4

## Context

ADR-0008 defaulted `source-positions?` to `#f` for release 0.1 and required Stage 3
to revisit rather than inherit that choice, predicting the resolution would be
"per-entry-point defaults — positions on for `markdown->ast`, off for the renderers".

ADR-0008 also concluded that in a renderer-only release the flag's only observable
effect is markup. That premise is too weak. `CMARK_OPT_SOURCEPOS` also changes the
positions cmark *records*:

    /* vendor/cmark-gfm/src/inlines.c:292-296 */
    static void adjust_subj_node_newlines(subject *subj, cmark_node *node,
                                          int matchlen, int extra, int options) {
      if (!(options & CMARK_OPT_SOURCEPOS)) {
        return;
      }

Positions are written onto every node unconditionally during parsing, but this
correction — which fixes `end_line`/`end_column` for a span crossing a newline and
advances `subj->line` and `subj->column_offset` for everything parsed afterwards — is
skipped when the flag is off. Its callers are multi-line code spans
(`src/inlines.c:407`) and multi-line raw inline HTML (`:999`, `:1009`).

So positions parsed without the flag are present but wrong, and wrong in a way that
propagates to later inlines in the same block.

## Decision

`markdown->ast` selects its default by **arity**:

```scheme
(markdown->ast markdown)          ; (default-ast-options): source-positions? #t
(markdown->ast markdown options)  ; the caller's record, verbatim
```

`(default-ast-options)` is `(cmark-options-with (make-cmark-options)
'source-positions? #t)` — ordinary data, one field different.

The flag governs the parse bits and the attachment together. When it is off,
`markdown->ast` parses without `SOURCEPOS` **and** every `markdown-node-source` is
`#f`, so an unreliable position can never reach a node.

Rejected alternatives:

- **Flip the shared default to `#t`.** Makes `markdown->html` emit `data-sourcepos`
  on every element at the defaults, which is the behaviour ADR-0008 was written to
  avoid, and is a breaking change for 0.1 callers.
- **A tri-state `'unset` sentinel** in the options record, so a per-entry-point
  default could distinguish "defaulted `#f`" from "explicitly `#f`". Puts a third
  value into a field documented as boolean; every validation path would carry it.
- **Always attach positions on the AST path**, ignoring the option. Never-wrong
  positions and no tri-state, but a caller's explicit `#f` would be silently
  disregarded.

## Consequences

- No 0.1 behaviour changes. ADR-0008's decision stands for the renderers.
- The AST at its own defaults carries positions, which is what makes it worth more
  than one without them.
- `xml.c:48`'s `start_line != 0` guard is mirrored in the converter, so a node cmark
  has no position for reports `#f` rather than `0:0-0:0`. That branch is ordinary,
  not defensive: `softbreak` and `linebreak` are built by `make_simple` in
  `src/inlines.c`, which never patches their position fields, so cmark emits them
  with no `sourcepos` at all and any document containing a line break exercises it.
- Two assertions hold the arity in place: the one-argument form must attach
  positions, and the two-argument form must honour an explicit `#f`. Neither can
  drift silently.
