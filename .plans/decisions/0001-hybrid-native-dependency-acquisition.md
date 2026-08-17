# ADR-0001: Obtain cmark-gfm via pkg-config with a pinned vendored fallback

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md)

## Context

`cmark-gfm` is not present on the development machine; Homebrew provides
`0.29.0.gfm.13`. The library must be installable by consumers without undue burden,
while CI needs an exactly known native version — differential testing against the
`cmark-gfm` CLI is meaningless if the CLI and the linked library can drift apart.

Three options were considered: system package only via `pkg-config`; a vendored
submodule always built from source; or a hybrid.

System-only keeps the package light but leaves version drift between developer
machines and CI likely, and `cmark-gfm` is absent from many distribution
repositories. Vendored-only gives total reproducibility but forces every consumer to
compile cmark and adds upstream license bookkeeping.

## Decision

Normal builds discover a system `cmark-gfm` through `pkg-config`. A pinned git
submodule at `vendor/cmark-gfm` provides a fallback, used automatically when
`pkg-config` finds nothing, and invoked explicitly by `make vendor`.

Both paths link **dynamically**. The vendored copy is built as shared libraries and
the shim links against them with an explicit `-Wl,-rpath` to each.

### Amended 2026-08-16, during Stage 1

This ADR originally specified **static** linking on the vendored path, to produce one
self-contained artifact. That is not implementable alongside
[ADR-0002](0002-traverse-ast-in-scheme.md).

cmark-gfm builds its static archives under `CMAKE_C_VISIBILITY_PRESET hidden` with
`CMARK_GFM_STATIC_DEFINE`, hiding every cmark symbol in whatever links them. ADR-0002
puts traversal in Scheme, so Scheme resolves cmark's entry points directly at runtime
via `foreign-procedure` — and a statically-linked shim exports none of them. Verified
empirically: linked that way, the shim exports its own 13 `chez_cmark_*` functions and
zero cmark functions, and the suite dies with `no entry for "cmark_parser_new"`.
`-Wl,-force_load` pulls the objects in but they stay hidden.

(The originally-specified archive names were also MSVC-only, so the link failed before
reaching the visibility problem.)

Of the two decisions, ADR-0002 is load-bearing — it is the project's central
memory-safety rationale — so the linking strategy gave way rather than the
architecture.

## Consequences

- Two build paths to maintain and test, now structurally identical: both resolve
  cmark symbols dynamically, so there is one Scheme code path rather than two.
- The vendored path is no longer a single self-contained artifact. The
  dynamic-loader concern in plan §10.7 is still met, because the rpath is an explicit
  absolute path recorded at build time rather than a system-path search.
- The vendored build must be present at runtime, not merely at link time.
- CI pins `0.29.0.gfm.13` so differential tests are meaningful.
- Static versus dynamic linking behavior must be documented, per plan §14.
