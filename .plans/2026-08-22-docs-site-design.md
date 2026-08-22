# Docs site generator: dogfooding chez-cmark-gfm onto GitHub Pages

Status: proposed
Date: 2026-08-22
Scope: new tooling and CI only. No library behaviour changes, no new
exports. `docs/` and `.plans/` content are untouched; the generator reads
them, it does not rewrite them.

Intended location on landing: `.plans/2026-08-22-docs-site-design.md`
(designs live in `.plans/`, per the publishing-prep design's own rule —
`docs/` is user-facing documentation only).

## Goal

Publish the eight `docs/*.md` reference pages plus an authored home page as
a Flexoki-themed, sidebar-and-TOC static site on GitHub Pages, built
entirely through the library's own `markdown->sxml` → transform →
serialize pipeline. The site is a working demonstration of the exact
capability `docs/sxml.md` documents.

Nothing generated is committed. The site is built and deployed by GitHub
Actions on a **release-tag push**, so out-of-site source links can pin to
that tag and every referenced file is guaranteed present at it.

This feature depends on `docs/*.md`, which today exist only on
`docs/publishing-prep`. See §12.

## 1. Architecture — functional core, imperative shell

The generator is one Chez program, `build-site.sps` (the shell), over a
pure core it can test without touching the filesystem.

**Pure core** — `(render-site inputs ref) → {pages, id-registry, leaked}`,
in **two passes**, because a cross-page anchor (`errors.md#guard`) cannot be
validated until the target page's slugs are known:

**Pass 1 — parse and slug** (per page: `site/index.md`, then `docs/*.md` in
nav order):

1. `markdown->sxml` the source with `(default-cmark-options)` — the GFM
   extensions (`table`, `tasklist`, `strikethrough`, …) are already on
   there, and the docs lean on tables heavily.
2. **Walk the tree once.** For every heading, compute a GitHub-style slug
   (§3) from its concatenated text descendants, inject `(^ (id slug))`,
   collect `(level text slug)` into the page's TOC, and fold ⚠️-led
   blockquotes into callouts (§4).

Pass 1 yields each page's slugged body and TOC, plus the global
**id-registry** (page → set of slugs).

**Pass 2 — link and template** (per page, now that the registry is
complete):

3. **Rewrite `(a …(href))` / `(img …(src))` attributes** by §2, resolving
   intra-site targets against the id-registry and recording any that dangle
   into `leaked`.
4. Splice the body into the full-page SXML template (§4), from the ordered
   page list and the page's TOC.

The core returns every page's final SXML, the id-registry, and `leaked`.
`check-site` (§7) asserts directly on that value — no filesystem needed.

**Imperative shell** — serialize each page's SXML with the pre-safe
serializer (§6), write to `build/site/<name>.html`, copy `site/style.css`.

### Why SXML is the *correct* path here, not merely the idiomatic one

The link inventory of the current docs contains, as **code-block content**
in `sxml.md`, targets like `javascript:alert(1)`, `JaVaScRiPt:alert(1)`,
`data:image/png;base64,AAA`, `/café`, and `/a?q=1&r=2` — the very examples
that teach the adapter's URL handling. A text-level `.md`→`.html` rewriter
would maul them. On the SXML tree these are plain string children of
`(pre (code …))`, never `(a)` nodes, so rewriting link attributes leaves
them untouched for free. The dogfood and the correctness argument point the
same way.

## 2. The link rewriter (tree-level)

Operates only on `href`/`src` attributes of `(a)`/`(img)` nodes. Grounded
in the actual link inventory of `docs/`:

| Target form | Real example | Rewrite |
|---|---|---|
| doc page `.md`, optional anchor | `options.md#resource-limits` | `options.html#resource-limits`; anchor validated against the target page's slugs |
| same-page anchor | `#wrap-width` | unchanged; validated against this page's slugs |
| repo-relative escape | `../.plans/2026-08-16-…-design.md`, `../examples/01-rendering.sps` | `https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/blob/$SITE_REF/<path>` |
| absolute URL | (none in prose today) | unchanged |
| code-block text | `javascript:alert(1)` in a `scheme` fence | untouched — not a link node |

The "repo-relative escape" rule covers everything that points outside the
published set: `../examples/*.sps`, `../tests/*.sls`, `../.plans/*.md`,
`../packaging/*`. Those files are not on the site, so a relative link would
404 on Pages; pinning them to `$SITE_REF` on GitHub is both stable and
always valid (the deploy trigger guarantees the ref contains them, §8).

`check-site` does **not** validate external targets (they live on GitHub),
only intra-site ones — see §7.

## 3. Slugging — GitHub-compatible, and load-bearing

The docs already contain **hand-written cross-page anchors** —
`#resource-limits`, `#what-make-build-does`, `#supported-versions`,
`#wrap-width`, `#rhel-fedora-and-alpine`. Our generated slugs must match
them, or those links dangle.

Algorithm (GitHub's, restricted to the ASCII the docs use): take the
heading's concatenated text descendants (so `(h2 "What " (code "make
build") " does")` yields `What make build does`); lowercase; drop every
character that is not alphanumeric, space, or hyphen; replace runs of
spaces with a single hyphen. Duplicate slugs on one page get `-1`, `-2`, …
appended, GitHub-style.

This is exactly what `check-site`'s anchor-resolution invariant proves: if
our slug for "Resource limits" is not `resource-limits`, the link
`options.md#resource-limits` fails to resolve and the build fails by name.
The gate validates the algorithm against real authored anchors.

## 4. Templating and navigation

`site/template.scm` builds the page shell as SXML:

- `<head>`: `<title>`, the `style.css` link, and a small inline theme
  script (§5). No external assets.
- **Left sidebar**: the wordmark (links home) and the nav — an ordered list
  from `site/pages.scm` (`file → nav-label`), the current page marked.
- **Content**: the transformed body.
- **Right rail**: the per-page "On this page" TOC from the collected
  headings.

`site/pages.scm` is the single source of nav order and labels; `check-site`
asserts it names exactly the `docs/*.md` set (§7), so a page added to
`docs/` without a nav entry fails the build.

`site/index.md` is the authored home (pitch, the "a taste" sample, and
cards linking the eight pages). It is a page like any other — slugged,
in the id-registry, rendered to `index.html` — but is reached from the
wordmark, not listed as a nav item.

**Callouts.** All blockquotes get styled. A blockquote whose first text
begins with `⚠️` is given the warning treatment (left accent + icon); the
two such callouts today are in `ast.md` and `sxml.md`. This is a small tree
transform in the same walk as §1.2.

## 5. Styling — locked

Ported verbatim from the approved preview artifact.

- **Fonts, by role**: body `Charter, …, serif`; headings and all UI
  (nav, TOC, labels) `Seravek, …, sans-serif`; tables the system UI stack;
  code `SFMono-Regular, …, monospace`.
- **Flexoki**, light → dark by the palette's own "600 for light, 400 for
  dark" rule:

  | Token | Light | Dark |
  |---|---|---|
  | ground / page | `#FFFCF0` paper | `#1C1B1A` base-950 |
  | surface (sidebar, code) | `#F2F0E5` base-50 | `#282726` base-900 |
  | body text | `#282726` base-900 | `#CECDC3` base-200 |
  | headings | `#100F0F` black | `#E6E4D9` base-100 |
  | muted | `#6F6E69` base-600 | `#878580` base-500 |
  | border | `#DAD8CE` base-150 | `#403E3C` base-800 |
  | link / accent | `#205EA6` blue-600 | `#66A0C8` blue-400 |
  | warning | `#DA702C` orange-600 | `#EC8B49` orange-400 |

- **Nav and TOC** share one active-state idiom: a 2px blue left border with
  blue text, no background, no radius.
- **Density**: a book-like reading column (~65ch, serif ~16.5px, generous
  line-height), not API-doc density.
- **Theme**: `prefers-color-scheme` by default, plus a persisted toggle
  (localStorage `theme` → `data-mode` on the root). ~15 lines of inline JS,
  no dependencies. Every color is a token defined for both modes; nothing
  is defined only inside a media query.

## 6. The serializer

`site/serializer.sls` is a self-contained, **pre-safe** SXML→HTML
serializer adapted from `tests/sxml-html-serializer.sls`. Pre-safe is
non-negotiable here: `docs/sxml.md` itself warns that a pretty-printing
serializer corrupts `<pre>` by injecting indentation into code — and this
site is wall-to-wall `scheme` code blocks. The test serializer already
exempts `pre`, `script`, `style`, `textarea` and byte-matches
`markdown->html` across all 744 corpus examples; the generator carries its
own copy — inlining any `wak-sxml-tools` helper the test version leans on —
honouring the page's own "your serializer, not ours" position and keeping
`make site` dependent on nothing but Chez + `libcmark-gfm`. (Task 0 of the
plan confirms the test serializer's actual dependencies.)

## 7. Gating — `check-site` (the Option-1 invariants)

`check-site` builds the site to a temp dir and asserts on the pure core's
return value:

1. **Nav completeness** — the `site/pages.scm` set equals the `docs/*.md`
   set; every page produced a non-empty output.
2. **Anchor resolution** — every intra-site href (`page.html#slug`,
   `#slug`) names a page in the id-registry and a slug that page emitted.
   This is the invariant that proves §3.
3. **No `.md` leak** — no *relative* href ends in `.md`. Absolute GitHub
   `…/blob/$SITE_REF/….md` URLs are expected and allowed.
4. **No `<pre>` reflow** — a fixture with a deeply-indented code block
   round-trips byte-for-byte through the serializer.

Per AGENTS.md, each invariant is proven able to fail, recorded in
`.plans/docs-site-mutation-log.md`:

| Check | Mutation that must make it fail |
|---|---|
| nav completeness | add a stray `docs/zzz.md`; the set comparison fails naming `zzz` |
| anchor resolution | change the slug algorithm to keep `.` (or point a TOC entry at a bogus slug); `options.md#resource-limits` fails to resolve |
| no `.md` leak | disable the `.md`→`.html` step; a relative `.md` href survives and is caught |
| no `<pre>` reflow | swap in a pretty-printing serializer; the indented-code fixture no longer matches |

`site` and `check-site` are `.PHONY` and each carries a `## ` description,
so the other session's `check-help` stays green.

## 8. Build and deploy

- `make site` → `build/site/` (under the already-gitignored `build/`).
  Depends on `build` (the preflight that resolves `libcmark-gfm`) since the
  generator calls into `(cmark gfm)` and `(cmark gfm sxml)`.
- `make check-site` builds to a temp prefix and runs the §7 assertions.
- `.github/workflows/pages.yml`:
  - **Triggers**: `push` on tags matching `v*`, plus `workflow_dispatch`.
  - `SITE_REF` = the pushed tag (or, for a manual run, the selected ref).
  - Provisions `libcmark-gfm` exactly as `ci.yml`'s Linux job does
    (`docs/installing.md`'s apt row), runs `make check-site` then
    `make site`, and deploys `build/site/` with
    `actions/upload-pages-artifact` + `actions/deploy-pages`.
  - Permissions `pages: write`, `id-token: write`; a `github-pages`
    environment; a `concurrency` group so overlapping tags don't race.
- Intra-site links are **relative** (`ast.html`, `#slug`), so the
  `/chez-cmark-gfm/` project-path prefix needs no `<base>` tag.

The first real deploy is the push of `v2.0.0`. A `workflow_dispatch` can
rebuild against any ref in the meantime.

## 9. File structure

All new. Nothing under `docs/` or `.plans/` (except this spec and the
mutation log) is modified.

| Path | Responsibility |
|---|---|
| `site/index.md` | Authored home page |
| `site/pages.scm` | Ordered `file → nav-label`; the nav's single source |
| `site/template.scm` | SXML page shell: head, sidebar, TOC rail |
| `site/style.css` | Flexoki + font roles, ported from the preview |
| `site/serializer.sls` | Self-contained pre-safe SXML→HTML serializer |
| `build-site.sps` | Generator entry point (the imperative shell) |
| `.github/workflows/pages.yml` | Build on `v*` tag, deploy to Pages |
| `.plans/docs-site-mutation-log.md` | Mutation evidence for §7 |

**Modified**: `Makefile` (`site`, `check-site`, `.PHONY`), `.gitignore`
only if `build/` is not already covered, and a `CHANGELOG.md` note.

## 10. Verification

Beyond the §7 mutation table: `make site && make check-site` is green; the
generated `build/site/` opens locally and every intra-site link and anchor
resolves; a `workflow_dispatch` dry run produces a Pages artifact.

## 11. Out of scope

- **Syntax highlighting** — code blocks are themed via CSS on
  `language-scheme`, not tokenized. A later add.
- **Client-side search**, versioned/multi-release docs.
- **Rewriting `README.org`** — it is Org (the library renders Markdown),
  and the other session owns it this branch.
- Validating **external** link targets (they resolve on GitHub, not here).

## 12. Coordination

The site renders `docs/*.md`, which exist only on `docs/publishing-prep`
(the other session's live branch), not yet on `main`. Therefore:

- Branch `feat/docs-site` off the tip of `docs/publishing-prep` (so the
  docs are present to build against), or land after publishing-prep merges
  to `main`.
- This spec and the mutation log are the only additions to `.plans/`.
- No commit touches the other session's working tree; all new paths are
  under `site/`, `.github/workflows/`, and the two `.plans/` files.
