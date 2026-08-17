# ADR-0012: Verify the SXML tree against cmark's own HTML rendering

- **Status:** Accepted
- **Date:** 2026-08-17
- **Scope:** chez-cmark-gfm 0.3
- **Related:** [Stage 5 design](../2026-08-17-stage-5-sxml-design.md) §6 · ADR-0010, ADR-0011

## Context

ADR-0010 verified the AST by re-serializing it into cmark's XML dialect and
diffing against cmark's own bytes, on the grounds that an expectation produced by
cmark cannot be tuned to accommodate a converter bug. The SXML adapter needs the
same guarantee and has no XML equivalent — cmark emits no SXML.

It does emit HTML, and `markdown->html` was proved byte-equal to the pinned CLI in
Stage 2 across 24 option configurations. `vendor/cmark-gfm/test/` additionally
ships 744 example documents, pinned to the same submodule commit the library links
against.

## Decision

A test-only serializer, written against `vendor/cmark-gfm/src/html.c`, renders our
SXML tree into HTML. The result is compared byte-for-byte against `markdown->html`
for the same parse, over all 744 corpus examples, first in-process and then
against the pinned CLI.

The serializer is generic over the tree. It maps an element name to a tag, an
attribute list to attributes, and consults a static table for childless tags and
newline placement. It never inspects the Markdown.

## Consequences

- A wrong tag, a dropped or reordered child, a missing `thead`, a `<p>` emitted
  inside a tight list, a mis-encoded URL, or a wrong `align` all surface as a byte
  difference.
- The serializer's genericity is what stops it compensating for an adapter bug.
  It has no node-type knowledge, so it cannot map `em` to `<strong>` to make a
  wrong tree agree. Its one point of leverage is the static tag table, and a wrong
  entry there is itself a byte difference.
- **Both legs are needed, for a different reason than ADR-0010's.** Our SXML path
  and `markdown->html` both consume a document parsed through our shim, so a wrong
  option bit or a missing extension corrupts the parse feeding both sides — they
  would agree while both being wrong. The CLI witnesses that the parse was
  configured correctly.
- Combined with ADR-0011, the oracle is total: nothing in the tree is invisible to
  it, so no property needs a direct assertion beside it. One of ADR-0010's three
  blind spots closes here — the HTML renderer emits `align` on body cells
  (`extensions/table.c:806`), which the XML renderer withheld. The other two are
  not gaps but non-subjects: `item` index is not carried into SXML, and table
  `columns` is never read, because the adapter builds cells from the row's
  children rather than from the count.
- Byte-equality is a property of *this* serializer, not of one a caller picks.
  cmark escapes `"` in text and `'` in hrefs, and writes childless elements as
  ` />`; a conforming third-party serializer will differ on all three while
  producing equivalent HTML. That is documented, not tested for.
- `raw-html: escape` sits outside this oracle, because cmark has no equivalent
  behaviour. It carries direct assertions and is recorded as a deliberate gap.
- The corpus parser asserts the number of examples it extracted. A parser that
  silently matched nothing would otherwise report 744 passes against no work.
