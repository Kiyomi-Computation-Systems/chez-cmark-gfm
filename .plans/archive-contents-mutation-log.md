# What the Akku package ships: mutation log

chez-cmark-gfm 2.0.0's repack on the Akku archive
(`chez-cmark-gfm_2.0.0_repack.tar.xz`) holds the whole tracked tree at the
tag, `.plans/`, `AGENTS.md` and `spike/` included; the tag had no
`.gitattributes`. The archive builds packages as `git archive` does:
byte-machine 0.8.0, which export-ignores `.plans`, `.decisions` and
`AGENTS.md`, has a repack lacking exactly those three. `akku install`
unpacks the whole package into each consumer's `.akku/src/<name>/`. Found
from uriparse's PR #49 work, 2026-10-14.

`make check-akku` was green throughout: it checks the libraries that land in
`.akku/lib`, and built its package from `git ls-files`, which ignores
`export-ignore`.

## The change

- `.gitattributes` marks `/.plans`, `/AGENTS.md` and `/spike`
  `export-ignore`.
- `scripts/archive-package` writes the tar the archive would build: `git
  archive` of a tree written from the working tree's tracked files, through a
  copy of the index and a private object directory. It fails if a tracked
  file is missing from the working tree.
- `scripts/check-archive` (`make check-archive`) keeps its own list,
  `PROCESS_ONLY`, and fails if any listed path is untracked, if any ships, or
  if the package is not the tracked tree less those paths.
- `scripts/check-akku` installs the package `archive-package` builds, in
  place of its own `git ls-files | tar` copy.

## Red, before `.gitattributes` existed

On the worktree, macOS, bsdtar 3.5.3, git 2.50.1:

```
$ make check-archive
check-archive: would ship in the package: .plans AGENTS.md spike (export-ignore them in a tracked .gitattributes)
make: *** [check-archive] Error 1
```

The script exited 1. With `.gitattributes` written but not yet added, the
same: the archive reads attributes from the tree it archives. After `git add
.gitattributes`: rc 0, "106 files ship; not .plans AGENTS.md spike".

The command from the issue, `git archive --worktree-attributes --format=tar
HEAD | tar -t | awk -F/ '{print $1}' | sort -u`, then lists no `.plans`,
`AGENTS.md` or `spike`.

## Mutants

Each in a `--no-hardlinks` clone outside the repository with the change
committed, so each mutation is an unstaged edit to the working tree.
`check-akku-main` is `scripts/check-akku` as on `main`. Harness:
`mutants.sh` in the session scratchpad, run on the host (akku
1.1.1-beta.0, Homebrew Chez).

| Mutant | Check | Result |
|---|---|---|
| none | check-archive | rc 0, 109 files ship |
| none | check-akku, check-akku-main | rc 0, 12 libraries |
| M1: `/.plans` line deleted | check-archive | rc 1, "would ship in the package: .plans" |
| M2: `/AGENTS.md` line deleted | check-archive | rc 1, "would ship in the package: AGENTS.md" |
| M3: `/spike` line deleted | check-archive | rc 1, "would ship in the package: spike" |
| M4: `/.plans` written `.plans/` | check-archive | rc 0: git honours the directory form too, so this is an equivalent spelling, not a defect |
| M5: `/src/cmark/gfm/ast.sls export-ignore` added | check-archive | rc 1, diff `-src/cmark/gfm/ast.sls` |
| M5 | check-akku | rc 1, diff `-cmark/gfm/ast.sls`, "installs a different set of libraries" |
| M5 | check-akku-main | **rc 0, 12 libraries**: main's copy ignored export-ignore |
| M6: `/examples export-ignore` added | check-archive | rc 1, diff lists every `examples/` file as left out |
| M7: `spike/` removed from the index | check-archive | rc 1, "not tracked, so absence from the package proves nothing: spike" |
| M8: `README.org` moved out of the working tree | check-archive, check-akku | rc 1, "tracked files missing from the working tree: README.org" |
| M8 | check-akku-main | rc 1, "could not archive the tracked files", as in `check-akku-and-theme-storage-mutation-log.md` |
| M9: `archive-package` archives `HEAD`, with M1 applied | check-archive | **rc 0**: the builder must read the working tree, or an uncommitted edit goes unseen |

`check-akku-and-theme-storage-mutation-log.md`'s `--no-recursion` row has no
site left: no tar builds the package from a file list any more.

Not mutated: the directory-entry and gitlink filters before the comparison.
Removing either puts entries on one side only, so the check fails on every
tree: it fails closed.

## The repository is left alone

On the worktree, with unstaged edits to `Makefile` and `scripts/check-akku`
that `git add -u` hashes, `git count-objects -v` and the index's checksum
were identical before and after `make check-archive`.

## Not covered

- `.superpowers/` is untracked, and its `sdd/.gitignore` is `*`, so nothing
  in it can be added. An `export-ignore` line for it could not be shown to
  do anything, so there is none.
- A new process-only path ships until someone adds it to both
  `.gitattributes` and `PROCESS_ONLY`: the check cannot know intent.
- Global and `$GIT_DIR/info/attributes` files apply to the local run. A
  developer's attributes could hide a missing line locally; CI has none.

## Gates

On the host, macOS: `make check-help`, `make check-pins`, `make build`,
`make test` (22 suites, "ALL SUITES PASSED") and `make check-site`.
`make check-archive` (108 files, with the new scripts tracked) and `make
check-akku` (12 libraries) passed both before and after `make deps` filled
the submodules. The Linux run is CI's: `check-archive` in the linux job,
`check-akku` in akku-install.
