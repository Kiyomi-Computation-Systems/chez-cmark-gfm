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
CHEZ_LIBDIRS := src:$(SRFI_LIBS)
TESTS        := $(wildcard tests/test-*.sps)

# The differential suite spawns ~400 cmark-gfm subprocesses. Those are separate
# processes and are NOT instrumented by the memory tools, so they add no
# coverage here -- test-render.sps already exercises every native allocation
# this stage introduces. Excluded by name so the omission is visible.
MEMORY_TESTS := $(filter-out tests/test-differential.sps,$(TESTS))

.PHONY: all build deps check-pins dev test test-memory vendor clean prod deps-info

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
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) valgrind --error-exitcode=9 \
	    --leak-check=full --show-leak-kinds=definite \
	    $(CHEZ) --program $$t || exit 1; \
	done
else
	@echo "macOS: ASan preload only; LeakSanitizer is unsupported on arm64."
	@echo "Leak claims must come from Linux CI (ADR-0003)."
	CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	  DYLD_INSERT_LIBRARIES="$$(command ls $$(dirname $$(xcrun --find clang))/../lib/clang/*/lib/darwin/libclang_rt.asan_osx_dynamic.dylib | head -1)" \
	  ASAN_OPTIONS=detect_leaks=0 \
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
