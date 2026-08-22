# Shimless FFI and Akku Installation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the C shim and bind `libcmark-gfm` directly from Scheme, resolving it at
runtime from a candidate list, so `akku install chez-cmark-gfm` works with no compiler.

**Architecture:** A new pure `(cmark gfm private discovery)` scans a fixed list of absolute
system directories for a *matched pair* of versioned cmark shared objects — core and
extensions at the same version in the same directory — and `(cmark gfm private native)`
loads them by absolute path. The five jobs the C shim did move into Scheme: version
reporting, option-bit constants, buffer freeing through cmark's own allocator, `_Bool`
normalisation, and debug counters.

**Tech Stack:** Chez Scheme 9.5.8+ (R6RS), SRFI-64 for tests, GNU Make, libcmark-gfm
0.29.x.gfm.y from the system package manager.

**Spec:** [.plans/2026-08-21-shimless-ffi-design.md](2026-08-21-shimless-ffi-design.md).
Section references below (§N) point there.

## Global Constraints

- **Branch:** `feat/shimless-ffi`. Already created and holding the design spec commit.
- **Supported version range:** `(#x001d0000 . #x001dffff)` — any `0.29.x.gfm.y`. Copy
  verbatim; never widen it in this work.
- **Version encoding:** `(major << 24) | (minor << 16) | (patch << 8) | gfm`. Check value:
  `0.29.0.gfm.13` = `#x001D000D`, which is what `cmark_version()` returns.
- **Ordering rule (load-bearing):** Chez resolves a foreign entry point when the
  `foreign-procedure` expression is **evaluated**, not when called. Every
  `load-shared-object` must therefore be written **as a definition** placed above the
  `foreign-procedure` definitions. See the ORDERING NOTE at `native.sls:5-11`. Writing it
  as a bare expression fails at *import* time.
- **Load order:** core **before** extensions, always. On Linux a dlopen'd library's
  dependencies are not placed in the global symbol namespace (`native.sls:88-96`).
- **Absolute paths only, never leafnames.** `load-shared-object "libcmark-gfm.dylib"`
  silently resolves to macOS's own shared-cache copy at `/usr/lib/libcmark-gfm.dylib`
  (§3.7). Never introduce a bare-soname fallback.
- **R6RS body rule:** definitions must precede expressions in any body. Several steps
  below fail to compile if this is violated.
- **`(only (chezscheme) …)` conflicts:** do not import `exit` or `file-exists?` from
  `(chezscheme)`; `(rnrs)` already exports both and Chez rejects the duplicate.
- **Tests before implementation.** Every task writes a failing test first and runs it to
  confirm it fails for the expected reason.
- **Commit at the end of every task**, with the suite green.
- **Baseline:** `make test` passes on `main` — `ALL SUITES PASSED`. Any behavioral
  difference introduced by this work is a bug, not an expected consequence.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `src/cmark/gfm/private/discovery.sls` | **new**, pure. Version parse/encode, platform library naming, candidate directories, pair selection, override parsing. Takes filesystem access as arguments so it is testable with no filesystem. | 1 |
| `tests/test-discovery.sps` | **new**. Unit suite for the above, driven by synthetic directory listings. | 1 |
| `tests/test-option-bits.sps` | **new**. Asserts the Scheme constant table against `vendor/cmark-gfm/src/cmark-gfm.h`. | 2 |
| `src/cmark/gfm/private/native.sls` | Loses the shim; gains direct cmark bindings, the constant table, and discovery wiring. | 2,3,4 |
| `src/cmark/gfm/private/scope.sls` | Counters become a Scheme box here. | 3 |
| `src/cmark/gfm/private/conditions.sls` | `&cmark-shim-unavailable` → `&cmark-library-unavailable`; `&cmark-version-incompatible` field reshape. | 5 |
| `src/cmark/gfm.sls` | Re-exports follow the rename. | 5 |
| `src/cmark/gfm/private/config.sls`, `fallback/` | **deleted**. | 4 |
| `src/cmark-gfm-shim.{c,h}` | **deleted**. | 4 |
| `Makefile` | `build` becomes a preflight; shim/flavor/prod machinery removed. | 6 |
| `.github/workflows/ci.yml` | New acquisition rows, a not-found job, an Akku job. | 7 |
| `README.org`, `CHANGELOG.md`, `NOTICE`, `Akku.manifest`, `.plans/decisions/00{15,16,17}-*.md` | Documentation and release. | 8 |

---

### Task 1: The discovery library

**Files:**
- Create: `src/cmark/gfm/private/discovery.sls`
- Create: `tests/test-discovery.sps`

**Interfaces:**
- Consumes: nothing. This library imports only `(rnrs)` and `(only (chezscheme) machine-type)`.
- Produces:
  - `(encode-version major minor patch gfm) -> integer`
  - `(version->string v) -> string` — `#x001D000D` → `"0.29.0.gfm.13"`
  - `(parse-version-string s) -> integer | #f`
  - `(library-file-version name kind platform) -> integer | #f`; `kind` ∈ `core`/`extensions`, `platform` ∈ `linux`/`macos`
  - `(core-library-name v platform) -> string`, `(extensions-library-name v platform) -> string`
  - `(current-platform) -> 'macos | 'linux`, `(current-machine) -> string`
  - `(default-candidate-directories platform machine list-dir dir?) -> (list string)`
  - `(select-cmark-libraries list-dir dir? candidates range platform) -> (values status payload)`
    where status ∈ `found` (payload `(core . ext)`), `not-found` (payload `#f`),
    `out-of-range` (payload integer)
  - `(parse-library-override str regular-file?) -> (values status payload)`
    where status ∈ `ok` (payload `(core . ext)`), `invalid` (payload `#f`)

- [ ] **Step 1: Write the failing test**

Create `tests/test-discovery.sps`:

```scheme
#!r6rs
(import (rnrs)
        (srfi :64)
        (cmark gfm private discovery))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "discovery")

(define RANGE '(#x001d0000 . #x001dffff))

;; --- version encoding round-trips against cmark's own scheme -----------
;; #x001D000D is what cmark_version() returns for 0.29.0.gfm.13; the encode
;; here must agree with it or every range check is meaningless.
(test-equal "encode matches cmark_version" #x001D000D (encode-version 0 29 0 13))
(test-equal "version->string" "0.29.0.gfm.13" (version->string #x001D000D))
(test-equal "parse round-trips" #x001D000D (parse-version-string "0.29.0.gfm.13"))
(test-assert "four components is not a version" (not (parse-version-string "0.29.0.13")))
(test-assert "missing gfm literal rejected" (not (parse-version-string "0.29.0.xyz.13")))
(test-assert "non-numeric component rejected" (not (parse-version-string "0.29.0.gfm.x")))

;; --- names ------------------------------------------------------------
(test-equal "linux core name" "libcmark-gfm.so.0.29.0.gfm.13"
  (core-library-name #x001D000D 'linux))
(test-equal "linux extensions name" "libcmark-gfm-extensions.so.0.29.0.gfm.13"
  (extensions-library-name #x001D000D 'linux))
(test-equal "macos core name" "libcmark-gfm.0.29.0.gfm.13.dylib"
  (core-library-name #x001D000D 'macos))
(test-equal "macos extensions name" "libcmark-gfm-extensions.0.29.0.gfm.13.dylib"
  (extensions-library-name #x001D000D 'macos))

;; The core prefix must not swallow the extensions file. On both platforms the
;; character after "libcmark-gfm" is what separates them.
(test-assert "core shape does not match extensions file (linux)"
  (not (library-file-version "libcmark-gfm-extensions.so.0.29.0.gfm.13" 'core 'linux)))
(test-assert "core shape does not match extensions file (macos)"
  (not (library-file-version "libcmark-gfm-extensions.0.29.0.gfm.13.dylib" 'core 'macos)))

;; Unversioned names are invisible to the search ON PURPOSE (spec 3.7): this
;; is one of three things keeping macOS's shared-cache copy unreachable.
(test-assert "unversioned .so is not a candidate"
  (not (library-file-version "libcmark-gfm.so" 'core 'linux)))
(test-assert "unversioned .dylib is not a candidate"
  (not (library-file-version "libcmark-gfm.dylib" 'core 'macos)))

;; --- selection, against synthetic listings ----------------------------
(define (fs-list alist) (lambda (d) (cond ((assoc d alist) => cdr) (else '()))))
(define (fs-dir? alist) (lambda (d) (and (assoc d alist) #t)))
(define (sel alist dirs)
  (let-values (((status payload)
                (select-cmark-libraries (fs-list alist) (fs-dir? alist)
                                        dirs RANGE 'linux)))
    (list status payload)))
(define (pair-at v)
  (list (string-append "libcmark-gfm.so." v)
        (string-append "libcmark-gfm-extensions.so." v)))
(define (found-at d v)
  (list 'found (cons (string-append d "/libcmark-gfm.so." v)
                     (string-append d "/libcmark-gfm-extensions.so." v))))

(test-equal "empty directory" '(not-found #f) (sel '(("/a")) '("/a")))
(test-equal "absent directory" '(not-found #f) (sel '() '("/a")))
(test-equal "core without extensions is not a pair" '(not-found #f)
  (sel '(("/a" "libcmark-gfm.so.0.29.0.gfm.13")) '("/a")))
(test-equal "extensions without core is not a pair" '(not-found #f)
  (sel '(("/a" "libcmark-gfm-extensions.so.0.29.0.gfm.13")) '("/a")))
(test-equal "matched pair is found" (found-at "/a" "0.29.0.gfm.13")
  (sel (list (cons "/a" (pair-at "0.29.0.gfm.13"))) '("/a")))

;; Both of these fail if version comparison is lexical rather than numeric.
;; "9" sorts above "13" as a string, so this is not a hypothetical.
(test-equal "gfm.6 and gfm.13 -> 13" (found-at "/a" "0.29.0.gfm.13")
  (sel (list (cons "/a" (append (pair-at "0.29.0.gfm.6")
                                (pair-at "0.29.0.gfm.13")))) '("/a")))
(test-equal "gfm.9 and gfm.13 -> 13" (found-at "/a" "0.29.0.gfm.13")
  (sel (list (cons "/a" (append (pair-at "0.29.0.gfm.9")
                                (pair-at "0.29.0.gfm.13")))) '("/a")))

;; The double-load hazard (spec 3.1 clause 4): the extensions library carries a
;; DT_NEEDED on the core's FULL versioned SONAME, so a mismatched pair would
;; pull a second cmark core into the process.
(test-equal "skewed core/extensions versions do not pair" '(not-found #f)
  (sel '(("/a" "libcmark-gfm.so.0.29.0.gfm.13"
               "libcmark-gfm-extensions.so.0.29.0.gfm.6")) '("/a")))
(test-equal "unversioned pair does not qualify" '(not-found #f)
  (sel '(("/a" "libcmark-gfm.so" "libcmark-gfm-extensions.so")) '("/a")))

;; A paired-but-unsupported version must say so by name rather than reporting
;; "nothing found", which would send the user looking for a missing package.
(test-equal "only 0.30 present -> out-of-range"
  (list 'out-of-range (encode-version 0 30 0 0))
  (sel (list (cons "/a" (pair-at "0.30.0.gfm.0"))) '("/a")))

(test-equal "first directory with a pair wins" (found-at "/a" "0.29.0.gfm.6")
  (sel (list (cons "/a" (pair-at "0.29.0.gfm.6"))
             (cons "/b" (pair-at "0.29.0.gfm.13"))) '("/a" "/b")))
(test-equal "unpaired first directory falls through" (found-at "/b" "0.29.0.gfm.13")
  (sel (list (cons "/a" '("libcmark-gfm.so.0.29.0.gfm.13"))
             (cons "/b" (pair-at "0.29.0.gfm.13"))) '("/a" "/b")))

;; --- candidate directories --------------------------------------------
(define (no-list d) '())
(define (no-dir d) #f)
(test-equal "macos candidates"
  '("/opt/homebrew/lib" "/usr/local/lib" "/opt/local/lib")
  (default-candidate-directories 'macos "tarm64osx" no-list no-dir))
(test-equal "linux x86_64 triple"
  '("/usr/local/lib" "/usr/lib/x86_64-linux-gnu" "/usr/lib" "/usr/lib64")
  (default-candidate-directories 'linux "ta6le" no-list no-dir))
(test-equal "linux arm64 triple"
  '("/usr/local/lib" "/usr/lib/aarch64-linux-gnu" "/usr/lib" "/usr/lib64")
  (default-candidate-directories 'linux "tarm64le" no-list no-dir))
(test-equal "unknown machine enumerates /usr/lib subdirectories"
  '("/usr/local/lib" "/usr/lib/aarch64-linux-gnu" "/usr/lib/x86_64-linux-musl"
    "/usr/lib" "/usr/lib64")
  (default-candidate-directories 'linux "zz99"
    (lambda (d) '("x86_64-linux-musl" "not-a-triple" "aarch64-linux-gnu"))
    (lambda (d) (string=? d "/usr/lib"))))

;; --- override ---------------------------------------------------------
(define (ov s . rf)
  (let-values (((status payload)
                (parse-library-override s (if (null? rf) (lambda (p) #t) (car rf)))))
    (list status payload)))
(define OK '(ok ("/a/libcmark-gfm.so" . "/a/libcmark-gfm-extensions.so")))

(test-equal "unset override"  '(invalid #f) (ov #f))
(test-equal "empty override"  '(invalid #f) (ov ""))
(test-equal "one entry"       '(invalid #f) (ov "/a/libcmark-gfm.so"))
(test-equal "three entries"   '(invalid #f)
  (ov "/a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so:/c"))
(test-equal "relative path"   '(invalid #f)
  (ov "a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so"))
(test-equal "two cores"       '(invalid #f)
  (ov "/a/libcmark-gfm.so:/b/libcmark-gfm.so"))
(test-equal "two extensions"  '(invalid #f)
  (ov "/a/libcmark-gfm-extensions.so:/b/libcmark-gfm-extensions.so"))
(test-equal "in order" OK (ov "/a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so"))
;; Order must NOT matter: classification is by basename, so a swapped variable
;; is not a footgun (spec 3.5).
(test-equal "swapped order normalises" OK
  (ov "/a/libcmark-gfm-extensions.so:/a/libcmark-gfm.so"))
(test-equal "nonexistent file" '(invalid #f)
  (ov "/a/libcmark-gfm.so:/a/libcmark-gfm-extensions.so" (lambda (p) #f)))

;; Classification reads the BASENAME only. Matching the whole path lets a
;; directory name decide which library is which: the second case below is
;; accepted as valid with the pair REVERSED under whole-path matching, which
;; loads the core as the extensions library and vice versa.
(test-equal "a directory named ...cmark-gfm-extensions... does not reclassify the core"
  '(ok ("/opt/cmark-gfm-extensions-build/libcmark-gfm.so"
        . "/opt/other/libcmark-gfm-extensions.so"))
  (ov "/opt/cmark-gfm-extensions-build/libcmark-gfm.so:/opt/other/libcmark-gfm-extensions.so"))

(test-equal "neither basename identifies itself -> refused, never guessed"
  '(invalid #f)
  (ov "/home/u/cmark-gfm-extensions-cache/renamed-core.so:/home/u/other/renamed-ext.so"))

(test-end "discovery")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-discovery.sps
```

Expected: `Exception: library (cmark gfm private discovery) not found`.

- [ ] **Step 3: Write the implementation**

Create `src/cmark/gfm/private/discovery.sls`. This code is verified — all 42 assertions
above pass against it.

```scheme
#!r6rs
;;; Runtime resolution of the cmark shared objects.
;;;
;;; PURE. Imports nothing that can reach a shared object, and takes its
;;; filesystem access as arguments, so every branch below is unit-testable
;;; against synthetic listings with no files on disk. That is the same reason
;;; resolve-shim-path was an exported procedure rather than a bare expression.
;;;
;;; Only VERSIONED filenames are candidates, and core and extensions must pair
;;; at the SAME version in the SAME directory. Three separate hazards depend on
;;; that rule; see the design spec 3.1 before relaxing any part of it.
(library (cmark gfm private discovery)
  (export encode-version version->string parse-version-string
          library-file-version core-library-name extensions-library-name
          current-platform current-machine default-candidate-directories
          select-cmark-libraries parse-library-override)
  (import (rnrs)
          (only (chezscheme) machine-type))

  ;; cmark's own encoding: cmark_version() returns exactly this.
  (define (encode-version major minor patch gfm)
    (+ (* major #x1000000) (* minor #x10000) (* patch #x100) gfm))

  (define (version->string v)
    (string-append
     (number->string (div v #x1000000)) "."
     (number->string (mod (div v #x10000) #x100)) "."
     (number->string (mod (div v #x100) #x100)) ".gfm."
     (number->string (mod v #x100))))

  (define (string-split s ch)
    (let loop ((i 0) (start 0) (acc '()))
      (cond
        ((= i (string-length s)) (reverse (cons (substring s start i) acc)))
        ((char=? (string-ref s i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
        (else (loop (+ i 1) start acc)))))

  ;; #f rather than an error for any non-numeric input: callers are filtering
  ;; directory listings, where a non-match is ordinary, not exceptional.
  (define (numeric-string->integer s)
    (and (> (string-length s) 0)
         (let loop ((i 0) (acc 0))
           (cond
             ((= i (string-length s)) acc)
             ((char<=? #\0 (string-ref s i) #\9)
              (loop (+ i 1) (+ (* acc 10) (- (char->integer (string-ref s i))
                                             (char->integer #\0)))))
             (else #f)))))

  (define (parse-version-string s)
    (let ((parts (string-split s #\.)))
      (and (= 5 (length parts))
           (string=? "gfm" (list-ref parts 3))
           (let ((m (numeric-string->integer (list-ref parts 0)))
                 (n (numeric-string->integer (list-ref parts 1)))
                 (p (numeric-string->integer (list-ref parts 2)))
                 (g (numeric-string->integer (list-ref parts 4))))
             (and m n p g
                  (< m 256) (< n 256) (< p 256) (< g 256)
                  (encode-version m n p g))))))

  (define (string-prefix? p s)
    (and (>= (string-length s) (string-length p))
         (string=? p (substring s 0 (string-length p)))))

  (define (string-suffix? q s)
    (and (>= (string-length s) (string-length q))
         (string=? q (substring s (- (string-length s) (string-length q))
                                (string-length s)))))

  (define (base-name kind)
    (if (eq? kind 'core) "libcmark-gfm" "libcmark-gfm-extensions"))

  ;; The separator is what keeps the core shape from matching the extensions
  ;; file: "libcmark-gfm." does not prefix "libcmark-gfm-extensions...".
  (define (name-prefix kind platform)
    (string-append (base-name kind) (if (eq? platform 'linux) ".so." ".")))

  (define (name-suffix platform)
    (if (eq? platform 'linux) "" ".dylib"))

  (define (core-library-name v platform)
    (string-append (name-prefix 'core platform) (version->string v)
                   (name-suffix platform)))

  (define (extensions-library-name v platform)
    (string-append (name-prefix 'extensions platform) (version->string v)
                   (name-suffix platform)))

  ;; -> encoded version, or #f when `name` is not a versioned library of `kind`
  (define (library-file-version name kind platform)
    (let ((p (name-prefix kind platform))
          (q (name-suffix platform)))
      (and (string-prefix? p name)
           (string-suffix? q name)
           (>= (string-length name) (+ (string-length p) (string-length q)))
           (parse-version-string
            (substring name (string-length p)
                       (- (string-length name) (string-length q)))))))

  (define (current-machine) (symbol->string (machine-type)))

  (define (current-platform)
    (if (string-suffix? "osx" (current-machine)) 'macos 'linux))

  (define (default-candidate-directories platform machine list-dir dir?)
    (if (eq? platform 'macos)
        '("/opt/homebrew/lib" "/usr/local/lib" "/opt/local/lib")
        (append '("/usr/local/lib")
                (linux-triple-directories machine list-dir dir?)
                '("/usr/lib" "/usr/lib64"))))

  ;; One derived triple rather than every triple present: on a multiarch box,
  ;; scanning all of them would eventually attempt a wrong-architecture load,
  ;; and there is deliberately no fall-through on load failure.
  (define (linux-triple-directories stem list-dir dir?)
    (cond
      ((known-triple stem) => (lambda (t) (list (string-append "/usr/lib/" t))))
      (else
       (if (dir? "/usr/lib")
           (map (lambda (d) (string-append "/usr/lib/" d))
                (list-sort string<?
                           (filter (lambda (d)
                                     (or (string-suffix? "-linux-gnu" d)
                                         (string-suffix? "-linux-musl" d)))
                                   (list-dir "/usr/lib"))))
           '()))))

  ;; machine-type is like ta6le / tarm64le; the leading `t` marks a threaded
  ;; build and is not part of the architecture.
  (define (known-triple stem)
    (let ((arch (if (string-prefix? "t" stem)
                    (substring stem 1 (string-length stem))
                    stem)))
      (let loop ((table '(("a6" . "x86_64-linux-gnu")
                          ("arm64" . "aarch64-linux-gnu")
                          ("i3" . "i386-linux-gnu")
                          ("ppc64le" . "powerpc64le-linux-gnu")
                          ("rv64" . "riscv64-linux-gnu"))))
        (cond
          ((null? table) #f)
          ((string-prefix? (caar table) arch) (cdar table))
          (else (loop (cdr table)))))))

  (define (versions-of names kind platform)
    (let loop ((ns names) (acc '()))
      (cond
        ((null? ns) acc)
        ((library-file-version (car ns) kind platform)
         => (lambda (v) (loop (cdr ns) (cons v acc))))
        (else (loop (cdr ns) acc)))))

  (define (intersect a b) (filter (lambda (x) (memv x b)) a))

  ;; Numeric, not lexical. "libcmark-gfm.so.0.29.0.gfm.9" sorts ABOVE
  ;; "...gfm.13" as a string, which would select the older library.
  (define (maximum lst)
    (fold-left (lambda (a b) (if (> b a) b a)) (car lst) (cdr lst)))

  (define (path-join dir name) (string-append dir "/" name))

  ;; -> (values 'found (core . ext)) | (values 'not-found #f)
  ;;  | (values 'out-of-range encoded-version)
  ;;
  ;; Two values rather than one overloaded return: a success pair and an
  ;; out-of-range pair would otherwise be told apart only by the car's type.
  (define (select-cmark-libraries list-dir dir? candidates range platform)
    (let ((lo (car range)) (hi (cdr range)))
      (let loop ((dirs candidates) (seen '()))
        (if (null? dirs)
            (if (null? seen)
                (values 'not-found #f)
                (values 'out-of-range (maximum seen)))
            (let ((d (car dirs)))
              (if (not (dir? d))
                  (loop (cdr dirs) seen)
                  (let* ((names (list-dir d))
                         (both (intersect (versions-of names 'core platform)
                                          (versions-of names 'extensions platform)))
                         (ok (filter (lambda (v) (and (>= v lo) (<= v hi))) both)))
                    (cond
                      ((pair? ok)
                       (let ((v (maximum ok)))
                         (values 'found
                                 (cons (path-join d (core-library-name v platform))
                                       (path-join d (extensions-library-name v platform))))))
                      ((pair? both) (loop (cdr dirs) (append both seen)))
                      (else (loop (cdr dirs) seen))))))))))

  (define (absolute? p)
    (and (> (string-length p) 0) (char=? #\/ (string-ref p 0))))

  (define (substring-search needle hay)
    (let ((n (string-length needle)) (h (string-length hay)))
      (let loop ((i 0))
        (cond
          ((> (+ i n) h) #f)
          ((string=? needle (substring hay i (+ i n))) #t)
          (else (loop (+ i 1)))))))

  ;; Classify by BASENAME, not the whole path. A core library sitting in a
  ;; directory whose name happens to contain "cmark-gfm-extensions" would
  ;; otherwise be classified as the extensions library and silently swapped
  ;; with its partner -- both files exist and both are absolute, so nothing
  ;; downstream would notice. Demonstrated: whole-path matching accepts
  ;; "/home/u/cmark-gfm-extensions-cache/renamed-core.so:/home/u/other/renamed-ext.so"
  ;; as valid with the pair reversed.
  (define (basename p)
    (let loop ((i (- (string-length p) 1)))
      (cond
        ((< i 0) p)
        ((char=? #\/ (string-ref p i)) (substring p (+ i 1) (string-length p)))
        (else (loop (- i 1))))))

  (define (extensions-path? p)
    (substring-search "cmark-gfm-extensions" (basename p)))

  ;; -> (values 'ok (core . ext)) | (values 'invalid #f)
  ;;
  ;; No version parsing: an explicit override may legitimately name the
  ;; unversioned symlinks from a -dev package. Selection is the user's;
  ;; verification is still ours, via cmark_version() after the load.
  ;;
  ;; Order in the variable does not matter -- each entry is classified by
  ;; basename -- so a swapped value is not a silent misload.
  (define (parse-library-override str regular-file?)
    (if (or (not str) (string=? str ""))
        (values 'invalid #f)
        (let ((parts (string-split str #\:)))
          (if (not (= 2 (length parts)))
              (values 'invalid #f)
              (let ((a (car parts)) (b (cadr parts)))
                (if (not (and (absolute? a) (absolute? b)
                              (regular-file? a) (regular-file? b)))
                    (values 'invalid #f)
                    (let ((a-ext? (extensions-path? a))
                          (b-ext? (extensions-path? b)))
                      (cond
                        ((and b-ext? (not a-ext?)) (values 'ok (cons a b)))
                        ((and a-ext? (not b-ext?)) (values 'ok (cons b a)))
                        (else (values 'invalid #f)))))))))))
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-discovery.sps
```

Expected: `# of expected passes 42`, exit 0.

- [ ] **Step 5: Confirm the rest of the suite is untouched**

```bash
make test
```

Expected: `ALL SUITES PASSED`. Nothing imports `discovery.sls` yet, so this must be
identical to the baseline.

- [ ] **Step 6: Commit**

```bash
git add src/cmark/gfm/private/discovery.sls tests/test-discovery.sps
git commit -m "feat: add pure cmark library discovery"
```

---

### Task 2: Option constants in Scheme, proven against the header and the shim

**Files:**
- Modify: `src/cmark/gfm/private/native.sls:113` (add the table beside `raw-option-bits`)
- Create: `tests/test-option-bits.sps`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `(option-bits validate-utf8? sourcepos? hardbreaks? nobreaks? smart? unsafe-html?) -> integer`, unchanged signature. Also exports `cmark-opt-default`, `cmark-opt-sourcepos`, `cmark-opt-hardbreaks`, `cmark-opt-nobreaks`, `cmark-opt-validate-utf8`, `cmark-opt-smart`, `cmark-opt-unsafe` for the parity test.

**Why this task comes before the shim is removed:** while both exist, the Scheme table can
be proven equal to `chez_cmark_option_bits` — the very code it replaces — across all 64
flag combinations. That assertion is deleted with the shim in Task 4. Its purpose is to
make Task 4 safe.

- [ ] **Step 1: Write the failing test**

Create `tests/test-option-bits.sps`:

```scheme
#!r6rs
;;; The Scheme option-bit table against its two oracles.
;;;
;;; The shim used to build this mask in C, so the constants could not drift
;;; from the headers. With the table in Scheme that guarantee becomes a test,
;;; and this is it. Five of the six bits are ALSO covered behaviourally by
;;; tests/test-differential.sps; validate-utf8 is unreachable through the
;;; public API and has no other coverage at all, which is why the header
;;; parity check below is not optional.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) file-exists?)
        (cmark gfm private native))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "option-bits")

(define HEADER "vendor/cmark-gfm/src/cmark-gfm.h")

;; Reads `#define CMARK_OPT_NAME (1 << N)` and `#define CMARK_OPT_NAME 0`.
;; Deliberately narrow: anything it cannot parse is skipped, and a name that
;; never appears yields #f, which fails the assertion rather than passing
;; vacuously.
(define (header-constant name)
  (and (file-exists? HEADER)
       (let ((needle (string-append "#define " name " ")))
         (call-with-input-file HEADER
           (lambda (port)
             (let loop ()
               (let ((line (get-line port)))
                 (cond
                   ((eof-object? line) #f)
                   ((and (>= (string-length line) (string-length needle))
                         (string=? needle (substring line 0 (string-length needle))))
                    (parse-value (substring line (string-length needle)
                                            (string-length line))))
                   (else (loop))))))))))

(define (parse-value s)
  ;; either "0" or "(1 << N)"
  (let ((digits (lambda (str)
                  (let loop ((i 0) (acc #f))
                    (cond
                      ((= i (string-length str)) acc)
                      ((char<=? #\0 (string-ref str i) #\9)
                       (loop (+ i 1) (+ (* (or acc 0) 10)
                                        (- (char->integer (string-ref str i))
                                           (char->integer #\0)))))
                      ((and acc (char=? (string-ref str i) #\))) acc)
                      (else (loop (+ i 1) acc)))))))
    (if (and (> (string-length s) 0) (char=? #\( (string-ref s 0)))
        (bitwise-arithmetic-shift-left 1 (digits s))
        (digits s))))

(test-assert "the vendored header is present"
  (file-exists? HEADER))

(test-equal "CMARK_OPT_DEFAULT"       (header-constant "CMARK_OPT_DEFAULT")       cmark-opt-default)
(test-equal "CMARK_OPT_SOURCEPOS"     (header-constant "CMARK_OPT_SOURCEPOS")     cmark-opt-sourcepos)
(test-equal "CMARK_OPT_HARDBREAKS"    (header-constant "CMARK_OPT_HARDBREAKS")    cmark-opt-hardbreaks)
(test-equal "CMARK_OPT_NOBREAKS"      (header-constant "CMARK_OPT_NOBREAKS")      cmark-opt-nobreaks)
(test-equal "CMARK_OPT_VALIDATE_UTF8" (header-constant "CMARK_OPT_VALIDATE_UTF8") cmark-opt-validate-utf8)
(test-equal "CMARK_OPT_SMART"         (header-constant "CMARK_OPT_SMART")         cmark-opt-smart)
(test-equal "CMARK_OPT_UNSAFE"        (header-constant "CMARK_OPT_UNSAFE")        cmark-opt-unsafe)

;; Structural properties, kept from tests/test-native.sps. Against a
;; Scheme-defined table these are weak on their own -- they compare the table
;; with itself -- which is exactly why the header parity above carries the
;; real weight.
(test-assert "the six flags set six distinct non-zero bits"
  (let ((flags (list cmark-opt-validate-utf8 cmark-opt-sourcepos
                     cmark-opt-hardbreaks cmark-opt-nobreaks
                     cmark-opt-smart cmark-opt-unsafe)))
    (and (for-all (lambda (f) (> f 0)) flags)
         (= 6 (length flags))
         (= (fold-left bitwise-ior 0 flags)
            (fold-left + 0 flags)))))   ; disjoint iff ior equals sum

(test-assert "option-bits composes by ior"
  (= (option-bits #t #t #f #f #f #f)
     (bitwise-ior (option-bits #t #f #f #f #f #f)
                  (option-bits #f #t #f #f #f #f))))

(test-equal "all flags off is zero" 0 (option-bits #f #f #f #f #f #f))

;; --- TRANSITIONAL: delete this block in Task 4, with the shim ----------
;; Equivalence against chez_cmark_option_bits over all 64 combinations. This
;; is a direct proof against the code being replaced; it exists to make the
;; shim's removal safe and has no purpose afterwards.
(test-assert "Scheme table agrees with the shim for all 64 combinations"
  (let loop ((n 0))
    (or (= n 64)
        (let ((bit (lambda (i) (bitwise-bit-set? n i))))
          (and (= (option-bits (bit 0) (bit 1) (bit 2) (bit 3) (bit 4) (bit 5))
                  (shim-option-bits (bit 0) (bit 1) (bit 2) (bit 3) (bit 4) (bit 5)))
               (loop (+ n 1)))))))
;; --- end transitional block -------------------------------------------

(test-end "option-bits")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-option-bits.sps
```

Expected: an unbound-identifier error naming `cmark-opt-default`.

- [ ] **Step 3: Add the constant table and the transitional export**

In `src/cmark/gfm/private/native.sls`, add these names to the `(export …)` list:

```scheme
          cmark-opt-default cmark-opt-sourcepos cmark-opt-hardbreaks
          cmark-opt-nobreaks cmark-opt-validate-utf8 cmark-opt-smart
          cmark-opt-unsafe
          shim-option-bits
```

Replace the body of `option-bits` (at `native.sls:288`, delegating to `raw-option-bits`)
with the table and a Scheme implementation. Keep `raw-option-bits` bound, renaming its
wrapper to `shim-option-bits` for the transitional assertion:

```scheme
  ;; cmark's option bits, transcribed from vendor/cmark-gfm/src/cmark-gfm.h.
  ;; tests/test-option-bits.sps asserts every one of these against that header;
  ;; five of the six are additionally covered behaviourally by
  ;; tests/test-differential.sps. Do not "tidy" these into a sequence -- the
  ;; values are not contiguous (UNSAFE is bit 17, not bit 5).
  (define cmark-opt-default       0)
  (define cmark-opt-sourcepos     (bitwise-arithmetic-shift-left 1 1))
  (define cmark-opt-hardbreaks    (bitwise-arithmetic-shift-left 1 2))
  (define cmark-opt-nobreaks      (bitwise-arithmetic-shift-left 1 4))
  (define cmark-opt-validate-utf8 (bitwise-arithmetic-shift-left 1 9))
  (define cmark-opt-smart         (bitwise-arithmetic-shift-left 1 10))
  (define cmark-opt-unsafe        (bitwise-arithmetic-shift-left 1 17))

  (define (option-bits validate-utf8? sourcepos? hardbreaks?
                       nobreaks? smart? unsafe-html?)
    (let ((add (lambda (acc on? bit) (if on? (bitwise-ior acc bit) acc))))
      (add (add (add (add (add (add cmark-opt-default
                                    validate-utf8? cmark-opt-validate-utf8)
                               sourcepos?    cmark-opt-sourcepos)
                          hardbreaks?   cmark-opt-hardbreaks)
                     nobreaks?     cmark-opt-nobreaks)
                smart?        cmark-opt-smart)
           unsafe-html?  cmark-opt-unsafe)))

  ;; TRANSITIONAL (deleted in Task 4 with the shim): the C implementation the
  ;; table above replaces, kept only so tests/test-option-bits.sps can prove
  ;; the two agree across all 64 combinations.
  (define (shim-option-bits validate-utf8? sourcepos? hardbreaks?
                            nobreaks? smart? unsafe-html?)
    (raw-option-bits (bool->int validate-utf8?)
                     (bool->int sourcepos?)
                     (bool->int hardbreaks?)
                     (bool->int nobreaks?)
                     (bool->int smart?)
                     (bool->int unsafe-html?)))
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-option-bits.sps
```

Expected: 12 passes, exit 0. **The 64-combination assertion passing is the gate for
Task 4** — if it fails, the table is wrong and the shim must not be removed.

- [ ] **Step 5: Run the whole suite**

```bash
make test
```

Expected: `ALL SUITES PASSED`. `option-bits` now comes from Scheme, so the differential
suite is exercising the new table end to end.

- [ ] **Step 6: Commit**

```bash
git add src/cmark/gfm/private/native.sls tests/test-option-bits.sps
git commit -m "feat: build cmark option masks in Scheme, proven against header and shim"
```

---

### Task 3: Direct cmark bindings replace the shim's; counters move to Scheme

**Files:**
- Modify: `src/cmark/gfm/private/native.sls:107-131` (shim bindings), `:225-300` (version check, counters)
- Modify: `src/cmark/gfm/private/scope.sls:16-25` (imports/exports unchanged in shape)
- Modify: `tests/test-native.sps` (drop shim-specific assertions)
- Modify: `tests/test-lifecycle.sps:58-59` (counters always on)

**Interfaces:**
- Consumes: `option-bits` and the constant table from Task 2.
- Produces:
  - `(cmark-runtime-version) -> integer` (replaces `shim-runtime-version`)
  - `(free-buffer addr) -> void` — now via the allocator's third slot
  - `(tasklist-checked node) -> boolean` — unchanged signature, `unsigned-8` result
  - `(live-counts) -> (parsers roots buffers)` — unchanged signature, Scheme-backed
  - `count-parser-new!` etc. — unchanged signatures, Scheme-backed
  - `shim-compiled-version` and `shim-option-bits` are **removed from the export list**

- [ ] **Step 1: Write the failing test**

Add to `tests/test-native.sps`, before the final `(test-end …)`:

```scheme
;; --- the allocator slot the shim used to hide ------------------------
;; cmark_get_default_mem_allocator returns {calloc, realloc, free}. Freeing a
;; renderer buffer with libc free() is NOT equivalent and is documented as
;; forbidden; this asserts we are reading the right member. A reordered or
;; resized struct cmark_mem shows up here rather than as a heap corruption.
(test-assert "allocator exposes three distinct non-null function pointers"
  (let ((slots (allocator-slots)))
    (and (= 3 (length slots))
         (for-all (lambda (s) (not (zero? s))) slots)
         (not (= (car slots) (cadr slots)))
         (not (= (cadr slots) (caddr slots)))
         (not (= (car slots) (caddr slots))))))

;; The counters are Scheme-side now. They count acquisitions this library
;; makes, which is what the ownership contract is about; they were never a
;; measure of the C heap.
(test-assert "counters are always live"
  (let ((before (live-counts)))
    (count-parser-new!)
    (let ((during (live-counts)))
      (count-parser-free!)
      (and (= (+ 1 (car before)) (car during))
           (equal? before (live-counts))))))
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-native.sps
```

Expected: unbound identifier `allocator-slots`.

- [ ] **Step 3: Replace the shim bindings**

In `native.sls`, delete these definitions (`:107-131`): `shim-compiled-version`,
`shim-runtime-version`, `raw-option-bits`, `free-buffer`, the six
`chez_cmark_count_*` bindings, and `live-parsers`/`live-roots`/`live-buffers`.

Also delete `shim-option-bits` and `bool->int` (both added in Task 2 solely for the
transition), and remove `shim-option-bits`, `shim-compiled-version`, and
`shim-runtime-version` from the export list. Add `cmark-runtime-version` and
`allocator-slots`.

**In the same step**, delete the transitional block from `tests/test-option-bits.sps` —
everything between `;; --- TRANSITIONAL` and `;; --- end transitional block`, inclusive.
It calls `shim-option-bits`, so leaving it would make that suite fail on an unbound
identifier. The block exists only to prove the Scheme table equals the shim's before
this step removes the shim's; it dies in the same commit as the thing it guards.

Insert, **after** the cmark shared objects are loaded and among the other
`foreign-procedure` definitions:

```scheme
  ;; --- version, straight from the library ------------------------------
  (define cmark-runtime-version (foreign-procedure "cmark_version" () int))

  ;; --- buffer release through cmark's own allocator ---------------------
  ;; cmark_get_default_mem_allocator returns a pointer to
  ;; struct cmark_mem { calloc; realloc; free; } -- three function pointers in
  ;; that order. The third is the ONLY correct way to release a renderer
  ;; buffer; libc free() is not equivalent and cmark's own header says so.
  ;;
  ;; Chez accepts an integer address where a name string normally goes, which
  ;; is what makes calling through a struct member possible at all. The offset
  ;; is an ABI assumption, checked by tests/test-native.sps "allocator exposes
  ;; three distinct non-null function pointers".
  (define default-mem-allocator
    (foreign-procedure "cmark_get_default_mem_allocator" () uptr))

  (define (allocator-slots)
    (let ((mem (default-mem-allocator))
          (w (foreign-sizeof 'void*)))
      (list (foreign-ref 'uptr mem 0)
            (foreign-ref 'uptr mem w)
            (foreign-ref 'uptr mem (* 2 w)))))

  (define free-buffer
    (foreign-procedure (caddr (allocator-slots)) (uptr) void))

  ;; --- tasklist checked state -------------------------------------------
  ;; `unsigned-8`, not `int`: the entry point returns C _Bool, which occupies
  ;; only the low byte of the return register with the upper bits unspecified.
  ;; Declaring `int` would read whatever happens to be there. This is the job
  ;; the shim existed to do, done by the type declaration instead.
  (define raw-tasklist-checked
    (foreign-procedure "cmark_gfm_extensions_get_tasklist_item_checked"
                       (uptr) unsigned-8))

  (define (tasklist-checked node) (not (zero? (raw-tasklist-checked node))))
```

Add `foreign-sizeof` to the `(only (chezscheme) …)` import list.

- [ ] **Step 4: Move the counters into Scheme**

Replace the deleted counter bindings with:

```scheme
  ;; --- allocation counters ----------------------------------------------
  ;; Always on. Three fixnum increments per document is not a cost worth a
  ;; build mode, and the C versions existed only so a prod build could compile
  ;; them out -- which is what `make prod` and the flavor machinery were for.
  ;; These count acquisitions THIS library makes; they were never a measure of
  ;; the C heap. tests/test-lifecycle.sps reads them to prove pairing.
  (define live-parser-count 0)
  (define live-root-count 0)
  (define live-buffer-count 0)

  (define (count-parser-new!)  (set! live-parser-count (+ live-parser-count 1)))
  (define (count-parser-free!) (set! live-parser-count (- live-parser-count 1)))
  (define (count-root-new!)    (set! live-root-count   (+ live-root-count 1)))
  (define (count-root-free!)   (set! live-root-count   (- live-root-count 1)))
  (define (count-buffer-new!)  (set! live-buffer-count (+ live-buffer-count 1)))
  (define (count-buffer-free!) (set! live-buffer-count (- live-buffer-count 1)))

  (define (live-counts)
    (list live-parser-count live-root-count live-buffer-count))
```

Delete the old `(define (live-counts) (list (live-parsers) …))` at `native.sls:284`.

- [ ] **Step 5: Collapse the version check**

Replace `version-compatible?` and the `ensure-native-loaded!` body
(`native.sls:267-283`):

```scheme
  ;; There is no compile step any more, so there is no compiled-vs-runtime skew
  ;; to detect: the only question is whether the library we loaded is one this
  ;; binding supports. version-compatible? is retained as a one-argument alias
  ;; so callers and tests keep a single name for the question.
  (define (version-compatible? runtime) (version-supported? runtime))

  (define (ensure-native-loaded!)
    (with-mutex init-mutex
      (unless initialized?
        (let ((runtime (cmark-runtime-version)))
          (unless (version-supported? runtime)
            (raise (make-cmark-version-incompatible
                    cmark-supported-version-range runtime))))
        (ensure-extensions-registered)
        (set! initialized? #t))))
```

Update the export list: `version-compatible?` stays, `shim-compiled-version` and
`shim-runtime-version` go.

- [ ] **Step 6: Update the two tests that referenced the shim**

In `tests/test-native.sps`, delete the assertions naming `shim-compiled-version`,
`shim-runtime-version`, and the Stage-2 `option-bits` structural block at `:281-300`
(now covered by `tests/test-option-bits.sps`). Replace uses of `(shim-runtime-version)`
with `(cmark-runtime-version)`.

In `tests/test-lifecycle.sps:55-59`, the check discriminated dev from prod builds.
Counters are always on now, so replace it with the unconditional form:

```scheme
(test-assert "live-counts moves during a scope"
  (let ((before (live-counts)))
    (markdown->html "# x\n" (default-cmark-options))
    ;; back to where it started: every acquire was paired
    (equal? before (live-counts))))
```

- [ ] **Step 7: Run the tests**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-native.sps
make test
```

Expected: both green, `ALL SUITES PASSED`. The differential suite is the real check here —
it renders through the new `free-buffer` roughly 400 times.

- [ ] **Step 8: Commit**

```bash
git add src/cmark/gfm/private/native.sls tests/test-native.sps tests/test-lifecycle.sps
git commit -m "feat: bind cmark directly, drop the shim's five entry points"
```

---

### Task 4: Wire discovery in; delete the shim, config.sls, and fallback/

**Files:**
- Modify: `src/cmark/gfm/private/native.sls:36-105` (resolution and loading)
- Delete: `src/cmark-gfm-shim.c`, `src/cmark-gfm-shim.h`, `src/cmark/gfm/private/config.sls`, `fallback/`, `tests/check-config.sps`, `tests/test-fallback-config.sps`, `tests/test-shim-loading.sps`
- Create: `tests/test-library-loading.sps`, `tests/preflight.sps`
- Modify: `Makefile:144` (`build` target) and `Makefile:97` (`CHEZ_LIBDIRS`) — the minimum
  to keep `make test` working; the cleanup is Task 6

**Interfaces:**
- Consumes: everything Task 1 produces; `cmark-runtime-version` from Task 3.
- Produces: `(resolve-cmark-libraries override) -> (core . ext)`, raising
  `&cmark-library-unavailable` on failure. Note the condition is renamed in Task 5; until
  then it is still spelled `make-cmark-shim-unavailable` with reasons reused as below.

**Note on ordering:** this task keeps the *old* condition name so the rename in Task 5 is a
single mechanical commit. Reasons used here are the final ones (`not-found`,
`invalid-override`, `load-failed`); `not-built` and `missing` disappear here.

- [ ] **Step 1: Write the failing test**

Create `tests/test-library-loading.sps`:

```scheme
#!r6rs
;;; Resolution behaviour that needs a real process, not synthetic listings.
;;; tests/test-discovery.sps covers the selection algorithm; this covers the
;;; wiring: that an override wins, that an invalid one raises instead of
;;; falling back, and that the default path finds a real library here.
(import (rnrs)
        (srfi :64)
        (only (chezscheme) getenv)
        (cmark gfm)
        (cmark gfm private native)
        (cmark gfm private conditions))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "library-loading")

;; The default path must have worked, or nothing below could run.
(test-assert "the default candidate search resolved a usable library"
  (string? (markdown->html "# x\n" (default-cmark-options))))

(test-assert "the loaded library is inside the supported range"
  (cmark-gfm-version-compatible?))

;; An invalid override raises and does NOT quietly fall back to the search.
;; Falling back would mean a typo in the variable silently loads a different
;; library than the one the user named.
(define (override-error str)
  (guard (e ((cmark-shim-unavailable? e) (cmark-shim-unavailable-reason e))
            (#t 'wrong-condition))
    (resolve-cmark-libraries str)
    'no-raise))

(test-equal "relative path override"    'invalid-override (override-error "a:b"))
(test-equal "single entry override"     'invalid-override (override-error "/usr/lib/libcmark-gfm.so"))
(test-equal "empty override"            'invalid-override (override-error ""))
(test-equal "nonexistent files"         'invalid-override
  (override-error "/nonexistent/libcmark-gfm.so:/nonexistent/libcmark-gfm-extensions.so"))

(test-end "library-loading")
(exit (if (zero? (test-runner-fail-count runner)) 0 1))
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
CHEZSCHEMELIBDIRS=src:fallback:tests:build/scheme-libs chez --program tests/test-library-loading.sps
```

Expected: unbound identifier `resolve-cmark-libraries`.

- [ ] **Step 3: Replace the resolution block in native.sls**

Delete `native.sls:46-105` — `regular-file?` stays, but `resolve-shim-path`, `load-shim`,
`shim-file`, `cmark-loaded`, and `shim-loaded` are replaced wholesale by:

```scheme
  ;; --- library resolution ------------------------------------------------
  ;; ABSOLUTE PATHS ONLY, NEVER LEAFNAMES. `(load-shared-object
  ;; "libcmark-gfm.dylib")` resolves to macOS's own copy in the dyld shared
  ;; cache at /usr/lib/libcmark-gfm.dylib -- a different build, with no headers
  ;; shipped anywhere, that Apple may change on any OS update, and which
  ;; currently reports the same version as the pinned one so nothing would
  ;; notice. Three properties keep it unreachable: it has no filesystem entry,
  ;; its name is unversioned, and there is no extensions library beside it.
  ;; Do not "simplify" this into a soname fallback.
  (define (regular-file? path)
    (and (file-exists? path) (file-regular? path)))

  (define (resolve-cmark-libraries override)
    (if override
        (let-values (((status payload) (parse-library-override override regular-file?)))
          (if (eq? status 'ok)
              payload
              (raise (make-cmark-shim-unavailable override 'invalid-override))))
        (let* ((platform (current-platform))
               (candidates (default-candidate-directories
                             platform (current-machine) directory-names directory?)))
          (let-values (((status payload)
                        (select-cmark-libraries directory-names directory?
                                                candidates
                                                cmark-supported-version-range
                                                platform)))
            (cond
              ((eq? status 'found) payload)
              ((eq? status 'out-of-range)
               (raise (make-cmark-version-incompatible
                       cmark-supported-version-range payload)))
              (else
               (raise (make-cmark-shim-unavailable #f 'not-found))))))))

  ;; directory-list yields names; some Chez versions yield (name . type) pairs.
  (define (directory-names dir)
    (map (lambda (entry) (if (pair? entry) (car entry) entry))
         (directory-list dir)))

  (define (directory? path) (file-directory? path))

  (define (load-library path)
    (guard (e (#t (raise (make-cmark-shim-unavailable path 'load-failed))))
      (load-shared-object path)))

  (define resolved-libraries
    (resolve-cmark-libraries (getenv "CHEZ_CMARK_GFM_LIBS")))

  ;; These two are DEFINITIONS, not expressions, so they run before every
  ;; foreign-procedure definition below -- see the ORDERING NOTE at the top of
  ;; this file. Core before extensions: on Linux the symbols of a dlopen'd
  ;; library's dependencies are not placed in the global namespace, so the
  ;; extensions library must find an already-loaded core.
  (define core-loaded (load-library (car resolved-libraries)))
  (define extensions-loaded (load-library (cdr resolved-libraries)))
```

Update the library's imports: drop `(cmark gfm private config)`, add
`(cmark gfm private discovery)`, and add `directory-list` and `file-directory?` to the
`(only (chezscheme) …)` list. Move `cmark-supported-version-range` into `native.sls` as a
plain definition, with the comment it carried in `config.sls`:

```scheme
  ;; Fixes cmark's major/minor at 0.29 and leaves the patch and gfm-patch
  ;; numbers free. A runtime library outside this range raises
  ;; &cmark-version-incompatible before any parse happens.
  (define cmark-supported-version-range '(#x001d0000 . #x001dffff))
```

Export `resolve-cmark-libraries` and `cmark-supported-version-range`.

- [ ] **Step 4: Delete the shim, the config, and the obsolete suites**

```bash
git rm src/cmark-gfm-shim.c src/cmark-gfm-shim.h
git rm -r fallback
git rm src/cmark/gfm/private/config.sls 2>/dev/null || rm -f src/cmark/gfm/private/config.sls
git rm tests/check-config.sps tests/test-fallback-config.sps tests/test-shim-loading.sps
```

`config.sls` is gitignored, so `git rm` may report it as untracked; the `||` branch
handles that.

(The transitional block in `tests/test-option-bits.sps` was already deleted in Task 3,
in the same step that removed `shim-option-bits`. Nothing to do here.)

- [ ] **Step 5: Run the tests**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-library-loading.sps
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-discovery.sps
```

Note `fallback` is gone from the path. Expected: both green.

- [ ] **Step 6: Confirm no C artifact is required**

```bash
rm -rf build/lib && CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-render.sps
```

Expected: green. This is the whole point of the change — rendering with no compiled shim
anywhere.

- [ ] **Step 7: Make `make` work again — the minimum, not the cleanup**

Deleting the shim sources breaks `Makefile:144` (`build: $(SHIM) $(CONFIG_SLS)`), and
`test: build deps check-pins` depends on it — so `make test` would fail from here until
Task 6. Fix only what is needed to keep the suite green; Task 6 removes the dead
machinery.

Create `tests/preflight.sps`:

```scheme
#!r6rs
;;; `make build` in 2.0. There is nothing to compile, so build answers the
;;; question the install contract actually raises: is this machine set up, and
;;; which library would be loaded?
;; `exit` comes from (rnrs), NOT (chezscheme) -- importing it from both raises
;; "multiple definitions for exit in body". See Global Constraints.
(import (rnrs)
        (only (chezscheme) printf getenv)
        (cmark gfm)
        (cmark gfm private native)
        (cmark gfm private conditions))

(guard (e ((cmark-library-unavailable? e)
           (printf "chez-cmark-gfm: no usable libcmark-gfm (~a)\n"
                   (cmark-library-unavailable-reason e))
           (printf "  install it with:  apt install cmark-gfm   (Debian/Ubuntu)\n")
           (printf "                    brew install cmark-gfm  (macOS)\n")
           (printf "  or name both libraries in CHEZ_CMARK_GFM_LIBS.\n")
           (exit 1))
          ((cmark-version-incompatible? e)
           (printf "chez-cmark-gfm: found cmark-gfm ~x, outside the supported range\n"
                   (cmark-version-incompatible-runtime e))
           (exit 1)))
  (let ((libs (resolve-cmark-libraries (getenv "CHEZ_CMARK_GFM_LIBS"))))
    (printf "cmark-gfm ~a\n" (cmark-gfm-version))
    (printf "  core: ~a\n" (car libs))
    (printf "  ext:  ~a\n" (cdr libs))
    (exit 0)))
```

**Note on the condition names:** Task 5 renames `&cmark-shim-unavailable` to
`&cmark-library-unavailable`. At this point in the sequence the old spelling is still in
force, so write `cmark-shim-unavailable?` / `cmark-shim-unavailable-reason` here and let
Task 5's mechanical rename sweep this file with the rest. Likewise
`cmark-version-incompatible-runtime` is already correct — only the `compiled`→`supported`
accessor changes in Task 5, and this file does not use it.

Then two minimal `Makefile` edits — nothing else:

```make
build:
	@CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ) --program tests/preflight.sps
```

```make
CHEZ_LIBDIRS := src:tests:$(SRFI_LIBS)
```

Leave `prod`, `check-prod`, `check-config`, `FLAVOR`, `mode-flip-relink`, and the
`$(SHIM)`/`$(CONFIG_SLS)` variable definitions alone — they are now unreachable from
`build` but harmless, and Task 6 removes them. `make check-config` and `make prod` will
fail until then; neither is on `make test`'s path.

- [ ] **Step 8: Run the full suite through make**

```bash
make test
```

Expected: `ALL SUITES PASSED`, with `make build` printing the two resolved absolute paths
instead of compiling anything.

- [ ] **Step 9: Commit**

```bash
git add -A src tests Makefile
git commit -m "feat: resolve libcmark-gfm at runtime; delete the C shim and fallback config"
```

---

### Task 5: Rename the condition and reshape the version condition

**Files:**
- Modify: `src/cmark/gfm/private/conditions.sls:26-28,50-51,90-100`
- Modify: `src/cmark/gfm.sls:57,62-63`
- Modify: `src/cmark/gfm/private/native.sls` (all raise sites)
- Modify: `tests/test-conditions.sps:19-31,52-53,72`, `tests/test-native.sps:202-204`, `tests/test-library-loading.sps`
- Modify: `examples/coverage-exemptions.scm:21,45,51,61,65`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: `&cmark-library-unavailable`, `make-cmark-library-unavailable`,
  `cmark-library-unavailable?`, `cmark-library-unavailable-path`,
  `cmark-library-unavailable-reason`; and
  `cmark-version-incompatible-supported` replacing `cmark-version-incompatible-compiled`.

- [ ] **Step 1: Write the failing test**

In `tests/test-conditions.sps`, replace the three `make-cmark-version-incompatible` uses
and the two `make-cmark-shim-unavailable` uses:

```scheme
(test-assert "version-incompatible is a cmark-error"
  (guard (e ((cmark-error? e) #t) (#t #f))
    (raise (make-cmark-version-incompatible '(#x001d0000 . #x001dffff) #x001e0000))))

(test-equal "version-incompatible carries the supported range"
  '(#x001d0000 . #x001dffff)
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-supported e)))
    (raise (make-cmark-version-incompatible '(#x001d0000 . #x001dffff) #x001e0000))))

(test-equal "version-incompatible carries what was actually found"
  #x001e0000
  (guard (e ((cmark-version-incompatible? e)
             (cmark-version-incompatible-runtime e)))
    (raise (make-cmark-version-incompatible '(#x001d0000 . #x001dffff) #x001e0000))))

(test-equal "library-unavailable carries its path"
  "/nope/libcmark-gfm.so.0.29.0.gfm.13"
  (guard (e ((cmark-library-unavailable? e) (cmark-library-unavailable-path e)))
    (raise (make-cmark-library-unavailable "/nope/libcmark-gfm.so.0.29.0.gfm.13"
                                           'load-failed))))

(test-equal "library-unavailable carries its reason" 'not-found
  (guard (e ((cmark-library-unavailable? e) (cmark-library-unavailable-reason e)))
    (raise (make-cmark-library-unavailable #f 'not-found))))
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
CHEZSCHEMELIBDIRS=src:tests:build/scheme-libs chez --program tests/test-conditions.sps
```

Expected: unbound identifier `make-cmark-library-unavailable`.

- [ ] **Step 3: Rename in conditions.sls**

Replace the export block at `:26-28`:

```scheme
          &cmark-library-unavailable make-cmark-library-unavailable
          cmark-library-unavailable? cmark-library-unavailable-path
          cmark-library-unavailable-reason
```

Replace the definition at `:90-100`, including the comment block above it:

```scheme
  ;; Raised when the cmark shared objects cannot be resolved or loaded.
  ;;   'not-found        -- no candidate directory held a matched core +
  ;;                        extensions pair at a supported version, and
  ;;                        CHEZ_CMARK_GFM_LIBS was not set. `path` is #f:
  ;;                        there is no single path to name.
  ;;   'invalid-override -- CHEZ_CMARK_GFM_LIBS is set but is not two absolute
  ;;                        paths to existing regular files, one core and one
  ;;                        extensions library
  ;;   'load-failed      -- load-shared-object raised on a validated path
  ;;
  ;; 'invalid-override deliberately covers several causes at once (wrong entry
  ;; count, a relative path, an absent file, two libraries of the same kind)
  ;; because the remedy is identical for all of them: name both libraries, by
  ;; absolute path.
  (define-condition-type &cmark-library-unavailable &cmark-error
    make-cmark-library-unavailable cmark-library-unavailable?
    (path   cmark-library-unavailable-path)
    (reason cmark-library-unavailable-reason))
```

Replace the `&cmark-version-incompatible` field at `:50-51`:

```scheme
    (supported cmark-version-incompatible-supported)
    (runtime   cmark-version-incompatible-runtime))
```

and its export at `:12`: `cmark-version-incompatible-supported`.

- [ ] **Step 4: Update every call site**

```bash
grep -rln 'cmark-shim-unavailable' src tests examples
```

In each file, replace `cmark-shim-unavailable` with `cmark-library-unavailable` — this
covers `&cmark-…`, `make-…`, `…?`, `…-path`, and `…-reason` in one substitution:

```bash
grep -rl 'cmark-shim-unavailable' src tests examples \
  | xargs sed -i '' 's/cmark-shim-unavailable/cmark-library-unavailable/g'
```

Then the version accessor:

```bash
grep -rl 'cmark-version-incompatible-compiled' src tests examples \
  | xargs sed -i '' 's/cmark-version-incompatible-compiled/cmark-version-incompatible-supported/g'
```

On Linux, `sed -i` takes no argument: use `sed -i 's/…/…/g'`.

- [ ] **Step 5: Verify nothing was missed**

```bash
grep -rn 'shim' src tests examples --include='*.sls' --include='*.sps' --include='*.scm'
```

Expected: no matches. Any hit is a missed rename or a stale comment; fix it.

- [ ] **Step 6: Run the tests**

```bash
make test
```

Expected: `ALL SUITES PASSED`. The export-coverage gate in
`examples/coverage-exemptions.scm` fails loudly if a public name was renamed without
updating it, which is the intended safety net here.

- [ ] **Step 7: Commit**

```bash
git add -A src tests examples
git commit -m "refactor!: rename &cmark-shim-unavailable to &cmark-library-unavailable"
```

---

### Task 6: Makefile cleanup — remove the dead shim machinery

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `tests/preflight.sps` and the reworked `build` target, both created in Task 4.
- Produces: nothing new. This task only deletes what the shim's removal made unreachable.

**Scope note.** Task 4 already made `make build` a preflight and dropped `fallback` from
`CHEZ_LIBDIRS`, because `make test` depends on `build` and would otherwise have been
broken from Task 4 through this task. What remains here is removing machinery that is now
unreachable but still present, and renaming the purity gate's variable. `make test` is
green before and after this task; the observable change is that `make prod` and
`make check-config` stop existing rather than failing.

- [ ] **Step 1: Rewrite the Makefile targets**

Delete from `Makefile`: `SHIM`, `CONFIG_SLS`, `FLAVOR`, `HAVE_PKG`, `CMARK_CFLAGS`,
`CMARK_LIBS`, `CMARK_DLLS`, `CMARK_LIBDIR`, the `$(SHIM):` rule, the `$(CONFIG_SLS):`
rule, `mode-flip-relink`, `prod`, `check-prod`, and `check-config`.

Keep `CMARK_CLI` — the differential suite needs it — but source it from the vendored
build or `PATH` only:

```make
CMARK_CLI ?= cmark-gfm
```

**Already done in Task 4, do not redo:** the `build` target is already the preflight, and
`CHEZ_LIBDIRS` already reads `src:tests:$(SRFI_LIBS)`. Confirm both, then add the comment
above `build` if Task 4 did not:

```make
# There is no compiled artifact in 2.0. `build` answers the question the
# install contract raises instead: is a usable libcmark-gfm present, and which
# one would be loaded? Kept as a canonical target because that question is
# worth one command.
```

Update `.PHONY`:

```make
.PHONY: all build deps check-pins check-purity examples dev test test-memory vendor clean deps-info
```

In `check-purity`, rename the poisoned variable:

```make
	  if CHEZ_CMARK_GFM_LIBS=/nonexistent CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
```

and update the two message lines that name `CHEZ_CMARK_GFM_SHIM`.

**No change needed for the new suites.** `Makefile:98` is
`TESTS := $(wildcard tests/test-*.sps)`, so `test-discovery.sps`, `test-option-bits.sps`,
and `test-library-loading.sps` are picked up automatically. `tests/preflight.sps` is
deliberately *not* named `test-*` so the wildcard does not run it as a suite.

Note that `test: build deps check-pins` now means `make test` runs the preflight first —
a missing libcmark-gfm fails with the install instructions rather than with an obscure
suite error. That is desirable; keep the dependency.

Update `clean` to drop the deleted variable:

```make
clean:
	rm -rf $(BUILD_DIR)
```

- [ ] **Step 2: Verify every canonical target**

```bash
make clean && make build && make test && make check-purity && make examples
```

Expected: all four succeed; `make build` prints the resolved paths; `ALL SUITES PASSED`.

- [ ] **Step 3: Verify a genuinely clean tree needs no compiler**

```bash
git clean -xdn | head -20
```

Review what would be removed, then in a scratch clone:

```bash
git clone --no-local . /tmp/shimless-check && cd /tmp/shimless-check \
  && git checkout feat/shimless-ffi && make deps && make build && make test
```

Expected: green with no C compilation anywhere in the output. `make deps` still
initialises the submodule for the corpus and the CLI oracle.

- [ ] **Step 4: Commit**

```bash
git add Makefile tests/preflight.sps
git commit -m "build: make build a discovery preflight; drop shim and flavor machinery"
```

---

### Task 7: CI

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `make build`, `make test` from Task 6.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the acquisition matrix**

The two former rows (pkg-config vs vendored) no longer name distinct code paths. Replace
with rows that differ in **how cmark-gfm was obtained**:

- macOS: `brew install chezscheme cmark-gfm` — drop `cmake` and `pkg-config` from the
  install line for this job. Add a step asserting no compiler ran:
  ```yaml
  - name: assert no C artifact was produced
    run: test ! -e build/lib || { echo "a shared object was built; 2.0 compiles nothing" >&2; exit 1; }
  ```
- Linux: `apt-get install -y chezscheme cmark-gfm` plus `cmake build-essential` **only**
  for the `deps`/oracle step, with a comment saying they are for the vendored corpus and
  CLI, not for building anything of ours.

- [ ] **Step 2: Add the not-found job**

```yaml
  no-library:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install Chez only, deliberately no cmark-gfm
        run: sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends chezscheme
      - name: build must fail with a message naming the remedy
        run: |
          set +e
          out=$(make build 2>&1); status=$?
          set -e
          echo "$out"
          test $status -ne 0 || { echo "expected failure, got success" >&2; exit 1; }
          echo "$out" | grep -q 'apt install cmark-gfm' \
            || { echo "diagnostic did not name the remedy" >&2; exit 1; }
```

- [ ] **Step 3: Add the Akku job**

```yaml
  akku-install:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install prerequisites
        run: sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends chezscheme cmark-gfm akku
      - name: install from the manifest and import with nothing set
        run: |
          akku install
          . .akku/bin/activate
          echo '(import (cmark gfm)) (display (markdown->html "# ok\n" (default-cmark-options)))' > /tmp/t.sps
          chezscheme --program /tmp/t.sps | grep -q '<h1>ok</h1>'
```

This job is the exit criterion from spec §1. If `akku` is unavailable from apt on the
runner image, install it from its release tarball rather than skipping the job — a skipped
exit-criterion check is worse than no check.

- [ ] **Step 4: Update the support-matrix assertion**

The README table's acquisition column changes (§7.6). Update whichever CI step asserts the
table so it compares against Homebrew/apt rather than pkg-config/vendored.

- [ ] **Step 5: Push and confirm CI is green**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: assert no compiler runs, and that akku install works end to end"
git push -u origin feat/shimless-ffi
```

Expected: every job green, including `no-library` and `akku-install`.

---

### Task 8: Documentation, ADRs, and release

**Files:**
- Modify: `README.org`, `CHANGELOG.md`, `NOTICE`, `Akku.manifest`, `packaging/debian-prereqs.txt`
- Create: `.plans/decisions/0015-bind-libcmark-gfm-directly.md`, `.plans/decisions/0016-paired-versioned-library-discovery.md`, `.plans/decisions/0017-no-akku-scripts.md`

**Interfaces:**
- Consumes: the finished implementation.
- Produces: the 2.0.0 release.

- [ ] **Step 1: Write the three ADRs**

Follow the existing format exactly (`.plans/decisions/0014-fallback-config-shadowing.md` is
the closest model): Status / Date / Scope / Related, then Context, Decision, Consequences,
and rejected alternatives.

- **ADR-0015** — binding libcmark-gfm directly. Amends ADR-0001 (both acquisition paths
  collapse to "system package") and ADR-0002's shim rationale. Must record the allocator
  struct-offset assumption (spec §11.2) and that discovery is a search, reversing
  `native.sls`'s former never-search wording (spec §11.5).
- **ADR-0016** — paired versioned discovery. All four clauses of spec §3.1, with the
  double-load hazard as the motivating failure and the `gfm.9`-over-`gfm.13` string-sort
  result as the concrete evidence for numeric comparison.
- **ADR-0017** — no Akku `scripts` clause. Spec §9: the approval prompt reaches downstream
  dependants, and `run-cmd` ignores exit status.

- [ ] **Step 2: Rewrite the README install section**

Replace **Prerequisites**, **Build**, **Static versus dynamic linking**, **Installing**,
**Running**, and the `CHEZ_CMARK_GFM_SHIM` section. The two install one-liners are
`apt install cmark-gfm` and `brew install cmark-gfm`; both pull core and extensions at
matching versions and the CLI the differential suite uses. `CHEZSCHEMELIBDIRS` is now
`src` alone. Add the RHEL/Fedora/Alpine subsection **verbatim from spec §8.2** — it is
already written as `.org`.

Update the supported matrix per spec §7.6, and the `CHEZ_CMARK_GFM_SHIM` section becomes
`CHEZ_CMARK_GFM_LIBS`, keeping the validated-never-searched framing for the override.

Keep it terse; depth is deferred to a future `docs/` tree.

- [ ] **Step 3: Update NOTICE, the manifest, and the prereqs**

- `NOTICE`: reframe cmark-gfm as a **development** dependency (vendored for the test
  oracle) rather than implying the runtime links a bundled copy. The license text stays.
- `Akku.manifest`: bump to `2.0.0`, add `homepage`, add **no** `scripts` and **no**
  `depends` key. `tests/test-manifest-deps.sps` asserts both; run it.
- `packaging/debian-prereqs.txt`: split into a runtime list (`cmark-gfm`) and a
  development list (`cmake`, `build-essential`, `pkg-config`), preserving the
  "one copy, deliberately" property — `README.org` and `ci.yml` both read this file.

- [ ] **Step 4: Write the CHANGELOG entry**

A `## 2.0.0` section with a **Breaking changes** table mapping every old name to its new
one:

| Removed / changed | Replacement |
|---|---|
| `&cmark-shim-unavailable` and its accessors | `&cmark-library-unavailable`, same shape |
| reasons `not-built`, `missing` | `not-found` |
| `cmark-version-incompatible-compiled` | `cmark-version-incompatible-supported`, now the `(lo . hi)` range |
| `CHEZ_CMARK_GFM_SHIM` | `CHEZ_CMARK_GFM_LIBS`, two absolute paths |
| `CHEZSCHEMELIBDIRS=src:fallback` | `CHEZSCHEMELIBDIRS=src` |
| `make prod`, `make check-prod`, `make check-config` | removed; `make build` is now a preflight |

Plus **Added** (Akku install support, `tests/test-discovery.sps`) and **Removed** (the C
shim, `fallback/`, the CMake shim build).

- [ ] **Step 5: Verify everything together**

```bash
make clean && make build && make test && make check-purity && make examples && make test-memory
```

Expected: all green. `make test-memory` is the ownership proof and must not be skipped —
it is the only evidence that the new `free-buffer` releases what it should.

- [ ] **Step 6: Confirm the documented commands actually work**

Run each command the README now tells a user to run, in the scratch clone from Task 6
Step 5. A README that documents a command nobody ran is how the 1.0 "10.4.1 or later"
claim happened.

- [ ] **Step 7: Commit and tag**

```bash
git add -A
git commit -m "docs: 2.0 install contract, three ADRs, and the CHANGELOG entry"
git tag -a v2.0.0 -m "2.0.0: shimless FFI, installable via Akku"
```

Do **not** push the tag until the PR is merged.

---

## Self-Review

**Spec coverage.** Every numbered spec section maps to a task: §2 → Tasks 2–3; §3 → Tasks 1
and 4; §4 → Tasks 3 and 5; §5 → Task 5; §6 → Tasks 4 and 6; §7 → Tasks 1, 2, 3, 6, 7;
§8 → Task 8; §9 → Task 8 Step 3; §10 ordering → the task order itself; §12 → Task 8 Step 1.

**Two spec items deliberately deferred, and where they go instead.** Spec §7.4's allocator
round-trip landed in Task 3 Step 1 as `allocator-slots` rather than in `test-stress.sps`,
because the assertion is about struct layout and belongs beside the binding. Spec §11.4's
stale-`/usr/local` behaviour has no test — it is emergent from first-directory-wins, which
Task 1 does cover ("first directory with a pair wins").

**Names checked across tasks.** `resolve-cmark-libraries` (Task 4) is used by Task 6's
preflight. `option-bits` keeps its Task-2 signature through Task 3. `live-counts` returns a
three-element list in Tasks 3 and 8. `select-cmark-libraries` and `parse-library-override`
return two values everywhere they appear. `cmark-library-unavailable-reason` is spelled
identically in Tasks 4, 5, and 6 — note Task 4 deliberately still writes
`cmark-shim-unavailable`, because the rename is Task 5's single mechanical commit.

**One known rough edge.** Task 5's `sed -i ''` is macOS syntax; the step says so and gives
the GNU form. An implementer on Linux who copies blindly will get an error immediately
rather than a silent corruption.
