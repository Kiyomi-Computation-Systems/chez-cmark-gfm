# Building and testing

This page is for building **this library itself** — running its test
suites, checking its own invariants, changing its code. If you only want
to *use* `(cmark gfm)` as a dependency, [installing.md](installing.md) is
the whole story; nothing below is required for that.

Every target that runs Chez does so via `$(CHEZ)`, which defaults to
`chez`. On Debian/Ubuntu, where the binary is `chezscheme`
([installing.md](installing.md#prerequisites)), either export `CHEZ=chezscheme`
for the session or pass it per invocation: `make CHEZ=chezscheme test`.

## Requirements for development

Start from [installing.md](installing.md#prerequisites): Chez Scheme and a
system `cmark-gfm`. Development needs one thing beyond that — the four
submodules under `vendor/`:

| Submodule                | What it's for |
|---------------------------|----------------|
| `vendor/chez-srfi`        | `(srfi :64)`, the assertion library every `tests/test-*.sps` suite is written against |
| `vendor/wak-sxml-tools`   | a third-party SXML serializer; `tests/test-sxml-portability.sps` uses it to prove `markdown->sxml`'s output is SXML a tool that isn't ours also accepts |
| `vendor/wak-common`       | `(wak private include)`, a library `wak-sxml-tools`'s serializer imports but does not vendor itself |
| `vendor/cmark-gfm`        | the 744-example corpus and the header `tests/test-option-bits.sps` parses — not a Scheme dependency at all |

None of these are needed to *use* the library: `(cmark gfm)` itself
imports none of them, which is exactly what `make examples` checks (below).
They exist only so the test suites have something to run against.

A plain `git clone` is enough — `--recursive` is never necessary. `make deps`
runs `git submodule update --init` for all four itself, and it's already a
prerequisite of `make test`, `make test-memory`, and `make check-purity`, so
a fresh clone becomes fully test-ready on the first `make test`, with no
separate setup step.

The differential suites — the ones comparing this binding's output against
real cmark-gfm — need a `cmark-gfm` CLI binary as their oracle. `$(CMARK_CLI)`
defaults to whatever `cmark-gfm` is on `PATH`, the same binary the system
package installs alongside the library
([installing.md](installing.md#prerequisites)). `make deps-info` prints
which one a run would use; point it elsewhere with
`CMARK_CLI=/path/to/cmark-gfm make test`. `make vendor` is a separate,
heavier target that builds `vendor/cmark-gfm` from source with CMake — for
a machine with no packaged CLI to point at
([RHEL, Fedora, and Alpine](installing.md#rhel-fedora-and-alpine)), or to
pin the oracle to the exact commit the corpus itself comes from.

## The targets

```sh
make help
```

is the live list — generated from a `## description` comment on each
target's own line in the `Makefile`. `make check-help` fails if any
`.PHONY` target lacks one, so a real target can't go undocumented and a
description can't go stale next to a renamed target without the build
itself catching it. That check runs one direction only: it does not
confirm a described target is real, so a stray `## `-commented line for a
target that was never added to `.PHONY` — and does not work — would still
show up in `make help` uncaught. That's still why this page doesn't
duplicate the target list: a second one here would only be a copy for
`make help` to drift from, which is why it describes what a target *does*
rather than enumerating what targets *exist*.

One target the house convention expects is deliberately absent: there is
no `make prod`. 2.0 compiles nothing at all (ADR-0015) — `make build` is a
discovery preflight, not a build step, see
[installing.md](installing.md#what-make-build-does) — so there is no
compiled artifact to have a production flavor of.

## Running the suites

```sh
make test
```

runs every `tests/test-*.sps` file present — the set is a `wildcard`, so a
new suite is picked up the moment its file exists, with no Makefile edit.
Each suite is its own Chez process and manages its own SRFI-64 test runner;
every one of them ends with the same line,
`(exit (if (zero? (test-runner-fail-count runner)) 0 1))`, because SRFI-64's
default runner does not otherwise set a process exit code, and without it a
failing suite would still exit `0`. `make test` runs them one at a time,
keeps going after a failure so one broken suite cannot hide the others, and
fails the target overall — printing `SUITE FAILED` in place of
`ALL SUITES PASSED` — if any of them did. `build`, `deps`, and `check-pins`
are prerequisites, so a bare `make test` is always a complete, pinned run.

## make test-memory

Runs the same suites again — all but `tests/test-differential.sps`, which
spawns hundreds of separate `cmark-gfm` subprocesses that no memory tool
here instruments and so add no coverage — under whichever instrumentation
the platform supports:

- **Linux**: Valgrind, `--leak-check=full --show-leak-kinds=definite
  --error-exitcode=9`. A leak is a hard failure.
- **macOS**: an AddressSanitizer preload, with leak detection explicitly
  off (`ASAN_OPTIONS=detect_leaks=0`). LeakSanitizer does not exist on
  macOS/ARM64, so this run catches corruption and use-after-free but
  **supports no leak claim** — that has to come from the Linux row (ADR-0003).
  The target refuses to run uninstrumented rather than skip quietly: if it
  can't find `libclang_rt.asan_osx_dynamic.dylib` under Xcode's clang
  toolchain, it exits with an error naming exactly that instead of reporting
  a false pass.

`tests/test-ast-differential.sps` and `tests/test-sxml-differential.sps`
stay **in**, unlike `test-differential.sps`, even though both also spawn
CLI subprocesses: each has a substantial leg that runs in-process instead —
parsing real documents through `markdown->ast` and `markdown->sxml` — which
allocates and frees native cmark objects inside the very Chez process the
instrumentation is watching. That in-process work is what would be lost by
excluding them, and for `test-sxml-differential.sps` in particular it is
the single largest block of instrumented coverage the memory target gets.

## make check-purity

`(cmark gfm options)` and `(cmark gfm ast)` each state, in their own header
comments, that they import no native library — not even transitively. This
target turns that from a comment into a check (AGENTS.md's own stated
preference): it runs `tests/test-options.sps`, `tests/test-ast.sps`,
`tests/test-sxml.sps`, `tests/test-example-coverage.sps`, and
`tests/test-manifest-deps.sps` with `CHEZ_CMARK_GFM_LIBS` poisoned to a path
that does not exist.

If none of those suites' import chains ever reach
`(cmark gfm private native)`, the poisoned variable is never even read, and
they pass untouched. If any of them *does* reach it, `native.sls`'s library
body raises `&cmark-library-unavailable`, reason `invalid-override`, at
*import* time, before a single assertion in the suite runs, and the target
fails outright. Passing is proof by construction that those five suites'
worth of behavior never touches native code, not merely a claim next to
the code that it doesn't.

## make check-pins

`vendor/chez-srfi`, `vendor/wak-sxml-tools`, and `vendor/wak-common` are
each pinned twice — once as a submodule commit, once by name inside
`Akku.lock` — and nothing enforces that the two agree except this target.
That duplication is real: a `git submodule update --init` resets a
submodule to its recorded commit and can silently undo a manual re-pin that
was never staged, so treating the submodule pin as self-evidently correct
would be trusting the exact mechanism most likely to drift. `make check-pins`
reads both pins for each of the three and fails if any pair disagrees,
printing which package and which two commits.

## make examples

```sh
make examples
```

runs every `examples/*.sps` file and diffs its combined stdout and stderr
against a pinned `examples/expected/NN.out`, matched by the leading number
in the example's own filename — `05-errors.sps` against `expected/05.out`,
not against a file named after the whole slug. A missing expected file,
changed output, or an example that fails to run are each a failure, and
the target keeps going after one so a single stale example cannot hide the
rest.

`CHEZSCHEMELIBDIRS` is set to `src` **only** for this target — no
`build/scheme-libs`, no vendored SRFI or wak libraries. That is deliberate:
an example is meant to show what an actual consumer of the package sees,
and this is the one target that would fail, immediately and by name, the
moment an example accidentally started depending on something this
library does not itself ship. A few other pages under `docs/` lean on that
directly — [usage.md](usage.md), [ast.md](ast.md), and
[errors.md](errors.md) each cite their own `examples/NN-*.sps` file by name
and adapt code from it inline rather than embedding the file by reference.
This target keeps the cited file itself from going stale; it does not
re-check an adapted copy against it, so a page that adapts code says so
directly.

## make check-install

```sh
make check-install
```

installs to a fresh `mktemp -d` prefix — never the real `PREFIX` — by
invoking `make install` itself with that temporary path, then runs a probe
program with `CHEZ_CMARK_GFM_LIBS` explicitly **unset** rather than merely
empty (`getenv` returns `""` for a set-but-empty variable, and an empty
string is truthy in Scheme, so leaving it merely empty would silently take
the override branch and fail with `invalid-override` — a result that looks
like a broken install but is really a broken check). The temp directory is
removed on exit either way.

`CHEZSCHEMELIBDIRS` for that probe is **parsed out of `make install`'s own
output** — the `export CHEZSCHEMELIBDIRS=` line it prints — rather than
spelled out again here. That line is the most-copied thing this project
emits, and a path hardcoded in the check would guard nothing: the printed
line could name the deeper `cmark/` subdirectory, the exact mistake
[installing.md](installing.md#installing-with-make-install) warns readers
about, and the check would still pass. The extraction also asserts the
trailing colon survives. The probe runs from an empty scratch directory, not
the repo root, so the `.` that colon keeps on the search path cannot resolve
`(cmark gfm)` by accident and mask a wrong printed path.

The probe does not just import `(cmark gfm)` — it calls `markdown->html`
and checks the literal rendered string. Chez instantiates an imported
library's body only when one of its bindings is actually referenced, so an
import-only probe would never run `native.sls`'s discovery at all and
would report success against an install that cannot possibly work. Calling
in and checking a real result is what makes a pass mean the copied tree is
not just present, but actually loadable and usable with nothing else on
the library path.

The same temp prefix is then handed to `make uninstall`, which must leave
neither the installed tree behind nor a marker file planted beside it under
the prefix — `uninstall` is `install`'s twin, and an untested one is what
[AGENTS.md](../AGENTS.md) forbids.

## The dev REPL

```sh
make dev
```

starts `$(CHEZ)` with `CHEZSCHEMELIBDIRS` set to `src:tests:build/scheme-libs`
— this library's own sources, the test suites' shared helper libraries, and
the vendored SRFI-64 and wak libraries `make deps` (a prerequisite of `dev`,
run automatically) symlinks into place. `(import (cmark gfm))` and
`(import (srfi :64))` both resolve immediately, with nothing further to set
up, which makes this the fastest way to try something against the library
or poke at a test helper interactively.
