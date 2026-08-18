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

# Which flags link the shim. dev is the default; `make prod` re-enters make
# with FLAVOR=prod so the whole graph -- shim, config.sls, stamps -- agrees
# on one flavor. Guarded because this variable's one failure mode is a typo
# silently falling back to dev and shipping the wrong artifact.
FLAVOR ?= dev
ifeq ($(FLAVOR),dev)
  CFLAGS_SHIM := $(CFLAGS_DEV)
else ifeq ($(FLAVOR),prod)
  CFLAGS_SHIM := $(CFLAGS_PROD)
else
  $(error FLAVOR must be dev or prod, got '$(FLAVOR)')
endif

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
SXMLT_SRC    := vendor/wak-sxml-tools
COMMON_SRC   := vendor/wak-common
SRFI_LIBS    := $(BUILD_DIR)/scheme-libs
# src FIRST, fallback SECOND, and the order is the mechanism: Chez resolves a
# library from the first entry that has it, so the generated
# src/cmark/gfm/private/config.sls shadows fallback/'s checked-in sentinel
# whenever a build has happened. Reversing these two makes every native suite
# fail with reason 'not-built against a perfectly good build.
# tests/test-fallback-config.sps asserts the ordering directly.
CHEZ_LIBDIRS := src:fallback:tests:$(SRFI_LIBS)
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
#
# test-sxml-differential.sps is the THIRD differential suite and the heaviest
# in-process, and it stays IN for the same reason test-ast-differential.sps
# does, only more so. Its main leg parses all 744 corpus examples through
# markdown->ast and then again through markdown->html, once per attribute
# marker -- 744 x 2 sides x 2 markers is ~3000 parses before the option
# matrix and the unsupported-node sweep add their own -- every one of them
# allocating and freeing cmark objects inside this Chez process. Nothing
# else in the suite puts that
# volume or that variety of document through the native allocator, so this
# is the single largest block of instrumented coverage the memory target
# gets. The adapter itself allocates nothing native (it is pure Scheme, which
# is what `make check-purity` gates), but the parse feeding it is not, and
# that is what is under the tool here.
#
# Its own CLI leg is the four fixtures under two markers -- eight
# subprocesses, uninstrumented like every other subprocess above, and far too
# few to be worth excluding the suite over. That is the whole reason the
# in/out judgement lands differently here than for test-differential.sps: the
# question is never "does it spawn subprocesses" but "is there instrumented
# work that would be lost".
MEMORY_TESTS := $(filter-out tests/test-differential.sps,$(TESTS))

.PHONY: all build deps check-pins check-purity check-prod dev test test-memory vendor clean prod deps-info

all: build

deps-info:
	@echo "cmark-gfm source : $(if $(filter yes,$(HAVE_PKG)),pkg-config,vendored)"
	@echo "shim             : $(SHIM)"
	@echo "cmark-gfm CLI    : $(CMARK_CLI)"

build: $(SHIM) $(CONFIG_SLS)

# Scheme dependencies. chez-srfi, wak-sxml-tools, and wak-common are each
# vendored as a submodule pinned to the SAME commit Akku.lock names. Keep them
# equal: bumping the Akku dependency without re-pinning the submodule means
# consumers and CI test different code, and nothing here would notice. Akku
# itself is deliberately NOT on this path: it has no prebuilt binary, and its
# downloader fails on some hosts with CURLE_URL_MALFORMED. Akku.manifest/
# Akku.lock remain the consumer-facing declaration.
#
# chez-srfi ships Akku's percent-encoded filenames (%3a64.sls). Chez resolves
# (srfi :64) only from the decoded spelling, so link both into a build tree and
# leave the submodule's own working tree untouched.
#
# wak-sxml-tools's own repo root has no `wak/` directory -- `(wak sxml-tools
# serializer)` is exported from sxml-tools/serializer.sls, so the symlink
# below aliases that directory straight to build/scheme-libs/wak/sxml-tools.
# Confirmed by `find vendor/wak-sxml-tools -name 'serializer*'`; a brief that
# assumed a `wak/sxml-tools/` layout was wrong about this.
#
# wak-sxml-tools's serializer.sls is not self-contained: it imports
# (wak private include), which lives in a SEPARATE package, wak-common --
# discovered by actually importing (wak sxml-tools serializer) and watching
# it fail with "library (wak private include) not found", then confirmed via
# `akku lock`, which resolves wak-common (and wak-ssax, unused by this one
# import chain and so not vendored) as transitive dependencies. wak-common is
# therefore vendored the same way, pinned to the commit `akku lock` names.
# Its (wak private include compat) library ships one file per Scheme
# implementation (compat.chezscheme.sls, compat.guile.sls, ...), each
# declaring the SAME library name; Akku's installer picks one and renames it
# to compat.sls at install time. Bypassing that installer (same reason as
# above) means this recipe must do the same rename -- the same kind of
# filename massaging as chez-srfi's percent-encoding fix above, just for a
# different naming convention.
#
# Every top-level private/*.sls file is linked, not just include.sls: the
# package also ships private/define-values.sls and private/let-optionals.sls
# beside it, unused by today's one import chain and so easy to miss by
# naming only the file that IS used. Naming files individually is exactly
# how include.sls ended up alone here the first time; a re-pin that made
# (wak private include) reach either of the other two would fail at TEST
# time with library-not-found, not at deps time where a missing link is far
# easier to diagnose. Globbing costs nothing extra today and removes that
# gap for any file this directory gains later, known about or not.
#
# The submodule pins and Akku.lock name the same commits, and nothing else
# enforces that. chez-srfi's drifted within minutes of the rule being
# written: a `git submodule update --init` (from `deps`, below) resets the
# working tree to the RECORDED gitlink, silently undoing a manual detach that
# had not been staged yet. So this is a check, not a comment.
#
# The lock= extraction below matches the URL line whose LAST PATH SEGMENT
# starts with "name_" -- e.g. .../w/wak-common_0.1.0-akku.15.6d495fc_repack
# .tar.xz -- rather than a bare /name/ search. An unanchored search matches
# $$name as a substring ANYWHERE in the file, including inside an earlier
# entry's own URL (a future package named, say, "common" would match inside
# "wak-common"'s own line), and would then read that earlier entry's hash
# instead of its own -- silently, since both are valid-looking hex. Every
# entry names its own URL right after its own "(name ...)" line, which is
# what let an earlier, unanchored version of this rule look correct for all
# three packages checked today; that was luck, not the mechanism, and the
# earlier version also relied on `head -1` to stop an "/$$name/,/^$$/" sed
# range that never terminates -- Akku.lock has no blank lines, so that range
# always ran to end of file. Anchoring on the tarball's own name_version
# convention removes both: the pattern can only match the target package's
# own line, so which line comes first no longer matters.
check-pins:
	@fail=0; \
	for pair in "$(SRFI_SRC):chez-srfi" "$(SXMLT_SRC):wak-sxml-tools" "$(COMMON_SRC):wak-common"; do \
	  src=$${pair%%:*}; name=$${pair##*:}; \
	  rec=$$(git ls-files -s $$src | awk '{print $$2}'); \
	  lock=$$(sed -n "s#.*/$${name}_[^\"]*-akku\.[0-9]*\.\([a-f0-9]*\)_repack.*#\1#p" Akku.lock | head -1); \
	  if [ -z "$$rec" ] || [ -z "$$lock" ]; then \
	    echo "check-pins: could not read both pins for $$name (submodule='$$rec' lock='$$lock')" >&2; \
	    fail=1; continue; \
	  fi; \
	  case "$$rec" in \
	    "$$lock"*) echo "pins agree: $$name $$lock" ;; \
	    *) echo "PIN DRIFT: $$name submodule $$rec but Akku.lock names $$lock." >&2; \
	       fail=1 ;; \
	  esac; \
	done; \
	exit $$fail

# options.sls and ast.sls must import no library that loads a shared object,
# directly or transitively (each file's own header comment states this).
# That purity is what makes every assertion in tests/test-options.sps,
# tests/test-ast.sps, and tests/test-sxml.sps unable to pass by accident
# because of native behaviour -- they exercise Scheme values only.
#
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
	for t in tests/test-options.sps tests/test-ast.sps tests/test-sxml.sps; do \
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
#
# cmark-gfm is initialised here too, and it is NOT a Scheme dependency: what
# `deps` needs from it is `test/*.txt`, the 744-example corpus
# tests/test-sxml-differential.sps reads. That suite is the only thing under
# tests/ that reads the vendored WORKING TREE at all -- every other suite
# reaches cmark through $(CMARK_CLI) or the shim, both of which the
# pkg-config path satisfies without any submodule. So under HAVE_PKG=yes
# nothing else initialised it: `$(SHIM): vendor` is guarded out, `vendor`
# never runs, and `make test` on a fresh clone died inside the suite on an
# uncaught &i/o-file-does-not-exist naming open-file-input-port -- pointing
# at the reader, not at the missing checkout.
#
# CHECKOUT ONLY, deliberately: no cmake, no build. Under HAVE_PKG=no the
# `vendor` target builds this same submodule for the shim to link against,
# and building it twice from two targets would be the waste that rule exists
# to avoid. `git submodule update --init` is idempotent and only ever resets
# to the recorded gitlink, so running it from both paths disturbs neither --
# and the corpus has to be at the pinned commit either way, since it is the
# same revision the library links against.
deps:
	git submodule update --init $(VENDOR_DIR)
	git submodule update --init $(SRFI_SRC)
	mkdir -p $(SRFI_LIBS)/srfi
	src=$(abspath $(SRFI_SRC)); dst=$(abspath $(SRFI_LIBS))/srfi; \
	for f in $$src/*; do \
	  b=$$(basename "$$f"); \
	  ln -sfn "$$f" "$$dst/$$b"; \
	  d=$$(printf '%s' "$$b" | sed 's/%3a/:/g'); \
	  [ "$$d" = "$$b" ] || ln -sfn "$$f" "$$dst/$$d"; \
	done
	git submodule update --init $(SXMLT_SRC)
	mkdir -p $(SRFI_LIBS)/wak
	ln -sfn $(abspath $(SXMLT_SRC))/sxml-tools $(abspath $(SRFI_LIBS))/wak/sxml-tools
	git submodule update --init $(COMMON_SRC)
	mkdir -p $(SRFI_LIBS)/wak/private/include
	src=$(abspath $(COMMON_SRC))/private; dst=$(abspath $(SRFI_LIBS))/wak/private; \
	for f in $$src/*.sls; do ln -sfn "$$f" "$$dst/$$(basename "$$f")"; done
	src=$(abspath $(COMMON_SRC))/private/include; dst=$(abspath $(SRFI_LIBS))/wak/private/include; \
	for f in $$src/*; do ln -sfn "$$f" "$$dst/$$(basename "$$f")"; done
	ln -sfn $(abspath $(SRFI_LIBS))/wak/private/include/compat.chezscheme.sls \
	        $(abspath $(SRFI_LIBS))/wak/private/include/compat.sls

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

# Same mechanism for the build flavor: flipping FLAVOR changes this
# prerequisite's identity and forces a relink. Without it, `make prod &&
# make test` would run the dev suite against a counters-free prod shim
# (its counter-movement discriminators would rightly fail), and `make
# build` after `make prod` would hand dev callers a prod shim.
FLAVOR_STAMP := $(BUILD_DIR)/.flavor-$(FLAVOR)

$(FLAVOR_STAMP): | $(LIB_DIR)
	rm -f $(BUILD_DIR)/.flavor-*
	touch $@

$(SHIM): src/cmark-gfm-shim.c src/cmark-gfm-shim.h $(ACQ_STAMP) $(FLAVOR_STAMP) | $(LIB_DIR)
	$(CC) $(CFLAGS_SHIM) $(CMARK_CFLAGS) $(SHLIB_LDFLAGS) \
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

# prod = the same graph as `build`, run at FLAVOR=prod after a clean. Each
# step is an explicit recipe line because the old form -- `prod: clean` plus
# a conditional `prod: vendor` and a trailing `$(MAKE) $(CONFIG_SLS)` -- hid
# two defects behind implicit ordering:
#   - the config sub-make re-entered the $(SHIM) rule, found the acquisition
#     stamp freshly recreated (and, vendored, the phony `vendor` prereq
#     always remade), and RELINKED the just-built -O2 shim with dev flags:
#     `make prod` exited 0 having shipped a debug build;
#   - clean and vendor as sibling prerequisites left their relative order to
#     make's internals -- here both make 3.81 and 4.4.1 ran clean first and
#     merely built vendor twice, but vendor-first turns the link into a
#     library-not-found failure.
# The vendored gate needs no prod-specific rule: $(SHIM) already depends on
# vendor when HAVE_PKG=no, inside the sub-make, after clean has finished.
prod:
	$(MAKE) clean
	$(MAKE) build FLAVOR=prod
	$(MAKE) check-prod

# Proves the artifact that survived to the end of `make prod` is the prod
# one (a check beats a comment): a shim carrying -DCHEZ_CMARK_DEBUG_COUNTERS
# reports moving live-counts while a document is live, a prod shim's stay
# frozen at zero (src/cmark-gfm-shim.c) -- the dev suite's discriminator
# (tests/test-lifecycle.sps "live-counts moves during a scope") pointed the
# other way. Deliberately NOT dependent on `build`: build at the default
# flavor would relink the shim as dev, and the check would then judge the
# artifact it itself just replaced. It probes what the last build left.
# `env -u` so an exported CHEZ_CMARK_GFM_SHIM cannot point the probe away
# from the shim config.sls names.
check-prod: deps
	@test -f $(SHIM) || { echo "check-prod: $(SHIM) is missing; run 'make prod' (or 'make build FLAVOR=prod') first" >&2; exit 1; }
	@test -f $(CONFIG_SLS) || { echo "check-prod: $(CONFIG_SLS) is missing; run 'make prod' first" >&2; exit 1; }
	env -u CHEZ_CMARK_GFM_SHIM CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ) --program tests/check-prod.sps

clean:
	rm -rf $(BUILD_DIR) $(CONFIG_SLS)
