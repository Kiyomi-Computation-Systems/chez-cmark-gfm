# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [1.0.0] — 2026-08-18

Packaging, documentation, and release. No parsing, rendering, or mapping
behavior changed: 1.0 freezes the API. The one public-API change is additive.

### Added

- **`examples/`** — six runnable programs covering rendering, options, the
  AST, SXML, the condition family, and capability inspection. `make examples`
  runs each and diffs its output. It sets `CHEZSCHEMELIBDIRS=src:fallback` and
  nothing else, so an example that reached a dev dependency breaks the build —
  which is what keeps 0.3.0's "a consumer acquires neither" true rather than
  merely written down.
- **`tests/test-example-coverage.sps`** — fails when `(cmark gfm)` gains an
  export that appears in no example. It reads the export list and each
  example as *datums*, not text, so an identifier mentioned only in a comment
  does not count. Exemptions carry a reason each and are themselves checked
  for staleness and typos; today they cover eleven condition type names,
  which are not first-class values, and eleven predicates and accessors on
  conditions an example cannot trigger through the public API — most
  genuinely unreachable, three (`cmark-shim-unavailable?` and its two
  accessors) reachable only at import time, before an example's own code
  runs. `cmark-unsupported-node?`/`cmark-unsupported-node-type` carry no
  exemption: an earlier version of the list exempted them on the reasoning
  that the adapter covers every node type the real parser emits, which
  argues from the parser's side — `markdown-ast->sxml` is public and accepts
  an arbitrary caller-built tree, and `make-markdown-node` validates
  nothing, so the condition is reachable through public procedures alone.
  `examples/05-errors.sps` demonstrates it directly, handing the adapter an
  `extension` node that names a native type cmark-gfm never registered.
- **`tests/test-manifest-deps.sps`** — reads `Akku.manifest` as data, the
  same technique `test-example-coverage.sps` uses on `gfm.sls`, and asserts
  that no declared dependency's name matches a documentation-site-tool
  marker and that the declared dependency set is exactly today's known-good
  one. Plan §16, criterion 15 (no dependency on a documentation-site
  framework) was true only by inspection before this suite existed.
  `make check-purity` now gates five pure suites, up from three: this one
  and `test-example-coverage.sps` join `test-options.sps`, `test-ast.sps`,
  and `test-sxml.sps`.
- **`tests/test-stress.sps`** — asserts the live parser, root, and buffer
  counts return to zero after *every* iteration of a repeated
  parse/render/AST/SXML loop. Every counter assertion before this was
  single-shot, so a per-call leak of one buffer satisfied all of them.
  `CMARK_STRESS_ITERATIONS` tunes the count; the memory targets drop it to 2.
- **`fallback/cmark/gfm/private/config.sls`** — a checked-in configuration,
  shadowed by the generated one whenever a build has happened. See below.
- **`NOTICE`** — the binding's own BSD-3-Clause notice, plus all seven
  license blocks bundled in `vendor/cmark-gfm/COPYING`, reproduced in full:
  cmark-gfm's core and its `test/` suite (BSD-2-Clause, both John
  MacFarlane); the `houdini`-, `buffer`/`chunk`-, and `utf8proc`-derived code
  (three separate MIT grants); `normalize.py` (MIT, Karl Dubost); and the
  CommonMark spec text itself (CC-BY-SA 4.0). Plan §14 requires license
  notices for the binding and its native dependency; this repository had
  neither before.
- **A clean-machine CI job** in a bare `ubuntu:24.04` container that runs only
  the steps the README documents. It never runs `make deps`.
- **`make check-config`** and **`make examples`**.

### Changed

- **`&cmark-shim-unavailable` carries a `reason`**: `not-built`, `missing`,
  `invalid-override`, or `load-failed`. Four distinct failures previously
  shared one field, so a caller could not tell a missing build from a bad
  `CHEZ_CMARK_GFM_SHIM`. Additive for existing `guard` clauses. Mirrors
  `&cmark-invalid-option`'s `key` + `reason` pair.
- **An unbuilt tree now names its own remedy.** It used to fail with
  `library (cmark gfm private config) not found`, which names no cause and is
  not a condition; it now raises `&cmark-shim-unavailable` with reason
  `not-built`. The fallback's `shim-path` is `#f` rather than a plausible fake
  path, because no build can produce a non-string there — which is what keeps
  "never built" distinguishable from "shim deleted since". See ADR-0014.
- **`CHEZSCHEMELIBDIRS` is now `src:fallback`.** The order is the mechanism:
  Chez resolves a library from the first entry that has it.
- **The documented Chez floor is 9.5.8, not 10.4.1.** The old claim recorded
  one developer's machine and was never tested; 9.5.8 is what Ubuntu CI runs
  green under Valgrind. A CI step now asserts the README matrix against the
  version each job actually ran, so a runner-image bump fails the build rather
  than letting the claim go stale.

### Fixed

- **Four empty assertions in `tests/test-native.sps`.** Each expected exactly
  the path `resolve-shim-path` *returns on success*, so all four passed against
  code with every rejection deleted — verified: 54 of 54, exit 0. They now
  assert `(path reason)`, a shape no success path here produces, and each
  `guard` body ends in `'no-condition`.

### Documentation

- The supported platform/Chez/cmark matrix, the memory-ownership contract, and
  the static-versus-dynamic linking behavior (static linking is *impossible*
  here, not merely unchosen — cmark's static archives hide every symbol that
  ADR-0002 requires Scheme to resolve at runtime). All three are Plan §14
  requirements the README had never met.
- Prerequisites live in `packaging/debian-prereqs.txt` in exactly one copy,
  which the README points at and CI installs from.
- Akku is documented as *not yet* a supported install path, with what an
  unbuilt tree does instead. README additions are deliberately terse; in-depth
  documentation is deferred to a `docs/` tree.

## [0.3.0] — 2026-08-18

The SXML adapter. `markdown->sxml` and `markdown-ast->sxml` turn Markdown into
an SXML tree in HTML vocabulary, which a conforming serializer renders as an
HTML fragment. `(cmark gfm sxml)` is pure and optional in both directions: it
imports nothing that reaches a shared object, and no existing library imports
it, so a caller who never mentions SXML links no new code and acquires no new
dependency.

### Added

- `markdown->sxml`. Three arities: `(markdown->sxml md)` uses
  `(default-cmark-options)` and `(default-sxml-options)`; `(markdown->sxml md
  opts)` and `(markdown->sxml md opts sxml-opts)` take the caller's records.
  It lives in `(cmark gfm)` rather than in the adapter because it parses.
- `markdown-ast->sxml` in the new library `(cmark gfm sxml)`, re-exported from
  `(cmark gfm)`. Arity 1–2. It is a pure Scheme-records-to-Scheme-lists
  transformation and runs under `make check-purity` as a third gated suite.
- `make-sxml-options`, `default-sxml-options`, `sxml-options-with`, and the
  three accessors, mirroring the `cmark-options` trio — including its
  rejection of unknown keys, duplicate keys, and unknown values. Fields:
  `raw-html` (`omit` | `escape`, default `omit`), `softbreak` (`newline` |
  `break` | `space`, default `newline`), and `attribute-marker` (`caret` |
  `at`, default `caret`).
- `softbreak` exists because cmark's `hardbreaks?` and `nobreaks?` are
  renderer options that never reach the parse, so no AST can carry them
  (`html.c:319-325`). It names what a softbreak *becomes*, because cmark's own
  pair is mutually exclusive with a precedence rule and a three-valued field
  cannot express the contradictory state at all.
- `attribute-marker` defaults to `caret`, **not** the SXML specification's
  `@`. Both serializers reachable on this platform mark an attribute list `^`
  — `wak-sxml-tools` (`sxml-tools/upstream/sxml-tools.scm:44-48`) and
  `wak-htmlprag` (`htmlprag/htmlprag.scm:334`) — and neither recognises `@` at
  all: handed a `@`-marked tree, `srl:sxml->html` does not raise, it silently
  turns every attribute list into bogus child elements. `'attribute-marker
  'at` gives the specification's spelling. See ADR-0013.
- `&cmark-unsupported-node`, carrying the native type string. It derives from
  `&cmark-error` directly rather than from `&cmark-invalid-input`: the
  document is not invalid, the adapter is incomplete. The SXML adapter is the
  first consumer with no way to continue, since it has no HTML vocabulary for
  a node type it does not know.
- `&cmark-malformed-tree`, carrying a reason. `markdown-ast->sxml` is public
  and takes an arbitrary tree, so a caller can hand it a table whose header
  row is not first — an order cmark's own parser never produces
  (`extensions/table.c:402-403,447`) and whose faithful rendering would open a
  `thead` inside an open `tbody`.
- `chez-srfi` moved from `depends` to `depends/dev`, where it always belonged
  — `(cmark gfm)` imports none of it — and `wak-sxml-tools` added alongside
  it. Both are test-only; a consumer of this package acquires neither.

### Security

- **`raw-html` defaults to `omit` because it is the policy that does not
  depend on the caller's serializer.** Under `omit` a raw `html-block` or
  `html-inline` becomes `(*COMMENT* " raw HTML omitted ")`, reproducing
  `html.c:259` and `html.c:337` exactly: there is nothing to escape, because
  the tree holds no attacker-controlled markup at all, so the output is safe
  whatever serializer the caller chose. Under `escape` the literal is carried
  through as an ordinary string and the safety rests entirely on that
  serializer escaping it — a policy only as good as code this project does not
  control, which is why it is opt-in and why the third-party serializer suite
  exists. There is no trusted or unsafe mode and none is planned (ADR-0011):
  SXML has no portable raw-markup node, and a caller needing the literal reads
  it from the AST.
- `markdown->sxml` raises `&cmark-invalid-option` with reason
  `not-applicable` for `unsafe-html?`, `hardbreaks?`, and `nobreaks?`. All
  three are cmark **renderer** options — verified absent from `blocks.c`,
  `inlines.c`, and `parser.h` — so none can reach the AST, and SXML is a
  different renderer with its own policies. Silently discarding a
  security-relevant setting the caller made explicitly is not acceptable; the
  cost is one `cmark-options-with` line for a record shared with
  `markdown->html`, which makes the divergence explicit at the call site.
- **The URL rule is cmark's own**, transcribed from `src/scanners.re:345-354`:
  a URL is dangerous when it begins `javascript:`, `vbscript:`, `file:`, or
  `data:`, matched case-insensitively — re2c single-quoted literals are
  case-insensitive — **including cmark's `data:image` carve-out**, which lets
  `data:image/png`, `data:image/gif`, `data:image/jpeg`, and
  `data:image/webp` through. It applies to `link` `href` and `image` `src`
  only, and a rejected URL yields an empty attribute value rather than a
  raised condition or a removed attribute (`html.c:387-391,405-409`). Adopting
  cmark's rule rather than inventing one is what makes the corpus differential
  run with zero URL deltas.
- The adapter percent-encodes bytes outside `HREF_SAFE`
  (`src/houdini_href_e.c:32-44`) and never touches `&` or `'`; entity-escaping
  those is the serializer's half. `houdini_escape_href` does both jobs in one
  pass, and doing both halves in one place silently produces `%2520` or
  `&amp;amp;` — valid HTML carrying the wrong URL.

### Notes

- `source-positions?` is **accepted and silently discarded**, the one stated
  exception to the rule above. Unlike the three renderer-only options it
  refuses, positions genuinely reach the AST; it is the adapter that drops
  them, per ADR-0011. The cost is wasted parse work, not a downgraded policy.
  `markdown->sxml` therefore defaults to `(default-cmark-options)`, not
  `(default-ast-options)` — ADR-0009's per-entry-point principle pointing the
  other way from `markdown->ast`.
- The tree carries HTML vocabulary and nothing else (ADR-0011): no
  annotations, no `data-*` metadata, no source positions. List `delimiter`,
  `item` index, fence info past the first token, image child structure, and
  every source position are dropped, and `markdown->ast` remains the interface
  for all of them. That is what puts almost everything under the oracle: with
  no metadata channel, what the tree says about the document is what the HTML
  shows. Two properties still sit outside it and carry direct assertions
  instead — `raw-html: escape`, which cmark has no equivalent for, and
  `attribute-marker`, which the test serializer normalises away because it
  accepts `^` and `@` alike. See design spec §10.
- `tagfilter` has no observable effect on SXML. `extensions/tagfilter.c:58`
  registers only an HTML filter function — no postprocess, block, or inline
  handler — so it cannot reach the AST. Asserted rather than documented.
- Verified by re-serializing the tree through a test-only serializer written
  against `vendor/cmark-gfm/src/html.c` and diffing byte-for-byte against
  `markdown->html`, in-process, across all 744 examples of cmark's own corpus
  (`spec.txt` 672, `extensions.txt` 30, `smart_punct.txt` 16, `regression.txt`
  26), once per attribute marker. The second leg — the pinned `cmark-gfm` CLI,
  the independent witness that the parse itself was configured right — runs the
  four `tests/fixtures/*.md`, not the corpus; 744 × 2 subprocesses costs about
  13 s against a suite that otherwise finishes in 0.36 s. Design spec §10
  records that reduction and what it gives up. `raw-html: escape` and
  `attribute-marker` sit outside the oracle entirely and carry direct
  assertions only (design spec §10 again).
- **Byte-equality with cmark is a property of that serializer, not a promise
  about the caller's pipeline.** A conforming third-party serializer differs
  in inter-block whitespace, `"` in text, `'` in an `href`, childless-element
  form, and the document's trailing newline — all semantically equivalent
  HTML. A **pretty-printing** serializer is a different matter: injected
  indentation corrupts `<pre>` content. See README.org.

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
