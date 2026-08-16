# Project Plan: Chez Scheme `cmark-gfm` to SXML Documentation Pipeline

## 1. Summary

Build a lightweight documentation toolchain for Chez Scheme that:

1. Parses CommonMark and GitHub Flavored Markdown with `cmark-gfm`.
2. Traverses the native `cmark-gfm` abstract syntax tree (AST) from Chez Scheme.
3. Converts the AST directly into Scheme-owned SXML/SHTML.
4. Applies Scheme-native transformations such as heading IDs, navigation, tables of contents, link rewriting, and page templates.
5. Serializes the final SXML/SHTML to HTML with `wak-htmlprag`.

The preferred pipeline is:

```text
Markdown source
    |
    v
cmark-gfm parser
    |
    v
native cmark AST
    |
    v
Chez AST-to-SXML converter
    |
    +-- security policy
    +-- heading IDs and anchors
    +-- table of contents
    +-- link rewriting
    +-- navigation and page template
    |
    v
wak-htmlprag serializer
    |
    v
static HTML site
```

This avoids the less desirable Markdown -> HTML -> HTML parser -> SXML round trip.

## 2. Goals

- Support CommonMark plus the standard GFM extensions:
  - autolinks;
  - strikethrough;
  - tables;
  - tag filtering;
  - task-list items.
- Expose a small, stable Chez API rather than the entire `cmark-gfm` C API.
- Produce ordinary SXML/SHTML that downstream Scheme code can inspect and transform.
- Keep all native AST ownership inside a single conversion call in the first release.
- Be safe by default when processing untrusted or accidentally hostile Markdown.
- Generate a small static documentation site without requiring a larger site generator.
- Package the libraries so that they can be installed reproducibly, preferably through Akku.

## 3. Non-goals for Version 1

- A general-purpose binding for every `cmark-gfm` mutation API.
- Editing Markdown by modifying the native AST and rendering it back to Markdown.
- A long-lived Chez wrapper around individual native AST nodes.
- JavaScript-powered search or client-side rendering.
- Built-in syntax highlighting. Version 1 will emit language classes that an external highlighter or CSS can use.
- Full compatibility with every GitHub.com post-processing behavior. `cmark-gfm` implements the documented GFM syntax, while GitHub applies additional processing and sanitization on its service.
- Footnotes, YAML front matter, alerts/admonitions, or arbitrary Markdown plugins unless they are added as explicitly designed extensions later.

## 4. Proposed Package Structure

Use separate libraries so that the native binding, semantic conversion, and site builder remain independently testable.

```text
chez-cmark-gfm/
├── Akku.manifest
├── Makefile
├── README.md
├── LICENSE
├── src/
│   ├── cmark-gfm-shim.c
│   ├── cmark-gfm-shim.h
│   ├── cmark/
│   │   ├── gfm.sls
│   │   ├── gfm/
│   │   │   ├── native.sls
│   │   │   ├── sxml.sls
│   │   │   ├── security.sls
│   │   │   └── transform.sls
│   └── docs/
│       ├── builder.sls
│       ├── manifest.sls
│       └── template.sls
├── tests/
│   ├── run.sps
│   ├── fixtures/
│   └── expected/
└── examples/
    ├── convert-file.sps
    └── build-site.sps
```

Suggested public libraries:

- `(cmark gfm)` — high-level Markdown parsing configuration.
- `(cmark gfm sxml)` — safe one-shot Markdown-to-SXML conversion.
- `(cmark gfm transform)` — heading, link, and table-of-contents transforms.
- `(docs builder)` — page manifest, navigation, templating, and static-site output.

Keep `(cmark gfm native)` private or clearly marked unstable.

## 5. Public Scheme API

Start with a narrow API that returns only Scheme-owned data:

```scheme
(markdown->sxml markdown options)       ; string -> SXML
(markdown-file->sxml pathname options) ; file -> SXML

(default-markdown-options)
(make-markdown-options
  extensions:
  raw-html-policy:
  allowed-url-schemes:
  max-input-bytes:
  max-nodes:
  max-depth:)

(add-heading-ids sxml)
(extract-table-of-contents sxml)
(rewrite-document-links sxml mapping)
(render-page metadata navigation body-sxml)
(build-documentation-site manifest output-directory)
```

Recommended defaults:

```scheme
extensions:          '(autolink strikethrough table tagfilter tasklist)
raw-html-policy:     'escape
allowed-url-schemes: '(http https mailto)
```

Relative URLs and fragment-only URLs should be allowed after validation.

Do not expose native `cmark_node*` pointers through the public API in version 1. This makes memory ownership much easier to reason about and prevents use-after-free bugs in client code.

## 6. Native Binding Design

### 6.1 Why use a small C shim

Chez can bind the C API directly with `foreign-procedure`, but a small C shim will:

- hide enum values and small ABI differences;
- centralize extension registration and parser setup;
- normalize null pointers and error reporting;
- provide length-aware UTF-8 boundaries;
- reduce the number of native calls made by Scheme;
- make AddressSanitizer and native leak testing easier;
- prevent Scheme code from depending on private C structs.

The shim must use only documented public headers and functions.

### 6.2 Required parser functions

The implementation will use or wrap:

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

The parser flow is:

1. Register the bundled GFM extensions once per process.
2. Create a parser with validated options.
3. Find and attach the selected extensions by name.
4. Feed the complete UTF-8 document or feed it incrementally.
5. Finish parsing and obtain the document root.
6. Free the parser.
7. Traverse and copy the document into Scheme-owned SXML.
8. Free the document root exactly once.

### 6.3 Required traversal and accessor functions

Core traversal:

```c
cmark_node_first_child
cmark_node_next
cmark_node_get_type_string
cmark_node_get_literal
```

Semantic properties:

```c
cmark_node_get_heading_level
cmark_node_get_list_type
cmark_node_get_list_start
cmark_node_get_list_tight
cmark_node_get_fence_info
cmark_node_get_url
cmark_node_get_title
cmark_node_get_start_line
cmark_node_get_start_column
cmark_node_get_end_line
cmark_node_get_end_column
```

GFM-specific properties:

```c
cmark_gfm_extensions_get_table_columns
cmark_gfm_extensions_get_table_alignments
cmark_gfm_extensions_get_table_row_is_header
cmark_gfm_extensions_get_tasklist_item_checked
```

Use `cmark_node_get_type_string` for dispatch, including extension node types. This avoids duplicating native enum values in Scheme and handles GFM node types such as tables and strikethrough more naturally.

### 6.4 Recursive traversal versus native iterator

Use child/sibling recursion for the first implementation because it maps directly to nested SXML. Enforce a maximum nesting depth before recursing further.

The native `cmark_iter` API remains an alternative for later transformations or for replacing recursion if deeply nested inputs prove inconvenient.

## 7. AST-to-SXML Mapping

Initial mapping:

| cmark type | SXML/SHTML result | Notes |
|---|---|---|
| `document` | `(*TOP* ...)` | May also return its child sequence internally. |
| `paragraph` | `(p ...)` | Tight-list paragraph handling may be applied during list conversion. |
| `heading` | `(h1 ...)` through `(h6 ...)` | Add a stable, unique `id`. |
| `text` | Scheme string | Serializer must escape it. |
| `emph` | `(em ...)` | |
| `strong` | `(strong ...)` | |
| `strikethrough` | `(del ...)` | GFM extension. |
| `blockquote` | `(blockquote ...)` | |
| `list` | `(ul ...)` or `(ol ...)` | Preserve ordered-list start when non-default. |
| `item` | `(li ...)` | Add task-list checkbox when applicable. |
| `link` | `(a (@ (href ...)) ...)` | URL must pass the security policy. |
| `image` | `(img (@ (src ...) (alt ...)))` | URL must pass the security policy. |
| `code` | `(code "...")` | Inline code. |
| `code_block` | `(pre (code ...))` | Sanitize the fence info before creating a CSS class. |
| `thematic_break` | `(hr)` | |
| `softbreak` | newline or single space | Make this configurable if necessary. |
| `linebreak` | `(br)` | |
| `table` | `(table ...)` | Preserve alignment as controlled classes or styles. |
| `table_row` | `(tr ...)` | Use extension metadata to identify header rows. |
| `table_cell` | `(th ...)` or `(td ...)` | Depends on parent row metadata. |
| `html_inline` | escaped text, rejected node, or parsed trusted HTML | Default is escaped text. |
| `html_block` | escaped text, rejected node, or parsed trusted HTML | Default is escaped text. |

Autolinks normally arrive as ordinary link nodes. Task-list state is metadata on a list item rather than necessarily a separate node type.

### 7.1 Heading identifiers

Heading IDs should be generated after AST conversion so that the policy is entirely under Scheme control.

Requirements:

- deterministic for the same heading text;
- URL-safe;
- unique within a page;
- stable when unrelated headings are inserted;
- able to preserve an explicit future heading-ID extension if one is introduced.

For duplicates, append a suffix such as `-2`, `-3`, and so on.

### 7.2 Code-fence language classes

For a fence such as:

````markdown
```scheme
(display "hello")
```
````

emit:

```scheme
(pre
  (code (@ (class "language-scheme"))
        "(display \"hello\")\n"))
```

Only accept a conservative language-token character set, such as ASCII letters, digits, `_`, `-`, and `+`. Do not copy arbitrary fence metadata into an HTML attribute.

## 8. Security Design

### 8.1 Threat model

The tool will often process trusted files committed to the same repository, but it must remain safe if Markdown comes from an external contributor, downloaded package, generated input, or compromised dependency.

Threats include:

- cross-site scripting through raw HTML;
- `javascript:`, `data:`, `vbscript:`, or `file:` URLs;
- malicious image sources;
- attribute injection through code-fence metadata or generated IDs;
- resource exhaustion through huge or pathologically nested input;
- unsafe output paths escaping the build directory;
- symlink surprises during site generation;
- incorrect assumptions that cmark's HTML renderer has sanitized a custom SXML rendering.

### 8.2 Critical rule: custom rendering owns sanitization

The project will consume the AST and perform its own SXML rendering. Therefore, the safety behavior of `cmark-gfm`'s built-in HTML renderer does not automatically protect the generated output.

In particular:

- `CMARK_OPT_UNSAFE` and the built-in renderer's raw-HTML suppression are not a substitute for a custom SXML security policy.
- The GFM `tagfilter` extension alone must not be treated as a complete sanitizer for custom rendering.
- All text and attribute values must pass through SXML serialization or explicit escaping; never concatenate untrusted strings into HTML.

### 8.3 Raw HTML policy

Support three explicit policies:

- `'escape` — default; emit raw HTML nodes as visible text.
- `'reject` — fail conversion with a source position and explanatory condition.
- `'trusted` — allow raw HTML only for explicitly trusted project documentation.

For `'trusted`, either parse the fragment with `wak-htmlprag` and inspect the resulting SHTML or deliberately emit it through a separately named unsafe path. Do not silently treat ordinary strings as raw markup.

Even trusted mode should reject or strip dangerous elements and attributes if the resulting site can include contributions from people who are not fully trusted.

### 8.4 URL policy

Apply validation to every link and image URL before placing it in an SXML attribute.

Default rules:

- allow relative URLs;
- allow fragment-only references;
- allow `http`, `https`, and `mailto` schemes;
- reject `javascript`, `vbscript`, `data`, and `file` schemes;
- compare schemes case-insensitively;
- trim or reject leading control characters and whitespace;
- reject embedded NUL characters;
- normalize local `.md` links to the corresponding `.html` output only after validation;
- do not add `target="_blank"` by default;
- if external links later use `target="_blank"`, also add `rel="noopener noreferrer"`.

Images may use a stricter policy than links. Data URIs should remain disabled by default.

### 8.5 Output-path policy

The site builder must:

- resolve every output path beneath one explicit build directory;
- reject absolute output paths from the page manifest;
- reject `..` traversal that escapes the build directory;
- avoid following unexpected symlinks when overwriting generated pages;
- write to a temporary file and rename it into place when practical;
- never delete directories outside the resolved build root.

### 8.6 Resource limits

Provide configurable limits, with conservative defaults:

- maximum input bytes per Markdown file;
- maximum number of AST nodes converted;
- maximum AST/SXML nesting depth;
- maximum output size, if practical;
- maximum number of pages in a single build manifest.

Failure should raise a structured Scheme condition identifying the limit and source file.

### 8.7 Serializer verification

Tests must verify that `wak-htmlprag` correctly escapes text and attribute values used by this project. Pin or lock the tested package version. Never assume serializer safety without regression tests for `<`, `>`, `&`, quotes, malformed Unicode, and adversarial attribute values.

## 9. Memory Management and Native Ownership

### 9.1 Ownership model

Use this ownership sequence for every document:

1. Chez owns the input Scheme string.
2. A UTF-8 buffer is passed to the native parser with an explicit byte length.
3. The parser owns its parsing state until `cmark_parser_free`.
4. `cmark_parser_finish` returns a root node that owns its descendant tree.
5. The parser may be freed after finishing; the returned root remains valid.
6. Native node strings and node pointers are borrowed views tied to the root's lifetime.
7. The converter copies every needed native string into a new Chez string.
8. The converter constructs an entirely Scheme-owned SXML tree.
9. `cmark_node_free(root)` frees the root and all descendants exactly once.
10. No pointer, borrowed string, or native node wrapper may escape the conversion's dynamic extent.

### 9.2 Borrowed strings

Values returned by functions such as these are borrowed:

```c
cmark_node_get_type_string
cmark_node_get_literal
cmark_node_get_fence_info
cmark_node_get_url
cmark_node_get_title
```

Copy their contents into Chez strings before freeing the root. Do not store the returned C pointers in SXML, global tables, delayed computations, closures, or records that survive conversion.

Handle nullable results explicitly. Some accessors return `NULL` when called for an incompatible node type.

### 9.3 Exception-safe cleanup

All native allocations must be released even when:

- UTF-8 decoding fails;
- an unknown node type is encountered;
- a security policy rejects a URL or raw HTML node;
- a resource limit is exceeded;
- an SXML transformation raises a Scheme condition.

Implement cleanup with `dynamic-wind`, a guarded helper, or an equivalent single-exit ownership abstraction. The design should make it impossible to call `cmark_node_free` twice.

Conceptually:

```scheme
(define (with-cmark-document markdown options proc)
  (let ((root #f))
    (dynamic-wind
      (lambda ()
        (set! root (parse-native-document markdown options)))
      (lambda ()
        (proc root))
      (lambda ()
        (when root
          (cmark-node-free root)
          (set! root #f))))))
```

The final implementation must also free a partially created parser if setup or extension attachment fails before a root exists.

### 9.4 Extension ownership

Call `cmark_gfm_core_extensions_ensure_registered` during process initialization. Extensions returned by `cmark_find_syntax_extension` are registry-owned. Attach them to parsers as documented; do not free registry-owned extension pointers from Scheme.

### 9.5 UTF-8 boundary

- Convert Chez strings to UTF-8 explicitly.
- Pass the byte count rather than a character count.
- Enable `CMARK_OPT_VALIDATE_UTF8` unless testing proves a stronger local validation path is preferable.
- Reject embedded NUL characters at the public boundary even when the underlying length-aware parser could receive them; they complicate C-string accessors and downstream HTML handling.
- Copy native UTF-8 results into Chez before freeing the native root.
- Report invalid UTF-8 as a structured conversion condition rather than silently producing corrupted output.

### 9.6 Concurrency

Treat extension registration as process-global initialization. Ensure it is invoked once before concurrent conversions begin. After initialization, test concurrent conversions before documenting them as supported. Until then, state that the first version's site builder is single-threaded.

### 9.7 Native diagnostics

Run the native shim and integration tests under:

- AddressSanitizer;
- UndefinedBehaviorSanitizer where supported;
- Valgrind or the platform's equivalent leak checker;
- a repeated-conversion stress test.

The stress test should convert a representative corpus thousands of times and verify stable process memory after allocator warm-up.

## 10. Error Model

Define structured Scheme conditions for:

- native library unavailable or incompatible;
- extension unavailable;
- parser initialization failure;
- invalid UTF-8 or embedded NUL;
- unknown or unsupported AST node;
- unsafe URL;
- rejected raw HTML;
- input, depth, node, or output limit exceeded;
- invalid page manifest;
- unsafe output path;
- serialization failure.

Every document-related condition should include the source pathname when known. Node-related conditions should include the cmark start and end positions when reliable.

Do not depend on exact inline source positions for security decisions. Some open `cmark-gfm` issues document imperfect source positions for tables and certain inline constructs.

## 11. Documentation Site Layer

### 11.1 Page manifest

Use ordinary Scheme data as the site manifest:

```scheme
(define documentation-pages
  '(("index.md"     "index.html"     "Introduction")
    ("install.md"   "install.html"   "Installation")
    ("guide.md"     "guide.html"     "Guide")
    ("reference.md" "reference.html" "API Reference")))
```

Generate from this single source:

- input and output paths;
- page titles;
- primary navigation;
- active-page state;
- previous/next links;
- `.md` to `.html` link mapping;
- an optional documentation index.

### 11.2 Page template

Use quasiquoted SXML rather than adding another template language:

```scheme
(define (page-template metadata navigation body)
  `(html
     (@ (lang "en"))
     (head
       (meta (@ (charset "utf-8")))
       (meta (@ (name "viewport")
                (content "width=device-width, initial-scale=1")))
       (link (@ (rel "stylesheet") (href "assets/docs.css")))
       (title ,(metadata-title metadata)))
     (body
       (header ,(site-header metadata))
       (nav (@ (aria-label "Documentation")) ,@navigation)
       (main ,@body)
       (footer ,(site-footer metadata)))))
```

All untrusted values inserted into the template must remain SXML strings or validated attribute values.

### 11.3 Transform order

Apply transformations in a documented order:

1. Convert cmark AST to safe SXML.
2. Generate unique heading IDs.
3. Extract the table of contents.
4. Rewrite local documentation links.
5. Validate internal fragments where possible.
6. Insert page-level navigation and metadata.
7. Serialize to HTML.

## 12. Testing Strategy

### 12.1 Unit tests

Test each standard mapping independently:

- text escaping;
- headings at every level;
- emphasis and strong emphasis;
- links, titles, and images;
- ordered and unordered lists;
- tight and loose lists;
- block quotes;
- inline and fenced code;
- soft and hard line breaks;
- raw HTML policies.

Test each GFM extension:

- autolink URL and email cases;
- strikethrough;
- aligned and unaligned tables;
- table header/body distinction;
- checked and unchecked task-list items;
- disallowed raw HTML/tag-filter cases.

### 12.2 Security regression tests

Include fixtures for:

```text
<script>alert(1)</script>
[click](javascript:alert(1))
[click](JaVaScRiPt:alert(1))
![image](data:text/html,...)
[file](file:///etc/passwd)
<img src=x onerror=alert(1)>
```

Also test:

- leading whitespace and control characters before a scheme;
- percent-encoded or entity-obscured attacks;
- quotes and angle brackets in titles and alt text;
- malicious fence-info strings;
- duplicate and hostile heading text;
- output path traversal and absolute paths;
- symlink handling;
- maximum input, node, and depth limits.

Expected behavior must be explicit for every fixture: safely escaped output or a structured rejection.

### 12.3 Golden output tests

Store representative Markdown fixtures and expected SXML plus final HTML. Normalize only insignificant formatting; do not normalize away escaping or attribute differences that could conceal security regressions.

### 12.4 Differential tests

For constructs not intentionally transformed, compare the structural result with `cmark-gfm`'s own HTML renderer. Differences should be reviewed and documented rather than blindly accepted.

### 12.5 Native ownership tests

- Convert an empty document.
- Fail during extension attachment.
- Fail halfway through AST conversion.
- Trigger each resource limit.
- Repeat successful and failing conversions under a leak checker.
- Verify no borrowed pointer is accessed after root cleanup.
- Verify every parser and root has exactly one cleanup path.

### 12.6 Integration tests

Build a miniature site containing:

- multiple pages;
- cross-page links;
- fragment links;
- duplicate headings;
- a table;
- task lists;
- Scheme code fences;
- previous/next navigation.

Check that all generated local links resolve and all output paths remain inside the build directory.

## 13. Build and Packaging

- Discover `cmark-gfm` and its extensions library through `pkg-config` where available instead of hard-coding platform-specific paths.
- Record the exact tested `cmark-gfm` versions.
- Provide clear errors when the shared libraries cannot be loaded.
- Lock Akku dependencies, including `wak-htmlprag`.
- Provide a reproducible native build path for environments without a system package.
- Test at least Linux and macOS initially; add Windows only after the FFI and library-loading approach is validated there.
- Keep generated documentation out of the source library path.

## 14. Milestones

### Milestone 0: Compatibility spike

- Install or build current `cmark-gfm`.
- Confirm Chez can load both the core and extension shared libraries.
- Parse one CommonMark document and one table document.
- Confirm node type strings and table/task-list accessors.
- Validate `wak-htmlprag` serialization and escaping.

Exit criterion: a small program prints safe HTML generated through AST -> SXML, including a GFM table.

### Milestone 1: Native binding foundation

- Implement the C shim.
- Bind parser lifecycle, extension setup, traversal, and basic accessors.
- Implement structured native errors.
- Add ASan and leak-test builds.

Exit criterion: Chez can parse and safely free representative documents without leaks.

### Milestone 2: CommonMark-to-SXML conversion

- Implement all core node mappings.
- Add URL validation and raw HTML policies.
- Add UTF-8 handling and resource limits.
- Add golden SXML tests.

Exit criterion: the supported CommonMark fixture corpus converts deterministically and safely.

### Milestone 3: GFM conversion

- Enable all five GFM extensions.
- Implement strikethrough, tables, autolinks, task lists, and tag-filter policy.
- Add alignment and checkbox rendering.

Exit criterion: representative GFM fixtures match the intended HTML structure.

### Milestone 4: Documentation transforms

- Generate heading IDs.
- Extract tables of contents.
- Rewrite local Markdown links.
- Validate duplicate IDs and broken local links.

Exit criterion: a multi-page fixture site has correct navigation and internal links.

### Milestone 5: Site builder and packaging

- Add the page manifest and SXML template.
- Add atomic output writing and safe path resolution.
- Package for Akku.
- Write user and API documentation.
- Add continuous integration across supported Chez and platform versions.

Exit criterion: a new project can install the package and build documentation with one documented command.

### Milestone 6: Hardening and release

- Complete the security corpus.
- Run sanitizers, leak checks, and repeated-conversion tests.
- Test malformed and fuzz-generated Markdown.
- Pin dependencies and publish a compatibility matrix.
- Tag version `0.1.0` once all acceptance criteria pass.

## 15. Acceptance Criteria

The first release is complete when:

- CommonMark and the five standard GFM extensions convert to valid SXML/SHTML.
- The public API never exposes native AST pointers.
- All native strings are copied before root cleanup.
- Every parser and document root is freed exactly once, including error paths.
- Raw HTML is escaped by default.
- Dangerous URL schemes are rejected by default.
- Text and attribute escaping have adversarial regression tests.
- Configurable input-size, node-count, and depth limits are enforced.
- Generated output cannot escape the configured build directory.
- Tables, task lists, heading IDs, navigation, and local link rewriting work in an integration site.
- Native tests pass under AddressSanitizer and a leak checker.
- The supported Chez, `cmark-gfm`, operating system, and `wak-htmlprag` versions are documented.

## 16. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Existing `chez-cmark` is too minimal | Build a separate focused binding rather than depending on its one-shot API. |
| Native ABI or library names vary | Use a small shim, `pkg-config`, version checks, and platform CI. |
| Extension nodes differ from core nodes | Dispatch by documented type strings and test every enabled extension. |
| Custom rendering bypasses cmark HTML safety | Enforce security at AST-to-SXML conversion and test it adversarially. |
| Borrowed strings outlive the native tree | Copy all strings immediately and keep native pointers private. |
| Cleanup is skipped on Scheme exceptions | Centralize ownership in an exception-safe `with-cmark-document` helper. |
| Old serializer behavior causes bad escaping | Pin `wak-htmlprag` and maintain serializer-specific security tests. |
| Source positions are imperfect | Use them for diagnostics only, never as a security boundary. |
| Deep input overflows recursive Scheme traversal | Enforce a depth limit and retain the iterator API as a fallback. |
| Project grows into a general site generator | Keep the page manifest and transforms deliberately documentation-focused. |

## 17. Future Enhancements

- Expose a safe, Scheme-owned Markdown AST distinct from SXML.
- Add optional YAML front matter parsing before passing the remaining document to cmark.
- Add footnotes or alerts through explicitly versioned extensions.
- Add a syntax-highlighting hook that consumes fenced-code language metadata.
- Generate a search index as JSON or S-expressions.
- Add incremental builds based on source and template hashes.
- Add an optional trusted-HTML sanitizer rather than only escape/reject modes.
- Add a controlled advanced API for native AST inspection if a compelling need appears.

## 18. References

- [CommonMark specification](https://spec.commonmark.org/spec)
- [`cmark`, the CommonMark C reference implementation](https://github.com/commonmark/cmark)
- [`cmark-gfm`](https://github.com/github/cmark-gfm)
- [`cmark-gfm` public AST API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm.h)
- [`cmark-gfm` extension API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm-extension_api.h)
- [`cmark-gfm` core extension accessors](https://github.com/github/cmark-gfm/blob/master/extensions/cmark-gfm-core-extensions.h)
- [GitHub Flavored Markdown specification](https://github.github.com/gfm/)
- [`wak-htmlprag` Akku package](https://akkuscm.org/packages/wak-htmlprag/)
