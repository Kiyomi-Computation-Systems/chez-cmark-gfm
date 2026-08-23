## What

<!-- One or two sentences: what changes and why. -->

## Checklist

- [ ] `make test` is green locally (`ALL SUITES PASSED`)
- [ ] `make check-pins`, `make check-purity`, `make check-help`, and
      `make check-install` are green
- [ ] `make examples` is green
- [ ] Commit/PR title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] Tests accompany code changes, and each new suite ends with `(exit …)`
- [ ] New or changed assertions have been **watched to fail** — mutation
      recorded in `.plans/`
- [ ] `README.org` / `docs/` updated if the public API changed
- [ ] `CHANGELOG.md` entry if the change is user-visible
