# AGENTS.md

## Project guidelines

* A Chez Scheme library binding the cmark-gfm C library through the FFI;
  handle C *safely*. Portable across darwin, linux and windows, amd64 and arm64.
* Functional core / imperative shell; 12 Factor Apps; TDD.
* Plans live in `/.plans`, decision records in `/.plans/decisions`. Add
  `CHANGELOG.md` entries for each release.
* **On a Guix host, run every build and test command through
  `scripts/guix-env`**, e.g. `scripts/guix-env make test`; batch with
  `scripts/guix-env sh -c 'make build && make test'`, since each call takes a
  few seconds to start. A bare `make` fails for want of `chez`; a bare
  `scripts/guix-env` with no terminal exits at once. Edit, commit and push on
  the host: the container has no git identity, agents or tokens (ADR-0019).
* **Closing Ritual:** squash merge PR, catch local `main` up, clean up
  branches, reflect on the session — all four, without asking which. A
  squash-merged branch needs `git branch -D`; diff it against `main` first to
  confirm nothing unique is dropped. The reflection is a retrospective, not a
  summary of what was done.

## Tests must be seen to fail

A test that passes whether the code is right or wrong is worse than no test.
Every decision in a module gets a mutation that breaks it, and the owning
specification must notice. **A test is not finished when it passes. It is
finished when you have watched it fail.** For every new assertion:

1. Copy the code under test to a scratch location outside the repo, break the
   specific decision the assertion claims to guard, run the suite, and confirm
   that assertion fails *by name*. Revert and confirm it passes. State the
   evidence when you report.
2. The failure must come *through the asserted property*, not from a syntax or
   import error or a side effect of the edit. Narrow the mutation until the
   failure is the one you predicted.
3. If no mutation can break it, the assertion is empty: rewrite it, or record
   in the mutation log that the property is uncovered and why. Never leave it
   silently.
4. **Expect a value only success can produce.** `test-assert` is where empty
   tests hide, since almost everything is truthy. `#f` is worse: a missing key,
   a defaulting accessor and a swallowed exception all return it. Seed an
   output variable before asserting it is empty. Prefer a sentinel.

**Prefer a check to a comment.** An invariant you are about to write as a
comment (keep these equal, run this first, never call X here) belongs in a make
target, a test or an assertion. Stated rules here have been broken in the very
commit that introduced them; see `make check-pins`.

## Traps this repo has already hit

Each shipped a green test or a working-looking build that was wrong. The full
incident behind each is in `.plans/traps.md`; read it before working in that
area.

**Tests**

* `guard` returns the body's value when nothing raises, and `0` is truthy.
  Assert on *what was raised* against an expected value, with a distinct
  sentinel for the no-raise case.
* Every `tests/test-*.sps` must end with its own `(exit …)`: SRFI-64 sets no
  exit status. Anything after that line never runs.
* SRFI-64 turns an exception in the *actual* expression into `#f`. Never
  expect `#f` from something that can raise: `'agree (or (compare …) 'agree)`.
* Chez evaluates arguments right-to-left in compiled library code,
  left-to-right when interpreted. No assertion may depend on argument order.
* An assertion passes whenever *another* rule can produce its expected value.
  Assert the whole rendering, not a substring; give a fixture a neighbour that
  cannot produce the same bytes by another route; build a functional-update
  test's base from non-default values.
* Mutate where the data actually flows, not where the name says it flows. Dump
  the real tree before choosing the mutation site or the assertion's name.
* A conformance test that transforms its input tests the transformation.

**Chez, FFI and cmark**

* `foreign-procedure` resolves its entry point when evaluated, so every binding
  must follow `load-shared-object` in `native.sls`. Mistakes fail at *import*.
* A library body runs only when one of its bindings is *referenced*. A test of
  load-time behaviour must call into the library, as
  `tests/load-failed-probe.sps` calls `markdown->html`.
* Read cmark's semantics from `vendor/cmark-gfm/`, never from recall
  (ADR-0005; `cmark_parser_attach_syntax_extension` always returns 1).
* The `0.29.0.gfm.x` range is a *symbol* constraint: distributions backport
  entry points without changing `cmark_version()`. Before adding a binding or
  widening the range, check the symbol across every tag. `native.sls` probes
  it inside a `guard` (reason `missing-entry-point`).
* An oracle mirroring cmark encodes one version's behaviour. Check which tags
  have it (`git tag --contains` in the submodule) and ask the loaded library;
  `cmark-caps-indent?` in `test-ast-differential.sps` is the pattern.
* Both SXML serializers here (`wak-sxml-tools`, `wak-htmlprag`) mark
  attributes `^`, not `@`, and mis-render `@` silently (ADR-0013).

**Checks and environment**

* Deleting a subsystem disarms the checks built around it, and they stay
  green. On any deletion, ask of every surviving check "what would make this
  fail now?"; "nothing" is a defect. Prove it by breaking the guarded thing. A
  passing CI job shows a check *ran*, not that it works.
* Point `CHEZ` at the real binary: a symlink breaks boot-file lookup, and a
  wrapper script hides Chez from Valgrind. `make check-guix` guards this.
* A memory tool checks only the process it is handed. macOS drops
  `DYLD_INSERT_LIBRARIES` at any SIP-protected binary (`/bin/sh`,
  `/usr/bin/env`), and ASan deletes it from the environment of whatever
  process it loads into, so a wrapper's child never gets it. The ASan arm's
  `sh -c` never loaded ASan from v0.1.0 to v2.0.0. Set the preload on the
  `chez` command itself, and keep wrappers outside Valgrind. Run
  `make check-memory-gate` whenever you touch `test-memory`.
* `guix shell --pure` does not stop a login shell from rebuilding `PATH`;
  `scripts/guix-env` uses `--container`, guarded by `make check-guix`. Do not
  assume you know how a tool builds its shell.
* No live site, kept for whoever returns there: C struct-tag prototype scope
  (C99 6.2.1p7), and Guix container mount-point modes that ssh and gpg reject.
