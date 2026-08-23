# Publishing-prep mutation log

Evidence that each check added by
`.plans/2026-08-22-publishing-prep-design.md` can fail. Per AGENTS.md, a
test is finished when it has been watched to fail, not when it passes.

## Mutation A — check-help notices an undocumented target

**Guards:** `make help` lists every target.
**Mutation:** added `scratch:` to `.PHONY` and as a bare target with no
`## ` description.
**Result:** FAILED, by name —
`check-help: target 'scratch' has no '## ' description on its own line`.
**Reverted:** yes; `make check-help` green again.

## Mutation B — check-install notices an empty install tree

**Guards:** `make install` produces a tree that actually loads.
**Mutation:** `install`'s copy step changed to `cp /dev/null`, so every
installed `.sls` lands empty.
**Result:** FAILED — the probe could not resolve `(cmark gfm)` and
`check-install` reported the tree at the temp prefix.
**Reverted:** yes.

## Mutation C — the probe is not import-only

**Guards:** the probe exercises load-time discovery, not just name
resolution.
**Mutation:** ran an import-only probe and `tests/install-probe.sps` side
by side with `CHEZ_CMARK_GFM_LIBS=/nonexistent`.
**Result:** import-only printed `import-only: imported` and exited **0**
against a library that cannot load; the real probe raised
`&cmark-library-unavailable` reason `invalid-override` and exited **255**.
The `markdown->html` call is what makes the difference — Chez does not
instantiate `native.sls`'s body until a binding is referenced.
**Reverted:** yes; scratch probe deleted.

## Mutation D — the CI matrix grep still discriminates after repointing

**Guards:** the Supported matrix names the Chez each CI job actually ran.
**Mutation:** changed the macOS row in `docs/installing.md` from 10.4.1 to
10.4.0.
**Result:** FAILED — the anchored grep found no matching row, exactly as
it did against README.org before the move.
**Reverted:** yes.

## Mutation D2 — the Linux row's grep also discriminates (reviewer-confirmed)

**Guards:** the Supported matrix names the Chez each CI job actually ran
(Linux row).
**Mutation:** the Task 3 reviewer independently mutated the Linux row in
`docs/installing.md` two ways: `9.5.8` -> `9.5.7`, and an empty version.
**Result:** FAILED in both cases, per the Task 3 reviewer — the anchored
grep found no matching row, the same discrimination Mutation D showed for
the macOS row.
**Reverted:** yes, per the Task 3 reviewer.

## Mutation E — check-help is actually invoked by CI

**Guards:** `make check-help` can fail *in CI*, not merely on a developer's
machine. A gate no workflow runs is a check that cannot fail (AGENTS.md).
**Prior state:** `grep -c 'check-help\|check-install'
.github/workflows/ci.yml` returned **0** at `7627f89^` — both targets
existed and neither was invoked, directly or as a prerequisite of `build`,
`test`, `check-purity`, or `examples`.
**Mutation:** added `sabotage-undocumented` to `.PHONY` and as a bare
target with no `## ` description, then ran `make check-help`.
**Result:** FAILED, by name — `check-help: target 'sabotage-undocumented'
has no '## ' description on its own line`, exit 2.
**Reverted:** yes; `Makefile` byte-identical to its committed state,
`make check-help` exit 0. Re-run first-hand during Task 11; the same
mutation was run before `7627f89` landed.

## Mutation F — check-install is actually invoked by CI

**Guards:** `make check-install` can fail *in CI*, on both platforms.
Same prior state as Mutation E.
**Mutation:** pointed `install`'s copy step at a `find -name` pattern
matching nothing (`'*.sls'` → `'*.nosuchext'`), so the tree installs with
no files at all — a stronger emptying than Mutation B's `cp /dev/null`,
which at least created the paths.
**Result:** FAILED — `Exception: library (cmark gfm) not found`, followed
by `check-install: FAILED -- the tree installed at … could not render a
document …  Check the install target's copy step.`, exit 2.
**Reverted:** yes; `Makefile` byte-identical, `make check-install` exit 0.
Re-run first-hand during Task 11; the same mutation was run before
`7627f89` landed.

**Note on what E and F do and do not show.** Both demonstrate the *gate*
discriminates when run. Neither exercises the GitHub Actions runner: that
the workflow now invokes them is established by inspection —
`.github/workflows/ci.yml:54` (`run: make check-help`, linux job) and
`:194` / `:385` (`run: make check-install`, linux and macos jobs) — against
zero such lines at `7627f89^`. The first real CI run of this branch is the
end-to-end confirmation, and it has not happened yet.

## Summary

| # | Check guarded | Mutation | Fired? |
|---|---|---|---|
| A | `make help` lists every target | undocumented `scratch:` in `.PHONY` | yes — named the target |
| B | `make install` produces a loadable tree | `cp /dev/null` for every `.sls` | yes — probe could not resolve `(cmark gfm)` |
| C | the install probe is not import-only | import-only probe vs. `install-probe.sps`, both with `CHEZ_CMARK_GFM_LIBS=/nonexistent` | yes — import-only exited 0, the real probe 255 |
| D | the CI matrix grep discriminates (macOS row) | `10.4.1` → `10.4.0` in `docs/installing.md` | yes — anchored grep found no row |
| D2 | the CI matrix grep discriminates (Linux row) | `9.5.8` → `9.5.7`, and an empty version | yes, both — per the Task 3 reviewer |
| E | `check-help` is invoked by CI | undocumented `sabotage-undocumented` `.PHONY` target | yes — named the target, exit 2 |
| F | `check-install` is invoked by CI | `install`'s `find` pattern matches nothing | yes — `library (cmark gfm) not found`, exit 2 |

**Uncovered checks: none.** Every mutation in this table produced the
predicted failure. Per AGENTS.md a check whose mutation did not fire must
be written down as uncovered with the reason; there is no such check in
this pass. The one scope limit worth stating plainly is the note above E
and F: the mutations prove the two gates discriminate, and inspection
proves the workflow invokes them, but no CI run has yet executed either.
