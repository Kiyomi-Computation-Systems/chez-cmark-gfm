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
