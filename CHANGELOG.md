# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [0.2.0] — 2026-08-17

The Scheme-owned AST. `markdown->ast` returns immutable records containing no
native pointers, valid after every cmark object has been freed. The SXML
adapter follows in 0.3 (ADR-0007).

### Added

- `markdown->ast`. Two arities: `(markdown->ast md)` uses
  `(default-ast-options)`, which turns source positions on; `(markdown->ast md
  opts)` honours the caller's options record verbatim. See ADR-0009 — one
  shared default cannot serve both the AST and the renderers well.
- `(cmark gfm ast)`, re-exported from `(cmark gfm)`: `make-markdown-node`,
  `markdown-node?`, the four field accessors, `markdown-node-property` with an
  optional default, `markdown-node-with-properties`,
  `markdown-node-with-children`, `markdown-node-map` (children-first),
  `markdown-node-fold` (pre-order), and the `source-position` record.
- 24 cmark type strings covering CommonMark and all five GFM extensions,
  mapping to 22 distinct `markdown-node-type` values — `"item"`/`"tasklist"`
  both yield `item`, and `"table_row"`/`"table_header"` both yield
  `table-row`. A task item and a table header row are distinguished by
  cmark's own type strings, which is the only reliable channel for either:
  `cmark_gfm_extensions_get_tasklist_item_checked` returns false both
  for an unchecked task and for a non-task.
- `max-nodes` (default 250000) and `max-depth` (default 1000) options.
  `max-input-bytes` does not bound the AST — 5 MiB of adversarial input parses
  to millions of nodes — so the copy has its own ceilings.
- `&cmark-resource-limit`, carrying the ceiling that was exceeded. It derives
  from `&cmark-invalid-input`, so existing code guarding
  `cmark-invalid-input?` on an oversized document keeps working while new code
  can catch resource exhaustion as a class.
- `default-ast-options`.

### Security

- **The AST is untrusted structured input.** Parsing preserves exactly what the
  document said, including raw HTML literals and `javascript:` URLs. No
  sanitisation happens during conversion and `unsafe-html?` has no effect on
  it — that option is a renderer policy. Sanitise when rendering.
- Node and depth ceilings bound the Scheme-side allocation, and a document
  exceeding either raises before the tree is built rather than exhausting
  memory.

### Notes

- Source positions are only trustworthy with `CMARK_OPT_SOURCEPOS` on:
  `vendor/cmark-gfm/src/inlines.c:292-296` skips a correction when it is off,
  leaving multi-line code spans and raw inline HTML with wrong end positions
  that propagate to later inlines. The AST therefore attaches a position only
  when it parsed with the flag, and reports `#f` otherwise.
- An unrecognised node type is preserved as an `extension` node carrying the
  native type string, never discarded. No such type is reachable through the
  options this library exposes — footnotes require `CMARK_OPT_FOOTNOTES`, which
  is not exposed — so the branch is unit-tested rather than exercised
  end-to-end.
- The AST is verified by re-serializing it into cmark's own XML dialect and
  diffing byte-for-byte against `cmark_render_xml` and the pinned CLI across
  the four fixtures with and without positions. Item index, table column count,
  and body-cell alignment are invisible to that oracle and carry direct
  assertions instead. See ADR-0010.

## [0.1.0] — 2026-08-17

First release. Parsing and direct rendering with safe defaults; the Scheme
AST and the SXML adapter follow in 0.2 and 0.3 (ADR-0007).

### Added

- `(cmark gfm)` — the public API: options, renderers, version and capability
  inspection, and the structured condition types.
- `markdown->html`, `markdown->commonmark`, `markdown->plaintext`, and
  `markdown->xml`. The commonmark and plaintext renderers take an optional
  wrap width; html and xml are fixed at arity 2, because cmark applies width
  only to the renderers that wrap.
- Immutable options: `make-cmark-options`, `default-cmark-options`, and
  `cmark-options-with`. Options are named symbols; cmark's numeric constants
  and string names never appear in the public API.
- All five standard GFM extensions — `autolink`, `strikethrough`, `table`,
  `tagfilter`, `tasklist` — enabled by default.
- `cmark-gfm-version`, `cmark-gfm-version-compatible?`, and
  `cmark-gfm-available-extensions`.

### Security

- HTML rendering is safe by default: raw HTML and unsafe link schemes are
  suppressed unless `'unsafe-html? #t` is set explicitly. There is no global
  switch; the setting belongs to each immutable options object.
- Embedded NUL input is rejected, and input is bounded by `max-input-bytes`
  (5 MiB by default) before parsing.

### Notes

- `source-positions?` defaults to `#f` in this release, diverging from
  project plan §6.2. See ADR-0008 — the AST in 0.2 is the consumer that
  wants positions, and this default is scoped to renderer-only releases.
- `validate-utf8?` is accepted and wired, but has no observable effect on
  input reaching the public API: Scheme strings always encode to valid
  UTF-8. See the Stage 2 design spec §10.1.
- Output is verified byte-for-byte against the pinned `cmark-gfm`
  0.29.0.gfm.13 CLI across 24 distinct option configurations in four formats,
  each exercised twice via the sweep's 48 boolean combinations. See the Stage
  2 design spec §7.4.
