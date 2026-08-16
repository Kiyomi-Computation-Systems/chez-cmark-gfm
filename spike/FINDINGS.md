# Stage 0 Findings

## Toolchain

| Item | Value |
|---|---|
| Chez Scheme | 10.4.1 |
| Machine type | tarm64osx |
| cmark-gfm CLI | cmark-gfm 0.29.0.gfm.13 - CommonMark with GitHub Flavored Markdown converter |
| pkg-config libcmark-gfm | 0.29.0.gfm.13 |
| libcmark-gfm-extensions .pc | absent — link manually via core libdir |
| Vendored submodule | vendor/cmark-gfm @ 0.29.0.gfm.13 |

## Open questions

- [x] Q1: How does Chez marshal `const char *`? (Task 3) — ANSWERED below
- [ ] Q2: Is the ADR-0005 use-after-free detectable by our tooling? (Task 5)

## Q0: loading

**Library path** (Step 1, `pkg-config --variable=libdir libcmark-gfm` + filename):

```
/opt/homebrew/Cellar/cmark-gfm/0.29.0.gfm.13/lib/libcmark-gfm.dylib
```

**Command run** (brief Step 3, verbatim):

```bash
chez --script spike/00-load.ss "$(pkg-config --variable=libdir libcmark-gfm)/libcmark-gfm.dylib"
```

**Actual observed output** — `spike/00-load.ss` now defines everything at top level (no `let` wrapping `load-shared-object` and the `define`s together), and running it exactly as above prints the three expected lines:

```
cmark_version()        = 1900557 (0x1D000D)
cmark_version_string() = 0.29.0.gfm.13
decoded                = 0.29.0.gfm.13
```

Exit code `0`. Confirmed deterministic across two separate runs (byte-identical output both times).

**Why top-level definitions fix it:** Scheme body syntax (`<body> -> <definition>* <expression>+`) requires every internal `define` in a body to precede all expressions sharing that body — a `define` that follows an expression in one `let` body raises `invalid context for definition`, exactly as the previous version of this script (which nested everything inside `(let ((lib ...)) ...)`) did. At top level, `define` and expressions may interleave freely: `(load-shared-object lib)` runs to completion as its own top-level form before the `foreign-procedure` `define`s execute. This ordering also happens to satisfy a second constraint — `foreign-procedure` resolves its C symbol eagerly at `define`-evaluation time, so the shared object must already be loaded by then regardless of body-syntax rules.

**Version encoding:** `CMARK_GFM_VERSION` packs *four* bytes, not three: `(major << 24) | (minor << 16) | (patch << 8) | gfm`. For `0.29.0.gfm.13` that is `0x001D000D` — decimal `1900557`, matching the observed `cmark_version()` output above. The four-byte decode reproduces `0.29.0.gfm.13` exactly, matching `cmark_version_string()`. (An earlier, incorrect three-field decode — `(major << 16) | (minor << 8) | patch` — misread this same integer as `29.0.13`; that formula is wrong and is no longer used.)

**Conclusion:** Chez can `load-shared-object` this library and call into it via `foreign-procedure`, using definitions kept at top level rather than interleaved with expressions inside a `let` body. The packed-integer version decodes correctly, via the four-byte layout, to match `cmark_version_string()`. Stage 1 is unblocked on both fronts.

## Q1: Chez `const char *` marshalling — ANSWERED

**Script:** `spike/01-strings.ss` (definitions kept at top level throughout, per the Q0 body-syntax finding above — no `define` follows an expression inside a `let`/lambda body).

**Command run** (brief Step 2, verbatim):

```bash
chez --script spike/01-strings.ss "$(pkg-config --variable=libdir libcmark-gfm)/libcmark-gfm.dylib"
```

Library path resolved to `/opt/homebrew/Cellar/cmark-gfm/0.29.0.gfm.13/lib/libcmark-gfm.dylib`.

**Actual observed output** (verbatim; byte-identical across two separate runs, exit code `0` both times):

```
--- (b) UTF-8 decoding ---
via `string` type : "Hello —world 世界"
via manual copy   : "Hello —world 世界"
identical?        : #t

--- (c) NULL handling ---
manual copy of NULL : #f
`string` type on NULL: #f

--- (a) copy vs alias ---
node type          : "text"
after free         : "Hello —world 世界"
still correct?     : #t
```

**Step 3 (Valgrind) — not run, by design.** This machine is macOS/ARM64; Valgrind
does not support this platform, so the brief's memory-tool step is skipped here
as instructed. Section (a) is therefore backed only by the value-comparison
probe embedded in the script (capture the `string`-typed value *before* freeing,
then `cmark_parser_free` + `cmark_node_free` the whole tree, force a GC pass with
`(collect)`, and compare the captured value against the pre-free original).
Preloading ASan as a substitute was considered and rejected: ASan only
instruments the loads it compiles from source, stock `libcmark-gfm.dylib` is a
prebuilt, uninstrumented binary, so an aliasing/use-after-free bug inside it
would go completely unreported by ASan in this configuration. **(a) is UNPROVEN
on this platform — the clean result below is evidence, not proof.**

| Question | Answer |
|---|---|
| (a) Does `string` copy? | Weakly evidenced yes, **not proven**. The captured value was still `"Hello —world 世界"` after `cmark_parser_free` + `cmark_node_free` + `(collect)`, `equal?` to the pre-free original. Consistent with a copy — but freed heap memory that has not yet been overwritten can read back correctly by coincidence, which is exactly the false-negative Valgrind exists to catch. Valgrind is unavailable on macOS/ARM64, so this is not proof. |
| (b) UTF-8 decoded correctly? | Yes, unambiguously. The `string`-typed accessor and a manual byte-for-byte `c-string->string` UTF-8 decode of the same address produced `equal?` Scheme strings, both displaying the em-dash (`—`, U+2014) and both CJK characters (`世界`, U+4E16 U+754C) correctly. |
| (c) Behaviour on NULL | Returns `#f`. `cmark_node_get_literal` on a paragraph node (no literal) returns a NULL `char *`. Bound with `string` as the foreign-procedure return type, Chez evaluated this directly to Scheme `#f` — no condition was raised (the probe's `guard` clause never fired: output was bare `#f`, not a `(raised ...)` list), no crash, and no empty string `""`. This behavior was not assumed going in; it is the literal, observed output. |

**Decision for Task 9: use `uptr` + manual copy.**

The verdict must be conservative — that is the point of this task. Spec 5.4
specifies the conservative `uptr` path by default, and permits the simpler
`string` path only if **all three** answers are unambiguously safe **and** (a)
was verified under Valgrind. Here, (b) and (c) are both unambiguously safe, but
(a) was **not** verified under Valgrind — Valgrind does not run on this
macOS/ARM64 machine, so (a) rests on a value-comparison alone, which cannot
rule out a use-after-free masked by not-yet-reclaimed heap memory. Per the
spec's own rule, that is disqualifying regardless of how clean the (a) result
looks. Task 9's FFI layer must therefore marshal every `const char *` return
as `uptr` and copy it explicitly with a `c-string->string`-style helper (as
prototyped in this spike's `c-string->string`), and must never bind a
`cmark_*` accessor's return type directly as `string`.

## Q3: node type strings

**Script:** `spike/02-parse.ss` (definitions kept at top level throughout, per the Q0 body-syntax finding — no `define` follows an expression inside a `let`/lambda body).

**Command run** (brief Step 2, verbatim):

```bash
LIBDIR="$(pkg-config --variable=libdir libcmark-gfm)"
chez --script spike/02-parse.ss \
  "$LIBDIR/libcmark-gfm.dylib" "$LIBDIR/libcmark-gfm-extensions.dylib"
```

Both paths resolved under `/opt/homebrew/Cellar/cmark-gfm/0.29.0.gfm.13/lib/`: `libcmark-gfm.dylib` and `libcmark-gfm-extensions.dylib` (the latter has no `.pc` file of its own, as already established in the Toolchain section above — its path is derived manually from the core library's libdir).

**Actual observed output** (verbatim; byte-identical across two separate runs, exit code `0` both times):

```
attach autolink -> rc=1
attach strikethrough -> rc=1
attach table -> rc=1
attach tagfilter -> rc=1
attach tasklist -> rc=1
heading
  text
paragraph
  text
  link
    text
  text
  strikethrough
    text
  text
table
  table_header
    table_cell
      text
    table_cell
      text
  table_row
    table_cell
      text
    table_cell
      text
list
  tasklist
    paragraph
      text
  tasklist
    paragraph
      text
html_block

OK: parsed, traversed, freed
```

**Attach return code: `rc=1`, not the brief's predicted `rc=0`.** All five `cmark_parser_attach_syntax_extension` calls returned `1`. The brief's Step 2 expected "`attach … rc=0` lines"; the actual value is `1` for every extension, consistently. This was checked against the vendored source rather than assumed: `vendor/cmark-gfm/src/blocks.c:102-111` shows `cmark_parser_attach_syntax_extension` unconditionally `return 1;` after appending the extension to the parser's list — there is no failure path and no `0` return in this function at all. So `rc=1` is the *only* value this function can ever produce in this library version; it means success (truthy), not a POSIX-style "0 is success" exit code. The brief's prediction of `rc=0` does not match the library's actual C source. Treat `rc=1` as the correct "attached successfully" signal for all five extensions in `cmark-gfm 0.29.0.gfm.13`.

**Node-type tree vs. the brief's predicted checklist** (`heading`, `table`, `table_row`, `table_cell`, `strikethrough`, `link`, `item`, `html_block`):

| Predicted type | Present? | Notes |
|---|---|---|
| `heading` | Yes | root-level, as predicted |
| `table` | Yes | as predicted |
| `table_row` | Yes | present, but only for the second (data) row — see finding below |
| `table_cell` | Yes | under both `table_header` and `table_row` |
| `strikethrough` | Yes | as predicted |
| `link` | Yes | produced by the autolink extension around the bare URL, as predicted |
| `item` | **No — absent from the entire tree** | see finding below |
| `html_block` | Yes | as predicted |

**Finding: `item` never appears — task-list items print as `tasklist` instead.** The brief's checklist predicted `item` for the two list entries (`- [x] done`, `- [ ] pending`), but the tree shows `tasklist` nodes nested directly under `list`; the string `item` does not occur anywhere in the output. This is real, source-confirmed behavior, not a spike bug: `cmark_node_get_type_string` (`vendor/cmark-gfm/src/node.c:239-246`) checks `node->extension && node->extension->get_type_string_func` *before* falling back to its switch over the core `cmark_node_type` enum, and the tasklist extension (`vendor/cmark-gfm/extensions/tasklist.c`) sets a hardcoded `static const char *TYPE_STRING = "tasklist";` returned unconditionally by its `get_type_string` override — so any node the tasklist extension attaches itself to reports as `"tasklist"` regardless of its underlying `CMARK_NODE_ITEM` enum value. Every list item in this spike's markdown is a checkbox item, so 100% of the items in this tree take the override; a plain (non-checkbox) `- like this` list item was not exercised here and, per the same source logic (no `node->extension` set), would fall through to the ordinary `"item"` string. **Consequence for Stage 3:** the AST converter's dispatch table must key `"tasklist"` as its own case distinct from `"item"` — code that dispatches on type string and only recognizes `"item"` will silently miss every GFM task-list entry.

**Unpredicted types that appeared** (not in the brief's checklist, all explicable): `text`, `paragraph`, and `list` are ordinary baseline CommonMark node types produced by any parse and were simply not called out in the brief's checklist. `table_header` is a distinct type from `table_row` for the header row of a table (row 1 of the table markdown, `| Fruit | Qty |`) — the brief's checklist named `table_row` but not `table_header`; both occur, as two different type strings for what markdown-source-wise are "rows" of the same table. `tasklist` appearing is a direct, expected consequence of attaching the tasklist extension, but the brief's own checklist named `item` instead, not `tasklist` — see the finding above.

**Determinism:** ran twice, byte-identical output both times, exit code `0` both times.

**Conclusion:** all five GFM extensions (`autolink`, `strikethrough`, `table`, `tagfilter`, `tasklist`) attach successfully (`rc=1`, the only value this library version's `cmark_parser_attach_syntax_extension` can return), and a document exercising every one of them parses, traverses depth-first via `cmark_node_first_child`/`cmark_node_next`, and frees (root then parser, per ADR-0005) without error. Seven of the brief's eight predicted node-type strings appeared exactly as predicted; `item` did not appear at all in this run because every list item in the test document was a task-list checkbox item, which the tasklist extension unconditionally relabels `"tasklist"` at the `cmark_node_get_type_string` level. Stage 3's dispatch table must account for `"tasklist"` as distinct from `"item"`, and should not assume `"item"` is the only list-item-shaped type string it will ever see.
