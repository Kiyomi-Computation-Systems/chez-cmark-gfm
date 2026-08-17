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

/* Tasklist checked state, normalised to int.
 *
 * cmark_gfm_extensions_get_tasklist_item_checked returns C _Bool. On the
 * x86-64 SysV ABI a _Bool return occupies only the low byte of the return
 * register, with the upper bits unspecified, so binding that entry point
 * directly as `int` would read whatever happens to be there. Normalising in C
 * -- where the return type is known to the compiler -- is exactly the
 * "stable, Chez-friendly function" job plan 8.1 assigns the shim, and adds no
 * traversal, parsing, or rendering (ADR-0002).
 *
 * Returns 1 if node is a checked task-list item, 0 otherwise (including for
 * a node that is not a task-list item at all).
 *
 * `struct cmark_node` is forward-declared at file scope (rather than left to
 * be introduced implicitly by the parameter list below) because a tag whose
 * first appearance is inside a function's parameter-type-list has prototype
 * scope only (C99 6.2.1p7): it does not extend to cmark-gfm-shim.c's
 * definition of this same function, so without this line the header's
 * `struct cmark_node` and the .c file's are two distinct, incompatible
 * incomplete types, and the two declarations of chez_cmark_tasklist_checked
 * conflict -- a hard error, independent of -Werror. */
struct cmark_node;
int chez_cmark_tasklist_checked(struct cmark_node *node);

#endif /* CHEZ_CMARK_GFM_SHIM_H */
