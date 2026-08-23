# Docs-site mutation log

Evidence that each check added by `.plans/2026-08-22-docs-site-design.md`
§7 (`tests/site-check.sps`, run as `make check-site`) can fail. Per
AGENTS.md, a test is finished when it has been watched to fail, not when
it passes.

## Mutation A — check-site notices an incomplete nav

**Guards:** every `docs/*.md` on disk appears in the site nav
(`site/pages.sls`), and vice versa.
**Mutation:** removed `("building.md" . "Building")` from `site/pages.sls`.
**Result:** FAILED, by name —
`check-site: nav completeness FAILED. missing-from-site/pages.sls=(building.md) extra-in-site/pages.sls=()`.
**Reverted:** yes; `git diff -- site/pages.sls` empty afterward, `make
check-site` green again.

## Mutation B — check-site notices a broken slug algorithm

**Guards:** generated heading slugs match the anchors `docs/*.md` hand-wrote
in prose.

**Mutation, first attempt (the brief's suggestion):** added `(char=? c
#\.)` to `slugify`'s kept-characters filter in `site/slug.sls`, so `.` is
no longer stripped.
**Result:** PASSED — `make check-site` stayed green. Confirmed why before
accepting it: `rg '^#{1,6}\s.*\.' docs/*.md site/index.md` matches zero
headings — no heading anywhere in the real site contains a literal `.`, so
retaining it changes no real slug and breaks no real anchor. This is not a
gap in `check-site`'s own mechanism (`tests/test-site-render.sps` already
proves, with a minimal synthetic fixture, that `render-site` reports a
dangler the instant a slug stops matching an authored anchor) — it is a
property of today's corpus that this *specific* mutation never reaches.
Recorded here rather than silently swapped for a convenient one, per
AGENTS.md ("narrow the mutation until the failure is the one you
predicted" / "do not hide it").

**Mutation, second attempt (exercises the same filter against real
content):** added `(char=? c #\,)` to the same kept-characters filter
instead. `docs/installing.md`'s heading "RHEL, Fedora, and Alpine" slugs
today to `rhel-fedora-and-alpine`, and is linked twice: same-page as
`#rhel-fedora-and-alpine` inside `installing.md` itself, and cross-page as
`installing.md#rhel-fedora-and-alpine` from `building.md`. Keeping the
comma changes that heading's slug to `rhel,-fedora,-and-alpine` (commas
are not hyphen/space, so `spaces->hyphen` leaves them in place), which no
longer matches either authored anchor.
**Result:** FAILED, by name —
`check-site: anchor resolution FAILED. danglers=((installing.md . #rhel-fedora-and-alpine) (building.md . installing.md#rhel-fedora-and-alpine))`.
**Reverted:** yes, both attempts; `git diff -- site/slug.sls` empty
afterward, `make check-site` green again.

## Mutation C — check-site notices a leaked .md link

**Guards:** no relative `.md` href/src reaches the serialized HTML;
absolute GitHub blob URLs ending in `.md` are unaffected.
**Mutation:** in `site/links.sls`, changed `rewrite-target`'s `(if (suffix?
".md" path) ...)` to `(if #f ...)`, so every `.md` target — bare or
anchored — falls through to the "unrecognised: leave, don't dangle" branch
and is returned unchanged.
**Result:** FAILED, by name —
`check-site: a relative .md link leaked into index.md: (installing.md usage.md options.md ast.md sxml.md errors.md memory.md building.md)`.
Note this mutation also makes `rewrite-target` report every `.md` link as
*not* dangling (the hard-coded `#f`), so check (2) (anchor resolution)
stays green and execution reaches check (3) — the leak scan — exactly as
the design intends: the two checks catch different failure modes of the
same rewrite function.
**Reverted:** yes; `git diff -- site/links.sls` empty afterward, `make
check-site` green again.

## Mutation D — check-site notices `<pre>` reflow

**Guards:** the serializer never injects whitespace into an element's
children — load-bearing for `<pre><code>`, where indentation is content.
**Mutation:** in `site/serializer.sls`'s `emit`, changed `(for-each
(lambda (k) (emit k p)) kids)` to `(for-each (lambda (k) (put-string p "\n
  ") (emit k p)) kids)`, injecting a newline and two-space indent before
every child of every element.
**Result:** FAILED, by name —
```
check-site: <pre> reflow FAILED: <pre>
  <code>
  a
        b
</code></pre>
```
**Reverted:** yes; `git diff -- site/serializer.sls` empty afterward, `make
check-site` green again.

## Summary

All four invariants were broken, watched to fail *by name* through
`make check-site`, and reverted. No invariant is recorded as UNCOVERED:
Mutation B's first attempt was inert against the real corpus for the
reason given above, not because the check cannot catch a broken slug
algorithm — its second attempt, targeting the same code with the same
kind of change, proves that it can. `make check-site` and `make
check-help` are both green on the committed tree.
