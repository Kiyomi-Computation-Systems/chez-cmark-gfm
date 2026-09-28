# Traps this repo has already hit — full accounts

`AGENTS.md` carries the one-line rule for each trap; this file keeps the
incident behind it. Each of these shipped a passing test or a
working-looking build that was wrong. None is obvious from reading the code.

## Why "prefer a check to a comment"

This is not abstract. The rule about empty tests was already written down
in `AGENTS.md`, and five tests violating it shipped anyway; it only started
holding once it carried an executable standard. A Makefile comment requiring
the `chez-srfi` submodule and `Akku.lock` to name the same commit was
violated *in the same commit that introduced it*, and only became true once
it was `make check-pins`. When a comment is load-bearing, that is the signal
it should not be a comment.

## Traps

* **`0` is truthy in Scheme, and `guard` returns the body's value when nothing
  raises.** So `(test-assert "…" (guard (e ((pred e) #t) (#t #f)) (accessor x)))`
  passes even when `accessor` never raises — freed pointer fields are zeroed, and
  `0` satisfies `test-assert`. Assert on *what was raised*, compared against an
  expected value, with a distinct sentinel for the no-raise case. Three tests
  guarding the liveness mechanism passed against code with that mechanism deleted.
* **Every `tests/test-*.sps` must end with its own `(exit …)`.** SRFI-64 does not set
  a process exit status, so a suite missing that line always reports success and
  `make test` stays green through real failures. Anything appended *after* it is
  dead code — a sabotage test added that way silently never runs.
* **`foreign-procedure` resolves its entry point when the expression is evaluated,
  not when the procedure is first called.** Every binding must be defined after
  `load-shared-object`, which is why the load is written as a definition placed
  ahead of them in `native.sls`. Getting this wrong fails at *import* time, not at
  first use, so the error points nowhere near the mistake.
* **Read cmark's semantics from `vendor/cmark-gfm/`, never from recall.** Ownership,
  NULL-versus-empty returns, and return-value meaning have each contradicted
  reasonable expectations here: see ADR-0005, and
  `cmark_parser_attach_syntax_extension`, which has a single unconditional
  `return 1` and cannot signal failure at all.
* **SRFI-64 turns any exception in a test's *actual* expression into `#f`**
  (`vendor/chez-srfi/%3a64/testing-impl.scm:568-571`: the R6RS
  `%test-evaluate-with-catch` is `(guard (ex (else #F)) …)`). An assertion
  expecting `#f` therefore passes when the code under test raises. Never make
  `#f` the expected value of an assertion that can raise — use a sentinel the
  failure path cannot produce: `'agree (or (compare …) 'agree)`. A whole
  differential leg reported 79/79 green against a `cmark-gfm` that crashed on
  every fixture, because the helper's raise on a non-zero exit was swallowed.
* **Chez evaluates argument expressions right-to-left in compiled library code**,
  left-to-right when interpreted. Never let an assertion's meaning depend on
  which argument runs first: one named "rejected before anything is allocated"
  was in fact satisfied by the *last* argument's accessor raising.
* **A struct tag first named in a prototype's parameter list has prototype scope
  only** (C99 6.2.1p7). Forward-declare it at file scope before the prototype.
  Learned on the C shim release 2.0 deleted, whose own header was included
  before `<cmark-gfm.h>`: `int f(struct cmark_node *n);` without that line
  declares a different type than the `.c` definition sees — conflicting types,
  unrelated to `-Werror`. This project compiles no C at all now (ADR-0015), so
  the lesson has no live site here; it is kept for whoever next reaches for a
  shim, and for reading the history that still contains one.
* **An SXML serializer that does not know your attribute marker will not reject
  the tree — it renders it wrong.** The specification marks an attribute list
  `@`; both serializers reachable on this platform (`wak-sxml-tools`,
  `wak-htmlprag`) mark it `^` and contain no `@` anywhere, so
  `(a (@ (href "/x")) "l")` comes back as `<a><@><href>/x</href></@>l</a>` with
  nothing raised. The first fix was worse than the bug: a test-only rewrite of
  `@` to `^` applied before handing the tree over, which made the conformance
  suite green while saying nothing about the tree the library actually emits —
  one of its four assertions passed unconditionally for as long as that rewrite
  existed. A conformance test that transforms its input tests the
  transformation. See ADR-0013.
* **Apply a mutation where the data flows, not where the name says it flows.** A
  mutation escaping the adapter's `text` case, meant to prove that escaping is
  the serializer's job, produced no failure at all — 4/4, exit 0 — because the
  `<script>` in its fixture reaches the tree as an `html-inline` node through a
  different function, and the three real `text` nodes it did touch held no
  character worth escaping. The assertion had been *named* for the `text` case
  too, so a real regression would have pointed a reader at the wrong function.
  Dump the actual tree before choosing either the mutation site or the name.
* **Deleting a subsystem disarms the checks built around it, and they stay
  green.** Release 2.0 removed the C shim and produced seven of these in one
  branch. `make check-purity` poisoned `CHEZ_CMARK_GFM_SHIM`, which the same
  release had replaced with `CHEZ_CMARK_GFM_LIBS` — nothing read the poison, so
  the gate passed unconditionally, including for regressions it existed to
  catch. A CI step asserted `! -e build/lib`, a path only the deleted shim rules
  ever created. `deps-info` branched on `$(HAVE_PKG)`; with the variable gone
  Make expanded it to empty and it reported "vendored" forever — a dangling Make
  variable is not an error. A CI job named for the vendored build passed while
  Homebrew's copy silently satisfied discovery first: green for the wrong
  reason, which is worse than red. And a `no-library` job greped only for remedy
  text that the preflight's catch-all `else` prints for *any* condition, so it
  could not identify the failure it claimed to test.
  None of these fail, so no gate surfaces them. On any deletion, ask of every
  surviving check "what would make this fail now?" and treat "nothing" as a
  defect — then prove it by breaking the guarded thing and watching it go red.
  A passing CI job is evidence a check *ran*, not that it works.
* **A hand-written oracle that mirrors cmark bakes in one version's behaviour,
  and the supported range spans several.** `tests/test-ast-differential.sps` and
  `tests/test-sxml-differential.sps` reimplement cmark's renderers in Scheme to
  diff against. Three of those reimplementations encoded gfm.13 behaviour as if
  it were constant across the declared `0.29.0.gfm.x` range: the XML indent cap
  (`MAX_INDENT`, upstream `f7e31f8`, gfm.10), nested-`strong` splicing
  (`5c75d23`, gfm.10), and the tasklist `completed` attribute
  (`extensions/tasklist.c`'s `xml_attr`, gfm.1). Two only surfaced when CI first
  ran against Ubuntu's gfm.6; the third had never fired anywhere. When an oracle
  encodes upstream behaviour, check *which versions in the range* have it —
  `git tag --contains` on the vendored submodule answers this in one command —
  and ask the loaded library rather than assuming. `cmark-caps-indent?` in
  `test-ast-differential.sps` is the pattern.
* **The supported range is a symbol constraint that a version check cannot
  express.** Distributions patch entry points independently of the version they
  report: Debian 11's `libcmark-gfm-extensions0.symbols` exports
  `cmark_gfm_extensions_get_tasklist_item_checked@Base 0.29.0.gfm.0`, while
  upstream gfm.0 has no such function. So a gfm.0 floor admits a crashing
  upstream build and a gfm.1 floor rejects a working Debian one — the two are
  indistinguishable by `cmark_version()`. `native.sls` therefore *probes* that
  binding inside a `guard` (a failed `foreign-procedure` resolution is
  catchable) and raises `&cmark-library-unavailable` reason `missing-entry-point`.
  Before widening the range or adding a binding, check the symbol across every
  tag in it, not the version.
* **Chez invokes an imported library's body only when a binding is
  *referenced*.** A probe that merely imports `(cmark gfm)` never forces
  `native.sls`'s body to run, so discovery never happens and
  `CHEZ_CMARK_GFM_LIBS` is never even read. A subprocess test written that way
  printed "unexpectedly imported" and exited 0 against libraries that cannot
  possibly load. Any test asserting something about load-time behaviour must
  *call* into the library — `tests/load-failed-probe.sps` calls
  `markdown->html` for exactly this reason. The same property is what makes
  `make check-purity` meaningful and what limits it.
* **An assertion passes whenever some *other* rule can produce the value it
  expects.** The abstract form of this is already above; here is what it looked
  like four times in one stage, each one green and each one empty. A
  `*COMMENT*`-in-`blockquote` fixture survived narrowing `block-comment-parents`
  to `'(*TOP*)`, because `blockquote` is also in `cr-before-close` and
  contributes the identical newline. An empty-URL assertion could not
  distinguish "empty routes to encoding" from "empty routes to rejection",
  because `percent-encode("")` and the rejection branch both yield `""`. A
  `contains?` probe for `"  indented\n"` still matched after the serializer was
  turned into a pretty-printer, because the injected indent lands immediately in
  front of the content's own two spaces — the substring survived the corruption
  it existed to detect. And a functional-update test cannot tell "carried from
  the argument" from "rebuilt from the default" while its base record holds the
  default for the field the update leaves alone; two of `sxml-options-with`'s
  three fields were unpinned that way. Assert the whole rendering rather than a
  substring, give the fixture a neighbour that cannot produce the same bytes by
  another route, and build the base out of non-default values.
* **An alias for the Chez binary must be neither a symlink nor a wrapper
  script.** A `chez` symlink to Guix's `scheme` aborts with `cannot find
  compatible chez.boot in search path "%x:%x/../lib/csv%v/%m:…"`: Chez
  derives its boot-file name from the invoked name. A wrapper script that
  `exec`s `scheme` fixes that and passes `make test`, but hides Chez from
  Valgrind: Valgrind traces the shell, the shell execs Chez uninstrumented,
  and `make test-memory` reported success over 21 suites without printing a
  single `ERROR SUMMARY`. Point `CHEZ` at the real binary, which is what
  `manifest.scm`'s search path does. `make check-guix` asserts that
  `valgrind $CHEZ` prints an `ERROR SUMMARY`.
* **The macOS memory gate never loaded ASan, and nobody had watched it
  fail.** From its first commit the ASan arm of `make test-memory` set
  `DYLD_INSERT_LIBRARIES` on `sh -c 'for t in …; do chez …; done'`. `/bin/sh`
  is SIP-protected, and macOS purges every `DYLD_*` variable when it launches
  a protected binary, so no suite ever ran under ASan, from v0.1.0 to v2.0.0.
  A planted `memset` overrun exited 0 through the recipe. The spike had
  checked that `chez` was not SIP-restricted and ran it directly, which was
  live; the recipe then put `/bin/sh` in between. Stage 2's Mutation C then
  misread the symptom. A double free crashed `make test-memory` with a bare
  `Trace/BPT trap`, a manual run that launched `chez` directly *and* set
  `MallocNanoZone=0` produced ASan's report, and the report was credited to
  the variable. The trap was the plain allocator, and the variable changed
  nothing. ASan has a second way to lose the preload: its `strip_env`
  default removes it from whatever process it loads into, so under a
  wrapper such as `timeout(1)` it is the wrapper that gets ASan. The same
  trap caught a probe while this was being fixed: a nested `/usr/bin/env`
  is SIP-protected too. Found through the identical defect in chez-libuv.
  `make check-memory-gate` now plants defects and requires the real recipe
  to fail on each, with the tool's own report in the log (ADR-0003's
  2026-09-28 amendment, `.plans/memory-gate-mutation-log.md`). The
  witness for a live ASan run is its `verbosity=1` banner. Speed is no
  witness: a live run takes about as long as `make test`.
* **`guix shell --pure` does not stop a login shell from rebuilding `PATH`.**
  `--pure` clears the environment once, at entry. A later login shell
  (`bash -l`) re-sources `~/.bash_profile` and `~/.profile`. On the maintainer's machine those put
  `~/.guix-home/profile/bin` ahead of the environment, so `scheme` and `git`
  resolved to the host's copies while everything still passed.
  `scripts/guix-env` uses `--container`, whose `HOME` is empty; `make
  check-guix` asserts both that (`isolated-home`) and that a login shell
  runs the pinned binaries, comparing resolved paths. Do not assume you
  know how a tool builds its shell: when Claude Code ran inside the
  container (ADR-0018, since withdrawn), its Bash tool put `/bin:/usr/bin`
  ahead of the profile, which a `bash -l` check never showed. `guix shell
  --check` diagnoses clobbering for a `--pure` shell.
* **Guix creates a container's mount points under the host umask.** `HOME`
  comes out `1777`, and every directory created to hold a shared file comes
  out `0775`: `~/.ssh`, `~/.gnupg`, `/run/user/<uid>/gnupg`. ssh then
  refuses to read anything under them (`bad ownership or modes for
  directory`). gpg quietly rejects the socket directory, falls back to one
  where no agent listens, and lists no secret keys, without an error that
  names the cause. ADR-0018's `scripts/guix-env-init` set them to `0700`;
  ADR-0019 then stopped sharing credentials at all, so the lesson has no
  live site here. It is kept for whoever next shares a socket or key into a
  Guix container.
