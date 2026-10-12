# scripts/guix-env in a linked worktree: mutation log

A linked worktree's `.git` is a file naming a directory inside the main
repository's `.git`. The container shared only the worktree, so git inside
found no repository. The fix ports chez-libuv's launcher block, which
shares the common directory, and its launcher tests.

## Before

In a linked worktree of origin/main (543127c), on x86_64 Linux:

- `scripts/guix-env sh -c 'git rev-parse --show-toplevel'` printed `fatal:
  not a git repository: (null)` and exited 128.
- `make check-guix` passed its launcher test (31) and the self-test's
  environment assertions, then failed `make-targets`: `check-pins` hit
  `fatal: not a git repository: (null)` three times.

## After

In the same worktree, `make check-guix`: the launcher test passed (61), and
so did every self-test assertion. `isolated-home` named the worktree and
the main repository's `.git`, and `git-reads-repo` named both. `check-pins`,
`test`, `check-purity`, `check-install`, `examples` and `check-site` all
passed: "ALL CHECKS PASSED".

## The launcher test

`tests/guix-env-launcher.sh` runs copies of the launcher in fake trees,
as chez-libuv's does, so its rows no longer depend on whether the checkout
running them is a worktree. Its existing rows (T1-T3, T7, T14, T20) are
unchanged apart from the tree they run in, and T1 gains a whole-command
row. T21-T26 are new.

Main's launcher, in a copy outside the repository: the 35 existing rows
pass, and the 26 new ones fail by name. The fixed launcher passes all 61.

Mutants, each applied to the fixed launcher in that copy:

| # | Mutation | Failed, by name |
|---|---|---|
| L1 | the `--share` never added | T21, T22, T23 (both), T24 separate git dir |
| L2 | `--share` placed after the `--` | the same five |
| L3 | a relative commondir taken as it is | T21, T22, T23 relative gitdir |
| L4 | an absolute commondir joined to the gitdir | T23 absolute commondir |
| L5 | the common directory not normalised (`cd` and `pwd`) | T21, T22, T23 relative, T24 inside the tree, T26 the checkout's parent |
| L6 | no refusal of a directory holding the checkout | T26 the checkout's parent |
| L7 | no refusal of a directory holding HOME | T26 HOME itself, HOME's parent |
| L8 | no refusal of a path with `=` | T26 a path with = |
| L9 | no check for `HEAD` | T26 a directory with no HEAD |
| L10 | a git directory inside the tree shared again | T24 git dir inside the tree |
| L11 | no refusal of a `.git` file with no gitdir line | T25 no gitdir line |

Each passed again once reverted (61).

## The self-test

Run with `scripts/guix-env sh scripts/guix-env-selftest` in a linked
worktree made under the scratch directory. It sits outside HOME, so HOME's
only entry is the path to the shared `.git`, and the two changed assertions
can each be told apart:

| Launcher, self-test | Result |
|---|---|
| fixed, fixed | ALL CHECKS PASSED |
| fixed, `isolated-home` without the common-directory exception | `FAILED isolated-home: /home/kishu/src is visible inside the container` |
| main's, fixed | `FAILED git-reads-repo: toplevel 'fatal: not a git repository: (null)'`, then `FAILED make-targets` |

## Not covered

- A main checkout's `make check-guix` with these scripts was not run. Its
  `.git` is a directory, so the new block does nothing, and the launcher
  test's T1 and T20 hold that it shares nothing more.
- No shellcheck on the host; `sh -n` passed on each script.
