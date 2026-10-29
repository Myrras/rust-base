# Changelog

All notable **functional** (user-facing) changes to this project are documented
here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Internal refactors, tooling, and chores are intentionally omitted. Every pull
request adds its entry under `## [Unreleased]`; the version number is assigned
when it merges.

## [Unreleased]

### Added

- Shared frontend config package `@myrras/rust-base-config` (ESLint, Prettier,
  TypeScript) in `packages/config/`, published to npm on `config-vX.Y.Z` tags.
  The template app uses it; apps migrate in a later step.
- Licensed under MIT.

### Changed

- Merged the shared CI (formerly ci-workflows) into this template; reusable
  workflows are now `reusable-*.yml`, shared recipes and scripts live in `ci/`.
  Apps pin `@v2`; `v1` (the old ci-workflows layout) is frozen.
- Apps: Dependabot runs monthly with minor/patch grouped; app-specific majors come as
  separate PRs; shared-stack majors (React, Tauri, Vite, ESLint, ...) are ignored
  until rust-base decides them.
- Owner renamed to Myrras: all references updated.

## [0.2.0] - 2026-10-28

### Changed

- **CI now uses the shared workflows from ci-workflows.** Checks, release and
  installer builds are unchanged for contributors; a nightly integration run is
  added.
- **Release label required.** Every PR must carry exactly one of `patch`,
  `minor` or `major`; it sets the version bump when the PR merges.

## [0.1.0] - 2026-10-08

### Added

- **Every merge ships a release.** Each change that lands on `main` becomes a
  numbered version right away (patch by default, `minor`/`major` via a PR
  label), with macOS and Windows installers attached to its GitHub Release. A
  PR must add its entry here under `## [Unreleased]`.
