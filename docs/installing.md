# Installing

## Prerequisites

- **Chez Scheme** 9.5.8 or later. The binary is `chez` on macOS and
  `chezscheme` on Debian/Ubuntu.
- **cmark-gfm**, from your system's package manager. One command, no compiler:

  ```sh
  apt install cmark-gfm     # Debian/Ubuntu
  brew install cmark-gfm    # macOS
  ```

  Each pulls the core and extensions shared libraries at matching versions,
  and each also installs the `cmark-gfm` CLI the differential suites use as
  their oracle. [packaging/debian-prereqs.txt](../packaging/debian-prereqs.txt)
  carries the Debian names in two labelled sections — using the library needs
  the first one only; the second is for building the vendored test oracle.
  RHEL, Fedora, and Alpine package no GFM library; see
  [RHEL, Fedora, and Alpine](#rhel-fedora-and-alpine) below.

## Supported versions

Supported versions are `0.29.0.gfm.x` — the constant
`cmark-supported-version-range` in `src/cmark/gfm/private/native.sls`,
`(#x001d0000 . #x001dffff)`, fixing cmark's major and minor at 0.29 and
leaving the patch and gfm-patch numbers free. Nothing is generated and
nothing is compiled: importing `(cmark gfm)` locates a library on this
machine and loads it, and one outside that range is refused with
`&cmark-version-incompatible` rather than used.

The range is not the whole contract, because one entry point this binding
needs — `cmark_gfm_extensions_get_tasklist_item_checked` — arrived in
`0.29.0.gfm.1`, and a version check cannot stand in for it: Debian 11
backports the symbol into its `gfm.0` and still reports `gfm.0`, so a floor
that rejected upstream `gfm.0` would reject Debian's working one too. The
symbol is probed instead. A library that satisfies the range but lacks it
raises `&cmark-library-unavailable` with reason `missing-entry-point`,
naming the extensions library, rather than dying with a raw foreign-procedure
error.

## Supported matrix

2.0 has **one** acquisition path — the system package — so the rows differ in
where cmark-gfm came from, not in how it was built; ADR-0015 amends
ADR-0001's two paths away. **Windows is not supported** (ADR-0004).

| Platform              | Chez   | cmark-gfm from | Memory evidence                                    |
|-----------------------|--------|----------------|----------------------------------------------------|
| macOS/ARM64 (Homebrew)| 10.4.1 | `brew`         | ASan only — **no leak claim**                      |
| Linux/x86-64 (apt)    | 9.5.8  | `apt`          | Valgrind clean, historically — **unverified here** |

Two further CI jobs cover what neither row does: `no-library` installs Chez
and deliberately no cmark-gfm, asserting `make build` fails, reports reason
`not-found`, and names the remedy — the reason symbol is what tells that
failure apart from any other, since the diagnostic's catch-all clause prints
the same remedy for every condition; `akku-install` installs from
`Akku.manifest` and calls into `(cmark gfm)` with nothing set in the
environment.

The floor is **9.5.8**. LeakSanitizer does not exist on macOS/ARM64, so only
the Linux row can support a leak claim (ADR-0003).

A CI step asserts this table against the versions each job actually ran, so
a runner-image bump fails the build until the table is updated rather than
letting the claim go stale.

## With Akku

`Akku.manifest` declares the package's name, version, license, homepage, and
its development-only dependencies; `Akku.lock` is committed. It names no
libraries — Akku infers those from the file tree — and carries no `scripts`
clause, because there is nothing to build (ADR-0017).

```sh
akku install
. .akku/bin/activate
```

puts `src/cmark/**.sls` under `.akku/lib/` and sets `CHEZSCHEMELIBDIRS`;
`(cmark gfm)` then finds the system libcmark-gfm on its own, with nothing
else set and no compiler involved. That is the release's exit criterion,
and CI's `akku-install` job is what proves it.

## From a clone

```sh
git clone <repo> && cd chez-cmark-gfm && make build
```

`--recursive` is needed only to run the test suite: everything under
`vendor/` is a development dependency — the 744-example corpus and the
header `tests/test-option-bits.sps` parses — and `make deps` checks those
out. The differential suites' CLI oracle is `$(CMARK_CLI)`, which defaults
to the `cmark-gfm` on `PATH` that the system package installed.

## Installing system-wide

Chez has no system-wide R6RS library directory. With nothing set,
`(library-directories)` is `(("." . "."))` — the current directory and
nothing else. So installing does not remove the need for
`CHEZSCHEMELIBDIRS`; it gives you one stable location to point it at
instead of a path into a source checkout.

```sh
make install PREFIX=/usr/local      # -> /usr/local/lib/chez-cmark-gfm/cmark/
```

`make install` prints the export line to add to your shell profile:

```sh
export CHEZSCHEMELIBDIRS=/usr/local/lib/chez-cmark-gfm:
```

**This names the parent, not the `cmark/` directory printed above.**
`(cmark gfm)` resolves to `<libdir>/cmark/gfm.sls`, so Chez needs the parent
on its search path; point `CHEZSCHEMELIBDIRS` at the deeper path instead and
the import silently fails to resolve.

**The trailing colon is not a typo.** Assigning `CHEZSCHEMELIBDIRS`
*replaces* Chez's search path rather than extending it, so without the
colon `.` is dropped and relative imports stop resolving:

```
CHEZSCHEMELIBDIRS=/tmp/foo    =>  (("/tmp/foo" . "/tmp/foo"))
CHEZSCHEMELIBDIRS=/tmp/foo:   =>  (("/tmp/foo" . "/tmp/foo") ("." . "."))
```

`PREFIX` names the root, and by default the tree lands in
`<PREFIX>/lib/chez-cmark-gfm`; set `LIBDIR` instead to choose that directory
outright.
`make uninstall PREFIX=/usr/local` removes it. Packagers can set `DESTDIR`.
Nothing is compiled — the install copies `.sls` files and finds
`libcmark-gfm` on the host at import time.

## RHEL, Fedora, and Alpine

Neither Fedora/RHEL (including EPEL) nor Alpine packages the cmark-gfm C
library. Fedora ships only language bindings — `ghc-cmark-gfm` and
`python3-cmarkgfm` — and `cmark-devel` is upstream cmark, not the GFM fork.
Alpine's `cmark` is likewise not the GFM fork.

Build it once from source; the default prefix is on the search path:

```sh
git clone --branch 0.29.0.gfm.13 https://github.com/github/cmark-gfm
cmake -S cmark-gfm -B cmark-gfm/build \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMARK_SHARED=ON -DCMARK_TESTS=OFF
cmake --build cmark-gfm/build --target install   # -> /usr/local/lib
```

`-DCMAKE_POLICY_VERSION_MINIMUM=3.5` is not optional on a current CMake and
is not decoration: 0.29.0.gfm.13 opens with `cmake_minimum_required(VERSION
3.0)`, which CMake 4 refuses outright — *Compatibility with CMake < 3.5 has
been removed from CMake.* — exit 1, before any target is configured. This
project's own `make vendor` passes the same flag for the same reason.

Any `0.29.x.gfm.y` satisfies the supported range. If you install somewhere
other than a searched directory, name both libraries explicitly:

```sh
export CHEZ_CMARK_GFM_LIBS=/opt/cmark/lib/libcmark-gfm.so.0.29.0.gfm.13:/opt/cmark/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13
```

2.0 compiles nothing, which is what makes the Akku install work, and the
cost falls on the platforms with no package.

## What `make build` does

```sh
make build
```

**compiles nothing.** There is no C shim in 2.0 and no generated
`config.sls`; `make build` is a preflight answering the question the
install contract actually raises — is a usable libcmark-gfm present, and
which one would be loaded:

```
cmark-gfm 0.29.0.gfm.13
  core: /opt/homebrew/lib/libcmark-gfm.0.29.0.gfm.13.dylib
  ext:  /opt/homebrew/lib/libcmark-gfm-extensions.0.29.0.gfm.13.dylib
```

With no usable library it exits non-zero and names the remedy instead of
dumping a loader error. Running it is optional — importing `(cmark gfm)`
performs the same discovery either way — but it is the one command that
turns a misconfigured machine into a sentence you can act on.

Discovery scans a fixed list of system directories, in order, for a **core
and extensions pair at the same version in the same directory**:
`/opt/homebrew/lib`, `/usr/local/lib`, `/opt/local/lib` on macOS;
`/usr/local/lib`, `/usr/lib/<triple>`, `/usr/lib`, `/usr/lib64` on Linux.
The first directory holding an in-range pair wins, so a stale
`/usr/local/lib` build shadows a newer packaged one — both are in range, so
both work, and `CHEZ_CMARK_GFM_LIBS` is the escape hatch. See ADR-0016.

## `CHEZ_CMARK_GFM_LIBS`

Environment override naming both shared objects outright, read once at
import time by `resolve-cmark-libraries` in
`src/cmark/gfm/private/native.sls` — config in the environment is
12-factor. It is **validated, never searched**:

- **Unset**: the directory scan above runs.
- **Set**: exactly **two** colon-separated **absolute** paths to **existing
  regular files**, one core and one extensions library; those two are
  loaded verbatim and the scan never runs. Order does not matter — each
  entry is classified by basename, so a swapped value is not a footgun —
  and versioned filenames are not required, so a `-dev` package's
  unversioned symlinks are accepted.
- **Anything else** — one path, three paths, a relative path, a missing
  file, a directory, two libraries of the same kind — raises
  `&cmark-library-unavailable` with reason `invalid-override`. There is no
  PATH search, no falling back to the scan, and the working directory is
  never consulted.

Selection is yours; verification is still ours. Whatever gets loaded, its
`cmark_version()` is checked against the supported range.
