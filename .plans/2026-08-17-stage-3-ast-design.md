# Design Spec: Stage 3 — Scheme AST and Resource Limits (release 0.2)

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** Milestone 3 plus the unfinished remainder of Milestone 4; ships as release **0.2** per ADR-0007
- **Related:** [project plan](chez-cmark-gfm-sxml-project-plan.md) §6.4, §7, §9.7, §12, §13.2 · [Stage 2 design](2026-08-16-stage-2-renderers-design.md) · ADR-0002, ADR-0003, ADR-0005, ADR-0006, ADR-0007, ADR-0008

## 1. Scope

Stage 3 adds the Scheme-owned AST: `markdown->ast` returns immutable records that
contain no native pointers and remain valid after every cmark object has been freed.
It also lands the two resource limits the AST makes necessary, because the AST is the
first operation whose output size is unbounded by the input-size limit alone.

**Exit criterion** (plan §15, M3): the returned AST contains no native pointers and
remains valid after native cleanup; the copied tree matches cmark's own serialization
of the same parse; counters balance on success and on every failure path; Valgrind
clean on Linux.

**In scope:** `markdown->ast`; `(cmark gfm ast)` — the node and source-position
records with their accessors and functional helpers; `(cmark gfm private convert)` —
the native traversal; `max-nodes` and `max-depth`; `default-ast-options`;
`&cmark-resource-limit`; the AST-to-XML differential harness; the deep-nesting
corpus; documenting the AST as untrusted structured input.

**Out of scope:** the SXML adapter (Stage 5 / release 0.3), footnotes,
`markdown->latex` and `markdown->man`, native AST mutation, and every plan §3
non-goal.

### 1.1 Why M4's remainder lands here rather than in its own stage

ADR-0007 assigns M3 and M4 both to 0.2. Most of M4's checklist already shipped in
0.1: safe-mode confirmation, `unsafe-html?` as explicit opt-in, embedded-NUL
rejection, `max-input-bytes`, version-mismatch failure, and library-resolution
tests. What genuinely remains is resource exhaustion and the hostile corpus — and
`max-nodes` and `max-depth` exist precisely to bound the Scheme allocation the AST
copy performs. They are meaningless without the AST. Deferring them would ship the
one unbounded operation in the library in the same release that introduces it.

## 2. Module layout

Follows plan §5. No structure the plan did not ask for.

| Path | Layer | New | Holds native pointers |
|---|---|---|---|
| `src/cmark/gfm/ast.sls` | 3 (public) | **yes** | **No — imports nothing native** |
| `src/cmark/gfm/private/convert.sls` | 2 | **yes** | Yes |
| `src/cmark/gfm/parse.sls` | 3 (public) | **yes** | No |
| `src/cmark/gfm/options.sls` | 3 (public) | no | No |
| `src/cmark/gfm.sls` | 3 (façade) | no | No |
| `src/cmark/gfm/private/native.sls` | 2 | no | Yes (extended) |
| `src/cmark/gfm/private/limits.sls` | 2 | no | No (extended) |
| `src/cmark/gfm/private/conditions.sls` | 2 | no | No (extended) |
| `src/cmark-gfm-shim.c` | 1 | no | n/a (one function added) |

`convert.sls` is the only new file permitted to hold a native pointer, and it holds
one only for the duration of a single traversal driven from inside
`call-with-native-document`'s body.

`parse.sls` is the layer-3 entry point for `markdown->ast`. It exists so that
`convert.sls` stays layer 2: a public export inside layer 2 would force
`convert.sls` to import the options record, inverting the layering. It mirrors
`render.sls`, which unpacks the same record into option bits.

### 2.1 `ast.sls` extends the existing purity gate

`ast.sls` must import no library that loads a shared object, for the same reason
`options.sls` must not: it is what makes every assertion in the node-algebra suite
unable to pass by accident because of native behaviour.

That invariant is already executable. `make check-purity` runs `test-options.sps`
with `CHEZ_CMARK_GFM_SHIM` poisoned to a nonexistent absolute path — if anything in
the import chain reaches `(cmark gfm private native)`, its library body raises
`&cmark-shim-unavailable` at *import* time and the suite fails outright. CI runs it
(`.github/workflows/ci.yml:79`).

Stage 3 **extends that target to `tests/test-ast.sps`**. The Makefile's existing
caveat carries over unchanged: Chez instantiates an imported library's body only
when something references one of its bindings, so an import that is added but never
called is invisible to the probe. A real accidental dependency is one `ast.sls`
actually calls, and that is what trips it.

### 2.2 The functional core / imperative shell split

- `ast.sls` is pure: records, predicates, accessors, property lookup, functional
  update, `markdown-node-map`, `markdown-node-fold`. It knows nothing about cmark.
- `convert.sls` is the shell: it reads native nodes through `scope.sls`'s checked
  accessors, copies every borrowed string at the moment of read, and calls
  `ast.sls`'s constructors. It contains the traversal, the limit counters, and the
  type-dispatch table.

The node model is therefore testable, and tested, with no cmark present.

## 3. The node model — `(cmark gfm ast)`

### 3.1 Records

Plan §7.1 verbatim, plus one lookup helper:

```scheme
(make-markdown-node type properties children source)
(markdown-node? x)
(markdown-node-type node)         ; symbol
(markdown-node-properties node)   ; immutable alist, symbol keys
(markdown-node-children node)     ; list of markdown-node
(markdown-node-source node)       ; source-position or #f

(markdown-node-property node key)          ; #f when absent
(markdown-node-property node key default)

(markdown-node-with-properties node properties)
(markdown-node-with-children node children)
(markdown-node-map proc node)
(markdown-node-fold proc seed node)

(make-source-position start-line start-column end-line end-column)
(source-position? x)
(source-position-start-line p) (source-position-start-column p)
(source-position-end-line p)   (source-position-end-column p)
```

`(cmark gfm)` re-exports all of the above plus `markdown->ast`, for the same reason
it re-exports the condition types (Stage 2 §2.2): the façade is the supported import,
and a caller should not have to know which file a record lives in.

An accessor applied to a non-node raises R6RS `&assertion` from the record accessor
itself. `ast.sls` adds no argument-checking layer of its own — a wrong type here is a
programming error in Scheme-only code, not one of the native or option failures
`&cmark-error` exists to describe.

Children are a **list**, not a vector: the two traversal helpers are the intended
access path and neither wants random access.

Properties are an **immutable alist**. No node type carries more than four
properties, so a mapping structure would cost more than it saves, and an alist is
directly comparable in tests.

### 3.2 Traversal helper semantics

- `markdown-node-map` rebuilds **children-first**: `proc` receives a node whose
  children have already been mapped, and returns the replacement node.
- `markdown-node-fold` is **pre-order**: `proc` receives `(node accumulator)` and
  returns the new accumulator, parent before children, children left to right.

Both orders are asserted by test. An ordering guarantee stated only in a docstring
is exactly the kind of load-bearing comment AGENTS.md requires to become a check.

Both helpers recurse. They operate on trees already bounded by `max-depth`
(§6), so no separate limit applies to them.

### 3.3 Type and property table

Dispatch is on `cmark_node_get_type_string`, never on the numeric enum — the
extension node types are assigned at runtime by
`cmark_syntax_extension_add_node` (`vendor/cmark-gfm/extensions/table.c:871-873`),
so their numeric values are not constants at all.

Given the options this library exposes, the reachable type strings are exactly these
24:

| cmark type string | node type | properties |
|---|---|---|
| `document` | `document` | none |
| `paragraph` | `paragraph` | none |
| `block_quote` | `blockquote` | none |
| `thematic_break` | `thematic-break` | none |
| `softbreak` | `softbreak` | none |
| `linebreak` | `linebreak` | none |
| `emph` | `emph` | none |
| `strong` | `strong` | none |
| `strikethrough` | `strikethrough` | none |
| `heading` | `heading` | `level` |
| `text` | `text` | `literal` |
| `code` | `code` | `literal` |
| `html_inline` | `html-inline` | `literal` |
| `html_block` | `html-block` | `literal` |
| `code_block` | `code-block` | `literal` `fence-info` |
| `link` | `link` | `url` `title` |
| `image` | `image` | `url` `title` |
| `list` | `list` | `kind` `start` `tight?` `delimiter` |
| `item` | `item` | `index` `task?` `checked?` |
| `tasklist` | `item` | `index` `task?` `checked?` |
| `table` | `table` | `columns` `alignments` |
| `table_header` | `table-row` | `header?` |
| `table_row` | `table-row` | `header?` |
| `table_cell` | `table-cell` | `alignment` |

Property value domains:

| Property | Value |
|---|---|
| `level` | exact integer 1–6 |
| `literal` `url` `title` `fence-info` | string (possibly empty) |
| `kind` | `bullet` or `ordered` |
| `start` | exact non-negative integer (0 for a bullet list) |
| `tight?` `task?` `checked?` `header?` | boolean |
| `delimiter` | `none`, `period`, or `paren` |
| `index` | exact non-negative integer |
| `columns` | exact non-negative integer |
| `alignments` | list of `left` / `center` / `right` / `none`, length `columns` |
| `alignment` | `left`, `center`, `right`, or `none` |

### 3.4 Key sets are uniform per node type

A plain `item` carries `task? #f` **and** `checked? #f`; a `table-row` from either
type string carries `header?`. Two reasons:

1. The §9 key-set assertion compares a fixed set per node type rather than a
   conditional one, so "the converter forgot `fence-info`" and "the converter
   invented a key" are both single-comparison failures.
2. Consumers never branch on key presence. `checked?` is documented as meaningful
   only when `task?` is true.

This choice also makes the differential harness verify task detection for free. The
serializer emits `completed=` only when `task?` is true, mirroring
`extensions/tasklist.c:134-141`, so labelling a task item as plain or a plain item as
a task breaks the byte comparison in §8.

### 3.5 The AST is untrusted structured input

Per plan §4.4 and §10.3, the AST faithfully represents what was parsed, including raw
HTML literals and `javascript:` URLs. No sanitization happens during conversion, and
`unsafe-html?` has no effect on it — that option is a *renderer* policy. This is
stated in the README's AST section and in `ast.sls`'s header comment, because plan
§17 names "users assume AST content is sanitized" as a project risk.

## 4. Source positions — resolving ADR-0008

### 4.1 Corrected premise: `SOURCEPOS` is not purely a rendering flag

ADR-0008 concluded that `CMARK_OPT_SOURCEPOS`'s only observable effect in a
renderer-only release is markup, and deferred the AST question to this stage. The
stronger finding, verified here, is that the flag also changes the *recorded*
positions:

```c
/* vendor/cmark-gfm/src/inlines.c:292-296 */
static void adjust_subj_node_newlines(subject *subj, cmark_node *node,
                                      int matchlen, int extra, int options) {
  if (!(options & CMARK_OPT_SOURCEPOS)) {
    return;
  }
  ...
```

Positions are written onto every node unconditionally during parsing, but this
correction — which fixes `end_line`/`end_column` for a span crossing a newline, and
advances `subj->line` and `subj->column_offset` for everything parsed after it — is
skipped when the flag is off. Its callers are multi-line code spans
(`src/inlines.c:407`) and multi-line raw inline HTML (`src/inlines.c:999`,
`src/inlines.c:1009`).

So positions parsed without the flag are present but wrong, and wrong in a way that
propagates to later inlines in the same block. **The converter must never attach a
position record obtained from a parse without `SOURCEPOS`.** This rules out
"populate positions always and let the option govern only renderers".

### 4.2 Per-entry-point defaults, delivered by arity

```scheme
(markdown->ast markdown)          ; uses (default-ast-options): source-positions? #t
(markdown->ast markdown options)  ; uses the caller's record verbatim
```

`(default-ast-options)` is `(cmark-options-with (default-cmark-options)
'source-positions? #t)` — ordinary data, defined in `options.sls` alongside
`default-cmark-options`.

This is ADR-0008's own predicted resolution ("positions on for `markdown->ast`, off
for the renderers") and it needs no tri-state. The alternative — a `'unset` sentinel
in the options record so a per-entry-point default can tell "defaulted `#f`" from
"explicitly `#f`" — would put a third value into a field documented as boolean, and
every option-validation path would have to carry it.

Consequences:

- No 0.1 behaviour changes. `markdown->html` still emits clean markup at the
  defaults, so ADR-0008's decision stands rather than being reversed.
- The flag governs the parse bits and the attachment together, so an unreliable
  position can never reach a node: when `source-positions?` is `#f`,
  `markdown->ast` parses without `SOURCEPOS` **and** every `markdown-node-source`
  is `#f`.
- A caller who explicitly passes `'source-positions? #f` to `markdown->ast` is
  honoured.

ADR-0009 records this and supersedes ADR-0008's deferral.

### 4.3 A start line of zero means "no position"

`src/xml.c:48` guards its `sourcepos` attribute with `node->start_line != 0`. The
converter mirrors that exactly: a node whose start line is 0 gets `source` `#f` even
when positions are requested. This keeps the §8 serializer a straight mapping from
our record to cmark's output rather than a special case, and it is the honest
representation — cmark is reporting that it has no position for that node.

**This branch is ordinary, not defensive.** `softbreak` and `linebreak` nodes
genuinely carry `start_line == 0`: both are built by `make_simple` in
`src/inlines.c`, which never patches the position fields, unlike `emph` and
`strong`, which are patched explicitly. cmark's own XML shows it — a paragraph
carries a span and the break inside it carries none:

    $ printf 'one\ntwo\n' | cmark-gfm --to xml --sourcepos
      <paragraph sourcepos="1:1-2:3">
        ...
        <softbreak />
        ...
      </paragraph>

So every document containing a soft or hard line break exercises this guard, and
removing it fails three existing assertions. It is covered code, not an
untestable defence.

## 5. Conversion — `(cmark gfm private convert)`

### 5.1 Shape

```scheme
(markdown->ast markdown options)
  ;; 1. validate options (already done by the options constructor)
  ;; 2. call-with-native-document markdown bits names max-input-bytes
  ;; 3.   convert-tree root, bounded by max-nodes and max-depth
  ;; 4. return the Scheme tree; dynamic-wind releases every native resource
```

Conversion runs entirely inside `call-with-native-document`'s body, reading the root
through `doc-root`. The lifecycle is untouched from 0.1: ADR-0005's ordering and
ADR-0006's liveness flag apply unchanged, and no new native resource is acquired.

`convert-tree` recurses over `cmark_node_first_child` / `cmark_node_next`, per
ADR-0002 and plan §9.7. Recursion is safe here because `max-depth` bounds it before
Chez's heap-allocated, segmented stack becomes relevant, and because the bound is
enforced rather than assumed (§6.3).

### 5.2 Borrowed strings are copied at the moment of read

Every `const char *` accessor is declared `uptr` and converted with
`c-string->string` immediately, per the rule established in Stage 1. There is no
lazy or deferred read: the tree is fully materialized before `convert-tree` returns,
which is what makes it valid after teardown.

`c-string->string` maps NULL to `#f`. For every property in §3.3's table the
accessor is only ever called on a node type that supports it, so NULL is
unreachable; the converter nonetheless raises `&cmark-error` if it sees one rather
than putting `#f` where a string is documented. That defensive path's unreachability
is recorded in §11.

### 5.3 Tables

Three separate hazards, all verified in the vendored source:

**No public cell-index accessor.** `get_cell_alignment`
(`vendor/cmark-gfm/extensions/table.c:133-139`) reads `node->as.cell_index`, which is
not exported. Cell alignment is therefore derived positionally: a cell's zero-based
index among its row's children indexes the table's `alignments` list. An index at or
beyond `columns` yields `none` — cmark's own table parser truncates rows to
`n_columns`, so this is a bound check on an unreachable case, not a correction.

**The table accessors dereference without a NULL check.**
`cmark_gfm_extensions_get_table_columns` and `..._get_table_alignments`
(`extensions/table.c:878-890`) both test `node->type` with no guard on `node`
itself. They are called only from inside the `table` branch of the dispatch table,
where the type string has already been confirmed — the discipline is structural, not
a comment.

**`alignments` is a borrowed byte array.** It is `uint8_t *` of length `columns`,
holding `0`, `'l'`, `'c'`, or `'r'` (`extensions/table.c:387-391`). Bytes are read
through a new `alignment-bytes` marshalling procedure in `native.sls`, so
`foreign-ref` continues to appear in exactly one library. A NULL pointer yields all
`none`.

Header rows have their own type string, `table_header` versus `table_row`
(`extensions/table.c:523-535`), so `header?` has **two** independent sources: the
type string and `cmark_gfm_extensions_get_table_row_is_header`. The converter uses
the type string; a test asserts the two agree on every row of the GFM fixture, which
costs one assertion and turns a redundancy into a cross-check.

### 5.4 Task items

`cmark_gfm_extensions_get_tasklist_item_checked` returns `false` for an unchecked
task item **and** for a node that is not a task item at all
(`extensions/tasklist.c:30-40`) — it cannot distinguish them. Task detection
therefore comes from the type string: the tasklist extension's
`get_type_string_func` returns `"tasklist"` (`extensions/tasklist.c:13-17`), while a
plain list item is `"item"`.

## 6. Resource limits

### 6.1 The three limits

| Option | Default | Bounds |
|---|---|---|
| `max-input-bytes` | 5242880 (5 MiB) | the UTF-8 bytevector handed to cmark |
| `max-nodes` | 250000 | the number of Scheme node records built |
| `max-depth` | 1000 | traversal depth, and therefore recursion depth |

`max-nodes` is not redundant with `max-input-bytes`. Five MiB of `*a*\n` repeated
parses to millions of nodes, so the input limit does not bound the Scheme-side
allocation at all. 250,000 nodes is roughly two orders of magnitude above realistic
documents and keeps the copied tree in the tens of megabytes.

`max-depth` 1000 is far past any non-adversarial Markdown while being the thing that
makes recursive traversal safe.

Both are caller-settable options validated exactly as `max-input-bytes` is — exact
positive integer, `&cmark-invalid-option` with reason `invalid-value` otherwise — and
neither has an artificial ceiling, consistent with `max-input-bytes`, which has
none. `limits.sls` gains `default-max-nodes` and `default-max-depth` so each
constant keeps exactly one definition.

### 6.2 `&cmark-resource-limit` derives from `&cmark-invalid-input`

```scheme
(define-condition-type &cmark-resource-limit &cmark-invalid-input
  make-cmark-resource-limit cmark-resource-limit?
  (value cmark-resource-limit-value))    ; the ceiling that was exceeded
```

Constructed as `(make-cmark-resource-limit reason value)`, inheriting `reason` from
its parent.

One added field, not two. A `limit` field naming the category (`nodes` / `depth` /
`input-bytes`) would be one-to-one redundant with the inherited `reason`, and two
fields that must be kept in agreement forever is the invariant `limits.sls`'s own
header argues against: removing it beats asserting it. `reason` is the discriminator;
`value` is what `reason` cannot carry.

Plan §12 groups the three limits into one condition category, but 0.1 already ships
input-size overflow as `&cmark-invalid-input` with reason `'too-large`. Deriving the
new type from that one satisfies both: existing code guarding `cmark-invalid-input?`
keeps working unchanged, new code discriminates with `cmark-resource-limit?` and
reads the reason and the exceeded ceiling, and all three limits live in one type
hierarchy.

The split also separates two things `&cmark-invalid-input` currently conflates:
`'not-a-string` and `'embedded-nul` mean the input is malformed and retrying is
pointless, while a ceiling means the input is fine and the budget was too small —
the one input failure where retrying with a larger limit is a sensible response.

Input-size overflow starts raising the subtype as well. That is not a breaking
change: it is still `cmark-invalid-input?` with reason `'too-large`, so the 0.1
regression test for it passes untouched.

Reasons: `'too-large`, `'too-many-nodes`, `'too-deep`. `value` is the ceiling that
was exceeded — `max-input-bytes`, `max-nodes`, or `max-depth` as configured, not the
library default, so a caller that passed its own limit sees its own number back.

No `&cmark-unsupported-node-type` is added. Plan §12 lists one, but §7 chose
preservation over strictness, so nothing raises it.

### 6.3 Enforcement points

Depth: the document root is depth 1, a child is its parent's depth plus one. The
check runs **before** descending, so exceeding the limit raises instead of
recursing.

Nodes: a counter increments as each record is built; exceeding the limit raises.

Both raise from inside `call-with-native-document`'s body, so its after-thunk frees
the parser and root on the way out and the partially built Scheme tree is simply
dropped. Every limit test asserts `live-counts` is back to baseline afterwards,
which makes these the failure-path memory tests plan §13.5 requires.

## 7. Unknown node types

The dispatch table maps type string to node type and property extractors. A string
with no entry becomes:

```scheme
;; a hypothetical "footnote_definition" node, were footnotes ever enabled
(make-markdown-node 'extension
                    '((native-type . "footnote_definition"))
                    (list <converted children>)
                    <source-position or #f>)
```

`native-type` is the cmark type string verbatim. A `literal` property is added when
`cmark_node_get_literal` returns a string for the node, and omitted when it returns
NULL — the one place §3.4's uniform-key-set rule does not apply, because the key set
of an unknown type cannot be known in advance. Children are always converted. This is
plan §7.4's default: preserve rather than discard, and never lose children or
literals.

Given the options this library exposes, **no unknown type is reachable**:
`footnote_definition` and `footnote_reference` require `CMARK_OPT_FOOTNOTES`
(`src/cmark-gfm.h`, `1 << 13`), which is not exposed and which plan §18 defers;
`custom_block` and `custom_inline` are never produced by the parser; `"<unknown>"`
is an error return. This is the same situation as Stage 2 §10.2's unreachable
`&cmark-extension-unavailable`.

It is nonetheless tested, because dispatch is a pure function of a string: the unit
test calls the dispatcher directly with `"footnote_definition"` and with
`"<unknown>"` and asserts the fallback shape. The end-to-end unreachability is
recorded in §11.

Preservation rather than a raise means a future cmark that adds a node type
degrades to a usable AST instead of failing every document containing one.

## 8. Verification: cmark's XML as the oracle

### 8.1 Why this oracle cannot be tuned to a buggy converter

`cmark_render_xml` is cmark's own serialization of the same tree the converter
copies. A test-only serializer renders our Scheme AST into that dialect, and the
result is compared byte-for-byte against cmark's actual output for the same parse.

The serializer is written against `vendor/cmark-gfm/src/xml.c` and judged against
cmark's real bytes. It cannot be adjusted to accommodate a converter bug: a wrong
heading level, a dropped child, a mislabelled table header, or a missing
`fence-info` all show up as a byte difference. This is the property AGENTS.md
demands — the assertion fails when the code under test is wrong, not when the
expectation is stale.

Two legs, both run:

1. **In-process.** Same parse, same options: compare our serialization against
   `render-xml` on the live root, inside the same native scope.
2. **Pinned CLI.** Reuse the Stage 2 harness (§7.1-7.2 there) to compare against
   `cmark-gfm --to xml`, which proves the in-process comparison is not two halves
   of the same mistake.

### 8.2 The format the serializer must reproduce

Exactly, or the byte comparison is meaningless:

- Header: `<?xml version="1.0" encoding="UTF-8"?>` then
  `<!DOCTYPE document SYSTEM "CommonMark.dtd">`, each newline-terminated
  (`src/xml.c:171-173`).
- Element name is the cmark type string, so the serializer maps our node type back
  to it — including `table_header` from `table-row` with `header?` true.
- `document` carries `xmlns="http://commonmark.org/xml/1.0"`.
- Indentation is two spaces per level, **capped at 40** (`MAX_INDENT`,
  `src/xml.c:14`, applied in `src/xml.c:28-32`). Without the cap, deeply nested
  documents diverge.
- A node with children opens `>`; a childless non-literal node self-closes ` />`
  (`src/xml.c:140-145`).
- Literal-bearing types (`text`, `code`, `html_block`, `html_inline`, `code_block`)
  emit ` xml:space="preserve">`, the escaped literal, then the closing tag on the
  same line.
- `sourcepos="L:C-L:C"` only when positions are on and start line is non-zero
  (`src/xml.c:48`) — which §4.3 already made a straight mapping.
- Attribute order per type follows `src/xml.c:63-133`: `list` emits `type`, then
  `start` and `delim` for ordered lists only, then `tight`; `code_block` emits
  `info` only when non-empty.
- Extension attributes precede the type-specific ones (`src/xml.c:55-59`):
  ` completed="true|false"` for tasklist items, and ` align="left|center|right"`
  for a table cell **whose parent row is a header** and whose alignment is set
  (`extensions/table.c:659-671`).
- Escaping is `houdini_escape_html0` with `secure = 0`
  (`src/houdini_html_e.c:32-60`): exactly `&` `<` `>` `"` are escaped; `'` and `/`
  are emitted literally.

### 8.3 What the oracle cannot see

cmark's XML never emits three properties in §3.3's table, so each gets direct
assertions instead:

| Not in XML | Covered by |
|---|---|
| `item` `index` | direct assertion against `cmark_node_get_item_index` on an ordered list with a `start` offset |
| `table` `columns` | direct assertion on the GFM fixture's known column count |
| `alignment` on **body** cells | direct assertion; `extensions/table.c:661` emits `align=` only for header-row cells |

## 9. Testing and exit gate

### 9.1 Suites

| Suite | Native? | Covers |
|---|---|---|
| `tests/test-ast.sps` | **no** — runs under `check-purity` | record construction and immutability, property lookup with and without a default, functional update, `markdown-node-map` children-first order, `markdown-node-fold` pre-order, source-position accessors |
| `tests/test-convert.sps` | yes | every §3.3 type from the fixtures; key-set exactness; value domains; positions on and off; `source` `#f` at start line 0; validity after native cleanup; both limits and their conditions; counter balance on every failure path; the unknown-type fallback via direct dispatcher call; the `header?` cross-check |
| `tests/test-ast-differential.sps` | yes | §8's two legs across the fixtures and the option matrix |

Fixtures: `core.md`, `gfm.md`, `smart.md`, `hostile.md` are reused. Deep input is
**generated in-test**, not committed — a line of *n* `>` characters produces *n*
nested blockquotes, and the test computes *n* from the target depth rather than
hardcoding a magic number.

`TESTS := $(wildcard tests/test-*.sps)` picks all three up with no Makefile change.
`test-ast-differential.sps` stays **in** `MEMORY_TESTS`, unlike `test-differential.sps`:
its in-process leg allocates and frees native objects inside the Chez process, which
is exactly what Valgrind needs to see.

### 9.2 Exit gate

- `make test` green; `make check-purity` green with `test-ast.sps` included.
- `make test-memory` clean under Valgrind on Linux (ADR-0003: a green macOS run is
  not evidence).
- The AST survives native teardown: a tree returned out of the scope is fully
  readable afterwards, and `live-counts` is at baseline.
- Both limits raise `&cmark-resource-limit` with the right `reason` and `value`, and
  leave counters balanced.
- Serialized AST matches `cmark_render_xml` and the pinned CLI byte-for-byte across
  the fixture and option matrix.
- `.plans/stage-3-mutation-log.md` records a watched failure for every assertion.

### 9.3 Planned mutations

Each must fail, by name, through the asserted property:

| Mutation | Must fail |
|---|---|
| Map `"tasklist"` to `item` with `task? #f` | differential — `completed=` disappears |
| Map `"table_header"` to `header? #f` | differential — element name and header-cell `align=` both change |
| Off-by-one in the cell-alignment index | differential on header cells; direct assertion on body cells |
| Drop the `MAX_INDENT` clamp in the serializer | differential on the deep fixture |
| Remove the depth check before descending | depth-limit test — no condition raised |
| Remove the node counter check | node-limit test — no condition raised |
| `markdown->ast`'s 1-argument case uses `(default-cmark-options)` | positions-on-by-default test |
| Attach positions when `source-positions?` is `#f` | positions-off test, and the differential without `--sourcepos` |
| Make `markdown-node-map` parent-first | map-order test |
| Give `ast.sls` a native import it calls | `make check-purity` |
| Drop `fence-info` from the `code_block` extractor | key-set test, and the differential's `info=` |
| Read a literal after the scope exits | after-cleanup test (and ASan) |

One mutation is deliberately absent: declaring the tasklist accessor `int` instead
of routing it through the shim wrapper (§10) cannot be shown to fail, because the
upper bits of the return register happen to be zero on the platforms available here.
Its justification is the ABI contract, not an observed failure, and §11 records
that.

## 10. Native layer additions

Twenty bindings in `native.sls`, plus one shim function.

Pointer and `const char *` returns are declared `uptr` and copied by
`c-string->string`, per the Stage 1 rule that the conservative form keeps NULL
distinguishable from `""`:

```
cmark_node_first_child  cmark_node_next  cmark_node_get_type_string
cmark_node_get_literal  cmark_node_get_fence_info
cmark_node_get_url      cmark_node_get_title
cmark_gfm_extensions_get_table_alignments
```

Integer returns:

```
cmark_node_get_heading_level  cmark_node_get_list_type  cmark_node_get_list_delim
cmark_node_get_list_start     cmark_node_get_list_tight cmark_node_get_item_index
cmark_node_get_start_line     cmark_node_get_start_column
cmark_node_get_end_line       cmark_node_get_end_column
cmark_gfm_extensions_get_table_row_is_header
cmark_gfm_extensions_get_table_columns        ; uint16_t -> unsigned-16
```

Plus `alignment-bytes`, a marshalling procedure that reads `columns` bytes from the
alignments pointer, so `foreign-ref` stays confined to `native.sls`.

### 10.1 The `_Bool` return needs a shim wrapper

`cmark_gfm_extensions_get_tasklist_item_checked` returns C `_Bool`
(`extensions/cmark-gfm-core-extensions.h:41`). On the x86-64 SysV ABI a `_Bool`
return occupies only the low byte of `%al`, with the upper bits unspecified;
declaring the entry point as `int` would read whatever happens to be there. So the
shim gains one function:

```c
int chez_cmark_tasklist_checked(cmark_node *node) {
  return cmark_gfm_extensions_get_tasklist_item_checked(node) ? 1 : 0;
}
```

This is what plan §8.1 assigns the shim — "stable, Chez-friendly functions" — and
does not compromise ADR-0002's thinness: still no traversal, no parsing, no
rendering.

### 10.2 The extension accessors resolve from the extensions library

Three of the four new extension bindings live in `libcmark-gfm-extensions`, not in
`libcmark-gfm`. `native.sls` already loads both explicitly, ahead of the shim,
because on Linux a dlopened library's dependencies are not placed in the global
symbol namespace. If that ever regressed, these bindings would fail at **import**
time on Linux while passing on macOS — the exact CI asymmetry this project has
already been caught by once.

## 11. Invariants enforced as checks, not comments

| Invariant | Check |
|---|---|
| `ast.sls` imports nothing native | `make check-purity`, extended to `test-ast.sps` |
| The §3.3 property table is real | key-set exactness test, comparing the dispatch table's declared keys against what the converter produced |
| Every reachable type string has an entry | a test-side list of the 24 strings, derived independently from cmark's enum and the extensions, asserted against the table |
| `header?` agrees with cmark's own accessor | cross-check assertion on every row of the GFM fixture |
| No native pointer escapes | string-valued properties are strings, children are nodes, `source` is a source-position or `#f`; plus the after-cleanup readability test |
| Resource limits leave no leak | `live-counts` at baseline after each limit condition |
| Each limit constant has one definition | `limits.sls` owns all three |
| Traversal helper orders | map-order and fold-order tests |

## 12. Deliberate coverage gaps

1. **Unknown node types are unreachable end-to-end.** Tested only by calling the
   dispatcher with a synthetic type string (§7).
2. **`&cmark-extension-unavailable` remains unreachable** from the public API,
   carried unchanged from Stage 2 §10.2.
3. **`item` index, table `columns`, and body-cell alignment are invisible to the XML
   oracle** and covered by direct assertions instead (§8.3).
4. **Footnote and custom node types cannot occur**, because
   `CMARK_OPT_FOOTNOTES` is not exposed and the parser never creates custom nodes.
5. **Source positions are not attached to resource-limit conditions.** Plan §12 asks
   for them "when available"; a depth overflow is structural and the offending
   node's position would be `#f` whenever positions are off, so the condition
   carries the reason and the exceeded ceiling instead.
6. **The `_Bool` ABI hazard is justified by contract, not by an observed failure**
   (§9.3).
7. **`validate-utf8?` remains behaviourally unreachable** from the public API, as
   Stage 2 §10.1 established: Scheme strings always encode to valid UTF-8.

## 13. Release 0.2

- `Akku.manifest` version to `0.2.0`.
- `CHANGELOG.md` 0.2.0 entry: `markdown->ast` and the node model; `max-nodes` and
  `max-depth`; `default-ast-options` and the per-entry-point position default;
  `&cmark-resource-limit`; the AST-is-untrusted note.
- **ADR-0009** — per-entry-point source-position defaults. Records §4.1's corrected
  premise and resolves ADR-0008's deferral.
- **ADR-0010** — cmark's XML as the AST oracle. Records why a serializer written
  against `xml.c` and judged against cmark's bytes cannot be tuned to a buggy
  converter, and what it cannot see.
- README: an AST section with the untrusted-input warning, the new options, and the
  arity difference between `(markdown->ast md)` and `(markdown->ast md opts)`.

Plan §16's acceptance criteria remain the bar for 1.0, not for this release
(ADR-0007). After 0.2, the outstanding ones are the SXML adapter, packaging, docs,
and the conformance corpus.

## 14. References

- Project plan §6.4, §7, §9.7, §12, §13.2, §15 (M3, M4), §17, §18
- Stage 2 design §7 (differential harness), §10 (deliberate gaps)
- ADR-0002 (traverse in Scheme), ADR-0003 (Linux memory gate), ADR-0005 (parser
  outlives rendering), ADR-0006 (liveness flag), ADR-0007 (release staging),
  ADR-0008 (source positions off for renderer releases)
- `vendor/cmark-gfm/src/xml.c`, `src/inlines.c`, `src/houdini_html_e.c`,
  `src/cmark-gfm.h`
- `vendor/cmark-gfm/extensions/table.c`, `extensions/tasklist.c`,
  `extensions/cmark-gfm-core-extensions.h`
