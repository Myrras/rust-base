# Shared recipes for the Tauri apps. Run from CI as
# `just -f "$RUNNER_TEMP/ci/common.just" -d . <recipe>`; import locally from a repo justfile
# with `import? '~/.ci-workflows/common.just'`.
# A repo justfile must not define recipes with the names below.

# Rust checks run on `--workspace` unless TEST_SCOPE says otherwise
# (e.g. `-p my-core` on the Windows runner).
TEST_SCOPE := env("TEST_SCOPE", "--workspace")

# Rustfmt is skipped on Windows: its result is the same on every OS and the
# rust job already checks it.

# Rustfmt (not on Windows), clippy and tests.
rust:
    # `tauri::generate_context!` requires the frontendDist dir (../dist,
    # gitignored) to exist when src-tauri compiles.
    mkdir -p dist
    {{ if os() == "windows" { "" } else { "cargo fmt --all --check" } }}
    cargo clippy --workspace --all-targets -- -D warnings
    cargo test {{ TEST_SCOPE }}

# Prettier, ESLint, Vitest and the production build (`pnpm build` runs tsc).
frontend:
    pnpm format:check
    pnpm lint
    pnpm test
    pnpm build

# The full pipeline: rust, then frontend.
ci: rust frontend

# Reuses the stable signing identity in tauri.dev-signed.conf.json
# (that file only sets bundle.macOS.signingIdentity, so it's equally valid for
# release). A stable identity means macOS privacy grants persist and the app
# launches with no Gatekeeper prompt on this machine. Output:
# <target dir>/release/bundle/macos/<App>.app.

# Build a signed release .app for personal install (macOS) and show it in Finder.
build-signed: _build-signed
    open "$(just -f '{{ justfile() }}' -d . _target-dir)/release/bundle/macos"

# Removes old dependency versions and other toolchains' artifacts WITHOUT
# touching the current build, so `target/` stops growing without bound.
# No-op with a hint if cargo-sweep isn't installed (`cargo install cargo-sweep`).

# Reclaim stale build artifacts in target/ (needs cargo-sweep).
sweep:
    @command -v cargo-sweep >/dev/null 2>&1 \
        && cargo sweep --installed >/dev/null && cargo sweep --time 7 >/dev/null \
        && echo "recycled stale target/ artifacts" \
        || echo "cargo-sweep not installed; skipping target/ recycle (cargo install cargo-sweep)"

# The signed release build behind build-signed. Only the .app is built
# (--bundles app): the .dmg step isn't needed for a personal install. The
# target dir is made absolute first (see _target-dir).
_build-signed: _signed-conf
    #!/usr/bin/env bash
    set -euo pipefail
    # Assigned apart from the export, so a failed lookup stops the recipe
    # (`export X="$(…)"` takes export's status and hides it from set -e).
    target_dir="$(just -f '{{ justfile() }}' -d . _target-dir)"
    export CARGO_TARGET_DIR="$target_dir"
    pnpm install
    pnpm tauri build --bundles app --config src-tauri/tauri.dev-signed.conf.json
    just -f '{{ justfile() }}' -d . sweep

# The cargo target directory as an absolute path, resolved from the repo root.
# tauri runs cargo from src-tauri/, where a relative CARGO_TARGET_DIR would
# point elsewhere than the recipes look: the signed recipes export this to the
# build so both agree.
_target-dir:
    @cargo metadata --format-version 1 --no-deps | node -e 'let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => console.log(JSON.parse(s).target_directory))'

# Guard for the signed recipes. The config is gitignored (it names *your*
# machine's signing identity), so a fresh clone or git worktree does not have it
# and tauri would fail with an opaque config error instead.
_signed-conf:
    @test -f src-tauri/tauri.dev-signed.conf.json || { echo "error: src-tauri/tauri.dev-signed.conf.json is missing."; echo "It is gitignored (machine-specific signing identity), so copy it from another checkout of this repo, or create it for your own signing identity."; echo "Your identities: security find-identity -v -p codesigning"; exit 1; }
