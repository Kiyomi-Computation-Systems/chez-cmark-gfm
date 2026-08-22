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
