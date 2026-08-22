# Publishing preparation: README, docs/, Makefile, and community files

Status: accepted
Date: 2026-08-22
Scope: documentation and packaging only. No library behaviour changes.

## Goal

Make the repository suitable for a public open-source release. Today's
`README.org` is 642 lines and reads as a design document: it argues *why*
at every turn, which is right for `.plans/` and wrong for the file a
stranger reads first. A reader arriving from a search result should be able
to install, render one document, and find the reference page for whatever
they need next, without reading an argument.

Three deliverables:

1. `README.org` cut to roughly 140 lines, in the shape `chez-libuv` already
   proves out.
2. `docs/` — eight user-facing Markdown pages carrying the reference material
   the README sheds. **`docs/` is for user-facing documentation only.**
   Designs, decision records, and mutation logs stay in `.plans/`.
3. Contributor scaffolding: `make help`, an install path for non-Akku users,
   `CONTRIBUTING.md`, `SECURITY.md`, and GitHub issue/PR templates.

## 1. README.org — target shape

```org
* chez-cmark-gfm          CI badge, one-line description, AI disclosure
* What it is              rendering + AST + SXML, safe by default, compiles nothing
* Status                  2.0; Windows unsupported (ADR-0004)
* Install                 prereqs, Akku, clone, make install -> docs/installing.md
* A taste                 ~12 lines: markdown->html, one option, markdown->sxml
* Documentation           table of links into docs/
* Contributing            -> CONTRIBUTING.md, SECURITY.md
* License                 BSD-3, NOTICE
```

Everything that argues *why* leaves: the symbol-probe rationale, the
`-DCMAKE_POLICY_VERSION_MINIMUM` explanation, the `strong`-splice version
qualifier, the discovery-shadowing discussion. None of it is deleted; it
moves to `docs/` or is already in `.plans/`.

Two typos are fixed in passing: "Chez Sceme" and "used extensively the in
the planning".

### Dropped outright

The **1.0 vs 2.0 comparison table** (current README lines 85-91). Nobody
consumed 1.0, so it is migration advice for a migration nobody performs.
The history remains in `CHANGELOG.md`, which is where it belongs.

## 2. docs/ — eight pages

| File | Absorbs |
|---|---|
| `installing.md` | prerequisites, supported version range and the symbol probe, **the supported matrix**, Akku and clone installs, `make install`, RHEL/Fedora/Alpine source build, `CHEZ_CMARK_GFM_LIBS`, discovery order |
| `usage.md` | the four renderers, entry-point table, wrap-width arity, capability queries |
| `options.md` | the `cmark-options` table, the hardbreaks/nobreaks conflict, the UTF-8 note |
| `ast.md` | node model, per-type property table, `index` semantics, resource limits, the untrusted-input warning |
| `sxml.md` | the adapter, its options, the full AST->SXML mapping, refused options, URL handling, **and serializing**: "your serializer, not ours", the `srl:sxml->html` delta table, the `<pre>` corruption warning |
| `errors.md` | the `&cmark-error` tree, which entry point raises what, guard examples |
| `memory.md` | the ownership contract |
| `building.md` | make targets, the test suites, `check-pins`/`check-purity`/`test-memory`, the dev REPL |

Serializing is a section of `sxml.md`, not a page of its own. The mapping
table means nothing until the reader knows their serializer's deltas —
splitting them puts a page boundary in the middle of one argument.

Code samples cite `examples/*.sps` wherever one exists. `make examples`
already diffs those against `examples/expected/NN.out`, so a sample that
drifts fails a target rather than misleading a reader. Samples that cannot
be an example (error cases, mapping fragments) are marked as illustrative.

## 3. Makefile

### help and check-help

Lifted from `chez-libuv`, which already runs this pattern: a `## `
description on each target's own line, an `awk` formatter, and
`check-help` failing when any `.PHONY` target lacks one.

```make
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
```

`check-help` is the reason `help` cannot rot: a target added without a
description fails the build.

### install and uninstall

**Chez has no system-wide R6RS library directory.** Measured on Chez
10.4.1:

```
(library-directories)  unset            => (("." . "."))
CHEZSCHEMELIBDIRS=/tmp/foo              => (("/tmp/foo" . "/tmp/foo"))
CHEZSCHEMELIBDIRS=/tmp/foo:             => (("/tmp/foo" ...) ("." . "."))
```

Two consequences the documentation must state rather than gloss:

- `make install` cannot make `CHEZSCHEMELIBDIRS` unnecessary. What it buys
  is one canonical location and one stable variable instead of a path into
  a source checkout.
- Assigning `CHEZSCHEMELIBDIRS` **replaces** the search path and silently
  drops `.`. The trailing colon is what preserves it. Every documented
  export line carries one, and the `install` target prints it that way.

```make
PREFIX  ?= /usr/local
LIBDIR  ?= $(PREFIX)/lib/chez-cmark-gfm     # DESTDIR-aware for packagers

install:   ## Copy src/cmark/**.sls into $(LIBDIR); print the export line
uninstall: ## Remove the installed tree
```

`install` copies the `.sls` tree only. Nothing is compiled — that is the
2.0 property (ADR-0015) and the install path must not quietly acquire a
build step.

### check-install

An untested `install` target is precisely what AGENTS.md forbids. The check
installs into a temporary prefix, then runs a program with
`CHEZSCHEMELIBDIRS` pointing **only** there and `CHEZ_CMARK_GFM_LIBS`
unset.

**The probe must call into the library, not merely import it.** Chez
instantiates an imported library's body only when a binding is
*referenced* (AGENTS.md, trap 4). A probe that imports `(cmark gfm)` and
exits proves nothing — `native.sls`'s body never runs, discovery never
happens. The probe calls `markdown->html` and asserts on its output, the
same reason `tests/load-failed-probe.sps` calls it.

## 4. NOTICE

The current NOTICE is ~8.4 KB and justifies itself on the wrong grounds:

> cmark-gfm remains a DEVELOPMENT dependency, and that is why its notice is
> reproduced here in full

That does not hold. A development dependency that is never redistributed
carries no reproduction obligation; a cloner fetches the submodule from
GitHub with its own LICENSE inside it.

The real obligation is transcribed expression in shipped source:

| This tree | Transcribed from | Upstream license |
|---|---|---|
| `src/cmark/gfm/sxml.sls:97-108`, the `HREF_SAFE` set | `houdini_href_e.c:32-45` | MIT, vmg/houdini, (C) 2012 Vicent Marti |
| `src/cmark/gfm/sxml.sls:153-174`, the dangerous-scheme rule | `scanners.re:345-354` | BSD-3, cmark-gfm |
| `tests/spec-corpus.sls`, the corpus parser | `test/spec_tests.py:89-120` | BSD-3, cmark's `test/` software |

The first was verified against the vendored source rather than taken from
the comment: bytes 32-47 of `HREF_SAFE` are
`0,1,0,1,1,1,0,0,1,1,1,1,1,1,1,1` — space and `"` unsafe, `&` and `'`
unsafe — matching the `!#$%()*+,-./` set `sxml.sls` carries and its note
that `&` and `'` are excluded because houdini entity-escapes them
separately. A transcribed lookup table carries expression across a language
port.

**Action:** keep NOTICE; reduce it to the two licenses actually implicated
(cmark-gfm BSD-3, houdini MIT); replace the rationale with the table above.

Removed, because nothing in this tree derives from them: utf8proc,
`buffer.c`/`chunk.h` (GitHub Inc.), `normalize.py`, and the CommonMark
spec's CC-BY-SA. The 744-example corpus is read from the submodule at test
time and never copied in; `tests/fixtures/*.md` are hand-written.

This is an engineering judgement, not legal advice. The cautious reading
and the accurate one agree here.

## 5. Community health files

- `CONTRIBUTING.md` — setup, the gates a PR must keep green (`test`,
  `check-pins`, `check-purity`, `test-memory`), Conventional Commits,
  branch naming, and the mutation-log discipline from AGENTS.md.
- `SECURITY.md` — private reporting via GitHub Security Advisories,
  supported versions, and a note that native-boundary reports are
  especially welcome. Asks for `make build` output, which names the exact
  libraries discovered.
- `.github/ISSUE_TEMPLATE/bug_report.md`, `feature_request.md`,
  `.github/PULL_REQUEST_TEMPLATE.md` — adapted from `chez-libuv`.

No `CODE_OF_CONDUCT.md`.

## 6. Coupled machinery

Moving prose out of `README.org` disarms checks that name it. AGENTS.md's
first trap is exactly this failure, seven times in one branch. Each item
below is repointed **and** proven still able to fail.

| Site | Today | After |
|---|---|---|
| `ci.yml:107` | greps `README.org` for the Linux matrix row | greps `docs/installing.md` |
| `ci.yml:242` | greps `README.org` for the macOS matrix row | greps `docs/installing.md` |
| `ci.yml:108-113`, `243-248` | `::error::` text naming README.org | names `docs/installing.md` |
| `ci.yml:323, 343, 359, 410` | comments and a step name citing "the README" | cite `docs/installing.md` |
| `tests/preflight.sps:66` | "README.org, \"RHEL, Fedora, and Alpine\"" | `docs/installing.md` |

The matrix greps fail loudly when a row goes missing, so they cannot rot
silently. The preflight string is prose printed to a user and would go
stale invisibly; it changes in the same commit.

## 7. Verification

Per AGENTS.md, a check is finished when it has been watched to fail.

| Check | Mutation that must make it fail |
|---|---|
| `check-help` | add a `.PHONY` target with no `## ` description |
| `check-install` | break `install`'s copy step so the tree lands empty |
| `check-install` (probe strength) | with the install tree emptied, replace the probe's `markdown->html` call with a bare import. It must **still** fail. If it passes, the probe is import-only and proves nothing — AGENTS.md trap 4. |
| `ci.yml` matrix greps | edit the Chez version in the `docs/installing.md` row |
| `make examples` | unchanged; it already gates the samples the docs cite |

Each mutation is recorded in `.plans/publishing-prep-mutation-log.md`
with the assertion that failed, by name. Named for the work rather than
a stage number: the `stage-N` series stopped at 6, and 2.0's shimless-FFI
release added none, so there is no stage 7 to continue.

## 8. Out of scope

- No library behaviour changes; no new exports.
- No `check-docs` link checker. Considered and declined for this pass.
- No `CODE_OF_CONDUCT.md`.
- No Akku index submission.
- `.plans/` is untouched apart from this spec and the mutation log.
