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

**Baseline:** `49 passed, 0 failed`, exit 0, at `f01bdb0`. After Task 3
added T15, T16 and turned T11's ssh-config check into an absence check (see
L13–L16): `54 passed, 0 failed`.

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

### L13. Every command enters through `guix-env-init`

**Guards:** the mode fix runs before anything else inside (Environment, M7).
**Mutation:** `-- sh scripts/guix-env-init` reduced to `--`.
**Result:** `50 passed, 4 failed`: `FAIL T1 no-args ends in -- bash`,
`FAIL T2 args pass through verbatim`, `FAIL T15 command enters via guix-env-init`,
`FAIL T4 runs the resolved binary with its args`.

### L14. `GH_TOKEN` only when `gh auth token` succeeds

**Mutation:** `--preserve=^GH_TOKEN$` moved out of the success branch.
**Result:** `53 passed, 1 failed`: `FAIL T16 gh fails: no GH_TOKEN`.

### L15. The token never reaches a command line

**Guards:** the token is passed by environment name only; a `--env=` or
argv copy would be visible in `ps` and in any log of the command.
**Mutation:** `"--env=GH_TOKEN=$gh_token"` appended beside the preserve.
**Result:** `53 passed, 1 failed`: `FAIL T16 token not on the command line`.

### L16. `~/.ssh/config` stays out

**Guards:** the maintainer's config pins `IdentitiesOnly yes` to
`IdentityFile ~/.ssh/github_kishu` (a private key, which never enters) and
sets `IdentityAgent ~/.1password/agent.sock` (absent inside), so with it ssh
offered no key: `Permission denied (publickey)`. With `-F /dev/null` the
shared agent authenticated.
**Mutation:** the config file exposed again beside `known_hosts`.
**Result:** `53 passed, 1 failed`: `FAIL T11 ssh config not exposed`.

## Environment (`make check-guix`)

Each mutation ran in a fresh `cp -a` of the repository. The clean tree is
`check-guix: ALL CHECKS PASSED`, exit 0. Store hashes are elided as `…`.

### Finding that reshaped Task 3: `test-memory` instrumented nothing

The first manifest supplied `chez` as a wrapper script (`exec scheme "$@"`).
`scripts/guix-env make test-memory` exited 0 with 21 Valgrind headers and
**no `ERROR SUMMARY` at all**: Valgrind traced the shell, the shell exec'd
Chez, and Chez ran uninstrumented. The wrapper was replaced by a `CHEZ`
search path (`<profile>/bin/scheme`), and assertion `valgrind-instruments-chez`
was added. Rerun: 21 suites, 21 × `ERROR SUMMARY: 0 errors from 0 contexts`,
exit 0.

### Finding: `--emulate-fhs` puts the pinned library at `/usr/lib`

The design's probe ran without FHS emulation. With it, discovery finds the
pair at `/usr/lib/…` (resolving to
`/gnu/store/prn4x0x…-cmark-gfm-0.29.0.gfm.13`), so dropping the override
no longer yields `not-found`. `store-library` is kept as a literal
`/gnu/store/` prefix, so it passes only while the override is in effect;
M1 below is the result.

### M1. No `CHEZ_CMARK_GFM_LIBS` search path

**Result:** exit 2, `FAILED store-library: core is '/usr/lib/libcmark-gfm.so.0.29.0.gfm.13'`
and the same for `ext`.

### M2. The pattern admits the unversioned symlinks

**Mutation:** `^libcmark-gfm(-extensions)?\.so` (no `\.[0-9]`).
**Result:** the variable has 4 entries (`wc -l`: `4`); exit 2,
`chez-cmark-gfm: no usable libcmark-gfm (invalid-override)`,
`check-guix: FAILED make-build`.

### M3. No `CHEZ` search path

**Result:** exit 2, `…/bin/sh: line 1: chez: command not found`,
`check-guix: FAILED make-build`.

### M4. No container

**Mutation:** `--container --network --emulate-fhs` removed from the launcher
(`--emulate-fhs` errors without `--container`; `--share` without it is
silently ignored). Through `make check-guix` this is caught first by the
launcher's own `T1 container flags`, `T1 network flag`, `T1 fhs flag`. To
reach assertion 2, the mutated launcher ran `sh scripts/check-guix-env`
directly.
**Result:** exit 1, `FAILED login-shell-path[-lc]` and `[-lic]` for `scheme`
and `git`, each resolving to `/home/kishu/.guix-home/profile/bin/…`, plus
`FAILED make-targets`. Host-dependent: on a host whose rc files do not
prepend `PATH`, assertion 2 cannot see this mutation, and only the launcher's
T1 checks catch it.

### M5. A valid pair copied out of the store

**Result:** `make build` succeeds, then exit 2,
`FAILED store-library: core is '/tmp/tmp.…/libcmark-gfm.so.0.29.0.gfm.13'`
and the same for `ext`.

### M6. `CHEZ` is a wrapper script again

**Mutation:** a `chez-command` wrapper package restored and `CHEZ` pointed at
its `bin/chez`. This is the regression the Valgrind finding describes.
**Result:** exit 2, only
`FAILED valgrind-instruments-chez: valgrind /gnu/store/…-profile/bin/chez --version printed no ERROR SUMMARY`.
`chez-variable` still passed, since the wrapper is inside the profile, which
is why the Valgrind assertion is the one that matters.

### M7. `guix-env-init` fixes no modes

**Mutation:** its `chmod 700` replaced by `:`.
**Result:** exit 2, `FAILED credential-dir-modes` for `/home/kishu` (1777),
`/home/kishu/.ssh` (775), `/home/kishu/.gnupg` (775) and
`/run/user/1000/gnupg` (775).

## One-off runs

- **Store item:** `guix time-machine -C channels.scm -- build cmark-gfm` and
  the profile's library both resolve to
  `/gnu/store/prn4x0x9i2m8mjxqyiyabay820j1snmd-cmark-gfm-0.29.0.gfm.13`.
  The search path does not change the package.
- **`scripts/guix-env make vendor`:** exit 0, `[100%] Built target cmark-gfm`.
- **`scripts/guix-env make site`:** exit 0, `site: build/site ready`.
- **`scripts/guix-env make test-memory`:** exit 0, 21 suites, 21 ×
  `ERROR SUMMARY: 0 errors from 0 contexts` (after the Valgrind finding).
- **Credentials, first attempt:** gpg listed no secret key and warned of
  unsafe homedir permissions. ssh failed with `bad ownership or modes for
  directory /home/kishu/.ssh`. gh: `The token in default is invalid`. Causes:
  guix creates mount points under the host umask (see M7), and gh's token
  lives in the desktop keyring over D-Bus. Fixes: `scripts/guix-env-init`,
  not exposing `~/.ssh/config` (L16), and `GH_TOKEN` from `gh auth token` on
  the host, the maintainer's choice.
- **Credentials, after the fixes:**
  `gpg --list-secret-keys` lists `sec ed25519/9EBA259B8EAC5130`
  (`CC2923E5…`) through the host agent, warning only that the host agent
  (2.2.27) is older than the container's gpg (2.5.21).
  `ssh -T git@github.com`: `Hi DarrenN! You've successfully authenticated`.
  `git fetch --dry-run`: exit 0. `gh auth status`:
  `Logged in to github.com account DarrenN (GH_TOKEN)`.
