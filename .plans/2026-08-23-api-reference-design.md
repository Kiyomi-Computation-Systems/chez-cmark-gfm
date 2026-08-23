# Public API reference: authored Markdown with executable export coverage

Status: proposed
Date: 2026-08-23
Scope: documentation and documentation checks only. No library behaviour
changes, no export changes, and no generated reference file.

## Goal

Add `docs/reference.md`, a single lookup-oriented reference for every public
module and binding in chez-cmark-gfm, and publish it through the existing
dogfooded Markdown -> SXML -> HTML site.

The result should have the useful properties of the 40ants-doc reference used
in Euclid -- complete symbol coverage, predictable entries, and a clean split
from tutorials and explanation -- without pretending this R6RS source already
contains structured docstrings that can generate good prose.

The prose is authored. Completeness is executable: a check reads the actual
R6RS `library` / `export` forms and fails when the reference is missing a
binding or module, names one that does not exist, duplicates an entry, or
leaves an entry empty.

## 1. Public surface

### 1.1 Which modules count

All six non-`private` libraries are part of the documented surface:

| Module | Source | Role | Native load |
|---|---|---|---|
| `(cmark gfm)` | `src/cmark/gfm.sls` | canonical consumer API | yes |
| `(cmark gfm options)` | `src/cmark/gfm/options.sls` | immutable cmark and SXML options | no |
| `(cmark gfm render)` | `src/cmark/gfm/render.sls` | four direct native renderers | yes |
| `(cmark gfm parse)` | `src/cmark/gfm/parse.sls` | Markdown-to-AST entry point | yes |
| `(cmark gfm ast)` | `src/cmark/gfm/ast.sls` | immutable Scheme AST records and traversal | no |
| `(cmark gfm sxml)` | `src/cmark/gfm/sxml.sls` | pure AST-to-SXML adapter | no |

`(cmark gfm)` remains the import recommended to ordinary users. The five
narrow modules are documented for callers that deliberately want a smaller
layer or a pure import boundary.

The check discovers this set from `src/cmark/gfm.sls` plus immediate `*.sls`
children of `src/cmark/gfm/`. It does not descend into `private/`. A future
non-private module therefore makes the check fail until a module-table row and
entries for its exports are added.

### 1.2 Which bindings count

The umbrella currently exports 84 identifiers. The union of the six modules
is 85: `(cmark gfm options)` additionally exports
`extension->native-name`. That binding is documented as a specialist bridge
from the Scheme extension symbol to cmark's native string, not silently
omitted. Removing it from the supported surface, if ever desired, is a
separate API-change task.

The reference covers exported identifiers, not merely procedures. Its 85
entries therefore include:

| Group | Unique bindings |
|---|---:|
| cmark options, including `extension->native-name` | 17 |
| SXML options | 7 |
| rendering and conversion entry points | 7 |
| AST nodes, source positions, and traversal | 17 |
| runtime version and capability queries | 3 |
| public condition types, predicates, and accessors | 34 |

Constructors kept inside `(cmark gfm private conditions)` are not public and
do not appear. The public condition type descriptors, predicates, and field
accessors re-exported by `(cmark gfm)` do.

## 2. Documentation architecture

The existing pages keep their current jobs:

- `usage.md` teaches the renderer entry points and width behaviour.
- `options.md` explains defaults, validation, and option interactions.
- `ast.md` explains the tree model, properties, traversal, and limits.
- `sxml.md` explains mapping and serialization consequences.
- `errors.md` explains the condition hierarchy and reason values.
- `memory.md` explains ownership at the native boundary.

`reference.md` is the fast lookup layer over those pages. It states exact
signatures and contracts, then links to the page that explains why. It does
not copy their long examples, mapping tables, rationale, or implementation
history.

This is the same separation sought in the Euclid documentation work:
reference answers "what is the binding and how do I call it?"; the existing
task-oriented and explanatory pages answer "how do I accomplish this?" and
"why does it behave this way?"

## 3. `docs/reference.md` structure

The page is ordered for lookup:

```text
# API reference

## Modules
## Conventions
## Rendering and conversion
## Parser options
## SXML options
## AST nodes and traversal
## Runtime and capabilities
## Conditions
## Alphabetical index
```

### 3.1 Module table

`## Modules` contains one Markdown table row per public module. Its first cell
is exactly the module name in code formatting:

```markdown
| `(cmark gfm)` | Canonical API; ... | Yes |
```

The remaining cells explain purpose, whether importing the module reaches
native loading, and when a narrow import is useful. The reference checker
parses only rows inside this section and compares their module names with the
discovered source modules.

### 3.2 Binding entry grammar

Each unique exported identifier receives one level-three heading:

```markdown
### `markdown->html` (procedure)

`(markdown->html markdown options) -> string`

Renders one Markdown string as an HTML fragment using the supplied immutable
options record.

**Available from:** `(cmark gfm)`, `(cmark gfm render)`  
**Raises:** `&cmark-invalid-input`, `&cmark-invalid-option`, ...  
**Details:** [Usage](usage.md#the-renderers)
```

The grammar is deliberately narrow:

- The heading starts with `### `.
- The first element is one backtick-delimited Scheme identifier.
- A parenthesized kind follows it: `procedure`, `record constructor`,
  `predicate`, `accessor`, or `condition type`.
- Exactly one `**Available from:**` line lists every public module exporting
  the binding.
- At least one other nonblank body line must occur before the next level-two
  or level-three heading.

The kind suffix makes anchors for names such as `&cmark-error` and
`cmark-error?` distinct after punctuation is removed by the site slugger:
`cmark-error-condition-type` versus `cmark-error-predicate`.

The checker extracts the identifier from this heading, so an identifier
mentioned in prose, a code sample, the alphabetical index, or an HTML comment
cannot masquerade as a documented entry.

The checker also parses each entry's `Available from` line and compares it to
the inverse of the real module export sets. This makes module availability a
checked contract rather than nearby prose: claiming `markdown->html` comes
from `(cmark gfm ast)`, or forgetting `(cmark gfm render)`, fails by name.

### 3.3 Entry content

Every entry states, as applicable:

1. Exact accepted call shape or record role.
2. Return type and important return shape.
3. Default selected by a shorter arity.
4. Mutability, traversal order, or ownership when it is part of the contract.
5. Public conditions the call can raise.
6. Every public module that exports the binding.
7. A link to the deeper topical section.

The reference reads signatures from the actual definitions, not from recall.
In particular it preserves the non-uniform arities already documented by the
library:

- `markdown->html` and `markdown->xml`: exactly two arguments.
- `markdown->commonmark` and `markdown->plaintext`: two or three arguments.
- `markdown->ast`: one or two arguments.
- `markdown->sxml`: one, two, or three arguments.
- `markdown-ast->sxml`: one or two arguments.
- `markdown-node-property`: two or three arguments.

Condition constructors are not invented. A condition entry documents the
public descriptor, predicate, inherited parent, and public accessors only.

### 3.4 Alphabetical index

The final index is for scanning, not coverage. It links to the generated
anchors of all 85 entries. The checker does not count identifiers in this
index as entries; the level-three entry headings remain the only coverage
signal.

## 4. Executable reference contract

### 4.1 Functional core

Add pure library `(site reference)` in `site/reference.sls`. It imports only
`(rnrs)` and consumes data or strings supplied by its caller. It owns:

- validation and extraction of a `(library name (export ...) ...)` datum;
- parsing public-module rows from the `## Modules` section;
- parsing level-three binding entries, availability lines, and their bodies;
- duplicate detection;
- set comparison; and
- construction of named diagnostics.

It does not read files, import `(cmark gfm)`, load a shared object, or render
Markdown. Unknown export syntax such as a future `(rename ...)` export spec
fails explicitly as `unsupported-export-spec`; silently ignoring it would
make the coverage claim false.

### 4.2 Imperative shell

Add `tests/reference-check.sps`, deliberately outside the
`tests/test-*.sps` glob. It:

1. discovers the six public source files;
2. reads the first R6RS datum from each file (`#!r6rs` and comments are
   skipped by Chez's reader);
3. reads `docs/reference.md`;
4. hands all values to `(site reference)`;
5. prints named missing, extra, duplicate, empty-body, module-membership, or
   unsupported-export diagnostics; and
6. exits non-zero on any diagnostic.

Successful validation returns and prints a sentinel only success can produce,
for example:

```text
check-reference: COMPLETE -- 6 modules, 85 unique bindings
```

An empty source discovery or empty reference is always an error. The check
must not accept the degenerate equality `() = ()`.

### 4.3 Make integration

Add:

```make
check-reference: ## Verify API reference modules and bindings match source exports
```

to the one physical `.PHONY` line and make `check-site` depend on it. Thus the
existing Pages workflow's `make check-site` gate automatically includes API
reference coverage without duplicating commands in YAML.

`check-reference` itself has no `build` or native dependency. It reads source
forms; it never instantiates the modules it documents.

## 5. Site integration

Add `reference.md` after `usage.md` in `site/pages.sls`:

```text
Installing -> Usage -> API reference -> Options -> The AST -> SXML
           -> Errors -> Memory ownership -> Building
```

Update `site/index.md` and `README.org` with the same position and a concise
description. Add an Unreleased changelog entry for the page and its coverage
gate. Historical plan and changelog text saying "eight pages" stays unchanged;
it accurately describes the earlier release work.

### 5.1 The right-rail TOC

Eighty-five binding headings must not become eighty-five links in the narrow
"On this page" rail. Change `site/render.sls`'s `rail-toc` policy from "all
levels below h1" to "level two sections only".

This is a general site rule rather than a filename special case:

- every heading level still receives an id;
- the global id registry still contains h1 through h6, so deep links to an
  individual API entry validate and resolve;
- the visible right rail lists only h2 sections; and
- existing pages do not visually change because they currently use only h1
  and h2.

A render test must prove both halves: an h3 API entry is absent from the rail
but remains present in the registry and rendered body.

## 6. Tests and mutation evidence

### 6.1 Unit tests

`tests/test-reference.sps` owns the pure parser and comparison behaviour:

- extracts the library name and all symbol exports from a synthetic datum;
- rejects an unsupported export spec by name;
- extracts a valid module row only from the Modules section;
- extracts a binding name and kind from the exact h3 grammar;
- does not count identifiers in prose, code fences, or the index;
- reports duplicate module rows and binding entries;
- reports a binding entry with no body;
- reports a missing or duplicate `Available from` line;
- reports an entry whose documented modules differ from the source modules;
- reports missing and extra modules;
- reports missing and extra bindings; and
- refuses empty source/reference inputs instead of returning success.

Every SRFI-64 suite ends with its own `(exit ...)`, with no assertions after
it.

### 6.2 Real-tree gate

`make check-reference` exercises the real six source modules and the real
`docs/reference.md`. It owns the claim that the shipped page covers the
shipped public surface. `make check-site` continues to own navigation,
anchors, `.md` rewriting, and serialization.

### 6.3 Required mutations

Record evidence in `.plans/api-reference-mutation-log.md`. Apply every
mutation to a scratch copy outside the repository, ensure the predicted
assertion fails by name through the intended property, then rerun the clean
copy green.

| Mutation | Guarded decision | Predicted named failure |
|---|---|---|
| Delete the `markdown->html` h3 entry | every real export has a substantive entry | `missing-bindings=(markdown->html)` |
| Rename that entry to `markdown->htlm` | missing and invented names are distinguished | both `missing-bindings` and `extra-bindings` name the typo |
| Duplicate the `markdown->html` heading | duplicates are not hidden by set conversion | `duplicate-bindings=(markdown->html)` |
| Delete the body while leaving its heading | a name-only inventory is not accepted as documentation | `empty-entry-bodies=(markdown->html)` |
| Remove the `(cmark gfm sxml)` module-table row | every non-private module is documented | `missing-modules=((cmark gfm sxml))` |
| Remove `(cmark gfm render)` from `markdown->html`'s availability line | per-binding module availability matches source | `module-membership-mismatches` names `markdown->html` and the missing module |
| Make export extraction drop the last symbol | the source parser cannot silently undercount | the real reference reports that symbol as extra |
| Change `rail-toc` back to every level greater than one | h3 binding entries do not flood the rail | render test fails because the h3 link appears in the rail |

If a mutation fails for syntax, import, or another incidental reason, narrow
it until the named property is what fails. A passing mutation is recorded as
inert and replaced, not silently discarded.

## 7. Files

### Created

| Path | Responsibility |
|---|---|
| `docs/reference.md` | authored module and binding reference |
| `site/reference.sls` | pure source/reference parser and comparator |
| `tests/test-reference.sps` | pure unit suite |
| `tests/reference-check.sps` | real-tree documentation gate |
| `.plans/api-reference-mutation-log.md` | mutation evidence |

### Modified

| Path | Change |
|---|---|
| `site/pages.sls` | add API reference after Usage |
| `site/render.sls` | right rail shows h2 sections only |
| `tests/test-site-render.sps` | prove h3 stays linkable but out of the rail |
| `site/index.md` | add API reference to Read next |
| `README.org` | add API reference to Documentation |
| `Makefile` | add `check-reference`; compose it into `check-site` |
| `CHANGELOG.md` | Unreleased entry |

No runtime source file under `src/` changes.

## 8. Verification

The completed task is not ready until all of these are green:

```text
make test
make check-reference
make check-site
make site
make check-help
```

Inspect `build/site/reference.html` at desktop and narrow widths. Confirm:

- all category sections appear in the right rail, but individual bindings do
  not;
- direct links to representative procedure, predicate, condition-type, and
  accessor entries land on the correct heading;
- punctuation-heavy identifiers display and escape correctly;
- prev/next links are Usage and Options;
- the page contains no relative `.md` links after rendering; and
- no generated file under `build/` is staged.

## 9. Out of scope

- No automatic prose generation or structured source-docstring convention.
- No public API addition, removal, or rename.
- No documentation of `private/` modules or condition constructors.
- No rearrangement or rewrite of the eight existing topic pages.
- No Pages workflow redesign; it inherits the new gate through Make.
- No committed HTML.
