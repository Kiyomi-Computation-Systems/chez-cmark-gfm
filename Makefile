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
  CMARK_DLLS   := $(CMARK_LIBDIR)/libcmark-gfm.$(SHLIB_EXT) \
                  $(CMARK_LIBDIR)/libcmark-gfm-extensions.$(SHLIB_EXT)
  CMARK_CLI    := cmark-gfm
else
  CMARK_CFLAGS := -I$(VENDOR_BUILD)/src -I$(VENDOR_DIR)/src \
                  -I$(VENDOR_DIR)/extensions
  # The vendored copy is built and linked as SHARED libraries (design spec
  # 6.1), never static. cmark-gfm's static archives are built with
  # CMAKE_C_VISIBILITY_PRESET hidden plus CMARK_GFM_STATIC_DEFINE, which
  # hides every cmark symbol from whatever links them. native.sls resolves
  # cmark's entry points directly via foreign-procedure at runtime, so those
  # symbols have to stay visible in a real shared object -- static linking
  # cannot satisfy that no matter what the archives are named.
  #
  # Each shared library gets its own -Wl,-rpath entry, absolute and recorded
  # at build time, so the shim resolves them at load time with no system
  # library search and no dependence on the working directory or
  # LD_LIBRARY_PATH/DYLD_LIBRARY_PATH -- the same guarantee the pkg-config
  # path gets from the installed library's own rpath/soname handling.
  #
  # Extensions FIRST, then core, on the link line: kept from the static case
  # for consistency, though it no longer determines symbol resolution --
  # shared objects carry their own recorded dependencies (libcmark-gfm-
  # extensions already depends on libcmark-gfm via its own CMake target).
  CMARK_VENDOR_LIBDIR_EXT := $(abspath $(VENDOR_BUILD)/extensions)
  CMARK_VENDOR_LIBDIR_SRC := $(abspath $(VENDOR_BUILD)/src)
  CMARK_LIBS   := -L$(CMARK_VENDOR_LIBDIR_EXT) -lcmark-gfm-extensions \
                  -L$(CMARK_VENDOR_LIBDIR_SRC) -lcmark-gfm \
                  -Wl,-rpath,$(CMARK_VENDOR_LIBDIR_EXT) \
                  -Wl,-rpath,$(CMARK_VENDOR_LIBDIR_SRC)
  CMARK_DLLS   := $(CMARK_VENDOR_LIBDIR_SRC)/libcmark-gfm.$(SHLIB_EXT) \
                  $(CMARK_VENDOR_LIBDIR_EXT)/libcmark-gfm-extensions.$(SHLIB_EXT)
  CMARK_CLI    := $(abspath $(VENDOR_BUILD)/src/cmark-gfm)
endif

SRFI_SRC     := vendor/chez-srfi
SRFI_LIBS    := $(BUILD_DIR)/scheme-libs
CHEZ_LIBDIRS := src:tests:$(SRFI_LIBS)
TESTS        := $(wildcard tests/test-*.sps)

# The differential suite spawns ~400 cmark-gfm subprocesses. Those are separate
# processes and are NOT instrumented by the memory tools, so they add no
# coverage here -- test-render.sps already exercises every native allocation
# this stage introduces. Excluded by name so the omission is visible.
#
# test-ast-differential.sps also spawns subprocesses -- its own pinned-CLI leg
# -- but stays IN, unlike test-differential.sps above: it has a FIRST leg that
# runs in-process, comparing our AST's XML serialization against cmark's own
# render-xml on the same live root, which allocates and frees native objects
# inside this very Chez process before the CLI leg ever runs. That is exactly
# what Valgrind/ASan need to see, so excluding this suite would drop coverage
# no other suite provides (design spec 2026-08-17-stage-3-ast-design.md 9.1).
MEMORY_TESTS := $(filter-out tests/test-differential.sps,$(TESTS))

.PHONY: all build deps check-pins check-purity dev test test-memory vendor clean prod deps-info

all: build

deps-info:
	@echo "cmark-gfm source : $(if $(filter yes,$(HAVE_PKG)),pkg-config,vendored)"
	@echo "shim             : $(SHIM)"
	@echo "cmark-gfm CLI    : $(CMARK_CLI)"

build: $(SHIM) $(CONFIG_SLS)

# Scheme dependencies. chez-srfi is vendored as a submodule pinned to the SAME
# commit Akku.lock names (7879b52). Keep them equal: bumping the Akku dependency
# without re-pinning the submodule means consumers and CI test different code,
# and nothing here would notice. Akku itself is
# deliberately NOT on this path: it has no prebuilt binary, and its downloader
# fails on some hosts with CURLE_URL_MALFORMED. Akku.manifest/Akku.lock remain
# the consumer-facing declaration.
#
# chez-srfi ships Akku's percent-encoded filenames (%3a64.sls). Chez resolves
# (srfi :64) only from the decoded spelling, so link both into a build tree and
# leave the submodule's own working tree untouched.
# The submodule pin and Akku.lock name the same chez-srfi commit, and nothing
# else enforces that. They drifted within minutes of the rule being written: a
# `git submodule update --init` (from `deps`, below) resets the working tree to
# the RECORDED gitlink, silently undoing a manual detach that had not been
# staged yet. So this is a check, not a comment.
check-pins:
	@rec=$$(git ls-files -s $(SRFI_SRC) | awk '{print $$2}'); \
	lock=$$(sed -n 's/.*akku\.[0-9]*\.\([a-f0-9]*\)_repack.*/\1/p' Akku.lock | head -1); \
	if [ -z "$$rec" ] || [ -z "$$lock" ]; then \
	  echo "check-pins: could not read both pins (submodule='$$rec' lock='$$lock')" >&2; \
	  exit 1; \
	fi; \
	case "$$rec" in \
	  "$$lock"*) echo "pins agree: chez-srfi $$lock" ;; \
	  *) echo "PIN DRIFT: submodule $$rec but Akku.lock names $$lock." >&2; \
	     echo "Consumers install what Akku.lock names; CI tests the submodule." >&2; \
	     exit 1 ;; \
	esac

# options.sls and ast.sls must import no library that loads a shared object,
# directly or transitively (each file's own header comment states this).
# That purity is what makes every assertion in tests/test-ast.sps and
# tests/test-sxml.sps unable to pass by accident because of native
# behaviour -- they exercise Scheme values only.
#
# tests/test-options.sps dropped out of this loop in Stage 5 Task 8: it now
# imports (cmark gfm) to cover markdown->sxml, so poisoning the shim faults
# it at library-instantiation time before a single assertion runs, for a
# reason that has nothing to do with options.sls's own purity (native.sls's
# top-level shim load runs on import alone, whether or not anything calls
# markdown->sxml). options.sls stays covered anyway: test-sxml.sps below
# also imports (cmark gfm options), so a real regression there still fails
# this loop.
# Poisoning CHEZ_CMARK_GFM_SHIM with a path that looks absolute but does not
# exist is a probe: if nothing in the suite's import chain ever reaches
# (cmark gfm private native), the variable is never even read and the suite
# passes untouched; if anything does reach it, native.sls's library body
# raises &cmark-shim-unavailable at IMPORT time, before a single test runs,
# and the suite fails outright. Per AGENTS.md ("prefer a check to a
# comment"): the check-pins comment above was itself violated in the same
# commit that introduced it, and only started holding once it became a
# check. This is the same lesson applied to the options.sls and ast.sls
# boundary.
#
# Caveat proven while wiring this up: Chez only instantiates an imported
# library's body when something actually REFERENCES one of its bindings, so
# an import added to options.sls or ast.sls but never called is invisible to
# this check -- it is the same elision that lets an unused import pass
# silently elsewhere. That is not a gap in practice: a real accidental
# dependency is something one of them actually CALLS, and that is exactly
# what trips this.
check-purity: build deps
	@fail=0; \
	for t in tests/test-ast.sps tests/test-sxml.sps; do \
	  echo "=== check-purity: $$t, CHEZ_CMARK_GFM_SHIM poisoned ==="; \
	  if CHEZ_CMARK_GFM_SHIM=/nonexistent CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	      $(CHEZ) --program $$t; then \
	    echo "purity holds: $$t pulled in no native code"; \
	  else \
	    echo "PURITY VIOLATED: $$t failed with CHEZ_CMARK_GFM_SHIM poisoned" >&2; \
	    echo "to a nonexistent path. Its import chain now reaches" >&2; \
	    echo "(cmark gfm private native), which loads a shared object -- check" >&2; \
	    echo "what it (or something it imports) just started pulling in." >&2; \
	    fail=1; \
	  fi; \
	done; \
	exit $$fail

# Always relinks rather than using a stamp file: a stamp keyed on nothing the
# submodule pin touches would leave stale symlinks after a re-pin. `ln -sfn` is
# idempotent and the whole loop is well under a second.
deps:
	git submodule update --init $(SRFI_SRC)
	mkdir -p $(SRFI_LIBS)/srfi
	src=$(abspath $(SRFI_SRC)); dst=$(abspath $(SRFI_LIBS))/srfi; \
	for f in $$src/*; do \
	  b=$$(basename "$$f"); \
	  ln -sfn "$$f" "$$dst/$$b"; \
	  d=$$(printf '%s' "$$b" | sed 's/%3a/:/g'); \
	  [ "$$d" = "$$b" ] || ln -sfn "$$f" "$$dst/$$d"; \
	done

$(LIB_DIR):
	mkdir -p $(LIB_DIR)

ifeq ($(HAVE_PKG),no)
$(SHIM): vendor
endif

# Which acquisition path last built the shim. The name encodes the mode, so
# flipping HAVE_PKG makes the prerequisite change identity and forces a relink.
# Without this, `make HAVE_PKG=no build && make build` leaves the vendored-linked
# shim in place -- make sees the .c unchanged and skips it -- so the two exit-gate
# runs would silently test the same artifact twice.
ACQ_MODE  := $(if $(filter yes,$(HAVE_PKG)),pkgconfig,vendored)
ACQ_STAMP := $(BUILD_DIR)/.acquisition-$(ACQ_MODE)

$(ACQ_STAMP): | $(LIB_DIR)
	rm -f $(BUILD_DIR)/.acquisition-*
	touch $@

$(SHIM): src/cmark-gfm-shim.c src/cmark-gfm-shim.h $(ACQ_STAMP) | $(LIB_DIR)
	$(CC) $(CFLAGS_DEV) $(CMARK_CFLAGS) $(SHLIB_LDFLAGS) \
	      -o $@ src/cmark-gfm-shim.c $(CMARK_LIBS)

# config.sls carries the shim's ABSOLUTE path so the loader never searches.
# Depends on the Makefile too: this file's contents are generated by the recipe
# below, so a change here must regenerate it. Without that, editing the recipe
# leaves a stale config.sls that looks correct and describes the previous build.
$(CONFIG_SLS): $(SHIM) Makefile
	@mkdir -p $(dir $@)
	@printf '%s\n' \
	  '#!r6rs' \
	  ';; GENERATED by make -- do not edit, do not commit.' \
	  '(library (cmark gfm private config)' \
	  '  (export shim-path cmark-library-paths cmark-supported-version-range)' \
	  '  (import (rnrs))' \
	  '  (define shim-path "$(abspath $(SHIM))")' \
	  '  ;; cmark shared objects, loaded explicitly before the shim. On Linux' \
	  '  ;; a dlopen'"'"'d library'"'"'s dependencies are NOT in the global symbol' \
	  '  ;; namespace, so binding cmark entry points through the shim alone' \
	  '  ;; fails there while working on macOS.' \
	  '  (define cmark-library-paths (quote ($(foreach l,$(CMARK_DLLS),"$(l)"))))' \
	  '  (define cmark-supported-version-range (quote (#x001d0000 . #x001dffff))))' \
	  > $@

vendor:
	git submodule update --init --recursive
	cmake -S $(VENDOR_DIR) -B $(VENDOR_BUILD) \
	  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	  -DCMARK_TESTS=OFF -DCMARK_SHARED=ON -DCMARK_STATIC=OFF
	cmake --build $(VENDOR_BUILD) -j

dev: build deps
	CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ)

# Each suite sets its own exit status. Keep going after a failure so one
# broken suite cannot hide the others, then fail the target if any failed.
test: build deps check-pins
	@fail=0; \
	for t in $(TESTS); do \
	  echo "=== $$t ==="; \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) CMARK_CLI=$(CMARK_CLI) $(CHEZ) --program $$t || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "ALL SUITES PASSED"; \
	else echo "SUITE FAILED"; fi; \
	exit $$fail

test-memory: build deps check-pins
ifeq ($(UNAME_S),Linux)
	@for t in $(MEMORY_TESTS); do \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) CMARK_CLI=$(CMARK_CLI) valgrind --error-exitcode=9 \
	    --leak-check=full --show-leak-kinds=definite \
	    $(CHEZ) --program $$t || exit 1; \
	done
else
	@echo "macOS: ASan preload only; LeakSanitizer is unsupported on arm64."
	@echo "Leak claims must come from Linux CI (ADR-0003)."
# MallocNanoZone=0: macOS's Nano allocator validates a freed block's own
# metadata and can SIGTRAP on a double-free before ASan's interposed free()
# gets a chance to run its check -- an unattributed crash (bare "Trace/BPT
# trap") instead of the diagnostic this target exists to provide. Observed
# on this exact recipe; see stage-2-mutation-log.md, Mutation C.
	CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	  CMARK_CLI=$(CMARK_CLI) \
	  DYLD_INSERT_LIBRARIES="$$(command ls $$(dirname $$(xcrun --find clang))/../lib/clang/*/lib/darwin/libclang_rt.asan_osx_dynamic.dylib | head -1)" \
	  ASAN_OPTIONS=detect_leaks=0 \
	  MallocNanoZone=0 \
	  sh -c 'for t in $(MEMORY_TESTS); do $(CHEZ) --program $$t || exit 1; done'
endif

# prod compiles directly rather than reusing $(SHIM), so it needs the same
# vendored-build gate that $(SHIM) gets above; without it `make prod` fails on
# a machine where pkg-config cannot see cmark-gfm.
ifeq ($(HAVE_PKG),no)
prod: vendor
endif

prod: clean
	mkdir -p $(LIB_DIR)
	$(CC) $(CFLAGS_PROD) $(CMARK_CFLAGS) $(SHLIB_LDFLAGS) \
	      -o $(SHIM) src/cmark-gfm-shim.c $(CMARK_LIBS)
	$(MAKE) $(CONFIG_SLS)

clean:
	rm -rf $(BUILD_DIR) $(CONFIG_SLS)
