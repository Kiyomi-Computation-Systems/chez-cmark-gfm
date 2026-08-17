#include "cmark-gfm-shim.h"

#include <cmark-gfm.h>
#include <cmark-gfm_version.h>
#include <cmark-gfm-core-extensions.h>

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

int chez_cmark_tasklist_checked(struct cmark_node *node) {
  return cmark_gfm_extensions_get_tasklist_item_checked((cmark_node *)node) ? 1 : 0;
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
