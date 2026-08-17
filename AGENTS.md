# AGENTS.md

## Project guidelines

* Use the functional core / imperative shell pattern
* Follow the 12 Factor Apps philosophy
* Use TDD / test-driven development
* A test that passes whether the code is right or wrong is worse than no test.
  Every decision in a module gets a mutation that breaks it, and the owning
  specification must notice. Seed an output variable before asserting it is empty.
* Project is specific to Chez Scheme and will be a Chez library.
* Project requires C ffi and handling C libraries *safely*
* Project should be portable across macos (darwin), linux, and windows
* Project should be portable across amd64 and arm64
* Plans live in `/.plans`, decision records in `/.plans/decisions`
* Add entries to `CHANGELOG.md` for each release

## Traps this repo has already hit

Each of these shipped a passing test or a working-looking build that was wrong.
None is obvious from reading the code.

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
