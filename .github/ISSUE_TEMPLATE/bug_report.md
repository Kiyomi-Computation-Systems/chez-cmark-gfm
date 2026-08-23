---
name: Bug report
about: Something broke or behaved unexpectedly
labels: bug
---

**Environment**

- OS and architecture (e.g. macOS 15 arm64, Ubuntu 24.04 x86_64):
- Chez Scheme version (`chez --version`, or `chezscheme --version`):
- cmark-gfm: paste the output of `make build` — it names the exact core
  and extensions libraries that would load.
- Installed via: Akku / clone / `make install` / other:

**What happened**

**What you expected**

**Minimal reproduction**

Ideally a small standalone `.sps`, run the same way `(cmark gfm)` already
resolves for you: from a clone,
`CHEZSCHEMELIBDIRS=src chez --program repro.sps` (`chezscheme` on
Debian/Ubuntu); under Akku, `. .akku/bin/activate` first, then
`chez --program repro.sps`; after `make install`, the
`CHEZSCHEMELIBDIRS` export line `make install` printed for you, then
`chez --program repro.sps`. Include the Markdown input if the bug depends
on it.

**Does `make test` pass locally?**
