# Project Plan: A `cmark-gfm` Library for Chez Scheme

## 1. Summary

Build a focused, production-quality Chez Scheme binding for `cmark-gfm`. The library will provide:

- CommonMark and GitHub Flavored Markdown parsing;
- safe direct rendering to HTML and other formats supported by `cmark-gfm`;
- a fully Scheme-owned AST for inspection and transformation;
- an optional AST-to-SXML adapter;
- explicit parser options and GFM extension selection;
- robust native-memory ownership and cleanup;
- safe defaults for raw HTML and unsafe links;
- reproducible packaging and compatibility checks.

The core project is a Markdown library, not a documentation generator. Page templates, navigation, site manifests, link checking, output-directory management, and static-site orchestration are outside its scope.

```text
                         +--> cmark-gfm HTML renderer --> HTML string
                         |
Markdown --> cmark-gfm AST
                         |
                         +--> copy to Scheme AST --> caller transformations
                                                   |
                                                   +--> optional SXML adapter
```

## 2. Goals

- Present an idiomatic Chez Scheme API rather than a thin collection of raw foreign procedures.
- Support the standard GFM extensions:
  - `autolink`;
  - `strikethrough`;
  - `table`;
  - `tagfilter`;
  - `tasklist`.
- Support direct rendering through `cmark-gfm`'s native renderers.
- Copy parsed documents into an implementation-independent Scheme AST.
- Provide source positions when supplied reliably by `cmark-gfm`.
- Keep native pointers private in the default public API.
- Prevent leaks, double frees, dangling pointers, and use-after-free behavior.
- Be safe by default when rendering Markdown to HTML.
- Make unsafe behavior deliberate, named, and difficult to enable accidentally.
- Package the library for reproducible use, preferably through Akku.
- Test against supported Chez and `cmark-gfm` versions on Linux and macOS initially.

## 3. Non-goals for Version 1

- A full documentation or static-site pipeline.
- Templating, navigation, tables of contents, or page manifests.
- A binding for every internal or experimental `cmark-gfm` function.
- Loading arbitrary third-party cmark plugins at runtime.
- Exposing mutable native AST nodes as ordinary long-lived Scheme objects.
- Converting a modified Scheme AST back into a native cmark AST.
- Providing a general HTML sanitizer.
- Syntax highlighting.
- Defining syntax beyond what the selected `cmark-gfm` version supports.
- Emulating GitHub.com post-processing that is not part of the published GFM specification.

## 4. Design Principles

### 4.1 Layer the library

Separate the package into four conceptual layers:

1. A small C compatibility shim.
2. Private Chez foreign-function bindings.
3. A high-level parser, renderer, and Scheme AST API.
4. An optional SXML interoperability library.

### 4.2 Prefer Scheme-owned results

Public parsing operations should return data owned by Chez. Native node and string pointers must not escape the dynamic extent in which the cmark document is alive.

### 4.3 Use named options

Callers should select options with symbols, records, or keyword-like arguments, not cmark bit masks. Numeric constants belong in the private native layer.

### 4.4 Preserve parsing semantics; secure rendering separately

The Scheme AST should faithfully represent what was parsed, including raw HTML and unsafe-looking URLs. It must be documented as untrusted structured input.

Rendering APIs must apply a security policy:

- native HTML rendering uses cmark's safe defaults;
- SXML conversion escapes or rejects raw HTML by default and validates URLs;
- unsafe rendering requires an explicit option.

### 4.5 Fail clearly

Library-loading problems, unsupported extensions, invalid options, resource-limit failures, and native errors should become structured Scheme conditions rather than crashes or vague foreign-interface errors.

## 5. Proposed Package Structure

```text
chez-cmark-gfm/
├── Akku.manifest
├── Akku.lock
├── Makefile
├── README.md
├── LICENSE
├── src/
│   ├── cmark-gfm-shim.c
│   ├── cmark-gfm-shim.h
│   └── cmark/
│       ├── gfm.sls
│       └── gfm/
│           ├── ast.sls
│           ├── options.sls
│           ├── render.sls
│           ├── sxml.sls
│           └── private/
│               ├── native.sls
│               ├── convert.sls
│               └── conditions.sls
├── tests/
│   ├── run.sps
│   ├── fixtures/
│   └── expected/
└── examples/
    ├── render-html.sps
    ├── inspect-ast.sps
    └── convert-sxml.sps
```

Suggested libraries:

- `(cmark gfm)` — primary convenient API.
- `(cmark gfm ast)` — Scheme AST predicates, constructors, and accessors.
- `(cmark gfm options)` — immutable option records and validation.
- `(cmark gfm render)` — direct native renderers.
- `(cmark gfm sxml)` — optional safe conversion from the Scheme AST to SXML.
- `(cmark gfm private native)` — private FFI declarations; not a supported API.

The SXML library should not require `wak-htmlprag`. It should only produce ordinary SXML. Callers may choose any compatible serializer.

## 6. Public API

### 6.1 Version and capability inspection

```scheme
(cmark-gfm-version)              ; runtime native version string or record
(cmark-gfm-version-compatible?)
(cmark-gfm-available-extensions) ; list of symbols
```

Check native compatibility when the library initializes. Report both the version expected by the compiled shim and the version loaded at runtime.

### 6.2 Options

```scheme
(make-cmark-options
  extensions:
  validate-utf8?:
  smart-punctuation?:
  hardbreaks?:
  nobreaks?:
  source-positions?:
  unsafe-html?:
  max-input-bytes:
  max-nodes:
  max-depth:)

(default-cmark-options)
```

Recommended defaults:

```scheme
extensions:         '(autolink strikethrough table tagfilter tasklist)
validate-utf8?:     #t
smart-punctuation?: #f
hardbreaks?:        #f
nobreaks?:          #f
source-positions?:  #t
unsafe-html?:       #f
```

Reject contradictory settings such as enabling both `hardbreaks?` and `nobreaks?`.

Do not expose `CMARK_OPT_UNSAFE` under a vague name such as `safe?`. Use the explicit positive-risk name `unsafe-html?` and default it to `#f`.

### 6.3 Direct rendering

Version 1 should expose:

```scheme
(markdown->html markdown options)       ; HTML fragment
(markdown->commonmark markdown options)
(markdown->plaintext markdown options)
(markdown->xml markdown options)        ; cmark AST XML
```

Add these if their behavior and extension handling are verified:

```scheme
(markdown->latex markdown options)
(markdown->man markdown options)
```

Width-sensitive renderers should accept a validated width option or separate argument.

Direct rendering should parse and render within one native ownership scope, copy the result into a Chez string, and free every native allocation before returning.

### 6.4 Scheme AST parsing

```scheme
(markdown->ast markdown options) ; returns a Scheme-owned document node
```

The result must contain no native pointers. It remains valid after all cmark objects have been freed.

### 6.5 SXML interoperability

```scheme
(markdown-ast->sxml ast sxml-options)
(markdown->sxml markdown cmark-options sxml-options)
```

The convenience operation may parse directly and then invoke `markdown-ast->sxml`. The SXML adapter must be optional and kept separate from the core AST API.

## 7. Scheme AST Model

### 7.1 Generic immutable node

Use a generic immutable record so extension node types do not require changes to the base record definition:

```scheme
(make-markdown-node type properties children source-position)
(markdown-node? value)
(markdown-node-type node)        ; symbol
(markdown-node-properties node)  ; immutable alist or mapping
(markdown-node-children node)    ; list or vector
(markdown-node-source node)      ; source-position record or #f
```

Provide functional update helpers rather than mutable fields:

```scheme
(markdown-node-with-properties node properties)
(markdown-node-with-children node children)
(markdown-node-map proc node)
(markdown-node-fold proc seed node)
```

### 7.2 Source positions

```scheme
(make-source-position start-line start-column end-line end-column)
```

Source positions are diagnostic metadata, not security boundaries. Some `cmark-gfm` source positions for tables and inline constructs have known limitations.

### 7.3 Node types and properties

Document at least these types:

| Type | Important properties |
|---|---|
| `document` | none |
| `paragraph` | none |
| `heading` | `level` |
| `text` | `literal` |
| `emph` | none |
| `strong` | none |
| `strikethrough` | none |
| `blockquote` | none |
| `list` | `kind`, `start`, `tight?`, `delimiter` |
| `item` | `task?`, `checked?`, `index` |
| `link` | `url`, `title` |
| `image` | `url`, `title` |
| `code` | `literal` |
| `code-block` | `literal`, `fence-info` |
| `thematic-break` | none |
| `softbreak` | none |
| `linebreak` | none |
| `html-inline` | `literal` |
| `html-block` | `literal` |
| `table` | `columns`, `alignments` |
| `table-row` | `header?` |
| `table-cell` | alignment if needed |

Autolinks normally become ordinary link nodes. Task-list state is attached to list-item metadata.

### 7.4 Unknown extension nodes

Do not silently discard unknown native node types. Either:

- preserve them as `(extension ...)` nodes with the native type string and copied properties; or
- raise an `unsupported-node-type` condition in strict mode.

Default to preservation when it can be done without losing children or literals.

## 8. Native Binding and C Shim

### 8.1 Responsibilities of the C shim

The shim should:

- include the public `cmark-gfm` and core-extension headers;
- expose compile-time and runtime version information;
- register bundled GFM extensions once;
- normalize extension lookup and attachment;
- centralize option-bit construction where useful;
- expose a correct function for freeing renderer buffers;
- avoid exposing C structs by value;
- provide stable, Chez-friendly functions for nullable strings and pointers;
- return explicit status codes and error messages for initialization failures.

The shim must not duplicate the parser or renderer.

### 8.2 Required parser lifecycle

Wrap or bind:

```c
cmark_gfm_core_extensions_ensure_registered
cmark_parser_new
cmark_find_syntax_extension
cmark_parser_attach_syntax_extension
cmark_parser_feed
cmark_parser_finish
cmark_parser_free
cmark_node_free
```

Parser sequence:

1. Enforce the Scheme-side input-size limit.
2. Convert the Chez string to a UTF-8 byte buffer.
3. Create the parser.
4. Attach each requested extension.
5. Feed the buffer with its byte length.
6. Finish parsing to obtain the document root.
7. Free the parser.
8. Render or copy the AST.
9. Free the root exactly once.

### 8.3 Required traversal

Use:

```c
cmark_node_first_child
cmark_node_next
cmark_node_get_type_string
cmark_node_get_literal
```

Use these semantic accessors as applicable:

```c
cmark_node_get_heading_level
cmark_node_get_list_type
cmark_node_get_list_delim
cmark_node_get_list_start
cmark_node_get_list_tight
cmark_node_get_item_index
cmark_node_get_fence_info
cmark_node_get_url
cmark_node_get_title
cmark_node_get_start_line
cmark_node_get_start_column
cmark_node_get_end_line
cmark_node_get_end_column
```

Use the extension accessors:

```c
cmark_gfm_extensions_get_table_columns
cmark_gfm_extensions_get_table_alignments
cmark_gfm_extensions_get_table_row_is_header
cmark_gfm_extensions_get_tasklist_item_checked
```

Dispatch on `cmark_node_get_type_string` instead of duplicating cmark's numeric node-type enum in the public Scheme API.

### 8.4 Rendering APIs

Use the documented native renderers:

```c
cmark_render_html
cmark_render_xml
cmark_render_commonmark
cmark_render_plaintext
cmark_render_latex
cmark_render_man
```

The HTML renderer needs the list of attached syntax extensions so extension nodes render correctly. The binding must retain or reconstruct the extension list for rendering within the native document's lifetime.

Every renderer returns a native buffer that the caller must free. The C shim should provide one unambiguous release operation using the same allocator that created the buffer.

## 9. Memory Management

### 9.1 Ownership rules

For a parsed document:

1. Chez owns the original Scheme string.
2. The FFI layer creates or pins an explicit UTF-8 representation for the call.
3. The parser owns parsing state until `cmark_parser_free`.
4. `cmark_parser_finish` returns a root node that owns its entire descendant tree.
5. The parser can be freed after finishing; the root remains valid.
6. Node pointers and strings returned by node accessors are borrowed from the root.
7. The AST converter copies all required values into Chez-owned objects.
8. `cmark_node_free(root)` releases the root and all descendants exactly once.
9. No native node or borrowed string survives the root's lifetime.

For direct rendering:

1. Parse to a native root.
2. Render while the root and extension list remain alive.
3. Copy the returned UTF-8 renderer buffer into a Chez string.
4. Free the renderer buffer with the allocator expected by `cmark-gfm`.
5. Free the root.
6. Free any parser-owned or binding-owned extension-list container without freeing registry-owned extension objects.

### 9.2 Borrowed strings

These return borrowed pointers:

```c
cmark_node_get_type_string
cmark_node_get_literal
cmark_node_get_fence_info
cmark_node_get_url
cmark_node_get_title
```

Copy their UTF-8 contents immediately. Never store a borrowed C pointer in:

- a Scheme AST record;
- a closure;
- a delayed computation;
- a global table;
- an SXML tree;
- an exception object that may outlive conversion.

Handle `NULL` separately from an empty string. Several accessors return `NULL` when called for an incompatible node type.

### 9.3 Renderer buffers

`cmark-gfm` documents renderer results as caller-owned. Do not rely on Chez's foreign-string conversion to free those buffers.

The shim should expose a function such as:

```c
void chez_cmark_free_buffer(char *buffer);
```

implemented with the same cmark allocator used by the renderer. Copy the buffer into Chez before calling it.

### 9.4 Exception-safe cleanup

Cleanup must occur if:

- an extension is missing;
- parser setup fails;
- UTF-8 conversion raises a condition;
- AST conversion encounters an unsupported node;
- node-count or depth limits are exceeded;
- a security policy rejects content;
- copying a result into Scheme fails.

Centralize lifecycle handling in internal helpers equivalent to:

```scheme
(call-with-native-document markdown options proc)
(call-with-native-render-buffer root renderer proc)
```

Use `dynamic-wind` or an equally reliable guard. After freeing a pointer, immediately replace the Scheme variable holding it with a null or false value so cleanup cannot run twice.

The design must have exactly one owner for each parser, root, extension-list container, and renderer buffer.

### 9.5 Extension ownership

Call `cmark_gfm_core_extensions_ensure_registered` once during controlled initialization. Objects returned by `cmark_find_syntax_extension` are registry-owned. Do not free those extension objects from Scheme.

If a temporary linked-list container is created for rendering, free the container according to the public cmark API without freeing the registry-owned extension data it references.

### 9.6 UTF-8

- Convert Chez strings to UTF-8 explicitly.
- Pass byte lengths, never Scheme character counts.
- Enable `CMARK_OPT_VALIDATE_UTF8` by default.
- Document that invalid native input is replaced with U+FFFD by this cmark option.
- Reject embedded NUL characters at the public Scheme boundary because downstream accessors return NUL-terminated C strings.
- Copy all native output into Chez before native cleanup.

### 9.7 Recursion and resource limits

The first AST converter may recurse through child and sibling nodes because that closely matches the Scheme tree. Enforce:

- maximum input bytes before parsing;
- maximum copied nodes;
- maximum traversal depth.

If deeply nested valid documents are an important use case, replace recursive traversal with `cmark_iter` or an explicit Scheme stack.

### 9.8 Native diagnostics

Run the shim and integration tests under:

- AddressSanitizer;
- UndefinedBehaviorSanitizer where supported;
- Valgrind or a platform-equivalent leak checker;
- a repeated parse/render/copy stress test.

Test successful and failing paths. Stable memory after allocator warm-up is required for long repeated runs.

## 10. Security

### 10.1 Security boundary

Parsing is not sanitization. The Scheme AST faithfully represents potentially unsafe input.

There are two distinct rendering paths:

- Native HTML rendering relies on `cmark-gfm` safe mode, which is the default when `CMARK_OPT_UNSAFE` is absent.
- SXML rendering is custom rendering and must enforce its own safety policy.

### 10.2 Direct HTML rendering

Default behavior:

- do not set `CMARK_OPT_UNSAFE`;
- keep raw HTML suppressed by cmark's renderer;
- keep unsafe links suppressed by cmark's renderer;
- enable requested GFM extensions explicitly;
- return an HTML fragment, not claim to return a complete HTML document.

Unsafe rendering must require `unsafe-html?: #t`. Document that callers who enable it must apply an HTML sanitizer appropriate to their application.

Do not provide a global mutable switch for unsafe mode. Security behavior belongs to each immutable options object.

### 10.3 Scheme AST

The AST may contain:

- `html-inline` and `html-block` literals;
- links with dangerous schemes;
- image sources with dangerous schemes;
- oversized strings or deeply nested structures within configured limits.

Document the AST as untrusted data. Generic AST operations must not imply that it is safe to serialize as HTML.

### 10.4 SXML adapter

The optional SXML adapter must default to:

- emit text nodes as Scheme strings for serializer escaping;
- escape raw HTML nodes as visible text or reject them;
- validate link and image URLs;
- reject unsafe attribute content;
- sanitize code-fence language tokens before using them as CSS classes;
- never concatenate untrusted strings into markup.

Support explicit raw-HTML policies:

- `'escape` — default;
- `'reject` — raise a structured condition;
- `'trusted` — return a distinguishable raw node only if the caller explicitly enables it.

The core library should not claim that trusted mode is sanitized.

### 10.5 URL policy for SXML

Default URL rules:

- allow relative URLs;
- allow fragment-only URLs;
- allow `http`, `https`, and `mailto`;
- reject `javascript`, `vbscript`, `file`, and `data`;
- compare schemes case-insensitively;
- reject leading control characters and embedded NULs;
- avoid adding `target="_blank"` automatically.

Expose URL-policy customization as a procedure or immutable policy record rather than as ad hoc flags.

### 10.6 Resource exhaustion

Before parsing, enforce `max-input-bytes`. During Scheme AST conversion, enforce `max-nodes` and `max-depth`.

Native parsing necessarily occurs before the final node count is known, so the input-size limit is the primary pre-allocation defense. Document that these limits reduce risk but do not form a hard real-time or constant-memory sandbox.

### 10.7 Dynamic-library safety

- Do not accept a shared-library path from Markdown input.
- Do not search the current working directory before trusted package/system locations.
- Verify the runtime `cmark-gfm` version against the compiled shim.
- Fail closed on incompatible versions.
- Do not load arbitrary cmark plugins in version 1.

## 11. SXML Mapping

The optional adapter should implement a minimal, predictable mapping:

| Markdown AST | SXML |
|---|---|
| `document` | `(*TOP* ...)` |
| `paragraph` | `(p ...)` |
| `heading` | `(h1 ...)` through `(h6 ...)` |
| `text` | string |
| `emph` | `(em ...)` |
| `strong` | `(strong ...)` |
| `strikethrough` | `(del ...)` |
| `blockquote` | `(blockquote ...)` |
| bullet `list` | `(ul ...)` |
| ordered `list` | `(ol ...)` |
| `item` | `(li ...)` |
| `link` | `(a (@ (href ...)) ...)` |
| `image` | `(img (@ (src ...) (alt ...)))` |
| inline `code` | `(code ...)` |
| `code-block` | `(pre (code ...))` |
| `thematic-break` | `(hr)` |
| `softbreak` | configurable newline or space |
| `linebreak` | `(br)` |
| `table` | `(table ...)` |
| `table-row` | `(tr ...)` |
| header `table-cell` | `(th ...)` |
| body `table-cell` | `(td ...)` |

The adapter should not generate opinionated heading IDs, navigation, a table of contents, or a page wrapper. Those belong to downstream applications.

Task-list items may prepend a disabled checkbox input. If emitted, checked state and attributes must be constructed by the adapter, not copied from input HTML.

## 12. Conditions and Diagnostics

Define structured conditions for:

- native library unavailable;
- runtime/compile-time version incompatibility;
- extension unavailable;
- invalid option combination;
- embedded NUL input;
- parser initialization failure;
- renderer failure;
- unsupported native node type;
- input-size, node-count, or depth limit exceeded;
- unsafe URL rejected by the SXML adapter;
- raw HTML rejected by the SXML adapter.

Include source positions in node-related conditions when available. Do not promise exact positions for every inline or extension node.

## 13. Testing Strategy

### 13.1 Initialization and ABI tests

- Load the native libraries from supported installation layouts.
- Compare compile-time and runtime versions.
- Fail correctly with a missing core library.
- Fail correctly with a missing extension library.
- Verify every standard GFM extension can be found and attached.

### 13.2 Parser and AST tests

Test every documented node and property:

- paragraphs and text;
- headings and levels;
- emphasis and strong emphasis;
- block quotes;
- tight and loose lists;
- ordered-list start values and delimiters;
- links, images, URLs, and titles;
- inline and fenced code plus fence info;
- raw inline and block HTML;
- soft and hard line breaks;
- tables and alignment;
- strikethrough;
- autolinks;
- checked and unchecked task items;
- source positions;
- unknown-node preservation or strict failure.

All results must remain valid after native cleanup to demonstrate that the AST is genuinely Scheme-owned.

### 13.3 Renderer differential tests

For the same pinned native version, compare binding output with the `cmark-gfm` command-line program for:

- HTML;
- CommonMark;
- plaintext;
- XML;
- any additional renderer exposed in version 1.

Test every extension combination supported by the public options API.

### 13.4 Security tests

Include at least:

```text
<script>alert(1)</script>
[click](javascript:alert(1))
[click](JaVaScRiPt:alert(1))
[file](file:///etc/passwd)
![image](data:text/html,...)
<img src=x onerror=alert(1)>
```

Verify separately that:

- direct HTML rendering is safe by default;
- unsafe native rendering changes behavior only when explicitly requested;
- the Scheme AST preserves the parsed information and is documented as untrusted;
- SXML conversion escapes or rejects raw HTML by default;
- SXML URL validation rejects dangerous schemes;
- text and attribute values are represented in a form that a conforming SXML serializer will escape.

### 13.5 Memory and failure tests

- Empty and minimal input.
- Very large input at and beyond the configured limit.
- Deeply nested input at and beyond the configured limit.
- Failure during extension attachment.
- Failure during AST copying.
- Failure during renderer-result copying.
- Repeated parsing, rendering, and AST conversion.
- Cleanup following every structured condition.
- No double frees when cleanup itself follows a partial failure.
- No access to node strings after the root is freed.

Run these under native memory diagnostics.

### 13.6 Conformance corpus

Use the CommonMark examples and GFM specification examples as externally defined fixtures where licensing and test harness integration permit. The binding does not need to retest cmark's parser implementation exhaustively, but it must verify that its option selection, extension attachment, AST copying, and output do not change the native semantics.

## 14. Build and Packaging

- Discover `cmark-gfm` and its core extensions through `pkg-config` where available.
- Avoid hard-coded Homebrew, Linux, or user-directory paths.
- Record supported native version ranges.
- Pin the native version in continuous integration.
- Build the compatibility shim with warnings enabled and treated as errors in CI.
- Provide Akku metadata and a locked development environment.
- Ensure the core package does not depend on `wak-htmlprag` or a site generator.
- Test current supported Chez on Linux and macOS.
- Document static versus dynamic linking behavior.
- Include license notices for the binding and its native dependency.

## 15. Milestones

### Milestone 0: Compatibility spike

- Load current `cmark-gfm` and its core-extension library from Chez.
- Report the runtime version.
- Attach all five standard GFM extensions.
- Parse a document containing a heading, table, strikethrough, autolink, and task list.
- Traverse the AST and free it without leaks.

Exit criterion: a Chez program prints the expected native node types and exits cleanly under a leak checker.

### Milestone 1: Shim and lifecycle foundation

- Implement the C shim.
- Implement version checking and extension initialization.
- Bind parser, root, renderer-buffer, and extension-list lifecycles.
- Add structured initialization conditions.
- Add sanitizer-enabled native tests.

Exit criterion: every owned native allocation has a tested success and failure cleanup path.

### Milestone 2: Direct renderers

- Implement immutable options.
- Implement HTML, CommonMark, plaintext, and XML conversions.
- Correctly pass attached extensions to the HTML renderer.
- Copy and free renderer buffers.
- Add differential tests against the native CLI.

Exit criterion: outputs match the pinned `cmark-gfm` CLI for the supported option matrix.

### Milestone 3: Scheme AST

- Implement immutable Scheme node and source-position records.
- Copy every supported core node.
- Copy GFM tables, task-list state, autolinks, and strikethrough.
- Enforce input, node, and depth limits.
- Preserve or reject unknown node types according to options.

Exit criterion: the returned AST contains no native pointers and remains valid after native cleanup.

### Milestone 4: Security hardening

- Confirm native safe-mode behavior.
- Make unsafe rendering explicitly opt-in.
- Reject embedded NUL input.
- Add malicious-input and resource-exhaustion tests.
- Test dynamic-library resolution and version mismatch behavior.

Exit criterion: all documented safe defaults have regression tests.

### Milestone 5: Optional SXML adapter

- Implement the minimal AST-to-SXML mapping.
- Add raw-HTML and URL policies.
- Test escaping assumptions with at least one supported serializer without making it a core dependency.
- Document that the adapter returns a fragment/tree, not a full page.

Exit criterion: representative CommonMark and GFM documents produce safe, structurally correct SXML.

### Milestone 6: Packaging and release

- Publish Akku metadata.
- Complete API and ownership documentation.
- Add examples for rendering, AST inspection, and SXML conversion.
- Publish the supported Chez/platform/native-version matrix.
- Run sanitizer, leak, stress, and conformance tests.

Exit criterion: a clean project can install the package and use each public API from the documentation.

## 16. Acceptance Criteria

Version 1 is complete when:

- All five standard GFM extensions can be selected and are enabled by default.
- HTML, CommonMark, plaintext, and XML renderers work through named Scheme options.
- Direct HTML output uses cmark's safe mode unless unsafe behavior is explicitly requested.
- Renderer buffers are copied and freed correctly.
- `markdown->ast` returns only Scheme-owned objects.
- Every borrowed native string is copied before root cleanup.
- Parsers, roots, extension-list containers, and renderer buffers are freed exactly once on success and failure paths.
- Embedded NUL input is rejected and UTF-8 handling is documented.
- Input-size, node-count, and depth limits are enforced.
- CommonMark and GFM node types are represented and tested.
- The optional SXML adapter escapes or rejects raw HTML by default and validates URLs.
- Runtime native-version incompatibility fails clearly.
- Native tests pass under AddressSanitizer and a leak checker.
- Supported Chez, platform, and `cmark-gfm` versions are documented.
- The core library has no dependency on a documentation-site framework.

## 17. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Native ABI changes | Compile a shim against public headers, check runtime versions, and test pinned versions in CI. |
| Renderer buffer leak | Centralize copy-and-free behavior in one internal helper and test repeated rendering. |
| Borrowed node strings escape | Return only Scheme-owned AST records and keep native bindings private. |
| Double free during conditions | Give each pointer one owner and clear it immediately after cleanup. |
| Extension objects are freed incorrectly | Treat registry results as borrowed; free only binding-owned list containers. |
| GFM nodes lose metadata during copying | Test table alignment, header rows, task state, autolinks, and strikethrough explicitly. |
| Custom SXML output bypasses cmark safety | Give the adapter its own raw-HTML and URL policies. |
| Users assume AST content is sanitized | State prominently that parsing preserves untrusted content and sanitization occurs during rendering. |
| Deep documents overflow Scheme recursion | Enforce a depth limit and retain iterator-based traversal as a fallback. |
| Dynamic loader selects an unintended library | Restrict search behavior and verify compile-time/runtime versions. |
| Scope expands into a site generator | Keep templates, navigation, manifests, and output orchestration out of the package. |

## 18. Possible Future Work

- A controlled managed-native-document API for advanced users.
- Native AST mutation with explicit lifetime scopes.
- Rebuilding a native AST from the Scheme AST.
- Additional cmark renderers or options after compatibility tests.
- Optional footnote support.
- Streaming input ports for very large documents.
- Custom allocators or allocation accounting.
- A generic visitor protocol for Scheme AST transformations.
- Separate downstream packages for documentation generation or syntax highlighting.

## 19. References

- [CommonMark specification](https://spec.commonmark.org/spec)
- [`cmark`, the CommonMark C reference implementation](https://github.com/commonmark/cmark)
- [`cmark-gfm`](https://github.com/github/cmark-gfm)
- [`cmark-gfm` public parser, AST, renderer, option, and version API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm.h)
- [`cmark-gfm` extension API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm-extension_api.h)
- [`cmark-gfm` core-extension accessors](https://github.com/github/cmark-gfm/blob/master/extensions/cmark-gfm-core-extensions.h)
- [GitHub Flavored Markdown specification](https://github.github.com/gfm/)
