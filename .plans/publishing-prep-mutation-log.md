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
