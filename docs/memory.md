# Memory ownership

The contract a caller can depend on: it holds on every call to a
renderer, to `markdown->ast`, or to `markdown->sxml`. Full rationale is
in the project's design spec,
[`.plans/2026-08-16-chez-cmark-gfm-design.md`](../.plans/2026-08-16-chez-cmark-gfm-design.md),
§5.

- `markdown->ast` returns *only Scheme-owned objects*. No native pointer
  is reachable from the result, and the tree stays valid after the
  native document that produced it is freed.
- Every borrowed native string is copied before the document it came
  from is cleaned up.
- A native document is dead outside its own scope; touching one raises
  `&cmark-dead-document`. No public entry point exposes a live document
  — nothing exported returns one, and nothing exported accepts one as
  an argument — so a caller of this library cannot reach that
  condition. It's exported anyway, alongside every other condition
  type, so the hierarchy in [errors.md](errors.md) stays complete and a
  `cmark-error?` guard clause can be exhaustive without a gap.
- Renderer buffers are copied into Scheme strings and freed exactly
  once, on the success path and the failure path alike.
- Parsers, roots, and extension-list containers have one owner each and
  are freed exactly once.

None of this requires anything from a caller. There's no handle to
close, no buffer valid only inside a callback, no "free this when you're
done." Every public entry point in [usage.md](usage.md),
[ast.md](ast.md), and [sxml.md](sxml.md) returns plain, GC-managed
Scheme data with nothing further owed.
