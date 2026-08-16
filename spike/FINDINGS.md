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

**Actual observed output — the committed `spike/00-load.ss`, run exactly as the brief specifies, does NOT print the expected three lines. It fails immediately:**

```
Exception: invalid context for definition (define cmark-version (foreign-procedure "cmark_version" () int)) at line 7, char 3 of spike/00-load.ss
```

Exit code `255`. Confirmed deterministic across repeated runs (identical output both times).

**Root cause:** Scheme body syntax (`<body> -> <definition>* <expression>+`, applies to Chez's `let`) requires every internal `define` in a body to precede all expressions in that same body. The brief's script places `(load-shared-object lib)` — an expression — *before* the two `define`s inside the one `let` body, so Chez rejects the whole form at expansion time; `load-shared-object` never actually runs. This is a general Scheme rule, not specific to FFI or this library: a minimal 4-line repro with no cmark-gfm involved at all —
`(let ((x 1)) (display "hi") (define y 2) (display (+ x y)))` — fails with the identical `invalid context for definition` exception shape.

Per this task's instructions, `spike/00-load.ss` is committed **verbatim** from the brief despite this bug; it is intentionally not patched in place.

**Follow-up — is the underlying premise (Chez can load this library and call into it) actually true?** Yes. Simply moving the `define`s before `load-shared-object` also fails, but differently (`Exception in foreign-procedure: no entry for "cmark_version"`, exit `255`) — `foreign-procedure` resolves its C symbol eagerly at `define`-evaluation time, so the library must finish loading *before* the `define`s run, not after. Sequencing `load-shared-object` to completion in its own preceding form (so it is not one of the body forms sharing a `let` with the `define`s) satisfies both constraints and succeeds:

```scheme
(let ((lib (cadr (command-line))))
  (load-shared-object lib))

(define cmark-version
  (foreign-procedure "cmark_version" () int))
(define cmark-version-string
  (foreign-procedure "cmark_version_string" () string))

(let ((v (cmark-version)))
  (printf "cmark_version()        = ~d (0x~x)\n" v v)
  (printf "cmark_version_string() = ~a\n" (cmark-version-string))
  (printf "decoded                = ~d.~d.~d\n"
          (bitwise-arithmetic-shift-right v 16)
          (bitwise-and (bitwise-arithmetic-shift-right v 8) #xff)
          (bitwise-and v #xff)))
```

Actual output of this corrected incantation, run against the same library path above:

```
cmark_version()        = 1900557 (0x1D000D)
cmark_version_string() = 0.29.0.gfm.13
decoded                = 29.0.13
```

Exit code `0`.

**Decoded-version discrepancy (reported, not smoothed over):** the brief expected `decoded` to read `0.29.0`. The actual decode is `29.0.13`. `cmark_version_string()` correctly reports the full human-readable string `0.29.0.gfm.13`, confirming this is unambiguously the right library and build — but `cmark_version()`'s packed integer (`0x1D000D`) does not encode `0.29.0` under the brief's `(major<<16)|(minor<<8)|patch` formula; it decodes to major=29. Upstream cmark's packed `CMARK_VERSION` integer and the dotted/gfm version string appear to be two independently-maintained representations that have drifted apart at this release, rather than one being derived from the other. **Stage 1 should treat `cmark_version_string()` as the authoritative human-readable version and not assume the packed-integer decode matches it.**

**Conclusion:** the core premise holds — Chez *can* `load-shared-object` this library and call into it via `foreign-procedure` (proven above), so Stage 1 is unblocked on that front. But the exact script text given in the brief is not directly usable: Stage 1's real FFI-loading code must run `load-shared-object` to completion in a form that finishes *before* any `foreign-procedure` `define`, not interleaved with those `define`s in one body.
