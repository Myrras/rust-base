# ci-workflows

Shared CI for Tauri 2 apps: reusable GitHub Actions workflows, a shared `common.just` and release scripts. Callers keep thin workflow files and pin this repo at `@v1`.

## Reusable workflows

All are `on: workflow_call` only. Every workflow takes `ci-ref` (string, default `v1`): the ref of this repo from which shared files (`common.just`, `scripts/`) are fetched into `$RUNNER_TEMP/ci`. The shared checkout is moved there right after checkout, so it is never inside the caller workspace. In `integration.yml` it is reserved (accepted for uniformity, no shared files are fetched). Secrets are passed explicitly; never use `secrets: inherit`.

| Workflow          | Inputs                                                                                                                                                                                                                                                                                                                                                                               | Secrets                                                            | Notes                                                                                                                                                                                            |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `tauri-ci.yml`    | `rust-runner` (default `ubuntu-latest`; on Linux the Tauri apt packages are installed first), `windows` (string, default `auto`; `auto`, `always` or `never`, see [Windows checks](#windows-checks-and-the-windows-label)), `windows-test-scope` (default `--workspace`), `extra-recipe` (default empty; runs `just <extra-recipe>` from the repo justfile after the rust recipe)    | none                                                               | Jobs `frontend`, `rust`, `windows`, `ci-ok` (aggregate gate; a skipped windows job is fine). The Rust cache is saved only on `main`.                                                             |
| `release.yml`     | `title-prefix` (default empty; joined with a space, so no trailing space), `require-deploy-key` (bool, default `false`)                                                                                                                                                                                                                                                              | `RELEASE_DEPLOY_KEY` (optional)                                    | Caller grants `contents: write, pull-requests: read, actions: write`. Dispatches the caller's `build.yml` with `--ref <tag>`. A missing deploy key only warns unless `require-deploy-key: true`. |
| `pr-checks.yml`   | `ci-ref` only                                                                                                                                                                                                                                                                                                                                                                        | none                                                               | Changelog entry gate and release:patch/minor/major/no-release label gate.                                                                                                                        |
| `build.yml`       | `ci-ref` only                                                                                                                                                                                                                                                                                                                                                                        | none                                                               | macOS + Windows matrix, installers (dmg, NSIS), uploads artifacts, attaches them to the GitHub Release on `refs/tags/v*`.                                                                        |
| `integration.yml` | `runner` (default `ubuntu-latest`), `apt-packages` (default empty), `setup-wsl` (bool, default `false`), `wsl-distro` (default `Ubuntu-24.04`), `wsl-packages` (default empty; packages installed inside the WSL distro), `env` (default empty; extra `KEY=value` lines written to `GITHUB_ENV`, not for secrets), `recipe` (default `test-integration`, run from the repo justfile) | `INTEGRATION_TOKEN` (optional, exposed as env `INTEGRATION_TOKEN`) | Covers DB drivers, ssh, WSL and real-API tests.                                                                                                                                                  |

## common.just

Recipes:

- `rust`: `cargo fmt --check` (skipped on Windows), `clippy -D warnings`, `cargo test {{TEST_SCOPE}}` (`TEST_SCOPE` env, default `--workspace`)
- `frontend`: `pnpm format:check`, `lint`, `test`, `build`
- `ci`: `rust`, then `frontend`
- local only: `build-signed`, `sweep`, `_signed-conf`, `_target-dir`

In CI the recipes run as `just -f "$RUNNER_TEMP/ci/common.just" -d . <recipe>`. Locally, each repo justfile imports the file:

```just
import? '~/.ci-workflows/common.just'
```

Callers point `~/.ci-workflows` at their local clone of this repo, e.g. `ln -s /path/to/ci-workflows ~/.ci-workflows`.

A repo justfile keeps its own `test-integration` and extra recipes, and must not redefine the names above.

In CI the `import?` resolves to nothing, because the path under `~` does not exist on the runner. No recipe in a caller justfile may list a `common.just` recipe as a dependency (`foo: build-signed`): the dependency is unknown, so the whole file fails to parse and breaks every recipe CI runs (`test-integration`, `extra-recipe`). Call it in the body instead (`just build-signed`). Verify with `HOME=$(mktemp -d) just --list`, which simulates CI by leaving the import unresolved.

## Caller setup

Copy the matching file into the repo's `.github/workflows/` and adjust the inputs:

- [`examples/ci.yml`](examples/ci.yml): push to `main` + pull requests; calls `tauri-ci.yml`, then `release.yml` on push to `main`
- [`examples/pr-checks.yml`](examples/pr-checks.yml): calls `pr-checks.yml`
- [`examples/build.yml`](examples/build.yml): `workflow_dispatch`, calls `build.yml`
- [`examples/integration.yml`](examples/integration.yml): nightly cron + dispatch, calls `integration.yml`

## Dependabot

Callers set `labels: ["release:patch", "dependencies"]` per ecosystem in `.github/dependabot.yml` (see [`examples/dependabot.yaml`](examples/dependabot.yaml); copy it to `.github/dependabot.yml`), so the release-label gate passes with `release:patch`. The changelog gate is skipped for Dependabot PRs (judged on the PR author). A deps-only merge has no CHANGELOG entry, so `release.yml` finds nothing to release; the bumps ship with the next release.

The npm entry ignores semver-major `typescript` updates: typescript-eslint doesn't support TypeScript 7 yet. Remove the `ignore` block when it does.

## Windows checks and the `windows` label

Billed minutes count Linux 1×, Windows 2× and macOS 10×, so by default only `main` pays for Windows:

| Event                         | `windows: auto` (default)                       |
| ----------------------------- | ----------------------------------------------- |
| push to `main`                | runs; gates `release` (`needs: ci`)             |
| pull request                  | runs only if the PR has the `windows` label     |
| `windows` label added to a PR | CI re-runs for the PR, now with Windows         |
| any other label added to a PR | nothing runs (the caller's `ci` job is skipped) |

`windows: always` runs it on every event, `windows: never` never.

The label trigger lives in the caller (see [`examples/ci.yml`](examples/ci.yml)): `labeled` in `pull_request.types`, a concurrency group that only the `windows` label shares with the running CI, and an `if:` on the `ci` job. Keep all three. Without the `if:`, a `release:patch` label would re-run CI; if the skip were inside `tauri-ci.yml` instead, the skipped `ci / ci-ok` would count as passing and replace a real result. A skipped caller job reports only as `ci`, so `ci / ci-ok` stays the result of the last real run. Adding `windows` re-runs frontend and Rust too, so the run still yields one complete `ci / ci-ok`. Removing the label doesn't trigger a run.

If a push and the `windows` label arrive within seconds, the push run (without the label) can cancel the label run, so Windows never runs. Add the label after the push, or remove and re-add it.

Each app repo needs a `windows` label: `gh label create windows --color 0078D6 --description "Run the Windows CI checks on this PR"`.

### When to add the `windows` label

Copy this into the app's `CLAUDE.md`. Add `windows` to a PR when it:

- touches `cfg(windows)`, `cfg(unix)` or `target_os` code, or platform-specific modules
- changes file paths, path separators, drive letters or case sensitivity; process spawning, PTY or shell quoting; environment variables; WSL
- changes the Windows settings in `tauri.conf.json` (bundle, NSIS) or installer scripts
- adds or upgrades a dependency with platform-specific code (`tauri`, `windows-rs`, `portable-pty`, …) or bumps the Rust toolchain
- fixes a Windows bug

Skip it for frontend-only, docs-only and purely cross-platform logic changes. If unsure, add it: `main` runs Windows after the merge anyway, and a failure there blocks the release.

## The `no-release` label

Use `no-release` instead of release:patch/minor/major on PRs that shouldn't release: CI, config, docs and tooling-only changes. The `Release label` gate accepts exactly one of `release:patch`, `release:minor`, `release:major` or `no-release`, and the `Changelog entry` gate is skipped for PRs with `no-release`. pr-checks runs on labeled/unlabeled, so adding or removing the label re-evaluates the gates.

With no CHANGELOG entry, the merge leaves nothing pending and `release.yml` reports "nothing to release". The label is never read as a bump: the bump step only looks at `release:major` and `release:minor`, and only runs when something is pending. If a `no-release` PR does add `## [Unreleased]` entries, they ship with the next release.

The labels must exist in each repo:

```sh
gh label create release:patch --color c5def5 --description "Release: patch bump"
gh label create release:minor --color 0e8a16 --description "Release: minor bump"
gh label create release:major --color d93f0b --description "Release: major bump"
gh label create no-release --color ededed --description "Merge without a release (CI, config, docs)"
```

### Migrating from patch/minor/major

Dependabot applies labels named `major`, `minor` and `patch` (the semver of the update) when they exist, which collided with the release labels. Rename the existing labels; PRs that carry them keep them under the new name:

```sh
gh label edit patch --name release:patch
gh label edit minor --name release:minor
gh label edit major --name release:major
```

Update `labels:` in `.github/dependabot.yml` to `["release:patch", "dependencies"]`. Until the callers and labels are renamed, a PR with a bare `major` label is treated as a patch bump.

## Required checks

In each app repo's branch protection (or ruleset) for `main`, require:

- `ci / ci-ok` (from `ci.yml`)
- `pr-checks / Changelog entry` and `pr-checks / Release label` (from `pr-checks.yml`)

Don't require `ci / frontend`, `ci / rust` or `ci / windows`: `ci-ok` aggregates them, and `ci / windows` is skipped (reported as passing) on most PRs.

## Caller requirements

- **pnpm:** `pnpm/action-setup` is given `version: 10`. Do not add a `packageManager` field to `package.json` that conflicts with it, or the setup fails with "Multiple versions of pnpm specified".
- **`ci-ref`:** defaults to `v1`. To test a branch of this repo, change both the `@ref` in `uses:` and `ci-ref` to that branch.
- **Changelog:** `CHANGELOG.md` must have a `## [Unreleased]` heading; a release without it fails.
- **Release bump:** the highest of release:patch, release:minor and release:major across all PRs since the last tag.
- **Labels:** `release:patch`, `release:minor`, `release:major`, `no-release` and `windows` must exist in the repo. Only the `release:` names count as bumps: Dependabot applies bare `major`/`minor`/`patch` labels itself when they exist, and those are ignored.
- **Linux Rust job:** the workspace must build and pass `cargo test --workspace` on `ubuntu-latest` with the packages installed by `tauri-ci.yml` (WebKitGTK 4.1, libsoup 3, JavaScriptCoreGTK 4.1, appindicator, librsvg, libxdo, OpenSSL, D-Bus, pkg-config). Gate tests that need a desktop session or macOS behind `cfg`, or set `rust-runner: macos-latest`.

## Versioning

Callers pin `@v1`. The `v1` tag is moved to the latest compatible release. Breaking changes ship as `v2`.

## Self-CI

`.github/workflows/self-ci.yml` runs actionlint (workflows and `examples/*.yml`), shellcheck, script tests, `just --fmt --check` and a prettier check of the whole repo.
