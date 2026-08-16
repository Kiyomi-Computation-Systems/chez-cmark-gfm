# Stage 0 Findings

## Toolchain

| Item | Value |
|---|---|
| Chez Scheme | 10.4.1 |
| Machine type | tarm64osx |
| cmark-gfm CLI | cmark-gfm 0.29.0.gfm.13 - CommonMark with GitHub Flavored Markdown converter |
| pkg-config libcmark-gfm | 0.29.0.gfm.13 |
| libcmark-gfm-extensions .pc | absent — link manually via core libdir |
| Vendored submodule | vendor/cmark-gfm @ 0.29.0.gfm.13 |

## Open questions

- [ ] Q1: How does Chez marshal `const char *`? (Task 3)
- [ ] Q2: Is the ADR-0005 use-after-free detectable by our tooling? (Task 5)
