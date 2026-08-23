# API-reference mutation log

Evidence that the checks added for
`.plans/2026-08-23-api-reference-design.md` fail through the property they
claim to guard. Every mutation below was applied to a scratch copy under
`/tmp`, with that copy placed first on `CHEZSCHEMELIBDIRS`; the repository
copy remained unchanged.

## Baseline

Before implementation, `make test`, `make check-site`, and `make check-help`
were green on commit `b2942c3`. The first run of the new
`tests/test-reference.sps` then failed because `(site reference)` did not yet
exist. After the pure core was implemented, the clean suite reported 24
expected passes.

## A. Export extraction cannot undercount

**Guards:** every symbol in an R6RS export clause reaches the source API set,
in declaration order.

**Mutation:** changed `library-datum->api` in a scratch
`site/reference.sls` to drop the final export from every clause.

**Result:** FAILED by name:
`FAIL every symbol export is preserved in declaration order`; 23 expected
passes, 1 unexpected failure.

**Clean rerun:** 24 expected passes.

## B. Fenced headings cannot masquerade as entries

**Guards:** API-looking Markdown inside a fenced code block is example content,
not a documented binding entry.

**Mutation:** disabled the parser's `in-fence?` opaque-content branch while
leaving the h3 recognizer active.

**Result:** FAILED by name:
`FAIL prose, fenced headings, and index links are not API entries`; 23
expected passes, 1 unexpected failure. The failure came from the fenced h3
flowing through the actual entry recognizer, not from syntax or import.

**Clean rerun:** 24 expected passes.

## C. Duplicate entries remain visible

**Guards:** converting entry names to a set cannot erase duplicate evidence.

**Mutation:** applied `unique-equal` before `duplicates-equal` in the scratch
diagnostic path.

**Result:** FAILED by name:
`FAIL duplicate binding headings survive parsing and fail by name`; 23
expected passes, 1 unexpected failure.

**Clean rerun:** 24 expected passes.

## D. Availability metadata is not a substantive body

**Guards:** a binding heading and its machine-checked module line alone do not
count as useful documentation.

**Mutation:** forced every finalized reference entry's `body?` field to `#t`,
regardless of the lines actually parsed.

**Result:** FAILED by name:
`FAIL availability metadata alone is not a substantive body`; 23 expected
passes, 1 unexpected failure.

**Clean rerun:** 24 expected passes.

## E. Per-binding module membership is checked

**Guards:** an entry's `Available from` modules equal the source modules that
actually export that binding, in both directions.

**Mutation:** replaced the computed `membership-mismatches` value with the
empty list.

**Result:** FAILED by name:
`FAIL per-binding module membership is checked in both directions`; 23
expected passes, 1 unexpected failure.

**Clean rerun:** 24 expected passes.

## F. Empty source and empty documentation cannot agree successfully

**Guards:** a broken discovery path and a broken reference parser cannot both
return `()` and make set equality look like success.

**Mutation:** disabled all four `no-public-*` / `no-reference-*` diagnostics.

**Result:** FAILED by four precise names:

- `FAIL empty source discovery can never be success`
- `FAIL empty public exports can never be success`
- `FAIL empty module documentation can never be success`
- `FAIL empty binding documentation can never be success`

The mutated run reported 20 expected passes and 4 unexpected failures.

**Clean rerun:** 24 expected passes.

## G. The right rail stops at top-level sections

**Guards:** h3 API entries remain rendered link targets and stay in the anchor
registry, but only h2 sections appear in the `On this page` rail.

**Mutation:** changed the scratch `rail-toc` predicate from heading level `= 2`
back to the old `> 1`, which admits h3 entries.

**Result:** FAILED by name:
`FAIL the rail lists h2 sections, not h3 binding details`; 8 expected passes,
1 unexpected failure. The companion assertion that the h3 still rendered as
an `id` passed, isolating the failure to rail membership.

**Clean rerun:** 9 expected passes.

## H. A deleted entry is missing

**Mutation:** deleted the complete `markdown->html` entry from a clean scratch
reference page.

**Result:** `check-reference: missing-bindings=(markdown->html)`; exit 1.

## I. A heading typo is both missing and extra

**Mutation:** renamed only the `markdown->html` heading to
`markdown->htlm`, leaving its body intact.

**Result:** `missing-bindings=(markdown->html)` and
`extra-bindings=(markdown->htlm)`; exit 1.

## J. A duplicate entry remains an error

**Mutation:** duplicated the complete `markdown->html` entry.

**Result:** `duplicate-bindings=(markdown->html)`; exit 1.

## K. Metadata alone is not documentation

**Mutation:** retained the `markdown->html` heading and its `Available from`
line, but deleted its signature, prose, raises, and details.

**Result:** `empty-entry-bodies=(markdown->html)`; exit 1. The binding was not
misreported as missing.

## L. Every public module needs a table row

**Mutation:** deleted only the `(cmark gfm sxml)` row from `## Modules`.

**Result:** `missing-modules=((cmark gfm sxml))`; exit 1.

## M. Availability must match the exporting modules

**Mutation:** removed only `(cmark gfm render)` from `markdown->html`'s
`Available from` line.

**Result:** `module-membership-mismatches` named `markdown->html`, the actual
modules `((cmark gfm) (cmark gfm render))`, and the documented modules
`((cmark gfm))`; exit 1.

## N. Source undercount cannot agree with the reference

**Mutation:** changed export extraction in a scratch `(site reference)` to
drop the sole non-umbrella binding `extension->native-name`.

**Result:** `extra-bindings=(extension->native-name)`; exit 1. The source side
could not silently undercount and pass.

**Clean real-tree rerun:** `check-reference: COMPLETE -- 6 modules, 85 unique
bindings`.

## Final clean verification

- `make test`: all 22 suites passed; the new reference suite reported 24
  expected passes and the rendered-site suite reported 9.
- `make check-reference`: complete at 6 modules and 85 unique bindings.
- `make check-site`: navigation, anchors, `.md` leakage, and `<pre>` reflow all
  green.
- `make site`: wrote 10 pages to `build/site`.
- `make check-help` and `git diff --check`: green.

The generated `reference.html` contains 85 h3 ids, 85 alphabetical-index
links, and 9 h2 links in the right rail. Its previous and next links are Usage
and Options, and condition names and signature arrows are HTML-escaped.

Direct browser inspection of the local generated file was not completed: the
available in-app browser rejected the `file:` URL under its URL safety policy,
and no alternate browser route was used. Static generated-HTML and responsive
CSS inspection confirmed the structural points above, including the 900px
rail cutoff, the 640px single-column navigation layout, and horizontal
overflow for code blocks; this is not claimed as a visual rendering result.
