#!/bin/sh
# Host-side tests for scripts/guix-env. Nothing here runs Guix: every case
# sets GUIX_ENV_DRY_RUN=1, under which the launcher prints `cd <cwd>` and
# then the guix command it would exec, one argument per line. Each case
# runs a copy of the launcher in a fake tree, so that whether this checkout
# is a worktree changes nothing. `make check-guix` runs this before
# entering the container. Checks name themselves, and the exit status is
# non-zero if any failed.
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
err_lines() { tr '\n' '|' <"$tmp/err"; }

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

# Fake trees live under a path with a space in it, as a checkout's may.
trees="$tmp/tr ees"

# tree DIR: a copy of the launcher at DIR/scripts/guix-env, so that DIR is
# the root it computes. Nothing else of the repository is needed.
tree() {
  mkdir -p "$1/scripts"
  cp "$launcher" "$1/scripts/guix-env"
}

# A main checkout, whose .git is a directory, and the git directories of
# the worktrees below, each naming the common directory as git does.
main=$trees/main
tree "$main"
mkdir -p "$main/docs" "$main/.git/worktrees/out" "$main/.git/worktrees/in" \
  "$main/.git/worktrees/rel" "$main/.git/worktrees/abs"
: >"$main/.git/HEAD"
for w in out in rel; do printf '../..\n' >"$main/.git/worktrees/$w/commondir"; done
printf '%s\n' "$main/.git" >"$main/.git/worktrees/abs/commondir"

# worktree DIR GITDIR: a linked worktree at DIR whose .git file names GITDIR.
worktree() {
  tree "$1"
  printf 'gitdir: %s\n' "$2" >"$1/.git"
}

# run [VAR=value...] LAUNCHER [ARG...]
# Runs from $cwd in a scrubbed environment. Later VAR=value pairs override
# the defaults. stdout -> $tmp/out, stderr -> $tmp/err, exit -> $status.
cwd=$main
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

prefix="guix|time-machine|-C|channels.scm|--|shell|-m|manifest.scm|--container|--network|--emulate-fhs|"
prefix=$prefix'--preserve=^(TERM|COLORTERM|LANG)$|'

# T1: no arguments means an interactive bash, behind the pinned prefix.
run "$main/scripts/guix-env"
check "T1 no-args exits 0" [ "$status" -eq 0 ]
check "T1 no-args runs from the repo root" [ "$(lines 1p)" = "cd $main|" ]
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
check "T1 main checkout: the whole command" \
  [ "$(lines '1,$p')" = "cd $main|$prefix--|bash|" ]

# T2: arguments pass through verbatim, spaces and dollars included.
run "$main/scripts/guix-env" make "a b" '$HOME'
check "T2 args pass through verbatim" \
  [ "$(tail_lines 4)" = '--|make|a b|$HOME|' ]

# T3: `claude` is an ordinary command, with no mode of its own.
run "$main/scripts/guix-env" claude --resume
check "T3 claude: exits 0" [ "$status" -eq 0 ]
check "T3 claude: passed through unresolved" \
  [ "$(tail_lines 3)" = "--|claude|--resume|" ]

# T20: nothing from HOME, and no agent or token, enters the container, in
# any mode. The fixture above has all of them on offer. A main checkout's
# .git is inside it, so nothing more is shared.
for args in "make test" "claude" ""; do
  # shellcheck disable=SC2086
  run "$main/scripts/guix-env" $args
  label=${args:-no-args}
  check "T20 [$label] no --share" lacks "--share"
  check "T20 [$label] no --expose" lacks "--expose"
  check "T20 [$label] nothing from HOME" lacks "$home"
  check "T20 [$label] no agent socket" lacks "SSH_AUTH_SOCK"
  check "T20 [$label] no GH_TOKEN" lacks "GH_TOKEN"
done

# T7: refuse to nest (Review Focus 4).
run GUIX_ENVIRONMENT=/gnu/store/fake-profile "$main/scripts/guix-env" make test
check "T7 nested: exit 2" [ "$status" -eq 2 ]
check "T7 nested: names GUIX_ENVIRONMENT" grep -Fq "/gnu/store/fake-profile" "$tmp/err"
check "T7 nested: prints no command" [ ! -s "$tmp/out" ]

# T14: launched by relative path from a subdirectory, the container still
# gets the repo root (Review Focus 2).
cwd=$main/docs
run ../scripts/guix-env make test
cwd=$main
check "T14 subdirectory: exits 0" [ "$status" -eq 0 ]
check "T14 subdirectory: runs from the repo root" [ "$(lines 1p)" = "cd $main|" ]

# T21: a linked worktree outside the main checkout shares the main
# repository's .git, the common directory, and only that. The flag comes
# before the `--` that ends guix's options.
wt_cmd() {  # ROOT SHARED
  printf 'cd %s|%s--share=%s|--|make|test|' "$1" "$prefix" "$2"
}
worktree "$trees/out" "$main/.git/worktrees/out"
cwd=$trees/out
run "$trees/out/scripts/guix-env" make test
check "T21 worktree outside: exit 0" [ "$status" -eq 0 ]
check "T21 worktree outside: the whole command" \
  [ "$(lines '1,$p')" = "$(wt_cmd "$trees/out" "$main/.git")" ]

# T22: one inside the main checkout's tree, as `.claude/worktrees/` puts
# them, still needs the share: the container shares only the worktree.
worktree "$main/.claude/worktrees/in" "$main/.git/worktrees/in"
cwd=$main/.claude/worktrees/in
run "$main/.claude/worktrees/in/scripts/guix-env" make test
check "T22 worktree inside main: the whole command" \
  [ "$(lines '1,$p')" = "$(wt_cmd "$main/.claude/worktrees/in" "$main/.git")" ]

# T23: a relative gitdir (worktree.useRelativePaths) resolves from the
# worktree's root, and an absolute commondir is taken as it is.
worktree "$trees/rel" "../main/.git/worktrees/rel"
cwd=$trees/rel
run "$trees/rel/scripts/guix-env" make test
check "T23 relative gitdir: shares the common directory" \
  [ "$(lines '1,$p')" = "$(wt_cmd "$trees/rel" "$main/.git")" ]
worktree "$trees/abs" "$main/.git/worktrees/abs"
cwd=$trees/abs
run "$trees/abs/scripts/guix-env" make test
check "T23 absolute commondir: shares the common directory" \
  [ "$(lines '1,$p')" = "$(wt_cmd "$trees/abs" "$main/.git")" ]

# T24: a separate git directory (`git init --separate-git-dir`) has no
# commondir: the git directory itself is shared. One inside the tree is
# shared already, and adds nothing.
mkdir -p "$trees/separate-git"
: >"$trees/separate-git/HEAD"
worktree "$trees/sep" "$trees/separate-git"
cwd=$trees/sep
run "$trees/sep/scripts/guix-env" make test
check "T24 separate git dir: shares it" \
  [ "$(lines '1,$p')" = "$(wt_cmd "$trees/sep" "$trees/separate-git")" ]
mkdir -p "$trees/own/.real-git"
: >"$trees/own/.real-git/HEAD"
worktree "$trees/own" ".real-git"
cwd=$trees/own
run "$trees/own/scripts/guix-env" make test
check "T24 git dir inside the tree: shares nothing more" lacks --share
check "T24 git dir inside the tree: exit 0" [ "$status" -eq 0 ]

# T25: a .git file the launcher cannot follow is refused, naming it, and
# nothing runs.
worktree "$trees/nogitdir" "unused"
printf 'not a gitdir line\n' >"$trees/nogitdir/.git"
cwd=$trees/nogitdir
run "$trees/nogitdir/scripts/guix-env" make test
check "T25 no gitdir line: exit 2" [ "$status" -eq 2 ]
check "T25 no gitdir line: says why" \
  [ "$(err_lines)" = "guix-env: $trees/nogitdir/.git is a file with no gitdir line|" ]
check "T25 no gitdir line: prints no command" [ ! -s "$tmp/out" ]
worktree "$trees/gone" "$tmp/no-such-git-dir"
cwd=$trees/gone
run "$trees/gone/scripts/guix-env" make test
check "T25 missing git dir: exit 2" [ "$status" -eq 2 ]
check "T25 missing git dir: says why" \
  [ "$(err_lines)" = "guix-env: $trees/gone/.git names $tmp/no-such-git-dir, whose common directory $tmp/no-such-git-dir does not exist|" ]
check "T25 missing git dir: prints no command" [ ! -s "$tmp/out" ]

# T26: a .git file that names something other than a git directory, or a
# directory holding the checkout or HOME, is refused, saying which, and
# nothing runs: a hand-edited one must not share a parent of the
# repository. Each named directory has a HEAD, so only the rule under test
# can refuse it.
refused_share() {  # LABEL TREE GITDIR EXPECTED-STDERR
  worktree "$2" "$3"
  cwd=$2
  run "$2/scripts/guix-env" make test
  check "T26 $1: exit 2" [ "$status" -eq 2 ]
  check "T26 $1: says why" [ "$(err_lines)" = "$4|" ]
  check "T26 $1: prints no command" [ ! -s "$tmp/out" ]
}
mkdir -p "$trees/up"
: >"$trees/up/HEAD"
refused_share "the checkout's parent" "$trees/up/inner" ".." \
  "guix-env: refusing to share $trees/up, named by $trees/up/inner/.git: it holds $trees/up/inner"
: >"$home/HEAD"
refused_share "HOME itself" "$trees/home" "$home" \
  "guix-env: refusing to share $home, named by $trees/home/.git: it holds $home"
# A HOME whose parent does not hold the trees, or the checkout's own rule
# would refuse it first.
saved_home=$home
home=$tmp/h2/home
mkdir -p "$home"
: >"$tmp/h2/HEAD"
refused_share "HOME's parent" "$trees/home-parent" "$tmp/h2" \
  "guix-env: refusing to share $tmp/h2, named by $trees/home-parent/.git: it holds $home"
home=$saved_home
mkdir -p "$trees/a=b/.git"
: >"$trees/a=b/.git/HEAD"
refused_share "a path with =" "$trees/eq" "$trees/a=b/.git" \
  "guix-env: refusing to share $trees/a=b/.git, named by $trees/eq/.git: guix would split it at the ="
mkdir -p "$trees/not-git"
refused_share "a directory with no HEAD" "$trees/nohead" "$trees/not-git" \
  "guix-env: $trees/nohead/.git names $trees/not-git, whose common directory $trees/not-git is not a git directory"
cwd=$main

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
