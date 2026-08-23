# chez-cmark-gfm

CHEZ        ?= chez
UNAME_S     := $(shell uname -s)

BUILD_DIR   := build
VENDOR_DIR  := vendor/cmark-gfm
VENDOR_BUILD:= $(BUILD_DIR)/vendor

# The differential suites' oracle (tests/test-differential.sps and friends).
# 2.0 builds no shim and draws no distinction between a pkg-config and a
# vendored acquisition path, so this is just an overridable default naming
# the PATH binary -- point it at another cmark-gfm explicitly if the one on
# PATH is not the one to test against.
CMARK_CLI ?= cmark-gfm

# Install prefix for `make install`. Chez has NO system-wide R6RS library
# directory -- (library-directories) is (("." . ".")) with nothing set --
# so installing here does not make CHEZSCHEMELIBDIRS unnecessary. What it
# buys is one canonical location and one stable variable instead of a path
# into a source checkout.
PREFIX  ?= /usr/local
LIBDIR  ?= $(PREFIX)/lib/chez-cmark-gfm
DESTDIR ?=

SRFI_SRC     := vendor/chez-srfi
SXMLT_SRC    := vendor/wak-sxml-tools
COMMON_SRC   := vendor/wak-common
SRFI_LIBS    := $(BUILD_DIR)/scheme-libs
# "." (repo root), not "site", is what puts (site slug) on the path: Chez
# resolves a library's FULL name as a path under each libdir -- (cmark gfm)
# needs libdir "src" because the file is src/cmark/gfm.sls, i.e. the libdir
# is the PARENT of the first path segment, not that segment itself. So
# (site slug) at site/slug.sls needs the repo root on CHEZ_LIBDIRS, not
# "site" (which would only resolve a bare (slug), or (site slug) nested a
# second time at site/site/slug.sls). Verified empirically: CHEZSCHEMELIBDIRS
# =site alone cannot find (site slug); =. can.
CHEZ_LIBDIRS := src:tests:.:$(SRFI_LIBS)
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

# MUST stay on one physical line. check-help extracts targets with
# `awk '/^\.PHONY:/ ...'`, which matches one physical line and has no
# continuation handling -- a backslash-wrapped .PHONY hides every
# continuation-line target from that check and adds a bogus `\`
# pseudo-target. Found and fixed once already, in commit 3f5552c.
.PHONY: all build deps check-pins check-purity check-help check-install check-site examples site dev help install uninstall test test-memory vendor clean deps-info

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

all: build ## Alias for build

deps-info: ## Report which cmark-gfm CLI the differential suites will use
	@echo "cmark-gfm CLI    : $(CMARK_CLI)"

# There is no compiled artifact in 2.0. `build` answers the question the
# install contract raises instead: is a usable libcmark-gfm present, and which
# one would be loaded? Kept as a canonical target because that question is
# worth one command.
build: ## Verify a usable libcmark-gfm is present and name which one loads
	@CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ) --program tests/preflight.sps

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
check-pins: ## Verify the submodule commits and Akku.lock name the same revisions
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
# Poisoning CHEZ_CMARK_GFM_LIBS with a path that looks absolute but does not
# exist is a probe: if nothing in the suite's import chain ever reaches
# (cmark gfm private native), the variable is never even read and the suite
# passes untouched; if anything does reach it, native.sls's library body
# raises &cmark-library-unavailable at IMPORT time, before a single test runs,
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
check-purity: build deps ## Verify the pure suites import no native code
	@fail=0; \
	for t in tests/test-options.sps tests/test-ast.sps tests/test-sxml.sps tests/test-example-coverage.sps tests/test-manifest-deps.sps tests/test-site.sps; do \
	  echo "=== check-purity: $$t, CHEZ_CMARK_GFM_LIBS poisoned ==="; \
	  if CHEZ_CMARK_GFM_LIBS=/nonexistent CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	      $(CHEZ) --program $$t; then \
	    echo "purity holds: $$t pulled in no native code"; \
	  else \
	    echo "PURITY VIOLATED: $$t failed with CHEZ_CMARK_GFM_LIBS poisoned" >&2; \
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
# reaches cmark through $(CMARK_CLI), a PATH lookup that touches no
# submodule. Nothing else in the graph initialises vendor/cmark-gfm -- there
# is no shim build left to do so as a side effect -- so `deps` has to check
# it out explicitly: without this, `make test` on a fresh clone died inside
# the suite on an uncaught &i/o-file-does-not-exist naming
# open-file-input-port -- pointing at the reader, not at the missing checkout.
#
# CHECKOUT ONLY, deliberately: no cmake, no build. `make vendor` builds this
# same submodule (for a local CLI binary and shared libraries), and building
# it twice from two targets would be the waste that rule exists to avoid.
# `git submodule update --init` is idempotent and only ever resets to the
# recorded gitlink, so running it from both paths disturbs neither -- and the
# corpus has to be at the pinned commit either way, since it is the same
# submodule commit either path resolves to.
deps: ## Vendor chez-srfi and the wak libraries into build/scheme-libs
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

vendor: ## Build the vendored cmark-gfm (dev dependency: corpus, header, CLI oracle)
	git submodule update --init --recursive
	cmake -S $(VENDOR_DIR) -B $(VENDOR_BUILD) \
	  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	  -DCMARK_TESTS=OFF -DCMARK_SHARED=ON -DCMARK_STATIC=OFF
	cmake --build $(VENDOR_BUILD) -j

dev: build deps ## Start a REPL with the library path set
	CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) $(CHEZ)

# Each suite sets its own exit status. Keep going after a failure so one
# broken suite cannot hide the others, then fail the target if any failed.
test: build deps check-pins ## Run every tests/test-*.sps suite
	@fail=0; \
	for t in $(TESTS); do \
	  echo "=== $$t ==="; \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) CMARK_CLI=$(CMARK_CLI) $(CHEZ) --program $$t || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "ALL SUITES PASSED"; \
	else echo "SUITE FAILED"; fi; \
	exit $$fail

test-memory: build deps check-pins ## Run the suites under Valgrind (Linux) or ASan (macOS)
ifeq ($(UNAME_S),Linux)
	@for t in $(MEMORY_TESTS); do \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) CMARK_CLI=$(CMARK_CLI) \
	    CMARK_STRESS_ITERATIONS=2 valgrind --error-exitcode=9 \
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
	asan_lib="$$(command ls $$(dirname $$(xcrun --find clang))/../lib/clang/*/lib/darwin/libclang_rt.asan_osx_dynamic.dylib 2>/dev/null | head -1)"; \
	  if [ -z "$$asan_lib" ]; then \
	    echo "error: no libclang_rt.asan_osx_dynamic.dylib found under $$(dirname $$(xcrun --find clang))/../lib/clang/*/lib/darwin -- refusing to run test-memory uninstrumented" >&2; \
	    exit 1; \
	  fi; \
	  CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) \
	  CMARK_CLI=$(CMARK_CLI) \
	  CMARK_STRESS_ITERATIONS=2 \
	  DYLD_INSERT_LIBRARIES="$$asan_lib" \
	  ASAN_OPTIONS=detect_leaks=0 \
	  MallocNanoZone=0 \
	  sh -c 'for t in $(MEMORY_TESTS); do $(CHEZ) --program $$t || exit 1; done'
endif

clean: ## Remove build/ and tests/tmp
	rm -rf $(BUILD_DIR) tests/tmp

EXAMPLES := $(wildcard examples/*.sps)

# CHEZSCHEMELIBDIRS is src and NOTHING ELSE, deliberately. No
# build/scheme-libs, no chez-srfi, no wak-*. The 0.3.0 CHANGELOG claims a
# consumer of this package acquires no dev dependency; an example that
# reached one would break this target, which is the only way that claim
# stays true rather than merely written down.
#
# Each examples/NN-name.sps pairs with examples/expected/NN.out. Keeps going
# after a failure so one stale example cannot hide the others.
examples: build ## Run every examples/*.sps and diff against examples/expected/
	@mkdir -p tests/tmp; \
	fail=0; \
	for e in $(EXAMPLES); do \
	  base=$$(basename $$e .sps); \
	  exp=examples/expected/$$(echo $$base | cut -d- -f1).out; \
	  echo "=== $$e ==="; \
	  if [ ! -f $$exp ]; then \
	    echo "MISSING expected output: $$exp" >&2; fail=1; continue; \
	  fi; \
	  if CHEZSCHEMELIBDIRS=src $(CHEZ) --program $$e > tests/tmp/$$base.out 2>&1; then \
	    if diff -u $$exp tests/tmp/$$base.out; then \
	      echo "ok"; \
	    else \
	      echo "OUTPUT CHANGED: $$e" >&2; fail=1; \
	    fi; \
	  else \
	    echo "EXAMPLE FAILED TO RUN: $$e" >&2; \
	    cat tests/tmp/$$base.out >&2; fail=1; \
	  fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "ALL EXAMPLES PASSED"; \
	else echo "EXAMPLES FAILED"; fi; \
	exit $$fail

# The tree under build/ (gitignored): reads site/index.md + docs/*.md,
# renders through (site render), writes build/site/*.html plus a copy of
# site/style.css. SITE_REF overrides the git ref used for the ../-escape
# rewrite in generated links; defaults to "main".
site: build ## Generate the static docs site into build/site/
	@mkdir -p build/site
	@CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) SITE_REF="$${SITE_REF:-main}" \
	  $(CHEZ) --program build-site.sps
	@cp site/style.css build/site/style.css
	@echo "site: build/site ready (open build/site/index.html)"

# Asserts on render-site's return value in memory -- no build/site/ write,
# no dependency on `site` itself. tests/site-check.sps is a plain program,
# not a tests/test-*.sps suite, precisely so it stays off `make test`'s
# glob and lives on this target instead (see its own header comment).
check-site: build ## Build the site in memory and assert links, anchors, nav, and no <pre> reflow
	@CHEZSCHEMELIBDIRS=$(CHEZ_LIBDIRS) SITE_REF="$${SITE_REF:-main}" \
	  $(CHEZ) --program tests/site-check.sps

# CHEZ_CMARK_GFM_LIBS is UNSET here, not set empty. `(getenv "X")` returns
# "" for an empty-but-set variable, and "" is truthy in Scheme, so
# resolve-cmark-libraries would take the override branch and raise
# &cmark-library-unavailable reason invalid-override -- a failure that
# looks like a broken install but is really a broken check.
#
# The probe runs with the export line `install` actually PRINTS, parsed out
# of its real output -- not with a path this recipe spells out for itself.
# A path hardcoded here guards nothing: that printed line is the most-copied
# thing this project emits, and while this check named its own path, the
# printed one could be changed to the deeper cmark/ subdirectory -- the exact
# mistake docs/installing.md warns readers about -- and still pass green.
# AGENTS.md, first rule: a check that cannot fail is worse than no check.
#
# The probe runs from an empty scratch directory rather than the repo root,
# so the "." that the trailing colon keeps on the search path is genuinely
# empty. Only the extracted directory can resolve (cmark gfm), which is the
# property under test; from the repo root a stray ./cmark would satisfy the
# import and hide a wrong printed path.
#
# uninstall is exercised here too, against the same temp prefix -- it is
# install's twin, is documented in README.org and docs/installing.md, and
# until now was run by no target and no CI job. The keep-me marker is not
# decoration: an rm -rf one level too high would take the whole prefix with
# it, and "the tree is gone" alone cannot tell that apart from success.
check-install: ## Install to a temp prefix, prove install's own printed export line works, then uninstall
	@set -eu; \
	tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT INT TERM; \
	prefix="$$tmp/prefix"; \
	out="$$tmp/install.out"; \
	probecwd="$$tmp/empty"; \
	mkdir -p "$$probecwd"; \
	$(MAKE) --no-print-directory install PREFIX="$$prefix" >"$$out"; \
	libdirs="$$(sed -n 's/^[[:space:]]*export CHEZSCHEMELIBDIRS=//p' "$$out")"; \
	if [ -z "$$libdirs" ]; then \
	  echo "check-install: FAILED -- make install printed no" >&2; \
	  echo "'export CHEZSCHEMELIBDIRS=...' line for this check to test. That" >&2; \
	  echo "line is the install target's entire user-facing output." >&2; \
	  exit 1; \
	fi; \
	case "$$libdirs" in \
	  *:) ;; \
	  *) echo "check-install: FAILED -- make install printed" >&2; \
	     echo "    export CHEZSCHEMELIBDIRS=$$libdirs" >&2; \
	     echo "with no TRAILING COLON. Assigning that variable REPLACES Chez's" >&2; \
	     echo "search path instead of extending it, so without the colon '.' is" >&2; \
	     echo "dropped and relative imports stop resolving." >&2; \
	     exit 1;; \
	esac; \
	echo "=== check-install: importing with the line install printed: $$libdirs ==="; \
	if ( cd "$$probecwd" && env -u CHEZ_CMARK_GFM_LIBS \
	       CHEZSCHEMELIBDIRS="$$libdirs" \
	       $(CHEZ) --program "$(CURDIR)/tests/install-probe.sps" ); then \
	  echo "check-install: an installed tree imports and renders"; \
	else \
	  echo "check-install: FAILED -- the export line make install printed," >&2; \
	  echo "    export CHEZSCHEMELIBDIRS=$$libdirs" >&2; \
	  echo "does not render a document against the tree it just installed under" >&2; \
	  echo "$$prefix. Either the copy step or that printed line is wrong -- note" >&2; \
	  echo "that (cmark gfm) resolves to <libdir>/cmark/gfm.sls, so the line must" >&2; \
	  echo "name the PARENT of cmark/, not cmark/ itself." >&2; \
	  exit 1; \
	fi; \
	mkdir -p "$$prefix/lib/keep-me"; \
	touch "$$prefix/lib/keep-me/marker"; \
	echo "=== check-install: uninstalling from $$prefix ==="; \
	$(MAKE) --no-print-directory uninstall PREFIX="$$prefix" >/dev/null; \
	if [ -e "$$prefix/lib/chez-cmark-gfm" ]; then \
	  echo "check-install: FAILED -- make uninstall left" >&2; \
	  echo "$$prefix/lib/chez-cmark-gfm behind. It must remove the tree that" >&2; \
	  echo "make install created." >&2; \
	  exit 1; \
	fi; \
	if [ ! -e "$$prefix/lib/keep-me/marker" ]; then \
	  echo "check-install: FAILED -- make uninstall removed" >&2; \
	  echo "$$prefix/lib/keep-me/marker, which make install never created." >&2; \
	  echo "uninstall must remove its own tree and nothing else." >&2; \
	  exit 1; \
	fi; \
	echo "check-install: uninstall removed its own tree and left the prefix intact"

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
