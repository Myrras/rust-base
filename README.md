# rust-base

The base for cross-platform desktop apps in **Rust + Tauri 2 + React + TypeScript + Vite**. One repo, two roles:

- **[Shared CI](#shared-ci):** reusable GitHub Actions workflows (`.github/workflows/reusable-*.yml`), shared `just` recipes (`ci/common.just`) and release scripts (`ci/scripts/`). Apps keep thin caller workflows and pin this repo at `@v2`.
- **[Template app](#template-app):** the repo root is a working Tauri app with the shared skeleton and conventions, and one tiny sample feature (greet + notes) wired end to end so `just dev` and `just ci` work out of the box. New apps [start from this template](#start-a-new-app-from-this-template).

Every PR here runs the shared CI on the template app: this repo's own callers use the local reusable workflows and the PR's own `ci/` files. See `CLAUDE.md` for the conventions.

## Shared CI

### Reusable workflows

All are `on: workflow_call` only. Every workflow takes `ci-repo` (string, default `RobbieMinderhoud/rust-base`) and `ci-ref` (string, default `v2`): the repo and ref from which the shared files (`ci/common.just`, `ci/scripts/`) are fetched into `$RUNNER_TEMP/rust-base`. The shared checkout is moved there right after checkout, so it is never inside the caller workspace. In `reusable-integration.yml` both are reserved (accepted for uniformity, no shared files are fetched). Secrets are passed explicitly; never use `secrets: inherit`.

| Workflow                   | Inputs                                                                                                                                                                                                                                                                                                                                                                               | Secrets                                                            | Notes                                                                                                                                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `reusable-tauri-ci.yml`    | `rust-runner` (default `ubuntu-latest`; on Linux the Tauri apt packages are installed first), `windows` (string, default `auto`; `auto`, `always` or `never`, see [Windows checks](#windows-checks-and-the-windows-label)), `windows-test-scope` (default `--workspace`), `extra-recipe` (default empty; runs `just <extra-recipe>` from the repo justfile after the rust recipe)    | none                                                               | Jobs `frontend`, `rust`, `windows`, `ci-ok` (aggregate gate; a skipped windows job is fine). The Rust cache is saved only on `main`.                                                             |
| `reusable-release.yml`     | `title-prefix` (default empty; joined with a space, so no trailing space), `require-deploy-key` (bool, default `false`)                                                                                                                                                                                                                                                              | `RELEASE_DEPLOY_KEY` (optional)                                    | Caller grants `contents: write, pull-requests: read, actions: write`. Dispatches the caller's `build.yml` with `--ref <tag>`. A missing deploy key only warns unless `require-deploy-key: true`. |
| `reusable-pr-checks.yml`   | `ci-repo` and `ci-ref` only                                                                                                                                                                                                                                                                                                                                                          | none                                                               | Changelog entry gate and release:patch/minor/major/no-release label gate.                                                                                                                        |
| `reusable-build.yml`       | `ci-repo` and `ci-ref` only                                                                                                                                                                                                                                                                                                                                                          | none                                                               | macOS + Windows matrix, installers (dmg, NSIS), uploads artifacts, attaches them to the GitHub Release on `refs/tags/v*`.                                                                        |
| `reusable-integration.yml` | `runner` (default `ubuntu-latest`), `apt-packages` (default empty), `setup-wsl` (bool, default `false`), `wsl-distro` (default `Ubuntu-24.04`), `wsl-packages` (default empty; packages installed inside the WSL distro), `env` (default empty; extra `KEY=value` lines written to `GITHUB_ENV`, not for secrets), `recipe` (default `test-integration`, run from the repo justfile) | `INTEGRATION_TOKEN` (optional, exposed as env `INTEGRATION_TOKEN`) | Covers DB drivers, ssh, WSL and real-API tests.                                                                                                                                                  |

The per-app inputs of `reusable-tauri-ci.yml`, `reusable-release.yml` and `reusable-integration.yml` default to empty (`false` for booleans) and fall back to the app's [`.github/rust-base.json`](#per-app-config-githubrust-basejson), then to the defaults above. A non-empty input still wins; a boolean input wins only when `true`. The `windows` input stays an input only.

The standard names (`ci.yml`, `pr-checks.yml`, `build.yml`, `integration.yml`) in `.github/workflows/` are this repo's own callers. They call the local reusable workflows with `ci-repo: ${{ github.repository }}` and `ci-ref` set to the PR's head commit, so a PR tests its own changes. `ci.yml` has no release job: the template app is never released. `build.yml` is `workflow_dispatch` only, to test the build workflow by hand.

### ci/common.just

Recipes:

- `rust`: `cargo fmt --check` (skipped on Windows), `clippy -D warnings`, `cargo test {{TEST_SCOPE}}` (`TEST_SCOPE` env, default `--workspace`)
- `frontend`: `pnpm format:check`, `lint`, `test`, `build`
- `ci`: `rust`, then `frontend`
- local only: `dev`, `dev-signed`, `build`, `build-signed`, `install-signed`, `check`, `test-core`, `format`, `version`, `version-check`, `sweep` (plus the private `_build-signed`, `_signed-conf`, `_target-dir`)

The local recipes need no per-app settings; they read what differs from the repo:

- app name: `productName` in `src-tauri/tauri.conf.json`
- core crate (`test-core`): the one workspace package named `*-core`
- target dir: `cargo metadata` (honours `CARGO_TARGET_DIR`)
- signing identity (`dev-signed`, `build-signed`, `install-signed`): `src-tauri/tauri.dev-signed.conf.json`
- scripts (`make-dmg.sh`, `sync-version.sh`): `ci/scripts/`, next to `common.just`

In CI the recipes run as `just -f "$RUNNER_TEMP/rust-base/ci/common.just" -d . <recipe>`. Locally, an app justfile imports the file from a local clone of this repo:

```just
import? '~/.rust-base/ci/common.just'
```

Point `~/.rust-base` at the clone, e.g. `ln -s /path/to/rust-base ~/.rust-base`. This repo's own `justfile` uses the plain relative import `import 'ci/common.just'`.

A justfile keeps its own `default`, `test-integration` and extra recipes, and must not redefine the names above. `just` rejects a duplicate recipe; don't work around that with `set allow-duplicate-recipes` (the repo's recipe would silently win).

In an app's CI the `import?` resolves to nothing, because the path under `~` does not exist on the runner. No recipe in an app justfile may list a `common.just` recipe as a dependency (`foo: build-signed`): the dependency is unknown, so the whole file fails to parse and breaks every recipe CI runs (`test-integration`, `extra-recipe`). Call it in the body instead (`just build-signed`). Verify with `HOME=$(mktemp -d) just --list`, which simulates CI by leaving the import unresolved.

### Caller setup

Every app runs the same four callers, kept in [`sync/files/.github/workflows/`](sync/files/.github/workflows/) and copied verbatim into each app:

- `ci.yml`: push to `main` + pull requests; calls the CI workflow, then the release workflow on push to `main`
- `pr-checks.yml`: calls the PR checks workflow
- `build.yml`: `workflow_dispatch`, calls the build workflow
- `integration.yml`: nightly cron + dispatch, calls the integration workflow

Rules:

- **Identical callers.** The synced callers pin `@v2`, pass no `with:` and always pass the secrets `RELEASE_DEPLOY_KEY` and `INTEGRATION_TOKEN` explicitly (an unset secret is an empty string). Don't edit them in an app: the next sync overwrites them. Change them here, in `sync/files/`.
- **Apps own `.github/rust-base.json`.** Whatever differs per app goes in that file. It is not synced; each app keeps its own.

[`examples/`](examples/) shows the same callers with the optional `with:` inputs, for repos outside the sync.

### Per-app config: `.github/rust-base.json`

Read by each reusable workflow's `config` job from the caller repo at the caller's ref. Every key is optional; a missing file or key means the default. An empty string counts as unset. Unknown keys log a warning; a value of the wrong type fails the run.

| Key                              | Type   | Default            | Effect                                                                 |
| -------------------------------- | ------ | ------------------ | ---------------------------------------------------------------------- |
| `ci.rust-runner`                 | string | `ubuntu-latest`    | Runner for the Rust job                                                |
| `ci.windows-test-scope`          | string | `--workspace`      | `cargo test` arguments on Windows (e.g. `-p my-core`)                  |
| `ci.extra-recipe`                | string | none               | Recipe from the app's justfile, run after the rust recipe              |
| `release.title-prefix`           | string | none               | Release title and tag message prefix (`MyApp` → `MyApp v1.2.3`)        |
| `release.require-deploy-key`     | bool   | `false`            | Fail instead of warn without `RELEASE_DEPLOY_KEY`                      |
| `integration.runner`             | string | `ubuntu-latest`    | Runner for the integration job                                         |
| `integration.apt-packages`       | string | none               | Space-separated apt packages (Linux)                                   |
| `integration.setup-wsl`          | bool   | `false`            | Install a WSL distro (Windows)                                         |
| `integration.wsl-distro`         | string | `Ubuntu-24.04`     | WSL distro to install                                                  |
| `integration.wsl-packages`       | string | none               | Packages installed inside the WSL distro                               |
| `integration.env`                | string | none               | Extra `KEY=value` lines (`\n`-separated) for `GITHUB_ENV`; not secrets |
| `integration.recipe`             | string | `test-integration` | Recipe in the app's justfile that runs the tests                       |

Example (an app with a core crate and a protected `main`):

```json
{
  "ci": { "windows-test-scope": "-p my-core" },
  "release": { "title-prefix": "MyApp", "require-deploy-key": true },
  "integration": { "apt-packages": "libdbus-1-dev pkg-config" }
}
```

This repo's own [`.github/rust-base.json`](.github/rust-base.json) lists every key with its default.

### Dependabot

Apps set `labels: ["release:patch", "dependencies"]` per ecosystem in `.github/dependabot.yml` (see [`examples/dependabot.yaml`](examples/dependabot.yaml) or this repo's own `.github/dependabot.yml`), so the release-label gate passes with `release:patch`. The changelog gate is skipped for Dependabot PRs (judged on the PR author). A deps-only merge has no CHANGELOG entry, so the release workflow finds nothing to release; the bumps ship with the next release.

The apps' config (`sync/files/.github/dependabot.yml`) is calm: cargo and npm only, monthly, minor/patch grouped per ecosystem, app-specific majors as separate PRs (one per dependency). Majors of the shared stack (React, Tauri, Vite, Vitest, ESLint, TypeScript and friends) are ignored as a bridge: rust-base decides them (this repo's Dependabot is the canary) and they later arrive via the shared package. Action pins live here. This repo's own Dependabot stays weekly with majors and github-actions visible: it is the canary.

### Windows checks and the `windows` label

Billed minutes count Linux 1×, Windows 2× and macOS 10×, so by default only `main` pays for Windows:

| Event                         | `windows: auto` (default)                       |
| ----------------------------- | ----------------------------------------------- |
| push to `main`                | runs; gates `release` (`needs: ci`)             |
| pull request                  | runs only if the PR has the `windows` label     |
| `windows` label added to a PR | CI re-runs for the PR, now with Windows         |
| any other label added to a PR | nothing runs (the caller's `ci` job is skipped) |

`windows: always` runs it on every event, `windows: never` never.

The label trigger lives in the caller (see [`examples/ci.yml`](examples/ci.yml)): `labeled` in `pull_request.types`, a concurrency group that only the `windows` label shares with the running CI, and an `if:` on the `ci` job. Keep all three. Without the `if:`, a `release:patch` label would re-run CI; if the skip were inside `reusable-tauri-ci.yml` instead, the skipped `ci / ci-ok` would count as passing and replace a real result. A skipped caller job reports only as `ci`, so `ci / ci-ok` stays the result of the last real run. Adding `windows` re-runs frontend and Rust too, so the run still yields one complete `ci / ci-ok`. Removing the label doesn't trigger a run.

If a push and the `windows` label arrive within seconds, the push run (without the label) can cancel the label run, so Windows never runs. Add the label after the push, or remove and re-add it.

Each repo needs a `windows` label: `gh label create windows --color 0078D6 --description "Run the Windows CI checks on this PR"`.

The rule for when to add the label is in [`CLAUDE.md`](CLAUDE.md#when-to-add-the-windows-label); copy it into each app's `CLAUDE.md`.

### The `no-release` label

Use `no-release` instead of release:patch/minor/major on PRs that shouldn't release: CI, config, docs and tooling-only changes. The `Release label` gate accepts exactly one of `release:patch`, `release:minor`, `release:major` or `no-release`, and the `Changelog entry` gate is skipped for PRs with `no-release`. pr-checks runs on labeled/unlabeled, so adding or removing the label re-evaluates the gates.

With no CHANGELOG entry, the merge leaves nothing pending and the release workflow reports "nothing to release". The label is never read as a bump: the bump step only looks at `release:major` and `release:minor`, and only runs when something is pending. If a `no-release` PR does add `## [Unreleased]` entries, they ship with the next release.

The labels must exist in each repo:

```sh
gh label create release:patch --color c5def5 --description "Release: patch bump"
gh label create release:minor --color 0e8a16 --description "Release: minor bump"
gh label create release:major --color d93f0b --description "Release: major bump"
gh label create no-release --color ededed --description "Merge without a release (CI, config, docs)"
```

#### Migrating from patch/minor/major

Dependabot applies labels named `major`, `minor` and `patch` (the semver of the update) when they exist, which collided with the release labels. Rename the existing labels; PRs that carry them keep them under the new name:

```sh
gh label edit patch --name release:patch
gh label edit minor --name release:minor
gh label edit major --name release:major
```

Update `labels:` in `.github/dependabot.yml` to `["release:patch", "dependencies"]`. Until the callers and labels are renamed, a PR with a bare `major` label is treated as a patch bump.

### Required checks

In each repo's branch protection (or ruleset) for `main`, require:

- `ci / ci-ok` (from `ci.yml`)
- `pr-checks / Changelog entry` and `pr-checks / Release label` (from `pr-checks.yml`)

Don't require `ci / frontend`, `ci / rust` or `ci / windows`: `ci-ok` aggregates them, and `ci / windows` is skipped (reported as passing) on most PRs.

### Caller requirements

- **pnpm:** `pnpm/action-setup` is given `version: 10`. Do not add a `packageManager` field to `package.json` that conflicts with it, or the setup fails with "Multiple versions of pnpm specified".
- **`ci-repo` / `ci-ref`:** default to `RobbieMinderhoud/rust-base` and `v2`. To test a branch of this repo from an app, change both the `@ref` in `uses:` and `ci-ref` to that branch.
- **Changelog:** `CHANGELOG.md` must have a `## [Unreleased]` heading; a release without it fails.
- **Release bump:** the highest of release:patch, release:minor and release:major across all PRs since the last tag.
- **Labels:** `release:patch`, `release:minor`, `release:major`, `no-release` and `windows` must exist in the repo. Only the `release:` names count as bumps: Dependabot applies bare `major`/`minor`/`patch` labels itself when they exist, and those are ignored.
- **Linux Rust job:** the workspace must build and pass `cargo test --workspace` on `ubuntu-latest` with the packages installed by `reusable-tauri-ci.yml` (WebKitGTK 4.1, libsoup 3, JavaScriptCoreGTK 4.1, appindicator, librsvg, libxdo, OpenSSL, D-Bus, pkg-config). Gate tests that need a desktop session or macOS behind `cfg`, or set `ci.rust-runner` to `macos-latest` in `.github/rust-base.json`.

### Versioning

Apps pin `@v2`. The `v2` tag is moved to the latest compatible commit. Breaking changes ship as `v3`. `v1` is the old ci-workflows layout (`tauri-ci.yml`) and is frozen.

### Syncing shared files to the apps

`.github/workflows/sync.yml` pushes the payload in `sync/` to every app in `sync/apps.txt` (one `owner/repo` per line). It runs on a push to `main` that touches `sync/**` or `ci/scripts/sync-apply.sh`, and on `workflow_dispatch`.

- `sync/files/<path>` is copied verbatim to `<path>` in each app, overwriting it. Only files listed there are synced.
- `sync/CLAUDE.block.md` goes into the app's `CLAUDE.md`, between `<!-- rust-base:start -->` and `<!-- rust-base:end -->`. Without the markers the block is inserted after the first `# ` heading paragraph. Text outside the markers is never touched.
- Per app, `ci/scripts/sync-apply.sh` does the work. If nothing differs, nothing happens. Otherwise the workflow force-pushes one commit to the branch `rust-base/sync` and opens or updates the PR "Sync shared files from rust-base" with the label `no-release`. The body lists the changed files and the rust-base commit.
- **Secret:** `SYNC_TOKEN`, a fine-grained PAT with contents and pull-requests write on all apps. The workflow's own token is read-only. Without the secret the run fails with an error.
- **Labels:** `no-release` must exist in each app.
- **Unsigned commits:** the bot's commits are not SSH-signed. That is fine as long as the apps' rulesets don't require signed commits.
- Local run: `ci/scripts/sync-apply.sh <rust-base-dir> <app-dir>`.

### Self-CI

`.github/workflows/self-ci.yml` runs actionlint (workflows and `examples/*.yml`), shellcheck, the `ci/scripts/*.test.sh` tests, `just --fmt --check` (root `justfile` and `ci/common.just`) and a prettier check of the repo.

## Template app

### Layout

```
Cargo.toml                 # [workspace]; [workspace.package] version is the source of truth
justfile                   # test-integration recipe; imports ci/common.just (dev, build, check, format, version, ...)
CHANGELOG.md               # Keep a Changelog; PRs add entries under [Unreleased]
crates/app-core/           # the domain: single entry point (Core), zero Tauri dependency
src-tauri/                 # thin Tauri IPC adapter over app-core
src/                       # React frontend (presentation only)
ci/                        # shared CI: common.just and scripts/ (see Shared CI)
examples/                  # caller workflows for apps
.github/workflows/         # reusable-*.yml, plus this repo's callers: ci, pr-checks, build, integration, self-ci
.github/dependabot.yml     # weekly grouped updates: actions, cargo, npm (canary; apps get a monthly config)
```

### Prerequisites

- Rust (stable; `rust-toolchain.toml` pins `rustfmt` + `clippy`)
- Node 22 + `pnpm` 10
- The Tauri 2 system prerequisites for your OS — see <https://tauri.app/start/prerequisites/>
- `just` (optional but recommended: `brew install just`)

### Get started

```
pnpm install
just dev            # shared recipe: run the app (Vite + Tauri, hot reload)
just ci             # fmt, clippy, tests, eslint, vitest, build (from ci/common.just)
just build          # shared recipe: production desktop bundle
```

`just dev-signed` and `just install-signed` need the gitignored `src-tauri/tauri.dev-signed.conf.json`: create it for your own signing identity (`security find-identity -v -p codesigning`) or copy it from another checkout.

## Start a new app from this template

1. Create the repo from this template (**Use this template** on GitHub). Only the files are copied, not the history or tags.
2. Clone rust-base once and link it, so the app's justfile finds the shared recipes: `ln -s /path/to/rust-base ~/.rust-base`.
3. In the new repo:
   - Replace `import 'ci/common.just'` in the `justfile` with `import? '~/.rust-base/ci/common.just'`, and delete `ci/`, `examples/` and the `reusable-*.yml` and `self-ci.yml` workflows.
   - Replace the callers in `.github/workflows/` with the synced ones from [`sync/files/.github/workflows/`](sync/files/.github/workflows/) (they pin `@v2` and add the release job), and put the app's settings in `.github/rust-base.json` (see [Per-app config](#per-app-config-githubrust-basejson)).
   - Replace `README.md` and the shared-CI parts of `CLAUDE.md` with your app's own.
4. Rename the crates (`app-core`, `app`), the product name / bundle identifier in `src-tauri/tauri.conf.json` (`com.example.app`), and the package names in `Cargo.toml` / `package.json`.
5. Replace the placeholder icons in `src-tauri/icons/` with your own: `pnpm tauri icon path/to/icon.png`.
6. Reset `CHANGELOG.md` to its intro and an empty `## [Unreleased]`, and set your starting version with `just version X.Y.Z` (one-off, before the first release).
7. Replace the sample `Core` (greet + notes) with your real domain, and the sample React shell with your real UI. Keep the wiring — typed IPC, a store mirroring the backend, token-driven styling.
8. Set up releases:
   1. Create the labels `release:patch`, `release:minor`, `release:major`, `no-release` and `windows` (see [The `no-release` label](#the-no-release-label)).
   2. If `main` is protected by a ruleset (PRs required), the release commit needs a way through:

      ```
      ssh-keygen -t ed25519 -N '' -C release -f release_key
      gh repo deploy-key add release_key.pub --allow-write --title 'CI release'
      gh secret set RELEASE_DEPLOY_KEY < release_key
      rm release_key release_key.pub
      ```

      Then add **DeployKey** to the `main` ruleset's bypass list. Without the secret the release job pushes with `GITHUB_TOKEN` (and logs a warning), which works only while `main` is unprotected.

### Releases (in an app)

Every merge to `main` is a release. Each PR adds its entry under `## [Unreleased]` in `CHANGELOG.md` (CI fails without one). On merge, CI picks the next version from the latest `v*` tag — by the PR's `release:patch`, `release:minor` or `release:major` label (exactly one, checked by `pr-checks`; `no-release` for CI, config and docs-only PRs) — bumps the manifests, commits `Release vX.Y.Z`, tags it, creates the GitHub Release and builds the macOS and Windows installers onto it. Don't bump or tag by hand. The first release (no `v*` tag yet) ships the version in `Cargo.toml`.

## License

No license file is included — add one before publishing.
