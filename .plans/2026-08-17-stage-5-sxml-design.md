# Design Spec: Stage 5 — The SXML Adapter (release 0.3)

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** Milestone 5; ships as release **0.3** per ADR-0007
- **Related:** [project plan](chez-cmark-gfm-sxml-project-plan.md) §6.5, §10.4, §10.5, §11, §13.4 · [Stage 3 design](2026-08-17-stage-3-ast-design.md) · ADR-0007, ADR-0009, ADR-0010, ADR-0011, ADR-0012

## 1. Scope

Stage 5 adds the optional SXML adapter: a pure transformation from the Scheme AST
into an SXML tree using HTML vocabulary, which a conforming SXML serializer renders
as an HTML fragment.

**Exit criterion** (plan §15, M5): representative CommonMark and GFM documents
produce safe, structurally correct SXML. Operationally — every example in cmark's
own test corpus, serialized from our tree, is byte-identical to `markdown->html`
for the same parse.

**In scope:** `(cmark gfm sxml)` and `markdown-ast->sxml`; `markdown->sxml` in
`(cmark gfm)`; `make-sxml-options` with the `raw-html` policy; the URL policy;
the corpus differential harness and its test-only HTML serializer; the
third-party serializer suite; `wak-sxml-tools` as a dev dependency.

**Out of scope:** source positions in SXML output, an annotation channel, a
trusted raw-HTML mode, URL-policy customisation, `data-sourcepos`, footnotes,
`markdown->latex` and `markdown->man`, and every plan §3 non-goal. Milestone 4
has no separate stage; its remainder landed in Stage 3 (see that spec §1.1).

### 1.1 What "optional" means here

Plan §4.1 makes the SXML library the fourth layer and §5 requires that the core
not depend on it. Stage 5 keeps that in both directions: `(cmark gfm sxml)`
imports nothing from the native layers, and no existing library imports it. A
caller who never mentions SXML links no new code and acquires no new dependency —
`wak-sxml-tools` is test-only.

## 2. Module layout

```text
src/cmark/gfm/sxml.sls              NEW  pure: AST -> SXML
src/cmark/gfm.sls                   EDIT re-export; markdown->sxml
src/cmark/gfm/options.sls           EDIT make-sxml-options, sxml-options-with
src/cmark/gfm/private/conditions.sls EDIT &cmark-unsupported-node
tests/test-sxml.sps                 NEW  pure unit suite
tests/test-sxml-differential.sps    NEW  corpus differential
tests/test-sxml-serializer.sps      NEW  unit suite for the serializer above
tests/test-sxml-portability.sps     NEW  third-party serializer suite
tests/sxml-html-serializer.sls      NEW  test-only, mirrors src/html.c
tests/spec-corpus.sls               NEW  test-only, parses cmark's spec files
```

### 2.1 The adapter is pure; the convenience entry point is not

`(cmark gfm sxml)` imports only pure libraries: `(rnrs)`, `(cmark gfm ast)`,
`(cmark gfm options)` for the policy accessors, and `(cmark gfm private
conditions)` for the raise. The last three are each `(import (rnrs))` and
nothing more, so none of them can reach a shared object. The conversion
is Scheme records to Scheme lists; nothing in it needs a shared object, and
`tests/test-sxml.sps` therefore runs with `CHEZ_CMARK_GFM_SHIM=/nonexistent`.
`make check-purity` gains it as a third entry alongside `test-options.sps` and
`test-ast.sps`.

That is the reason `markdown->sxml` does **not** live in `sxml.sls`. It has to
parse, so it needs `(cmark gfm parse)`; putting it in the adapter would pull
`(cmark gfm private native)` into the import chain and forfeit the gate. It lives
in `(cmark gfm)`, which already imports both sides, and is a two-line composition
of `markdown->ast` and `markdown-ast->sxml`.

This is the same split `ast.sls` and `convert.sls` already use, for the same
reason: a suite that cannot load native code cannot pass because of native
behaviour.

### 2.2 Public API

```scheme
(markdown-ast->sxml ast)                      ; (default-sxml-options)
(markdown-ast->sxml ast sxml-opts)

(markdown->sxml md)                           ; (default-cmark-options) + defaults
(markdown->sxml md cmark-opts)
(markdown->sxml md cmark-opts sxml-opts)

(make-sxml-options 'raw-html 'omit)
(default-sxml-options)
(sxml-options-with opts 'raw-html 'escape)
```

## 3. Options

### 3.1 `make-sxml-options`

Three fields in 0.3:

| Key | Values | Default |
|---|---|---|
| `raw-html` | `omit`, `escape` | `omit` |
| `softbreak` | `newline`, `break`, `space` | `newline` |
| `attribute-marker` | `caret`, `at` | `caret` |

`softbreak` exists because cmark's `hardbreaks?` and `nobreaks?` are renderer
options that never reach the parse, so no AST can carry them —
`markdown->sxml` refuses all three renderer-only options rather than discard
them silently (§3.2). `attribute-marker` exists because the two SXML
serializers available on this platform use `^`, not the specification's `@`;
see ADR-0013.

A record rather than a bare symbol argument, for three reasons: it matches
`make-cmark-options`, so callers meet one convention rather than two; it inherits
that library's unknown-key and duplicate-key rejection, which a bare symbol cannot
have; and a later field costs no arity change at any call site.

### 3.2 `markdown->sxml` rejects `unsafe-html?`

`unsafe-html?` is a cmark **renderer** policy. Stage 3 established that it has no
effect on the AST, and the adapter takes only the AST — so it cannot reach SXML
even in principle. The adapter has its own policies: `raw-html` and the URL rule
in §5.2.

Silently ignoring it is not acceptable. A caller who explicitly set a
security-relevant option and had it discarded is precisely the failure `AGENTS.md`
names when it says to prefer a check to a comment. `markdown->sxml` therefore
raises `&cmark-invalid-option` with reason `not-applicable` when the options
record carries `'unsafe-html? #t`.

The cost is real and accepted: a caller with one options record shared between
`markdown->html` and `markdown->sxml` must derive a variant with
`cmark-options-with`. That is one line, and it makes the divergence in security
semantics between those two calls explicit at the call site rather than invisible.

There is no unsafe mode for SXML, and none is planned. See ADR-0011.

### 3.3 Source positions default off

`markdown->sxml` defaults to `default-cmark-options`, where `source-positions?` is
`#f`. ADR-0009 chose per-entry-point defaults on the principle that the default
serves the consumer: the AST carries positions, so `markdown->ast` turns them on.
SXML carries none, so turning them on would cost a flag in the parse for
information that never reaches the output.

This is assertable, not merely documented — see §8.1.

### 3.4 `&cmark-unsupported-node` is new

The condition set has nine types and none of them fits. Plan §12 calls for an
"unsupported native node type" condition, but Stage 3 chose preservation over
raising — an unrecognised type becomes an `extension` node carrying its native
type string — so it was never needed. The SXML adapter is the first consumer with
no way to continue: it has no HTML vocabulary for a node type it does not know.

```scheme
(define-condition-type &cmark-unsupported-node &cmark-error
  make-cmark-unsupported-node cmark-unsupported-node?
  (type cmark-unsupported-node-type))   ; the native type string
```

It derives from `&cmark-error` directly rather than `&cmark-invalid-input`: the
document is not invalid, the adapter is incomplete. Dropping the node instead
would lose content silently, which is the behaviour plan §7.4 rejects.

## 4. The mapping

### 4.1 Node table

Every row is the shape a conforming serializer must render as the cited cmark
output.

| AST node | SXML | cmark |
|---|---|---|
| `document` | `(*TOP* …)` | — |
| `heading` level *n* | `(h1 …)` … `(h6 …)` | `html.c:201` |
| `paragraph` | `(p …)` — but see §4.2.1 | `html.c:287` |
| `text` | string | `html.c:311` |
| `emph` | `(em …)` | `html.c:376` |
| `strong` | `(strong …)` | `html.c:366` |
| `strikethrough` | `(del …)` | `extensions/strikethrough.c:132` |
| `blockquote` | `(blockquote …)` | `html.c:151` |
| `list`, bullet | `(ul …)` | `html.c:170` |
| `list`, ordered, start = 1 | `(ol …)` | `html.c:174` |
| `list`, ordered, start ≠ 1 | `(ol (@ (start "N")) …)` | `html.c:178` |
| `item`, plain | `(li …)` | `html.c:190` |
| `item`, task, checked | `(li (input (@ (type "checkbox") (checked "") (disabled ""))) " " …)` | `extensions/tasklist.c:125` |
| `item`, task, unchecked | `(li (input (@ (type "checkbox") (disabled ""))) " " …)` — no `checked` at all | `extensions/tasklist.c:127` |
| `link` | `(a (@ (href …) (title …)) …)` | `html.c:384` |
| `image` | `(img (@ (src …) (alt …) (title …)))` | `html.c:402` |
| `code` | `(code …)` | `html.c:329` |
| `code-block`, no info | `(pre (code …))` | `html.c:218` |
| `code-block`, info | `(pre (code (@ (class "language-X")) …))` | `html.c:242` |
| `thematic-break` | `(hr)` | `html.c:280` |
| `linebreak` | `(br)` | `html.c:315` |
| `softbreak` | `"\n"` | `html.c:319` |
| `softbreak`, `hardbreaks?` | `(br)` | `html.c:320` |
| `softbreak`, `nobreaks?` | `" "` | `html.c:322` |
| `html-inline` / `html-block` | see §5.1 | `html.c:259, 337` |
| `table` | `(table …)` | `extensions/table.c:756` |
| `table-row` | see §4.2.2 | `extensions/table.c:774` |
| `table-cell`, header | `(th (@ (align …)) …)` | `extensions/table.c:798` |
| `table-cell`, body | `(td (@ (align …)) …)` | `extensions/table.c:798` |
| `extension` (unknown) | raises `&cmark-unsupported-node` (§3.4) | — |

Details the table compresses:

- **`title` is omitted, not empty.** `html.c:392` writes the `title` attribute only
  when `title.len` is non-zero. An empty `title` attribute is a byte difference.
- **`align` is omitted when the column has no alignment.** `extensions/table.c:806`
  switches on `'l'`, `'c'`, `'r'` and writes nothing otherwise. Our AST reports
  that case as `none`.
- **`align` appears on body cells.** Unlike the XML renderer, which ADR-0010
  recorded as emitting it only for header cells, the HTML renderer emits it for
  both. One of that ADR's three blind spots closes here.
- **`class="language-X"` takes the first token only.** `html.c:223-227` scans the
  info string to the first whitespace. The remainder is reachable only through
  `CMARK_OPT_FULL_INFO_STRING`, which this library does not expose.
- **`hr`, `br`, `img`, `input` are childless.** cmark writes them ` />`; the SXML
  element simply has no children, and how a serializer closes it is that
  serializer's business (§11).
- **An `extension` node raises.** Stage 3 preserves unrecognised native types
  rather than discarding them, and no such type is reachable through this
  library's options. The adapter has no HTML vocabulary for one, so it raises
  rather than guessing or dropping. Unit-tested via a hand-built node, as Stage 3
  tests its own unknown-type branch.

### 4.2 Three rules that are not node-for-node

These are where the bugs will be, and each gets its own assertions.

#### 4.2.1 Tight lists elide `<p>` entirely

`html.c:287-297` reads tightness from the paragraph's **grandparent** and, when the
list is tight, emits no `<p>` tags at all — the paragraph's children go straight
into the `<li>`. The adapter must carry the enclosing list's `tight?` down two
levels and splice rather than wrap.

A tight list is not a list whose paragraphs render compactly. It is a list with no
paragraph elements in its output at all.

#### 4.2.2 Table rows regroup into `thead` and `tbody`

Our AST is flat — `table` → `table-row` carrying `header?` → `table-cell`. HTML is
nested, and cmark's grouping is stateful (`extensions/table.c:774-797`): a header
row opens and closes `<thead>` around itself; the first non-header row opens
`<tbody>`, which stays open until the table ends. A table with no body rows emits
no `<tbody>`.

This is the only structural regrouping in the mapping. It is a fold over the row
list, not a per-node rewrite, and `markdown-node-map` is the wrong tool for it.

#### 4.2.3 Image alt is flattened by cmark, not by the serializer

`html.c:118-139`: on entering an `image`, cmark sets `renderer->plain` and renders
the subtree in plain mode into the `alt` attribute — `text`, `code`, and
`html-inline` contribute their literals, `linebreak` and `softbreak` contribute a
single space, every other node contributes nothing but is still descended into.

The adapter reproduces this to produce an `alt` **string**, because an SXML
attribute value is a string and cannot hold the child elements. Two consequences
worth stating: an image's inline structure does not survive into SXML, and an
`html-inline` inside an image contributes its literal to `alt` regardless of the
`raw-html` policy — safely, because it lands in an attribute value the serializer
escapes.

### 4.3 What the mapping loses

HTML vocabulary cannot express everything the AST holds. Lost, deliberately:

| Lost | Where it survives |
|---|---|
| `list` `delimiter` (period vs paren) | `markdown->ast` |
| `item` `index` | `markdown->ast` |
| fence info past the first token | `markdown->ast` |
| image child structure | `markdown->ast` |
| all source positions | `markdown->ast` |
| raw HTML literals | `markdown->ast` |

This is a consequence of ADR-0011, not an oversight, and it is why the AST is the
documented answer for inspection and transformation. It is also what makes the
oracle in §6 total.

## 5. Safety

### 5.1 Raw HTML

| Policy | `html-block` / `html-inline` becomes |
|---|---|
| `omit` (default) | `(*COMMENT* " raw HTML omitted ")` |
| `escape` | the literal, as an ordinary string |

`omit` reproduces `html.c:259` and `html.c:337` exactly.

The two differ in more than output, and the difference decides the default. Under
`omit` there is **nothing to escape**: the tree contains no attacker-controlled
markup, so the result is safe whatever serializer the caller chose. Under `escape`
the safety rests entirely on the serializer escaping that string — the policy is
only as good as code we do not control. That is why `escape` is opt-in, and why
§6.6's suite exists.

`escape` also matches `markdown->html` in neither bytes nor behaviour, so it has no
oracle. See §8.3 and §10.

Plan §10.4's `'trusted` mode is not implemented: SXML has no portable
raw-markup node. The 3.0 grammar provides `*TOP*`, `*PI*`, `*COMMENT*`, `*ENTITY*`,
and `@`, none of which mean "emit these bytes verbatim", so a trusted mode would
require inventing a node type no serializer honours. Plan §10.4's `'reject` is
deferred as unused surface. Both are recorded in ADR-0011; a caller needing the
raw literal reads it from the AST, which preserves it.

### 5.2 URLs

The policy is cmark's own, from `src/scanners.re:345-354`: a URL is dangerous when
it begins `javascript:`, `vbscript:`, `file:`, or `data:`, matched
case-insensitively — re2c single-quoted literals are case-insensitive — with
`data:image/png`, `data:image/gif`, `data:image/jpeg`, and `data:image/webp`
allowed through. It applies to `link` `href` and `image` `src` only.

A rejected URL yields an **empty** attribute value, not a raised condition and not
a removed attribute, matching `html.c:387-391` and `html.c:405-409`.

Adopting cmark's rule rather than plan §10.5's own list is what makes the corpus
differential run with zero URL deltas. The lists agree on the four schemes; cmark
additionally carves out inline images, which the plan does not mention.
Customisation is deferred — see §10.

### 5.3 The escaping split

cmark renders hrefs with `houdini_escape_href` (`src/houdini_href_e.c:32-100`),
which does two different jobs in one pass: it percent-encodes every byte outside
`HREF_SAFE`, and it escapes `&` → `&amp;` and `'` → `&#x27;` as HTML entities.

Only the first is a property of the value. The second is serialization. The
adapter must therefore perform exactly one half:

| Stage | Does | Must never do |
|---|---|---|
| Adapter | Percent-encodes bytes outside `HREF_SAFE` | Touch `&` or `'` |
| Serializer | `&`→`&amp;`, `'`→`&#x27;` in `href`/`src`; `escape_html` elsewhere | Percent-encode |

Their composition is `houdini_escape_href`. Getting the boundary wrong in either
direction is silent and produces `%2520` or `&amp;amp;` — both of which are valid
HTML carrying the wrong URL, so only a byte comparison catches them.

Note that `escape_html` (`src/houdini_html_e.c:18-33`) escapes `"` in **text**, not
only in attributes; `'` and `/` are escaped only under the `secure` flag, which
cmark does not set here. The test-only serializer mirrors this. A third-party
serializer will not, which is a documented delta rather than a defect (§11).

### 5.4 tagfilter has no observable effect on SXML

`extensions/tagfilter.c:58` registers `cmark_syntax_extension_set_html_filter_func`
and nothing else — no postprocess, no block or inline handler. The extension exists
solely to neuter raw HTML passing through cmark's HTML renderer, so it cannot reach
the AST and cannot reach SXML. Under `omit` there is no HTML to filter; under
`escape` the literal is already inert text.

Someone enabling `tagfilter` and expecting it to matter for SXML would be wrong,
so this is asserted rather than left to the documentation: SXML output is
byte-identical with the extension on and off.

## 6. Verification: cmark's HTML as the oracle

### 6.1 Why this oracle cannot be tuned

The same property ADR-0010 relies on. A test-only serializer renders our SXML into
HTML, and the result is compared byte-for-byte against `markdown->html` for the
same parse. The expectation is produced by cmark, so "adjust the expectation until
it passes" is not available.

The serializer is generic over the tree: it maps an element name to a tag, an
attribute list to attributes, and consults a static table for which tags are
childless and where newlines fall. It never inspects the Markdown and has no
node-type knowledge to compensate with — so an adapter that emits `(em …)` where
cmark emits `<strong>` produces a byte difference, not a serializer that quietly
agrees. ADR-0012 records this.

### 6.2 The corpus

`vendor/cmark-gfm/test/`, pinned to the same submodule commit the library links
against:

| File | Examples |
|---|---|
| `spec.txt` | 672 |
| `extensions.txt` | 30 |
| `smart_punct.txt` | 16 |
| `regression.txt` | 26 |
| **Total** | **744** |

Only the Markdown side is used. The expected-HTML side is cmark's own
record of its behaviour at some past revision and is normalised by their Python
harness before comparison; our oracle is the pinned library itself, which is
stricter and cannot drift from the code under test.

`tests/spec-corpus.sls` parses the fenced `example` blocks — the delimiter is a run
of at least 32 backticks followed by `example`, with `.` on its own line separating
input from expected output. The count of examples extracted is asserted against the
table above, so a parser that silently matches nothing cannot report success.

### 6.3 The test-only serializer

`tests/sxml-html-serializer.sls`, written against `src/html.c` and judged against
cmark's bytes. Two behaviours are less obvious than they look:

- **Newlines are collapsed, not appended.** `cmark_html_render_cr`
  (`src/html.h:8-11`) emits `\n` only when the buffer does not already end in one.
  A serializer that unconditionally appends a newline after each block agrees on
  most documents and diverges wherever two block boundaries meet.
- **Attribute escaping is per-attribute.** `href` and `src` take the entity half of
  `houdini_escape_href` (§5.3); every other attribute and all text take
  `escape_html`.

Whitespace does not live in the tree. Block-boundary newlines are formatting and
belong to the serializer; the newline a `softbreak` produces is content from
cmark's own inline stream and is a text node.

### 6.4 Why both legs

In-process against `markdown->html`, then against the pinned CLI, as in Stages 2
and 3.

The second leg is not redundant. Both our SXML path and `markdown->html` consume a
document parsed through our shim, so a wrong option bit or a missing extension
corrupts the parse feeding **both sides** — they would agree with each other while
both being wrong. The CLI is the independent witness that the parse was configured
correctly in the first place.

Each leg carries a discrimination guard proving its comparator can report a
difference at all, for the reason Stage 2 §7.3 and ADR-0010 both give: a parity
assertion whose comparator always returns "equal" passes against anything.

### 6.5 The oracle is total

Stage 3's oracle had three blind spots — `item` index, table `columns`, and
body-cell alignment — which needed direct assertions. This one has none.

That follows from ADR-0011. Because the tree carries no metadata channel, every
piece of information in an SXML tree is information the HTML shows; there is no
property that a byte comparison against cmark's HTML cannot see.

Of ADR-0010's three blind spots, one genuinely closes: body-cell alignment, which
the HTML renderer emits (`extensions/table.c:806`) and the XML renderer withheld.
The other two are not gaps here because they are not subject matter — `item` index
is not carried into SXML, and table `columns` is never read, since the adapter
builds cells from the row's children rather than from the count. Both remain
covered by Stage 3's direct assertions, where they belong.

The one behaviour outside the oracle's reach is `raw-html: escape`, which cmark has
no equivalent for. It is covered by direct assertions and named in §10.

### 6.6 What a third-party serializer proves that ours cannot

Two things, and both are structural rather than incidental:

1. **That the tree is conforming SXML** a tool written to the specification
   accepts — not merely something our own serializer handles.
2. **That escaping actually happens.** Plan §10.4's "emit text nodes as Scheme
   strings for serializer escaping" is a claim about somebody else's code. Testing
   it with our own serializer proves nothing about it. This is the adapter's entire
   security claim under `escape`, and the only way to test it is to run a real
   serializer.

## 7. Dependencies

### 7.1 `wak-sxml-tools`

| | |
|---|---|
| Version | `0.0.0-akku.1.5c14730` |
| Upstream | `https://gitlab.com/wak/wak-sxml-tools.git` |
| Licence | MIT |
| Used | `(wak sxml-tools serializer)` — `srl:sxml->html` |

MIT avoids any licence question against the project's BSD-3-Clause even as a dev
dependency, and the package descends from the same Lizorkin/Kiselyov lineage as the
SXML specification, which makes it the strongest available witness that our tree is
conforming SXML rather than merely tolerated by one tool. `wak-htmlprag` was the
alternative; it is LGPL-3.0-or-later and plan §5 already names it as the thing the
core must not require.

It follows the `chez-srfi` pattern exactly: an Akku dependency **and** a git
submodule pinned to the same commit, symlinked into `build/scheme-libs` by
`make deps`, with `make check-pins` extended to enforce the equality. Akku's
downloader is not on the build path, which is why the submodule exists at all.

### 7.2 `Akku.manifest` correction

`chez-srfi` currently sits in `(depends …)` despite being test-only — `(cmark gfm)`
imports none of it. Both it and `wak-sxml-tools` belong in `(depends/dev …)`.
A consumer of this package should not acquire either.

## 8. Testing and exit gate

### 8.1 Suites

**`tests/test-sxml.sps`** — pure, runs under `check-purity`.

- Every row of §4.1, against hand-built AST nodes.
- `title` omitted when empty, present when not.
- `align` omitted for `none`, present for each of `left`, `center`, `right`, on
  header **and** body cells.
- `class="language-X"` takes the first token of a multi-token fence info.
- Tight and loose lists: a tight list's output contains no `p` element; a loose
  list's does.
- Table grouping: header-only, body-only, both, and multiple body rows —
  asserting `thead`/`tbody` presence and absence.
- Image `alt` flattening, including nested emphasis, a `code` child, a
  `softbreak`, and an `html-inline` child.
- Percent-encoding of a URL containing a space and a non-ASCII character, with
  `&` and `'` asserted to pass through **untouched** (§5.3).
- Each dangerous scheme, in mixed case, yielding an empty attribute; each
  `data:image/*` subtype passing through; `data:text/html` rejected.
- `raw-html` `omit` and `escape` on both `html-block` and `html-inline`.
- An `extension` node raising `&cmark-unsupported-node`.
- `markdown-ast->sxml` on a document produced before the options record existed —
  i.e. the adapter reads nothing but the AST.

**`tests/test-sxml-differential.sps`** — the corpus, both legs, per §6.4.

- 744 examples × `omit` × default options, byte-identical, in-process and CLI.
- Option sweep in the Stage 2 style over the five extensions, `hardbreaks?`,
  `nobreaks?`, and `smart?`.
- Two no-effect assertions: output byte-identical with `source-positions?` on and
  off (§3.3), and with `tagfilter` on and off (§5.4).
- A discrimination guard per leg.

**`tests/test-sxml-portability.sps`** — `wak-sxml-tools`, per §6.6.

- The tree from each of the four existing fixtures is accepted.
- A `text` node holding `<script>alert(1)</script>` serializes escaped — asserted
  on the absence of an unescaped `<script` substring **and** the presence of the
  escaped form, because absence alone passes against empty output.
- An attribute value holding `"` serializes escaped.
- `<pre>` content survives with no injected indentation.

**`tests/test-options.sps`** — extended.

- `make-sxml-options` rejects unknown keys, duplicate keys, and an unknown
  `raw-html` value.
- `markdown->sxml` raises `&cmark-invalid-option` on `'unsafe-html? #t` (§3.2).

### 8.2 Exit gate

- `make test` green, including all three new suites.
- `make check-purity` green with `test-sxml.sps` added.
- `make check-pins` green with `wak-sxml-tools` added.
- `make test-memory` green — the adapter allocates nothing native, but
  `markdown->sxml` parses, and that path must stay clean.
- Every assertion in §8.1 recorded in `.plans/stage-5-mutation-log.md` with the
  mutation that broke it, by name.

### 8.3 Planned mutations

Each must fail the named assertion and nothing else.

| Mutation | Must break |
|---|---|
| Emit `(p …)` inside tight lists | tight-list assertion; corpus |
| Open `<tbody>` for every body row | table grouping; corpus |
| Omit `align` on body cells | body-cell alignment; corpus |
| Emit `title=""` when the title is empty | title omission; corpus |
| Percent-encode `&` in the adapter | escaping-split; corpus |
| Escape `&` in the adapter *and* the serializer | escaping-split; corpus |
| Use the whole fence info as the class | language-class; corpus |
| Flatten image `alt` without descending | alt assertion; corpus |
| Drop the `data:image/*` carve-out | URL assertion; corpus |
| Compare URL schemes case-sensitively | mixed-case URL assertion; corpus |
| Append newlines unconditionally in the serializer | corpus, at adjacent block boundaries |
| Make the corpus parser match zero examples | corpus example-count assertion |
| Make the differential comparator always return equal | discrimination guard |
| Let `markdown->sxml` accept `'unsafe-html? #t` | options assertion |
| Give `tagfilter` an effect on the tree | no-effect assertion |

## 9. Invariants enforced as checks, not comments

Per `AGENTS.md`: a load-bearing comment is a signal it should not be a comment.

| Invariant | Check |
|---|---|
| The adapter reaches no native code | `make check-purity`, `test-sxml.sps` |
| `wak-sxml-tools` submodule and `Akku.lock` name one commit | `make check-pins` |
| `source-positions?` does not affect SXML | differential no-effect assertion |
| `tagfilter` does not affect SXML | differential no-effect assertion |
| The corpus parser actually found the examples | example-count assertion |
| The comparator can report a difference | discrimination guard, per leg |
| Escaping happens in a real serializer | `test-sxml-portability.sps` |

## 10. Deliberate coverage gaps

- **`raw-html: escape` has no oracle.** cmark has no equivalent behaviour, so it
  carries direct assertions only. Recorded here rather than left implicit.
- **`extension` nodes are unit-tested, not reached end to end.** No unknown node
  type is producible through this library's options, exactly as Stage 3 found.
- **Non-default URL policies are untested because they do not exist.** Deferred
  to 0.4; adding one would put it outside the differential's coverage, which is
  the reason it is not in 0.3.
- **A caller's serializer is tested for escaping and conformance, not for byte
  equality.** §11 explains why that is not a gap.

## 11. Documented deltas from a caller's serializer

Byte-equality with cmark is a property of the serializer in `tests/`, not of
whichever one a caller picks. A conforming third-party serializer will differ in:

| | cmark | Typical serializer |
|---|---|---|
| Between blocks | `\n` | nothing |
| `"` in text | `&quot;` | `"` |
| `'` in an `href` | `&#x27;` | `'` |
| Childless elements | `<hr />` | `<hr>` or `<hr></hr>` |

All four are semantically equivalent HTML, and none affects what the document
means. This belongs in the README so that nobody reads "byte-identical to cmark"
as a promise about their own pipeline.

A **pretty-printing** serializer is a different matter: injected indentation
corrupts `<pre>` content and changes inline spacing. That is a warning, and
`test-sxml-portability.sps` asserts our chosen serializer does not do it.

## 12. Release 0.3

`CHANGELOG.md` gains a 0.3.0 entry covering `markdown->sxml`, `markdown-ast->sxml`,
`make-sxml-options`, the two raw-HTML policies, the URL policy and its provenance,
the `unsafe-html?` rejection, and — under **Security** — that `omit` is the default
because it is the policy that does not depend on the caller's serializer.

`README.org` gains an SXML section with the mapping table, the deltas in §11, the
pretty-printer warning, and a statement that the AST remains the answer for
positions and for the properties in §4.3.

## 13. References

- [Project plan](chez-cmark-gfm-sxml-project-plan.md) §6.5, §10.4, §10.5, §11, §13.4, §15 M5
- [Stage 3 design](2026-08-17-stage-3-ast-design.md) — the AST this adapter consumes
- ADR-0007 — incremental release staging
- ADR-0009 — per-entry-point source-position defaults
- ADR-0010 — XML as the AST oracle; the pattern §6 reuses
- ADR-0011 — SXML carries HTML vocabulary only
- ADR-0012 — cmark's HTML renderer as the SXML oracle
- `vendor/cmark-gfm/src/html.c`, `src/html.h`, `src/houdini_html_e.c`,
  `src/houdini_href_e.c`, `src/scanners.re`
- `vendor/cmark-gfm/extensions/table.c`, `tasklist.c`, `strikethrough.c`,
  `tagfilter.c`
- [SXML specification 3.0](https://okmij.org/ftp/Scheme/SXML.html)
