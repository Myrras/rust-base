# CLAUDE.md — rust-base

Guidance for AI agents (and humans) working in this repository.

## What this is

rust-base is two things in one repo:

- **The template app** (repo root): the canonical **skeleton and conventions**
  for a cross-platform desktop app in **Rust + Tauri 2 + React + TypeScript +
  Vite**. It is deliberately small: a UI-agnostic core crate, a thin Tauri IPC
  shell, a presentation-only React frontend, version syncing, and CI — plus one
  sample feature (greet + notes) wired end to end so the toolchain works on
  checkout.
- **The shared CI** for every app built from it: the reusable workflows
  `.github/workflows/reusable-*.yml`, the shared recipes `ci/common.just` and
  the release scripts `ci/scripts/`. Apps call them pinned at `@v1`.

New apps are **created from this template**. It is the source of truth for the
shared skeleton; derived apps (e.g. Selene, Podium) carry their own domain on
top.

> **This template is upstream.** When a derived app changes something that
> belongs to the shared skeleton — the workspace/IPC/layering conventions, the
> `justfile`, the CI callers, the shared config files, the design
> tokens, or these conventions themselves — that change must also be **PR'd back
> here** so the template stays current. App-specific domain code does not
> flow back.

> **This repo is public.** Never commit internal names, work e-mail addresses,
> internal hostnames or anything else that identifies an employer.

## Tech stack

| Concern     | Choice                                                    |
| ----------- | -------------------------------------------------------- |
| Shell / UI  | Tauri 2 + React 19 + TypeScript + Vite                   |
| Core        | Plain Rust crate, zero Tauri dependency                  |
| FE state    | Zustand 5 (no data-fetching lib; call IPC, then resync)  |
| Motion      | CSS tokens (`--dur-*`/`--ease-*`), reduced-motion guard  |
| Tests       | `cargo test` (core + integration) · Vitest + jsdom + RTL |

## Architecture

A Cargo **workspace**. `app-core` holds all domain logic and has **zero Tauri
dependency** (plain-`cargo test`-able). `src-tauri` is a thin IPC adapter. `src/`
is the React app (presentation only).

```
crates/app-core/src/
  lib.rs      # Core — THE single entry point (all mutation goes through it)
  error.rs    # CoreError / CoreResult (messages are app-owned text, never secrets)
  ids.rs      # UUID newtypes via the uuid_newtype! macro
crates/app-core/tests/
  core.rs     # integration test over the public API — no UI required
src-tauri/src/
  main.rs     # binary entry → app_lib::run()
  lib.rs      # Tauri builder, plugins, command registration
  state.rs    # AppState: Arc<Core>
  error.rs    # IpcError { kind, message } ← CoreError
  commands/   # one thin (de)serialize-and-forward shim per command
src/
  App.tsx     # the shell
  ipc/        # typed command wrappers + hand-written wire types
  state/      # Zustand stores (mirror the backend; don't guess)
  lib/        # framework-agnostic helpers (log, motion)
  styles/     # tokens.css (design tokens) + global.css (resets/primitives)
```

### The core contract

`Core` (`crates/app-core/src/lib.rs`) is the **single entry point**: all domain
state and mutation live behind it. It is `Send + Sync` and cheap to share (hold
it behind an `Arc`); interior mutability keeps the public API `&self`.

### Tauri IPC contract

Commands return `Result<T, IpcError>` where `IpcError = { kind, message }`.
`kind` is a stable, machine-readable camelCase category the frontend branches
on; `message` is human-readable, sanitized, **app-owned text — never secrets**.
`CoreError` maps to `IpcError` via `From`; IPC-only failures (bad input, parse
errors) use `IpcError::new` / `IpcError::invalid_input`.

> ⚠️ **Wire casing:** everything on the wire is **camelCase** — Tauri maps
> camelCase JS argument keys to snake_case Rust parameters, and structs use
> `#[serde(rename_all = "camelCase")]`. Ids are plain UUID strings
> (`#[serde(transparent)]`). Keep the hand-written types in `src/ipc/types.ts`
> in lockstep with the Rust serde derives whenever either side changes.

### Frontend

Stores (Zustand) are the single place the UI learns about backend state: an
action calls a typed IPC wrapper, then **re-reads from the backend** so the store
mirrors the core rather than optimistically guessing. Components reference design
**tokens** (`src/styles/tokens.css`), never hard-coded colors/durations/easings.

## Build, run, test

Prefer `just` (run `just` to list recipes). The Tauri CLI is the local
`@tauri-apps/cli` dev-dependency, so use `pnpm tauri …` (no global install).

```
just dev              # shared: run the app (Vite + Tauri, hot reload)
just dev-signed       # shared: debug .app with a stable signing identity (macOS)
just build            # shared: production bundle
just install-signed   # shared: signed release build, installed to /Applications
just check            # shared: cargo check --workspace
just test-core        # shared: app-core tests only
just test-integration # #[ignore]d tests (cargo test --workspace -- --ignored)
just format           # shared: rustfmt + prettier
just version 0.2.0    # shared: bump + sync version across all manifests (emergencies only; CI bumps on merge)
just version-check    # shared: verify versions are in sync
just ci               # shared: rust (fmt, clippy, test) + frontend (prettier, eslint, vitest, build)
```

All recipes above marked shared, plus `rust`, `frontend`, `ci`, `build-signed`
and `sweep`, come from `ci/common.just`. This repo's `justfile` imports it with
`import 'ci/common.just'`; an app imports its local rust-base clone with
`import? '~/.rust-base/ci/common.just'` after
`ln -s /path/to/rust-base ~/.rust-base`. Don't redefine those names in a
justfile. `dev-signed` and `install-signed` need the gitignored
`src-tauri/tauri.dev-signed.conf.json`: create it for your own signing identity
(`security find-identity -v -p codesigning`) or copy it from another checkout.

CI is a set of thin callers in `.github/workflows/`: `ci.yml` (checks; in an app
also the release on push to `main`), `pr-checks.yml` (changelog entry + release
label), `build.yml` (installers, dispatched by the release) and
`integration.yml` (nightly `just test-integration`). In an app they call
`RobbieMinderhoud/rust-base/.github/workflows/reusable-*.yml@v1`. In rust-base
they call the local `./.github/workflows/reusable-*.yml` with
`ci-repo: ${{ github.repository }}` and the PR's head commit as `ci-ref`, so
every PR here self-tests the shared CI on the template app. rust-base's `ci.yml`
has no release job: the template app is never released. Behaviour is documented
in `README.md`.

Rust checks run on ubuntu. Windows runs on pushes to `main` and on PRs that carry
the `windows` label (adding the label re-runs CI for the PR). The required check
is `ci / ci-ok` plus `pr-checks / Changelog entry` and `pr-checks / Release label`;
don't require `ci / frontend`, `ci / rust` or `ci / windows`. The `windows` label
must exist in the repo.

### When to add the `windows` label

Add `windows` to a PR when it:

- touches `cfg(windows)`, `cfg(unix)` or `target_os` code, or platform-specific modules
- changes file paths, path separators, drive letters or case sensitivity; process spawning, PTY or shell quoting; environment variables; WSL
- changes the Windows settings in `tauri.conf.json` (bundle, NSIS) or installer scripts
- adds or upgrades a dependency with platform-specific code (`tauri`, `windows-rs`, `portable-pty`, …) or bumps the Rust toolchain
- fixes a Windows bug

Skip it for frontend-only, docs-only and purely cross-platform logic changes. If unsure, add it: `main` runs Windows after the merge anyway, and a failure there blocks the release.

Windows-sensitive spots in this repo are currently few: the `windows_subsystem`
attribute in `src-tauri/src/main.rs` and the `bundle` settings (`targets: all`,
`icons/icon.ico`) in `src-tauri/tauri.conf.json`. There is no `cfg(target_os)`
code and no NSIS-specific config yet.

## Conventions

- **Rust:** `#![forbid(unsafe_code)]` in every crate; `cargo clippy -- -D
  warnings` must pass; `cargo fmt`. Comment the _why_ of non-obvious logic.
- **Layering (always-on):** all domain logic belongs in `app-core`; `src-tauri`
  only (de)serializes and forwards. If a command handler grows logic, move it
  down. The core must keep compiling without Tauri.
- **Security (always-on):** `CoreError`/`IpcError` messages are app-owned text —
  never terminal output, file contents, or secrets. Don't log secrets above
  `DEBUG`. In tests/fixtures use **only fictitious** sample data.
- **Motion:** timing comes from the `--dur-*` / `--ease-*` tokens — no raw
  values in components. Animate only `transform`/`opacity` in hot paths; keep
  the reduced-motion guard working.
- **Casing:** wire casing is fixed (camelCase; see the IPC contract);
  `src/ipc/types.ts` tracks the Rust serde derives.

## Versioning & CI

- **SemVer.** The `[workspace.package]` version in the root `Cargo.toml` is the
  single source of truth; `ci/scripts/sync-version.sh` propagates it to
  `tauri.conf.json` and `package.json` (`just version-check` detects drift).
- **`CHANGELOG.md`** follows _Keep a Changelog_ and lists **only functional
  (user-facing) changes**. Every PR adds its entry under `## [Unreleased]`; the
  `pr-checks.yml` caller fails unless the PR touches `CHANGELOG.md` and that
  section holds at least one `- ` entry.
- **Every PR carries exactly one of `release:patch`, `release:minor` or
  `release:major`**, enforced by `pr-checks.yml`. Use `no-release` instead for
  CI, config or docs-only PRs (no CHANGELOG entry needed).
- **Releasing is automatic in an app: every merge to `main` is a release.**
  (rust-base itself never releases; its `ci.yml` has no `release` job.) The
  `release` job in an app's `ci.yml` runs after `ci` on each push to `main`. An empty
  `## [Unreleased]` means already released. Otherwise the version is the latest
  `v*` tag bumped **patch by default**, `release:minor`/`release:major` by the highest label
  across the PRs merged since the tag; with no `v*` tag yet, the first release
  ships the `Cargo.toml` version as-is. It commits `Release vX.Y.Z [skip ci]`,
  tags, creates the GitHub Release and dispatches `build.yml` on the tag, which
  builds the macOS `.dmg` and Windows NSIS installers and attaches them.
  `build.yml` must keep that name; a hand-pushed tag builds with
  `gh workflow run build.yml --ref vX.Y.Z`.
- **App callers pin `@v1`.** Don't add a `packageManager` field to `package.json`
  (the shared workflows set pnpm 10; a second version fails setup). Recipes CI
  calls (`test-integration`) must not depend on `common.just` recipes: in an
  app's CI the optional import resolves to nothing.
- **Dependabot** (`.github/dependabot.yml`) opens weekly grouped PRs for
  GitHub Actions, Cargo and npm.
- **Protected `main`** (optional, one-off setup per repo): the release job must
  push to `main`, which a ruleset requiring PRs would block (`GH013`); GitHub
  refuses the Actions app as a bypass actor on a user-owned repo (an org-owned repo can add the Actions app as a bypass actor instead), so
  `GITHUB_TOKEN` cannot get through. Create the labels `release:patch`, `release:minor` and
  `release:major` (plus `no-release`), then add a **deploy key with write access** and its private half as the
  secret **`RELEASE_DEPLOY_KEY`**:
  `ssh-keygen -t ed25519 -N '' -C release -f release_key`,
  `gh repo deploy-key add release_key.pub --allow-write --title 'CI release'`,
  `gh secret set RELEASE_DEPLOY_KEY < release_key`, delete both key files, and
  add **DeployKey** to the `main` ruleset's bypass list. The release job checks
  out with that key, so its push goes over SSH and through the bypass. Without
  the secret, `ssh-key` is empty and `actions/checkout` falls back to
  `GITHUB_TOKEN` over HTTPS: fine for an unprotected `main`; the job's first
  step then logs a `::warning::` with these setup commands rather than failing.
  A deploy-key push triggers workflows (a `GITHUB_TOKEN` push does not), hence
  `[skip ci]` on the release commit. Rotating the key = new deploy key +
  `gh secret set RELEASE_DEPLOY_KEY`, then delete the old key.
- **Never bump the version or create a tag by hand**; `just version` is for
  emergencies only.

## Shared CI (`ci/`, `reusable-*.yml`)

The apps depend on these files, so treat them as a public interface. The full
reference (inputs, secrets, labels, required checks) is in `README.md`.

- **Interface:** the reusable workflows' inputs and secrets, the check names
  (`ci / ci-ok`, `pr-checks / Changelog entry`, `pr-checks / Release label`)
  and the `ci/common.just` recipe names. Apps pin `@v1`, which is moved to the
  latest compatible commit; a breaking change ships as `v2`. Never create or
  move a tag (including `v1`) without the owner's explicit OK.
- **Naming:** reusable workflows are `on: workflow_call` only and named
  `reusable-*.yml`. The standard names (`ci.yml`, `pr-checks.yml`, `build.yml`,
  `integration.yml`) are this repo's own callers: keep them like the app
  callers, except that they use the local reusable workflows and pass
  `ci-repo`/`ci-ref`.
- **Shared files:** a reusable workflow checks out `ci-repo` at `ci-ref` into
  `.ci` and moves it to `$RUNNER_TEMP/rust-base` in the next step, so it is
  never inside the caller workspace (or a release commit). Reference shared
  files as `$RUNNER_TEMP/rust-base/ci/common.just` and
  `$RUNNER_TEMP/rust-base/ci/scripts/<name>.sh`.
- **Security:** pin every action by full commit SHA with a version comment;
  keep `permissions:` minimal; `persist-credentials: false` on checkouts that
  don't push; pass secrets explicitly, never `secrets: inherit`; pass inputs to
  `run:` through `env:`, never inline `${{ }}` in scripts.
- **Scripts** (`ci/scripts/`) run from the app repo root and resolve the
  manifests against `$PWD`, never against their own location. A script change
  comes with its `*.test.sh`. Recipes in `ci/common.just` reach the scripts via
  `source_directory()`, so they work both imported and with `just -f`.
- **No overrides:** a justfile that imports `ci/common.just` keeps only its own
  `default`, `test-integration` and genuinely app-specific recipes. `just`
  rejects a duplicate recipe; never work around that with
  `set allow-duplicate-recipes`.
- **Self-CI** (`self-ci.yml`) runs actionlint (workflows and `examples/*.yml`),
  shellcheck, the script tests, prettier and `just --fmt --check`. Run the same
  locally before opening a PR. The callers in this repo additionally run the
  shared CI itself on the template app.
- **`windows` label in rust-base:** besides the rule above, add it when a PR
  changes the `windows` job in `reusable-tauri-ci.yml`, the `rust` recipe in
  `ci/common.just` or `reusable-build.yml`.
