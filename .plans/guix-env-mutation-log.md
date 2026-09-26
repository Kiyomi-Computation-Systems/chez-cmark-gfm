# Guix development environment mutation log

Evidence that the checks added for
`.plans/2026-09-26-guix-dev-env-design.md` fail through the property they
claim to guard. Every mutation was applied to a scratch copy of the
repository outside the working tree (`cp -a` into the session scratchpad).
The repository copy was never edited.

## Launcher (`tests/guix-env-launcher.sh`)

`/bin/sh` is dash on the machine these ran on, so the launcher and its
tests ran under a strict POSIX shell.

**Red run, before `scripts/guix-env` existed:** `13 passed, 36 failed`,
exit 1, first failure `FAIL T1 no-args exits 0` (`env` exits 127 on the
missing file). The 36 are every presence check (`has`, an exact status, an
exact line sequence). Each can pass only if the launcher prints that exact
line, so the missing launcher is a sufficient red for them. The 13 that
passed are the absence checks (`lacks`, `! -s`), which an absent launcher
satisfies trivially. Each of those needed its own mutation below, and
every one of the 13 now has one.

**Baseline:** `49 passed, 0 failed`, exit 0, on the tree committed with
this log (parent `a158a2a`).

**Fixture fix found by this log.** Under L6 as first run, `T9 openpgp: no
ssh signing key` did not fail. The openpgp fixture's `user.signingkey` was
a key id, so there was no file for any branch to expose, and the assertion
passed for want of a file, not because of the format. The openpgp fixture
now names the same `~/.ssh/signing.pub` the ssh fixture uses, so only
`gpg.format` decides. The L6 result below is the rerun.

Each entry: the mutation, then the checks that failed, verbatim. The clean
rerun after every mutation was `49 passed, 0 failed`.

### L1. Claude's login stays out of command mode

**Guards:** a shell or `make` run never mounts `~/.claude` (spec §3).
**Mutation:** `set -- "$@" "--share=$HOME/.claude"` inserted before the
claude-mode block.
**Result:** `48 passed, 1 failed`: `FAIL T3 command mode: no ~/.claude share`.

### L1b. The updater variable stays out of command mode

**Mutation:** `set -- "$@" '--preserve=^DISABLE_AUTOUPDATER$'` inserted
before the claude-mode block.
**Result:** `48 passed, 1 failed`: `FAIL T3 command mode: no DISABLE_AUTOUPDATER`.

### L1c. The Claude binary stays out of command mode

**Mutation:** an unconditional `--expose` of the resolved `claude` binary's
directory inserted before the claude-mode block. This is the shape of
"always mount Claude, it's harmless".
**Result:** `48 passed, 1 failed`: `FAIL T3 command mode: no claude binary expose`.

### L2. A stale SSH agent socket is skipped

**Guards:** `guix shell` refuses a `--share` whose source is missing, so
a dead `SSH_AUTH_SOCK` must not reach it (Review Focus 3).
**Mutation:** `&& [ -e "$SSH_AUTH_SOCK" ]` deleted.
**Result:** `47 passed, 2 failed`: `FAIL T12 stale agent: not shared`,
`FAIL T12 stale agent: not preserved`.

### L3. The container gets the repo root from any directory

**Guards:** launched as `../scripts/guix-env` from `docs/`, the shared
working directory is still the root (Review Focus 2).
**Mutation:** `cd "$root"` deleted.
**Result:** `48 passed, 1 failed`: `FAIL T14 subdirectory: runs from the repo root`.
The dry run prints `$PWD`, not `$root`. Printing `$root` would have made
this check pass with the `cd` gone.

### L4. Nesting is refused

**Guards:** Review Focus 4.
**Mutation:** the `GUIX_ENVIRONMENT` refusal block deleted.
**Result:** `46 passed, 3 failed`: `FAIL T7 nested: exit 2`,
`FAIL T7 nested: names GUIX_ENVIRONMENT`, `FAIL T7 nested: prints no command`.

### L5. Arguments survive the flag rotation

**Guards:** arguments pass through verbatim (spec §3). Review Focus 1.
**Mutation:** `"$1"` unquoted in the rotation loop.
**Result:** `47 passed, 2 failed`: `FAIL T2 args pass through verbatim`,
`FAIL T4 runs the resolved binary with its args` (the fake HOME has a space).

### L6. The signing format decides what is shared

**Guards:** openpgp shares the agent socket and public keyring; ssh exposes
the named `.pub`; never both.
**Mutation:** the `openpgp)` and `ssh)` case labels swapped.
**Result:** `42 passed, 7 failed`: `FAIL T9 gpg agent socket shared`,
`FAIL T9 pubring exposed`, `FAIL T9 trustdb exposed`,
`FAIL T9 openpgp: no ssh signing key`, `FAIL T10 ssh signing key exposed`,
`FAIL T10 ssh format: no gpg socket`, `FAIL T10 ssh format: no pubring`.

### L7. The relative local config is not exposed

**Guards:** only absolute git config origins are exposed. `.git/config` is
already inside the shared repo.
**Mutation:** the `/*)` case pattern widened to `*)`.
**Result:** `48 passed, 1 failed`: `FAIL T8 relative .git/config not exposed`.

### L8. A missing `~/.claude.json` is skipped

**Guards:** Review Focus 3, a fresh Claude install.
**Mutation:** `if [ -f "$HOME/.claude.json" ]` replaced by `if true`.
**Result:** `48 passed, 1 failed`: `FAIL T5 no .claude.json: not shared`.

### L9. The Claude symlink is resolved

**Guards:** Review Focus 5.
**Mutation:** `claude_bin=$(readlink -f -- "$claude_link")` replaced by
`claude_bin=$claude_link`.
**Result:** `47 passed, 2 failed`: `FAIL T4 binary directory exposed`,
`FAIL T4 runs the resolved binary with its args`.

### L10. No arguments means bash

**Mutation:** `set -- bash` changed to `set -- sh`. Deleting the default
instead crashes on `$1` under `set -u`, which would be a failure for the
wrong reason.
**Result:** `48 passed, 1 failed`: `FAIL T1 no-args ends in -- bash`.

### L11. A missing `claude` is a refusal, not a fallback

**Mutation:** the `no Claude Code binary on PATH` refusal replaced by
`claude_link=/bin/true`, the shape of "fall back to something".
**Result:** `46 passed, 3 failed`: `FAIL T6 missing claude: exit 2`,
`FAIL T6 missing claude: says so`, `FAIL T6 missing claude: prints no command`.

### L12. A missing `gh` config is skipped

**Mutation:** `if [ -d "$HOME/.config/gh" ]` replaced by `if true`.
**Result:** `48 passed, 1 failed`: `FAIL T13 no gh config: not shared`.
