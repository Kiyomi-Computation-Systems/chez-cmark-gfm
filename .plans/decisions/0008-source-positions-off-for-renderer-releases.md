# ADR-0008: `source-positions?` defaults off in renderer-only releases

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.1
- **Related:** [Stage 2 design](../2026-08-16-stage-2-renderers-design.md) §3.1, project plan §6.2

## Context

Project plan §6.2 recommends `source-positions?: #t` as a default. That
recommendation was written with the Stage 3 Scheme AST in mind, where source
positions are useful diagnostic metadata attached to nodes.

Release 0.1 has no AST. The flag's only observable effect is markup:
`CMARK_OPT_SOURCEPOS` makes the HTML renderer emit a `data-sourcepos`
attribute on every element (`vendor/cmark-gfm/src/html.c:155` onward), and
adds `sourcepos` attributes to XML output. Verified:

    $ printf '# hi\n\npara\n' | cmark-gfm --sourcepos
    <h1 data-sourcepos="1:1-1:4">hi</h1>
    <p data-sourcepos="3:1-3:4">para</p>

So the plan's recommended default would make `markdown->html` — the headline
procedure of the release — emit attributes most callers do not want.

## Decision

Default `source-positions?` to `#f` for 0.1. Callers who want positions set
`'source-positions? #t` explicitly.

**This is scoped to renderer-only releases, and is not a rejection of source
positions.** We want them for the AST: `markdown->ast` in Stage 3 is exactly
the consumer plan §6.2 had in mind, and a Scheme AST without positions is
worth less than one with them.

## Consequences

- `markdown->html` output at the defaults is clean markup.
- Stage 3 must revisit this rather than inherit it. The likely resolution is
  per-entry-point defaults — positions on for `markdown->ast`, off for the
  renderers — since one global default cannot serve both well.
- If Stage 3 instead changes the shared default to `#t`, that is a
  behavioural change for existing 0.1 callers and needs a CHANGELOG entry and
  a minor version bump.
- Regression: `tests/test-render.sps` asserts both that the default emits no
  `data-sourcepos` and that setting the option explicitly does emit it, so
  neither direction can drift silently.
