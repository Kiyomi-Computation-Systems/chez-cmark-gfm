#!/bin/sh
# Host-side tests for scripts/guix-env. Nothing here runs Guix: every case
# sets GUIX_ENV_DRY_RUN=1, under which the launcher prints `cd <cwd>` and
# then the guix command it would exec, one argument per line. `make
# check-guix` runs this before entering the container. Checks name
# themselves, and the exit status is non-zero if any failed.
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

# The fake HOME has a space and a non-ASCII letter in it (Review Focus 1),
# and holds every kind of credential a developer's HOME does. The container
# must receive none of them (T20): commits, pushes and GitHub access happen
# on the host.
home="$tmp/fake hôme"
mkdir -p "$home/.local/bin" "$home/.claude" "$home/.config/gh" "$home/.ssh" \
         "$home/.gnupg"
for f in .claude.json .ssh/config .ssh/known_hosts .ssh/id_ed25519 \
         .ssh/id_ed25519.pub .gnupg/pubring.kbx .gnupg/trustdb.gpg \
         gpg-agent.sock ssh-agent.sock; do
  : >"$home/$f"
done
printf '[user]\n\tname = Test\n\tsigningkey = ~/.ssh/id_ed25519.pub\n[gpg]\n\tformat = ssh\n' \
  >"$home/.gitconfig"
# A gh whose `auth token` succeeds, and a claude on PATH.
printf '#!/bin/sh\n[ "$1 $2" = "auth token" ] && echo fake-token-5f3a\n' >"$home/.local/bin/gh"
printf '#!/bin/sh\n' >"$home/.local/bin/claude"
chmod +x "$home/.local/bin/gh" "$home/.local/bin/claude"

# run [VAR=value...] LAUNCHER [ARG...]
# Runs from $cwd in a scrubbed environment. Later VAR=value pairs override
# the defaults. stdout -> $tmp/out, stderr -> $tmp/err, exit -> $status.
cwd=$root
run() {
  status=999
  ( cd "$cwd" && env -i HOME="$home" PATH="$home/.local/bin:$PATH" \
      GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
      GUIX_ENV_DRY_RUN=1 \
      SSH_AUTH_SOCK="$home/ssh-agent.sock" \
      GNUPGHOME="$home/.gnupg" \
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
check "T1 container flag" has --container
check "T1 network flag" has --network
# FHS emulation puts the pinned library at /usr/lib, the only place
# discovery can find it with CHEZ_CMARK_GFM_LIBS unset -- which is exactly
# how `make check-install` probes the install contract.
check "T1 fhs flag" has --emulate-fhs
check "T1 no-args ends in -- bash" [ "$(tail_lines 2)" = "--|bash|" ]

# T2: arguments pass through verbatim, spaces and dollars included.
run "$launcher" make "a b" '$HOME'
check "T2 args pass through verbatim" \
  [ "$(tail_lines 4)" = '--|make|a b|$HOME|' ]

# T3: `claude` is an ordinary command, with no mode of its own.
run "$launcher" claude --resume
check "T3 claude: exits 0" [ "$status" -eq 0 ]
check "T3 claude: passed through unresolved" \
  [ "$(tail_lines 3)" = "--|claude|--resume|" ]

# T20: nothing from HOME, and no agent or token, enters the container, in
# any mode. The fixture above has all of them on offer.
for args in "make test" "claude" ""; do
  # shellcheck disable=SC2086
  run "$launcher" $args
  label=${args:-no-args}
  check "T20 [$label] no --share" lacks "--share"
  check "T20 [$label] no --expose" lacks "--expose"
  check "T20 [$label] nothing from HOME" lacks "$home"
  check "T20 [$label] no agent socket" lacks "SSH_AUTH_SOCK"
  check "T20 [$label] no GH_TOKEN" lacks "GH_TOKEN"
done

# T7: refuse to nest (Review Focus 4).
run GUIX_ENVIRONMENT=/gnu/store/fake-profile "$launcher" make test
check "T7 nested: exit 2" [ "$status" -eq 2 ]
check "T7 nested: names GUIX_ENVIRONMENT" grep -Fq "/gnu/store/fake-profile" "$tmp/err"
check "T7 nested: prints no command" [ ! -s "$tmp/out" ]

# T14: launched by relative path from a subdirectory, the container still
# gets the repo root (Review Focus 2).
cwd=$root/docs
run ../scripts/guix-env make test
cwd=$root
check "T14 subdirectory: exits 0" [ "$status" -eq 0 ]
check "T14 subdirectory: runs from the repo root" [ "$(lines 1p)" = "cd $root|" ]

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
