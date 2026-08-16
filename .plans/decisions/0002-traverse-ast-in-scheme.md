# ADR-0002: Traverse the AST in Scheme behind a thin C shim

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md), [ADR-0003](0003-linux-primary-memory-verification.md)

## Context

The binding must copy a native cmark AST into Scheme-owned records. The traversal
can live in C or in Scheme, and the choice determines how much memory-unsafe code
exists and how the "no native pointer escapes" invariant is enforced.

Three options were considered:

1. **Thin shim, traverse in Scheme.** Scheme drives `first-child`/`next` and calls
   accessors directly.
2. **Node-snapshot shim.** Scheme drives the walk, but one C call per node copies
   every field into caller-owned memory.
3. **Traverse entirely in C.** The shim walks the tree and returns one serialized
   blob that Scheme decodes after the native tree is freed.

Options 2 and 3 make the invariant *structural* rather than disciplinary — with (3),
exactly one pointer crosses the boundary. But they buy that guarantee by adding
buffer arithmetic in C, itself a classic defect source.

Performance does not distinguish them: a 2,000-node document at roughly 8 accessors
per node is about 16,000 FFI calls, well under a millisecond.

## Decision

Option 1. The C shim performs no tree traversal and contains no parsing or rendering
logic. It does only what C must: version reporting, one-time extension registration,
extension lookup normalization, option-bit construction, renderer buffer release, and
debug allocation counters. Target size is roughly 150 lines.

## Consequences

- The most effective available memory-safety measure is applied: less C.
- Node-type coverage evolves without recompiling C.
- **The lifecycle logic that memory safety depends on now lives in Scheme.** A
  standalone C test harness cannot exercise it, so memory verification must run the
  Chez process itself under a memory tool. See
  [ADR-0003](0003-linux-primary-memory-verification.md).
- Opaque node pointers live in Scheme variables during the walk, so the invariant is
  enforced by scoping helpers and checked accessors rather than by structure. See
  [ADR-0006](0006-liveness-flag-with-dynamic-wind.md).
