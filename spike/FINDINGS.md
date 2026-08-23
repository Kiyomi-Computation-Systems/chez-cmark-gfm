# Stage 0 Findings

> **Historical record, not current instructions.** This is the pre-2.0
> compatibility spike (commit `3752e78`), written when the acquisition
> path was `pkg-config` against a system-installed library. ADR-0015
> removed that path — 2.0 finds `libcmark-gfm` by scanning a fixed list of
> directories instead, with no `pkg-config` step anywhere. The toolchain
> table and commands below describe the spike's environment at the time,
> not how to install or build this project today; see
> [docs/installing.md](../docs/installing.md) for that.

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
- [x] Q2: Is the ADR-0005 use-after-free detectable by our tooling? (Task 5) — CONFIRMED below

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

## Q2: ADR-0005 use-after-free — CONFIRMED

**Script:** `spike/03-uaf.ss` (definitions kept at top level throughout, per the Q0 body-syntax finding — no `define` follows an expression inside a `let`/lambda body). Parses a one-row GFM table (forces the renderer to consult the syntax-extension list) with the `table` extension attached, then renders under one of two argv-selected teardown orderings: `buggy` calls `cmark_parser_free` — which frees `parser->syntax_extensions` via `cmark_llist_free` — *before* calling `cmark_render_html` with that same now-dangling list; `correct` renders first and frees the parser last, per ADR-0005.

**Step 1: build cmark-gfm with AddressSanitizer** (brief Step 1, verbatim flags):

```bash
cmake -S vendor/cmark-gfm -B build/asan \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address" \
  -DCMARK_TESTS=OFF -DCMARK_STATIC=OFF
cmake --build build/asan -j
```

**Deviation required to configure — recorded, not silently absorbed:** the vendored `CMakeLists.txt` declares `cmake_minimum_required(VERSION 3.0)`. CMake 4.3.3 (installed on this machine) hard-errors on that (`Compatibility with CMake < 3.5 has been removed from CMake`) rather than just warning. Added `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` — CMake's own suggested workaround in its error text — to the configure invocation. This only changes how CMake interprets the vendored project's minimum-version policy floor; it does not touch `CMAKE_C_FLAGS`, `CMAKE_SHARED_LINKER_FLAGS`, or any target definition. With that flag, configure succeeded (one deprecation warning only) and `HAVE_FLAG_SANITIZE_ADDRESS` reported `Success`. Build completed in ~1s on this 8-core machine (not the "several minutes" the brief allows for — evidently fast on this hardware). Produced `build/asan/src/libcmark-gfm.dylib` and `build/asan/extensions/libcmark-gfm-extensions.dylib`. Confirmed genuinely instrumented via `otool -L`: both dylibs link `@rpath/libclang_rt.asan_osx_dynamic.dylib` as a direct dependency.

**ASan runtime path** (brief Step 3, verbatim glob resolved with `ls | head -1`):

```
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/../lib/clang/21.0.0/lib/darwin/libclang_rt.asan_osx_dynamic.dylib
```

No literal `*` remained. Confirmed with `file`/`stat` to be a real 4924256-byte Mach-O universal binary (arm64 slice present, matching the running machine) — this is the same runtime as the sibling `.../clang/21/...` path (`21.0.0` is a symlink to `21`), consistent with the brief's ambiguity note. **Gotcha found and worked around:** this machine's `ls` is aliased to `command ls --color` (unconditional color, not `--color=auto`), which injects ANSI escape codes into `ls` output even under `$(...)` command substitution. On the first attempt this silently corrupted the captured path — `file` and `stat` both reported "No such file or directory" on a path that contained no literal `*` and looked correct when echoed to a color-capable terminal. This is exactly the "looks resolved, is not" failure mode the brief's ambiguity note warns about, just from a different cause than the glob itself. Worked around by resolving with `command ls` (bypasses the alias) instead of bare `ls`.

**Harness verification performed before trusting either run result** (per task requirement — a clean run is meaningless unless the harness is proven to be watching):
- `chez` (`/opt/homebrew/bin/chez`, Cellar `10.4.1`) is codesigned `adhoc,linker-signed` — not a hardened-runtime/SIP-restricted binary — so `DYLD_INSERT_LIBRARIES` is not stripped at launch. Checked directly with `codesign -dv`, not assumed.
- A diagnostic run with `DYLD_PRINT_LIBRARIES=1` added (in addition to the required env vars) showed the ASan runtime dylib loading, and both `libcmark-gfm` dylibs loading from full, hash-qualified paths under this repo's `build/asan/...` — not from `/opt/homebrew/Cellar/cmark-gfm/...`. No Homebrew/Cellar `libcmark-gfm` path appeared anywhere in the dyld trace.

**Command run — correct ordering** (brief Step 3, verbatim):

```bash
DYLD_INSERT_LIBRARIES="$ASAN_LIB" ASAN_OPTIONS=detect_leaks=0 \
  chez --script spike/03-uaf.ss \
    build/asan/src/libcmark-gfm.dylib \
    build/asan/extensions/libcmark-gfm-extensions.dylib correct
```

**Actual observed output** (verbatim; exit code `0`; stderr: 0 bytes, no sanitizer output of any kind):

```
<table>
<thead>
<tr>
<th>a</th>
<th>b</th>
</tr>
</thead>
<tbody>
<tr>
<td>1</td>
<td>2</td>
</tr>
</tbody>
</table>
done: correct
```

**Command run — buggy ordering** (brief Step 4, verbatim):

```bash
DYLD_INSERT_LIBRARIES="$ASAN_LIB" ASAN_OPTIONS=detect_leaks=0 \
  chez --script spike/03-uaf.ss \
    build/asan/src/libcmark-gfm.dylib \
    build/asan/extensions/libcmark-gfm-extensions.dylib buggy
```

**Actual observed output** — exit code `134` (SIGABRT — ASan aborts the process after reporting); stdout empty (the process aborted inside the C call, before control ever returned to the Scheme `printf`). Complete stderr, verbatim, 68 lines — the `heap-use-after-free` header and READ trace, the freed-by trace through `cmark_llist_free` → `cmark_parser_free`, the previously-allocated-by trace through `cmark_llist_append` → `cmark_parser_attach_syntax_extension`, the `SUMMARY` line, and the shadow-byte legend:

```
=================================================================
==28585==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000398 at pc 0x0001088d0b7c bp 0x00016f12a3d0 sp 0x00016f12a3c8
READ of size 8 at 0x602000000398 thread T0
    #0 0x0001088d0b78 in cmark_render_html_with_mem html.c:481
    #1 0x0001088d0958 in cmark_render_html html.c:469
    #2 0x00010a366de0  (<unknown module>)
    #3 0x000100d577ac in boot_call+0x28 (chez:arm64+0x1000837ac)
    #4 0x000100d57b7c in run_script+0x124 (chez:arm64+0x100083b7c)
    #5 0x000100cd5aa4 in main+0x7c4 (chez:arm64+0x100001aa4)
    #6 0x000190083dfc in start+0x1b4c (dyld:arm64e+0x1fdfc)

0x602000000398 is located 8 bytes inside of 16-byte region [0x602000000390,0x6020000003a0)
freed by thread T0 here:
    #0 0x0001017b5258 in free+0x7c (libclang_rt.asan_osx_dynamic.dylib:arm64e+0x41258)
    #1 0x000108859604 in xfree cmark.c:36
    #2 0x0001088e1948 in cmark_llist_free_full linked_list.c:31
    #3 0x0001088e197c in cmark_llist_free linked_list.c:36
    #4 0x0001088628f0 in cmark_parser_free blocks.c:164
    #5 0x00010a365f9c  (<unknown module>)
    #6 0x000100d577ac in boot_call+0x28 (chez:arm64+0x1000837ac)
    #7 0x000100d57b7c in run_script+0x124 (chez:arm64+0x100083b7c)
    #8 0x000100cd5aa4 in main+0x7c4 (chez:arm64+0x100001aa4)
    #9 0x000190083dfc in start+0x1b4c (dyld:arm64e+0x1fdfc)

previously allocated by thread T0 here:
    #0 0x0001017b5450 in calloc+0x80 (libclang_rt.asan_osx_dynamic.dylib:arm64e+0x41450)
    #1 0x0001088594e8 in xcalloc cmark.c:18
    #2 0x0001088e169c in cmark_llist_append linked_list.c:7
    #3 0x0001088620d8 in cmark_parser_attach_syntax_extension blocks.c:104
    #4 0x00010a364a4c  (<unknown module>)
    #5 0x000100d577ac in boot_call+0x28 (chez:arm64+0x1000837ac)
    #6 0x000100d57b7c in run_script+0x124 (chez:arm64+0x100083b7c)
    #7 0x000100cd5aa4 in main+0x7c4 (chez:arm64+0x100001aa4)
    #8 0x000190083dfc in start+0x1b4c (dyld:arm64e+0x1fdfc)

SUMMARY: AddressSanitizer: heap-use-after-free html.c:481 in cmark_render_html_with_mem
Shadow bytes around the buggy address:
  0x602000000100: fa fa fd fd fa fa fd fa fa fa 06 fa fa fa fd fd
  0x602000000180: fa fa 00 06 fa fa 00 00 fa fa fd fd fa fa 00 01
  0x602000000200: fa fa 00 00 fa fa 00 00 fa fa fd fd fa fa 00 02
  0x602000000280: fa fa fd fd fa fa 00 01 fa fa fd fd fa fa 00 00
  0x602000000300: fa fa 00 00 fa fa 00 00 fa fa 00 00 fa fa 00 00
=>0x602000000380: fa fa fd[fd]fa fa fd fd fa fa fd fa fa fa fd fa
  0x602000000400: fa fa fd fd fa fa fd fa fa fa fd fa fa fa 02 fa
  0x602000000480: fa fa 01 fa fa fa fd fd fa fa fd fa fa fa fd fa
  0x602000000500: fa fa 01 fa fa fa fd fd fa fa fd fa fa fa fd fa
  0x602000000580: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x602000000600: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
Shadow byte legend (one shadow byte represents 8 application bytes):
  Addressable:           00
  Partially addressable: 01 02 03 04 05 06 07 
  Heap left redzone:       fa
  Freed heap region:       fd
  Stack left redzone:      f1
  Stack mid redzone:       f2
  Stack right redzone:     f3
  Stack after return:      f5
  Stack use after scope:   f8
  Global redzone:          f9
  Global init order:       f6
  Poisoned by user:        f7
  Container overflow:      fc
  Array cookie:            ac
  Intra object redzone:    bb
  ASan internal:           fe
  Left alloca redzone:     ca
  Right alloca redzone:    cb
==28585==ABORTING
```

**Determinism:** both orderings were run twice. `correct` produced byte-identical stdout and empty stderr both times (exit `0` both times). `buggy` crashed both times at the identical site — same `heap-use-after-free html.c:481 in cmark_render_html_with_mem` summary, same `cmark_parser_free blocks.c:164` in the freed-by trace, same exit code `134` — differing only in process id and ASLR-shifted addresses, which is expected and does not affect the finding. The capture recorded above (`==28585==`) is from a later third run made to inline the full trace. It reproduced the same crash site and the same freed-by trace as the first two. Scope note: the allocation stanza is recorded verbatim for that third run only — the first two runs were checked against the summary line, the freed-by frame, and the exit code, so this document does not evidence allocation-stanza determinism across all three.

**Conclusion:** the defect is real, and this project's ASan harness sees it. `cmark_render_html` (via `cmark_render_html_with_mem`, `html.c:481`) reads a heap block that was freed by `cmark_parser_free` → `cmark_llist_free` (`blocks.c:164` → `linked_list.c:36`); that same 16-byte block was originally allocated by `cmark_parser_attach_syntax_extension` → `cmark_llist_append` (`blocks.c:104` → `linked_list.c:7`) — i.e., it is a node of `parser->syntax_extensions`, exactly the list ADR-0005 identified as shared between `cmark_parser_free` and `cmark_render_html`. The `correct` ordering (render, then free) produced zero sanitizer output across the run. The `buggy` ordering (free, then render) reliably crashed with `heap-use-after-free` under ASan (exit code `134`) on every invocation. Both runs were confirmed, not assumed, to be exercising the ASan-instrumented `build/asan` libraries rather than stock Homebrew binaries. ADR-0005's teardown order (parser must outlive the render call) is therefore both necessary and — critically for every later memory-safety claim this project makes — detectable by the sanitizer harness this project actually uses.
