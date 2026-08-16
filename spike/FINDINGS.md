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

- [ ] Q1: How does Chez marshal `const char *`? (Task 3)
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
