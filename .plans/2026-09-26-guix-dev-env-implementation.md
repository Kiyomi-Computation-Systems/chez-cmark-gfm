# Guix Development Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pinned Guix container, entered with `scripts/guix-env`, that gives
any contributor an interactive development shell. It runs any make target
unmodified, and hosts a Claude Code session that can commit, sign, push and
use `gh`. `make check-guix` proves this locally.

**Architecture:** `channels.scm` pins Guix. `manifest.scm` holds the
toolchain plus two local definitions. One is a `cmark-gfm` variant whose
search path exports `CHEZ_CMARK_GFM_LIBS`, the other a `chez` wrapper
script. `scripts/guix-env` is a POSIX-sh imperative shell. It builds a
`guix time-machine … shell --container` command, and its argument
construction is testable on the host through `GUIX_ENV_DRY_RUN=1`.
`scripts/check-guix-env` runs inside the container and asserts two
properties. The library came from `/gnu/store`, and a login shell sees only
the environment's tools.

**Tech Stack:** GNU Guix (`time-machine`, `shell --container`, manifests,
`search-path-specification`, `trivial-build-system`), POSIX sh, GNU Make,
Chez Scheme 10.4.0, cmark-gfm 0.29.0.gfm.13.

**Spec:** `.plans/2026-09-26-guix-dev-env-design.md`. Read it first. §1 is
the probe evidence every task depends on.

## Global Constraints

- Guix channel `guix` only, commit `b532aa7d0bb345aafabf6b63cbfbda45abbec091`,
  introduction `9edb3f66fd807b096b48283debdcddccfea34bad`, fingerprint
  `BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA`. No `nonguix`.
- x86_64-linux only. No macOS, arm64 or Windows path changes.
- No change under `src/`, no change to discovery, and no change under
  `.github/`: `check-guix` is local only.
- `.PHONY` stays on **one physical line** (`check-help` parses it with
  awk). `check-guix` gets a `## ` description on its own target line.
- `tests/test-*.sps` is the `make test` glob. The new launcher test is
  `tests/guix-env-launcher.sh`, deliberately outside it.
- `scripts/guix-env` and `scripts/check-guix-env` are POSIX `sh`: no arrays,
  no `[[`, no `eval`, no `local`. Use `if` statements, not `a && b`, for
  conditional appends under `set -e`.
- No private key file ever enters the container: only the paths listed in
  spec §3.
- Every new assertion is watched failing **by name** under a mutation
  applied in a scratch copy **outside the repository**, then seen green
  again. Record each one in `.plans/guix-env-mutation-log.md`.
- Commits are GPG-signed through a desktop pinentry. If a commit fails with
  `gpg: signing failed: Operation cancelled`, stop and ask the user to retry.
  Never pass `--no-gpg-sign`.
- Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01V3R9HBFZGRtF7CTkPfFcCh
  ```
- Work on branch `guix-dev-env`. Do not push or open a PR unless the user
  asks.

## Review Focus

1. **A `HOME` or argument containing a space.** Every share path and every
   passed-through argument must survive intact. Pinned by the launcher
   test's fake HOME (`$tmp/fake home`) and T2 (Task 1).
2. **Launching from a subdirectory or by relative path**
   (`../scripts/guix-env` from `docs/`). The container must still share the
   repo root, not `docs/`. Pinned by T14 (Task 1).
3. **A credential that is absent or stale**: no `~/.claude.json` on a fresh
   Claude install, `SSH_AUTH_SOCK` naming a socket that no longer exists, no
   `~/.config/gh`. Each must be skipped, never an error, because `guix
   shell` refuses a `--share` whose source is missing. Pinned by T5, T12, T13
   (Task 1).
4. **Nesting.** Claude, running inside the container, invokes
   `make check-guix` or `scripts/guix-env`. It must refuse with a message
   naming `GUIX_ENVIRONMENT`, not fail obscurely because `guix` is absent.
   Pinned by T7 (Task 1).
5. **`claude` on `PATH` is a symlink** (the native installer's
   `~/.local/bin/claude → ~/.local/share/claude/versions/<v>`). The
   container must receive the resolved binary's directory. Pinned by T4
   (Task 1).

---

## Files

| Path | Responsibility | Task |
|---|---|---|
| `tests/guix-env-launcher.sh` | Host-side dry-run tests for the launcher | 1 |
| `scripts/guix-env` | The launcher: shell, command and `claude` modes | 1 |
| `.plans/guix-env-mutation-log.md` | Mutation evidence | 1, 3, 5 |
| `channels.scm` | Pinned Guix | 2 |
| `manifest.scm` | Toolchain + `chez-command` + `cmark-gfm/chez-search-path` | 2 |
| `scripts/check-guix-env` | In-container assertions and target run | 2 |
| `Makefile` | `check-guix` target, `.PHONY` entry | 2 |
| `.plans/decisions/0018-guix-development-environment.md` | ADR | 4 |
| `docs/building.md` | "Guix development environment" section | 4 |
| `CONTRIBUTING.md`, `CHANGELOG.md`, `AGENTS.md` | Pointer, entry, two traps | 4 |

---

### Task 1: The launcher and its host-side tests

**Files:**
- Create: `tests/guix-env-launcher.sh`
- Create: `scripts/guix-env` (mode `0755`)
- Create: `.plans/guix-env-mutation-log.md`

**Interfaces:**
- Consumes: nothing. The launcher references `channels.scm` and
  `manifest.scm` by relative path but does not read them, so dry runs need
  neither to exist.
- Produces:
  - `scripts/guix-env` takes one of:
    - no arguments: `bash`
    - `CMD [ARG…]`: that command
    - `claude [ARG…]`: the resolved Claude binary plus Claude shares
  - Exit `2` with `guix-env: …` on stderr for a refusal.
  - With `GUIX_ENV_DRY_RUN=1` it prints `cd <cwd>` then `guix` and each
    argument, one per line, and exits 0.
  - `GUIX_ENV_GPG_AGENT_SOCKET` overrides the `gpgconf` socket lookup.
  - Task 2's Makefile target calls `sh tests/guix-env-launcher.sh`, then
    `scripts/guix-env sh scripts/check-guix-env`.

- [ ] **Step 1: Write the failing test**

Create `tests/guix-env-launcher.sh`:

```sh
#!/bin/sh
# Host-side tests for scripts/guix-env. Nothing here runs Guix: every case
# sets GUIX_ENV_DRY_RUN=1, under which the launcher prints `cd <cwd>` and
# then the guix command it would exec, one argument per line. `make
# check-guix` runs this before entering the container. Checks name
# themselves, and the exit status is the number of failures (capped at 1).
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
launcher=$root/scripts/guix-env
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0

ok()    { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf 'FAIL %s\n' "$1" >&2; }
check() { name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has()   { grep -Fxq -- "$1" "$tmp/out"; }
lacks() { ! grep -Fq -- "$1" "$tmp/out"; }
lines() { sed -n "$1" "$tmp/out" | tr '\n' '|'; }
tail_lines() { tail -n "$1" "$tmp/out" | tr '\n' '|'; }

# The fake HOME has a space in it, so every path the launcher builds must
# survive quoting (Review Focus 1).
home="$tmp/fake home"
versions="$home/.local/share/claude/versions"
mkdir -p "$versions" "$home/.local/bin" "$home/.claude" "$home/.config/gh" \
         "$home/.ssh" "$home/.gnupg"
printf '#!/bin/sh\n' >"$versions/9.9.9"
chmod +x "$versions/9.9.9"
ln -s "$versions/9.9.9" "$home/.local/bin/claude"
for f in .claude.json .ssh/config .ssh/known_hosts .ssh/signing.pub \
         .gnupg/pubring.kbx .gnupg/trustdb.gpg gpg-agent.sock ssh-agent.sock; do
  : >"$home/$f"
done
cat >"$home/.gitconfig" <<EOF
[user]
	name = Test
[include]
	path = $home/signing.gitconfig
EOF
signing() {
  printf '[gpg]\n\tformat = %s\n[user]\n\tsigningkey = %s\n' "$1" "$2" \
    >"$home/signing.gitconfig"
}
signing openpgp ABCDEF0123456789

# PATH minus every directory holding a real `claude`, so the only one the
# launcher can find is the fake one prepended by run().
base_path=$(printf '%s\n' "$PATH" | tr ':' '\n' | while IFS= read -r d; do
  if [ ! -e "$d/claude" ]; then printf '%s:' "$d"; fi
done)
base_path=${base_path%:}

# run [VAR=value...] LAUNCHER [ARG...]
# Runs from $cwd in a scrubbed environment. Later VAR=value pairs override
# the defaults. stdout -> $tmp/out, stderr -> $tmp/err, exit -> $status.
cwd=$root
run() {
  status=999
  ( cd "$cwd" && env -i HOME="$home" PATH="$home/.local/bin:$base_path" \
      GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
      GUIX_ENV_DRY_RUN=1 \
      GUIX_ENV_GPG_AGENT_SOCKET="$home/gpg-agent.sock" \
      SSH_AUTH_SOCK="$home/ssh-agent.sock" \
      "$@" ) >"$tmp/out" 2>"$tmp/err"
  status=$?
}

# T1: no arguments means an interactive bash, behind the pinned prefix.
run "$launcher"
check "T1 no-args exits 0" [ "$status" -eq 0 ]
check "T1 no-args runs from the repo root" [ "$(lines 1p)" = "cd $root|" ]
check "T1 no-args pins guix via channels.scm" \
  [ "$(lines 2,8p)" = "guix|time-machine|-C|channels.scm|--|shell|-m|" ]
check "T1 no-args uses manifest.scm" [ "$(lines 9p)" = "manifest.scm|" ]
check "T1 container flags" has --container
check "T1 network flag" has --network
check "T1 fhs flag" has --emulate-fhs
check "T1 no-args ends in -- bash" [ "$(tail_lines 2)" = "--|bash|" ]

# T2: arguments pass through verbatim, spaces and dollars included.
run "$launcher" make "a b" '$HOME'
check "T2 args pass through verbatim" \
  [ "$(tail_lines 4)" = '--|make|a b|$HOME|' ]

# T3: command mode carries no Claude share. T4 is its partner: the same
# fixture in claude mode must produce them, so T3 cannot pass vacuously.
run "$launcher" make test
check "T3 command mode: no ~/.claude share" lacks "--share=$home/.claude"
check "T3 command mode: no claude binary expose" lacks "--expose=$versions"
check "T3 command mode: no DISABLE_AUTOUPDATER" lacks "DISABLE_AUTOUPDATER"

# T8: every absolute git config origin is exposed. The relative local
# .git/config is not: the repo is already shared.
check "T8 global gitconfig exposed" has "--expose=$home/.gitconfig"
check "T8 included gitconfig exposed" has "--expose=$home/signing.gitconfig"
check "T8 relative .git/config not exposed" lacks "--expose=.git/config"

# T9: openpgp signing shares the agent socket and the public keyring only.
check "T9 gpg agent socket shared" has "--share=$home/gpg-agent.sock"
check "T9 pubring exposed" has "--expose=$home/.gnupg/pubring.kbx"
check "T9 trustdb exposed" has "--expose=$home/.gnupg/trustdb.gpg"
check "T9 openpgp: no ssh signing key" lacks "--expose=$home/.ssh/signing.pub"

# T11: SSH agent and client config.
check "T11 ssh agent shared" has "--share=$home/ssh-agent.sock"
check "T11 SSH_AUTH_SOCK preserved" has '--preserve=^SSH_AUTH_SOCK$'
check "T11 ssh config exposed" has "--expose=$home/.ssh/config"
check "T11 known_hosts exposed" has "--expose=$home/.ssh/known_hosts"

# T13a: gh config shared when present.
check "T13 gh config shared" has "--share=$home/.config/gh"

# T4: claude mode resolves the symlink and adds Claude's shares.
run "$launcher" claude --resume
check "T4 claude exits 0" [ "$status" -eq 0 ]
check "T4 ~/.claude shared" has "--share=$home/.claude"
check "T4 ~/.claude.json shared" has "--share=$home/.claude.json"
check "T4 binary directory exposed" has "--expose=$versions"
check "T4 DISABLE_AUTOUPDATER preserved" has '--preserve=^DISABLE_AUTOUPDATER$'
check "T4 runs the resolved binary with its args" \
  [ "$(tail_lines 3)" = "--|$versions/9.9.9|--resume|" ]

# T5: a fresh Claude install has no ~/.claude.json. Skip it, do not fail.
mv "$home/.claude.json" "$tmp/claude.json.aside"
run "$launcher" claude
check "T5 no .claude.json: exits 0" [ "$status" -eq 0 ]
check "T5 no .claude.json: still claude mode" has "--share=$home/.claude"
check "T5 no .claude.json: not shared" lacks "--share=$home/.claude.json"
mv "$tmp/claude.json.aside" "$home/.claude.json"

# T6: claude mode with no claude on PATH is a named refusal.
run PATH="$base_path" "$launcher" claude
check "T6 missing claude: exit 2" [ "$status" -eq 2 ]
check "T6 missing claude: says so" grep -Fq "no Claude Code binary on PATH" "$tmp/err"
check "T6 missing claude: prints no command" [ ! -s "$tmp/out" ]

# T7: refuse to nest (Review Focus 4).
run GUIX_ENVIRONMENT=/gnu/store/fake-profile "$launcher" make test
check "T7 nested: exit 2" [ "$status" -eq 2 ]
check "T7 nested: names GUIX_ENVIRONMENT" grep -Fq "/gnu/store/fake-profile" "$tmp/err"
check "T7 nested: prints no command" [ ! -s "$tmp/out" ]

# T10: ssh-format signing exposes the named .pub, expanded from ~/, and
# not the gpg agent, even though a gpg socket exists.
signing ssh "~/.ssh/signing.pub"
run "$launcher" make test
check "T10 ssh signing key exposed" has "--expose=$home/.ssh/signing.pub"
check "T10 ssh format: no gpg socket" lacks "--share=$home/gpg-agent.sock"
check "T10 ssh format: no pubring" lacks "--expose=$home/.gnupg/pubring.kbx"
signing openpgp ABCDEF0123456789

# T12: a stale SSH_AUTH_SOCK is skipped, not an error (Review Focus 3).
run SSH_AUTH_SOCK="$home/no-such.sock" "$launcher" make test
check "T12 stale agent: exits 0" [ "$status" -eq 0 ]
check "T12 stale agent: not shared" lacks "no-such.sock"
check "T12 stale agent: not preserved" lacks '--preserve=^SSH_AUTH_SOCK$'

# T13b: no gh config, no share.
rmdir "$home/.config/gh"
run "$launcher" make test
check "T13 no gh config: exits 0" [ "$status" -eq 0 ]
check "T13 no gh config: not shared" lacks "--share=$home/.config/gh"
mkdir -p "$home/.config/gh"

# T14: launched by relative path from a subdirectory, the container still
# gets the repo root (Review Focus 2).
cwd=$root/docs
run ../scripts/guix-env make test
cwd=$root
check "T14 subdirectory: exits 0" [ "$status" -eq 0 ]
check "T14 subdirectory: runs from the repo root" [ "$(lines 1p)" = "cd $root|" ]

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `sh tests/guix-env-launcher.sh`
Expected: many `FAIL` lines, starting with `FAIL T1 no-args exits 0` (the
launcher does not exist, so `env` exits 127), and a non-zero exit.

- [ ] **Step 3: Write the launcher**

Create `scripts/guix-env`, then `chmod 0755 scripts/guix-env`:

```sh
#!/bin/sh
# The pinned Guix development container (ADR-0018; docs/building.md,
# "Guix development environment").
#
#   scripts/guix-env                  an interactive bash
#   scripts/guix-env CMD [ARG...]     run CMD, e.g. `make test`
#   scripts/guix-env claude [ARG...]  Claude Code, with its login shared in
#
# GUIX_ENV_DRY_RUN=1 prints `cd <dir>` and the guix command, one argument
# per line, instead of running it: tests/guix-env-launcher.sh asserts on
# that. GUIX_ENV_GPG_AGENT_SOCKET overrides the gpgconf socket lookup.
#
# Every share except the container's own is optional and skipped when its
# source is missing: guix shell refuses a --share whose source does not
# exist, and a contributor without gh or a signing key still needs a shell.
set -eu

die() { printf 'guix-env: %s\n' "$*" >&2; exit 2; }

if [ -n "${GUIX_ENVIRONMENT:-}" ]; then
  die "already inside a Guix environment (GUIX_ENVIRONMENT=$GUIX_ENVIRONMENT); run the command directly"
fi

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

if [ $# -eq 0 ]; then
  set -- bash
fi

claude_mode=
if [ "$1" = claude ]; then
  claude_mode=1
  claude_link=$(command -v claude || true)
  if [ -z "$claude_link" ]; then
    die "claude: no Claude Code binary on PATH"
  fi
  claude_bin=$(readlink -f -- "$claude_link")
  if [ ! -x "$claude_bin" ]; then
    die "claude: $claude_link does not resolve to an executable"
  fi
  shift
  set -- "$claude_bin" "$@"
fi

# POSIX sh has no arrays: flags are appended after the user's command and
# rotated in front of it at the end.
nuser=$#

set -- "$@" --container --network --emulate-fhs \
  '--preserve=^(TERM|COLORTERM|LANG)$'

if [ -n "$claude_mode" ]; then
  mkdir -p "$HOME/.claude"
  set -- "$@" "--share=$HOME/.claude" \
    "--expose=$(dirname -- "$claude_bin")" \
    '--preserve=^DISABLE_AUTOUPDATER$'
  if [ -f "$HOME/.claude.json" ]; then
    set -- "$@" "--share=$HOME/.claude.json"
  fi
  # The binary is read-only inside; stop the updater rather than let it fail.
  DISABLE_AUTOUPDATER=1
  export DISABLE_AUTOUPDATER
fi

# Every git config file outside the repo, includes too: an includeIf keyed
# on this repo's path still matches, because the repo keeps its path inside.
tab=$(printf '\t')
origins=$(git config --list --show-origin 2>/dev/null \
  | sed -n "s/^file:\([^$tab]*\)$tab.*/\1/p" | sort -u)
while IFS= read -r f; do
  case "$f" in
    /*)
      if [ -e "$f" ]; then
        set -- "$@" "--expose=$f"
      fi
      ;;
  esac
done <<EOF
$origins
EOF

# Signing. Private keys stay with the host agent; only public material and
# the agent socket enter.
format=$(git config --get gpg.format || true)
case "${format:-openpgp}" in
  openpgp)
    sock=${GUIX_ENV_GPG_AGENT_SOCKET:-$(gpgconf --list-dirs agent-socket 2>/dev/null || true)}
    if [ -n "$sock" ] && [ -e "$sock" ]; then
      set -- "$@" "--share=$sock"
    fi
    for f in "$HOME/.gnupg/pubring.kbx" "$HOME/.gnupg/trustdb.gpg"; do
      if [ -f "$f" ]; then
        set -- "$@" "--expose=$f"
      fi
    done
    ;;
  ssh)
    key=$(git config --get user.signingkey || true)
    case "$key" in
      "~/"*) key="$HOME/${key#"~/"}" ;;
    esac
    if [ -n "$key" ] && [ -f "$key" ]; then
      set -- "$@" "--expose=$key"
    fi
    ;;
esac

if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -e "$SSH_AUTH_SOCK" ]; then
  set -- "$@" "--share=$SSH_AUTH_SOCK" '--preserve=^SSH_AUTH_SOCK$'
fi
for f in "$HOME/.ssh/config" "$HOME/.ssh/known_hosts"; do
  if [ -f "$f" ]; then
    set -- "$@" "--expose=$f"
  fi
done

if [ -d "$HOME/.config/gh" ]; then
  set -- "$@" "--share=$HOME/.config/gh"
fi

set -- "$@" --
i=0
while [ "$i" -lt "$nuser" ]; do
  set -- "$@" "$1"
  shift
  i=$((i + 1))
done

set -- time-machine -C channels.scm -- shell -m manifest.scm "$@"

if [ -n "${GUIX_ENV_DRY_RUN:-}" ]; then
  printf 'cd %s\n' "$PWD"
  printf '%s\n' guix "$@"
  exit 0
fi
exec guix "$@"
```

`printf 'cd %s\n' "$PWD"` prints the directory the script actually `cd`'d
into, not `$root`. That is what makes T14 able to fail when the `cd` goes
missing.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `sh tests/guix-env-launcher.sh; echo "exit=$?"`
Expected: every line `ok …`, a final `N passed, 0 failed`, and `exit=0`.

- [ ] **Step 5: Watch each launcher assertion fail under its mutation**

Make a scratch copy outside the repo. For each row below, edit only the
copy's `scripts/guix-env`, run the copy's `tests/guix-env-launcher.sh`,
confirm the named check fails *and* that nothing else explains it, then
restore the copy:

```sh
S=$(mktemp -d)/repo && cp -a "$PWD" "$S"
cp "$S/scripts/guix-env" "$S/guix-env.orig"
# after each mutation:
sh "$S/tests/guix-env-launcher.sh" 2>&1 | grep FAIL
cp "$S/guix-env.orig" "$S/scripts/guix-env"
```

| # | Edit in the copy | Expected `FAIL` |
|---|---|---|
| L1 | Insert `set -- "$@" "--share=$HOME/.claude"` on the line before `if [ -n "$claude_mode" ]; then` (not `if true`: that would crash on the unset `$claude_bin` under `set -u`, the wrong reason) | `T3 command mode: no ~/.claude share` |
| L2 | In the SSH block, delete `&& [ -e "$SSH_AUTH_SOCK" ]` | `T12 stale agent: not shared` |
| L3 | Delete the line `cd "$root"` | `T14 subdirectory: runs from the repo root` |
| L4 | Delete the `GUIX_ENVIRONMENT` refusal block | `T7 nested: exit 2` |
| L5 | In the rotation loop, change `"$1"` to `$1` | `T2 args pass through verbatim`, and `T4 runs the resolved binary with its args` (the fake HOME has a space) |
| L6 | Swap the `openpgp)` and `ssh)` case labels | `T9 gpg agent socket shared`, `T10 ssh signing key exposed` |
| L7 | Change the `/*)` case pattern to `*)` | `T8 relative .git/config not exposed` |
| L8 | Replace `if [ -f "$HOME/.claude.json" ]` with `if true` | `T5 no .claude.json: not shared` |
| L9 | Change `claude_bin=$(readlink -f -- "$claude_link")` to `claude_bin=$claude_link` | `T4 binary directory exposed`, `T4 runs the resolved binary with its args` |
| L10 | Change `set -- bash` to `set -- sh` (not a deletion: that crashes on `$1` under `set -u`, the wrong reason) | `T1 no-args ends in -- bash` only |

Any row whose named check does not fail means an empty assertion. Rewrite it
before moving on, and do not record the row until it fails for the
predicted reason.

- [ ] **Step 6: Start the mutation log**

Create `.plans/guix-env-mutation-log.md`:

````markdown
# Guix development environment mutation log

Evidence that the checks added for
`.plans/2026-09-26-guix-dev-env-design.md` fail through the property they
claim to guard. Every mutation was applied to a scratch copy of the
repository outside the working tree. The repository copy was never edited.

## Launcher (`tests/guix-env-launcher.sh`)

Baseline: `<N> passed, 0 failed` on commit `<sha>`.

### L1. Claude's shares stay in claude mode

**Guards:** a shell or `make` run never mounts the Claude login (spec §3).
**Mutation:** the claude-mode guard around the shares block replaced by `if true`.
**Result:** FAILED by name: `<paste the FAIL lines>`.
**Clean rerun:** `<N> passed, 0 failed`.
````

Then add one `### L<n>` entry per row of Step 5, in the same shape, pasting
the real `FAIL` lines. Fill `<N>` and `<sha>` from the actual runs. Do not
leave the placeholders.

- [ ] **Step 7: Commit**

```bash
git add tests/guix-env-launcher.sh scripts/guix-env .plans/guix-env-mutation-log.md
git commit -m "feat(guix): scripts/guix-env launcher with host-side dry-run tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V3R9HBFZGRtF7CTkPfFcCh"
```

---

### Task 2: The pinned environment and `make check-guix`

**Files:**
- Create: `channels.scm`
- Create: `manifest.scm`
- Create: `scripts/check-guix-env` (mode `0755`)
- Modify: `Makefile`: the `.PHONY` line (line 81), and a new target after
  `check-site`

**Interfaces:**
- Consumes:
  - `scripts/guix-env CMD…` (Task 1).
  - `tests/preflight.sps` output. On success, `make build` prints exactly:
    ```
    cmark-gfm 0.29.0.gfm.13
      core: <path>
      ext:  <path>
    ```
    On failure it prints `chez-cmark-gfm: no usable libcmark-gfm (<reason>)`
    and exits 1.
- Produces: `make check-guix`. Inside the container, `CHEZ_CMARK_GFM_LIBS`
  names the two versioned store libraries, and `chez` runs Guix's `scheme`.
  Task 3's mutations edit `manifest.scm`'s `native-search-paths`
  `file-pattern` and `chez-command`'s builder.

This task is a TDD ladder. The check comes first, and each manifest step
must fail with exactly the predicted message before the next one is added.

- [ ] **Step 1: Pin Guix**

Create `channels.scm`:

```scheme
;;; The Guix revision the development environment is built from
;;; (ADR-0018). scripts/guix-env passes this to `guix time-machine`.
;;; Generated with `guix describe -f channels`, keeping only the guix
;;; channel. To bump it, change the commit and run `make check-guix`.
(list (channel
       (name 'guix)
       (url "https://git.guix.gnu.org/guix.git")
       (branch "master")
       (commit "b532aa7d0bb345aafabf6b63cbfbda45abbec091")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
```

- [ ] **Step 2: Write the in-container check**

Create `scripts/check-guix-env`, then `chmod 0755 scripts/check-guix-env`:

```sh
#!/bin/sh
# Runs INSIDE the pinned container: `make check-guix` is
#   sh tests/guix-env-launcher.sh && scripts/guix-env sh scripts/check-guix-env
# Asserts the two properties the environment exists for (spec §4), then
# runs the targets. Each failure names its assertion.
set -u

if [ -z "${GUIX_ENVIRONMENT:-}" ]; then
  echo "check-guix: FAILED not-in-environment: run this through make check-guix" >&2
  exit 2
fi

fail=0
out=$(mktemp)

if ! make build >"$out" 2>&1; then
  cat "$out"
  echo "check-guix: FAILED make-build" >&2
  exit 1
fi
cat "$out"

# Assertion 1: the library came from the store. A missing line yields an
# empty path, which fails the same way.
for role in core ext; do
  p=$(sed -n "s/^  $role: *//p" "$out")
  case "$p" in
    /gnu/store/*) echo "check-guix: ok store-library ($role: $p)" ;;
    *) echo "check-guix: FAILED store-library: $role is '$p', expected a /gnu/store/ path" >&2
       fail=1 ;;
  esac
done

# Assertion 2: a login shell, started the way Claude Code's Bash tool starts
# one, sees the environment's tools. Both the non-interactive and the
# interactive form, since rc files branch on $-.
for mode in -lc -lic; do
  for tool in chez scheme make git cmark-gfm; do
    p=$(bash "$mode" "command -v $tool" 2>/dev/null | tail -n 1)
    case "$p" in
      "$GUIX_ENVIRONMENT"/*)
        echo "check-guix: ok login-shell-path[$mode] ($tool: $p)" ;;
      *)
        echo "check-guix: FAILED login-shell-path[$mode]: $tool resolves to '${p:-nothing}', expected under $GUIX_ENVIRONMENT" >&2
        fail=1 ;;
    esac
  done
done

if ! make check-pins test check-purity check-install examples check-site; then
  echo "check-guix: FAILED make-targets" >&2
  fail=1
fi

rm -f "$out"
if [ "$fail" -eq 0 ]; then
  echo "check-guix: ALL CHECKS PASSED"
fi
exit "$fail"
```

- [ ] **Step 3: Add the Makefile target**

In `Makefile`, append ` check-guix` to the `.PHONY:` line (line 81). Keep
it on one physical line. Then insert after the `check-site` recipe:

```make
# Local only: no CI job runs this (ADR-0018). The launcher's own tests run
# on the host first, needing no Guix; everything after runs inside the
# pinned container, which scripts/guix-env refuses to nest.
check-guix: ## Test scripts/guix-env, then run the suites inside the pinned Guix container
	@sh tests/guix-env-launcher.sh
	@scripts/guix-env sh scripts/check-guix-env
```

Run: `make check-help`
Expected: exit 0, no output.

- [ ] **Step 4: First rung, toolchain only. Watch it fail on `chez`**

Create `manifest.scm` with the plain toolchain and neither local
definition:

```scheme
;;; Development environment for chez-cmark-gfm (ADR-0018).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and
;;; runs this manifest in a container. Plain `guix shell` also loads this
;;; file, but against whatever Guix you have pulled: the unpinned path.

(specifications->manifest
 '("chez-scheme" "cmark-gfm"
   ;; What the Makefile shells out to. The container has nothing else.
   "bash" "coreutils" "make" "git" "grep" "sed" "gawk" "findutils"
   "diffutils" "nss-certs"
   "cmake" "gcc-toolchain"            ; make vendor
   "valgrind"                         ; make test-memory
   "openssh" "github-cli" "gnupg"))   ; push, PRs, commit signing
```

Run: `make check-guix`
Expected:
- The launcher tests pass.
- Guix builds the profile. The first run may take minutes.
- The output has a shell error naming `chez` (`chez: not found` or `chez:
  command not found`, depending on `/bin/sh`), then `check-guix: FAILED
  make-build`, and make exits non-zero. Any other failure (a manifest
  error, a Guix download failure) is not this rung's red. Fix it and rerun.

- [ ] **Step 5: Second rung, add the `chez` wrapper. Watch it fail on discovery**

Replace `manifest.scm` with:

```scheme
;;; Development environment for chez-cmark-gfm (ADR-0018).
;;;
;;; Enter it with scripts/guix-env, which pins Guix to channels.scm and
;;; runs this manifest in a container. Plain `guix shell` also loads this
;;; file, but against whatever Guix you have pulled: the unpinned path.

(use-modules (guix packages)
             (guix profiles)
             (guix gexp)
             (guix build-system trivial)
             ((guix licenses) #:prefix license:)
             (gnu packages bash)
             (gnu packages chez))

;; A script, not a symlink: Chez derives its boot-file name from the name
;; it was invoked by, so a `chez` symlink looks for chez.boot and aborts.
(define chez-command
  (package
    (name "chez-command")
    (version (package-version chez-scheme))
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:builder
      #~(let ((bin (string-append #$output "/bin")))
          (mkdir #$output)
          (mkdir bin)
          (call-with-output-file (string-append bin "/chez")
            (lambda (port)
              (format port "#!~a~%exec ~a \"$@\"~%"
                      #$(file-append bash-minimal "/bin/sh")
                      #$(file-append chez-scheme "/bin/scheme"))))
          (chmod (string-append bin "/chez") #o555))))
    (home-page "https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm")
    (synopsis "@command{chez} for the Makefile's default @code{CHEZ}")
    (description "Runs Guix's @command{scheme} under the name the
chez-cmark-gfm Makefile expects.")
    (license license:bsd-3)))

(concatenate-manifests
 (list
  (packages->manifest (list chez-command))
  (specifications->manifest
   '("chez-scheme" "cmark-gfm"
     ;; What the Makefile shells out to. The container has nothing else.
     "bash" "coreutils" "make" "git" "grep" "sed" "gawk" "findutils"
     "diffutils" "nss-certs"
     "cmake" "gcc-toolchain"            ; make vendor
     "valgrind"                         ; make test-memory
     "openssh" "github-cli" "gnupg"))))  ; push, PRs, commit signing
```

Run: `make check-guix`
Expected: output contains
`chez-cmark-gfm: no usable libcmark-gfm (not-found)`, then
`check-guix: FAILED make-build`. Discovery never searches a Guix profile.

- [ ] **Step 6: Third rung, add the search path. Watch it pass**

In `manifest.scm`, add `(guix search-paths)` and `(gnu packages markup)` to
`use-modules`. Add this definition after `chez-command`:

```scheme
;; Discovery never searches a Guix profile (ADR-0016), so the environment
;; names the pair through the documented override. The pattern matches only
;; the versioned files: the unversioned symlinks would make four entries,
;; which parse-library-override rejects as invalid-override. Adding a search
;; path leaves cmark-gfm's store item unchanged, so substitutes still apply.
(define cmark-gfm/chez-search-path
  (package
    (inherit cmark-gfm)
    (native-search-paths
     (list (search-path-specification
            (variable "CHEZ_CMARK_GFM_LIBS")
            (files '("lib"))
            (file-type 'regular)
            (file-pattern "^libcmark-gfm(-extensions)?\\.so\\.[0-9]"))))))
```

Change the manifest body: `(packages->manifest (list chez-command
cmark-gfm/chez-search-path))`, and remove `"cmark-gfm"` from the
specification list so the plain and inherited packages do not collide.

Run: `make check-guix; echo "exit=$?"`
Expected:
- `check-guix: ok store-library (core: /gnu/store/…-profile/lib/libcmark-gfm.so.0.29.0.gfm.13)` and the `ext` line.
- Ten `ok login-shell-path[…]` lines: five tools × `-lc`/`-lic`.
- `pins agree` ×3, `ALL SUITES PASSED`, the purity, install, examples and
  site checks green.
- `check-guix: ALL CHECKS PASSED`, then `exit=0`.

If `-lic` prints nothing because bash refuses to run interactively without
a TTY, change the command substitution to `bash "$mode" "command -v $tool"
</dev/null 2>/dev/null | tail -n 1`, rerun, and note it in the mutation log.

- [ ] **Step 7: Confirm the store item is unchanged**

Run: `guix time-machine -C channels.scm -- build cmark-gfm` and
`scripts/guix-env sh -c 'readlink -f "$GUIX_ENVIRONMENT"/lib/libcmark-gfm.so.0.*'`
Expected: both name the same `/gnu/store/<hash>-cmark-gfm-0.29.0.gfm.13`
item. If they differ, the search path changed the derivation and forces a
local build. Record this in the mutation log either way (spec §1).

- [ ] **Step 8: Commit**

```bash
git add channels.scm manifest.scm scripts/check-guix-env Makefile
git commit -m "feat(guix): pinned manifest and make check-guix

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V3R9HBFZGRtF7CTkPfFcCh"
```

---

### Task 3: Environment mutations and one-off target runs

**Files:**
- Modify: `.plans/guix-env-mutation-log.md` (append)

**Interfaces:**
- Consumes: `make check-guix`, `manifest.scm`, `scripts/guix-env` and
  `scripts/check-guix-env` as Task 2 left them.
- Produces: evidence only. No code change unless a mutation shows an
  assertion is empty. In that case fix the check, rerun the mutation, and
  say so in the log.

Every mutation runs in a fresh scratch copy of the repo, outside the
working tree:

```sh
S=$(mktemp -d)/repo && cp -a "$PWD" "$S" && cd "$S"
# edit, then:
make check-guix 2>&1 | tee ../run.log | grep -E 'check-guix: (ok|FAILED)|no usable|chez.boot'
cd - && rm -rf "$(dirname "$S")"
```

- [ ] **Step 1: M1. Remove the search path**

In the copy's `manifest.scm`, delete the `(native-search-paths …)` form
from `cmark-gfm/chez-search-path`.
Expected: `chez-cmark-gfm: no usable libcmark-gfm (not-found)` and
`check-guix: FAILED make-build`.

- [ ] **Step 2: M2. Widen the pattern to the unversioned symlinks**

In the copy, change the file-pattern to `"^libcmark-gfm(-extensions)?\\.so"`.
Expected: `chez-cmark-gfm: no usable libcmark-gfm (invalid-override)` and
`check-guix: FAILED make-build`. Also confirm the cause:
`scripts/guix-env sh -c 'echo "$CHEZ_CMARK_GFM_LIBS"' | tr ':' '\n' | wc -l`
prints `4`.

- [ ] **Step 3: M3. Make `bin/chez` a symlink**

In the copy, replace the whole `(call-with-output-file …)` form and the
`chmod` in `chez-command`'s builder with:

```scheme
(symlink #$(file-append chez-scheme "/bin/scheme")
         (string-append bin "/chez"))
```

Expected: `cannot find compatible chez.boot in search path` and
`check-guix: FAILED make-build`.

- [ ] **Step 4: M4. Drop container mode**

In the copy's `scripts/guix-env`, change
`set -- "$@" --container --network --emulate-fhs \` to `set -- "$@" \`.
Both flags must go: `--emulate-fhs` errors without `--container`, which
would fail for the wrong reason. `--share` without `--container` is
silently ignored (verified, spec §1).
Expected on this machine: `check-guix: FAILED login-shell-path[-lic]:
scheme resolves to '/home/kishu/.guix-home/profile/bin/scheme'`, and
possibly other tools and `[-lc]`. Record exactly which tools and modes
failed. Record also that on a host whose rc files do not prepend `PATH`,
this mutation is not observable, and that is a property of the host, not a
gap in the check (spec §5.2).

- [ ] **Step 5: M5. Load a library from outside the store**

In the copy's `scripts/check-guix-env`, insert immediately before
`if ! make build >"$out" 2>&1; then`:

```sh
m5=$(mktemp -d)
cp -L "$GUIX_ENVIRONMENT"/lib/libcmark-gfm.so.0.* "$GUIX_ENVIRONMENT"/lib/libcmark-gfm-extensions.so.0.* "$m5"/
CHEZ_CMARK_GFM_LIBS="$(echo "$m5"/libcmark-gfm.so.0.*):$(echo "$m5"/libcmark-gfm-extensions.so.0.*)"
export CHEZ_CMARK_GFM_LIBS
```

Expected: `make build` succeeds (the copy is a valid pair), then
`check-guix: FAILED store-library: core is '/tmp/…/libcmark-gfm.so.0.29.0.gfm.13', expected a /gnu/store/ path`
and the same for `ext`. This breaks assertion 1 through the path it checks.

- [ ] **Step 6: Watch the clean tree go green again**

Run in the real repo: `make check-guix; echo "exit=$?"`
Expected: `check-guix: ALL CHECKS PASSED`, `exit=0`.

- [ ] **Step 7: Run the targets check-guix skips**

Run each once in the real repo, and record the tail of each:
- `scripts/guix-env make vendor`. Expected: cmake configures and builds
  `build/vendor` with no error.
- `scripts/guix-env make site`. Expected: `site: build/site ready`.
- `scripts/guix-env make test-memory`. Expected: exit 0 with no Valgrind
  error summary. This is slow, so allow it to run.

- [ ] **Step 8: Check the credential paths without spending a signature**

Run each and record the result. These cover the network and credential
shares without creating a commit or a pinentry prompt.
- `scripts/guix-env gpg --list-secret-keys --keyid-format long`.
  Expected: a `sec` line for `CC2923E50902E936049B696B9EBA259B8EAC5130`,
  which proves the host agent is reachable. If gpg errors about
  `~/.gnupg` being unwritable or not finding the agent, that is spec risk
  R3. Apply its fallback in `scripts/guix-env`, add a launcher test for it,
  and rerun Task 1's suite.
- `scripts/guix-env ssh -T git@github.com`.
  Expected: `Hi <user>! You've successfully authenticated` (ssh exits 1 by
  design).
- `scripts/guix-env gh auth status`. Expected: `Logged in to github.com`.
- `scripts/guix-env git -C . fetch --dry-run`. Expected: exit 0.

- [ ] **Step 9: Record and commit**

Append to `.plans/guix-env-mutation-log.md` an `## Environment
(make check-guix)` section with a `### M1` to `### M5` entry each, in the
Task 1 shape (Guards / Mutation / Result with the pasted lines / Clean
rerun). Add a `## One-off runs` section with the Step 7 and Step 8 results
and Task 2 Step 7's store-item comparison.

```bash
git add .plans/guix-env-mutation-log.md
git commit -m "docs(plans): guix env mutation evidence M1-M5 and one-off runs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V3R9HBFZGRtF7CTkPfFcCh"
```

---

### Task 4: Documentation, ADR-0018, traps

**Files:**
- Create: `.plans/decisions/0018-guix-development-environment.md`
- Modify: `docs/building.md` (new section after "Requirements for
  development", before "The targets")
- Modify: `CONTRIBUTING.md` (Setup section, after the code block)
- Modify: `CHANGELOG.md` (`## Unreleased` → `### Added`, first bullet)
- Modify: `AGENTS.md` (append two bullets to "Traps this repo has already hit")

**Interfaces:**
- Consumes: the behaviour of Tasks 1–3, and the Task 3 log for concrete
  numbers.
- Produces: the anchor `#guix-development-environment` in
  `docs/building.md`, which `CONTRIBUTING.md` and ADR-0018 link to.

- [ ] **Step 1: Write ADR-0018**

Create `.plans/decisions/0018-guix-development-environment.md`:

```markdown
# ADR-0018: A pinned Guix container as the development environment

- **Status:** Accepted
- **Date:** 2026-09-26
- **Scope:** development tooling. No library change
- **Related:** [design spec](../2026-09-26-guix-dev-env-design.md) ·
  [ADR-0016](0016-paired-versioned-library-discovery.md) (the discovery this leaves alone) ·
  [ADR-0003](0003-linux-primary-memory-verification.md) (Valgrind is available inside)

## Context

The maintainer develops on Guix and runs Claude Code as the primary
contributor. A development environment is wanted that is the same for every
contributor and every session, and that can host an agent that commits,
signs, pushes and opens PRs. Three facts constrained it:

- Discovery searches `/usr/local/lib`, `/usr/lib/<triple>`, `/usr/lib` and
  `/usr/lib64`, never a Guix profile, so `make build` fails `not-found` in
  any Guix environment unless `CHEZ_CMARK_GFM_LIBS` is set.
- Guix names the Chez binary `scheme`, and Chez derives its boot-file name
  from the name it was invoked by, so a `chez` symlink aborts.
- Inside `guix shell --pure`, a login shell re-sources the user's rc files,
  and on the maintainer's machine these put `~/.guix-home/profile/bin` ahead
  of the environment. `scheme` then resolved to the host's copy: a pass on
  tools outside the pin.

## Decision

- **Pin with `guix time-machine -C channels.scm`.** Plain `guix shell` would
  resolve the manifest against each developer's latest `guix pull`.
- **Provision through the manifest, not a wrapper or a library change.** A
  `cmark-gfm` variant declares a search path whose pattern matches only the
  versioned libraries, so the profile itself exports the two-entry override.
  The store item is unchanged. A `chez-command` package supplies a `chez`
  wrapper script.
- **Run in `--container`, not `--pure`.** The container's `HOME` is empty,
  so no rc file can clobber `PATH`, and that is decided by files in this
  repository rather than by each contributor's dotfiles.
- **One launcher, `scripts/guix-env`**, used by people (`bash` with no
  arguments), by `make check-guix`, and by Claude (`claude` mode). What is
  verified is what is run.
- **Credentials are shared deliberately and listed:** git config files, the
  gpg-agent socket and public keyring, the SSH agent socket, `~/.config/gh`,
  and, in `claude` mode only, `~/.claude` and `~/.claude.json`. Private key
  files are never exposed.
- **Verification is local.** `make check-guix` asserts that the library came
  from `/gnu/store` and that a login shell resolves the environment's tools.
  No CI job runs it.

Rejected:

- **Teach discovery to search `$GUIX_ENVIRONMENT/lib`.** Reopens ADR-0016 to
  serve a development convenience.
- **A wrapper that exports the variables.** A bare `guix shell -m
  manifest.scm` would then be a broken environment.
- **`--pure` plus rc-file guards.** Correct only for contributors whose
  dotfiles carry the guard. This repository cannot enforce that.

## Consequences

- **x86_64-linux only.** Guix builds `chez-scheme` and `cmark-gfm` for
  `x86_64-linux` and `i686-linux` alone. macOS and arm64 development is
  unchanged.
- **Nothing automated notices rot.** A broken pin or manifest surfaces the
  next time someone runs `make check-guix`. This was accepted to keep CI
  spend where #18 left it.
- **The container confines the filesystem, not GitHub.** An agent inside
  holds the maintainer's GitHub credentials through the agent sockets and
  `gh`.
- **The `--container` half of the PATH assertion is host-dependent.** On a
  host whose rc files do not prepend `PATH`, dropping `--container` changes
  nothing observable (mutation M4, `.plans/guix-env-mutation-log.md`).
- **A pin bump can bring a `cmark-gfm` outside the supported range.** The
  existing post-load version check in `native.sls` fails `make build`, which
  fails `check-guix`.
```

- [ ] **Step 2: Add the `docs/building.md` section**

Insert before the line `## The targets`:

````markdown
## Guix development environment

On x86_64 Linux with [Guix](https://guix.gnu.org) installed, one command
gives you every tool this page needs, at versions pinned by the repository:

```sh
scripts/guix-env              # an interactive shell in the container
scripts/guix-env make test    # or run one command
```

Inside, every target works as written: no `CHEZ=`, and no
`CHEZ_CMARK_GFM_LIBS`. The environment sets both. `make build` reports a
cmark-gfm from `/gnu/store`.

What to expect:

- **The first run is slow.** `guix time-machine` builds the Guix revision
  pinned in `channels.scm`, then the profile. Later runs reuse both.
- **It is a container.** You see the repository (at its usual path),
  `/gnu/store`, and nothing else of your home directory except the pieces
  shared in below. `HOME` is empty, so your aliases and prompt are absent.
  That is deliberate: your shell's startup files could otherwise put your
  own tools ahead of the pinned ones.
- **There is no editor inside.** Edit on the host. The repository is the
  same directory inside and out, so use the container shell to run things.
- **Shared in, when they exist on your machine:** your git config
  (including `includeIf` files), your gpg-agent and public keyring for
  signed commits, your SSH agent, and `~/.config/gh`. Private key files are
  never shared: signing and authentication go through your host agents,
  and pinentry appears on your desktop as usual. Anything you don't have is
  skipped, and you just can't push from inside.
- **`scripts/guix-env` refuses to nest.** Run commands directly once
  you're inside.

`make check-guix` (run it on the host, not inside) tests the launcher,
then proves inside the container that the library came from the store and
that a login shell resolves `chez`, `scheme`, `make`, `git` and `cmark-gfm`
from the environment. It then runs `build`, `check-pins`, `test`,
`check-purity`, `check-install`, `examples` and `check-site`. No CI job runs
it (ADR-0018), so run it after touching `channels.scm`, `manifest.scm` or
`scripts/`.

**Bumping the pin:** change the commit in `channels.scm` (take it from `guix
describe -f channels`) and run `make check-guix`. If the new Guix ships a
cmark-gfm outside the supported range, `make build` says so.

Plain `guix shell` in this directory also loads `manifest.scm`, but against
whatever Guix you last pulled. That environment is unpinned.

### Running Claude Code in the environment

```sh
scripts/guix-env claude
```

runs your installed Claude Code inside the same container, with
`~/.claude` and `~/.claude.json` shared so your login, settings and project
memory carry over. The auto-updater is disabled inside because the binary
is mounted read-only; update from a normal shell. Only this mode mounts
Claude's files.

The first time, or after changing `scripts/guix-env` or `manifest.scm`,
check the session by hand:

1. It starts logged in.
2. Ask it to run `command -v scheme chez cmark-gfm` and
   `echo "$CHEZ_CMARK_GFM_LIBS"`. Every path is under `/gnu/store`.
3. Ask it to make a commit. It is signed:
   `git log --show-signature -1` reports a good signature.
4. `git push --dry-run` and `gh auth status` both succeed.
5. Quit, relaunch, and it is still logged in with your settings.
````

- [ ] **Step 3: Point CONTRIBUTING.md at it**

In `CONTRIBUTING.md`, after the paragraph that begins ``--recursive` is
never necessary``, add:

```markdown
On x86_64 Linux with Guix, `scripts/guix-env` gives you a pinned container
with every prerequisite, and `make test` works in it as written. See
[docs/building.md](docs/building.md#guix-development-environment).
```

- [ ] **Step 4: CHANGELOG entry**

In `CHANGELOG.md`, as the first bullet under `## Unreleased` → `### Added`:

```markdown
- A pinned Guix development environment for x86_64 Linux.
  `scripts/guix-env` opens a container shell, runs a command, or starts
  Claude Code in it, with the toolchain pinned by `channels.scm` and
  `manifest.scm`. `make check-guix` (local, not CI) proves the library loads
  from `/gnu/store` and that a login shell sees only the pinned tools. See
  [docs/building.md](docs/building.md#guix-development-environment) and
  ADR-0018.
```

- [ ] **Step 5: Two AGENTS.md traps**

Append to the end of the "Traps this repo has already hit" list in
`AGENTS.md`:

```markdown
* **Chez finds its boot file from the name it was invoked by.** A `chez`
  symlink to Guix's `scheme` aborts with `cannot find compatible chez.boot in
  search path "%x:%x/../lib/csv%v/%m:…"`: `%x` is the invoked name, so it
  looks for `chez.boot`, which does not exist. An alias for the Chez binary
  must be a script that `exec`s it by its real name. That is why
  `manifest.scm`'s `chez-command` is a script.
* **`guix shell --pure` does not stop a login shell from rebuilding `PATH`.**
  `--pure` clears the environment once, at entry. A later `bash -l`, which
  is how Claude Code's Bash tool starts its shells, re-sources
  `~/.bash_profile` and `~/.profile`. On the maintainer's machine those put
  `~/.guix-home/profile/bin` ahead of the environment, so `scheme` resolved
  to the host's copy while everything still passed. `scripts/guix-env` uses
  `--container`, whose `HOME` is empty, and `make check-guix` asserts the
  resolution from a login shell. `guix shell --check` diagnoses the same
  thing for a `--pure` shell.
```

- [ ] **Step 6: Check the docs build**

Run: `scripts/guix-env make check-site`
Expected: green. The new section's heading must resolve as the anchor
`guix-development-environment`, and the site check fails on a broken link.

- [ ] **Step 7: Commit**

```bash
git add .plans/decisions/0018-guix-development-environment.md docs/building.md CONTRIBUTING.md CHANGELOG.md AGENTS.md
git commit -m "docs: Guix development environment, ADR-0018, two traps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V3R9HBFZGRtF7CTkPfFcCh"
```

---

### Task 5: Claude smoke check (the maintainer runs it)

**Files:**
- Modify: `.plans/guix-env-mutation-log.md` (append `## Claude smoke check`)
- Possibly modify: `scripts/guix-env`, `manifest.scm`,
  `tests/guix-env-launcher.sh`, if a spec risk materialises

**Interfaces:**
- Consumes: `scripts/guix-env claude` and the five-step checklist in
  `docs/building.md`.
- Produces: the recorded result. Any fallback is applied with a launcher
  test and a mutation.

The implementer cannot run this. The auto-mode classifier blocks starting a
nested Claude session, and the check needs the maintainer's credentials and
pinentry.

- [ ] **Step 1: Hand the checklist to the user**

Ask the user to run `scripts/guix-env claude` in a separate terminal, work
through the five steps under "Running Claude Code in the environment" in
`docs/building.md`, and report each result verbatim.

- [ ] **Step 2: Apply a fallback only for a failure actually reported**

| Reported symptom | Spec risk | Change |
|---|---|---|
| Claude cannot save settings, `EBUSY` on `~/.claude.json`, or loses state on relaunch | R1 | In claude mode, stop sharing `~/.claude.json`, and set `CLAUDE_CONFIG_DIR=$HOME/.claude` plus `--preserve=^CLAUDE_CONFIG_DIR$`. Add launcher test T15 asserting both lines in claude mode and neither in command mode, and a mutation that removes the preserve |
| `claude` fails to start: missing library or tool (e.g. `rg: not found`) | R2 | Add the named package to `manifest.scm`'s specification list, and rerun `make check-guix` |
| Commit signing fails inside: gpg lock or agent errors | R3 | Should already be handled by Task 3 Step 8. If not, apply the `GNUPGHOME` fallback from spec §3 with a launcher test |

For any change, rerun `make check-guix` and `sh tests/guix-env-launcher.sh`
to green, and ask the user to repeat the failing checklist step.

- [ ] **Step 3: Record and commit**

Append `## Claude smoke check` to the mutation log: the date, the Claude
Code version (from the exposed `versions/<v>` path), each of the five steps
with its reported result, and any fallback applied.

```bash
git add .plans/guix-env-mutation-log.md  # plus any files changed in Step 2
git commit -m "docs(plans): record the Claude smoke check in the Guix container

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V3R9HBFZGRtF7CTkPfFcCh"
```
