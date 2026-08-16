# ADR-0007: Ship incrementally from 0.1 rather than a single v1.0

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md)

## Context

The project plan defines milestones M0–M6 and its §16 acceptance criteria treat all of
them as version 1. That implies a long stretch with no releasable artifact, and memory
correctness, AST copying, and SXML policy all in flight simultaneously.

The relevant observation: `markdown->html` **alone** already exercises every native
ownership rule — parser, root, extension list, and renderer buffer — at the smallest
possible Scheme surface area.

## Decision

| Release | Milestones | Contains |
|---|---|---|
| 0.1 | M0–M2 | Parse and render, safe defaults |
| 0.2 | M3–M4 | Scheme AST, security hardening |
| 0.3 | M5 | SXML adapter |
| 1.0 | M6 | Packaging, docs, release |

## Consequences

- The hardest memory problem is front-loaded into the first deliverable, so AST
  copying is built on a foundation already proven under Valgrind rather than
  concurrently with it.
- More release cycles, each with its own version bump and CHANGELOG entry.
- Each release is independently reviewable, keeping the surface small enough to audit.
- Plan §16's acceptance criteria become the bar for **1.0**, not for first release.
