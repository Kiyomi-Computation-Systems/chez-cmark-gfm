# Publishing Preparation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make this repository suitable for a public open-source release: a
~140-line `README.org`, eight user-facing pages under `docs/`, an install
path for non-Akku users, and contributor scaffolding.

**Architecture:** Reference material moves out of `README.org` into
`docs/*.md`, which is **user-facing documentation only** — designs,
decision records, and mutation logs stay in `.plans/`. Two Makefile checks
(`check-help`, `check-install`) keep the new machinery from rotting. The
CI greps and preflight message that name `README.org` are repointed in the
same commit that gives them a new target.

**Tech Stack:** GNU Make, POSIX sh, Chez Scheme 9.5.8+, Org-mode
(`README.org`), Markdown (`docs/`), GitHub Actions.

**Design spec:** `.plans/2026-08-22-publishing-prep-design.md`

## Global Constraints

- **`docs/` is user-facing documentation only.** No designs, ADRs, or
  mutation logs. Those stay in `.plans/`.
- **Nothing compiles.** Release 2.0 has no C shim and no generated
  `config.sls` (ADR-0015). No task may add a build step, and `make install`
  copies `.sls` files only.
- **`CHEZSCHEMELIBDIRS` replaces the search path**, silently dropping `.`.
  Every documented export line ends with a **trailing colon**. Verified:
  `CHEZSCHEMELIBDIRS=/tmp/foo` → `(("/tmp/foo" . "/tmp/foo"))`;
  `CHEZSCHEMELIBDIRS=/tmp/foo:` → `(("/tmp/foo" ...) ("." . "."))`.
- **`CHEZ_CMARK_GFM_LIBS` must be UNSET, never set empty.** `(getenv ...)`
  returns `""` for an empty-but-set variable, which is truthy in Scheme, so
  `native.sls` takes the override branch and raises
  `&cmark-library-unavailable` reason `invalid-override`. Use
  `env -u CHEZ_CMARK_GFM_LIBS`.
- **A load-time probe must CALL into the library, not merely import it.**
  Chez instantiates an imported library's body only when a binding is
  *referenced* (AGENTS.md trap 4).
- **Supported version range:** `0.29.0.gfm.x`, i.e.
  `(#x001d0000 . #x001dffff)` in `src/cmark/gfm/private/native.sls`.
- **Chez floor is 9.5.8.** Binary is `chez` on macOS, `chezscheme` on
  Debian/Ubuntu.
- **Every new check gets a mutation.** Break the guarded thing, watch the
  check fail by name, record it in
  `.plans/publishing-prep-mutation-log.md`. A check nobody has watched fail
  is assumed broken (AGENTS.md trap 1).
- **`.PHONY` MUST stay on ONE physical line.** `check-help` extracts targets
  with `awk '/^\.PHONY:/ ...'`, which matches a single physical line and has
  no continuation handling. A backslash-wrapped `.PHONY` yields
  ` alpha beta \` — every target on a continuation line becomes invisible to
  the check, and `\` becomes a bogus pseudo-target. Verified during Task 1.
- **Conventional Commits**, branch `docs/publishing-prep`.

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `docs/installing.md` | Every acquisition path, the supported matrix, `CHEZ_CMARK_GFM_LIBS`, discovery order |
| `docs/usage.md` | The four renderers and capability queries |
| `docs/options.md` | `cmark-options` reference |
| `docs/ast.md` | Node model and resource limits |
| `docs/memory.md` | Ownership contract |
| `docs/sxml.md` | SXML adapter, the mapping, **and serializing** |
| `docs/errors.md` | Condition hierarchy |
| `docs/building.md` | Make targets and test suites |
| `CONTRIBUTING.md` | Setup, gates, conventions |
| `SECURITY.md` | Private vulnerability reporting |
| `.github/ISSUE_TEMPLATE/bug_report.md` | Bug template |
| `.github/ISSUE_TEMPLATE/feature_request.md` | Feature template |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR checklist |
| `tests/install-probe.sps` | Proves an installed tree renders |
| `.plans/publishing-prep-mutation-log.md` | Mutation evidence |

**Modified:** `README.org` (642 → ~140 lines), `Makefile`, `NOTICE`,
`.github/workflows/ci.yml`, `tests/preflight.sps`, `CHANGELOG.md`.

## Source Line Map

`README.org` at HEAD (`cb895bc`), for the move tasks:

| Lines | Section | Destination |
|---|---|---|
| 11-48 | Prerequisites | `docs/installing.md` |
| 49-78 | Supported matrix | `docs/installing.md` |
| 79-115 | Installing | `docs/installing.md` |
| 116-148 | RHEL, Fedora, and Alpine | `docs/installing.md` |
| 149-178 | Build | `docs/installing.md` |
| 179-200 | Running | README (condensed) |
| 201-223 | `CHEZ_CMARK_GFM_LIBS` | `docs/installing.md` |
| 224-251 | Tests | `docs/building.md` |
| 252-279 | Usage | `docs/usage.md` |
| 280-305 | Options | `docs/options.md` |
| 306-322 | Memory ownership | `docs/memory.md` |
| 323-394 | The AST | `docs/ast.md` |
| 395-625 | SXML through "Your serializer, not ours" | `docs/sxml.md` |
| 626-643 | Errors | `docs/errors.md` |

---

### Task 1: Makefile help and check-help

**Files:**
- Modify: `Makefile:59` (the `.PHONY` line) and each target
- Create: `.plans/publishing-prep-mutation-log.md`

**Interfaces:**
- Consumes: nothing
- Produces: the `## ` description convention every later Makefile target
  must follow, and `check-help` which enforces it

- [ ] **Step 1: Write the failing check**

Add to `Makefile`, immediately after the `.PHONY` line:

```make
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# `help` cannot rot: a .PHONY target added without a `## ` description on
# its own line fails this check. Lifted from chez-libuv, which runs the
# same pair.
check-help: ## Fail if any .PHONY target is undocumented in `make help`
	@missing=0; \
	targets=$$(awk '/^\.PHONY:/ { $$1 = ""; print }' Makefile); \
	for t in $$targets; do \
	  grep -qE "^$$t:.*## " Makefile || { \
	    echo "check-help: target '$$t' has no '## ' description on its own line" >&2; \
	    missing=1; \
	  }; \
	done; \
	exit $$missing
```

Update the `.PHONY` line at `Makefile:59` to:

```make
.PHONY: all build deps check-pins check-purity check-help examples dev help test test-memory vendor clean deps-info
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `make check-help`

Expected: FAIL, listing every existing target — `all`, `build`, `deps`,
`check-pins`, `check-purity`, `examples`, `dev`, `test`, `test-memory`,
`vendor`, `clean`, `deps-info` — each as
`check-help: target 'X' has no '## ' description on its own line`.

- [ ] **Step 3: Add a description to every existing target**

Append `## <text>` to each target line. The text after `## ` is what
`make help` prints, so it must read as a sentence to someone who has never
seen this repo:

```make
all: build ## Alias for build
deps-info: ## Report which cmark-gfm CLI the differential suites will use
build: ## Verify a usable libcmark-gfm is present and name which one loads
check-pins: ## Verify the submodule commits and Akku.lock name the same revisions
check-purity: build deps ## Verify the pure suites import no native code
deps: ## Vendor chez-srfi and the wak libraries into build/scheme-libs
vendor: ## Build the vendored cmark-gfm (dev dependency: corpus, header, CLI oracle)
dev: build deps ## Start a REPL with the library path set
test: build deps check-pins ## Run every tests/test-*.sps suite
test-memory: build deps check-pins ## Run the suites under Valgrind (Linux) or ASan (macOS)
clean: ## Remove build/ and tests/tmp
examples: build ## Run every examples/*.sps and diff against examples/expected/
```

Do not otherwise change any recipe. Leave every existing comment block
above these targets exactly where it is.

- [ ] **Step 4: Run the check to verify it passes**

Run: `make check-help && make help`

Expected: `check-help` exits 0 silently; `help` prints one cyan-padded
line per target.

- [ ] **Step 5: Mutate — prove check-help can fail**

Append a bare target and add it to `.PHONY`:

```make
.PHONY: ... deps-info scratch
scratch:
	@true
```

Run: `make check-help`

Expected: FAIL with
`check-help: target 'scratch' has no '## ' description on its own line`.
Then remove both lines and confirm `make check-help` passes again.

- [ ] **Step 6: Record the mutation**

Create `.plans/publishing-prep-mutation-log.md`:

```markdown
# Publishing-prep mutation log

Evidence that each check added by
`.plans/2026-08-22-publishing-prep-design.md` can fail. Per AGENTS.md, a
test is finished when it has been watched to fail, not when it passes.

## Mutation A — check-help notices an undocumented target

**Guards:** `make help` lists every target.
**Mutation:** added `scratch:` to `.PHONY` and as a bare target with no
`## ` description.
**Result:** FAILED, by name —
`check-help: target 'scratch' has no '## ' description on its own line`.
**Reverted:** yes; `make check-help` green again.
```

- [ ] **Step 7: Commit**

```bash
git add Makefile .plans/publishing-prep-mutation-log.md
git commit -m "feat(make): add help and check-help targets

Every .PHONY target now carries a '## ' description, and check-help fails
when one does not -- so \`make help\` cannot drift out of date silently.
Pattern lifted from chez-libuv.

Mutation A recorded: an undocumented target fails check-help by name."
```

---

### Task 2: Makefile install, uninstall, and check-install

**Files:**
- Modify: `Makefile` (variables near the top, targets at the end, `.PHONY`)
- Create: `tests/install-probe.sps`
- Modify: `.plans/publishing-prep-mutation-log.md`

**Interfaces:**
- Consumes: the `## ` convention from Task 1
- Produces: `make install PREFIX=<dir>`, installing to
  `$(DESTDIR)$(PREFIX)/lib/chez-cmark-gfm/cmark/**.sls`, which
  `docs/installing.md` (Task 3) documents

- [ ] **Step 1: Write the probe**

Create `tests/install-probe.sps`:

```scheme
#!r6rs
;;; Proves an INSTALLED tree is importable and actually renders. TEST ONLY.
;;;
;;; Run by `make check-install` with CHEZSCHEMELIBDIRS pointing at nothing
;;; but the install directory, and CHEZ_CMARK_GFM_LIBS unset.
;;;
;;; This program CALLS markdown->html rather than merely importing
;;; (cmark gfm), and that is the whole point. Chez instantiates an imported
;;; library's body only when one of its bindings is REFERENCED, so an
;;; import-only probe never runs native.sls's body, never performs
;;; discovery, and reports success against a tree that cannot possibly
;;; work. tests/load-failed-probe.sps calls into the library for the same
;;; reason. See AGENTS.md, "Chez invokes an imported library's body only
;;; when a binding is referenced".
(import (rnrs) (cmark gfm))

;; Expect a value only success can produce: the exact rendered string, not
;; a truthiness check. A missing key, a defaulting accessor, and a
;; swallowed exception all yield #f; none of them yields "<h1>ok</h1>\n".
(let ((out (markdown->html "# ok\n" (default-cmark-options))))
  (unless (string=? out "<h1>ok</h1>\n")
    (display "install-probe: unexpected render: ")
    (write out)
    (newline)
    (exit 1)))

(display "install-probe: the installed tree imports and renders\n")
(exit 0)
```

- [ ] **Step 2: Add check-install and run it to verify it fails**

Add to `Makefile` (targets, near `examples`):

```make
# CHEZ_CMARK_GFM_LIBS is UNSET here, not set empty. `(getenv "X")` returns
# "" for an empty-but-set variable, and "" is truthy in Scheme, so
# resolve-cmark-libraries would take the override branch and raise
# &cmark-library-unavailable reason invalid-override -- a failure that
# looks like a broken install but is really a broken check.
check-install: ## Install to a temp prefix and prove (cmark gfm) loads from it alone
	@set -eu; \
	tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT INT TERM; \
	$(MAKE) --no-print-directory install PREFIX="$$tmp" >/dev/null; \
	echo "=== check-install: importing from $$tmp/lib/chez-cmark-gfm alone ==="; \
	if env -u CHEZ_CMARK_GFM_LIBS \
	     CHEZSCHEMELIBDIRS="$$tmp/lib/chez-cmark-gfm" \
	     $(CHEZ) --program tests/install-probe.sps; then \
	  echo "check-install: an installed tree imports and renders"; \
	else \
	  echo "check-install: FAILED -- the tree installed at $$tmp could not" >&2; \
	  echo "render a document with CHEZSCHEMELIBDIRS naming only that" >&2; \
	  echo "directory. Check the install target's copy step." >&2; \
	  exit 1; \
	fi
```

Run: `make check-install`

Expected: FAIL with `No rule to make target 'install'` — the target does
not exist yet.

- [ ] **Step 3: Implement install and uninstall**

Add near the top of `Makefile`, after `CMARK_CLI ?= cmark-gfm`:

```make
# Install prefix for `make install`. Chez has NO system-wide R6RS library
# directory -- (library-directories) is (("." . ".")) with nothing set --
# so installing here does not make CHEZSCHEMELIBDIRS unnecessary. What it
# buys is one canonical location and one stable variable instead of a path
# into a source checkout.
PREFIX  ?= /usr/local
LIBDIR  ?= $(PREFIX)/lib/chez-cmark-gfm
DESTDIR ?=
```

Add the targets beside `check-install`:

```make
# Copies .sls files and nothing else. 2.0 compiles nothing (ADR-0015), and
# the install path must not quietly acquire a build step.
install: ## Copy src/cmark/**.sls into $(DESTDIR)$(LIBDIR) and print the export line
	@set -eu; \
	dest="$(DESTDIR)$(LIBDIR)"; \
	find src/cmark -name '*.sls' | while read -r f; do \
	  rel="$${f#src/}"; \
	  mkdir -p "$$dest/$$(dirname "$$rel")"; \
	  cp "$$f" "$$dest/$$rel"; \
	done; \
	echo "installed to $$dest"; \
	echo; \
	echo "Add this to your shell profile. The TRAILING COLON matters:"; \
	echo "without it Chez replaces its search path outright and drops"; \
	echo "\".\", so relative imports stop resolving."; \
	echo; \
	echo "    export CHEZSCHEMELIBDIRS=$(LIBDIR):"

uninstall: ## Remove the tree installed by `make install`
	@set -eu; \
	dest="$(DESTDIR)$(LIBDIR)"; \
	rm -rf "$$dest/cmark"; \
	rmdir "$$dest" 2>/dev/null || true; \
	echo "removed $$dest/cmark"
```

Extend `.PHONY`:

```make
.PHONY: all build deps check-pins check-purity check-help check-install examples dev help install uninstall test test-memory vendor clean deps-info
```

- [ ] **Step 4: Run the checks to verify they pass**

Run: `make check-install && make check-help`

Expected: `check-install` prints
`install-probe: the installed tree imports and renders` then
`check-install: an installed tree imports and renders`, exit 0.
`check-help` exits 0 — the three new targets all carry `## `.

- [ ] **Step 5: Mutate — prove check-install notices an empty install**

In `install`, break the copy so the tree lands empty:

```make
	  cp /dev/null "$$dest/$$rel"; \
```

Run: `make check-install`

Expected: FAIL. The probe raises on import (the `.sls` files are empty, so
`(cmark gfm)` does not exist), and the recipe prints
`check-install: FAILED -- the tree installed at ...`.

- [ ] **Step 6: Mutate — prove the probe is not import-only**

Restore the `cp` line from Step 5 first: this mutation is about the probe,
not the install. Poison the library instead of the tree, and compare an
import-only probe against the real one. Write both to a scratch directory
outside the repo:

```sh
cat > /tmp/import-only.sps <<'EOF'
#!r6rs
(import (rnrs) (cmark gfm))
(display "import-only: imported\n")
(exit 0)
EOF

echo "--- import-only ---"
CHEZ_CMARK_GFM_LIBS=/nonexistent CHEZSCHEMELIBDIRS=src \
  chez --program /tmp/import-only.sps; echo "exit=$?"

echo "--- the real probe ---"
CHEZ_CMARK_GFM_LIBS=/nonexistent CHEZSCHEMELIBDIRS=src \
  chez --program tests/install-probe.sps; echo "exit=$?"
```

Expected — measured, not predicted:

```
--- import-only ---
import-only: imported
exit=0                       <- PASSES against a library that cannot load
--- the real probe ---
Exception occurred with condition components:
  0. &cmark-library-unavailable
      path: "/nonexistent"
      reason: invalid-override
exit=255                     <- correctly fails
```

That difference is the whole justification for the `markdown->html` call.
An import-only probe reports success against a library that cannot
possibly load, because Chez never instantiates `native.sls`'s body until a
binding is referenced. If the two ever produce the same exit code, the
probe has lost its strength and `check-install` is decorative.

Then delete `/tmp/import-only.sps` and confirm `make check-install` is
green again.

- [ ] **Step 7: Record the mutations**

Append to `.plans/publishing-prep-mutation-log.md`:

```markdown
## Mutation B — check-install notices an empty install tree

**Guards:** `make install` produces a tree that actually loads.
**Mutation:** `install`'s copy step changed to `cp /dev/null`, so every
installed `.sls` lands empty.
**Result:** FAILED — the probe could not resolve `(cmark gfm)` and
`check-install` reported the tree at the temp prefix.
**Reverted:** yes.

## Mutation C — the probe is not import-only

**Guards:** the probe exercises load-time discovery, not just name
resolution.
**Mutation:** ran an import-only probe and `tests/install-probe.sps` side
by side with `CHEZ_CMARK_GFM_LIBS=/nonexistent`.
**Result:** import-only printed `import-only: imported` and exited **0**
against a library that cannot load; the real probe raised
`&cmark-library-unavailable` reason `invalid-override` and exited **255**.
The `markdown->html` call is what makes the difference — Chez does not
instantiate `native.sls`'s body until a binding is referenced.
**Reverted:** yes; scratch probe deleted.
```

- [ ] **Step 8: Commit**

```bash
git add Makefile tests/install-probe.sps .plans/publishing-prep-mutation-log.md
git commit -m "feat(make): add install, uninstall, and check-install

Chez has no system-wide R6RS library directory, so \`make install\` cannot
make CHEZSCHEMELIBDIRS unnecessary -- it gives one canonical location and
prints the export line with the trailing colon that keeps \".\" on the
search path.

check-install installs to a temp prefix and renders a document with
CHEZSCHEMELIBDIRS naming only that directory. CHEZ_CMARK_GFM_LIBS is
unset rather than blanked: \"\" is truthy in Scheme and would take the
override branch.

Mutations B and C recorded."
```

---

### Task 3: docs/installing.md, and repoint the machinery that names README.org

**Files:**
- Create: `docs/installing.md`
- Modify: `.github/workflows/ci.yml:107, 108-113, 242, 243-248, 323, 343, 359, 410`
- Modify: `tests/preflight.sps:66`
- Modify: `.plans/publishing-prep-mutation-log.md`

**Interfaces:**
- Consumes: `make install` / `PREFIX` / `LIBDIR` from Task 2
- Produces: `docs/installing.md` containing a **Supported matrix** table
  whose rows begin `| Linux/x86-64 (apt)    | ` and
  `| macOS/ARM64 (Homebrew)| `, which two CI steps grep

**`README.org` is NOT edited in this task.** The matrix is briefly present
in both files; Task 8 removes the copy. This keeps CI green at every
commit: the greps move to `docs/installing.md` the moment that file has
the rows.

- [ ] **Step 1: Create docs/installing.md**

Move `README.org` lines 11-178 and 201-223 into this structure. Preserve
every command, table, and path **verbatim** — the version range, the
`0.29.0.gfm.13` clone tag, the `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` flag,
the discovery directory lists, and both matrix rows including their exact
column spacing.

```markdown
# Installing

## Prerequisites            <- README 11-48
## Supported versions       <- README 35-48 (the range and the symbol probe)
## Supported matrix         <- README 49-78, rows byte-identical
## With Akku                <- README 93-107
## From a clone             <- README 108-115
## Installing system-wide   <- NEW: make install, PREFIX, the trailing colon
## RHEL, Fedora, and Alpine <- README 116-148
## What `make build` does   <- README 149-178 (preflight + discovery order)
## CHEZ_CMARK_GFM_LIBS      <- README 201-223
```

Rewrite rules, applied throughout:

- Convert Org markup to Markdown: `~code~` → `` `code` ``,
  `*bold*` → `**bold**`, `#+begin_src sh` → ``` ```sh ```,
  `#+begin_example` → ``` ``` ```, Org tables → Markdown tables.
- Drop the sentences that argue rather than inform: "One copy, which CI
  installs from and this section points at rather than restating", "Two
  rows, because two rows are what CI proves", "the position is stated here
  rather than left implied", "established by test rather than assumption:
  earlier revisions of this file said...".
- Keep every sentence that tells a reader something they cannot see:
  why `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` is required (CMake 4 refuses
  `cmake_minimum_required(VERSION 3.0)` outright), why the tasklist symbol
  is probed rather than version-checked, and that a stale `/usr/local/lib`
  build shadows a newer packaged one.
- **Do not** carry over the 1.0-vs-2.0 comparison table (README 81-91).

The new section:

```markdown
## Installing system-wide

Chez has no system-wide R6RS library directory. With nothing set,
`(library-directories)` is `(("." . "."))` — the current directory and
nothing else. So installing does not remove the need for
`CHEZSCHEMELIBDIRS`; it gives you one stable location to point it at
instead of a path into a source checkout.

```sh
make install PREFIX=/usr/local      # -> /usr/local/lib/chez-cmark-gfm/cmark/
```

Then, in your shell profile:

```sh
export CHEZSCHEMELIBDIRS=/usr/local/lib/chez-cmark-gfm:
```

**The trailing colon is not a typo.** Assigning `CHEZSCHEMELIBDIRS`
*replaces* Chez's search path rather than extending it, so without the
colon `.` is dropped and relative imports stop resolving:

```
CHEZSCHEMELIBDIRS=/tmp/foo    =>  (("/tmp/foo" . "/tmp/foo"))
CHEZSCHEMELIBDIRS=/tmp/foo:   =>  (("/tmp/foo" . "/tmp/foo") ("." . "."))
```

`make uninstall PREFIX=/usr/local` removes it. Packagers can set
`DESTDIR`. Nothing is compiled — the install copies `.sls` files and
finds `libcmark-gfm` on the host at import time.
```

- [ ] **Step 2: Repoint the two CI matrix greps**

In `.github/workflows/ci.yml`, at both line 107 and line 242, change the
grep target:

```yaml
          if ! grep -qF -e "$prefix " -e "$prefix|" docs/installing.md; then
```

In the Linux block (108-113) and the macOS block (243-248), change every
`README.org` mention to `docs/installing.md`, including the final
fallback:

```yaml
            echo "::error::docs/installing.md's Supported matrix does not name Chez $actual for the Linux row."
            echo "This runner now ships a different Chez than the table documents."
            echo "Fix: edit the 'Supported matrix' table in docs/installing.md to say $actual."
            echo "Do not pin the toolchain and do not delete this check -- the table is"
            echo "supposed to track whatever CI actually runs, not the other way around."
            grep -n 'Linux/x86-64' docs/installing.md || true
```

The macOS block is identical but for `macOS row` and
`grep -n 'macOS/ARM64'`.

Also update the four prose references:

- line 323: `"'no compiler required' claim -- docs/installing.md, and the"`
- line 343: `# docs/installing.md tells a reader to run.`
- line 359: `# The SAME list docs/installing.md points readers at -- one copy, so this`
- line 410: `- name: Build, exactly as docs/installing.md says`

- [ ] **Step 3: Repoint the preflight message**

In `tests/preflight.sps:66`:

```scheme
           (printf "  source -- docs/installing.md, \"RHEL, Fedora, and Alpine\", has the cmake recipe --\n")
```

- [ ] **Step 4: Verify the greps still work**

Run:

```bash
actual=$(chez --version 2>&1 | tr -d '[:space:]')
grep -qF -e "| macOS/ARM64 (Homebrew)| $actual " \
         -e "| macOS/ARM64 (Homebrew)| $actual|" docs/installing.md \
  && echo "macOS row found: $actual"
```

Expected: `macOS row found: 10.4.1`. If this fails, the table's column
spacing did not survive the Org→Markdown conversion — fix the table, not
the check.

- [ ] **Step 5: Mutate — prove the repointed grep can still fail**

Change the Chez version in `docs/installing.md`'s macOS row from `10.4.1`
to `10.4.0`, then re-run the Step 4 command.

Expected: no output, non-zero exit — the check still discriminates.
Restore `10.4.1` and confirm it passes again.

This is the mutation that matters most in the whole plan. AGENTS.md's
first trap is a check that survives the deletion of what it guarded and
stays green forever.

- [ ] **Step 6: Run the preflight**

Run: `make build`

Expected: prints `cmark-gfm 0.29.0.gfm.13` and the two resolved library
paths, exit 0. (The changed line is in an error branch, so this confirms
the edit did not break the file, not that the message is reachable.)

- [ ] **Step 7: Record the mutation and commit**

Append to `.plans/publishing-prep-mutation-log.md`:

```markdown
## Mutation D — the CI matrix grep still discriminates after repointing

**Guards:** the Supported matrix names the Chez each CI job actually ran.
**Mutation:** changed the macOS row in `docs/installing.md` from 10.4.1 to
10.4.0.
**Result:** FAILED — the anchored grep found no matching row, exactly as
it did against README.org before the move.
**Reverted:** yes.
```

```bash
git add docs/installing.md .github/workflows/ci.yml tests/preflight.sps \
        .plans/publishing-prep-mutation-log.md
git commit -m "docs: add docs/installing.md and repoint CI at it

Two CI steps grep the Supported matrix and the preflight names the section
holding the cmake recipe. All three now point at docs/installing.md, which
carries both.

README.org keeps its copy until the rewrite removes it, so no commit in
this branch leaves CI grepping a file without the rows.

Mutation D recorded: the repointed grep still fails on a wrong version."
```

---

### Task 4: docs/usage.md and docs/options.md

**Files:**
- Create: `docs/usage.md`, `docs/options.md`

**Interfaces:**
- Consumes: nothing
- Produces: `docs/usage.md` and `docs/options.md`, linked from the
  Documentation table in Task 8

- [ ] **Step 1: Create docs/usage.md**

From `README.org` 252-279, expanded into a reference page:

```markdown
# Usage

## Getting started            <- the (import (cmark gfm)) block, README 254-282
## The renderers              <- a table of the four entry points
## Wrap width                 <- README 273-276, why it is an arity not an option
## Which library is loaded    <- README 278-281, the three capability queries
```

The renderer table, with arities taken from `src/cmark/gfm.sls:28`:

```markdown
| Entry point            | Arity                      | Wraps |
|------------------------|----------------------------|-------|
| `markdown->html`       | `(md options)`             | no    |
| `markdown->xml`        | `(md options)`             | no    |
| `markdown->commonmark` | `(md options width)`       | yes   |
| `markdown->plaintext`  | `(md options width)`       | yes   |
```

State plainly that passing a width to `markdown->html` is an arity error,
not a silently ignored setting. Cross-link `options.md`, `ast.md`,
`sxml.md`, and `errors.md`. Note that `examples/01-rendering.sps` and
`examples/02-options.sps` are runnable and gated by `make examples`.

- [ ] **Step 2: Create docs/options.md**

From `README.org` 280-305:

```markdown
# Options

## The defaults              <- the ten-row table, values verbatim
## Constructing and updating <- make-cmark-options / default-cmark-options /
                                cmark-options-with, and that unknown keys,
                                duplicate keys, and unknown extensions are
                                rejected before anything native is allocated
## hardbreaks? and nobreaks? <- README 295-298, why the combination is refused
## validate-utf8?            <- README 300-305, why it is unreachable here
## Resource limits           <- max-input-bytes / max-nodes / max-depth,
                                cross-linked to ast.md
```

Keep the default values byte-identical: `5242880` (5 MiB), `250000`,
`1000`, and the extension list
`(autolink strikethrough table tagfilter tasklist)`.

- [ ] **Step 3: Verify the documented defaults against the code**

Run:

```bash
CHEZSCHEMELIBDIRS=src chez --program /dev/stdin <<'EOF'
#!r6rs
(import (rnrs) (cmark gfm))
(define o (default-cmark-options))
(for-each (lambda (p) (display (car p)) (display " = ")
                      (write ((cdr p) o)) (newline))
  (list (cons 'extensions cmark-options-extensions)
        (cons 'validate-utf8? cmark-options-validate-utf8?)
        (cons 'source-positions? cmark-options-source-positions?)
        (cons 'hardbreaks? cmark-options-hardbreaks?)
        (cons 'nobreaks? cmark-options-nobreaks?)
        (cons 'smart? cmark-options-smart?)
        (cons 'unsafe-html? cmark-options-unsafe-html?)
        (cons 'max-input-bytes cmark-options-max-input-bytes)
        (cons 'max-nodes cmark-options-max-nodes)
        (cons 'max-depth cmark-options-max-depth)))
EOF
```

Expected: every printed value matches the table in `docs/options.md`. If
one differs, the **table** is wrong — correct it.

- [ ] **Step 4: Commit**

```bash
git add docs/usage.md docs/options.md
git commit -m "docs: add usage and options reference pages

Defaults in options.md verified against default-cmark-options rather than
transcribed from the README."
```

---

### Task 5: docs/ast.md and docs/memory.md

**Files:**
- Create: `docs/ast.md`, `docs/memory.md`

**Interfaces:**
- Consumes: nothing
- Produces: both pages, linked from Task 8's table; `sxml.md` (Task 6)
  cross-links `ast.md` for everything the SXML mapping drops

- [ ] **Step 1: Create docs/ast.md**

From `README.org` 323-394:

```markdown
# The AST

## Parsing                 <- README 325-345, both arities; positions ON at
                              arity 1 (ADR-0009), your record verbatim at arity 2
## Node shape              <- (type properties children source), and
                              markdown-node-property's optional default and
                              why absence and #f must stay distinguishable
## Properties by node type <- README 355-371, the full table
## Ordinal index           <- README 368-372: index is start + offset, 0 for
                              every bullet item; `1. 1. 1.` and `1. 5. 9.`
                              both index 1 2 3
## Traversal               <- markdown-node-map (children-first),
                              markdown-node-fold (pre-order), both returning
                              new trees
## The AST is untrusted    <- README 373-378, keep the warning callout
## Resource limits         <- README 380-397, the guard example verbatim
```

Keep the untrusted-input warning prominent — it is the one thing on this
page a reader must not miss:

```markdown
> **⚠️ The AST is untrusted structured input.** It preserves exactly what
> the document said, including raw HTML and `javascript:` URLs.
> `unsafe-html?` does not affect it — that option is a renderer policy.
> Sanitise when you render, not when you parse.
```

- [ ] **Step 2: Create docs/memory.md**

From `README.org` 306-322. Five bullets, unchanged in substance. Replace
"Rationale is in the design spec §5" with a pointer to
`.plans/2026-08-16-chez-cmark-gfm-design.md`, since a public reader has no
idea what "the design spec" names.

Frame it as the contract a caller may depend on, and state that no public
entry point exposes a live document, so `&cmark-dead-document` is
unreachable from outside.

- [ ] **Step 3: Verify the ordinal-index claim**

Run:

```bash
CHEZSCHEMELIBDIRS=src chez --program /dev/stdin <<'EOF'
#!r6rs
(import (rnrs) (cmark gfm))
(define (indices md)
  (map (lambda (n) (markdown-node-property n 'index))
       (markdown-node-children
         (car (markdown-node-children (markdown->ast md))))))
(write (indices "1. a\n1. b\n1. c\n")) (newline)
(write (indices "1. a\n5. b\n9. c\n")) (newline)
(write (indices "- a\n- b\n")) (newline)
EOF
```

Expected: `(1 2 3)`, `(1 2 3)`, `(0 0)` — matching the page. If not, fix
the page to match observed behaviour.

- [ ] **Step 4: Commit**

```bash
git add docs/ast.md docs/memory.md
git commit -m "docs: add AST and memory-ownership reference pages

The ordinal-index claim is verified against markdown->ast, not restated
from the README."
```

---

### Task 6: docs/sxml.md, serializing included

**Files:**
- Create: `docs/sxml.md`

**Interfaces:**
- Consumes: `docs/ast.md` from Task 5 (linked as the home of everything the
  mapping drops)
- Produces: `docs/sxml.md`, the single page covering the adapter, the
  mapping, and serializer choice

- [ ] **Step 1: Create docs/sxml.md**

From `README.org` 395-625 — the whole SXML run, including "Your
serializer, not ours". Serializing is a **section here**, not a separate
page: the mapping table means nothing until the reader knows their
serializer's deltas.

```markdown
# SXML

## Getting started            <- README 397-416
## Options                    <- README 419-433, the three-row table
## Why `omit` is the default  <- README 435-445, keep the full argument;
                                 it is a security property, not a taste
## The attribute marker       <- README 447-457: `^` not `@`, and the
                                 silent corruption `@` causes with
                                 srl:sxml->html
## Options that are refused   <- README 459-485, including source-positions?
                                 as the accepted-and-discarded exception
## The mapping                <- README 486-553, the full table
## Four details the table compresses <- README 526-543
## The `strong` splice        <- README 545-550, the one version-qualified row
## What the mapping drops     <- README 554-574, cross-linked to ast.md
## URLs                       <- README 575-591
## Serializing: your serializer, not ours  <- README 592-625
```

The serializing section keeps both warnings intact:

- The delta table against `srl:sxml->html`, with the adjacent-inline row
  called out as the one worth knowing: an injected newline between two
  inline elements collapses to a rendered space.
- The `<pre>` callout:

```markdown
> **⚠️ A pretty-printing serializer will corrupt `<pre>` content.**
> Injected indentation inside a code block is content, not formatting.
> `srl:sxml->html` does not do it — it exempts `pre`, `script`, `style`,
> and `textarea`, and any element with a bare-text child, and
> `tests/test-sxml-portability.sps` asserts the exact rendering — but that
> is a property of that serializer, checked, not a property of SXML.
```

State plainly that byte-equality with `markdown->html` across all 744
corpus examples is a property of the **test-only** serializer in `tests/`,
not a promise about the reader's pipeline.

- [ ] **Step 2: Verify the two headline examples**

Run:

```bash
CHEZSCHEMELIBDIRS=src chez --program /dev/stdin <<'EOF'
#!r6rs
(import (rnrs) (cmark gfm))
(write (markdown->sxml "# Hello\n\n[l](/x \"t\")\n")) (newline)
(write (markdown->sxml "para <b>raw</b>\n"
                       (default-cmark-options)
                       (make-sxml-options 'raw-html 'escape))) (newline)
EOF
```

Expected, matching the page:

```
(*TOP* (h1 "Hello") (p (a (^ (href "/x") (title "t")) "l")))
(*TOP* (p "para " "<b>" "raw" "</b>"))
```

- [ ] **Step 3: Commit**

```bash
git add docs/sxml.md
git commit -m "docs: add the SXML reference page, serializing included

Serializing is a section rather than its own page: the mapping table means
nothing until the reader knows their serializer's deltas. Both worked
examples verified against markdown->sxml."
```

---

### Task 7: docs/errors.md and docs/building.md

**Files:**
- Create: `docs/errors.md`, `docs/building.md`

**Interfaces:**
- Consumes: nothing
- Produces: both pages; `building.md` is what `CONTRIBUTING.md` (Task 10)
  links to for the full build story

- [ ] **Step 1: Create docs/errors.md**

From `README.org` 626-643, expanded — 13 lines at the bottom of the README
is where this material currently hides. Take the condition names from
`src/cmark/gfm.sls:55-76`:

```markdown
# Errors

## The condition family      <- every failure derives from &cmark-error, so a
                                caller can catch the family or discriminate
## The tree
## What raises what
## Examples                  <- the guard from README 631-642, plus the
                                resource-limit guard from README 391-397
```

The tree, from the exports:

```
&cmark-error
├── &cmark-invalid-option        key, reason
├── &cmark-invalid-input         reason
│   └── &cmark-resource-limit    value
├── &cmark-library-unavailable   path, reason
├── &cmark-version-incompatible  supported, runtime
├── &cmark-extension-unavailable name
├── &cmark-dead-document
├── &cmark-render-failed         format
├── &cmark-unsupported-node      type
└── &cmark-malformed-tree        reason
```

Note the reason symbols a caller can act on: `unknown-key`,
`not-applicable`, `too-deep`, `not-found`, `invalid-override`,
`missing-entry-point`, `header-row-not-first`.

- [ ] **Step 2: Verify the condition tree**

Run:

```bash
CHEZSCHEMELIBDIRS=src chez --program /dev/stdin <<'EOF'
#!r6rs
(import (rnrs) (cmark gfm))
;; &cmark-resource-limit must derive from &cmark-invalid-input, which must
;; derive from &cmark-error. Print all three predicates for one condition.
(guard (e (#t (write (list 'resource-limit? (cmark-resource-limit? e)
                           'invalid-input?  (cmark-invalid-input? e)
                           'cmark-error?    (cmark-error? e)
                           'reason (cmark-invalid-input-reason e)
                           'value  (cmark-resource-limit-value e)))
              (newline)))
  (markdown->ast (make-string 200 #\>) (make-cmark-options 'max-depth 4)))
EOF
```

Expected: all three predicates `#t`, `reason too-deep`, `value 4`. Correct
the page if the derivation differs.

- [ ] **Step 3: Create docs/building.md**

From `README.org` 224-251 plus the Makefile's targets:

```markdown
# Building and testing

## Requirements for development  <- submodules, `make deps`, the CLI oracle
## The targets                   <- point at `make help` as the live list;
                                    do not duplicate it here, or it rots
## Running the suites            <- make test, and that each suite sets its
                                    own exit status
## make test-memory              <- Valgrind on Linux, ASan preload on macOS;
                                    only Linux can support a leak claim
                                    (ADR-0003)
## make check-purity             <- what it poisons and what that proves
## make check-pins               <- submodule commits vs Akku.lock
## make examples                 <- examples/NN-*.sps vs examples/expected/NN.out
## make check-install            <- installs to a temp prefix and renders
## The dev REPL                  <- make dev and what it puts on the path
```

Deliberately **do not** reproduce the target list — point at `make help`,
which `check-help` keeps complete. A second copy here is a copy that rots.

- [ ] **Step 4: Commit**

```bash
git add docs/errors.md docs/building.md
git commit -m "docs: add errors and building reference pages

The condition tree is verified against a live &cmark-resource-limit
rather than read off the export list. building.md points at \`make help\`
instead of duplicating the target list."
```

---

### Task 8: Rewrite README.org

**Files:**
- Modify: `README.org` (642 lines → ~140)

**Interfaces:**
- Consumes: all eight `docs/*.md` pages from Tasks 3-7
- Produces: the Documentation table every docs page is reached from

- [ ] **Step 1: Rewrite README.org**

Replace the whole file with this structure. Every link target must exist —
all eight pages are created by Tasks 3-7.

```org
* chez-cmark-gfm

[[https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/actions/workflows/ci.yml][https://github.com/Kiyomi-Computation-Systems/chez-cmark-gfm/actions/workflows/ci.yml/badge.svg]]

CommonMark and GitHub Flavored Markdown for Chez Scheme.

#+begin_quote
✨ *AI Disclosure:* LLMs are used extensively in the planning and development of this project.
#+end_quote

* What it is
* Status
* Install
** Prerequisites
** With Akku
** From a clone
** System-wide
** Running your program
* A taste
* Documentation
* Contributing
* License
```

Fix both typos while rewriting: the current line 3 says "CommonMark GFM
for Chez *Sceme*", and line 6 says "used extensively *the in* the
planning".

Content rules:

- **What it is** — three or four sentences: four renderers, an immutable
  Scheme AST, an SXML adapter; safe by default (raw HTML and unsafe link
  schemes suppressed); binds the system `libcmark-gfm` and **compiles
  nothing**.
- **Status** — 2.0, supported range `0.29.0.gfm.x`, Chez 9.5.8+, macOS and
  Linux; Windows unsupported (ADR-0004). One line each.
- **Install** — the `apt`/`brew` one-liners, `akku install` +
  `. .akku/bin/activate`, the clone, and `make install PREFIX=...` with
  the trailing-colon export. Everything else defers to
  `docs/installing.md`. Do not restate the version range, the discovery
  order, or the RHEL recipe here.
- **A taste** — about twelve lines, drawn from `examples/01-rendering.sps`
  and `examples/04-sxml.sps` so it stays gated by `make examples`:
  `markdown->html` with defaults, one `make-cmark-options` call, one
  `markdown->sxml` call.
- **Documentation** — the table below.
- **License** — BSD 3-Clause, `LICENSE`, `NOTICE`, and the © line, kept at
  the bottom where commit `cb895bc` put it.

The Documentation table:

```org
| [[file:docs/installing.md][Installing]]   | Prerequisites, Akku, system-wide install, and every acquisition path |
| [[file:docs/usage.md][Usage]]             | The four renderers, and which library got loaded                    |
| [[file:docs/options.md][Options]]         | Every option, its default, and the two that conflict                |
| [[file:docs/ast.md][The AST]]             | Node shape, properties by type, traversal, resource limits          |
| [[file:docs/sxml.md][SXML]]               | The adapter, the full mapping, and choosing a serializer            |
| [[file:docs/errors.md][Errors]]           | The condition family, and what raises what                          |
| [[file:docs/memory.md][Memory ownership]] | The contract a caller depends on                                    |
| [[file:docs/building.md][Building]]       | Targets, test suites, and the memory checks                         |
| [[file:CHANGELOG.md][CHANGELOG]]          | Per-release history                                                 |
| [[file:.plans/][Design specs & ADRs]]     | Why it is built this way, with the evidence                         |
```

- [ ] **Step 2: Verify the length and every link**

Run:

```bash
wc -l README.org
grep -o 'file:[^]]*' README.org | sed 's/^file://' | while read -r p; do
  [ -e "$p" ] && echo "ok   $p" || echo "MISS $p"
done
```

Expected: roughly 140 lines, and `ok` for all ten targets. Any `MISS` is a
broken link — fix before committing.

- [ ] **Step 3: Verify CI's matrix greps now find only docs/installing.md**

Run:

```bash
grep -c 'Linux/x86-64' README.org docs/installing.md
```

Expected: `README.org:0` and `docs/installing.md:1`. A non-zero README
count means the duplicate survived the rewrite.

- [ ] **Step 4: Run the full suite**

Run: `make test && make examples`

Expected: `ALL SUITES PASSED` and `ALL EXAMPLES PASSED`. The taste block
must not have introduced a claim the examples do not support.

- [ ] **Step 5: Commit**

```bash
git add README.org
git commit -m "docs: rewrite README.org for a public audience

642 lines to ~140. Everything that argued *why* moved to docs/ in the
preceding commits; what remains gets a reader installed and rendering,
then points at the reference page for whatever they need next.

Removes the now-duplicated Supported matrix -- CI has grepped
docs/installing.md since the commit that created it. Fixes 'Chez Sceme'
and 'used extensively the in the planning'."
```

---

### Task 9: Rewrite NOTICE

**Files:**
- Modify: `NOTICE`

**Interfaces:**
- Consumes: nothing
- Produces: a NOTICE whose stated rationale matches the actual obligation

- [ ] **Step 1: Confirm the three transcription sites still exist**

Run:

```bash
grep -n 'houdini_href_e.c:32-44' src/cmark/gfm/sxml.sls
grep -n 'scanners.re:345-354'    src/cmark/gfm/sxml.sls
grep -n 'spec_tests.py:89-120'   tests/spec-corpus.sls
```

Expected: one hit each. If a line moved, use the new number in Step 2 —
the table must cite real anchors.

- [ ] **Step 2: Rewrite NOTICE**

Keep the header and the two implicated license texts. Replace the
development-dependency rationale with the obligation that actually
applies:

```
chez-cmark-gfm
==============

Copyright (c) 2026, Kiyomi Computation Systems LLC.
Licensed under the BSD 3-Clause License; see LICENSE.


This package binds cmark-gfm but does not distribute it. Release 2.0
compiles nothing: the library is located on the host at import time and
loaded from wherever the system package manager put it (ADR-0015,
ADR-0016).

The notices below are reproduced because this tree carries expression
transcribed from cmark-gfm's source, not because cmark-gfm is a
development dependency:

  src/cmark/gfm/sxml.sls   the HREF_SAFE byte set, from
                           src/houdini_href_e.c:32-45      (houdini, MIT)

  src/cmark/gfm/sxml.sls   the dangerous-URL scheme rule, from
                           src/scanners.re:345-354         (cmark-gfm, BSD-3)

  tests/spec-corpus.sls    the corpus parser, from
                           test/spec_tests.py:89-120       (cmark-gfm, BSD-3)

cmark-gfm
---------
<the existing BSD-3 text, unchanged>

houdini
-------

houdini_href_e.c derives from https://github.com/vmg/houdini

Copyright (C) 2012 Vicent Marti
<the existing MIT text, unchanged>
```

**Delete** the four sections nothing in this tree derives from: `buffer.h`
/ `buffer.c` / `chunk.h` (GitHub, Inc.), utf8proc, `normalize.py`, and the
CommonMark spec's CC-BY-SA. The 744-example corpus is read from the
submodule at test time and never copied in; `tests/fixtures/*.md` are
hand-written.

Keep the "test software in `test/`" BSD-3 grant — `spec-corpus.sls`
transcribes from it. It is the same BSD-3 text as cmark-gfm's own, so one
copy under the `cmark-gfm` heading covers both; say so in one line rather
than repeating it.

- [ ] **Step 3: Verify the shrink**

Run: `wc -c NOTICE`

Expected: roughly 3000 bytes, down from 8362.

- [ ] **Step 4: Commit**

```bash
git add NOTICE
git commit -m "docs: state NOTICE's actual obligation and drop four uninvolved licenses

NOTICE justified itself as reproducing a development dependency's license,
which carries no obligation -- a cloner fetches the submodule from GitHub
with its own LICENSE inside it.

The real obligation is transcribed expression in shipped source: sxml.sls
carries houdini's HREF_SAFE set (MIT) and cmark's dangerous-scheme rule
(BSD-3), and spec-corpus.sls carries cmark's corpus parser (BSD-3). Each
is now cited by file and line.

Removes utf8proc, buffer.c/chunk.h, normalize.py, and the spec's CC-BY-SA:
nothing here derives from any of them. The corpus is read from the
submodule at test time, never copied in."
```

---

### Task 10: CONTRIBUTING, SECURITY, and GitHub templates

**Files:**
- Create: `CONTRIBUTING.md`, `SECURITY.md`,
  `.github/ISSUE_TEMPLATE/bug_report.md`,
  `.github/ISSUE_TEMPLATE/feature_request.md`,
  `.github/PULL_REQUEST_TEMPLATE.md`

**Interfaces:**
- Consumes: `docs/building.md` (Task 7) and `make help` (Task 1)
- Produces: the files the README's Contributing section links to

- [ ] **Step 1: Create CONTRIBUTING.md**

Adapt `~/github/chez-libuv/CONTRIBUTING.md`. Sections: intro (drive-by fix
vs feature-sized work), Setup, The gates, Conventions, How this repo is
developed, Security.

The gates section must name what CI actually runs:

```markdown
## The gates

A PR must keep these green — they are what CI runs:

- `make test` — every suite passes (`ALL SUITES PASSED`).
- `make check-pins` — the submodule commits and `Akku.lock` agree.
- `make check-purity` — `options.sls`, `ast.sls`, and the SXML adapter
  still import nothing that loads a shared object.
- `make check-help` — every target is documented in `make help`.
- `make check-install` — an installed tree still imports and renders.
- `make examples` — every `examples/*.sps` still produces its expected
  output.
- `make test-memory` runs in CI; only the Linux Valgrind leg can support a
  leak claim (ADR-0003).
- **Tests accompany code changes.** A behaviour change without a test that
  fails against the old behaviour will be asked for one.
- Every new suite ends with its own `(exit …)` — SRFI-64 does not set a
  process exit status, and a suite missing that line reports success
  forever.
```

The "How this repo is developed" section carries the mutation discipline
from `AGENTS.md`: *a test is not finished when it passes; it is finished
when you have watched it fail*, with evidence in a mutation log. Point at
`.plans/` for the existing logs.

- [ ] **Step 2: Create SECURITY.md**

Adapt `~/github/chez-libuv/SECURITY.md`:

```markdown
# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 2.0.x (latest) | ✅ |
| < 2.0 | ❌ |

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub:
**Security → Report a vulnerability** on this repository. Do not open a
public issue.

You can expect an acknowledgement within 7 days.

This is an FFI binding around a C library, and it renders untrusted input.
Reports are especially welcome on:

- the native boundary — memory safety, lifetimes, argument validation;
- **rendering policy** — anything that gets raw HTML or a `javascript:`
  URL through `markdown->html` with `unsafe-html?` left at its `#f`
  default, or through `markdown->sxml` under `raw-html: omit`;
- resource limits — input that defeats `max-nodes` or `max-depth`.

Please include your platform, Chez version, and the output of
`make build`, which names the exact libraries discovered.
```

Note in the page that the AST is *documented* as untrusted — it preserves
raw HTML by design — so an AST carrying a `javascript:` URL is not a
vulnerability. See `docs/ast.md`.

- [ ] **Step 3: Create the issue templates**

`.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Something broke or behaved unexpectedly
labels: bug
---

**Environment**

- OS and architecture (e.g. macOS 15 arm64, Ubuntu 24.04 x86_64):
- Chez Scheme version (`chez --version`, or `chezscheme --version`):
- cmark-gfm: paste the output of `make build` — it names the exact core
  and extensions libraries that would load.
- Installed via: Akku / clone / `make install` / other:

**What happened**

**What you expected**

**Minimal reproduction**

Ideally a small standalone `.sps`, run as
`CHEZSCHEMELIBDIRS=src chez --program repro.sps`. Include the Markdown
input if the bug depends on it.

**Does `make test` pass locally?**
```

`.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
---
name: Feature request
about: Propose an addition to the binding
labels: enhancement
---

**The problem**

What can't you do today?

**Proposed API surface**

Which module — `(cmark gfm)`, `(cmark gfm sxml)`, a new one — and what
would the exports look like?

**Does cmark-gfm already expose this?**

If it wraps an existing `cmark_*` entry point, name it. Note that the
supported range is `0.29.0.gfm.x`, and that a distribution can backport a
symbol while still reporting an older version — so a new binding needs its
availability checked across the range, not just on your machine. See
`AGENTS.md`.

**If this is an SXML change**

`(cmark gfm sxml)` is pure and carries HTML vocabulary only (ADR-0011).
Proposals that need a non-HTML node, or that would make the adapter reach
native code, need a design conversation first.
```

`.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## What

<!-- One or two sentences: what changes and why. -->

## Checklist

- [ ] `make test` is green locally (`ALL SUITES PASSED`)
- [ ] `make check-pins`, `make check-purity`, `make check-help`, and
      `make check-install` are green
- [ ] `make examples` is green
- [ ] Commit/PR title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] Tests accompany code changes, and each new suite ends with `(exit …)`
- [ ] New or changed assertions have been **watched to fail** — mutation
      recorded in `.plans/`
- [ ] `README.org` / `docs/` updated if the public API changed
- [ ] `CHANGELOG.md` entry if the change is user-visible
```

- [ ] **Step 4: Verify every command the new files name actually exists**

Run:

```bash
for t in test check-pins check-purity check-help check-install examples build; do
  grep -qE "^$t:" Makefile && echo "ok   make $t" || echo "MISS make $t"
done
```

Expected: `ok` for all seven. A `MISS` means a contributor would be told to
run a target that does not exist.

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md SECURITY.md .github/ISSUE_TEMPLATE .github/PULL_REQUEST_TEMPLATE.md
git commit -m "docs: add CONTRIBUTING, SECURITY, and GitHub templates

The gates listed in CONTRIBUTING are the targets CI runs, each verified to
exist in the Makefile. SECURITY names rendering policy alongside the
native boundary, and notes that the AST is documented as untrusted so a
raw javascript: URL in a tree is not a vulnerability."
```

---

### Task 11: Final verification and CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `.plans/publishing-prep-mutation-log.md`

**Interfaces:**
- Consumes: every preceding task
- Produces: the release note for this pass

- [ ] **Step 1: Run every gate**

Run:

```bash
make check-help && make check-pins && make check-purity && \
make check-install && make test && make examples
```

Expected: each exits 0; `ALL SUITES PASSED`, `ALL EXAMPLES PASSED`.
**Do not proceed on a failure** — fix it in the task that introduced it.

- [ ] **Step 2: Confirm no stale README references survive**

Run:

```bash
grep -rn 'README\.org' .github/workflows/ci.yml tests/ Makefile || \
  echo "no stale references"
```

Expected: either `no stale references`, or only hits that legitimately
concern the README as a file (not as the home of moved content). Inspect
each hit; a reference to a section that no longer exists there is a
defect.

- [ ] **Step 3: Confirm docs/ holds only user-facing documentation**

Run: `ls docs/`

Expected: exactly the eight `.md` files. No specs, no ADRs, no mutation
logs — those stay in `.plans/`.

- [ ] **Step 4: Add the CHANGELOG entry**

Add an `Unreleased` section at the top of `CHANGELOG.md`, matching the
file's existing heading style:

```markdown
## Unreleased

### Documentation

- `README.org` cut from 642 lines to ~140. Reference material moved to
  eight pages under `docs/`: installing, usage, options, the AST, SXML
  (serializing included), errors, memory ownership, and building.
- Dropped the 1.0-vs-2.0 comparison table. Nobody consumed 1.0; the
  history is in this file.
- `NOTICE` now states the obligation that actually applies — expression
  transcribed into `sxml.sls` and `spec-corpus.sls` — and drops four
  licenses nothing here derives from.
- Added `CONTRIBUTING.md`, `SECURITY.md`, and GitHub issue/PR templates.

### Added

- `make help` lists every target, and `make check-help` fails when one is
  undocumented.
- `make install` / `make uninstall` copy `src/cmark/**.sls` to
  `$(PREFIX)/lib/chez-cmark-gfm` for consumers not using Akku. Nothing is
  compiled. Chez has no system-wide R6RS library directory, so the target
  prints the `CHEZSCHEMELIBDIRS` line to add — with the trailing colon
  that keeps `.` on the search path.
- `make check-install` installs to a temporary prefix and renders a
  document with `CHEZSCHEMELIBDIRS` naming only that directory.

### Changed

- The two CI steps that grep the Supported matrix, and the preflight's
  cmake-recipe pointer, now name `docs/installing.md`.
```

- [ ] **Step 5: Close out the mutation log**

Append a summary table to `.plans/publishing-prep-mutation-log.md` listing
Mutations A-D, what each guards, and its outcome. Any check whose mutation
did **not** produce the predicted failure is written down as uncovered,
with the reason — per AGENTS.md, leaving it silent is the failure the rule
exists to prevent.

- [ ] **Step 6: Commit and open the PR**

```bash
git add CHANGELOG.md .plans/publishing-prep-mutation-log.md
git commit -m "docs: record the publishing-prep pass in CHANGELOG"
git push -u origin docs/publishing-prep
gh pr create --title "docs: prepare the repository for a public release" --body "$(cat <<'EOF'
## What

README.org from 642 lines to ~140, eight user-facing pages under `docs/`,
an install path for non-Akku users, and contributor scaffolding.

Design: `.plans/2026-08-22-publishing-prep-design.md`

## Notable

- Chez has no system-wide R6RS library directory, so `make install` cannot
  make `CHEZSCHEMELIBDIRS` unnecessary. It prints the export line with the
  trailing colon that keeps `.` on the search path.
- `check-install` unsets `CHEZ_CMARK_GFM_LIBS` rather than blanking it:
  `""` is truthy in Scheme and takes the override branch.
- Moving the Supported matrix disarmed two CI greps and a preflight
  message. All three are repointed, and the grep was mutated to confirm it
  still discriminates.
- `NOTICE` now cites the three transcription sites by file and line and
  drops four uninvolved licenses.

## Gates

`make check-help`, `check-pins`, `check-purity`, `check-install`, `test`,
and `examples` all green. Mutations recorded in
`.plans/publishing-prep-mutation-log.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
