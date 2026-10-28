# ci-workflows

Shared CI for Tauri 2 apps: reusable GitHub Actions workflows, a shared `common.just` and release scripts. Callers keep thin workflow files and pin this repo at `@v1`.

## Reusable workflows

All are `on: workflow_call` only. Every workflow takes `ci-ref` (string, default `v1`): the ref of this repo from which shared files (`common.just`, `scripts/`) are fetched into `.ci/`. Secrets are passed explicitly; never use `secrets: inherit`.

| Workflow | Inputs | Secrets | Notes |
|---|---|---|---|
| `tauri-ci.yml` | `rust-runner` (default `macos-latest`), `windows` (bool, default `true`), `windows-test-scope` (default `--workspace`), `extra-recipe` (default empty; runs `just <extra-recipe>` from the repo justfile after the rust recipe) | none | Jobs `frontend`, `rust`, `windows`, `ci-ok` (aggregate gate; a skipped windows job is fine). |
| `release.yml` | `title-prefix` (default empty), `require-deploy-key` (bool, default `false`) | `RELEASE_DEPLOY_KEY` (optional) | Caller grants `contents: write, pull-requests: read, actions: write`. Dispatches the caller's `build.yml` with `--ref <tag>`. A missing deploy key only warns unless `require-deploy-key: true`. |
| `pr-checks.yml` | none | none | Changelog entry gate and patch/minor/major label gate. |
| `build.yml` | none | none | macOS + Windows matrix, installers (dmg, NSIS), uploads artifacts, attaches them to the GitHub Release on `refs/tags/v*`. |
| `integration.yml` | `runner` (default `ubuntu-latest`), `apt-packages` (default empty), `setup-wsl` (bool, default `false`), `wsl-distro` (default `Ubuntu-24.04`), `recipe` (default `test-integration`, run from the repo justfile) | `INTEGRATION_TOKEN` (optional, exposed as env `INTEGRATION_TOKEN`) | Covers DB drivers, ssh, WSL and real-API tests. |

## common.just

Recipes:

- `rust`: `cargo fmt --check`, `clippy -D warnings`, `cargo test {{TEST_SCOPE}}` (`TEST_SCOPE` env, default `--workspace`)
- `frontend`: `pnpm format:check`, `lint`, `test`, `build`
- `ci`: `rust`, then `frontend`
- local only: `build-signed`, `sweep`, `_signed-conf`, `_target-dir`

In CI the recipes run as `just -f .ci/common.just -d . <recipe>`. Locally, each repo justfile imports the file:

```just
import? '~/.ci-workflows/common.just'
```

A repo justfile keeps its own `test-integration` and extra recipes, and must not redefine the names above.

## Caller setup

Copy the matching file into the repo's `.github/workflows/` and adjust the inputs:

- [`examples/ci.yml`](examples/ci.yml): push to `main` + pull requests; calls `tauri-ci.yml`, then `release.yml` on push to `main`
- [`examples/pr-checks.yml`](examples/pr-checks.yml): calls `pr-checks.yml`
- [`examples/build.yml`](examples/build.yml): `workflow_dispatch`, calls `build.yml`
- [`examples/integration.yml`](examples/integration.yml): nightly cron + dispatch, calls `integration.yml`

## Versioning

Callers pin `@v1`. The `v1` tag is moved to the latest compatible release. Breaking changes ship as `v2`.

## Self-CI

`.github/workflows/self-ci.yml` runs actionlint, shellcheck, script tests and `just --fmt --check` on this repo.
