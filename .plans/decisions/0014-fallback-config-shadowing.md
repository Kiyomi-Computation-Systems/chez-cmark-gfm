# ADR-0014: Ship a checked-in fallback config, shadowed by the generated one

- **Status:** Accepted
- **Date:** 2026-08-18
- **Scope:** chez-cmark-gfm 1.0
- **Related:** [Stage 6 design](../2026-08-18-stage-6-packaging-design.md) · ADR-0001, ADR-0002

## Context

`make build` generates `src/cmark/gfm/private/config.sls`, holding the shim's absolute
path, the cmark shared-object paths, and the supported version range. It is gitignored
and carries a "do not commit" banner, because every value in it is machine-specific.

A tree that has not been built therefore fails at import with:

```text
Exception: library (cmark gfm private config) not found
```

which names no cause and no remedy, and is not a condition a caller can `guard`. It is
also what any future `akku install` would produce, since Akku distributes Scheme source
and cannot run a C compiler.

## Decision

Check in a second `(cmark gfm private config)` under `fallback/`, and put `src` ahead of
`fallback` on `CHEZSCHEMELIBDIRS`. Chez resolves a library from the first entry that has
it, so the generated file shadows the fallback whenever a build has happened.

The fallback's `shim-path` is `#f` — not a string. No build can produce a non-string
there, so `resolve-shim-path` distinguishes "never built" from "built, but the shim has
since gone missing" without either case guessing. `&cmark-shim-unavailable` gains a
`reason` field, and the fallback's case is `'not-built`.

Two alternatives were rejected:

- **Commit `config.sls` and let `make build` overwrite it.** Zero mechanism, and
  `CHEZSCHEMELIBDIRS=src` would stay as documented. But every build then leaves a
  modified tracked file holding a machine-specific absolute path, and `make clean`
  becomes `git checkout`. This repo has already lost a submodule pin to that class of
  accident, which is why `check-pins` exists; a second one is not worth the saved
  directory.
- **Read the configuration at runtime**, with no generated library at all. This is the
  right eventual shape and is recorded below as the successor, but it rewrites the load
  path Stage 1 built and Valgrind-proved, in the release meant to freeze the API.

## Consequences

- Two files declare `(cmark gfm private config)`, and nothing else would notice them
  diverging. `make check-config` compares library name, export set, and version range,
  and runs in CI right after `make build`.
- The documented library path gains an entry: `CHEZSCHEMELIBDIRS=src:fallback`.
- Reversing those two entries breaks every native suite against a good build.
  `tests/test-fallback-config.sps` covers the documented order only — that the
  fallback engages when the entry ahead of it has no config, and that a built
  `src` shadows it. It does not exercise the reversed order failing against a
  good build; that property rests on the other suites breaking collaterally.
- The fallback names no cmark libraries, so `CHEZ_CMARK_GFM_SHIM` in an unbuilt tree
  works on macOS and fails on Linux, whose loader does not put a dlopen'd library's
  dependencies in the global symbol namespace. Documented in the README, not fixed.
- Akku installation becomes *diagnosable* rather than supported. 1.0 claims clone plus
  `make build` and nothing more.

## Successor

Making an Akku install actually work means configuration read at runtime rather than
generated into the source tree: shim path and cmark library paths from the environment
or a config file, resolved and validated at load time. That is a second config
mechanism with its own security surface — it loads shared objects named by the
environment — and it deserves its own ADR and its own stage rather than a bolt-on here.
