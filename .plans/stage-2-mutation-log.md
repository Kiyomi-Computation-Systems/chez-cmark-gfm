# Stage 2 Mutation Log

Task 10 proves each renderer/options decision in [design spec
§8.3](2026-08-16-stage-2-renderers-design.md) has a test that fails when the decision
is broken. Method, applied identically to every mutation below: back up the target
file (to the session scratchpad, not `/tmp`), apply the mutation, run `make test`
(and, for mutation C, `make test-memory`), record the exact result, restore the file
from the backup, `diff` the restore against the backup to confirm byte-identical, and
confirm `git status --short` is clean before moving to the next mutation. No mutation
was left in the tree while another was applied.

Mutations A, B, D, E, and H were run during Tasks 8, 6, 5, 3, and 7 respectively, as
part of each task's own required TDD mutation step. Their evidence is transcribed
below from those tasks' reports (`task-8-report.md`, `task-6-report.md`,
`task-5-report.md`, `task-3-report.md`, `task-7-report.md`), not re-run — re-running
a passing implementation against an old mutation would add nothing the original,
contemporaneous run didn't already show. Mutations C, F, and G were run fresh for
this task, against the current tree (commit history through `7986236`, branch
`feat/stage-2-renderers`).

**Baseline** (before any mutation, and reconfirmed clean after all of them): 7
suites, 178 assertions, `make test` prints `ALL SUITES PASSED`, `exit=0`.

```
=== tests/test-conditions.sps ===
%%%% Starting test conditions
# of expected passes      18
=== tests/test-differential.sps ===
%%%% Starting test differential
# of expected passes      28
=== tests/test-lifecycle.sps ===
%%%% Starting test lifecycle
# of expected passes      22
=== tests/test-native.sps ===
%%%% Starting test native
# of expected passes      29
=== tests/test-options.sps ===
%%%% Starting test options
# of expected passes      36
=== tests/test-render.sps ===
%%%% Starting test render
# of expected passes      35
=== tests/test-shim-loading.sps ===
%%%% Starting test shim-loading
# of expected passes      10
ALL SUITES PASSED
```

A note on exit codes below: GNU Make reports the *make* process's exit code as `2`
for a failed recipe even though the recipe's own `exit $$fail` computes `1` — this
was established in the Stage 1 mutation log and is reconfirmed here independently:
every one of today's three fresh mutation runs (C, F, G) exited `2`, not a new
finding.

## Summary

Per-suite fractions below (e.g. "render 6/9" vs. "render 30/35") are **not**
directly comparable across rows: A, B, D, E, and H are transcribed at the suite
size that existed when each was originally run (the suite has grown since, as
later tasks added assertions), while C, F, and G were run today against the
current 178-assertion tree. Each row's own fraction is internally consistent;
none of them are being compared against each other.

| # | Mutation | Change | `make test` result | Named test(s) that failed | Covered? |
|---|---|---|---|---|---|
| A | Transpose two `chez_cmark_option_bits` arguments | In the C shim, `nobreaks` was made to set `CMARK_OPT_SMART` and `smart` to set `CMARK_OPT_NOBREAKS` | FAIL, differential 23/25, exit=2 | "nobreaks -- our output matches the CLI"; "smart -- our output matches the CLI" | **Yes** |
| B | Drop the extension list from the `cmark_render_html` call | `markdown->html`'s `(doc-extensions h)` argument replaced with `0` | First attempt: **PASS**, `ALL SUITES PASSED`, exit=0. After the fix wave: FAIL, render 28/29, exit=2 | First attempt: none. After the fix wave: "tagfilter's \<script\> defanging under unsafe-html? requires the extension list reaching render-html" | **Yes** — only after a wrong prediction was diagnosed and a new assertion written; see below |
| C | Free the buffer before copying it | `call-with-render-buffer`'s copy-thunk now frees `buf` and decrements the counter *before* reading it; the unchanged after-thunk frees it again | CRASH (`Trace/BPT trap: 5`) in `test-differential.sps` and `test-render.sps`, no per-suite pass/fail line for either, exit=2. `make test-memory`: identical crash signature in `test-render.sps`, exit=2 | None by name — the process aborts before any SRFI-64 assertion in either file can complete | **No — crashes, but not caught by name; see below** |
| D | Delete `count-buffer-free!` (and, separately, `count-buffer-new!`) | One counter call removed from `call-with-render-buffer`'s after-thunk (two variants, run separately, each reverted before the next) | FAIL both times, render 6/9, exit=2 | "counters balance after a successful render"; "counters balance after the render scope's body raises"; "200 renders leave the counters balanced" | **Yes** |
| E | Remove the `hardbreaks?`/`nobreaks?` rejection | Deleted the contradictory-pair `when` block from `validate` | FAIL, options 34/36, exit=2 | "hardbreaks? and nobreaks? together are rejected"; "cmark-options-with cannot reach the contradictory pair either" | **Yes** |
| F | `cmark-options-with` skips validation | `cmark-options-with`'s `build` call replaced with a direct `%make-cmark-options` call using `o`'s own 8 field values — the plist argument and `validate` are both dropped | FAIL, options 33/36, exit=2 | "cmark-options-with overrides the named field"; "cmark-options-with rejects an unknown key"; "cmark-options-with cannot reach the contradictory pair either" | **Yes** — one more name than predicted; see below |
| G | Flip the `source-positions?` default to `#t` | `make-cmark-options`'s 3rd positional default (`source-positions?`) changed from `#f` to `#t` | FAIL, differential 27/28, options 35/36, render 30/35, exit=2 | 7 names, across 3 suites — see below | **Yes** — 7 names, only 1 of the brief's 5 predicted names among them; see below |
| H | Change one extension's mapped string | `(tagfilter . "tagfilter")` → `(tagfilter . "tagfiltr")` in `options.sls`'s native-name alist | FAIL, render 27/35, exit=2 | 8 names, all in `test-render.sps` — see below | **Yes** — 8 names, not the predicted 2; see below |

## Notes on each mutation

### Mutation A — transposed option bits (covered)

Source: `task-8-report.md`, Step 6. In `chez_cmark_option_bits`, `nobreaks` and
`smart` were swapped so each set the other's bit. `make test`:

```
%%%% Starting test differential
FAIL nobreaks -- our output matches the CLI
FAIL smart -- our output matches the CLI
# of expected passes      23
# of unexpected failures  2
```

Exactly these two, nothing else. In the **same run**, `tests/test-native.sps`
reported `# of expected passes      29` with zero `FAIL` lines — every bit-distinctness
assertion (including "each of the six option flags sets a distinct, non-zero bit")
still passed. This is the contrast the harness is built around: swapping which
parameter sets which bit is a *relabeling*, not a *collision* — the two bits are
still pairwise distinct after the swap, which is all a structural distinctness check
can see. Only a semantic, CLI-compared assertion can see that the labels themselves
got attached to the wrong boolean, which is why the differential layer exists
alongside the native bit-level layer rather than replacing it. Restored and
reconfirmed: `ALL SUITES PASSED`.

### Mutation B — dropped extension list (covered only after a wrong prediction was corrected)

Source: `task-6-report.md`, Step 6 and the later "Fix wave (review finding)" section
(commits `3ea44ef`, then `6700ffb` after design-spec correction `7d2a80b`). Recording
the whole arc, not just the end state, because the first attempt is itself the
finding.

**First attempt.** In `markdown->html`, `(doc-extensions h)` replaced with the
literal `0`. The brief in force at the time predicted this would break "tables
render through markdown->html, which requires the extension list." Observed:

```
=== tests/test-render.sps ===
%%%% Starting test render
# of expected passes      28
=== tests/test-shim-loading.sps ===
%%%% Starting test shim-loading
# of expected passes      10
ALL SUITES PASSED
```

Nothing failed. The prediction was wrong, and — per the task's own instruction to
investigate rather than accept a silent pass at face value — it was root-caused
against the vendored source rather than shrugged off:
`vendor/cmark-gfm/src/html.c:142-144` dispatches extension-node HTML rendering
(tables, strikethrough, tasklists) through each node's own `->extension` pointer,
set at **parse** time when the extensions are attached to the parser — never through
the `extensions` argument `cmark_render_html` receives. That argument is filtered
(`html.c:480-485`) down to only extensions with an `html_filter_func`; `tagfilter`
(`extensions/tagfilter.c`) is the only core extension that sets one, and the
filtered list (`renderer.filter_extensions`) is consulted only when
`CMARK_OPT_UNSAFE` is set. So dropping the argument cannot touch table or
strikethrough rendering at all — it can only touch tagfilter's `<script>`-defanging,
and only under `unsafe-html?`. This correction is recorded permanently in [design
spec §13](2026-08-16-stage-2-renderers-design.md).

**Fix wave.** The false claim in the table test's name/comment was corrected, and a
new assertion was added that isolates the property the argument actually controls:

```scheme
(test-assert "tagfilter's <script> defanging under unsafe-html? requires the extension list reaching render-html"
  (string-contains? (markdown->html "<script>alert(1)</script>\n"
                                    (make-cmark-options 'unsafe-html? #t))
                    "&lt;script>"))
```

Re-running the **same** mutation (`(doc-extensions h)` → `0`) against this corrected
suite:

```
=== tests/test-render.sps ===
%%%% Starting test render
FAIL tagfilter's <script> defanging under unsafe-html? requires the extension list reaching render-html
# of expected passes      28
# of unexpected failures  1
```

Exactly the new assertion, nothing else — table and strikethrough output are
byte-identical to the unmutated binding (confirmed directly against the mutated
build: `<table>`, `<td>1</td>`, and `<del>gone</del>` all render exactly as before).
Restored both times; `diff` against each backup showed no differences; final
`make test`: `ALL SUITES PASSED`.

**The finding, stated plainly:** a mutation that passes clean on the first try is
not evidence of coverage — it can equally be evidence that the *predicted*
discriminator was never the real one. The fix here was to re-derive the prediction
from the vendored C source rather than from the plan's prose, then write the
assertion the corrected prediction actually implies.

### Mutation C — free the buffer before copying (NOT covered by a named test)

Run fresh today. Backed up `src/cmark/gfm/private/scope.sls`. In
`call-with-render-buffer`, the copy-thunk changed from:

```scheme
        (lambda () (c-string->string buf))
```

to:

```scheme
        (lambda () (free-buffer buf) (count-buffer-free!) (c-string->string buf))
```

The after-thunk was left untouched — it still runs
`(unless (zero? buf) (free-buffer buf) (count-buffer-free!) (set! buf 0))`. Since
the body never zeroes `buf`, this is a genuine double-free: `buf` is freed once in
the body (immediately followed by a read through the now-dangling pointer to build
the Scheme string), then freed a second time in the after-thunk.

**`make test`** — verbatim:

```
=== tests/test-conditions.sps ===
%%%% Starting test conditions
# of expected passes      18
=== tests/test-differential.sps ===
%%%% Starting test differential
/bin/sh: line 1: 95242 Trace/BPT trap: 5       CHEZSCHEMELIBDIRS=src:build/scheme-libs CMARK_CLI=cmark-gfm chez --program $t
=== tests/test-lifecycle.sps ===
%%%% Starting test lifecycle
# of expected passes      22
=== tests/test-native.sps ===
%%%% Starting test native
# of expected passes      29
=== tests/test-options.sps ===
%%%% Starting test options
# of expected passes      36
=== tests/test-render.sps ===
%%%% Starting test render
/bin/sh: line 1: 95254 Trace/BPT trap: 5       CHEZSCHEMELIBDIRS=src:build/scheme-libs CMARK_CLI=cmark-gfm chez --program $t
=== tests/test-shim-loading.sps ===
%%%% Starting test shim-loading
# of expected passes      10
SUITE FAILED
make: *** [test] Error 1
```

`MAKE_EXIT=2`. This is **not** the brief's anticipated "green `make test`" outcome —
it is a hard process abort (`SIGTRAP`) in both `test-differential.sps` and
`test-render.sps` (each exercises `call-with-render-buffer` via `markdown->*`, so
both hit the double-free on their first render). Note the Makefile's `test:` recipe
uses `|| fail=1` per file with no early exit, so the other five suites still ran to
completion and reported their normal counts — only the two files that actually
call a renderer crashed.

**`make test-memory`** — verbatim (the exact invocation `make test-memory` runs, no
extra flags):

```
%%%% Starting test conditions
# of expected passes      18
%%%% Starting test lifecycle
# of expected passes      22
%%%% Starting test native
# of expected passes      29
%%%% Starting test options
# of expected passes      36
%%%% Starting test render
sh: line 1: 98949 Trace/BPT trap: 5       chez --program $t
make: *** [test-memory] Error 1
```

`MAKE_EXIT=2`. `test-differential.sps` is excluded from `MEMORY_TESTS` by the
Makefile's own design (§8.1 of the design spec), so it never runs here.
`test-memory`'s `sh -c '... || exit 1'` stops at the first failure, so
`test-shim-loading.sps` never runs either. **No ASan diagnostic banner appears
anywhere in this output** — this is the same bare `Trace/BPT trap: 5` as plain
`make test`, not the "heap-use-after-free" report the brief anticipated.

**Additional diagnostic** (not part of the required steps; run to explain why ASan
produced no banner, since that gap seemed worth understanding rather than leaving
as a loose end). Re-ran `tests/test-render.sps` directly under the same ASan
preload, but with `MallocNanoZone=0` added and `ASAN_OPTIONS` made more verbose:

```
$ CHEZSCHEMELIBDIRS=src:build/scheme-libs \
    DYLD_INSERT_LIBRARIES="$ASAN_LIB" \
    ASAN_OPTIONS="detect_leaks=0:abort_on_error=0:symbolize=1:print_stacktrace=1" \
    MallocNanoZone=0 \
    chez --program tests/test-render.sps
```

```
%%%% Starting test render
=================================================================
==11573==ERROR: AddressSanitizer: attempting double-free on 0x6020000004f0 in thread T0:
    #0 0x0001017e5258 in free+0x7c (libclang_rt.asan_osx_dynamic.dylib:arm64e+0x41258)
    #1 0x0001032ec644 in chez_cmark_free_buffer cmark-gfm-shim.c:32
    #2 0x00010a4fb51c  (<unknown module>)
    ...
freed by thread T0 here:
    #0 ... in free+0x7c ...
    #1 ... in chez_cmark_free_buffer cmark-gfm-shim.c:32
    ...
previously allocated by thread T0 here:
    #0 ... in realloc+0x80 ...
    #1 ... in xrealloc+0x8 (libcmark-gfm.0.29.0.gfm.13.dylib...)
    #2 ... in cmark_strbuf_grow+0x54 ...
    #3 ... in cmark_strbuf_put+0x2c ...
    #4 ... in cmark_render_html_with_mem+0xa28 ...
    ...
SUMMARY: AddressSanitizer: double-free cmark-gfm-shim.c:32 in chez_cmark_free_buffer
==11573==ABORTING
```

Exit 1. With the platform's Nano allocator disabled, ASan cleanly attributes the
defect to the exact line (`cmark-gfm-shim.c:32`, inside `chez_cmark_free_buffer`),
naming it precisely: **a double-free, not a use-after-free.** This is a real
correction to the brief's prediction, and it explains the bare `Trace/BPT trap`
mechanistically: `c-string->string` (`native.sls:220-232`) reads the freed buffer
via Chez's own `foreign-ref` primitive, a raw pointer dereference in Chez's runtime
that this preload-only ASan configuration never instruments (only `malloc`/`free`
are interposed; neither Chez nor the shim is compiled with `-fsanitize=address`) —
so the *read* was never going to be caught by ASan here, predicted outcome or not.
What ASan *can* see is the second `free()` call, and normally would report cleanly
— but on this machine, macOS's own Nano-zone allocator validates a freed block's
metadata and traps (`SIGTRAP`) on the second `free()` before ASan's interposed
`free()` gets a chance to run its own check and print a report. The Makefile's
`test-memory` recipe (lines 213-216) does not set `MallocNanoZone=0`, so on this
platform it inherits this race and produces an unattributed crash for exactly this
class of bug (a double-free of a small allocation) instead of the diagnostic it
exists to provide.

Restored (twice — once after the required run, once after the diagnostic run);
`diff` against the backup showed no differences both times; `make test` after each
restore: `ALL SUITES PASSED`.

**Covered? No — not by name.** `make test` and `make test-memory`, run exactly as
the Makefile defines them, both fail loudly (`SUITE FAILED` / `Error 1`, exit 2),
so a CI pipeline gating on exit status is protected. But neither run produces a
SRFI-64 `FAIL <name>` line or an attributed diagnostic — nothing in the captured
output says *what* broke. Per this task's own opening rule ("every mutation must
break its named test through the asserted property... if no mutation can break an
assertion, write down that the property is uncovered and why"), an unattributed
process abort does not meet that bar, even though it is a stronger signal than the
brief's anticipated silent pass. This is listed again under "Deliberate coverage
gaps" below. The one path that *does* attribute it precisely — a manual ASan
invocation with `MallocNanoZone=0` — is not the command `make test-memory` runs, so
it does not count as suite coverage as it stands today.

### Mutation D — buffer counter deleted, both halves (covered)

Source: `task-5-report.md`, Step 6. Backed up `scope.sls`.

**Half 1**: `(count-buffer-free!)` deleted from the after-thunk.

```
=== tests/test-render.sps ===
%%%% Starting test render
FAIL counters balance after a successful render
FAIL counters balance after the render scope's body raises
FAIL 200 renders leave the counters balanced
# of expected passes      6
# of unexpected failures  3
```

Mechanism: without the decrement, `live-buffers` ends one higher than before after
every successful render.

**Half 2** (decrement restored, `(count-buffer-new!)` deleted instead):

```
=== tests/test-render.sps ===
%%%% Starting test render
FAIL counters balance after a successful render
FAIL counters balance after the render scope's body raises
FAIL 200 renders leave the counters balanced
# of expected passes      6
# of unexpected failures  3
```

Identical three names, identical counts — but a different underlying defect:
without the increment, the still-present decrement drives `live-buffers`
*negative* relative to `before`, rather than climbing. Two distinct bugs producing
the same outward failure signature is exactly why the brief requires both halves
recorded, not just one. "the buffer counter actually moves" does not fail under
either half by design — it drives the counter primitives directly rather than
through `call-with-render-buffer`. Both halves restored in turn (byte-identical
`diff` each time); final `make test`: render back to 9/9, `ALL SUITES PASSED`.

### Mutation E — hardbreaks?/nobreaks? rejection removed (covered)

Source: `task-3-report.md`, Step 6. The seven-line `when` block (leading comment
through the `raise`) removed from `validate` in `options.sls`.

```
=== tests/test-options.sps ===
%%%% Starting test options
FAIL hardbreaks? and nobreaks? together are rejected
FAIL cmark-options-with cannot reach the contradictory pair either
# of expected passes      34
# of unexpected failures  2
```
```
SUITE FAILED
make: *** [test] Error 1
```

Both required names present. (`grep -c 'contradictory'` over this output returns
`1`, not `2` — that is a property of the two test names, only one of which contains
the literal word "contradictory"; it is not a partial-failure signal, and the report
recorded the full `FAIL` lines precisely so that count could not be misread as one.)
Restored; `diff` against the backup: no differences; `make test`: options back to
36/36, `ALL SUITES PASSED`.

### Mutation F — `cmark-options-with` skips validation (covered, one more name than predicted)

Run fresh today. Backed up `src/cmark/gfm/options.sls`. In `cmark-options-with`,
replaced:

```scheme
    (build (plist->alist plist)
           (cmark-options-extensions o)
           ...)
```

with:

```scheme
    (%make-cmark-options
           (cmark-options-extensions o)
           ...)
```

i.e. the same eight field-value expressions, called directly against
`%make-cmark-options` instead of through `build`. This drops two things at once:
`build`'s call to `validate` (the brief's stated target), *and* — because the
`(plist->alist plist)` argument is no longer passed anywhere — the plist overrides
themselves. `cmark-options-with` under this mutation ignores its own `plist`
argument entirely and returns an unchecked clone of `o`.

`make test` — verbatim:

```
=== tests/test-options.sps ===
%%%% Starting test options
FAIL cmark-options-with overrides the named field
FAIL cmark-options-with rejects an unknown key
FAIL cmark-options-with cannot reach the contradictory pair either
# of expected passes      33
# of unexpected failures  3
```

`MAKE_EXIT=2`. Two of the three are the brief's prediction
("...contradictory pair either" and "...rejects an unknown key"). The third —
"cmark-options-with overrides the named field" — is not in the brief's prediction,
and follows mechanically from the same root cause: once `build`'s alist lookups are
bypassed entirely rather than just its `validate` call, the override the caller
asked for (`'smart? #t` in that test) is never applied either.
"cmark-options-with preserves a non-default field it did not touch" and "...does
not mutate its argument" still pass — both happen to hold vacuously once
`cmark-options-with` becomes a pure clone of `o`, since neither test checks that an
override actually took effect on a *different* field. Restored; `diff` against the
backup: no differences; `make test`: options back to 36/36, `ALL SUITES PASSED`.

**Finding:** the brief's phrasing ("replace the `build` call... bypassing
`validate`") under-described its own mutation's effect — the literal, and only,
way to satisfy both of the brief's named predictions turns out to also disable the
plist entirely, not just the validation step. A smaller mutation that inlined the
`lookup` calls and skipped only `validate` (preserving the plist mechanism) would
have caught the contradictory-pair test but *not* "rejects an unknown key" (that
check lives in `plist->alist`, upstream of `build`, and would still have run) — so
it would not have matched the brief's own prediction. This was checked by
construction (reasoning through both readings) before applying either, then
confirmed against the actual run.

### Mutation G — `source-positions?` default flipped (covered, but not as predicted)

Run fresh today. Backed up `src/cmark/gfm/options.sls`. The brief says "in both
`default-cmark-options` and `make-cmark-options`, change the third default" — in
the current tree there is only **one** occurrence to change: Task 3's DRY refactor
made `default-cmark-options` delegate to `(make-cmark-options)` with no arguments,
so it carries no positional-default tuple of its own any more (`options.sls:146-147`).
This is a stale detail in the brief's phrasing, not a deviation in the mutation
itself. Changed `make-cmark-options`'s `build` call:

```scheme
    (build (plist->alist plist)
           default-extensions #t #f #f #f #f #f default-max-input-bytes))
```

3rd default (`source-positions?`) `#f` → `#t`:

```scheme
    (build (plist->alist plist)
           default-extensions #t #t #f #f #f #f default-max-input-bytes))
```

`make test` — verbatim:

```
=== tests/test-differential.sps ===
%%%% Starting test differential
FAIL sourcepos -- the CLI's own output changes
# of expected passes      27
# of unexpected failures  1
=== tests/test-options.sps ===
%%%% Starting test options
FAIL source-positions? defaults to #f
# of expected passes      35
# of unexpected failures  1
=== tests/test-render.sps ===
%%%% Starting test render
FAIL markdown->html renders a heading
FAIL markdown->xml emits a CommonMark XML document
FAIL tables render through markdown->html, given the default extension set
FAIL the default options do NOT emit data-sourcepos (ADR-0008)
FAIL the façade exposes the renderers
# of expected passes      30
# of unexpected failures  5
=== tests/test-shim-loading.sps ===
%%%% Starting test shim-loading
# of expected passes      10
SUITE FAILED
make: *** [test] Error 1
```

`MAKE_EXIT=2`. Total: 7 named failures (1 + 1 + 5), against a prediction of 5
names ("source-positions? defaults to #f", "the default options do NOT emit
data-sourcepos (ADR-0008)", and the four "default options agree with the CLI in
..." cells). Only **one** of the five predicted names actually failed. The other
four predicted names — all differential parity cells — did **not** fail, and a
**different** differential test failed instead, together with three
`test-render.sps` names the brief never mentioned.

**Why the four predicted "agree with the CLI" cells did not fail.** Confirmed
directly (probe run while the mutation was still applied):
`(cmark-options-source-positions? (make-cmark-options 'validate-utf8? #f 'extensions '()))`
→ `#t` under the mutation. `test-differential.sps`'s `DEFAULTS = '()`, and each
"agree with the CLI" cell calls `(mismatch fixture format DEFAULTS DEFAULTS)`.
`config->flags` — which builds the CLI's own command-line flags for the comparison
— reads `cmark-options-source-positions?` off `(config->options cli-cfg)`, i.e. off
**our own (mutated) `make-cmark-options`**, not off an independent, hand-written
baseline. Both sides of the comparison therefore inherit the same mutated default
and stay in agreement (both add `--sourcepos` / `CMARK_OPT_SOURCEPOS`) regardless
of what the default actually is. This parity design is deliberate —
`test-differential.sps:71-72`'s own comment on `config->flags` states the intent
directly: "Our options record drives the CLI flags too, so the two sides cannot
describe different configurations by accident" — but that same deliberate coupling
is structurally blind to a pure default-value mutation: it can only ever catch a
*mismatch* between our bit-wiring and the CLI's own flag generation, not a change
to the shared default itself.

**Why "sourcepos -- the CLI's own output changes" failed instead.** This is a
layer-1 *discrimination guard*, not a parity cell:
`(cli-differs? "tests/fixtures/core.md" 'html BASE (cfg '() 'source-positions? #t))`.
`BASE = (cfg '())` = `(list 'validate-utf8? #f 'extensions '())` — it does not
explicitly pin `source-positions?`, so under the mutation `BASE` silently absorbs
the new default (`#t`), becoming identical to the explicitly-flipped comparison
config. The CLI's own two outputs are therefore now byte-identical, and the guard
correctly reports that they are — not because our library disagrees with the CLI,
but because the two configurations being compared are no longer actually
different once the mutation lands. This is the discrimination guard doing exactly
its documented job (§7.3: "a differential assertion only discriminates if the flag
actually changes output... Expect this to force at least one baseline adjustment"),
just against a mutation nobody anticipated it would be the one to catch.

**Why the `test-render.sps` failures.** Verified with a direct probe (mutation
still applied):

```
(markdown->html "# hi\n" (make-cmark-options 'extensions '()))
=> "<h1 data-sourcepos=\"1:1-1:4\">hi</h1>\n"

(markdown->html "| a |\n|---|\n| 1 |\n" (default-cmark-options))
=> "<table data-sourcepos=\"1:1-3:5\">\n...<td data-sourcepos=\"3:2-3:4\">1</td>...\n"

(markdown->html "~~gone~~\n" (default-cmark-options))
=> "<p data-sourcepos=\"1:1-1:8\"><del>gone</del></p>\n"

(markdown->xml "# hi\n" (make-cmark-options 'extensions '()))
=> "...<document sourcepos=\"1:1-1:4\" xmlns=\"...\">\n  <heading sourcepos=\"1:1-1:4\" level=\"1\">..."
```

`plain` (used by "markdown->html renders a heading" and the XML test) is
`(make-cmark-options 'extensions '())` (`test-render.sps:136`) — it does not
override `source-positions?` either, so it inherits the mutated default exactly
like `default-cmark-options` does. The exact-string match `"<h1>hi</h1>\n"` and the
substring checks `"<table>"`/`"<td>1</td>"`/`"<heading level=\"1\">"` etc. all fail
because `data-sourcepos="..."`/`sourcepos="..."` is inserted **between** the tag
name and the next attribute, breaking every one of those literal substrings.
**Strikethrough does not fail** ("strikethrough renders through markdown->html" is
absent from the FAIL list) because `<del>` is an inline node, and cmark's HTML
renderer only attaches `data-sourcepos` to block-level nodes — confirmed directly
above (`<del>gone</del>` inside the mutated output is byte-identical to the
unmutated form). "the façade exposes the renderers" uses the same
`'extensions '()` construction as `plain` and fails for the identical reason.

Restored; `diff` against the backup: no differences; `make test`:
`ALL SUITES PASSED`, 178/178.

**Finding:** this is the largest prediction-to-observation gap of the three
mutations run today. A default-value mutation and a bit-wiring mutation (like A)
stress this harness differently: bit-wiring mutations are exactly what the parity
cells are built to catch, but a default-value mutation can pass straight through
the parity layer if the baseline config on either side of a comparison doesn't
pin the mutated field explicitly — and gets caught instead, if at all, wherever an
exact-output assertion (`test-options.sps`'s field check, `test-render.sps`'s
string matches) or an *implicitly*-pinned discrimination-guard baseline happens to
depend on the old default. Both parts of that sentence had to be checked against
the real run; neither was obvious from reading `options.sls` alone.

### Mutation H — mistyped extension name (covered, wider blast radius than predicted)

Source: `task-7-report.md`, Step 5. `(tagfilter . "tagfilter")` →
`(tagfilter . "tagfiltr")` in `options.sls`'s native-name alist (the string value
only; the symbol key `tagfilter` used by `default-extensions` was untouched).

```
=== tests/test-render.sps ===
%%%% Starting test render
FAIL tables render through markdown->html, given the default extension set
FAIL strikethrough renders through markdown->html
FAIL tagfilter's <script> defanging under unsafe-html? requires the extension list reaching render-html
FAIL the default options do NOT emit data-sourcepos (ADR-0008)
FAIL raw HTML is suppressed by default
FAIL a javascript: link has its href emptied by default
FAIL all five standard extensions are available in the loaded library
FAIL every supported extension symbol maps to a name cmark resolves
# of expected passes      27
# of unexpected failures  8
```

`SUITE FAILED`, exit 2. The brief's own prose ("both fail") reads as if only the
two capability-probe assertions ("all five standard extensions are available in
the loaded library" and "every supported extension symbol maps to a name cmark
resolves") would be affected. 8 failed, not 2. Mechanism: `default-extensions` is a
literal **symbol** list untouched by the mutation, so `(default-cmark-options)`
still requests the `tagfilter` *symbol*. Every renderer call built on
`(default-cmark-options)` therefore still asks `call-with-native-document` to
attach an extension named, via `extension->native-name`, `"tagfiltr"`.
`scope.sls`'s `acquire!` calls `find-extension` on that string eagerly for *every*
requested extension before any parsing happens, gets NULL, and raises
`&cmark-extension-unavailable` immediately — so every test that renders through
`(default-cmark-options)` fails outright, not just the two probe assertions. The
two probe assertions fail for a related but distinct reason:
`cmark-gfm-available-extensions` calls `find-extension` on `"tagfiltr"` directly,
gets NULL, and filters `tagfilter` out of its own result, dropping it from five
symbols to four. Restored; `diff` against the backup: `RESTORED: identical to
HEAD`; `make test`: render back to 35/35, `ALL SUITES PASSED`.

**Finding:** one misspelling has a much wider blast radius than "the capability
probe drops one extension" — it breaks default-options rendering entirely, because
the eager-attach path (Task 3/6) and the probe path (Task 7) both resolve through
the identical string. That coupling, not just the probe's own count, is the real
thing this mutation demonstrates.

## `make test-memory`

Clean baseline (no mutation applied), run fresh today for this log, on macOS
(Darwin), arm64. Per the Makefile and ADR-0003, this platform runs an ASan preload
with leak detection explicitly disabled (`ASAN_OPTIONS=detect_leaks=0`) —
LeakSanitizer is unsupported on macOS/arm64.

```
macOS: ASan preload only; LeakSanitizer is unsupported on arm64.
Leak claims must come from Linux CI (ADR-0003).
%%%% Starting test conditions
# of expected passes      18
%%%% Starting test lifecycle
# of expected passes      22
%%%% Starting test native
# of expected passes      29
%%%% Starting test options
# of expected passes      36
%%%% Starting test render
# of expected passes      35
%%%% Starting test shim-loading
# of expected passes      10
exit=0
```

150 passes across the 6 `MEMORY_TESTS` suites (`test-differential.sps` is excluded
by the Makefile's own design — its ~400 CLI subprocesses are not
memory-instrumented and add no coverage `test-render.sps` doesn't already provide).
No AddressSanitizer report of any kind. Per ADR-0003, leak claims proper require
Linux CI; this is the ASan-preload check macOS can do, and on the clean tree it is
silent.

**Mutation C, run against this exact target, is not silent** — see above. That is
the one place in this log where `make test-memory` has something to say, and where
what it actually says (a bare, unattributed `Trace/BPT trap: 5`, not the clean
"heap-use-after-free" diagnostic the brief anticipated) is itself the finding.

## Deliberate coverage gaps

Recorded here rather than papered over, per the design spec §10 and this task's
own brief.

### `validate-utf8?` is behaviourally unreachable

The public API takes a Scheme string, and `string->utf8` always produces valid
UTF-8, so `CMARK_OPT_VALIDATE_UTF8` has no observable effect on any input reachable
through `markdown->*`. No differential cell can discriminate it — the CLI can be
fed invalid bytes from a file; the Scheme API cannot construct an invalid-UTF-8
string to feed it in the first place. `tests/test-differential.sps` says so
explicitly in its own comment ("`validate-utf8?` is off here and is not given an
OFAT cell: its behaviour is structurally unreachable through the public API").
Covered only at the bit level, in `tests/test-native.sps`:
`"validate-utf8? is wired to a real bit even though its behaviour is unreachable"`
(`(not (= (option-bits #t #f #f #f #f #f) (option-bits #f #f #f #f #f #f)))`). The
behavioural property itself is uncovered by construction, not by omission. Design
spec §10.1.

### `&cmark-extension-unavailable` is unreachable from the public API

By design (§3.5): unknown extension symbols are rejected by `validate` at options
construction, before any native resource exists, so the private-layer condition
`&cmark-extension-unavailable` can never actually surface through
`markdown->*`/`(cmark gfm)`. It keeps its Stage 1 private-layer test,
`tests/test-lifecycle.sps`'s `"a missing extension is named in the condition"`,
which reaches the condition directly through `call-with-native-document` with a
raw (non-symbol-validated) native-name string — the one caller in this codebase
still able to construct the scenario. Design spec §10.2.

### Mutation C — no named test catches it

Restated from above for completeness of this section, per the brief's third
bullet: freeing the render buffer before copying it is a real, reproducible
double-free (confirmed via a manual ASan run with `MallocNanoZone=0`), and it
crashes both `make test` and `make test-memory` outright — but neither command, run
as the Makefile actually defines them, attributes the crash to any named assertion
or produces a diagnostic banner. The exit-gate protection is real (a broken build
fails loudly); the assertion-level protection this log otherwise documents is not.
Closing this would mean either adding `MallocNanoZone=0` to the `test-memory`
recipe on Darwin so ASan's own interposed `free()` wins the race and reports
cleanly, or accepting that on this platform, this class of defect is only ever
caught by exit code, never by name.

## Final clean-tree confirmation

```
$ git status --short
?? .plans/stage-2-mutation-log.md
$ make test; echo "exit=$?"
=== tests/test-conditions.sps ===
%%%% Starting test conditions
# of expected passes      18
=== tests/test-differential.sps ===
%%%% Starting test differential
# of expected passes      28
=== tests/test-lifecycle.sps ===
%%%% Starting test lifecycle
# of expected passes      22
=== tests/test-native.sps ===
%%%% Starting test native
# of expected passes      29
=== tests/test-options.sps ===
%%%% Starting test options
# of expected passes      36
=== tests/test-render.sps ===
%%%% Starting test render
# of expected passes      35
=== tests/test-shim-loading.sps ===
%%%% Starting test shim-loading
# of expected passes      10
ALL SUITES PASSED
exit=0
```

The only change in the tree is this file, untracked. Every mutation above (C, F, G
run fresh; A, B, D, E, H transcribed) was individually reverted and confirmed
byte-identical to its backup via `diff` before the next began. No mutation was left
in the tree while another was applied, and the final count (178/178, 7 suites)
matches the baseline exactly.
