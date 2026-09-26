# ADR-0018: A pinned Guix container as the development environment

- **Status:** Accepted
- **Date:** 2026-09-26
- **Scope:** development tooling. No library change
- **Related:** [design spec](../2026-09-26-guix-dev-env-design.md) ·
  [mutation log](../guix-env-mutation-log.md) ·
  [ADR-0016](0016-paired-versioned-library-discovery.md) (the discovery this leaves alone) ·
  [ADR-0003](0003-linux-primary-memory-verification.md) (Valgrind runs inside)

## Context

The maintainer develops on Guix and runs Claude Code as a primary
contributor. The goal was a development environment that is the same for
every contributor and every session, and that can host an agent that
commits, signs, pushes and opens PRs. Five facts constrained it. The first
two were known going in; the other three were found building it.

- Discovery searches `/usr/local/lib`, `/usr/lib/<triple>`, `/usr/lib` and
  `/usr/lib64`, never a Guix profile. Plain `guix shell` therefore fails
  `make build` with `not-found` unless `CHEZ_CMARK_GFM_LIBS` is set.
- Guix names the Chez binary `scheme`. A `chez` symlink aborts, because Chez
  derives its boot-file name from the name it was invoked by.
- A `chez` **wrapper script** passes `make test` but hides Chez from
  Valgrind. Valgrind traces the shell, the shell execs Chez, and `make
  test-memory` passed with 21 suites and no `ERROR SUMMARY`: nothing was
  instrumented.
- Inside `guix shell --pure`, a login shell re-sources the user's rc files.
  On the maintainer's machine these put `~/.guix-home/profile/bin` ahead of
  the environment, so `scheme` and `git` resolved to the host's copies while
  everything still passed.
- Guix creates the container's `HOME` and mount-point directories under the
  host umask (`1777`, `0775`). ssh then refuses its config and gpg refuses
  its socket directory. The maintainer's `~/.ssh/config` also names a
  private key and a 1Password agent socket that must not or cannot enter,
  and `gh` keeps its token in the desktop keyring, over D-Bus.

## Decision

- **Pin with `guix time-machine -C channels.scm`.** Plain `guix shell`
  resolves the manifest against each developer's latest `guix pull`.
- **Provision through the manifest's search paths**, not a wrapper, not a
  launcher-exported variable, and not a library change. One package that
  installs nothing, `chez-cmark-gfm-dev-env`, declares two:
  - `CHEZ=<profile>/bin/scheme`, which the Makefile's `CHEZ ?= chez` honours.
  - `CHEZ_CMARK_GFM_LIBS`, whose pattern matches only the versioned
    libraries, so the value is exactly the two-entry override.

  Under `--emulate-fhs`, discovery would also find the pair at `/usr/lib`,
  but only the override names the store path, and only the override works
  without FHS emulation.
- **Run in `--container --network --emulate-fhs`, not `--pure`.** `HOME` is
  empty, so no rc file can clobber `PATH`, and that is decided by files in
  this repository rather than by each contributor's dotfiles. FHS emulation
  is what lets the glibc-linked `claude` binary run.
- **One launcher, `scripts/guix-env`**, serves people (`bash` with no
  arguments), `make check-guix`, and Claude (`claude` mode). What is
  verified is what is run. Every command inside starts through
  `scripts/guix-env-init`, which sets those directories to `0700`.
- **Credentials are shared deliberately, and listed:**
  - git config files, including `include`/`includeIf` targets;
  - the gpg-agent socket and the public keyring;
  - the SSH agent socket and `known_hosts`;
  - `~/.config/gh`, plus `GH_TOKEN` taken from `gh auth token` on the host.
    The token is passed by environment name, never on a command line. This
    was the maintainer's choice over sharing the D-Bus session or dropping
    `gh`.
  - In `claude` mode only: `~/.claude` and `~/.claude.json`.

  Private key files and `~/.ssh/config` are never exposed.
- **Verification is local.** `make check-guix` asserts four things:
  1. The library came from `/gnu/store`.
  2. A login shell resolves the environment's tools.
  3. `$CHEZ` is inside the environment and instrumentable by Valgrind.
  4. The credential directories are `0700`.

  No CI job runs it.

Rejected:

- **Teach discovery to search `$GUIX_ENVIRONMENT/lib`.** It reopens ADR-0016
  to serve a development convenience.
- **A launcher that exports the variables.** A bare `guix shell -m
  manifest.scm` would then be a broken environment.
- **A `chez` wrapper script.** It hides Chez from Valgrind, which is the
  third fact above.
- **`--pure` plus rc-file guards.** Correct only for contributors whose
  dotfiles carry the guard, which this repository cannot enforce.

## Consequences

- **x86_64-linux only.** Guix builds `chez-scheme` and `cmark-gfm` only for
  `x86_64-linux` and `i686-linux`. macOS and arm64 development is unchanged.
- **Nothing automated notices rot.** A broken pin or manifest surfaces the
  next time someone runs `make check-guix`. This was accepted to keep CI
  spend where #18 left it.
- **The container confines the filesystem, not GitHub.** Anything running
  inside holds the maintainer's GitHub access, through the agents and
  `GH_TOKEN`, and can read `GH_TOKEN` from its environment.
- **`~/.ssh/config` settings do not apply inside.** Host aliases and custom
  ports are unavailable. GitHub over SSH works through the agent.
- **There is no `chez` command inside.** Type `scheme`. `make` uses `$CHEZ`.
- **The `--container` half of the PATH assertion is host-dependent.** On a
  host whose rc files do not prepend `PATH`, dropping `--container` is
  caught only by the launcher's own flag checks (mutation M4).
- **A pin bump can bring a `cmark-gfm` outside the supported range.** The
  existing post-load version check in `native.sls` fails `make build`, which
  fails `check-guix`.
