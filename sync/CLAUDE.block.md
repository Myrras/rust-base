## Shared CI and recipes (rust-base)

CI, release and installer builds come from
<https://github.com/RobbieMinderhoud/rust-base>. `.github/workflows/` holds thin
callers (`ci.yml`, `pr-checks.yml`, `build.yml`, `integration.yml`) of its
reusable workflows, pinned `@v1`. The callers and the shared config files
(`.gitattributes`, `.editorconfig`, `rust-toolchain.toml`, `.prettierrc.json`,
`.prettierignore`, `eslint.config.js`, `tsconfig*.json`,
`.github/dependabot.yml`) are synced from rust-base: **change them there**,
not here. Behaviour is documented in the rust-base README.

App-specific CI settings (runner, Windows test scope, extra recipe, release
title prefix, integration packages and env) live in `.github/rust-base.json`.
That file is owned by this repo.

- **Required checks on `main`:** `ci / ci-ok`, `pr-checks / Changelog entry`,
  `pr-checks / Release label`. Don't require `ci / frontend`, `ci / rust` or
  `ci / windows`. The labels `release:patch`, `release:minor`, `release:major`,
  `no-release` and `windows` must exist.
- **Release labels:** every PR carries exactly one of `release:patch`,
  `release:minor` or `release:major`, enforced by `pr-checks.yml`. Use
  `no-release` for CI, config or docs-only PRs. Merging to `main` releases:
  the version is the latest `v*` tag bumped by the highest label across the PRs
  merged since. Never bump the version or create a tag by hand; `just version`
  is for emergencies only.
- **Changelog gate:** every PR adds an entry under `## [Unreleased]` in
  `CHANGELOG.md` (user-facing changes only, _Keep a Changelog_). `pr-checks.yml`
  fails unless the PR touches `CHANGELOG.md` and that section holds at least one
  `- ` entry. The heading must stay exactly `## [Unreleased]`. `no-release` PRs
  need no entry.
- **`packageManager`:** don't add one to `package.json`. The shared workflows
  set pnpm 10; a second version fails setup.
- **Shared recipes** (`dev`, `dev-signed`, `build`, `build-signed`,
  `install-signed`, `check`, `test-core`, `format`, `version`, `version-check`,
  `rust`, `frontend`, `ci`, `sweep`) come from `ci/common.just` in rust-base.
  The justfile imports it with `import? '~/.rust-base/ci/common.just'`; link
  your clone with `ln -s /path/to/rust-base ~/.rust-base`. Don't redefine those
  names (just rejects duplicates) and never add `set allow-duplicate-recipes`:
  change the shared recipe in rust-base instead. Recipes that CI calls
  (`test-integration`) must not depend on shared recipes: in CI the optional
  import resolves to nothing.

### When to add the `windows` label

Windows CI runs on pushes to `main` and on PRs that carry the `windows` label
(adding the label re-runs CI for the PR). It gates the release. Add `windows`
to a PR when it:

- touches `cfg(windows)`, `cfg(unix)` or `target_os` code, or platform-specific modules
- changes file paths, path separators, drive letters or case sensitivity; process spawning, PTY or shell quoting; environment variables; WSL
- changes the Windows settings in `tauri.conf.json` (bundle, NSIS) or installer scripts
- adds or upgrades a dependency with platform-specific code (`tauri`, `windows-rs`, `portable-pty`, …) or bumps the Rust toolchain
- fixes a Windows bug

Skip it for frontend-only, docs-only and purely cross-platform logic changes. If unsure, add it: `main` runs Windows after the merge anyway, and a failure there blocks the release.
