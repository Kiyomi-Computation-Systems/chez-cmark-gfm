# ADR-0013: Emit `^` as the attribute marker by default, with `@` available

- **Status:** Accepted
- **Date:** 2026-08-18
- **Scope:** chez-cmark-gfm 0.3
- **Related:** [Stage 5 design](../2026-08-17-stage-5-sxml-design.md) §3.1, §4.1, §6.6 · ADR-0011, ADR-0012

## Context

Kiselyov's SXML specification marks an attribute list with `@`:
`(a (@ (href "/x")) "text")`. Stage 5 was designed and built against that.

Task 11 found that the two SXML serializers reachable through Akku both use `^`
instead, and neither recognises `@` at all:

| Library | Marker | Evidence |
|---|---|---|
| `wak-sxml-tools` | `^` (aux `^^`) | `sxml-tools/upstream/sxml-tools.scm:44-48`, `upstream/serializer.scm:215,246` |
| `wak-htmlprag` | `^` | `htmlprag/htmlprag.scm:334,1351,1485` |

`wak-sxml-tools` vendors Lizorkin's upstream verbatim, so this is not an
artefact of the R6RS port — `^`/`^^` is that lineage's own convention.
Neither library contains a `\x40;` escape anywhere, so neither can be handed a
`@`-marked tree at all. A conforming-looking tree was silently turned into
bogus child elements rather than rejected.

Two audiences exist, and both are real:

- **`^`** — anyone serializing on Chez with either available library. Without
  it, our output cannot be rendered by any tool the platform ships.
- **`@`** — anyone hand-writing or pattern-matching SXML in ordinary Chez code,
  or moving trees between Schemes. Chez rejects a bare `@` only under `#!r6rs`;
  a plain Chez script reads `(@ (href "x"))` without complaint.

## Decision

`sxml-options` carries `attribute-marker`, taking `caret` or `at`, defaulting
to **`caret`**.

The values are named rather than being the markers themselves, because `@`
cannot be written as a symbol literal in the `#!r6rs` source that would have to
name it.

The corpus differential runs its full sweep **once per marker**, so both are
covered by all 744 examples rather than one being covered by the oracle and the
other by a handful of assertions.

## Consequences

- Default output renders through `wak-sxml-tools` and `wak-htmlprag` with no
  caller-side transformation. That is what the library exists to produce.
- ADR-0012's oracle stays total. The twin sweep costs about ten lines, because
  the test serializer's attribute predicate accepts either marker and the sweep
  already runs in seconds.
- Task 11's portability suite tests **the tree we emit** rather than a rewritten
  one, which is the only construction under which design spec §6.6's
  conformance claim means anything.
- The default is deliberately not the specification's marker. The README says
  so plainly rather than letting a reader assume canonical SXML.
- A caller wanting the specification's spelling passes `'attribute-marker 'at`.
  This was weighed against shipping `caret` alone and documenting an
  eight-line caller-side rewrite; the option won because both audiences exist
  today and the marker is baked into every tree, so the choice belongs where
  the tree is built.
- No other SXML construct is affected. `*TOP*` and `*COMMENT*` are spelled the
  same in both dialects, and this library emits no aux lists, so `^^` versus
  `@@` never arises.
