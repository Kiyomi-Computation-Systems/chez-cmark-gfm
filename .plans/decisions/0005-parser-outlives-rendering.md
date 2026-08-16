# ADR-0005: The parser outlives rendering

- **Status:** Accepted
- **Date:** 2026-08-16
- **Scope:** chez-cmark-gfm v1
- **Related:** [design spec](../2026-08-16-chez-cmark-gfm-design.md), corrects plan §8.2

## Context

Plan §8.2 orders the parse lifecycle as: *…6. finish parsing → 7. free the parser →
8. render or copy the AST → 9. free the root.*

Verified in `cmark-gfm/src/blocks.c`:

```c
void cmark_parser_free(cmark_parser *parser) {
  cmark_mem *mem = parser->mem;
  cmark_parser_dispose(parser);
  cmark_strbuf_free(&parser->curline);
  cmark_strbuf_free(&parser->linebuf);
  cmark_llist_free(parser->mem, parser->syntax_extensions);        /* <-- */
  cmark_llist_free(parser->mem, parser->inline_syntax_extensions);
  mem->free(parser);
}
```

`cmark_parser_get_syntax_extensions` returns `parser->syntax_extensions` — precisely
the list freed above. The renderer signature is:

```c
char *cmark_render_html(cmark_node *root, int options, cmark_llist *extensions);
```

So on the **render** path, step 7 frees the extension list that step 8 hands to the
renderer: a dangling `cmark_llist *`, in the default configuration where extensions
are enabled.

The AST-copy path is unaffected. That asymmetry is what makes the defect dangerous —
one of the two paths sharing the sequence is correct, so it survives casual review and
manifests only with extensions on.

## Decision

The parser outlives rendering. Teardown is strict reverse of acquisition, freeing the
renderer buffer first and the parser last:

```
R1  chez_cmark_free_buffer     (render path only)
R2  cmark_node_free(root)
R3  cmark_parser_free          (last)
```

Rejected alternative: build an independent `cmark_llist` from
`cmark_find_syntax_extension` results and free it with `cmark_llist_free`. This also
works but adds a container to own for no benefit; holding the parser marginally longer
costs nothing.

## Consequences

- Parser memory is held slightly longer, which is immaterial.
- A mutation test is mandatory: reintroducing the plan §8.2 order must fail a
  table/strikethrough render test under ASan.
- Stage 0 writes the buggy ordering deliberately and confirms ASan reports it, which
  validates both this finding and that the sanitizer harness works at all.

## Verified as correct in the plan

Two adjacent claims were checked and hold, and are retained unchanged:

- `cmark_parser_finish` detaches the root (`parser->root = NULL`), so the root
  survives `cmark_parser_free` — plan §9.1 rule 5.
- Registered extensions are library-owned and must never be freed by the binding —
  plan §9.5. Note `cmark_llist_free` frees list containers only, not the data they
  point at, so the registry objects survive correctly.
