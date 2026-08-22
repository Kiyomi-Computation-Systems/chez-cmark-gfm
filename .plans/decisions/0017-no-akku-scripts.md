# ADR-0017: Ship no Akku `scripts` clause

- **Status:** Accepted
- **Date:** 2026-08-22
- **Scope:** chez-cmark-gfm 2.0
- **Related:** [Shimless FFI design](../2026-08-21-shimless-ffi-design.md) §9, §11.3 ·
  [ADR-0015](0015-bind-libcmark-gfm-directly.md) (why there is nothing to build) ·
  [ADR-0014](0014-fallback-config-shadowing.md) (whose claim about Akku this corrects)

## Context

ADR-0014 stated that Akku "distributes Scheme source and cannot run a C compiler."
**That was wrong**, and the error mattered: it made a build-at-install-time design look
impossible rather than merely unwise, so it was never weighed on its actual merits.

Akku has a `scripts` mechanism. `akku install` runs it twice, once per phase —
`(pre-install)` before the libraries are placed and `(post-install)` after
(`akku.sps:237-241`, akku 1.1.1-beta.0). Each entry is a shell command run through
`/bin/sh -c` with `akku_path_*` variables in the environment
(`lib/scripts.scm:191-218`). A `scripts` clause naming `cmake` or `cc` would run.

This decision therefore has to be made, not assumed.

## Decision

`Akku.manifest` carries no `scripts` clause. Three properties of the mechanism, all
read from akku 1.1.1-beta.0's own source, are why:

- **The approval prompt reaches downstream dependants, not just this project.**
  `run-scripts` collects the scripts of every project in the lockfile *and* the current
  manifest (`lib/scripts.scm:284-285`). A project whose scripts are absent from the
  index, or differ from what the index holds, is classified not-vetted
  (`lib/scripts.scm:229-239`) — with warnings including "There may be a good reason for
  this, but dishonesty may also be involved" — and the user is prompted to approve the
  raw shell command (`lib/scripts.scm:241-263`). Until this package is vetted in the
  Akku index, that prompt fires for anyone who depends on it, in their own
  `akku install`, about a command they did not write.
- **Declining the prompt is not an error.** The prompt defaults to no on an empty line
  or EOF (`lib/scripts.scm:137-147`); declining logs "User said no to running scripts,
  continuing without them" and returns `#f` (`lib/scripts.scm:260-262`), which the
  caller's `when` treats as "nothing to run" (`lib/scripts.scm:296`). The install then
  proceeds and reports success. A package whose build step is its whole reason to have
  scripts installs cleanly and fails at first import.
- **The prompt is skipped entirely in non-interactive installs.** `prompt?` is
  `(not (assq-ref opts 'prompt-yes #f))` (`akku.sps:236`), and
  `((not prompt?) 'user-ok)` (`lib/scripts.scm:259`) runs the commands unasked. So the
  gate is present exactly where it costs the most friction and absent exactly where a
  CI job would hit it.

**A correction to the design spec.** §9 also gave "`run-cmd` ignores exit status, so a
failed build would report success" as a reason. That is false for akku 1.1.1-beta.0:
`run-cmd` reads the wait status and raises on a signal or a non-zero exit
(`lib/scripts.scm:209-216`). The hazard it describes is real — an install that reports
success with no build behind it — but it arrives by the declined-prompt path above,
not by an ignored exit code. Recorded rather than quietly dropped, because the wrong
version of this claim is already in the design spec and would otherwise outlive it.

Two alternatives were rejected:

- **A `scripts` clause that builds the shim.** Even setting the mechanism aside, an
  Akku archive tarball is a repack of the git tree, so `vendor/cmark-gfm` arrives empty
  and the script would have to clone over the network and run a multi-minute CMake
  build during install — inside a mechanism whose output is logged at `debug`
  (`lib/scripts.scm:218`) unless the command fails. A worse failure mode than requiring
  a system package.
- **A `post-install` script that only checks for cmark-gfm and prints advice.** It buys
  a warning at install time and pays the approval prompt above, on every downstream
  dependant, for it. Rejected on that trade — but not for free: see the last
  Consequence.

## Consequences

- `akku install` places this package's `src/cmark/**.sls` under `.akku/lib` and does
  nothing else: no prompt, no `.akku/ffi` artifact, no generated file, no post-install
  step. The `akku-install` CI job installs from the manifest and then calls into
  `(cmark gfm)` with nothing set in the environment
  (`.github/workflows/ci.yml:447-453`), which is release 2.0's exit criterion.
- **This decision only stands because 2.0 needs no build step at all.** It is a
  consequence of ADR-0015, not an independent position on packaging. Anything that
  reintroduces a compile — a Windows shim, a vendored fallback, a generated
  configuration — reopens the whole question, and would have to answer the three
  properties above rather than cite this ADR.
- **Nothing asserts the absence of a `scripts` clause.** `tests/test-manifest-deps.sps`
  checks that `depends` is empty and that `depends/dev` is exactly the known-good set
  (`:118-126`), but it has no assertion about `scripts`, so a clause added later would
  pass the suite. That gap is stated rather than closed: the assertion that test exists
  to make is about dependencies, and a `scripts` clause would be plainly visible in a
  manifest this short.
- The cost of the decision falls on RHEL, Fedora, and Alpine, who have no cmark-gfm
  package and now do a one-time source build by hand (ADR-0015). A `scripts` clause is
  the mechanism that could have hidden that from them, and it is declined knowing so.
- **An Akku user with no cmark-gfm gets a worse first encounter than a clone-and-make
  user, and nothing here fixes it.** They learn at first import, from
  `&cmark-library-unavailable` reason `not-found` — a structured condition, not a
  printed instruction. `make build` prints the install one-liners
  (`tests/preflight.sps:25-31`), but someone who installed through Akku has no checkout
  to run it in. This is the one cost of the decision that is not offset elsewhere, and
  it is what the rejected advice-only script would have bought.
- These findings are pinned to akku 1.1.1-beta.0, the version installed on the
  development machine and the source these line numbers were read from. CI installs the
  1.1.0 release tarball instead (`.github/workflows/ci.yml:429-435`), which was not
  re-checked against them. The mechanism is Akku's, not ours, and it can change; a
  future reader weighing a `scripts` clause should re-read `lib/scripts.scm` rather than
  trust the citations above.

## Successor

Publishing to the Akku archive is deliberately out of scope for 2.0 — it is a
submission process, and it should follow a release that has proven itself. It is also
what would make a `scripts` clause *vetted* and stop the prompt firing for downstream
dependants, so if the archive submission ever happens, the first bullet of this
decision weakens and the other two do not.
