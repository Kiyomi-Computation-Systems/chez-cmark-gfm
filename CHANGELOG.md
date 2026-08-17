# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org).

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
