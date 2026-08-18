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

The corpus differential runs its full sweep **once per marker**. That does not
put the marker itself under the oracle, and an earlier version of this ADR said
it did. `tests/sxml-html-serializer.sls`'s attribute predicate accepts `^` and
`@` alike, so the marker is normalised away before any byte is compared and the
two sweeps agree by construction, whatever the adapter emitted. What the second
sweep does prove is narrower and still worth having: that the conversion
completes across all 744 documents under `at`.

The marker's real coverage is the three assertions in `tests/test-sxml.sps` —
`caret-tree`, `at-tree`, and the `(string->symbol "@")` equality. **They are not
redundant with the corpus.** They are the only thing in the repository that
fails when the marker is wrong; see the first Consequence below.

## Consequences

- Default output renders through `wak-sxml-tools` and `wak-htmlprag` with no
  caller-side transformation. That is what the library exists to produce.
- **This option is the one property ADR-0012's oracle cannot reach**, and it is
  the price of letting one test serializer judge both dialects. Measured, not
  reasoned: with `marker` in `src/cmark/gfm/sxml.sls` hardwired to `'^` so it
  ignores the option entirely, `tests/test-sxml-differential.sps` passes 53/53
  and exits 0 — both corpus sweeps, the ten-configuration option matrix, and
  both CLI legs — and `tests/test-sxml-portability.sps` passes 5/5. Only
  `tests/test-sxml.sps` notices, failing two assertions by name.
  `.plans/stage-5-mutation-log.md` records the probe. Design spec §10 lists it
  alongside `raw-html: escape` as a deliberate gap.
- The twin sweep is kept for the narrower guarantee it does give — 744
  documents converting under `at` without raising — and it is cheap: a full
  744-example sweep measures at 17–20 ms, plus four extra CLI subprocesses,
  against a suite that runs in about 0.36 s end to end. Cheap enough to keep,
  as long as nobody reads it as byte coverage of the marker.
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
