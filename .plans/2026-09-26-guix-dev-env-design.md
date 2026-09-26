# Guix development environment: a pinned container that can host Claude Code

Status: proposed
Date: 2026-09-26
Scope: development tooling only. No library behaviour changes, no export
changes, no change to discovery (ADR-0016), and no CI job.

## Goal

Define a reproducible, pinned Guix environment for developing this
repository. Its primary user is a Claude Code session: the maintainer
launches `claude` inside the environment and works there, including
committing, pushing, opening and merging PRs, and running the closing ritual.

Success means:

1. One command, `scripts/guix-env claude`, starts a Claude session inside a
   Guix container whose toolchain comes entirely from a pinned Guix revision.
2. Inside that container every Linux make target works (`build`, `test`,
   `check-*`, `examples`, `site`, `vendor`, `test-memory`) with no argument
   such as `CHEZ=` and no manually set variable.
3. A shell started the way Claude's Bash tool starts one sees the
   environment's tools, not the host's.
4. Signed commits, `git push` and `gh` work from inside.
5. `make check-guix` proves 1–3 locally, and every assertion in it has been
   seen to fail under a mutation that breaks the property it names. The
   targets it does not run (`vendor`, `site`, `test-memory`) are each run
   once inside the container during implementation, with the result
   recorded in the mutation log.

### Decided during brainstorming

| Question | Decision |
|---|---|
| Purpose | Reproducible, pinned dev environment, not a local convenience, and not a Guix package for consumers |
| Where it is verified | Local `make check-guix` only. No CI job (CI spend was cut in #18) |
| How `CHEZ` and `CHEZ_CMARK_GFM_LIBS` get set | By the Guix files themselves (search path and wrapper package), not a wrapper that exports them, and not a change to discovery |
| Isolation for Claude sessions | `--container`, not `--pure` + dotfile guards |
| Push/PRs from inside | Yes: the SSH agent and `gh` config are shared in |

### Non-goals

- A Guix package definition for chez-cmark-gfm (a consumer-side `guix.scm`).
- Teaching `(cmark gfm private discovery)` to search Guix profiles. That
  reopens ADR-0016 to serve a dev environment. The environment uses the
  documented `CHEZ_CMARK_GFM_LIBS` override instead.
- aarch64, macOS, Windows. See §6.
- Automating the Claude smoke check (§5.3).

## 1. Evidence from the feasibility probe

A throwaway manifest was built in the session scratchpad (not the repo)
against the Guix commit this spec pins. Findings, each of which the design
below depends on:

- **Guix's `cmark-gfm` is `0.29.0.gfm.13`,** the project's pinned version,
  and installs the versioned pair `libcmark-gfm.so.0.29.0.gfm.13` /
  `libcmark-gfm-extensions.so.0.29.0.gfm.13` beside the unversioned `-dev`
  style symlinks, plus the `cmark-gfm` CLI. Library and oracle come from one
  build, so they cannot drift.
- **Discovery cannot find a profile library.** Its Linux candidates are
  `/usr/local/lib`, `/usr/lib/<triple>`, `/usr/lib`, `/usr/lib64`
  (`discovery.sls`, `default-candidate-directories`). Without the override,
  `make build` fails `not-found` inside any Guix environment.
- **A search-path specification yields exactly the override's format.**
  `file-pattern "^libcmark-gfm(-extensions)?\\.so\\.[0-9]"` over `lib/`
  produced exactly two colon-separated absolute paths (extensions first,
  which `parse-library-override` accepts, since it classifies by basename).
- **Inheriting `cmark-gfm` to add the search path does not change its store
  item.** The profile's library resolved to the same
  `/gnu/store/prn4x0x…-cmark-gfm-0.29.0.gfm.13` that `guix build cmark-gfm`
  returns, so substitutes still apply and nothing rebuilds.
- **A `chez` symlink to `scheme` aborts:** `cannot find compatible chez.boot
  in search path "%x:%x/../lib/csv%v/%m:…"`. Chez derives its boot-file name
  from the name it was invoked by. A wrapper script that `exec`s `scheme`
  works.
- **With the wrapper and search path, in `--container --network`,
  `make build` named the profile pair and all 22 suites passed.**
- **Login shells clobber the environment's `PATH` under `--pure`.** On the
  maintainer's machine `bash -lic` inside a `--pure` shell put
  `~/.local/bin`, `~/.guix-home/profile/bin` and `~/.config/guix/current/bin`
  ahead of the environment's `bin`. `scheme` then resolved to guix-home's.
  This is why the container was chosen (§3).
- Guix packages `github-cli` (2.83.2) and `openssh`.
- The `claude` binary is glibc-linked (`interpreter
  /lib64/ld-linux-x86-64.so.2`), hence `--emulate-fhs`.
- Commits are signed, and the remote is SSH. The signing *format* differs by
  repository: the global `~/.gitconfig` names an SSH key, but for this
  repository an included `~/.config/git/.gitconfig-kiyomi` overrides it
  with `gpg.format = openpgp` and a GPG key, signed through the host
  gpg-agent (`/run/user/1000/gnupg/S.gpg-agent`, whose pinentry runs on the
  host desktop). Found when the spec's own first commit prompted pinentry. So
  the launcher cannot assume a signing setup: it must derive one.

Not verified, and deliberately left to §5.3: that `claude` actually starts
and operates under `--container --emulate-fhs`. Starting a nested Claude
session from inside a Claude session was blocked by the auto-mode
classifier.

## 2. Files

```
channels.scm          pinned Guix revision
manifest.scm          toolchain + two local definitions
scripts/guix-env      the one launcher (Claude sessions and check-guix)
```

`channels.scm` and `manifest.scm` sit at the repo root, the locations
`guix shell` and `guix time-machine` conventionally look for.

### 2.1 `channels.scm`

The official `guix` channel only, pinned to commit
`b532aa7d0bb345aafabf6b63cbfbda45abbec091` (the maintainer's current
revision, minus the `nonguix` channel, which nothing here needs), with the
channel introduction so `time-machine` authenticates it. The file is
generated with `guix describe -f channels` and trimmed, not hand-written.

Bumping the pin is editing that commit and running `make check-guix`. A newer
Guix whose `cmark-gfm` is outside the supported range is caught by the
existing post-load `cmark_version()` check in `native.sls`, which fails
`make build`. No new mechanism is needed for that case.

### 2.2 `manifest.scm`

Two local definitions:

- **`cmark-gfm/chez-search-path`**: `(package (inherit cmark-gfm) …)`
  adding one `native-search-paths` entry: variable `CHEZ_CMARK_GFM_LIBS`,
  files `("lib")`, file-type `regular`, file-pattern as in §1. The pattern
  must match only the versioned names; the unversioned symlinks would make
  four entries, which `parse-library-override` rejects as
  `invalid-override`.
- **`chez-command`**: a `trivial-build-system` package whose `bin/chez` is a
  script `#!<bash-minimal>/bin/sh` / `exec <chez-scheme>/bin/scheme "$@"`,
  both by store path. Not a symlink (§1).

Packages:

| Group | Packages |
|---|---|
| Chez and cmark | `chez-scheme`, `chez-command`, `cmark-gfm/chez-search-path` |
| What the Makefile shells out to | `bash`, `coreutils`, `make`, `git`, `grep`, `sed`, `gawk`, `findutils`, `diffutils`, `nss-certs` |
| `make vendor` | `cmake`, `gcc-toolchain` |
| `make test-memory` | `valgrind` |
| Push, PRs, signing | `openssh`, `github-cli`, `gnupg` |

Akku is not included: it is a consumer-side tool with its own CI job. Tools
Claude Code itself turns out to need (e.g. `ripgrep`, `less`, `procps`) are
added when the §5.3 smoke check shows them missing, not guessed.

## 3. `scripts/guix-env [cmd…]`

The single entry point. `scripts/guix-env claude` starts a session,
`scripts/guix-env make test` runs a target, and `make check-guix` calls it,
so the environment that is verified is the environment Claude runs in.

It runs:

```
guix time-machine -C channels.scm -- shell -m manifest.scm \
  --container --network --emulate-fhs <shares> -- <cmd>
```

from the repo root. The container shares the working directory read-write at
the same path, so Claude's per-project memory (keyed on the path) is the
same inside and out. `HOME` is an empty directory: no rc files, so nothing
re-prepends `PATH`. That is the fix for §1's login-shell finding.

Shares:

| Need | Flags | Notes |
|---|---|---|
| Claude login and state | `--share=$HOME/.claude`, `--share=$HOME/.claude.json` | Read-write. See risk R1 |
| Claude binary | `--expose` the directory of `readlink -f ~/.local/bin/claude`. Exec by absolute path with `DISABLE_AUTOUPDATER=1` | The binary is read-only inside, so the updater is disabled rather than left to fail |
| git config | `--expose` every file `git config --list --show-origin` reports for this repo (global, XDG, and `include`/`includeIf` targets such as `~/.config/git/.gitconfig-kiyomi`) | The repo is at the same path inside, so `includeIf gitdir:` still matches. `~/.gitconfig` is a symlink into `/gnu/store`, which the container sees |
| Signing, `openpgp` (the default `gpg.format`) | `--share` the socket `gpgconf --list-dirs agent-socket` names. `--expose` `~/.gnupg/pubring.kbx` and `trustdb.gpg` | Private keys stay with the host agent, and pinentry appears on the host desktop. See R3 |
| Signing, `ssh` | `--expose` the `.pub` file `user.signingkey` names | The agent (next row) signs |
| SSH | `--share=$SSH_AUTH_SOCK --preserve='^SSH_AUTH_SOCK$'`, `--expose` `~/.ssh/config` and `~/.ssh/known_hosts` if present | The private key never enters. The agent signs and authenticates |
| `gh` | `--share=$HOME/.config/gh` | Read-write: `gh` refreshes tokens |
| Terminal | `--preserve` `^TERM$`, `^COLORTERM$`, `^LANG$` | |

Behaviour:

- **Refuses to nest.** If `$GUIX_ENVIRONMENT` is already set it exits
  non-zero naming the variable. Guix is not in the manifest, so nesting
  would fail obscurely otherwise.
- **An optional share whose source does not exist is skipped, not an error.**
  A contributor without `gh` or a signing key can still run tests. A missing
  `claude` binary is an error only when the command is `claude`.
- **Arguments pass through verbatim** after `--`.
- POSIX `sh`, so it runs from the host before any environment exists.

Risks, each resolved by the §5.3 smoke check rather than speculation:

- **R1.** Claude may save `~/.claude.json` by writing a temporary file and
  renaming it over the original. A rename onto a bind-mounted single file
  fails `EBUSY`. Fallback: set `CLAUDE_CONFIG_DIR` to the shared
  `~/.claude`, at the cost of that config being separate from the host's.
- **R2.** The binary may need libraries beyond glibc, or tools not in the
  manifest. Fallback: add them to the manifest.
- **R3.** gpg inside the container may want to write to `~/.gnupg` (lock
  files, the trust database), or may not find the shared agent socket at the
  path it computes. Fallback: point `GNUPGHOME` at a container-local
  directory that holds the exposed public keyring and a symlink to the
  shared socket. For `ssh` signing, the agent may not hold the key: document
  `ssh-add` on the host. No private key file is ever exposed.

## 4. `make check-guix`

A new target in `.PHONY` with a `## ` description, so `check-help` covers it.
Local only; nothing in `.github/` calls it.

It runs, through `scripts/guix-env`:

```
make build check-pins test check-purity check-install examples check-site
```

then two assertions inside the same container:

1. **The library came from the store.** The `core:` and `ext:` lines that
   `make build` prints both begin with `/gnu/store/`. A pass cannot come
   from a library found anywhere else.
2. **A login shell sees the environment's tools.** In `bash -lc`, the way
   Claude's Bash tool starts shells, `command -v` for `chez`, `scheme`,
   `make`, `git` and `cmark-gfm` each resolves under `$GUIX_ENVIRONMENT`.
   This is the property the container exists for.

Each assertion prints what it expected and what it saw, and names itself on
failure. The target fails if any step fails.

`test-memory` is available in the environment but not run by `check-guix`,
because it is slow. It is run once during implementation to confirm Valgrind
works inside the container, and the result is recorded in the mutation log.

## 5. Testing and evidence

### 5.1 TDD order

`make check-guix` is the test. Write it and its assertions first, run it
against the tree before `manifest.scm` exists and watch it fail, then build
the manifest until it passes.

### 5.2 Mutations

Recorded in `.plans/guix-env-mutation-log.md`, in the same form as the
existing logs. Each is applied to a copy or a scratch edit, must turn
`check-guix` red *for the predicted reason*, then is reverted and seen green:

| # | Mutation | Predicted failure |
|---|---|---|
| M1 | Remove the `native-search-paths` entry | `make build` fails with reason `not-found` |
| M2 | Widen the file pattern to also match unversioned `.so` | Four entries in the override: `invalid-override` |
| M3 | Make `bin/chez` a symlink instead of a wrapper script | `make build` aborts with the `chez.boot` message |
| M4 | Drop `--container` from `scripts/guix-env` | Assertion 2 fails on `scheme` (guix-home's copy) |
| M5 | Make the build step report a non-store library | Assertion 1 fails naming the path |

M4 is machine-dependent: it fails only where the host's rc files prepend
`PATH`, as the maintainer's do. On a machine without such rc files, the
container's contribution to assertion 2 is not observable, and the log says
so rather than claiming coverage. M5's exact mechanism is chosen during
implementation. If no mutation can break assertion 1 through the path
check itself, the log records the property as uncovered and why, per
AGENTS.md.

### 5.3 Claude smoke check (manual, once, run by the maintainer)

Documented in `docs/building.md`, results recorded in the mutation log:

1. `scripts/guix-env claude` starts and is logged in.
2. In the session's Bash tool: `command -v scheme chez cmark-gfm` all name
   `$GUIX_ENVIRONMENT`, and `echo $CHEZ_CMARK_GFM_LIBS` names the store pair.
3. A signed commit succeeds, and `git log --show-signature -1` shows a good
   signature.
4. `git push --dry-run` and `gh auth status` succeed.
5. Quitting and relaunching keeps login and settings (exercises R1).

Anything missing becomes a manifest or launcher change, and the check is
rerun.

## 6. Scope limits, stated

- **x86_64-linux only.** Guix builds `chez-scheme` and `cmark-gfm` for
  `x86_64-linux` and `i686-linux` alone. The macOS and arm64 workflows
  (`docs/building.md`, `docs/installing.md`) are unchanged.
- **Ungated in CI.** Nothing automated notices if the pin rots or the
  manifest breaks between runs of `make check-guix`. This is the accepted
  cost of the "local only" decision, recorded in ADR-0018 the way `ci.yml`
  records the removed macOS job.
- **The shares are deliberate holes.** Inside the container Claude holds the
  maintainer's GitHub credentials, via the agent and `gh`. The container
  confines the filesystem to the repo and the listed paths. It does not
  confine what can be done on GitHub.

## 7. Documentation

- **`docs/building.md`**: a "Guix" section covering entering the
  environment, running Claude in it, `make check-guix`, bumping the pin, the
  §5.3 checklist, and the x86_64-only limit. It notes that bare `guix shell`
  (which auto-loads `manifest.scm`) bypasses `channels.scm` and is the
  unpinned path.
- **`CONTRIBUTING.md`**: one line pointing Guix users at that section.
- **`CHANGELOG.md`**: an Unreleased "Added" entry.
- **ADR-0018** (`.plans/decisions/0018-guix-development-environment.md`):
  pinned `time-machine` plus container; search-path provisioning rather than
  a discovery change or an exporting wrapper; x86_64-only; local-only
  verification and what it leaves ungated; the credential shares.
- **`AGENTS.md`**, two traps:
  - Chez derives its boot-file name from the name it was invoked by, so an
    alias must be a wrapper script, not a symlink.
  - Login-shell rc files re-prepend `PATH` inside `guix shell --pure`, so a
    `--pure` environment can pass on host tools. The container is the fix
    here.
