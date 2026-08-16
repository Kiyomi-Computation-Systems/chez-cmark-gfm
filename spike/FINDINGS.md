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
