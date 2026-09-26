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

# The fake HOME has a space and a non-ASCII letter in it: every path the
# launcher builds must survive quoting (Review Focus 1), and git quotes
# non-ASCII paths in its plain --show-origin output.
home="$tmp/fake hôme"
versions="$home/.local/share/claude/versions"
mkdir -p "$versions" "$home/.local/bin" "$home/.claude" "$home/.config/gh" \
         "$home/.ssh" "$home/.gnupg"
printf '#!/bin/sh\n' >"$versions/9.9.9"
chmod +x "$versions/9.9.9"
ln -s "$versions/9.9.9" "$home/.local/bin/claude"
# A fake gh whose `auth token` succeeds; T16 swaps in one that fails.
gh_ok() { printf '#!/bin/sh\n[ "$1 $2" = "auth token" ] && echo fake-token-5f3a\n' >"$home/.local/bin/gh"; chmod +x "$home/.local/bin/gh"; }
gh_fails() { printf '#!/bin/sh\nexit 1\n' >"$home/.local/bin/gh"; chmod +x "$home/.local/bin/gh"; }
gh_ok
for f in .claude.json .ssh/config .ssh/known_hosts \
         .gnupg/pubring.kbx .gnupg/trustdb.gpg gpg-agent.sock ssh-agent.sock; do
  : >"$home/$f"
done
# Key files carry real-looking first lines: the launcher decides what to
# mount by content, and must never mount a private key.
pubkey='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFake test'
printf '%s\n' "$pubkey" >"$home/.ssh/signing.pub"
printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' 'b3BlbnNzaC1rZXktdjEAAAAA' \
  '-----END OPENSSH PRIVATE KEY-----' >"$home/.ssh/id_test"
printf '%s\n' "$pubkey" >"$home/.ssh/id_test.pub"
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
# The openpgp fixture names the same .pub file the ssh one does, so only the
# format can decide whether it is exposed: T9's "no ssh signing key" would
# otherwise pass for want of a file, not because of the format.
signing openpgp "~/.ssh/signing.pub"

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
check "T1 no-args ends in -- bash" [ "$(tail_lines 4)" = "--|sh|scripts/guix-env-init|bash|" ]

# T2: arguments pass through verbatim, spaces and dollars included.
run "$launcher" make "a b" '$HOME'
check "T2 args pass through verbatim" \
  [ "$(tail_lines 6)" = '--|sh|scripts/guix-env-init|make|a b|$HOME|' ]

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
# ~/.ssh/config is deliberately NOT exposed: personal configs name host-only
# things (IdentityFile private keys, which never enter; other agents'
# sockets), and with them ssh inside never offers the shared agent's key.
check "T11 ssh config not exposed" lacks "--expose=$home/.ssh/config"
check "T11 known_hosts exposed" has "--expose=$home/.ssh/known_hosts"

# T13a: gh config shared when present.
# Read-only: GH_TOKEN carries the credential, and a writable config would
# let the container plant gh aliases the host then runs.
check "T13 gh config exposed read-only" has "--expose=$home/.config/gh"
check "T13 gh config not shared read-write" lacks "--share=$home/.config/gh"

# T15: every command enters through guix-env-init, which fixes the modes of
# the mount points guix creates (ssh and gpg reject group-writable dirs).
check "T15 command enters via guix-env-init" \
  [ "$(grep -n -Fx -- '--' "$tmp/out" | tail -n 1 | cut -d: -f1)" -eq \
    "$(( $(grep -n -Fx 'scripts/guix-env-init' "$tmp/out" | cut -d: -f1) - 2 ))" ]

# T16a: a working `gh auth token` is passed as GH_TOKEN by name only: the
# token itself must never appear on the printed (or real) command line.
check "T16 GH_TOKEN preserved" has '--preserve=^GH_TOKEN$'
check "T16 token not on the command line" lacks "fake-token-5f3a"

# T16b: gh present but not logged in: nothing to pass.
gh_fails
run "$launcher" make test
check "T16 gh fails: exits 0" [ "$status" -eq 0 ]
check "T16 gh fails: no GH_TOKEN" lacks "GH_TOKEN"
gh_ok

# T4: claude mode resolves the symlink and adds Claude's shares.
run "$launcher" claude --resume
check "T4 claude exits 0" [ "$status" -eq 0 ]
check "T4 ~/.claude shared" has "--share=$home/.claude"
check "T4 ~/.claude.json shared" has "--share=$home/.claude.json"
check "T4 binary directory exposed" has "--expose=$versions"
check "T4 DISABLE_AUTOUPDATER preserved" has '--preserve=^DISABLE_AUTOUPDATER$'
check "T4 runs the resolved binary with its args" \
  [ "$(tail_lines 5)" = "--|sh|scripts/guix-env-init|$versions/9.9.9|--resume|" ]

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
signing openpgp "~/.ssh/signing.pub"

# T17: git allows user.signingkey to name the PRIVATE key for ssh format.
# It must never be mounted; its .pub is, and without one, nothing is.
signing ssh "~/.ssh/id_test"
run "$launcher" make test
check "T17 private signing key not exposed" [ "$(grep -cFx -- "--expose=$home/.ssh/id_test" "$tmp/out")" -eq 0 ]
check "T17 its .pub exposed instead" has "--expose=$home/.ssh/id_test.pub"
mv "$home/.ssh/id_test.pub" "$tmp/id_test.pub.aside"
run "$launcher" make test
check "T17 no .pub: exits 0" [ "$status" -eq 0 ]
check "T17 no .pub: nothing of the key mounted" lacks "id_test"
mv "$tmp/id_test.pub.aside" "$home/.ssh/id_test.pub"
signing openpgp "~/.ssh/signing.pub"

# T18: the repo's own config is writable from inside the container, so
# nothing in it may choose what the next launch mounts. A launcher copy in a
# throwaway repo whose local config forges an origin line inside a
# multi-line value, includes a host file, and names a signing key.
secret="$tmp/host-secret"; printf 'x\n' >"$secret"
inc="$tmp/host-included.gitconfig"; printf '[x]\n\ty = 1\n' >"$inc"
lkey="$tmp/local-signing.pub"; printf '%s\n' "$pubkey" >"$lkey"
repo="$tmp/repo"
mkdir -p "$repo/scripts"
cp "$launcher" "$repo/scripts/guix-env"
git init -q "$repo"
git -C "$repo" config forged.value "$(printf 'x\nfile:%s\tz' "$secret")"
git -C "$repo" config include.path "$inc"
git -C "$repo" config gpg.format ssh
git -C "$repo" config user.signingkey "$lkey"
cwd=$repo
run "$repo/scripts/guix-env" make test
cwd=$root
check "T18 local config: exits 0" [ "$status" -eq 0 ]
check "T18 forged origin line not exposed" lacks "$secret"
check "T18 local include not exposed" lacks "$inc"
check "T18 local signing key not exposed" lacks "$lkey"
check "T18 global config still exposed" has "--expose=$home/.gitconfig"
check "T18 global signing format still decides" has "--share=$home/gpg-agent.sock"

# T12: a stale SSH_AUTH_SOCK is skipped, not an error (Review Focus 3).
run SSH_AUTH_SOCK="$home/no-such.sock" "$launcher" make test
check "T12 stale agent: exits 0" [ "$status" -eq 0 ]
check "T12 stale agent: not shared" lacks "no-such.sock"
check "T12 stale agent: not preserved" lacks '--preserve=^SSH_AUTH_SOCK$'

# T13b: no gh config, no share.
rmdir "$home/.config/gh"
run "$launcher" make test
check "T13 no gh config: exits 0" [ "$status" -eq 0 ]
check "T13 no gh config: not mounted" lacks "$home/.config/gh"
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
