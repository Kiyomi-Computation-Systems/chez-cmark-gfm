---
name: Feature request
about: Propose an addition to the binding
labels: enhancement
---

**The problem**

What can't you do today?

**Proposed API surface**

Which module — `(cmark gfm)`, `(cmark gfm sxml)`, a new one — and what
would the exports look like?

**Does cmark-gfm already expose this?**

If it wraps an existing `cmark_*` entry point, name it. Note that the
supported range is `0.29.0.gfm.x`, and that a distribution can backport a
symbol while still reporting an older version — so a new binding needs its
availability checked across the range, not just on your machine. See
`AGENTS.md`.

**If this is an SXML change**

`(cmark gfm sxml)` is pure and carries HTML vocabulary only (ADR-0011).
Proposals that need a non-HTML node, or that would make the adapter reach
native code, need a design conversation first.
