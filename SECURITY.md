# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 2.0.x (latest) | ✅ |
| < 2.0 | ❌ |

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub:
**Security → Report a vulnerability** on this repository. Do not open a
public issue.

You can expect an acknowledgement within 7 days.

This is an FFI binding around a C library, and it renders untrusted input.
Reports are especially welcome on:

- the native boundary — memory safety, lifetimes, argument validation;
- **rendering policy** — anything that gets raw HTML or a `javascript:`
  URL through `markdown->html` with `unsafe-html?` left at its `#f`
  default, or through `markdown->sxml` under `raw-html: omit`;
- resource limits — input that defeats `max-nodes` or `max-depth`.

Please include your platform, Chez version, and the output of
`make build`, which names the exact libraries discovered.

## What is not a vulnerability

`markdown->ast` performs no sanitisation, by design — see
[The AST is untrusted](docs/ast.md#the-ast-is-untrusted). An `html-block`,
`html-inline`, `link`, or `image` node carrying raw HTML or a
`javascript:` URL exactly as written in the source is the documented
contract, not a bug: `unsafe-html?` governs what the *renderers* emit and
has no effect on the AST. Sanitise when you render your own output from
the tree, not when you parse.
