# ADR-0010: Verify the AST against cmark's own XML serialization

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.2
- **Related:** [Stage 3 design](../2026-08-17-stage-3-ast-design.md) §8, [Stage 2 design](../2026-08-16-stage-2-renderers-design.md) §7

## Context

The AST copy touches 24 node types and roughly a dozen properties. Hand-written
expected trees are readable but cover only what someone had the patience to type
out, and the table, list, and position permutations are exactly where that runs
out.

`cmark_render_xml` walks the same tree `markdown->ast` copies, and emits the type
string, source positions, and most properties of every node.

## Decision

A test-only serializer renders our Scheme AST into cmark's XML dialect, and the
result is compared byte-for-byte against cmark's output for the same parse — first
in-process against `cmark_render_xml`, then against the pinned CLI.

The serializer is written against `vendor/cmark-gfm/src/xml.c` and judged against
cmark's real bytes. That is the property that matters: it **cannot be tuned** to
accommodate a converter bug. "Adjust the expectation until it passes" is not
available, because the expectation is produced by cmark.

## Consequences

- A wrong heading level, a dropped or reordered child, a mislabelled table header, a
  missing fence info, or a bad source position all surface as a byte difference.
- Both legs are needed. The in-process leg would still pass if our AST and our
  reading of `xml.c` were wrong in the same way; the CLI is an independent witness.
- Three properties are invisible to the oracle and need direct assertions: `item`
  index, table `columns`, and alignment on **body** cells — `extensions/table.c:661`
  emits `align=` only for cells whose parent row is a header.
- The serializer must reproduce cmark's formatting exactly, including `MAX_INDENT`
  (`src/xml.c:14`), which caps indentation at 40 spaces. A serializer without the cap
  agrees on every shallow fixture and diverges only past 20 levels of nesting, so
  that case is asserted specifically.
- Each comparison leg carries a guard proving the detector can report a difference at
  all, for the same reason Stage 2 §7.3's discrimination guard exists: a parity
  assertion whose comparator always returns "equal" passes against anything.
