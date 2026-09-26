# Contributing to chez-cmark-gfm

Thanks for wanting to improve this. Two kinds of contribution get two
levels of ceremony: a **drive-by fix** (typo, doc fix, small bug with a
test) needs only the gates below; **feature-sized work** should start as
an issue or design conversation before code — this binding is safe by
default and keeps its SXML adapter pure (ADR-0011), and a proposal that
would change either needs a design decision first.

## Setup

You need Chez Scheme 9.5.8+ (binary `chez` on macOS, `chezscheme` on
Debian/Ubuntu) and a system `cmark-gfm` in the `0.29.0.gfm.x` range:

```sh
git clone https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm
cd chez-cmark-gfm
make test                     # macOS
make test CHEZ=chezscheme     # Debian/Ubuntu
```

`--recursive` is never necessary: `make test` pulls in `build`, `deps`,
and `check-pins` as prerequisites, and `deps` checks out the `vendor/`
submodules the test suites need — nothing under `vendor/` is a runtime
dependency of `(cmark gfm)` itself. `make help` lists every target;
[docs/building.md](docs/building.md) has the full build story, and
[docs/installing.md](docs/installing.md#prerequisites) has the
`cmark-gfm` prerequisite for every platform, including the RHEL/Fedora/
Alpine source build.

On x86_64 Linux with Guix, `scripts/guix-env` gives you a pinned container
with every prerequisite, and `make test` works in it as written. See
[docs/building.md](docs/building.md#guix-development-environment).

## The gates

A PR must keep these green — they are what CI runs:

- `make test` — every suite passes (`ALL SUITES PASSED`).
- `make check-pins` — the submodule commits and `Akku.lock` agree.
- `make check-purity` — `options.sls`, `ast.sls`, and the SXML adapter
  still import nothing that loads a shared object.
- `make check-help` — every target is documented in `make help`.
- `make check-install` — an installed tree still imports and renders.
- `make examples` — every `examples/*.sps` still produces its expected
  output.
- `make test-memory` — **not on your PR.** Valgrind is 10–50x native, so it
  runs on `main` and on `v*` tags only, and only the Linux Valgrind leg can
  support a leak claim (ADR-0003). Your PR still runs every correctness
  suite under `make test`; what it does not run is the instrumentation. If
  you touch the FFI, `discovery.sls`, or anything that allocates native
  cmark objects, ask for it explicitly rather than finding out post-merge:

  ```bash
  gh workflow run ci.yml --ref your-branch -f run_memory=true
  ```
- **Tests accompany code changes.** A behaviour change without a test that
  fails against the old behaviour will be asked for one.
- Every new suite ends with its own `(exit …)` — SRFI-64 does not set a
  process exit status, and a suite missing that line reports success
  forever.

**CI runs on Linux only.** There is no macOS job — GitHub bills those
runners at ten times the Linux rate, and the job repeated what the author
had just run locally. If your change touches
`src/cmark/gfm/private/discovery.sls`, note that its macOS and Linux
branches search different directories for differently named files, and CI
can only go red for the Linux one. Run the gates above on a Mac yourself
before asking for a review of anything on that path;
`.github/workflows/ci.yml`'s header lists what is no longer checked
automatically.

## Conventions

- [Conventional Commits](https://www.conventionalcommits.org): `feat:`,
  `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- Branch names: `feat/<slug>`, `fix/<slug>`, `docs/<slug>`, etc.
- PRs are squash-merged.

## How this repo is developed

The house style — encouraged for feature work, not demanded of drive-by
fixes: designs are written and accepted before implementation
(`.plans/*-design.md`), architectural decisions get numbered records
(`.plans/decisions/`), and the testing discipline in
[AGENTS.md](AGENTS.md) applies — *a test is not finished when it passes;
it is finished when you have watched it fail*, with the evidence recorded
in a mutation log. Reading one of the existing mutation logs in `.plans/`
is the fastest way to understand what that means in practice.

## Security

Please do not open public issues for suspected vulnerabilities — see
[SECURITY.md](SECURITY.md).
