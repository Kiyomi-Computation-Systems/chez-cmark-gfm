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
  - git config files from the global and system scopes, including their
    `include`/`includeIf` targets. The repository's own `.git/config` is
    writable from inside, so it never decides what is mounted, and the
    listing is read NUL-framed so no value can forge a path;
  - the gpg-agent socket and the public keyring;
  - the SSH agent socket and `known_hosts`;
  - `~/.config/gh`, read-only, plus `GH_TOKEN` taken from `gh auth token`
    on the host.
    The token is passed by environment name, never on a command line. This
    was the maintainer's choice over sharing the D-Bus session or dropping
    `gh`.
  - In `claude` mode only: `~/.claude` and `~/.claude.json`.

  Private key files and `~/.ssh/config` are never exposed. For ssh
  signing, the file `user.signingkey` names is mounted only if it is a
  public key, else its `.pub`, else nothing: git allows it to name the
  private key.
- **Verification is local.** `make check-guix` asserts four things:
  1. The library came from `/gnu/store`.
  2. However a shell finds `scheme`, `make`, `git` and `cmark-gfm`
     (`bash -lc`, `bash -lic`, and `/bin` first, the PATH order Claude
     Code's Bash tool was seen to use), it runs the pinned binary. The
     comparison is by resolved path, because under FHS emulation
     `/bin/scheme` *is* the pinned `scheme`.
  3. `$CHEZ` is inside the environment, is an ELF binary rather than a
     wrapper, and Valgrind instruments it.
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
- **The container isolates the toolchain. It is not a sandbox against
  what runs inside it.** Anything inside holds the maintainer's GitHub
  access, through the agents and `GH_TOKEN`, which it can read from its
  environment. It can also get code run on the host later, because the
  repository and Claude's state are shared read-write:
  - `.git/hooks` and `core.fsmonitor` run on the host's next `git` command;
  - the `Makefile` and `tests/guix-env-launcher.sh` run on the host under
    `make check-guix`;
  - hooks in `~/.claude/settings.json` (shared in `claude` mode) run in the
    host's next Claude session.

  What the design does guarantee is narrower: no private key file, and
  nothing the repository's own config names, is ever mounted.
- **`~/.ssh/config` settings do not apply inside.** Host aliases and custom
  ports are unavailable. GitHub over SSH works through the agent.
- **There is no `chez` command inside.** Type `scheme`. `make` uses `$CHEZ`.
- **The `--container` half of the PATH assertion depends on the host.**
  Dropping `--container` is caught by the launcher's own flag checks, and
  inside by `tool-path[fhs-first]` on any host whose `/usr/bin` holds
  different copies of `make` or `git` (mutation M4). On a host where every
  such tool is the same store item as the pin, there is nothing wrong to
  detect.
- **A pin bump can bring a `cmark-gfm` outside the supported range.** The
  existing post-load version check in `native.sls` fails `make build`, which
  fails `check-guix`.
