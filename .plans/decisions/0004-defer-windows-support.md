# ADR-0004: Defer Windows support beyond version 1

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md)

## Context

`AGENTS.md` calls for portability across macOS, Linux, and Windows. Plan §2 scopes v1
to "Linux and macOS initially." These conflict and the conflict must be settled before
the build system is written.

Windows as a tier-1 target would make the vendored path primary there (`pkg-config`
is impractical on Windows), require an MSVC build of the shim, and fork the
verification story, since Valgrind does not exist on Windows. A tier-2 MSYS2/mingw
approach is cheaper but produces mingw-linked DLLs that may not load into an
MSVC-built Chez — green CI that misrepresents how Windows users would consume the
library.

## Decision

Version 1 targets Linux and macOS. The C stays strictly portable — no POSIX-only APIs
— and library-name and path resolution sit behind a single abstraction, so Windows is
additive later rather than a redesign.

## Consequences

- Resolves the `AGENTS.md` / plan §2 conflict in favor of the plan.
- v1 effort stays on its actual risk, which is memory correctness rather than platform
  breadth.
- The vendored acquisition path ([ADR-0001](0001-hybrid-native-dependency-acquisition.md)) means adding Windows later is mostly CI
  work.
- The supported-platform matrix must state the Windows position explicitly rather than
  leaving it implied.
