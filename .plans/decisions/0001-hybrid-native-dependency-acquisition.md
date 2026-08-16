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

Linking differs by path: the system path links dynamically, as consumers expect; the
vendored path links cmark **statically** into the shim.

## Consequences

- Two build paths to maintain and test.
- The vendored path produces one self-contained artifact with no runtime resolution
  of `libcmark-gfm`, which is also the cleanest answer to the dynamic-loader concern
  in plan §10.7.
- CI pins `0.29.0.gfm.13` so differential tests are meaningful.
- Static versus dynamic linking behavior must be documented, per plan §14.
