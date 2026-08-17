# ADR-0011: SXML carries HTML vocabulary only, with no metadata channel

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.3
- **Related:** [Stage 5 design](../2026-08-17-stage-5-sxml-design.md) §4.3, §5.1 · [project plan](../chez-cmark-gfm-sxml-project-plan.md) §7.2, §10.4, §11 · ADR-0010, ADR-0012

## Context

The AST holds more than HTML can express: list `delimiter`, `item` index, fence
info past the first token, image child structure, and source positions on every
node. Plan §11's mapping is HTML tags, so all of that is dropped on conversion.

Three ways to keep it were considered: SXML annotations — the nested `(@ …)` the
SXML 3.0 grammar permits as the last member of an attribute list; `data-*`
attributes; and cmark's own `data-sourcepos` convention for positions
specifically.

Two facts constrained the choice. cmark emits `data-sourcepos` on **block nodes
only** — no inline case in `src/html.c` calls `cmark_html_render_sourcepos`, and
`extensions/strikethrough.c:132` emits a bare `<del>` — so `data-*` cannot carry
the inline positions the AST has without abandoning byte-equality. And no
serializer was known to honour SXML annotations; one that does not would emit
`@="…"` into HTML we do not control.

The related question is plan §10.4's `'trusted` raw-HTML mode. SXML has no
portable raw-markup node: the 3.0 grammar provides `*TOP*`, `*PI*`, `*COMMENT*`,
`*ENTITY*`, and `@`, none of which mean "emit these bytes verbatim".

## Decision

The SXML tree carries HTML vocabulary and nothing else. No annotations, no
`data-*` metadata, no source positions, and no trusted raw-HTML mode.

`markdown->ast` remains the interface for everything the mapping drops.

## Consequences

- **The oracle becomes total.** Every piece of information in an SXML tree is
  information the HTML shows, so ADR-0012's byte comparison has no blind spot and
  needs no direct assertions alongside it. Stage 3's oracle needed three.
- There is no untested side channel, because there is no side channel.
- A caller wanting positions, list delimiters, or item indices uses the AST. The
  two entry points have distinct jobs rather than overlapping ones.
- `'trusted` is not merely deferred but unavailable: implementing it would mean
  inventing a node type no serializer honours, which is the same trap the
  annotations option carried.
- `data-sourcepos` remains a clean 0.4 addition if anyone wants it. It is an
  output-fidelity feature — mirroring `cmark --sourcepos` on block elements — not
  a metadata channel, and adding it later breaks nothing here.
- Source positions were verified against cmark's XML in Stage 3, which emits them
  on every node including inlines. That coverage is not lost by this decision; it
  simply lives in the AST, where it was already paid for.
