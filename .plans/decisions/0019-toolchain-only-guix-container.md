# ADR-0019: The Guix container holds the toolchain only; agents run on the host

- **Status:** Accepted
- **Date:** 2026-09-26
- **Scope:** development tooling. No library change
- **Amends:** [ADR-0018](0018-guix-development-environment.md). Its credential
  shares, `claude` mode and `scripts/guix-env-init` are withdrawn. Its pin,
  search paths, container and `make check-guix` stand.
- **Related:** [mutation log](../guix-env-mutation-log.md) ("Toolchain-only
  container")

## Context

ADR-0018 was built for a Claude session living inside the container,
committing, signing and pushing from there. That took an agent-grade
launcher:
- git config parsing;
- gpg and SSH agent sockets, and `GH_TOKEN`;
- public-key checks;
- a mode-fixing init script;
- `claude` mode.

The final review then found two ways the container could mount host secrets.

The maintainer's actual goal was narrower: build and test this repository
without its dependencies polluting the host, while an agent can still
develop on it. An agent on the host meets that goal. It edits and commits
with the host's own tools, and sends builds and tests through
`scripts/guix-env`. None of the credential machinery is needed, and there
is no credential inside for anything to misuse.

## Decision

- **The container receives nothing from `HOME`**: no git config, no agent
  socket, no token, no Claude state. `scripts/guix-env` runs `bash` or a
  given command, and nothing else. `claude` is an ordinary command with no
  mode of its own.
- **Agents run on the host.** They edit and commit there, and run builds and
  tests as `scripts/guix-env …`. `AGENTS.md` says so, because a bare `make` on
  a Guix host has no `chez`.
- **Removed:** `claude` mode, every credential share, `host_config`, the
  public-key check, `scripts/guix-env-init`, the `credential-dir-modes`
  assertion, the `fhs-first` PATH mode, and `openssh`, `github-cli` and
  `gnupg` from the manifest.
- **Kept, and now justified independently:** `--emulate-fhs`. ADR-0018 had
  it for the glibc-linked `claude` binary. Removing it broke `make
  check-install`, whose probe runs with `CHEZ_CMARK_GFM_LIBS` unset. That is
  the install contract: an installed tree finds cmark-gfm by discovery
  alone. Without an FHS `/usr/lib`, discovery finds nothing in a Guix
  container. Every earlier `check-install` pass had depended on the flag.
- **Added:** the assertion `isolated-home`. The container's `HOME` holds
  nothing but the directories leading to the repository. That is the
  "doesn't pollute, and isn't polluted by, the host" property, checked
  directly. The `scripts/check-guix-env` self-test is renamed
  `scripts/guix-env-selftest`, since it was mistaken for the launcher.

## Consequences

- **An agent inside the container is no longer supported.** It could not
  sign, push or reach GitHub.
- **The container is not a security boundary for the agent**, because the
  agent runs on the host with the maintainer's full access. What the
  container isolates is the toolchain, in both directions.
- **Every build or test call pays about 4 s of `time-machine` startup.**
  Agents should batch commands into one call.
- **`isolated-home` makes the `--container` check host-independent.** ADR-0018
  could only detect a dropped `--container` on hosts whose rc files clobber
  `PATH`. Any host's `HOME` has files in it.
