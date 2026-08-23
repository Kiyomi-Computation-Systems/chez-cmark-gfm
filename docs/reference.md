# API reference

This page is the binding-by-binding reference for chez-cmark-gfm. Most callers
should import `(cmark gfm)`, the complete consumer API. Narrow modules are
available when code deliberately needs only one layer or must preserve a pure
Scheme import boundary.

For examples and explanation, start with [Usage](usage.md),
[Options](options.md), [The AST](ast.md), [SXML](sxml.md), or
[Errors](errors.md). This page answers the smaller question: what is the exact
binding, how is it called, and where is it exported?

## Modules

| Module | Purpose | Loads native code? |
|---|---|---:|
| `(cmark gfm)` | Canonical API: every ordinary consumer binding below except the specialist `extension->native-name`. | Yes |
| `(cmark gfm options)` | Immutable cmark and SXML options plus the extension-name bridge. | No |
| `(cmark gfm render)` | Four direct native renderers. | Yes |
| `(cmark gfm parse)` | Markdown-to-AST parsing. | Yes |
| `(cmark gfm ast)` | Immutable AST and source-position records, functional updates, and traversal. | No |
| `(cmark gfm sxml)` | Pure AST-to-SXML conversion. | No |

The three pure modules import no library that loads a shared object, even
transitively; `make check-purity` enforces that boundary. Importing the
umbrella remains the simplest choice unless the narrower dependency boundary
itself matters.

## Conventions

Signatures below use `->` to separate arguments from the result; it is
notation, not Scheme syntax. Markdown inputs are Scheme strings. Option, AST,
and source-position records are immutable; converted AST and SXML trees are
Scheme-owned after the native parse scope ends. `width` is an exact
non-negative integer. A bracketed argument is optional, and separate
signatures show distinct `case-lambda` arities. Some AST properties
legitimately contain `#f`; use `markdown-node-property`'s explicit default
when absence must be distinguished from a present false value.

An entry's **Raises** line names the library conditions most directly owned by
that call. R6RS can still raise ordinary assertion or arity conditions for
programming errors outside the library's validated contracts. See
[Errors](errors.md) for the complete hierarchy and every reason value.

## Rendering and conversion

### `markdown->html` (procedure)

`(markdown->html markdown options) -> string`

Renders a Markdown string as an HTML fragment. Raw HTML and dangerous URL
schemes are suppressed by the default options; `unsafe-html?` must be enabled
explicitly to pass raw HTML through.

**Available from:** `(cmark gfm)`, `(cmark gfm render)`\
**Raises:** `&cmark-invalid-input`, `&cmark-resource-limit`,
`&cmark-invalid-option`, `&cmark-extension-unavailable`,
`&cmark-render-failed`\
**Details:** [The renderers](usage.md#the-renderers)

### `markdown->commonmark` (procedure)

`(markdown->commonmark markdown options) -> string`\
`(markdown->commonmark markdown options width) -> string`

Renders normalized CommonMark. The two-argument form uses width `0`, meaning
no wrapping. An inexact or negative width raises `&cmark-invalid-option` with
key `width` and reason `invalid-width` before native allocation.

**Available from:** `(cmark gfm)`, `(cmark gfm render)`\
**Raises:** the renderer conditions listed for `markdown->html`, plus invalid
width\
**Details:** [Wrap width](usage.md#wrap-width)

### `markdown->plaintext` (procedure)

`(markdown->plaintext markdown options) -> string`\
`(markdown->plaintext markdown options width) -> string`

Renders plain text. Width has the same contract as
`markdown->commonmark`; omitting it is byte-equivalent to passing `0`.

**Available from:** `(cmark gfm)`, `(cmark gfm render)`\
**Raises:** the renderer conditions listed for `markdown->html`, plus invalid
width\
**Details:** [Wrap width](usage.md#wrap-width)

### `markdown->xml` (procedure)

`(markdown->xml markdown options) -> string`

Renders cmark's XML representation of the parse tree. It has exactly two
arguments; width is not applicable.

**Available from:** `(cmark gfm)`, `(cmark gfm render)`\
**Raises:** the renderer conditions listed for `markdown->html`\
**Details:** [The renderers](usage.md#the-renderers)

### `markdown->ast` (procedure)

`(markdown->ast markdown) -> markdown-node`\
`(markdown->ast markdown options) -> markdown-node`

Parses Markdown into a Scheme-owned immutable tree. The one-argument form
uses `default-ast-options`, with source positions enabled. The two-argument
form honors the supplied record verbatim.

**Available from:** `(cmark gfm)`, `(cmark gfm parse)`\
**Raises:** `&cmark-invalid-input`, `&cmark-resource-limit`,
`&cmark-invalid-option`, `&cmark-extension-unavailable`\
**Details:** [Parsing](ast.md#parsing)

### `markdown->sxml` (procedure)

`(markdown->sxml markdown) -> sxml`\
`(markdown->sxml markdown cmark-options) -> sxml`\
`(markdown->sxml markdown cmark-options sxml-options) -> sxml`

Parses Markdown and converts it to an `(*TOP* ...)` SXML tree. Defaults are
`default-cmark-options` and `default-sxml-options`. Explicit
`unsafe-html?`, `hardbreaks?`, and `nobreaks?` cmark options are refused as
`not-applicable`; the SXML policy record owns their corresponding output
choices.

**Available from:** `(cmark gfm)`\
**Raises:** the parse conditions plus `&cmark-unsupported-node`,
`&cmark-malformed-tree`, and SXML option failures\
**Details:** [SXML getting started](sxml.md#getting-started)

### `markdown-ast->sxml` (procedure)

`(markdown-ast->sxml tree) -> sxml`\
`(markdown-ast->sxml tree sxml-options) -> sxml`

Purely converts an existing `markdown-node` tree to SXML. The one-argument
form uses `default-sxml-options`; no parse or native call occurs.

**Available from:** `(cmark gfm)`, `(cmark gfm sxml)`\
**Raises:** `&cmark-invalid-option`, `&cmark-unsupported-node`,
`&cmark-malformed-tree`; wrong Scheme record types can raise R6RS assertion
conditions\
**Details:** [SXML getting started](sxml.md#getting-started)

## Parser options

### `make-cmark-options` (record constructor)

`(make-cmark-options key value ...) -> cmark-options`

Builds an immutable options record from a property list. Unknown or duplicate
keys, odd-length lists, invalid values, unknown extensions, and contradictory
`hardbreaks?`/`nobreaks?` settings raise `&cmark-invalid-option`.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Constructing and updating](options.md#constructing-and-updating)

### `default-cmark-options` (procedure)

`(default-cmark-options) -> cmark-options`

Returns the same validated values as `(make-cmark-options)` with no
overrides: all five extensions, UTF-8 validation on, renderer flags off, and
the documented resource ceilings.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The defaults](options.md#the-defaults)

### `cmark-options-with` (procedure)

`(cmark-options-with options key value ...) -> cmark-options`

Returns a validated copy carrying the requested overrides. The input record
is unchanged, and the same property-list rules as `make-cmark-options` apply.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Raises:** `&cmark-invalid-option`\
**Details:** [Constructing and updating](options.md#constructing-and-updating)

### `cmark-options?` (predicate)

`(cmark-options? object) -> boolean`

Returns whether `object` is a cmark options record.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Constructing and updating](options.md#constructing-and-updating)

### `cmark-options-extensions` (accessor)

`(cmark-options-extensions options) -> list-of-symbols`

Returns the enabled extension symbols in caller-supplied order.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The defaults](options.md#the-defaults)

### `cmark-options-validate-utf8?` (accessor)

`(cmark-options-validate-utf8? options) -> boolean`

Returns the cmark UTF-8 validation flag. Scheme strings cannot produce
invalid UTF-8 through this binding, but the native option remains explicit.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [validate-utf8?](options.md#validate-utf8)

### `cmark-options-source-positions?` (accessor)

`(cmark-options-source-positions? options) -> boolean`

Returns whether the parse requests source positions. Renderer defaults use
`#f`; `default-ast-options` uses `#t`.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The defaults](options.md#the-defaults)

### `cmark-options-hardbreaks?` (accessor)

`(cmark-options-hardbreaks? options) -> boolean`

Returns whether native renderers turn soft breaks into hard line breaks.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [hardbreaks? and nobreaks?](options.md#hardbreaks-and-nobreaks)

### `cmark-options-nobreaks?` (accessor)

`(cmark-options-nobreaks? options) -> boolean`

Returns whether native renderers turn soft breaks into spaces. It cannot be
enabled together with `hardbreaks?` through the public constructors.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [hardbreaks? and nobreaks?](options.md#hardbreaks-and-nobreaks)

### `cmark-options-smart?` (accessor)

`(cmark-options-smart? options) -> boolean`

Returns whether cmark's smart punctuation option is enabled.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The defaults](options.md#the-defaults)

### `cmark-options-unsafe-html?` (accessor)

`(cmark-options-unsafe-html? options) -> boolean`

Returns whether native renderers may pass raw HTML and dangerous URL schemes
through instead of suppressing them. It does not sanitize or alter the AST.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The AST is untrusted](ast.md#the-ast-is-untrusted)

### `cmark-options-max-input-bytes` (accessor)

`(cmark-options-max-input-bytes options) -> positive-exact-integer`

Returns the maximum UTF-8 byte length accepted before parsing.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Resource limits](options.md#resource-limits)

### `cmark-options-max-nodes` (accessor)

`(cmark-options-max-nodes options) -> positive-exact-integer`

Returns the maximum number of nodes copied into a Scheme AST.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Resource limits](options.md#resource-limits)

### `cmark-options-max-depth` (accessor)

`(cmark-options-max-depth options) -> positive-exact-integer`

Returns the maximum AST nesting depth copied into Scheme.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Resource limits](options.md#resource-limits)

### `default-ast-options` (procedure)

`(default-ast-options) -> cmark-options`

Returns the ordinary cmark defaults with only `source-positions?` changed to
`#t`. It is the one-argument `markdown->ast` default.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The defaults](options.md#the-defaults)

### `supported-extensions` (procedure)

`(supported-extensions) -> list-of-symbols`

Returns `(autolink strikethrough table tagfilter tasklist)`, the pure set of
extension names this binding understands. It does not probe the loaded native
library.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Which library is loaded](usage.md#which-library-is-loaded)

### `extension->native-name` (procedure)

`(extension->native-name extension-symbol) -> string`

Maps a supported Scheme symbol to cmark's native extension name. This
specialist bridge is the only public binding not re-exported by the umbrella;
an unknown symbol raises `&cmark-invalid-option` with key `extensions` and
reason `unknown-extension`.

**Available from:** `(cmark gfm options)`\
**Details:** [The defaults](options.md#the-defaults)

## SXML options

### `make-sxml-options` (record constructor)

`(make-sxml-options key value ...) -> sxml-options`

Builds immutable adapter options. Accepted keys and values are `raw-html`:
`omit` or `escape`; `softbreak`: `newline`, `break`, or `space`; and
`attribute-marker`: `caret` or `at`.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Raises:** `&cmark-invalid-option`\
**Details:** [SXML options](sxml.md#options)

### `default-sxml-options` (procedure)

`(default-sxml-options) -> sxml-options`

Returns `raw-html` `omit`, `softbreak` `newline`, and `attribute-marker`
`caret`.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [SXML options](sxml.md#options)

### `sxml-options-with` (procedure)

`(sxml-options-with options key value ...) -> sxml-options`

Returns a validated immutable copy with the requested adapter-policy
overrides. A wrong record type raises `&cmark-invalid-option` rather than a
bare record-accessor assertion.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Raises:** `&cmark-invalid-option`\
**Details:** [SXML options](sxml.md#options)

### `sxml-options?` (predicate)

`(sxml-options? object) -> boolean`

Returns whether `object` is an SXML options record.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [SXML options](sxml.md#options)

### `sxml-options-raw-html` (accessor)

`(sxml-options-raw-html options) -> symbol`

Returns `omit` or `escape`. Under `omit`, raw HTML becomes cmark's omission
comment; under `escape`, it remains an ordinary string for the serializer to
escape.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [Why omit is the default](sxml.md#why-omit-is-the-default)

### `sxml-options-softbreak` (accessor)

`(sxml-options-softbreak options) -> symbol`

Returns `newline`, `break`, or `space`, naming what an AST softbreak becomes
in SXML.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [SXML options](sxml.md#options)

### `sxml-options-attribute-marker` (accessor)

`(sxml-options-attribute-marker options) -> symbol`

Returns `caret` or `at`. The default `caret` produces `^` attribute lists
compatible with the serializers available through Akku.

**Available from:** `(cmark gfm)`, `(cmark gfm options)`\
**Details:** [The attribute marker](sxml.md#the-attribute-marker)

## AST nodes and traversal

The AST is untrusted structured input: raw HTML and dangerous URLs remain
exactly as authored. Sanitize at the output boundary, not by assuming parsing
made the content safe.

### `make-markdown-node` (record constructor)

`(make-markdown-node type properties children source) -> markdown-node`

Constructs an immutable node from a type symbol, property alist, child list,
and source-position record or `#f`.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node?` (predicate)

`(markdown-node? object) -> boolean`

Returns whether `object` is a Markdown node record.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-type` (accessor)

`(markdown-node-type node) -> symbol`

Returns the node type, such as `document`, `paragraph`, `heading`, or
`extension`.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Properties by node type](ast.md#properties-by-node-type)

### `markdown-node-properties` (accessor)

`(markdown-node-properties node) -> alist`

Returns the immutable node property alist. Prefer `markdown-node-property`
when absence must be distinguished from a present `#f` value.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-children` (accessor)

`(markdown-node-children node) -> list-of-markdown-nodes`

Returns child nodes in document order.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-source` (accessor)

`(markdown-node-source node) -> source-position-or-#f`

Returns the node's source span when positions were parsed and cmark supplies
one; otherwise returns `#f`.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-property` (procedure)

`(markdown-node-property node key) -> value-or-#f`\
`(markdown-node-property node key default) -> value-or-default`

Looks up one property with `assq`. The explicit default is consulted only
when the key is absent, preserving the distinction between absence and a
legitimate `#f` property value.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-with-properties` (procedure)

`(markdown-node-with-properties node properties) -> markdown-node`

Returns a new node with replacement properties while preserving its type,
children, and source. The original is unchanged.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-with-children` (procedure)

`(markdown-node-with-children node children) -> markdown-node`

Returns a new node with replacement children while preserving its type,
properties, and source.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `markdown-node-map` (procedure)

`(markdown-node-map procedure node) -> markdown-node`

Maps children-first, bottom-up. The procedure receives a node whose children
have already been mapped, and every node is rebuilt even under the identity
procedure.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Traversal](ast.md#traversal)

### `markdown-node-fold` (procedure)

`(markdown-node-fold procedure seed node) -> value`

Folds in pre-order: parent before children, with children visited left to
right. The procedure receives `(node accumulator)`.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Traversal](ast.md#traversal)

### `make-source-position` (record constructor)

`(make-source-position start-line start-column end-line end-column) -> source-position`

Constructs immutable diagnostic source coordinates from four exact integers.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `source-position?` (predicate)

`(source-position? object) -> boolean`

Returns whether `object` is a source-position record.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `source-position-start-line` (accessor)

`(source-position-start-line source) -> exact-integer`

Returns the one-based starting line.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `source-position-start-column` (accessor)

`(source-position-start-column source) -> exact-integer`

Returns the one-based starting column.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `source-position-end-line` (accessor)

`(source-position-end-line source) -> exact-integer`

Returns the one-based ending line.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

### `source-position-end-column` (accessor)

`(source-position-end-column source) -> exact-integer`

Returns the one-based ending column.

**Available from:** `(cmark gfm)`, `(cmark gfm ast)`\
**Details:** [Node shape](ast.md#node-shape)

## Runtime and capabilities

### `cmark-gfm-version` (procedure)

`(cmark-gfm-version) -> string`

Returns the loaded native runtime's version string. It deliberately reports
an incompatible runtime rather than first raising the compatibility condition,
so callers can diagnose what was found.

**Available from:** `(cmark gfm)`\
**Details:** [Which library is loaded](usage.md#which-library-is-loaded)

### `cmark-gfm-version-compatible?` (predicate)

`(cmark-gfm-version-compatible?) -> boolean`

Returns whether the loaded runtime version lies in the binding's supported
range.

**Available from:** `(cmark gfm)`\
**Details:** [Supported versions](installing.md#supported-versions)

### `cmark-gfm-available-extensions` (procedure)

`(cmark-gfm-available-extensions) -> list-of-symbols`

Probes the loaded extension registry and returns the supported symbolic names
actually present there.

**Available from:** `(cmark gfm)`\
**Raises:** native discovery, compatibility, or missing-entry-point conditions\
**Details:** [Which library is loaded](usage.md#which-library-is-loaded)

## Conditions

Every public condition derives from `&cmark-error`. Constructors remain
private: callers handle failures through the type predicates and accessors
below. [Errors](errors.md) catalogs every reason, field value, and public
entry point that can raise each family.

### `&cmark-error` (condition type)

The root library condition type, derived from the R6RS `&error` type. It has
no fields of its own.

**Available from:** `(cmark gfm)`\
**Details:** [The condition family](errors.md#the-condition-family)

### `cmark-error?` (predicate)

`(cmark-error? object) -> boolean`

Returns true for every condition in this library's family, including all
subtypes below.

**Available from:** `(cmark gfm)`\
**Details:** [The condition family](errors.md#the-condition-family)

### `&cmark-version-incompatible` (condition type)

A subtype of `&cmark-error` raised when a discovered or loaded runtime lies
outside the supported version range. It carries `supported` and `runtime`.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-version-incompatible?` (predicate)

`(cmark-version-incompatible? object) -> boolean`

Returns whether `object` carries a version-incompatibility condition.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-version-incompatible-supported` (accessor)

`(cmark-version-incompatible-supported condition) -> version-range`

Returns the encoded version range accepted by this binding.

**Available from:** `(cmark gfm)`\
**Details:** [Supported versions](installing.md#supported-versions)

### `cmark-version-incompatible-runtime` (accessor)

`(cmark-version-incompatible-runtime condition) -> encoded-version`

Returns the incompatible runtime version that was found.

**Available from:** `(cmark gfm)`\
**Details:** [Supported versions](installing.md#supported-versions)

### `&cmark-dead-document` (condition type)

A subtype of `&cmark-error` representing access to an internal native handle
after its scope ended. No public entry point exposes such a handle, so this
condition is exported for completeness but ordinarily unreachable.

**Available from:** `(cmark gfm)`\
**Details:** [Memory ownership](memory.md)

### `cmark-dead-document?` (predicate)

`(cmark-dead-document? object) -> boolean`

Returns whether `object` carries a dead-document condition.

**Available from:** `(cmark gfm)`\
**Details:** [Memory ownership](memory.md)

### `&cmark-extension-unavailable` (condition type)

A subtype of `&cmark-error` raised when an accepted extension name is absent
from the loaded runtime's registry. It carries the native extension name.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-extension-unavailable?` (predicate)

`(cmark-extension-unavailable? object) -> boolean`

Returns whether `object` carries an unavailable-extension condition.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-extension-unavailable-name` (accessor)

`(cmark-extension-unavailable-name condition) -> string`

Returns cmark's native extension name, such as `"table"`.

**Available from:** `(cmark gfm)`\
**Details:** [Which library is loaded](usage.md#which-library-is-loaded)

### `&cmark-invalid-input` (condition type)

A subtype of `&cmark-error` for invalid Markdown input or extension-name
values. It carries a symbolic reason. Resource ceilings form the narrower
subtype documented below.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-invalid-input?` (predicate)

`(cmark-invalid-input? object) -> boolean`

Returns true for plain invalid-input conditions and for
`&cmark-resource-limit` subconditions.

**Available from:** `(cmark gfm)`\
**Details:** [The condition family](errors.md#the-condition-family)

### `cmark-invalid-input-reason` (accessor)

`(cmark-invalid-input-reason condition) -> symbol`

Returns the invalid-input reason, including inherited resource reasons such
as `too-large`, `too-many-nodes`, and `too-deep`.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `&cmark-resource-limit` (condition type)

A subtype of `&cmark-invalid-input` raised when an input-byte, node-count, or
depth ceiling is exceeded. It adds the configured ceiling as `value`.

**Available from:** `(cmark gfm)`\
**Details:** [Resource limits](options.md#resource-limits)

### `cmark-resource-limit?` (predicate)

`(cmark-resource-limit? object) -> boolean`

Returns whether `object` carries the narrower resource-limit condition.

**Available from:** `(cmark gfm)`\
**Details:** [The condition family](errors.md#the-condition-family)

### `cmark-resource-limit-value` (accessor)

`(cmark-resource-limit-value condition) -> positive-exact-integer`

Returns the configured ceiling that was exceeded, not the measured size of
the offending document or tree.

**Available from:** `(cmark gfm)`\
**Details:** [Resource limits](options.md#resource-limits)

### `&cmark-library-unavailable` (condition type)

A subtype of `&cmark-error` raised when the native core/extensions pair cannot
be resolved, validated, loaded, or probed for a required symbol. It carries
`path` and `reason`.

**Available from:** `(cmark gfm)`\
**Details:** [CHEZ_CMARK_GFM_LIBS](installing.md#chezcmarkgfmlibs)

### `cmark-library-unavailable?` (predicate)

`(cmark-library-unavailable? object) -> boolean`

Returns whether `object` carries a library-unavailable condition.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-library-unavailable-path` (accessor)

`(cmark-library-unavailable-path condition) -> string-or-#f`

Returns the implicated shared-object path, or `#f` when discovery found no
single path to name.

**Available from:** `(cmark gfm)`\
**Details:** [CHEZ_CMARK_GFM_LIBS](installing.md#chezcmarkgfmlibs)

### `cmark-library-unavailable-reason` (accessor)

`(cmark-library-unavailable-reason condition) -> symbol`

Returns `not-found`, `invalid-override`, `load-failed`, or
`missing-entry-point`.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `&cmark-invalid-option` (condition type)

A subtype of `&cmark-error` for malformed property lists, unknown or
duplicate keys, invalid values, contradictory settings, invalid widths, and
options not applicable to SXML. It carries `key` and `reason`.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-invalid-option?` (predicate)

`(cmark-invalid-option? object) -> boolean`

Returns whether `object` carries an invalid-option condition.

**Available from:** `(cmark gfm)`\
**Details:** [Constructing and updating](options.md#constructing-and-updating)

### `cmark-invalid-option-key` (accessor)

`(cmark-invalid-option-key condition) -> symbol-or-#f`

Returns the offending option key, or `#f` when the argument list or record as
a whole is invalid.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-invalid-option-reason` (accessor)

`(cmark-invalid-option-reason condition) -> symbol`

Returns the precise validation reason, such as `unknown-key`,
`invalid-value`, `invalid-width`, or `not-applicable`.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `&cmark-render-failed` (condition type)

A subtype of `&cmark-error` raised if a native renderer returns a null buffer.
It carries the requested format.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-render-failed?` (predicate)

`(cmark-render-failed? object) -> boolean`

Returns whether `object` carries a render-failed condition.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-render-failed-format` (accessor)

`(cmark-render-failed-format condition) -> symbol`

Returns `html`, `xml`, `commonmark`, or `plaintext`.

**Available from:** `(cmark gfm)`\
**Details:** [The renderers](usage.md#the-renderers)

### `&cmark-unsupported-node` (condition type)

A direct subtype of `&cmark-error` raised when the SXML adapter encounters a
node type it cannot represent. It is intentionally not invalid input: it
signals an adapter coverage gap.

**Available from:** `(cmark gfm)`\
**Details:** [The condition family](errors.md#the-condition-family)

### `cmark-unsupported-node?` (predicate)

`(cmark-unsupported-node? object) -> boolean`

Returns whether `object` carries an unsupported-node condition.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-unsupported-node-type` (accessor)

`(cmark-unsupported-node-type condition) -> string`

Returns the native node type the SXML adapter did not recognize.

**Available from:** `(cmark gfm)`\
**Details:** [The mapping](sxml.md#the-mapping)

### `&cmark-malformed-tree` (condition type)

A direct subtype of `&cmark-error` raised when a caller-built or rewritten AST
has a shape the real parser cannot produce. It is intentionally not a subtype
of `&cmark-invalid-input`.

**Available from:** `(cmark gfm)`\
**Details:** [The condition family](errors.md#the-condition-family)

### `cmark-malformed-tree?` (predicate)

`(cmark-malformed-tree? object) -> boolean`

Returns whether `object` carries a malformed-tree condition.

**Available from:** `(cmark gfm)`\
**Details:** [What raises what](errors.md#what-raises-what)

### `cmark-malformed-tree-reason` (accessor)

`(cmark-malformed-tree-reason condition) -> symbol`

Returns the structural reason, currently `header-row-not-first`.

**Available from:** `(cmark gfm)`\
**Details:** [The mapping](sxml.md#the-mapping)

## Alphabetical index

The index is only navigation; the complete contracts are the entries above.

- [`&cmark-dead-document`](#cmark-dead-document-condition-type)
- [`&cmark-error`](#cmark-error-condition-type)
- [`&cmark-extension-unavailable`](#cmark-extension-unavailable-condition-type)
- [`&cmark-invalid-input`](#cmark-invalid-input-condition-type)
- [`&cmark-invalid-option`](#cmark-invalid-option-condition-type)
- [`&cmark-library-unavailable`](#cmark-library-unavailable-condition-type)
- [`&cmark-malformed-tree`](#cmark-malformed-tree-condition-type)
- [`&cmark-render-failed`](#cmark-render-failed-condition-type)
- [`&cmark-resource-limit`](#cmark-resource-limit-condition-type)
- [`&cmark-unsupported-node`](#cmark-unsupported-node-condition-type)
- [`&cmark-version-incompatible`](#cmark-version-incompatible-condition-type)
- [`cmark-dead-document?`](#cmark-dead-document-predicate)
- [`cmark-error?`](#cmark-error-predicate)
- [`cmark-extension-unavailable-name`](#cmark-extension-unavailable-name-accessor)
- [`cmark-extension-unavailable?`](#cmark-extension-unavailable-predicate)
- [`cmark-gfm-available-extensions`](#cmark-gfm-available-extensions-procedure)
- [`cmark-gfm-version`](#cmark-gfm-version-procedure)
- [`cmark-gfm-version-compatible?`](#cmark-gfm-version-compatible-predicate)
- [`cmark-invalid-input-reason`](#cmark-invalid-input-reason-accessor)
- [`cmark-invalid-input?`](#cmark-invalid-input-predicate)
- [`cmark-invalid-option-key`](#cmark-invalid-option-key-accessor)
- [`cmark-invalid-option-reason`](#cmark-invalid-option-reason-accessor)
- [`cmark-invalid-option?`](#cmark-invalid-option-predicate)
- [`cmark-library-unavailable-path`](#cmark-library-unavailable-path-accessor)
- [`cmark-library-unavailable-reason`](#cmark-library-unavailable-reason-accessor)
- [`cmark-library-unavailable?`](#cmark-library-unavailable-predicate)
- [`cmark-malformed-tree-reason`](#cmark-malformed-tree-reason-accessor)
- [`cmark-malformed-tree?`](#cmark-malformed-tree-predicate)
- [`cmark-options-extensions`](#cmark-options-extensions-accessor)
- [`cmark-options-hardbreaks?`](#cmark-options-hardbreaks-accessor)
- [`cmark-options-max-depth`](#cmark-options-max-depth-accessor)
- [`cmark-options-max-input-bytes`](#cmark-options-max-input-bytes-accessor)
- [`cmark-options-max-nodes`](#cmark-options-max-nodes-accessor)
- [`cmark-options-nobreaks?`](#cmark-options-nobreaks-accessor)
- [`cmark-options-smart?`](#cmark-options-smart-accessor)
- [`cmark-options-source-positions?`](#cmark-options-source-positions-accessor)
- [`cmark-options-unsafe-html?`](#cmark-options-unsafe-html-accessor)
- [`cmark-options-validate-utf8?`](#cmark-options-validate-utf8-accessor)
- [`cmark-options-with`](#cmark-options-with-procedure)
- [`cmark-options?`](#cmark-options-predicate)
- [`cmark-render-failed-format`](#cmark-render-failed-format-accessor)
- [`cmark-render-failed?`](#cmark-render-failed-predicate)
- [`cmark-resource-limit-value`](#cmark-resource-limit-value-accessor)
- [`cmark-resource-limit?`](#cmark-resource-limit-predicate)
- [`cmark-unsupported-node-type`](#cmark-unsupported-node-type-accessor)
- [`cmark-unsupported-node?`](#cmark-unsupported-node-predicate)
- [`cmark-version-incompatible-runtime`](#cmark-version-incompatible-runtime-accessor)
- [`cmark-version-incompatible-supported`](#cmark-version-incompatible-supported-accessor)
- [`cmark-version-incompatible?`](#cmark-version-incompatible-predicate)
- [`default-ast-options`](#default-ast-options-procedure)
- [`default-cmark-options`](#default-cmark-options-procedure)
- [`default-sxml-options`](#default-sxml-options-procedure)
- [`extension->native-name`](#extension-native-name-procedure)
- [`make-cmark-options`](#make-cmark-options-record-constructor)
- [`make-markdown-node`](#make-markdown-node-record-constructor)
- [`make-source-position`](#make-source-position-record-constructor)
- [`make-sxml-options`](#make-sxml-options-record-constructor)
- [`markdown->ast`](#markdown-ast-procedure)
- [`markdown->commonmark`](#markdown-commonmark-procedure)
- [`markdown->html`](#markdown-html-procedure)
- [`markdown->plaintext`](#markdown-plaintext-procedure)
- [`markdown->sxml`](#markdown-sxml-procedure)
- [`markdown->xml`](#markdown-xml-procedure)
- [`markdown-ast->sxml`](#markdown-ast-sxml-procedure)
- [`markdown-node-children`](#markdown-node-children-accessor)
- [`markdown-node-fold`](#markdown-node-fold-procedure)
- [`markdown-node-map`](#markdown-node-map-procedure)
- [`markdown-node-properties`](#markdown-node-properties-accessor)
- [`markdown-node-property`](#markdown-node-property-procedure)
- [`markdown-node-source`](#markdown-node-source-accessor)
- [`markdown-node-type`](#markdown-node-type-accessor)
- [`markdown-node-with-children`](#markdown-node-with-children-procedure)
- [`markdown-node-with-properties`](#markdown-node-with-properties-procedure)
- [`markdown-node?`](#markdown-node-predicate)
- [`source-position-end-column`](#source-position-end-column-accessor)
- [`source-position-end-line`](#source-position-end-line-accessor)
- [`source-position-start-column`](#source-position-start-column-accessor)
- [`source-position-start-line`](#source-position-start-line-accessor)
- [`source-position?`](#source-position-predicate)
- [`supported-extensions`](#supported-extensions-procedure)
- [`sxml-options-attribute-marker`](#sxml-options-attribute-marker-accessor)
- [`sxml-options-raw-html`](#sxml-options-raw-html-accessor)
- [`sxml-options-softbreak`](#sxml-options-softbreak-accessor)
- [`sxml-options-with`](#sxml-options-with-procedure)
- [`sxml-options?`](#sxml-options-predicate)
