# Design Spec: chez-cmark-gfm

- **Date:** 2026-08-16
- **Status:** Approved, pending implementation plan
- **Supersedes:** nothing. Refines `.plans/chez-cmark-gfm-sxml-project-plan.md`
- **Scope:** Version 1 of the Chez Scheme binding for `cmark-gfm`

This document records the design decisions taken on top of the project plan. Where
this spec and the project plan disagree, **this spec wins** — see §2.5 and §2.6,
which correct defects in the plan's memory-management sequence.

**Reference convention:** a bare `§` refers to a section of *this* document; a
reference to the project plan is always written `plan §N`.

---

## 1. Context

The project plan (`.plans/chez-cmark-gfm-sxml-project-plan.md`) specifies *what*
to build in considerable detail. It leaves open several *how* questions whose
answers shape everything downstream: how the native dependency is obtained, where
AST traversal executes, how memory claims are verified, and what ships when.

This spec settles those questions and corrects two memory-safety defects found in
the plan during design review.

### 1.1 Verified environment

| Component | Finding |
|---|---|
| Chez Scheme | 10.4.1, full (binary `chez`), machine type `tarm64osx` (threaded ARM64 macOS) |
| cmark-gfm | Not installed; Homebrew provides `0.29.0.gfm.13` |
| pkg-config | 2.5.1 |
| Akku | Not installed |

Chez being **threaded** is load-bearing: `cmark_gfm_core_extensions_ensure_registered`
mutates a global registry and must be serialized (§4.4).

---

## 2. Decisions

Each decision is recorded as an ADR under `.plans/decisions/`. This section is an
index: the ADRs carry the full context, the alternatives considered, and the
consequences. Where a decision corrects the project plan, the ADR quotes the evidence.

| ADR | Decision | Corrects |
|---|---|---|
| [0001](decisions/0001-hybrid-native-dependency-acquisition.md) | Hybrid native dependency acquisition | — |
| [0002](decisions/0002-traverse-ast-in-scheme.md) | Traverse the AST in Scheme behind a thin C shim | — |
| [0003](decisions/0003-linux-primary-memory-verification.md) | Linux-primary memory verification with in-process counters | — |
| [0004](decisions/0004-defer-windows-support.md) | Defer Windows support beyond v1 | `AGENTS.md` |
| [0005](decisions/0005-parser-outlives-rendering.md) | The parser outlives rendering | plan §8.2 |
| [0006](decisions/0006-liveness-flag-with-dynamic-wind.md) | Pair `dynamic-wind` with a liveness flag | plan §9.4 |
| [0007](decisions/0007-incremental-release-staging.md) | Ship incrementally from 0.1 | plan §16 |

### 2.1 Native dependency: hybrid acquisition

Normal builds discover a system `cmark-gfm` through `pkg-config`; a pinned
`vendor/cmark-gfm` submodule is the fallback, with cmark linked **statically** on that
path. See [ADR-0001](decisions/0001-hybrid-native-dependency-acquisition.md).

### 2.2 Traversal lives in Scheme; the shim stays thin

The C shim performs no tree traversal and holds no parsing or rendering logic —
roughly 150 lines covering version reporting, one-time extension registration,
option-bit construction, renderer buffer release, and debug counters. The most
effective memory-safety measure available is to write less C.

Consequence carried into this spec: the lifecycle logic memory safety depends on lives
in Scheme, so it must be verified in-process (§2.3). See
[ADR-0002](decisions/0002-traverse-ast-in-scheme.md).

### 2.3 Memory verification: Linux-primary, with in-process counters

Linux CI is the gate for all memory claims (Valgrind against stock Chez, plus
ASan/UBSan). macOS is best-effort, because **LeakSanitizer is not supported on
macOS/ARM64** — ASan there finds use-after-free and overflows but not leaks. Debug
allocation counters in the shim (§7.1) close that gap and add per-test granularity
neither tool provides. See
[ADR-0003](decisions/0003-linux-primary-memory-verification.md).

### 2.4 Windows deferred beyond v1

v1 targets Linux and macOS. The C stays strictly portable and path resolution sits
behind one abstraction, so Windows is additive later rather than a redesign. Resolves
the conflict between `AGENTS.md` and plan §2 in favor of the plan. See
[ADR-0004](decisions/0004-defer-windows-support.md).

### 2.5 CORRECTION: the parser must outlive rendering

Plan §8.2 frees the parser before rendering. But `cmark_parser_free` calls
`cmark_llist_free` on `parser->syntax_extensions`, which is exactly the list
`cmark_render_html` receives — so the render path is a use-after-free whenever
extensions are enabled, which is the default. The AST-copy path is unaffected, and
that asymmetry is what lets the defect survive review.

Teardown is therefore strict reverse of acquisition, freeing the parser last (§5.2).
Evidence and the rejected alternative are in
[ADR-0005](decisions/0005-parser-outlives-rendering.md).

### 2.6 CORRECTION: `dynamic-wind` alone is an insufficient guard

Plan §9.4 proposes `dynamic-wind`. It handles non-local escape correctly but fails on
re-entry: a continuation captured inside the scope and reinvoked after teardown
dereferences a freed document. Nulling pointers after freeing prevents double *frees*,
not use-after-free.

`dynamic-wind` is therefore paired with a liveness flag and checked accessors (§5.3),
converting the failure into a structured condition. See
[ADR-0006](decisions/0006-liveness-flag-with-dynamic-wind.md).

### 2.7 Release staging

| Release | Milestones | Contains |
|---|---|---|
| 0.1 | M0–M2 | Parse and render, safe defaults |
| 0.2 | M3–M4 | Scheme AST, security hardening |
| 0.3 | M5 | SXML adapter |
| 1.0 | M6 | Packaging, docs, release |

`markdown->html` alone already exercises every native ownership rule, so the hardest
memory problem is front-loaded into the smallest deliverable. See
[ADR-0007](decisions/0007-incremental-release-staging.md).

## 3. Goals and non-goals

Inherited unchanged from plan §2 and §3. This spec adds no features and removes
none. It constrains *how* the plan is realized.

---

## 4. Architecture

### 4.1 Layers

```
(cmark gfm)          convenience API ......... layer 3
(cmark gfm render)   direct renderers ........ layer 3
(cmark gfm ast)      Scheme node records ..... layer 3   no native pointers
(cmark gfm options)  immutable options ....... layer 3
(cmark gfm sxml)     optional adapter ........ layer 4   consumes layer 3 only
──────────────────────────────────────────────────────────────────────────────
(cmark gfm private native)      FFI decls .... layer 2   pointers live here
(cmark gfm private scope)       lifecycle .... layer 2   sole owner of teardown
(cmark gfm private convert)     AST copy ..... layer 2
(cmark gfm private conditions)  conditions ... layer 2
──────────────────────────────────────────────────────────────────────────────
cmark-gfm-shim.c                             . layer 1   no tree logic
```

**Boundary rule.** Only layer 2 ever holds a native pointer. Layer 3 has none to
expose, so layer 4 cannot reach one even by mistake.

### 4.2 Package structure

Follows plan §5, with additions:

```
src/cmark/gfm/private/
├── native.sls        FFI declarations
├── scope.sls         native-doc record, call-with-native-document
├── convert.sls       native tree -> Scheme AST
├── conditions.sls    structured condition types
└── config.sls        GENERATED at build time; gitignored
```

### 4.3 Public API

Unchanged from plan §6. Options are symbol-named and immutable; numeric cmark
constants never appear above layer 2.

### 4.4 Initialization

`cmark_gfm_core_extensions_ensure_registered` runs exactly once, behind a mutex,
during controlled library initialization. Version compatibility (§6.3) is checked at
the same point, and failure there prevents any parsing from being attempted.

---

## 5. Memory ownership model

### 5.1 One owner, one record

```scheme
(define-record-type native-doc          ; layer 2, never exported
  (fields (mutable parser)              ; uptr, or #f once released
          (mutable root)                ; uptr, or #f once released
          (mutable alive?)              ; #f after teardown
          option-bits                   ; for the renderer
          extensions))                  ; parser-owned llist, borrowed
```

`extensions` is explicitly **borrowed** from the parser and is never freed by the
binding — see §2.5 for why its lifetime is bound to the parser's.

### 5.2 Acquisition and teardown

Teardown is strict reverse of acquisition. The parser is freed last.

| # | Acquire | Release (reverse order) |
|---|---|---|
| 1 | validate: no embedded NUL, bytes ≤ `max-input-bytes` | — |
| 2 | encode Scheme string → UTF-8 bytevector | (garbage collected) |
| 3 | `cmark_parser_new(opts)` | **R3** `cmark_parser_free` |
| 4 | attach extensions (registry-owned, never freed) | — |
| 5 | `cmark_parser_feed` + `cmark_parser_finish` → root | **R2** `cmark_node_free(root)` |
| — | *(render path only)* renderer → `char *` | **R1** `chez_cmark_free_buffer` |

Release runs **R1 → R2 → R3**: renderer buffer first, parser last.

Renderer buffers are released by the shim, not libc `free`, because cmark allocates
them through its own `cmark_mem` allocator. The buffer is copied into a Scheme
string before release.

### 5.3 The guard

```scheme
(define (call-with-native-document markdown options proc)
  (let ((h (acquire-native-document! markdown options)))
    (dynamic-wind
      (lambda ()
        (unless (native-doc-alive? h)             ; re-entry after teardown
          (raise (make-dead-document-condition))))
      (lambda () (proc h))
      (lambda () (release-native-document! h))))) ; idempotent
```

`release-native-document!` clears `alive?` **first**, then frees and nulls each
field. A second call is a no-op, so cleanup triggered during cleanup — the partial
failure case — cannot double-free.

Every native access goes through a checked accessor; layer 2 never reads a record
field directly:

```scheme
(define (doc-root h)
  (if (native-doc-alive? h)
      (native-doc-root h)
      (raise (make-dead-document-condition))))
```

### 5.4 Borrowed strings

These accessors return borrowed pointers, and several return `NULL` for
incompatible node types — distinct from the empty string:

```
cmark_node_get_type_string   cmark_node_get_literal   cmark_node_get_fence_info
cmark_node_get_url           cmark_node_get_title
```

They are declared in the FFI as returning raw `uptr`, and layer 2 converts
explicitly:

```
uptr → zero? → #f          ; NULL, distinct from ""
     → else  → strlen, copy to bytevector, utf8->string
```

**Rationale.** Chez may well copy and decode correctly for a `string` return type,
which would make this verbose for no reason. That behavior is *unverified*, and the
design does not depend on unverified marshalling. Stage 0 resolves it (§9.1); if the
simpler form is proven safe, §5.4 may be simplified.

A borrowed pointer is never stored in a Scheme AST record, closure, promise, global
table, SXML tree, or condition object.

### 5.5 Limits

- `max-input-bytes` — checked on **bytevector length**, before `cmark_parser_new`.
  It is the only pre-allocation defense.
- `max-nodes`, `max-depth` — enforced in Scheme during conversion, threaded as
  counters through the walk. Exceeding them raises inside the scope body, where the
  after-thunk still frees everything.

Documented limitation: these reduce risk but do not constitute a hard real-time or
constant-memory sandbox (plan §10.6).

### 5.6 UTF-8 and NUL

Embedded NUL is rejected at the public Scheme boundary, because downstream accessors
return NUL-terminated C strings and would silently truncate. `CMARK_OPT_VALIDATE_UTF8`
is on by default; invalid input is replaced with U+FFFD by cmark, and this is
documented rather than hidden. Byte lengths are passed to cmark, never Scheme
character counts.

---

## 6. Build, packaging, and loading

### 6.1 Acquisition paths

```
make build
  │
  ├─ pkg-config --exists libcmark-gfm ?
  │    ├─ yes → link shim dynamically against system cmark-gfm
  │    └─ no  → build vendor/cmark-gfm (pinned submodule) with CMake as
  │              SHARED libraries, link the shim against them with an
  │              explicit -Wl,-rpath to each
  │
  └─ emit build/lib/libchezcmarkgfm.{dylib,so}
     emit src/cmark/gfm/private/config.sls   (generated, gitignored)
```

Both paths link dynamically. **This revises an earlier decision to link the vendored
copy statically**, which was found to be unimplementable during Stage 1.

Static linking cannot work here, for a structural reason worth recording. cmark-gfm
builds its static archives with `CMAKE_C_VISIBILITY_PRESET hidden` and
`CMARK_GFM_STATIC_DEFINE`, so every cmark symbol is hidden in whatever links it. But
§4.1 puts traversal in Scheme, which means Scheme resolves cmark's entry points
directly at runtime through `foreign-procedure`. A statically-linked shim exports
none of them, and the bindings fail to resolve. The two decisions — static vendoring
and Scheme-side traversal — were incompatible as specified; Scheme-side traversal is
the load-bearing one, so linking gave way.

The dynamic-loader concern in plan §10.7 is still met: the rpath is an explicit
absolute path recorded at build time, not a system-path search, and the working
directory is never consulted. Both behaviours are documented per plan §14.

### 6.2 Runtime loading

`config.sls` is generated at build time and carries the shim's absolute path.
Loading uses `(load-shared-object <absolute-path>)` — never a bare-name `dlopen`, no
dependence on `LD_LIBRARY_PATH`, and no CWD in the search order. This satisfies plan
§10.7 structurally rather than by convention.

A single override, `CHEZ_CMARK_GFM_SHIM`, is honored — config in the environment is
12-factor, and the environment is the user's own trust domain. It is validated: must
be absolute, must exist, must be a regular file. Anything else fails closed with a
structured condition; there is no fallback search. A shared-library path is never
accepted from Markdown input.

### 6.3 Version compatibility

The shim records the `CMARK_GFM_VERSION` it was compiled against; initialization
compares it against `cmark_version()` reported at runtime. Mismatch outside the
supported range raises `&cmark-version-incompatible` carrying both values. v1
supports `0.29.0.gfm.x`, pinned in CI to `0.29.0.gfm.13` so differential tests
against the CLI are meaningful.

### 6.4 C hardening

```
-std=c99 -Wall -Wextra -Werror -Wconversion -Wshadow -Wpointer-arith
```

CI additionally runs GCC `-fanalyzer` and `clang-tidy`. At roughly 150 lines of
shim, false-positive volume is manageable.

### 6.5 Makefile

| Target | Does |
|---|---|
| `build` | shim + `config.sls`, via pkg-config or vendored |
| `dev` | build, then a REPL with the library preloaded |
| `test` | Scheme suite; **non-zero exit on any failure** |
| `test-memory` | Valgrind (Linux) / ASan preload (macOS) |
| `vendor` | init and build the pinned submodule explicitly |
| `clean` | build artifacts and generated `config.sls` |
| `prod` | optimized, warnings-as-errors, no debug symbols, counters compiled out |

### 6.6 Packaging

`Akku.manifest` declares the Scheme libraries; `Akku.lock` is committed. The core
package does not depend on `wak-htmlprag` or any site generator.

**Documented install caveat:** Akku distributes Scheme source and cannot build the
native shim, so installation requires `make build` after `akku install`. This must
appear in the README, not be discovered at install time.

---

## 7. Testing strategy

Framework: SRFI-64 via Akku, behind a thin runner reporting per-suite counts and
exiting non-zero on failure.

### 7.1 Debug allocation counters

A free is not observable from Scheme, and process-level tools cannot attribute a
leak to a test. Under `-DCHEZ_CMARK_DEBUG_COUNTERS` the shim tracks parsers, roots,
and renderer buffers created versus freed, queryable from Scheme:

```scheme
(test-assert "html render leaks nothing"
  (let ((before (native-live-counts)))
    (markdown->html "# hi\n| a |\n|---|\n" (default-cmark-options))
    (equal? (native-live-counts) before)))    ; per-test, not per-process
```

This gives per-test granularity, behaves identically on both platforms, closes the
macOS LSan gap from §2.3, and compiles to nothing under `make prod`. Valgrind and
ASan remain the outer gate for what counters cannot see: overflows, use-after-free,
and leaks originating inside cmark.

### 7.2 Failure paths

Plan §13.5 requires verified cleanup after every structured condition, which means
provoking failures that do not occur naturally.

- **Scheme-side, no special build.** Set `max-nodes: 1` or `max-depth: 1` and parse
  a larger document. Conversion raises mid-walk inside the scope body. Assert both
  the condition and that counters returned to baseline, proving the after-thunk ran
  on the exception path.
- **Shim-side, debug build only.** A hook forcing `cmark_parser_new` to return
  `NULL`, or extension attachment to fail, exercising partial-acquisition cleanup
  where some resources exist and others do not. This is the path most likely to
  double-free.

### 7.3 Proving the AST is Scheme-owned

```
parse to AST inside scope → scope exits, everything freed → (collect) →
  fully traverse the AST, comparing every literal against expected
```

Under Valgrind, any node retaining a borrowed `char *` reads freed memory and is
caught. Forcing a collection first shakes out anything the collector would relocate.
Without the post-free traversal, this test would pass whether or not the AST copied
its strings — precisely the "test that passes whether the code is right or wrong"
that `AGENTS.md` prohibits.

### 7.4 Mutation discipline

Each memory rule must have a mutation that breaks a specific named test:

| Mutation | Test that must fail |
|---|---|
| Free parser before render (the plan §8.2 order) | table/strikethrough render under ASan |
| Drop the `alive?` check in `doc-root` | re-entry test |
| Make `release!` non-idempotent | cleanup-after-partial-failure test |
| Return a borrowed pointer instead of copying | post-free AST traversal under Valgrind |
| Skip the embedded-NUL check | truncation test on `"a\x0;b"` |
| Use libc `free` on a renderer buffer | counter balance / ASan allocator mismatch |

If a mutation breaks nothing, that rule is untested.

### 7.5 Differential and conformance

Differential tests invoke the pinned `cmark-gfm` CLI and compare HTML, CommonMark,
plaintext, and XML across the full supported option matrix — the check that our
option-bit construction and extension attachment do not alter native semantics.
CommonMark and GFM specification examples serve as the conformance corpus; the
binding does not retest cmark's parser, only its own transparency.

### 7.6 Security corpus

Plan §13.4's inputs are asserted at **three** distinct layers, since passing at one
proves nothing about the others:

1. native HTML rendering is safe by default;
2. the Scheme AST *preserves* hostile content — a test that fails if parsing quietly
   sanitizes;
3. SXML conversion escapes or rejects it under default policy.

---

## 8. Stages

| Stage | Milestone | Exit criterion |
|---|---|---|
| 0 | M0 | Spike prints expected node types, clean under Valgrind; the intentionally-buggy §2.5 ordering **is caught** by ASan; FFI marshalling question answered |
| 1 | M1 | Every owned allocation has a passing success *and* failure test; each §7.4 mutation breaks its named test |
| 2 | M2 → **0.1** | Output matches the pinned CLI across the option matrix; counters balance; Valgrind clean |
| 3 | M3 | Post-free AST traversal passes under Valgrind |
| 4 | M4 → **0.2** | Every documented safe default has a regression test that fails when the default is flipped |
| 5 | M5 → **0.3** | Representative documents produce structurally correct SXML; hostile corpus escaped or rejected |
| 6 | M6 → **1.0** | A clean machine installs and exercises every public API from the documentation alone |

### 8.1 Stage 0 detail

Stage 0 is deliberately throwaway code whose purpose is retiring unknowns before
they can be designed around wrongly:

- Install cmark-gfm; pin `vendor/cmark-gfm` at the matching tag.
- Resolve how Chez 10.4.1 marshals `const char *` as `string`, `u8*`, and `uptr` —
  whether it copies, whether it decodes UTF-8, and its behavior on `NULL`.
- Write the buggy ordering from §2.5 and confirm ASan reports the use-after-free.
  This validates the finding *and* proves the sanitizer harness catches anything at
  all; a tool reporting nothing is indistinguishable from a tool that is not running.
- Attach all five extensions; parse a document containing a heading, table,
  strikethrough, autolink, and task list; traverse and free.

---

## 9. Open questions

### 9.1 Chez FFI string marshalling (resolved in Stage 0)

If Chez's `string` foreign return type is shown to copy, decode UTF-8, and handle
`NULL` safely, §5.4's explicit `uptr` conversion may be simplified. The design
deliberately does not assume this.

## 10. References

- `.plans/chez-cmark-gfm-sxml-project-plan.md` — the project plan this refines
- [cmark-gfm public API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm.h)
- [cmark-gfm extension API](https://github.com/github/cmark-gfm/blob/master/src/cmark-gfm-extension_api.h)
- [cmark-gfm core-extension accessors](https://github.com/github/cmark-gfm/blob/master/extensions/cmark-gfm-core-extensions.h)
- [CommonMark specification](https://spec.commonmark.org/spec)
- [GitHub Flavored Markdown specification](https://github.github.com/gfm/)
