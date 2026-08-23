# Errors

Every failure this library can raise is a structured R6RS condition, never
a raw foreign-interface error and never an unstructured `&error`. Individual
entry points document what they raise in [usage.md](usage.md),
[options.md](options.md), [ast.md](ast.md), and [sxml.md](sxml.md); this
page is the catalogue those pages point back to — every condition type,
how they nest, and every `reason`, `format`, or `type` symbol a caller can
match on.

## The condition family

All ten condition types below derive, directly or through one intermediate
type, from `&cmark-error`. That gives a caller two grains to catch at:
precisely, with a predicate like `cmark-invalid-option?`, or as a family,
with `cmark-error?`. `tests/test-conditions.sps` asserts both directions
for every type — that it satisfies its own predicate *and* `cmark-error?` —
and, for the three types most easily mistaken for one another, that the
negative holds too: a resource limit is invalid input, but a plain invalid
input is *not* a resource limit; an unsupported node and a malformed tree
are each asserted *not* to satisfy `cmark-invalid-input?`, which is exactly
the separation the next section explains.

`&cmark-error` itself carries no fields. A handful of internal checks — an
allocation from cmark's own allocator coming back null, which should not
happen on a supported library — raise it bare, with no subtype and nothing
beyond `cmark-error?` to discriminate on. Every condition raised *by name*
below carries more than that.

## The tree

```
&cmark-error
├── &cmark-invalid-option        key, reason
├── &cmark-invalid-input         reason
│   └── &cmark-resource-limit    value            (+ reason, inherited)
├── &cmark-library-unavailable   path, reason
├── &cmark-version-incompatible  supported, runtime
├── &cmark-extension-unavailable name
├── &cmark-dead-document
├── &cmark-render-failed         format
├── &cmark-unsupported-node      type
└── &cmark-malformed-tree        reason
```

`&cmark-resource-limit` is the one non-trivial branch. It derives from
`&cmark-invalid-input` rather than straight from `&cmark-error`, so that
code written against an earlier release — which only ever raised
`&cmark-invalid-input` for an oversized document — keeps working unchanged:
`cmark-invalid-input?` is still `#t` for a resource-limit condition, and
`cmark-invalid-input-reason` still answers. New code can catch the
narrower `cmark-resource-limit?` instead and read the ceiling that was
configured, via `cmark-resource-limit-value`.

`&cmark-unsupported-node` and `&cmark-malformed-tree` are deliberately
**not** under `&cmark-invalid-input`, even though both are raised while
converting a tree handed to `markdown-ast->sxml`. Neither is "the document
was bad": an unsupported node means this library's own SXML coverage has a
gap, not that the input was invalid, and a malformed tree means the caller
built or edited a `markdown-node` shape the real parser could never
produce — a `table` whose header row isn't first. Filing either one under
"invalid input" would let a caller's blanket `cmark-invalid-input?` guard
silently swallow a coverage gap, or a structurally broken caller-built
tree, as if it were merely bad Markdown.

## What raises what

| Condition                      | Own fields             | Values |
|---------------------------------|-------------------------|--------|
| `&cmark-invalid-option`        | `key`, `reason`         | `reason`: `malformed-plist`, `unknown-key`, `duplicate-key`, `invalid-value`, `unknown-extension`, `contradictory`, `invalid-width`, `not-applicable` |
| `&cmark-invalid-input`         | `reason`                | `reason`: `not-a-string`, `embedded-nul`, `extension-name-not-a-string` |
| `&cmark-resource-limit`        | `value`                 | `reason` (inherited): `too-large`, `too-many-nodes`, `too-deep`; `value` is the ceiling as *configured*, not the size of the offending input |
| `&cmark-library-unavailable`   | `path`, `reason`        | `reason`: `not-found`, `invalid-override`, `load-failed`, `missing-entry-point` |
| `&cmark-version-incompatible`  | `supported`, `runtime`  | no `reason` — `supported` is the accepted range, `runtime` the version found outside it |
| `&cmark-extension-unavailable` | `name`                  | the extension's cmark-native name, e.g. `"table"` |
| `&cmark-dead-document`         | —                       | — |
| `&cmark-render-failed`         | `format`                | `format`: `html`, `xml`, `commonmark`, `plaintext` |
| `&cmark-unsupported-node`      | `type`                  | the node's type, as a string |
| `&cmark-malformed-tree`        | `reason`                | `reason`: `header-row-not-first` |

`&cmark-invalid-option` is raised by `make-cmark-options`, `cmark-options-with`,
`make-sxml-options`, and `sxml-options-with` — each of those two pairs shares
one validation path with its sibling, so nothing built by an update
(`cmark-options-with`, `sxml-options-with`) can carry a value fresh
construction would have refused — plus the width check on
`markdown->commonmark`/`markdown->plaintext`, and the three renderer-only
options `markdown->sxml` refuses outright (`not-applicable`; see
[sxml.md](sxml.md)). All of it runs before any native resource is acquired.

`&cmark-invalid-input` and `&cmark-resource-limit` are raised while
validating the markdown string or an extension name, and while
`markdown->ast` walks the parsed tree. `too-large` is checked against the
encoded byte count before parsing starts; `too-many-nodes` and `too-deep`
are checked node by node during the AST copy, so a document that would
exceed either ceiling raises immediately rather than finishing the walk
first. See [ast.md](ast.md#resource-limits) and
[options.md](options.md#resource-limits) for the defaults and how all
three ceilings — `max-input-bytes` included — fit together.

`&cmark-unsupported-node` and `&cmark-malformed-tree` are raised only by
`markdown-ast->sxml` (and therefore `markdown->sxml`), and only for a tree
shape the real parser could never produce.

Five of the ten are exported for completeness but are not reachable by
calling only the public API against a supported library:

- **`&cmark-dead-document`** — no public entry point returns a live
  document handle or accepts one as an argument, so there is nothing a
  caller could touch after its scope closed. See [memory.md](memory.md).
- **`&cmark-version-incompatible`** and **`&cmark-library-unavailable`** —
  both are raised once, at *import* time, while `(cmark gfm)` resolves and
  loads the native libraries, before any of your own code runs. Arranging
  either one needs a deliberately wrong or missing library on the test
  machine, which is why `tests/test-library-loading.sps` drives it from a
  subprocess instead of a `guard` in-process.
- **`&cmark-extension-unavailable`** — raised only when the option layer
  has accepted an extension name that the *loaded* library's own registry
  doesn't have. Unreachable while the pinned version ships all five
  extensions this binding knows about.
- **`&cmark-render-failed`** — raised only when a cmark renderer returns
  NULL, which the pinned version does not do for any input this library
  can produce.

Each is exported and documented anyway, alongside every condition that
*is* reachable, so this tree is complete and a `cmark-error?` guard can be
written as exhaustive rather than "exhaustive modulo whatever I forgot."
[`examples/coverage-exemptions.scm`](../examples/coverage-exemptions.scm)
records the specific predicate and accessors for each of these five,
naming the reason none can be demonstrated through the public API — it
also exempts every condition *type name* itself, reachable or not, for an
unrelated reason: an R6RS condition type is not a first-class value a
caller can reference, only its predicate and accessors are. That file
cannot quietly go stale: `tests/test-example-coverage.sps` fails if an
entry turns out to be exercised by an example after all, or names
something not actually exported.

## Examples

Catching one condition precisely, and falling back to the family for
everything else:

```scheme
(guard (e ((cmark-invalid-option? e)
           (list 'bad-option (cmark-invalid-option-key e)
                             (cmark-invalid-option-reason e)))
          ((cmark-error? e) 'some-other-cmark-failure))
  (markdown->html "# hi\n" (make-cmark-options 'unsaef-html? #t)))
;; => (bad-option unsaef-html? unknown-key)
```

A resource limit, discriminated from the rest of `&cmark-invalid-input` and
read back through both the inherited accessor and the new one:

```scheme
(guard (e ((cmark-resource-limit? e)
           (list (cmark-invalid-input-reason e)
                 (cmark-resource-limit-value e))))
  (markdown->ast (make-string 200 #\>) (make-cmark-options 'max-depth 4)))
;; => (too-deep 4)
```

Both patterns above, and every other practically-reachable condition in
the table — `&cmark-malformed-tree` and `&cmark-unsupported-node`
included — are exercised in
[`examples/05-errors.sps`](../examples/05-errors.sps). `make examples` runs
it and diffs its output against a pinned expectation, so the patterns on
this page cannot go stale silently without a test noticing. The five
conditions listed above as unreachable through the public API are, for the
same reason, unreachable from an example; `make examples` does not attempt
them.
