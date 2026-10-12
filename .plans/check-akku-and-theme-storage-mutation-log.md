# check-akku's tar, and the theme script's storage: mutation log

Both defects were found while chez-libuv ported this repository's docs-site
tooling (chez-libuv PR #135) and are fixed there the same way.

## check-akku

Run on the host, x86_64 Linux, GNU tar, through
`guix shell akku chez-scheme -- make check-akku CHEZ=scheme`.

On the worktree, submodules checked out:

| Script | Result |
|---|---|
| main's (`-T - --no-recursion`, a pipe) | rc 2: "installs a different set of libraries than src/", 1,153 extra (`srfi/` 1,121, `wak/` 31, one more). tar printed "--no-recursion has no effect" and "Exiting with failure status"; the pipe dropped the status. |
| fixed | rc 0: "12 libraries installed, exactly src/", no tar message |

Mutants, each in a `--no-hardlinks` clone outside the repository with the
script copied in. `vendor/wak-common` was filled from the worktree for the
rows that need a submodule's files, and emptied for the rest, as CI's
checkout leaves it:

| Mutant | Submodule files | main's script | fixed script |
|---|---|---|---|
| none | present | rc 2, extra libraries | rc 0, 12 libraries |
| `README.org` moved out of the working tree | absent | **rc 0, 12 libraries**: tar's "Cannot stat" was dropped | rc 2: "could not archive the tracked files" |
| the same, file restored | absent | not run | rc 0, 12 libraries |
| `--no-recursion` moved back after `-T` | present | the bug itself | rc 2: "could not archive the tracked files" (GNU tar exits 2 on the misplaced option, and the status now counts) |

With the submodules empty, as on CI, main's script passed while tar exited 2
on every run for the misplaced option.

## The theme script

`tests/test-site.sps`'s new row, "the theme script reaches localStorage
twice, each time inside a try block", expects `(2 ())`: two accesses, none
outside a try block.

- Before the fix, on the worktree: it fails by name (36 passed, 1 failed).
- After: 37 passed.

Mutants, each in a copy of `site/`, `src/` and `tests/` outside the
repository, run with host Chez:

| Mutant | Result |
|---|---|
| T1: `g` reads `localStorage.getItem` with no try | the row fails by name, 36 passed |
| T2: `p` closes its try before `setItem` (`try{}catch(e){}localStorage.setItem(…)`) | the row fails by name, 36 passed |
| T3: a third, guarded access (`localStorage.length` inside `p`'s try) | the row fails by name, 36 passed |
| none | 37 passed |

T3 shows the count is checked, so a script that gained or lost an access
cannot pass on the empty list alone. A page with no script element makes
`script-of` raise, which SRFI-64 turns into an actual of `#f`; that was not
run as a mutant.

### Behaviour, checked under node

The structural row cannot run the script. `.plans/theme-script-print.sps`
prints it as a rendered page carries it, and `.plans/theme-storage-probe.js`
runs it under node (`guix shell node`, v24.18.0) with a stub document, after
load and after one click on the toggle:

| Storage | main's script | fixed script |
|---|---|---|
| works | `light`, "Dark mode"; click → `dark`, "Light mode"; stored `dark` | the same |
| access throws `SecurityError` (site data blocked) | throws; no mode set, label left as written, toggle not wired | `light`, "Dark mode"; click → `dark`, "Light mode" |
| `setItem` throws (some private modes) | throws; mode set, label left as written, toggle not wired | the same as above |

## Gates

- On the host: `check-pins` and `check-akku`.
- In the container, with `deps` and `check-pins` taken as made (`make -o`):
  `make test` ("ALL SUITES PASSED", 22 suites) and `check-site` ("nav,
  anchors, no .md leak, no <pre> reflow -- all green").
- `make deps` fails inside `scripts/guix-env` in a linked worktree ("fatal:
  not a git repository: (null)"): the launcher shares the worktree but not
  the main repository's `.git`, which a worktree's `.git` file names. It ran
  on the host instead. chez-libuv's launcher shares both.
