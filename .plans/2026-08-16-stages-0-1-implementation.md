# chez-cmark-gfm Stages 0–1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire every unknown that could invalidate the design (Stage 0), then build the C shim and the native-memory lifecycle foundation that all later stages sit on (Stage 1).

**Architecture:** A deliberately thin C shim handles only what C must — version reporting, option-bit construction from real header macros, renderer-buffer release, and debug allocation counters. All traversal and lifecycle sequencing lives in Scheme. Native pointers exist only inside `(cmark gfm private ...)` libraries, guarded by a handle record with a liveness flag so that use-after-free becomes a Scheme condition rather than undefined behaviour.

**Tech Stack:** Chez Scheme 10.4.1, C99, cmark-gfm 0.29.0.gfm.13, CMake, pkg-config, Akku (`chez-srfi` for SRFI-64), Valgrind (Linux) / AddressSanitizer (macOS).

**Source documents:**
- Design spec: `.plans/2026-08-16-chez-cmark-gfm-design.md`
- ADRs: `.plans/decisions/0001` … `0007`
- Project plan: `.plans/chez-cmark-gfm-sxml-project-plan.md`

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Chez Scheme** 10.4.1 or later. The local binary is `chez` (**not** `scheme`); `petite` cannot compile and must not be used for tests.
- **cmark-gfm** version range `0.29.0.gfm.x`; pinned to `0.29.0.gfm.13`.
- **C standard:** C99. Compile flags, warnings fatal:
  `-std=c99 -Wall -Wextra -Werror -Wconversion -Wshadow -Wpointer-arith`
- **No POSIX-only APIs in C.** Windows is deferred (ADR-0004) but must not be precluded. Anything needing threads or paths belongs in Scheme, not the shim.
- **Numeric cmark constants never appear in Scheme.** The shim reads them from the installed headers and exposes them through functions. This makes the binding immune to upstream renumbering.
- **Only layer 2** (`cmark gfm private *`) may hold a native pointer. Layers 3 and 4 must have none to expose.
- **Teardown order is fixed** (ADR-0005): renderer buffer → root → **parser last**. Never free the parser before rendering.
- **Every native access is checked** (ADR-0006): `dynamic-wind` for escape, plus a liveness flag for re-entry. Layer 2 never reads a handle field directly.
- **Commits:** Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`). Run tests before every commit.
- **`make test` must exit non-zero** on any failure.
- Borrowed C strings are copied immediately. A borrowed pointer is never stored in a record, closure, promise, global table, or condition object.

---

## File Structure

| Path | Responsibility |
|---|---|
| `spike/` | **Stage 0 only. Throwaway.** Deleted at the end of Stage 1. |
| `spike/00-load.ss` | Proves `load-shared-object` and version reporting |
| `spike/01-strings.ss` | Answers the string-marshalling question (spec §9.1) |
| `spike/02-parse.ss` | Full parse, all five extensions, traverse, free |
| `spike/03-uaf.ss` | Deliberately wrong teardown order; must be caught |
| `spike/FINDINGS.md` | Recorded answers; the gate between Stage 0 and Stage 1 |
| `src/cmark-gfm-shim.h` | Shim public declarations |
| `src/cmark-gfm-shim.c` | Shim implementation — no tree logic, ~150 lines |
| `src/cmark/gfm/private/config.sls` | **Generated** at build time; gitignored |
| `src/cmark/gfm/private/conditions.sls` | Structured condition types |
| `src/cmark/gfm/private/native.sls` | FFI declarations + C-string copying |
| `src/cmark/gfm/private/scope.sls` | `native-doc` record, acquire/release, checked accessors |
| `tests/test-conditions.sps` | Condition-type suite; exits non-zero on failure |
| `tests/test-native.sps` | FFI-layer suite |
| `tests/test-lifecycle.sps` | Lifecycle, liveness, and counter-balance tests |
| `Makefile` | `build`, `dev`, `test`, `test-memory`, `vendor`, `clean`, `prod` |
| `Akku.manifest` | Declares `chez-srfi` |

---

# Part A — Stage 0: Compatibility Spike

Everything in `spike/` is **throwaway**. Its only product is `spike/FINDINGS.md`. Do not carry spike code into Stage 1; carry the answers.

---

### Task 1: Install and pin the native toolchain

**Files:**
- Create: `.gitmodules` (via `git submodule add`)
- Create: `spike/FINDINGS.md`

**Interfaces:**
- Produces: a working `cmark-gfm` install; a pinned `vendor/cmark-gfm` submodule at tag `0.29.0.gfm.13`; `spike/FINDINGS.md` with a "Toolchain" section.

- [ ] **Step 1: Install the native library and the package manager**

```bash
brew install cmark-gfm akku
```

- [ ] **Step 2: Verify the installed version matches the pin**

```bash
cmark-gfm --version
pkg-config --modversion libcmark-gfm
```

Expected: both report `0.29.0.gfm.13`. If they differ, stop and record the discrepancy in `FINDINGS.md` before continuing — the whole differential-test strategy depends on this pin.

- [ ] **Step 3: Confirm the extensions library has no pkg-config file**

```bash
pkg-config --exists libcmark-gfm && echo "core: found"
pkg-config --exists libcmark-gfm-extensions && echo "ext: found" || echo "ext: NO .pc (expected)"
pkg-config --variable=libdir libcmark-gfm
```

Expected: `core: found`, `ext: NO .pc (expected)`, and a libdir path. This is not a broken install — upstream ships a `.pc` for the core library only, so the extensions library must be linked manually with `-lcmark-gfm-extensions` using the core's libdir. The Makefile in Task 7 depends on this.

- [ ] **Step 4: Add the pinned submodule**

```bash
git submodule add https://github.com/github/cmark-gfm.git vendor/cmark-gfm
git -C vendor/cmark-gfm checkout 0.29.0.gfm.13
git add .gitmodules vendor/cmark-gfm
```

- [ ] **Step 5: Record findings**

Create `spike/FINDINGS.md`:

```markdown
# Stage 0 Findings

## Toolchain

| Item | Value |
|---|---|
| Chez Scheme | (output of `chez --version`) |
| Machine type | (output of `(machine-type)`) |
| cmark-gfm CLI | (output of `cmark-gfm --version`) |
| pkg-config libcmark-gfm | (output of `pkg-config --modversion libcmark-gfm`) |
| libcmark-gfm-extensions .pc | absent — link manually via core libdir |
| Vendored submodule | vendor/cmark-gfm @ 0.29.0.gfm.13 |

## Open questions

- [ ] Q1: How does Chez marshal `const char *`? (Task 3)
- [ ] Q2: Is the ADR-0005 use-after-free detectable by our tooling? (Task 5)
```

- [ ] **Step 6: Commit**

```bash
git add .gitmodules vendor/cmark-gfm spike/FINDINGS.md
git commit -m "chore: pin cmark-gfm 0.29.0.gfm.13 and record toolchain findings"
```

---

### Task 2: Prove shared-object loading and version reporting

**Files:**
- Create: `spike/00-load.ss`

**Interfaces:**
- Consumes: installed cmark-gfm from Task 1.
- Produces: a confirmed absolute library path and the exact `load-shared-object` incantation, recorded in `FINDINGS.md`.

- [ ] **Step 1: Find the absolute library path**

```bash
echo "$(pkg-config --variable=libdir libcmark-gfm)/libcmark-gfm.dylib"
```

On Linux the extension is `.so`. Note the value; the script below takes it as an argument so nothing is hard-coded.

- [ ] **Step 2: Write the spike script**

Create `spike/00-load.ss`:

```scheme
;; Stage 0 spike: prove load-shared-object and version reporting.
;; Usage: chez --script spike/00-load.ss /abs/path/to/libcmark-gfm.dylib

(let ((lib (cadr (command-line))))
  (load-shared-object lib)

  (define cmark-version
    (foreign-procedure "cmark_version" () int))
  (define cmark-version-string
    (foreign-procedure "cmark_version_string" () string))

  (let ((v (cmark-version)))
    (printf "cmark_version()        = ~d (0x~x)\n" v v)
    (printf "cmark_version_string() = ~a\n" (cmark-version-string))
    ;; Version is encoded (major << 16) | (minor << 8) | patch.
    (printf "decoded                = ~d.~d.~d\n"
            (bitwise-arithmetic-shift-right v 16)
            (bitwise-and (bitwise-arithmetic-shift-right v 8) #xff)
            (bitwise-and v #xff))))
```

- [ ] **Step 3: Run it**

```bash
chez --script spike/00-load.ss "$(pkg-config --variable=libdir libcmark-gfm)/libcmark-gfm.dylib"
```

Expected: three lines printed, with `decoded` reading `0.29.0`. A failure here means the library path is wrong, not that the design is wrong.

- [ ] **Step 4: Record and commit**

Append the working path and the decoded version to `FINDINGS.md` under a `## Q0: loading` heading, then:

```bash
git add spike/00-load.ss spike/FINDINGS.md
git commit -m "chore(spike): prove shared-object loading and version reporting"
```

---

### Task 3: Resolve the Chez string-marshalling question

This task answers spec §9.1, the one open question in the design. It is the highest-value task in Stage 0.

**Files:**
- Create: `spike/01-strings.ss`

**Interfaces:**
- Produces: a definitive answer recorded in `FINDINGS.md` on whether Chez's `string` foreign return type copies, decodes UTF-8, and survives `NULL`. Task 11 consumes this.

- [ ] **Step 1: Write the probe**

Create `spike/01-strings.ss`:

```scheme
;; Stage 0 spike: determine how Chez marshals `const char *` returns.
;; Three questions:
;;   (a) does the `string` return type COPY, or alias native memory?
;;   (b) does it decode UTF-8 correctly?
;;   (c) what happens when the C function returns NULL?
;; Usage: chez --script spike/01-strings.ss /abs/path/to/libcmark-gfm.dylib

(let ((lib (cadr (command-line))))
  (load-shared-object lib)

  ;; --- helpers -------------------------------------------------------
  ;; Manual, unambiguous copy from a raw address. This is the fallback
  ;; the design specifies (spec 5.4) if `string` proves unsafe.
  (define (c-string->string addr)
    (if (zero? addr)
        #f
        (let scan ((len 0))
          (if (zero? (foreign-ref 'unsigned-8 addr len))
              (let ((bv (make-bytevector len)))
                (let copy ((i 0))
                  (if (= i len)
                      (utf8->string bv)
                      (begin
                        (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 addr i))
                        (copy (+ i 1))))))
              (scan (+ len 1))))))

  ;; --- bindings ------------------------------------------------------
  (define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
  (define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
  (define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
  (define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
  (define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
  (define first-child   (foreign-procedure "cmark_node_first_child" (uptr) uptr))

  ;; The SAME accessor bound two ways, so the results can be compared.
  (define literal-as-string (foreign-procedure "cmark_node_get_literal" (uptr) string))
  (define literal-as-uptr   (foreign-procedure "cmark_node_get_literal" (uptr) uptr))
  ;; get_literal returns NULL for a paragraph node -- that is question (c).
  (define type-as-uptr      (foreign-procedure "cmark_node_get_type_string" (uptr) uptr))

  ;; --- probe ---------------------------------------------------------
  ;; Non-ASCII on purpose: em-dash and a CJK character exercise UTF-8.
  (let* ((md   (string->utf8 "Hello \x2014;world \x4e16;\x754c;\n"))
         (p    (parser-new 0))
         (_    (parser-feed p md (bytevector-length md)))
         (root (parser-finish p))
         (para (first-child root))
         (text (first-child para)))

    (printf "--- (b) UTF-8 decoding ---\n")
    (let ((via-string (literal-as-string text))
          (via-uptr   (c-string->string (literal-as-uptr text))))
      (printf "via `string` type : ~s\n" via-string)
      (printf "via manual copy   : ~s\n" via-uptr)
      (printf "identical?        : ~a\n" (equal? via-string via-uptr)))

    (printf "\n--- (c) NULL handling ---\n")
    ;; A paragraph node has no literal; the accessor returns NULL.
    (printf "manual copy of NULL : ~s\n" (c-string->string (literal-as-uptr para)))
    (printf "`string` type on NULL: ")
    (flush-output-port)
    (printf "~s\n"
            (guard (e (#t (list 'raised (condition/report-string e))))
              (literal-as-string para)))

    (printf "\n--- (a) copy vs alias ---\n")
    ;; Capture BEFORE the tree is freed, then read AFTER. If `string`
    ;; copied, the value survives intact. If it aliased, this is a
    ;; use-after-free and the value is garbage or the process crashes.
    (let ((captured (literal-as-string text))
          (node-type (c-string->string (type-as-uptr text))))
      (printf "node type          : ~s\n" node-type)
      (parser-free p)
      (node-free root)
      (collect)
      (printf "after free         : ~s\n" captured)
      (printf "still correct?     : ~a\n"
              (equal? captured "Hello \x2014;world \x4e16;\x754c;")))))
```

- [ ] **Step 2: Run it**

```bash
chez --script spike/01-strings.ss "$(pkg-config --variable=libdir libcmark-gfm)/libcmark-gfm.dylib"
```

- [ ] **Step 3: Run it again under a memory tool**

On Linux:

```bash
valgrind --error-exitcode=9 --leak-check=full \
  chez --script spike/01-strings.ss /usr/lib/x86_64-linux-gnu/libcmark-gfm.so
```

On macOS, skip this step and note in `FINDINGS.md` that section (a) was verified by value comparison only. Preloading ASan is not useful here: ASan checks only loads it instrumented, and stock cmark is not instrumented, so an aliasing bug would go unreported. Do not claim (a) is proven on macOS.

- [ ] **Step 4: Record the verdict**

Append to `FINDINGS.md`:

```markdown
## Q1: Chez `const char *` marshalling — ANSWERED

| Question | Answer |
|---|---|
| (a) Does `string` copy? | yes / no — evidence: value after free was … |
| (b) UTF-8 decoded correctly? | yes / no |
| (c) Behaviour on NULL | returns #f / raises / crashes |

**Decision for Task 11:** use `string` directly / use `uptr` + manual copy.

Spec 5.4 specifies the conservative `uptr` path by default. Only choose
`string` if ALL THREE answers are unambiguously safe AND (a) was verified
under Valgrind, not merely by value comparison.
```

- [ ] **Step 5: Commit**

```bash
git add spike/01-strings.ss spike/FINDINGS.md
git commit -m "chore(spike): answer Chez const char* marshalling question"
```

---

### Task 4: Full parse with all five extensions

**Files:**
- Create: `spike/02-parse.ss`

**Interfaces:**
- Consumes: loading approach from Task 2.
- Produces: confirmation that all five GFM extensions attach and that a document containing every one of them traverses and frees cleanly.

- [ ] **Step 1: Write the spike**

Create `spike/02-parse.ss`:

```scheme
;; Stage 0 spike: attach all five GFM extensions, parse, traverse, free.
;; Usage: chez --script spike/02-parse.ss /abs/core.dylib /abs/extensions.dylib

(let ((core (cadr (command-line)))
      (exts (caddr (command-line))))
  (load-shared-object core)
  (load-shared-object exts)

  (define ensure-registered
    (foreign-procedure "cmark_gfm_core_extensions_ensure_registered" () void))
  (define find-extension
    (foreign-procedure "cmark_find_syntax_extension" (string) uptr))
  (define attach-extension
    (foreign-procedure "cmark_parser_attach_syntax_extension" (uptr uptr) int))
  (define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
  (define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
  (define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
  (define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
  (define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
  (define first-child   (foreign-procedure "cmark_node_first_child" (uptr) uptr))
  (define node-next     (foreign-procedure "cmark_node_next" (uptr) uptr))
  (define type-string   (foreign-procedure "cmark_node_get_type_string" (uptr) uptr))

  (define (c-string->string addr)
    (if (zero? addr)
        #f
        (let scan ((len 0))
          (if (zero? (foreign-ref 'unsigned-8 addr len))
              (let ((bv (make-bytevector len)))
                (let copy ((i 0))
                  (if (= i len)
                      (utf8->string bv)
                      (begin
                        (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 addr i))
                        (copy (+ i 1))))))
              (scan (+ len 1))))))

  (define extension-names '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

  ;; A document exercising every extension at once.
  (define markdown
    (string-append
     "# Heading\n\n"
     "Visit https://example.com for ~~old~~ new info.\n\n"
     "| Fruit | Qty |\n|---|---:|\n| apple | 3 |\n\n"
     "- [x] done\n- [ ] pending\n\n"
     "<script>alert(1)</script>\n"))

  (ensure-registered)

  (let ((p (parser-new 0)))
    ;; Attach every extension, failing loudly if any is missing.
    (for-each
     (lambda (name)
       (let ((ext (find-extension name)))
         (when (zero? ext)
           (error 'spike "extension not found" name))
         (let ((rc (attach-extension p ext)))
           (printf "attach ~a -> rc=~d\n" name rc))))
     extension-names)

    (let ((bytes (string->utf8 markdown)))
      (parser-feed p bytes (bytevector-length bytes)))

    (let ((root (parser-finish p)))
      ;; Depth-first walk printing the type of every node.
      (let walk ((node (first-child root)) (depth 0))
        (unless (zero? node)
          (printf "~a~a\n"
                  (make-string (* 2 depth) #\space)
                  (c-string->string (type-string node)))
          (walk (first-child node) (+ depth 1))
          (walk (node-next node) depth)))

      ;; Teardown per ADR-0005: root first, parser LAST.
      (node-free root)
      (parser-free p)
      (printf "\nOK: parsed, traversed, freed\n"))))
```

- [ ] **Step 2: Run it**

```bash
LIBDIR="$(pkg-config --variable=libdir libcmark-gfm)"
chez --script spike/02-parse.ss \
  "$LIBDIR/libcmark-gfm.dylib" "$LIBDIR/libcmark-gfm-extensions.dylib"
```

Expected: five `attach … rc=0` lines, an indented node-type tree containing `heading`, `table`, `table_row`, `table_cell`, `strikethrough`, `link` (from the autolink), `item`, and `html_block`, then `OK: parsed, traversed, freed`.

- [ ] **Step 3: Record the observed node-type names**

The exact strings returned by `cmark_node_get_type_string` are the dispatch keys for the Stage 3 converter, so copy the printed tree verbatim into `FINDINGS.md` under `## Q3: node type strings`. Do not paraphrase them.

- [ ] **Step 4: Commit**

```bash
git add spike/02-parse.ss spike/FINDINGS.md
git commit -m "chore(spike): parse with all five GFM extensions and record node types"
```

---

### Task 5: Prove the ADR-0005 use-after-free is detectable

This task validates two things at once: that the defect found during design review is real, and that our tooling can actually see it. A sanitizer that reports nothing is indistinguishable from one that is not running.

**Files:**
- Create: `spike/03-uaf.ss`

**Interfaces:**
- Consumes: the vendored submodule from Task 1.
- Produces: a recorded sanitizer report proving the buggy ordering is caught, and a clean run proving the correct ordering is not.

- [ ] **Step 1: Build the vendored cmark-gfm with AddressSanitizer**

Stock cmark is not instrumented, so preloading ASan cannot catch a read inside `cmark_render_html`. The library under test must itself be built with ASan.

```bash
cmake -S vendor/cmark-gfm -B build/asan \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-fsanitize=address -fno-omit-frame-pointer -g" \
  -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address" \
  -DCMARK_TESTS=OFF -DCMARK_STATIC=OFF
cmake --build build/asan -j
find build/asan -name 'libcmark-gfm*.dylib' -o -name 'libcmark-gfm*.so'
```

- [ ] **Step 2: Write the spike with both orderings**

Create `spike/03-uaf.ss`:

```scheme
;; Stage 0 spike: demonstrate the ADR-0005 use-after-free.
;;
;; cmark_parser_free() calls cmark_llist_free() on parser->syntax_extensions,
;; which is the SAME list cmark_render_html() receives. Freeing the parser
;; before rendering therefore hands the renderer a dangling list.
;;
;; Usage: chez --script spike/03-uaf.ss <core.dylib> <ext.dylib> [buggy|correct]

(let ((core (cadr (command-line)))
      (exts (caddr (command-line)))
      (mode (string->symbol (cadddr (command-line)))))
  (load-shared-object core)
  (load-shared-object exts)

  (define ensure-registered
    (foreign-procedure "cmark_gfm_core_extensions_ensure_registered" () void))
  (define find-extension
    (foreign-procedure "cmark_find_syntax_extension" (string) uptr))
  (define attach-extension
    (foreign-procedure "cmark_parser_attach_syntax_extension" (uptr uptr) int))
  (define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
  (define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
  (define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
  (define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
  (define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
  (define get-extensions
    (foreign-procedure "cmark_parser_get_syntax_extensions" (uptr) uptr))
  (define render-html
    (foreign-procedure "cmark_render_html" (uptr int uptr) uptr))
  (define c-free (foreign-procedure "free" (uptr) void))

  (define (c-string->string addr)
    (if (zero? addr)
        #f
        (let scan ((len 0))
          (if (zero? (foreign-ref 'unsigned-8 addr len))
              (let ((bv (make-bytevector len)))
                (let copy ((i 0))
                  (if (= i len)
                      (utf8->string bv)
                      (begin
                        (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 addr i))
                        (copy (+ i 1))))))
              (scan (+ len 1))))))

  ;; A table forces the renderer to consult the extension list.
  (define markdown "| a | b |\n|---|---|\n| 1 | 2 |\n")

  (ensure-registered)

  (let ((p (parser-new 0)))
    (let ((ext (find-extension "table")))
      (when (zero? ext) (error 'spike "table extension missing"))
      (attach-extension p ext))

    (let ((bytes (string->utf8 markdown)))
      (parser-feed p bytes (bytevector-length bytes)))

    (let* ((root (parser-finish p))
           (ext-list (get-extensions p)))
      (case mode
        ((buggy)
         ;; WRONG: this is plan 8.2's ordering. ext-list now dangles.
         (parser-free p)
         (let ((buf (render-html root 0 ext-list)))
           (printf "~a" (c-string->string buf))
           (c-free buf))
         (node-free root))
        ((correct)
         ;; RIGHT: parser outlives the render (ADR-0005).
         (let ((buf (render-html root 0 ext-list)))
           (printf "~a" (c-string->string buf))
           (c-free buf))
         (node-free root)
         (parser-free p))
        (else (error 'spike "mode must be buggy or correct")))
      (printf "done: ~a\n" mode))))
```

- [ ] **Step 3: Run the correct ordering under ASan — expect clean**

```bash
ASAN_LIB=$(dirname $(xcrun --find clang))/../lib/clang/*/lib/darwin/libclang_rt.asan_osx_dynamic.dylib
DYLD_INSERT_LIBRARIES=$ASAN_LIB ASAN_OPTIONS=detect_leaks=0 \
  chez --script spike/03-uaf.ss \
    build/asan/src/libcmark-gfm.dylib \
    build/asan/extensions/libcmark-gfm-extensions.dylib correct
```

Expected: an HTML table, then `done: correct`, with no sanitizer output.

- [ ] **Step 4: Run the buggy ordering under ASan — expect a report**

```bash
DYLD_INSERT_LIBRARIES=$ASAN_LIB ASAN_OPTIONS=detect_leaks=0 \
  chez --script spike/03-uaf.ss \
    build/asan/src/libcmark-gfm.dylib \
    build/asan/extensions/libcmark-gfm-extensions.dylib buggy
```

Expected: `ERROR: AddressSanitizer: heap-use-after-free`, with `cmark_llist` visible in the freed-block allocation trace.

**If this run comes out clean, do not proceed.** It means the harness is not detecting anything, and every later memory claim would be worthless. Diagnose the harness before continuing: confirm `DYLD_INSERT_LIBRARIES` survived (SIP strips it for system binaries — `chez` from Homebrew is not one, but a wrapper script would be), and confirm the ASan-built libraries are the ones actually loaded.

On Linux, use Valgrind instead of ASan and stock libraries are sufficient, since Valgrind instruments everything at runtime:

```bash
valgrind --error-exitcode=9 chez --script spike/03-uaf.ss \
  /usr/lib/x86_64-linux-gnu/libcmark-gfm.so \
  /usr/lib/x86_64-linux-gnu/libcmark-gfm-extensions.so buggy
```

- [ ] **Step 5: Record both outcomes**

Append the first 15 lines of the ASan report to `FINDINGS.md` under `## Q2: ADR-0005 use-after-free — CONFIRMED`, alongside the clean `correct` run. This is the evidence that justifies the fixed teardown order.

- [ ] **Step 6: Commit**

```bash
git add spike/03-uaf.ss spike/FINDINGS.md
git commit -m "test(spike): confirm ADR-0005 use-after-free is detected by ASan"
```

---

## Stage 0 Exit Gate

Do not begin Part B until all of these hold:

- [ ] `cmark-gfm` reports `0.29.0.gfm.13` from both the CLI and pkg-config.
- [ ] `vendor/cmark-gfm` is pinned at the matching tag.
- [ ] Q1 is answered in `FINDINGS.md`, with an explicit decision for Task 11.
- [ ] All five extensions attach with `rc=0`, and the observed node-type strings are recorded verbatim.
- [ ] The buggy ordering produces a `heap-use-after-free` report; the correct ordering is clean.

If Q1 came back showing `string` is unsafe in any respect, Task 11 uses the `uptr` path as written — no change needed. If Q1 showed `string` is safe on all three counts *and* was verified under Valgrind, Task 11 may be simplified, but record that deviation in `FINDINGS.md` first.

---

# Part B — Stage 1: Shim and Lifecycle Foundation

---

### Task 6: Project scaffolding and the Makefile

**Files:**
- Create: `Makefile`
- Create: `Akku.manifest`
- Modify: `.gitignore` (append generated `config.sls`)

**Interfaces:**
- Produces: `make build` emitting `build/lib/libchezcmarkgfm.<ext>` and `src/cmark/gfm/private/config.sls`; `make test` exiting non-zero on failure.

- [ ] **Step 1: Declare the Akku manifest**

Create `Akku.manifest`:

```scheme
#!r6rs ; -*- scheme -*-
(import (akku format manifest))

(akku-package ("chez-cmark-gfm" "0.1.0-alpha")
  (synopsis "CommonMark and GitHub Flavored Markdown for Chez Scheme")
  (authors "Kiyomi Computation Systems LLC")
  (license "BSD-3-Clause")
  (depends ("chez-srfi" "^0.0.0-akku.280")))
```

- [ ] **Step 2: Install dependencies and verify SRFI-64 resolves**

```bash
akku install
```

```bash
printf '(import (rnrs) (srfi :64))\n(test-begin "probe")\n(test-equal 1 1)\n(test-end)\n' > /tmp/probe.sps
CHEZSCHEMELIBDIRS=".akku/lib" chez --program /tmp/probe.sps
```

Expected: SRFI-64 output showing 1 pass, 0 fail. If the import fails, run `akku search srfi` and correct the dependency name before continuing.

- [ ] **Step 3: Write the Makefile**

Create `Makefile`. Note the two acquisition paths and that the extensions library is linked manually, because upstream ships no `.pc` for it (confirmed in Task 1 Step 3).

```make
# chez-cmark-gfm

CHEZ        ?= chez
CC          ?= cc
UNAME_S     := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
  SHLIB_EXT := dylib
  SHLIB_LDFLAGS := -dynamiclib
else
  SHLIB_EXT := so
  SHLIB_LDFLAGS := -shared -fPIC
endif

BUILD_DIR   := build
LIB_DIR     := $(BUILD_DIR)/lib
SHIM        := $(LIB_DIR)/libchezcmarkgfm.$(SHLIB_EXT)
CONFIG_SLS  := src/cmark/gfm/private/config.sls
VENDOR_DIR  := vendor/cmark-gfm
VENDOR_BUILD:= $(BUILD_DIR)/vendor

CFLAGS_BASE := -std=c99 -Wall -Wextra -Werror -Wconversion -Wshadow -Wpointer-arith -fPIC
CFLAGS_DEV  := $(CFLAGS_BASE) -g -O0 -DCHEZ_CMARK_DEBUG_COUNTERS
CFLAGS_PROD := $(CFLAGS_BASE) -O2

# --- native dependency discovery (ADR-0001) --------------------------
HAVE_PKG := $(shell pkg-config --exists libcmark-gfm && echo yes || echo no)

ifeq ($(HAVE_PKG),yes)
  CMARK_CFLAGS := $(shell pkg-config --cflags libcmark-gfm)
  CMARK_LIBDIR := $(shell pkg-config --variable=libdir libcmark-gfm)
  # Upstream ships no .pc for the extensions library: link it manually.
  CMARK_LIBS   := $(shell pkg-config --libs libcmark-gfm) \
                  -L$(CMARK_LIBDIR) -lcmark-gfm-extensions
else
  CMARK_CFLAGS := -I$(VENDOR_BUILD)/src -I$(VENDOR_DIR)/src \
                  -I$(VENDOR_DIR)/extensions
  CMARK_LIBS   := $(VENDOR_BUILD)/src/libcmark-gfm_static.a \
                  $(VENDOR_BUILD)/extensions/libcmark-gfm-extensions_static.a
endif

CHEZ_LIBDIRS := src:.akku/lib
TESTS        := $(wildcard tests/test-*.sps)

.PHONY: all build dev test test-memory vendor clean prod deps-info

all: build

deps-info:
	@echo "cmark-gfm source : $(if $(filter yes,$(HAVE_PKG)),pkg-config,vendored)"
	@echo "shim             : $(SHIM)"

build: $(SHIM) $(CONFIG_SLS)

$(LIB_DIR):
	mkdir -p $(LIB_DIR)

ifeq ($(HAVE_PKG),no)
$(SHIM): vendor
endif

$(SHIM): src/cmark-gfm-shim.c src/cmark-gfm-shim.h | $(LIB_DIR)
	$(CC) $(CFLAGS_DEV) $(CMARK_CFLAGS) $(SHLIB_LDFLAGS) \
	      -o $@ src/cmark-gfm-shim.c $(CMARK_LIBS)

# config.sls carries the shim's ABSOLUTE path so the loader never searches.
$(CONFIG_SLS): $(SHIM)
	@printf '%s\n' \
	  '#!r6rs' \
	  ';; GENERATED by make -- do not edit, do not commit.' \
	  '(library (cmark gfm private config)' \
	  '  (export shim-path cmark-supported-version-range)' \
	  '  (import (rnrs))' \
	  '  (define shim-path "$(abspath $(SHIM))")' \
	  '  (define cmark-supported-version-range (quote (#x001d0000 . #x001dffff))))' \
	  > $@

vendor:
	git submodule update --init --recursive
	cmake -S $(VENDOR_DIR) -B $(VENDOR_BUILD) \
	  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	  -DCMARK_TESTS=OFF -DCMARK_SHARED=OFF -DCMARK_STATIC=ON
	cmake --build $(VENDOR_BUILD) -j

dev: build
	CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ)

# Each suite sets its own exit status. Keep going after a failure so one
# broken suite cannot hide the others, then fail the target if any failed.
test: build
	@fail=0; \
	for t in $(TESTS); do \
	  echo "=== $$t ==="; \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ) --program $$t || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "ALL SUITES PASSED"; \
	else echo "SUITE FAILED"; fi; \
	exit $$fail

test-memory: build
ifeq ($(UNAME_S),Linux)
	@for t in $(TESTS); do \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) valgrind --error-exitcode=9 \
	    --leak-check=full --show-leak-kinds=definite \
	    $(CHEZ) --program $$t || exit 1; \
	done
else
	@echo "macOS: ASan preload only; LeakSanitizer is unsupported on arm64."
	@echo "Leak claims must come from Linux CI (ADR-0003)."
	CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	  DYLD_INSERT_LIBRARIES=$$(dirname $$(xcrun --find clang))/../lib/clang/*/lib/darwin/libclang_rt.asan_osx_dynamic.dylib \
	  ASAN_OPTIONS=detect_leaks=0 \
	  sh -c 'for t in $(TESTS); do $(CHEZ) --program $$t || exit 1; done'
endif

prod: clean
	mkdir -p $(LIB_DIR)
	$(CC) $(CFLAGS_PROD) $(CMARK_CFLAGS) $(SHLIB_LDFLAGS) \
	      -o $(SHIM) src/cmark-gfm-shim.c $(CMARK_LIBS)
	$(MAKE) $(CONFIG_SLS)

clean:
	rm -rf $(BUILD_DIR) $(CONFIG_SLS)
```

- [ ] **Step 4: Ignore the generated config**

Append to `.gitignore`:

```
# Generated by make build
src/cmark/gfm/private/config.sls
.akku/
```

- [ ] **Step 5: Verify discovery works**

```bash
make deps-info
```

Expected: `cmark-gfm source : pkg-config` and a shim path. The shim does not exist yet; that is Task 7.

- [ ] **Step 6: Commit**

```bash
git add Makefile Akku.manifest Akku.lock .gitignore
git commit -m "build: add Makefile with dual cmark-gfm acquisition and Akku manifest"
```

---

### Task 7: The C shim

**Files:**
- Create: `src/cmark-gfm-shim.h`
- Create: `src/cmark-gfm-shim.c`

**Interfaces:**
- Produces, consumed by Task 9 (`native.sls`):
  - `int  chez_cmark_shim_compiled_version(void)`
  - `int  chez_cmark_runtime_version(void)`
  - `int  chez_cmark_option_bits(int validate_utf8, int sourcepos, int hardbreaks, int nobreaks, int smart, int unsafe_html)`
  - `void chez_cmark_free_buffer(char *buffer)`
  - `long chez_cmark_live_parsers(void)` / `_roots(void)` / `_buffers(void)`
  - `void chez_cmark_count_parser_new(void)` / `_parser_free(void)` / `_root_new(void)` / `_root_free(void)` / `_buffer_new(void)`

- [ ] **Step 1: Write the header**

Create `src/cmark-gfm-shim.h`:

```c
/* chez-cmark-gfm compatibility shim.
 *
 * Deliberately thin (ADR-0002): no tree traversal, no parsing, no rendering.
 * Its jobs are version reporting, translating named options into cmark's
 * numeric bits so those constants never appear in Scheme, releasing renderer
 * buffers with cmark's own allocator, and counting live allocations in
 * debug builds.
 */
#ifndef CHEZ_CMARK_GFM_SHIM_H
#define CHEZ_CMARK_GFM_SHIM_H

/* Version the shim was COMPILED against, from the installed header. */
int chez_cmark_shim_compiled_version(void);

/* Version reported by the library loaded at RUNTIME. */
int chez_cmark_runtime_version(void);

/* Build cmark's option mask from booleans. Each argument is 0 or non-zero.
 * Keeping this in C means the numeric constants are read from the real
 * headers and cannot drift from what Scheme believes them to be. */
int chez_cmark_option_bits(int validate_utf8,
                           int sourcepos,
                           int hardbreaks,
                           int nobreaks,
                           int smart,
                           int unsafe_html);

/* Release a buffer returned by a cmark renderer, using the same allocator
 * cmark used to create it. Never call libc free() on such a buffer. */
void chez_cmark_free_buffer(char *buffer);

/* Debug allocation counters. Compiled to no-ops unless
 * CHEZ_CMARK_DEBUG_COUNTERS is defined; the query functions then
 * always return 0. Single-threaded test use only. */
void chez_cmark_count_parser_new(void);
void chez_cmark_count_parser_free(void);
void chez_cmark_count_root_new(void);
void chez_cmark_count_root_free(void);
void chez_cmark_count_buffer_new(void);
void chez_cmark_count_buffer_free(void);

long chez_cmark_live_parsers(void);
long chez_cmark_live_roots(void);
long chez_cmark_live_buffers(void);

#endif /* CHEZ_CMARK_GFM_SHIM_H */
```

- [ ] **Step 2: Write the implementation**

Create `src/cmark-gfm-shim.c`:

```c
#include "cmark-gfm-shim.h"

#include <cmark-gfm.h>
#include <cmark-gfm_version.h>

int chez_cmark_shim_compiled_version(void) {
  return CMARK_GFM_VERSION;
}

int chez_cmark_runtime_version(void) {
  return cmark_version();
}

int chez_cmark_option_bits(int validate_utf8,
                           int sourcepos,
                           int hardbreaks,
                           int nobreaks,
                           int smart,
                           int unsafe_html) {
  int bits = CMARK_OPT_DEFAULT;
  if (validate_utf8) bits |= CMARK_OPT_VALIDATE_UTF8;
  if (sourcepos)     bits |= CMARK_OPT_SOURCEPOS;
  if (hardbreaks)    bits |= CMARK_OPT_HARDBREAKS;
  if (nobreaks)      bits |= CMARK_OPT_NOBREAKS;
  if (smart)         bits |= CMARK_OPT_SMART;
  if (unsafe_html)   bits |= CMARK_OPT_UNSAFE;
  return bits;
}

void chez_cmark_free_buffer(char *buffer) {
  if (buffer != NULL) {
    cmark_get_default_mem_allocator()->free(buffer);
  }
}

#ifdef CHEZ_CMARK_DEBUG_COUNTERS

static long live_parsers = 0;
static long live_roots   = 0;
static long live_buffers = 0;

void chez_cmark_count_parser_new(void)  { live_parsers += 1; }
void chez_cmark_count_parser_free(void) { live_parsers -= 1; }
void chez_cmark_count_root_new(void)    { live_roots   += 1; }
void chez_cmark_count_root_free(void)   { live_roots   -= 1; }
void chez_cmark_count_buffer_new(void)  { live_buffers += 1; }
void chez_cmark_count_buffer_free(void) { live_buffers -= 1; }

long chez_cmark_live_parsers(void) { return live_parsers; }
long chez_cmark_live_roots(void)   { return live_roots; }
long chez_cmark_live_buffers(void) { return live_buffers; }

#else

void chez_cmark_count_parser_new(void)  { }
void chez_cmark_count_parser_free(void) { }
void chez_cmark_count_root_new(void)    { }
void chez_cmark_count_root_free(void)   { }
void chez_cmark_count_buffer_new(void)  { }
void chez_cmark_count_buffer_free(void) { }

long chez_cmark_live_parsers(void) { return 0; }
long chez_cmark_live_roots(void)   { return 0; }
long chez_cmark_live_buffers(void) { return 0; }

#endif /* CHEZ_CMARK_DEBUG_COUNTERS */
```

- [ ] **Step 3: Build it and confirm warnings are clean**

```bash
make build
```

Expected: the shim compiles with no warnings (they are errors), and `build/lib/libchezcmarkgfm.dylib` plus `src/cmark/gfm/private/config.sls` exist.

- [ ] **Step 4: Sanity-check the shim from Chez**

```bash
cat > /tmp/shim-check.ss <<'EOF'
(load-shared-object "build/lib/libchezcmarkgfm.dylib")
(define compiled (foreign-procedure "chez_cmark_shim_compiled_version" () int))
(define runtime  (foreign-procedure "chez_cmark_runtime_version" () int))
(define optbits  (foreign-procedure "chez_cmark_option_bits" (int int int int int int) int))
(printf "compiled = 0x~x\nruntime  = 0x~x\n" (compiled) (runtime))
(printf "defaults = 0x~x\n" (optbits 1 1 0 0 0 0))
EOF
chez --script /tmp/shim-check.ss
```

Expected: `compiled` and `runtime` are equal and begin `0x1d` (0.29.x), and `defaults` is a non-zero mask.

- [ ] **Step 5: Commit**

```bash
git add src/cmark-gfm-shim.c src/cmark-gfm-shim.h
git commit -m "feat: add cmark-gfm compatibility shim with option bits and counters"
```

---

### Task 8: Structured conditions

**Files:**
- Create: `src/cmark/gfm/private/conditions.sls`
- Create: `tests/test-conditions.sps`

**Interfaces:**
- Produces, consumed by Tasks 9 and 10:
  `&cmark-error` (base), `make-cmark-error`, `cmark-error?`;
  `&cmark-version-incompatible` with fields `compiled` and `runtime`, constructor `make-cmark-version-incompatible`, accessors `cmark-version-incompatible-compiled` / `-runtime`;
  `&cmark-dead-document` / `make-cmark-dead-document` / `cmark-dead-document?`;
  `&cmark-extension-unavailable` with field `name`, accessor `cmark-extension-unavailable-name`;
  `&cmark-invalid-input` with field `reason`, accessor `cmark-invalid-input-reason`;
  `&cmark-shim-unavailable` with field `path`, accessor `cmark-shim-unavailable-path`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-conditions.sps`:

```scheme
#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) exit)
        (cmark gfm private conditions))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "conditions")

;; Each condition must be catchable both as itself and as the base type,
;; so callers can choose their granularity.
(test-assert "version-incompatible is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-equal "version-incompatible carries the compiled version"
  #x001d0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-compiled e)))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-equal "version-incompatible carries the runtime version"
  #x001e0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-runtime e)))
    (raise (make-cmark-version-incompatible #x001d0000 #x001e0000))))

(test-assert "dead-document is distinguishable from version-incompatible"
  (guard (e ((cmark-version-incompatible? e) #f)
            ((cmark-dead-document? e) #t)
            (#t #f))
    (raise (make-cmark-dead-document))))

(test-equal "extension-unavailable names the extension"
  "table"
  (guard (e ((cmark-extension-unavailable? e)
             (cmark-extension-unavailable-name e)))
    (raise (make-cmark-extension-unavailable "table"))))

(test-equal "invalid-input carries a reason"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (raise (make-cmark-invalid-input 'embedded-nul))))

(test-equal "shim-unavailable carries the attempted path"
  "/nope/libchezcmarkgfm.dylib"
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-path e)))
    (raise (make-cmark-shim-unavailable "/nope/libchezcmarkgfm.dylib"))))

(test-end "conditions")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
CHEZSCHEMELIBDIRS="src:.akku/lib" chez --program tests/test-conditions.sps
```

Expected: FAIL — the library `(cmark gfm private conditions)` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `src/cmark/gfm/private/conditions.sls`:

```scheme
#!r6rs
;;; Structured conditions for chez-cmark-gfm.
;;;
;;; Every failure the binding can produce is one of these, so callers never
;;; see a raw foreign-interface error. All of them derive from &cmark-error,
;;; which lets a caller catch the whole family or discriminate precisely.
(library (cmark gfm private conditions)
  (export &cmark-error make-cmark-error cmark-error?

          &cmark-version-incompatible make-cmark-version-incompatible
          cmark-version-incompatible?
          cmark-version-incompatible-compiled
          cmark-version-incompatible-runtime

          &cmark-dead-document make-cmark-dead-document cmark-dead-document?

          &cmark-extension-unavailable make-cmark-extension-unavailable
          cmark-extension-unavailable? cmark-extension-unavailable-name

          &cmark-invalid-input make-cmark-invalid-input
          cmark-invalid-input? cmark-invalid-input-reason

          &cmark-shim-unavailable make-cmark-shim-unavailable
          cmark-shim-unavailable? cmark-shim-unavailable-path)
  (import (rnrs))

  (define-condition-type &cmark-error &error
    make-cmark-error cmark-error?)

  ;; Raised at initialisation when the shim's compile-time version and the
  ;; runtime library disagree beyond the supported range. Fails closed.
  (define-condition-type &cmark-version-incompatible &cmark-error
    make-cmark-version-incompatible cmark-version-incompatible?
    (compiled cmark-version-incompatible-compiled)
    (runtime  cmark-version-incompatible-runtime))

  ;; Raised when a native handle is touched after its scope was torn down.
  ;; This is what converts a use-after-free into an ordinary error (ADR-0006).
  (define-condition-type &cmark-dead-document &cmark-error
    make-cmark-dead-document cmark-dead-document?)

  (define-condition-type &cmark-extension-unavailable &cmark-error
    make-cmark-extension-unavailable cmark-extension-unavailable?
    (name cmark-extension-unavailable-name))

  ;; reason is a symbol: 'embedded-nul, 'too-large, 'not-a-string.
  (define-condition-type &cmark-invalid-input &cmark-error
    make-cmark-invalid-input cmark-invalid-input?
    (reason cmark-invalid-input-reason))

  (define-condition-type &cmark-shim-unavailable &cmark-error
    make-cmark-shim-unavailable cmark-shim-unavailable?
    (path cmark-shim-unavailable-path)))
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
CHEZSCHEMELIBDIRS="src:.akku/lib" chez --program tests/test-conditions.sps
```

Expected: 7 passes, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/cmark/gfm/private/conditions.sls tests/test-conditions.sps
git commit -m "feat: add structured condition types"
```

---

### Task 9: The FFI layer

**Files:**
- Create: `src/cmark/gfm/private/native.sls`
- Create: `tests/test-native.sps`

**Interfaces:**
- Consumes: `config.sls` (generated in Task 6), conditions from Task 8, shim symbols from Task 7.
- Produces, consumed by Task 10:
  `(ensure-native-loaded!)` — idempotent, mutexed, raises on version mismatch;
  `(c-string->string addr)` → string or `#f` for NULL;
  `(option-bits validate-utf8? sourcepos? hardbreaks? nobreaks? smart? unsafe-html?)` → exact integer;
  `(live-counts)` → `(parsers roots buffers)`;
  raw bindings `parser-new`, `parser-feed`, `parser-finish`, `parser-free`,
  `node-free`, `find-extension`, `attach-extension`,
  `parser-get-syntax-extensions`, `render-html`, `free-buffer`.
  (`ensure-extensions-registered` stays internal — callers go through
  `ensure-native-loaded!`.)

- [ ] **Step 1: Write the failing test**

Create `tests/test-native.sps`:

```scheme
#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) exit)
        (cmark gfm private native))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(test-begin "native")

(test-assert "loading is idempotent"
  (begin (ensure-native-loaded!) (ensure-native-loaded!) #t))

;; NULL must be distinguishable from the empty string. Several cmark
;; accessors return NULL for nodes of an incompatible type, and conflating
;; that with "" would silently invent data.
(test-equal "c-string->string maps NULL to #f" #f (c-string->string 0))

(test-assert "option-bits sets a bit for validate-utf8"
  (> (option-bits #t #f #f #f #f #f) 0))

(test-assert "option-bits with everything off is zero"
  (= 0 (option-bits #f #f #f #f #f #f)))

(test-assert "option-bits composes distinct flags"
  (let ((a (option-bits #t #f #f #f #f #f))
        (b (option-bits #f #t #f #f #f #f)))
    (= (option-bits #t #t #f #f #f #f) (bitwise-ior a b))))

;; Seeded deliberately: assert a NON-empty starting shape so the test
;; cannot pass by accident if live-counts returned something degenerate.
(test-equal "live-counts reports three counters"
  3
  (length (live-counts)))

(test-assert "live-counts starts balanced at zero"
  (for-all zero? (live-counts)))

(test-end "native")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to verify it fails**

```bash
make build && CHEZSCHEMELIBDIRS="src:.akku/lib" chez --program tests/test-native.sps
```

Expected: FAIL — `(cmark gfm private native)` does not exist.

- [ ] **Step 3: Write the implementation**

Create `src/cmark/gfm/private/native.sls`:

```scheme
#!r6rs
;;; Private FFI layer. This is the ONLY library permitted to hold a native
;;; pointer (design spec 4.1). Nothing here is a supported public API.
;;;
;;; ORDERING NOTE -- this is the subtle part of the file. Chez resolves a
;;; foreign entry point when the `foreign-procedure` expression is
;;; EVALUATED, not when the resulting procedure is first called. Every such
;;; definition below therefore has to run after the shared object is loaded.
;;; Library bodies evaluate their definitions in order, so the load is
;;; written as a definition placed ahead of them. Moving it later fails at
;;; IMPORT time with an unresolved-entry error, not at first use.
(library (cmark gfm private native)
  (export ensure-native-loaded!
          c-string->string
          option-bits
          live-counts
          count-parser-new! count-parser-free!
          count-root-new!   count-root-free!
          count-buffer-new! count-buffer-free!
          parser-new parser-feed parser-finish parser-free
          node-free find-extension attach-extension
          parser-get-syntax-extensions render-html free-buffer)
  (import (rnrs)
          (only (chezscheme)
                load-shared-object foreign-procedure foreign-ref
                make-mutex with-mutex getenv file-exists?)
          (cmark gfm private config)
          (cmark gfm private conditions))

  ;; --- shim resolution --------------------------------------------------
  ;; The override exists because config-in-the-environment is 12-factor. It
  ;; is validated, never searched: an absolute path to an existing regular
  ;; file, or nothing at all. There is no fallback search and the working
  ;; directory is never consulted (design spec 6.2).
  (define shim-file
    (let ((override (getenv "CHEZ_CMARK_GFM_SHIM")))
      (cond
        ((not override)
         (if (file-exists? shim-path)
             shim-path
             (raise (make-cmark-shim-unavailable shim-path))))
        ((and (> (string-length override) 0)
              (char=? (string-ref override 0) #\/)
              (file-exists? override))
         override)
        (else (raise (make-cmark-shim-unavailable override))))))

  ;; A definition, not a bare expression, so it is legal at this position in
  ;; an R6RS library body while still running before every binding below.
  (define shim-loaded (load-shared-object shim-file))

  ;; --- shim bindings ----------------------------------------------------
  (define shim-compiled-version
    (foreign-procedure "chez_cmark_shim_compiled_version" () int))
  (define shim-runtime-version
    (foreign-procedure "chez_cmark_runtime_version" () int))
  (define raw-option-bits
    (foreign-procedure "chez_cmark_option_bits" (int int int int int int) int))
  (define free-buffer
    (foreign-procedure "chez_cmark_free_buffer" (uptr) void))

  (define count-parser-new!
    (foreign-procedure "chez_cmark_count_parser_new" () void))
  (define count-parser-free!
    (foreign-procedure "chez_cmark_count_parser_free" () void))
  (define count-root-new!
    (foreign-procedure "chez_cmark_count_root_new" () void))
  (define count-root-free!
    (foreign-procedure "chez_cmark_count_root_free" () void))
  (define count-buffer-new!
    (foreign-procedure "chez_cmark_count_buffer_new" () void))
  (define count-buffer-free!
    (foreign-procedure "chez_cmark_count_buffer_free" () void))

  (define live-parsers (foreign-procedure "chez_cmark_live_parsers" () long))
  (define live-roots   (foreign-procedure "chez_cmark_live_roots" () long))
  (define live-buffers (foreign-procedure "chez_cmark_live_buffers" () long))

  ;; --- cmark bindings ---------------------------------------------------
  ;; Accessors returning `const char *` are declared `uptr`, not `string`,
  ;; and copied explicitly by c-string->string below. See design spec 5.4:
  ;; the conservative form does not depend on marshalling behaviour, and it
  ;; keeps NULL distinguishable from "".
  (define ensure-extensions-registered
    (foreign-procedure "cmark_gfm_core_extensions_ensure_registered" () void))
  (define parser-new    (foreign-procedure "cmark_parser_new" (int) uptr))
  (define parser-feed   (foreign-procedure "cmark_parser_feed" (uptr u8* size_t) void))
  (define parser-finish (foreign-procedure "cmark_parser_finish" (uptr) uptr))
  (define parser-free   (foreign-procedure "cmark_parser_free" (uptr) void))
  (define node-free     (foreign-procedure "cmark_node_free" (uptr) void))
  (define find-extension
    (foreign-procedure "cmark_find_syntax_extension" (string) uptr))
  (define attach-extension
    (foreign-procedure "cmark_parser_attach_syntax_extension" (uptr uptr) int))
  (define parser-get-syntax-extensions
    (foreign-procedure "cmark_parser_get_syntax_extensions" (uptr) uptr))
  (define render-html
    (foreign-procedure "cmark_render_html" (uptr int uptr) uptr))

  ;; --- one-time version check and extension registration ----------------
  ;; Chez here is threaded (tarm64osx) and
  ;; cmark_gfm_core_extensions_ensure_registered mutates a global registry,
  ;; so this is serialised. The mutex lives in Scheme rather than C
  ;; deliberately: a C mutex would need pthreads, and POSIX-only APIs are
  ;; barred so Windows stays reachable later (ADR-0004).
  (define init-mutex (make-mutex))
  (define initialized? #f)

  (define (version-supported? runtime)
    (let ((lo (car cmark-supported-version-range))
          (hi (cdr cmark-supported-version-range)))
      (and (>= runtime lo) (<= runtime hi))))

  ;; Idempotent. Fails closed on an out-of-range runtime version.
  (define (ensure-native-loaded!)
    (with-mutex init-mutex
      (unless initialized?
        (let ((compiled (shim-compiled-version))
              (runtime  (shim-runtime-version)))
          (unless (version-supported? runtime)
            (raise (make-cmark-version-incompatible compiled runtime))))
        (ensure-extensions-registered)
        (set! initialized? #t))))

  (define (live-counts)
    (list (live-parsers) (live-roots) (live-buffers)))

  (define (bool->int x) (if x 1 0))

  (define (option-bits validate-utf8? sourcepos? hardbreaks?
                       nobreaks? smart? unsafe-html?)
    (raw-option-bits (bool->int validate-utf8?)
                     (bool->int sourcepos?)
                     (bool->int hardbreaks?)
                     (bool->int nobreaks?)
                     (bool->int smart?)
                     (bool->int unsafe-html?)))

  ;; --- borrowed string copying ------------------------------------------
  ;; Copies immediately into Scheme-owned storage. NULL becomes #f, which is
  ;; deliberately distinct from "": several cmark accessors return NULL when
  ;; called on a node of an incompatible type, and conflating the two would
  ;; invent data that was never in the document.
  (define (c-string->string addr)
    (if (zero? addr)
        #f
        (let scan ((len 0))
          (if (zero? (foreign-ref (quote unsigned-8) addr len))
              (let ((bv (make-bytevector len)))
                (let copy ((i 0))
                  (if (= i len)
                      (utf8->string bv)
                      (begin
                        (bytevector-u8-set! bv i (foreign-ref (quote unsigned-8) addr i))
                        (copy (+ i 1))))))
              (scan (+ len 1)))))))
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
CHEZSCHEMELIBDIRS="src:.akku/lib" chez --program tests/test-native.sps
```

Expected: 7 passes, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/cmark/gfm/private/native.sls tests/test-native.sps
git commit -m "feat: add private FFI layer with validated shim loading"
```

---

### Task 10: The lifecycle scope

This is the task the whole stage exists for. It implements ADR-0005 and ADR-0006.

**Files:**
- Create: `src/cmark/gfm/private/scope.sls`
- Create: `tests/test-lifecycle.sps`

**Interfaces:**
- Consumes: everything from Tasks 8 and 9.
- Produces, consumed by Stage 2:
  `(call-with-native-document markdown options-bits extension-names proc)` — `proc` receives a `native-doc`;
  `(native-doc? x)`, `(doc-root h)`, `(doc-parser h)`, `(doc-extensions h)` — all checked;
  `(validate-markdown-input markdown max-bytes)` → bytevector, or raises `&cmark-invalid-input`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-lifecycle.sps`:

```scheme
#!r6rs
(import (rnrs)
        (srfi :64)
        (only (chezscheme) call/1cc collect exit)
        (cmark gfm private native)
        (cmark gfm private conditions)
        (cmark gfm private scope))

;; SRFI-64's default runner does not set a process exit code, so a failing
;; suite would still exit 0 and `make test` would report success. Hold the
;; runner so its fail count can drive the exit status.
(define runner (test-runner-simple))
(test-runner-current runner)

(ensure-native-loaded!)

(test-begin "lifecycle")

(define opts (option-bits #t #t #f #f #f #f))
(define gfm-extensions '("autolink" "strikethrough" "table" "tagfilter" "tasklist"))

;; --- input validation -------------------------------------------------
(test-equal "embedded NUL is rejected"
  'embedded-nul
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (validate-markdown-input "a\x0;b" 1000)))

(test-equal "oversized input is rejected"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (validate-markdown-input "hello world" 4)))

;; The limit is on BYTES, not characters. This 3-character string is 7
;; bytes in UTF-8, so a 5-byte limit must reject it. If the implementation
;; measured characters it would wrongly accept, so this test discriminates.
(test-equal "the limit counts bytes, not characters"
  'too-large
  (guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
    (validate-markdown-input "\x4e16;\x754c;!" 5)))

(test-assert "valid input returns a bytevector of the right length"
  (let ((bv (validate-markdown-input "hi" 100)))
    (and (bytevector? bv) (= 2 (bytevector-length bv)))))

;; --- balanced teardown ------------------------------------------------
(test-assert "counters balance after a successful scope"
  (let ((before (live-counts)))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (doc-root h)))
    (equal? before (live-counts))))

(test-assert "counters balance after the body raises"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "# hello\n" opts gfm-extensions
        (lambda (h) (error 'test "deliberate failure"))))
    (equal? before (live-counts))))

;; A continuation escape must still free. dynamic-wind's after-thunk is
;; what makes this work; without it this test leaks.
(test-assert "counters balance after a non-local escape"
  (let ((before (live-counts)))
    (call/1cc
     (lambda (k)
       (call-with-native-document "# hello\n" opts gfm-extensions
         (lambda (h) (k 'escaped)))))
    (equal? before (live-counts))))

;; --- liveness (ADR-0006) ---------------------------------------------
(test-assert "the handle is dead after the scope exits"
  (let ((escaped #f))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (guard (e ((cmark-dead-document? e) #t) (#t #f))
      (doc-root escaped))))

(test-assert "every checked accessor rejects a dead handle"
  (let ((escaped #f))
    (call-with-native-document "# hello\n" opts gfm-extensions
      (lambda (h) (set! escaped h) #t))
    (and (guard (e ((cmark-dead-document? e) #t) (#t #f)) (doc-root escaped))
         (guard (e ((cmark-dead-document? e) #t) (#t #f)) (doc-parser escaped))
         (guard (e ((cmark-dead-document? e) #t) (#t #f)) (doc-extensions escaped)))))

;; --- extension failure ------------------------------------------------
(test-equal "a missing extension is named in the condition"
  "no-such-extension"
  (guard (e ((cmark-extension-unavailable? e)
             (cmark-extension-unavailable-name e)))
    (call-with-native-document "x" opts '("no-such-extension")
      (lambda (h) h))))

(test-assert "counters balance after extension attachment fails"
  (let ((before (live-counts)))
    (guard (e (#t #t))
      (call-with-native-document "x" opts '("no-such-extension")
        (lambda (h) h)))
    (equal? before (live-counts))))

;; --- repetition -------------------------------------------------------
(test-assert "100 scopes leave the counters balanced"
  (let ((before (live-counts)))
    (let loop ((n 0))
      (when (< n 100)
        (call-with-native-document "# hi\n\n| a |\n|---|\n| 1 |\n"
                                   opts gfm-extensions
          (lambda (h) (doc-root h)))
        (loop (+ n 1))))
    (collect)
    (equal? before (live-counts))))

(test-end "lifecycle")

(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run to verify it fails**

```bash
CHEZSCHEMELIBDIRS="src:.akku/lib" chez --program tests/test-lifecycle.sps
```

Expected: FAIL — `(cmark gfm private scope)` does not exist.

- [ ] **Step 3: Write the implementation**

Create `src/cmark/gfm/private/scope.sls`:

```scheme
#!r6rs
;;; Native document lifecycle.
;;;
;;; This library is the SOLE owner of native teardown. Two invariants matter
;;; more than anything else here:
;;;
;;;   1. The parser outlives rendering (ADR-0005). cmark_parser_free calls
;;;      cmark_llist_free on parser->syntax_extensions, which is the same
;;;      list cmark_render_html receives -- so freeing the parser first
;;;      leaves the renderer holding a dangling list.
;;;
;;;   2. dynamic-wind alone is not enough (ADR-0006). It handles non-local
;;;      escape, but a continuation captured inside the body and reinvoked
;;;      after teardown would re-enter with freed pointers. The alive? flag
;;;      plus checked accessors turn that into a condition.
(library (cmark gfm private scope)
  (export call-with-native-document
          native-doc?
          doc-root doc-parser doc-extensions
          validate-markdown-input)
  (import (rnrs)
          (cmark gfm private native)
          (cmark gfm private conditions))

  (define-record-type native-doc
    (fields (mutable parser)
            (mutable root)
            (mutable alive?)
            (mutable extensions)))

  ;; --- checked accessors ----------------------------------------------
  ;; Nothing outside this library reads a field directly, and nothing
  ;; inside it reads one without going through here.
  (define (check-alive h)
    (unless (and (native-doc? h) (native-doc-alive? h))
      (raise (make-cmark-dead-document))))

  (define (doc-root h)       (check-alive h) (native-doc-root h))
  (define (doc-parser h)     (check-alive h) (native-doc-parser h))
  (define (doc-extensions h) (check-alive h) (native-doc-extensions h))

  ;; --- input validation ------------------------------------------------
  ;; Embedded NUL is rejected because downstream accessors return
  ;; NUL-terminated C strings and would silently truncate. The size limit is
  ;; measured in BYTES after encoding, never in characters: it is the only
  ;; pre-allocation defence, and cmark is fed a byte count.
  (define (validate-markdown-input markdown max-bytes)
    (unless (string? markdown)
      (raise (make-cmark-invalid-input 'not-a-string)))
    (let loop ((i 0))
      (cond
        ((= i (string-length markdown))
         (let ((bv (string->utf8 markdown)))
           (if (> (bytevector-length bv) max-bytes)
               (raise (make-cmark-invalid-input 'too-large))
               bv)))
        ((char=? #\nul (string-ref markdown i))
         (raise (make-cmark-invalid-input 'embedded-nul)))
        (else (loop (+ i 1))))))

  ;; --- acquisition ------------------------------------------------------
  ;; Ordering matters: the handle is created BEFORE extensions are attached,
  ;; so that if attachment fails the release path already has the parser to
  ;; free. Building the handle late would leak the parser on that path.
  (define (acquire! bytes option-bits extension-names)
    (ensure-native-loaded!)
    (let ((p (parser-new option-bits)))
      (when (zero? p)
        (raise (make-cmark-error)))
      (count-parser-new!)
      (let ((h (make-native-doc p 0 #t 0)))
        (for-each
         (lambda (name)
           (let ((ext (find-extension name)))
             (when (zero? ext)
               ;; Free before raising: the scope's after-thunk has not been
               ;; established yet, so cleanup is this procedure's duty.
               (release! h)
               (raise (make-cmark-extension-unavailable name)))
             (attach-extension p ext)))
         extension-names)
        (parser-feed p bytes (bytevector-length bytes))
        (let ((root (parser-finish p)))
          (when (zero? root)
            (release! h)
            (raise (make-cmark-error)))
          (count-root-new!)
          (native-doc-root-set! h root)
          ;; Borrowed from the parser; valid only while the parser lives.
          (native-doc-extensions-set! h (parser-get-syntax-extensions p))
          h))))

  ;; --- release ----------------------------------------------------------
  ;; Idempotent by construction: alive? is cleared FIRST, so a second call
  ;; (cleanup triggered during cleanup) does nothing. Each pointer is nulled
  ;; immediately after being freed.
  (define (release! h)
    (when (native-doc-alive? h)
      (native-doc-alive?-set! h #f)
      ;; Reverse acquisition order. The extension list is borrowed from the
      ;; parser and must NOT be freed here.
      (native-doc-extensions-set! h 0)
      (let ((root (native-doc-root h)))
        (unless (zero? root)
          (node-free root)
          (count-root-free!)
          (native-doc-root-set! h 0)))
      (let ((p (native-doc-parser h)))
        (unless (zero? p)
          ;; LAST, per ADR-0005.
          (parser-free p)
          (count-parser-free!)
          (native-doc-parser-set! h 0)))))

  ;; --- the scope --------------------------------------------------------
  (define (call-with-native-document markdown option-bits extension-names proc)
    (let* ((bytes (validate-markdown-input markdown (greatest-fixnum)))
           (h (acquire! bytes option-bits extension-names)))
      (dynamic-wind
        (lambda ()
          ;; Re-entry via a captured continuation lands here. The document is
          ;; gone and cannot be rebuilt, so refuse rather than proceed.
          (unless (native-doc-alive? h)
            (raise (make-cmark-dead-document))))
        (lambda () (proc h))
        (lambda () (release! h))))))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
CHEZSCHEMELIBDIRS="src:.akku/lib" chez --program tests/test-lifecycle.sps
```

Expected: 12 passes, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/cmark/gfm/private/scope.sls tests/test-lifecycle.sps
git commit -m "feat: add native document lifecycle with checked liveness"
```

---

### Task 11: Verify the aggregate test target and its exit codes

The Makefile from Task 6 already loops over `tests/test-*.sps`. This task proves
that loop actually fails when a suite fails. It gets its own gate because a test
target that always exits 0 is worse than no target at all — every later stage,
and CI, trusts this one behaviour, and nothing else in the suite can catch it.

**Files:**
- Modify: none (verification only, plus the fix if a defect is found)

**Interfaces:**
- Consumes: the `test` target from Task 6 and all three suites.
- Produces: a trustworthy `make test` — the contract every later stage depends on.

- [ ] **Step 1: Confirm all three suites are discovered**

```bash
ls tests/test-*.sps
```

Expected: `test-conditions.sps`, `test-lifecycle.sps`, `test-native.sps`. Any suite not matching the `test-*.sps` glob is silently skipped by the Makefile, which is the quiet way for coverage to rot.

- [ ] **Step 2: Confirm a passing run exits zero**

```bash
make test; echo "exit=$?"
```

Expected: three `=== tests/… ===` headers, `ALL SUITES PASSED`, `exit=0`.

- [ ] **Step 3: Sabotage one suite and confirm a non-zero exit**

```bash
printf '\n(test-begin "sabotage")\n(test-equal "deliberate" 1 2)\n(test-end "sabotage")\n' >> tests/test-conditions.sps
make test; echo "exit=$?"
```

Expected: the conditions suite reports a failure, `SUITE FAILED`, `exit=1`.

If this prints `exit=0`, the target is broken. The usual cause is the recipe
losing the `fail` variable across lines — every line of a `make` recipe runs in
its own shell unless joined with backslashes, so the loop must remain one
continuation-joined command.

- [ ] **Step 4: Confirm one failing suite does not mask the others**

With the sabotage still in place, check that all three suite headers still print.
A loop that aborts on first failure would hide later regressions behind an early
one, turning a full test run into a single-bug-at-a-time crawl.

Expected: all three `===` headers appear, and the exit code is still 1.

- [ ] **Step 5: Revert the sabotage and confirm green**

```bash
git checkout tests/test-conditions.sps
make test; echo "exit=$?"
```

Expected: `ALL SUITES PASSED`, `exit=0`.

- [ ] **Step 6: Commit only if the Makefile needed fixing**

If Steps 3 or 4 exposed a defect and you changed the recipe:

```bash
git add Makefile
git commit -m "fix: make the test target fail when a suite fails"
```

If nothing needed changing, there is nothing to commit — record in the task notes
that the exit-code contract was verified.

---

### Task 12: Mutation verification

The suite is only worth what it catches. This task proves each memory rule has a test that fails when the rule is broken. Every mutation is reverted immediately after being checked — nothing here is committed except the record.

**Files:**
- Create: `.plans/stage-1-mutation-log.md`

**Interfaces:**
- Consumes: everything above.
- Produces: a written record that each rule in design spec §7.4 is enforced by a named test.

- [ ] **Step 1: Mutation A — free the parser before the root**

In `scope.sls`, move the `parser-free` block in `release!` to run *before* the `node-free` block. Then:

```bash
make test; echo "exit=$?"
```

Expected: still passes. **This is the correct and important result** — teardown order between root and parser is not observable from the counters, because both still happen exactly once. The ordering rule that matters is the one covering *render*, and rendering does not exist until Stage 2. Record this honestly: the ADR-0005 ordering is currently guarded only by the Stage 0 spike, and Stage 2 Task 1 must add a render-with-extensions test under ASan. Revert the mutation.

- [ ] **Step 2: Mutation B — drop the liveness check**

In `scope.sls`, change `check-alive` to `(define (check-alive h) #t)`. Then:

```bash
make test; echo "exit=$?"
```

Expected: FAIL on "the handle is dead after the scope exits" and "every checked accessor rejects a dead handle". Revert.

- [ ] **Step 3: Mutation C — make release non-idempotent**

In `scope.sls`, remove the `(when (native-doc-alive? h) …)` guard from `release!` so the body always runs, and move `native-doc-alive?-set!` to the end. Then:

```bash
make test; echo "exit=$?"
```

Expected: FAIL or crash — a double `node-free` on the same root. If it merely passes, the counters are not being decremented where you think they are; investigate before continuing. Revert.

- [ ] **Step 4: Mutation D — skip the embedded-NUL check**

In `scope.sls`, delete the `char=? #\nul` clause from `validate-markdown-input`. Then:

```bash
make test; echo "exit=$?"
```

Expected: FAIL on "embedded NUL is rejected". Revert.

- [ ] **Step 5: Mutation E — measure characters instead of bytes**

In `scope.sls`, change the size check to `(> (string-length markdown) max-bytes)`. Then:

```bash
make test; echo "exit=$?"
```

Expected: FAIL on "the limit counts bytes, not characters". Revert.

- [ ] **Step 6: Mutation F — drop a counter decrement**

In `scope.sls`, delete the `(count-parser-free!)` call. Then:

```bash
make test; echo "exit=$?"
```

Expected: FAIL on every counter-balance test. Revert.

- [ ] **Step 7: Confirm the tree is clean and green**

```bash
git status --short
make test; echo "exit=$?"
```

Expected: no modifications, `exit=0`. If `git status` shows changes, a mutation was not reverted.

- [ ] **Step 8: Record the results**

Create `.plans/stage-1-mutation-log.md` with a row per mutation: what was changed, which named tests failed, and whether the rule is considered covered. Mutation A must be recorded as **not yet covered**, with a pointer to Stage 2.

- [ ] **Step 9: Run the memory suite**

```bash
make test-memory; echo "exit=$?"
```

On Linux expect a Valgrind run with no definite leaks and `exit=0`. On macOS expect the printed caveat and a clean ASan run; do not record a leak claim from macOS.

- [ ] **Step 10: Remove the spike and commit**

The spike's answers now live in `FINDINGS.md`; the code has served its purpose.

```bash
git rm -r spike/00-load.ss spike/01-strings.ss spike/02-parse.ss spike/03-uaf.ss
git add .plans/stage-1-mutation-log.md
git commit -m "test: verify memory rules by mutation and retire the spike"
```

Note `spike/FINDINGS.md` is deliberately kept — it is the record of what Stage 0 established.

---

## Stage 1 Exit Gate

- [ ] `make build` succeeds with warnings-as-errors on both acquisition paths (test the vendored path with `HAVE_PKG=no make build`).
- [ ] `make test` passes and exits 0; a deliberately broken test makes it exit 1.
- [ ] Every mutation in Task 12 behaves as recorded in the mutation log.
- [ ] `make test-memory` is clean on the platform that can make the claim.
- [ ] No native pointer is reachable from outside `(cmark gfm private ...)`.
- [ ] `spike/FINDINGS.md` answers Q1, and Task 9 reflects that answer.

**Carried into Stage 2:** ADR-0005's teardown ordering has no regression test yet, because nothing renders. Stage 2's first task must be a render-with-extensions test that fails under ASan when the parser is freed early.
