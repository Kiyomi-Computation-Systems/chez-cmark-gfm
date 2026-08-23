# Options

Every renderer, plus `markdown->ast`, takes a `cmark-options` record as its
options argument. It's an immutable value: `make-cmark-options` builds one,
`cmark-options-with` builds an updated copy, and nothing ever mutates one in
place. See [usage.md](usage.md) for the entry points that consume it.

## The defaults

| Key                 | Default                                              |
|----------------------|-------------------------------------------------------|
| `extensions`        | `(autolink strikethrough table tagfilter tasklist)`  |
| `validate-utf8?`    | `#t`                                                 |
| `source-positions?` | `#f`                                                 |
| `hardbreaks?`       | `#f`                                                 |
| `nobreaks?`         | `#f`                                                 |
| `smart?`            | `#f`                                                 |
| `unsafe-html?`      | `#f`                                                 |
| `max-input-bytes`   | `5242880` (5 MiB)                                    |
| `max-nodes`         | `250000`                                             |
| `max-depth`         | `1000`                                               |

`(default-cmark-options)` builds exactly this record. It's defined as
`(make-cmark-options)` called with no overrides at all, not as a second copy
of these ten values, so the two constructors cannot drift apart.

`markdown->ast`, called with just a markdown string, uses a different
default: `default-ast-options`, built as `(cmark-options-with
(make-cmark-options) 'source-positions? #t)` — every field the same as the
table above except `source-positions?`. Positions are worth having in a
parsed tree and not worth paying for in rendered markup, so the default is
chosen per entry point rather than the record carrying a third "unset"
state. `markdown->ast` called with an explicit options record honours it
verbatim, `default-cmark-options` included. Details are in [ast.md](ast.md).

## Constructing and updating

```scheme
(make-cmark-options 'extensions '(table) 'smart? #t)
;; A new record: extensions '(table), smart? #t, and the other eight
;; fields at their defaults from The defaults above.

(default-cmark-options)
;; Equivalent to (make-cmark-options) with no plist at all.

(cmark-options-with (make-cmark-options 'extensions '(table)) 'smart? #t)
;; A THIRD record. The argument to cmark-options-with is untouched --
;; there is no setter anywhere in this API.
```

`cmark-options?` is the type predicate. `cmark-options-with`, every
renderer, and `markdown->ast` all check it on their options argument —
passing something else raises `&cmark-invalid-option` with key `#f` and
reason `invalid-value`. That check runs before anything else for every
entry point except one: the three-argument form of `markdown->commonmark`
and `markdown->plaintext` checks its width argument *first*, so a call
that gets both the width and the options record wrong raises on `width`
(reason `invalid-width`), not on the options record — see
[Wrap width](usage.md#wrap-width).

Both constructors run their result through the same validation, so nothing
built by `cmark-options-with` can carry a value the original construction
path would have refused. `(cmark gfm options)` imports no native library —
not even transitively — so every one of these checks runs in pure Scheme,
and a rejected plist never reaches native code at all:

| Problem                                                    | Reason              |
|--------------------------------------------------------------|----------------------|
| Plist has an odd number of elements                        | `malformed-plist`   |
| A key is not one of the ten fields                         | `unknown-key`       |
| The same key appears twice in one call                     | `duplicate-key`     |
| A value is the wrong type for its field                    | `invalid-value`     |
| `extensions` names something outside the five known extensions | `unknown-extension` |
| Both `hardbreaks?` and `nobreaks?` are `#t`                 | `contradictory`     |

Each is `&cmark-invalid-option`, with `cmark-invalid-option-key` naming the
field (`#f` for `malformed-plist`, which is a problem with the plist as a
whole, not one field) and `cmark-invalid-option-reason` giving the symbol
above:

```scheme
(guard (e ((cmark-invalid-option? e)
           (list (cmark-invalid-option-key e) (cmark-invalid-option-reason e))))
  (make-cmark-options 'extensiosn '(table)))
;; => (extensiosn unknown-key)
```

See [errors.md](errors.md) for the complete condition hierarchy, including
the conditions renderers and `markdown->ast` raise that construction never
does.

## hardbreaks? and nobreaks?

Both default to `#f`, and setting both to `#t` is refused —
`&cmark-invalid-option`, key `hardbreaks?`, reason `contradictory` — rather
than silently resolved to one of them:

```scheme
(guard (e ((cmark-invalid-option? e) (cmark-invalid-option-reason e)))
  (make-cmark-options 'hardbreaks? #t 'nobreaks? #t))
;; => contradictory
```

This is not a defence against undefined behaviour: cmark's own renderers
give `hardbreaks?` precedence over `nobreaks?` when both option bits are
set, so the combination is well-defined at the C level. Refusing it here is
policy — a caller who set both explicitly made a mistake, and silently
honouring one request while discarding the other would hide that mistake
instead of surfacing it.

## validate-utf8?

Defaults to `#t`, and is a real cmark option bit — but has no effect
reachable through this binding. Markdown input here is always a Scheme
string, encoded internally with `string->utf8`, which cannot produce
invalid UTF-8 from a valid Scheme string. cmark's `validate-utf8?` exists to
replace invalid bytes with U+FFFD for callers who hand it raw, untrusted
bytes; this binding never does, so there is nothing for the flag to correct.

What *is* rejected, regardless of `validate-utf8?`, is an embedded NUL
character — at any position in the string, not only a leading or trailing
one:

```scheme
(guard (e ((cmark-invalid-input? e) (cmark-invalid-input-reason e)))
  (markdown->html (string #\a #\nul #\b) (default-cmark-options)))
;; => embedded-nul
```

This is a property of the string, not of `validate-utf8?`'s setting: cmark's
own accessors return NUL-terminated C strings, and an embedded NUL would
silently truncate rather than error, so it is refused outright before
anything reaches native code.

## Resource limits

Two ceilings bound how much a parse can produce, independent of
`max-input-bytes`: five megabytes of adversarial Markdown can still parse to
millions of nodes, so the input-size limit alone does not bound the
Scheme-side copy.

| Key               | Default            | Bounds                          |
|--------------------|----------------------|-----------------------------------|
| `max-input-bytes` | `5242880` (5 MiB)  | the UTF-8 bytevector parsed      |
| `max-nodes`       | `250000`           | total nodes in the copied tree   |
| `max-depth`       | `1000`             | nesting depth of the copied tree |

Exceeding any of the three raises `&cmark-resource-limit` — a subtype of
`&cmark-invalid-input`, carrying the ceiling that was exceeded via
`cmark-resource-limit-value`, and discriminated from the other two by
`cmark-invalid-input-reason`: `too-large` for `max-input-bytes`,
`too-many-nodes` for `max-nodes`, `too-deep` for `max-depth`. Full
behaviour, including where in a parse each one is checked, is in
[ast.md](ast.md).
