# Shared recipes for the Tauri apps. Run from CI as
# `just -f "$RUNNER_TEMP/rust-base/ci/common.just" -d . <recipe>`; import locally
# from an app justfile with `import? '~/.rust-base/ci/common.just'` (rust-base
# itself uses `import 'ci/common.just'`).
# A repo justfile must not define recipes with the names below, and must not
# set allow-duplicate-recipes to override them.

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

# Local development. The recipes below are not run by CI; they read
# per-app values (app name, core crate) from the repo itself, so a repo
# justfile needs no settings for them.

# Run the app in development (Vite dev server + Tauri, hot reload).
dev:
    pnpm tauri dev

# `just dev` ad-hoc-signs the binary with a fresh identity every rebuild, so the
# keychain re-prompts each run and "Always Allow" never sticks. This build keeps
# the identity from src-tauri/tauri.dev-signed.conf.json, so one "Always Allow"
# persists. Tradeoff: it runs a bundle, so there is no hot reload. Output:
# <target dir>/debug/bundle/macos/<productName>.app.

# Build and launch a debug .app with a stable signing identity (macOS).
dev-signed: _signed-conf
    #!/usr/bin/env bash
    set -euo pipefail
    target_dir="$(just -f '{{ justfile() }}' -d . _target-dir)"
    export CARGO_TARGET_DIR="$target_dir"
    app="$(node -p 'require("./src-tauri/tauri.conf.json").productName')"
    pnpm tauri build --debug --bundles app --config src-tauri/tauri.dev-signed.conf.json
    just -f '{{ justfile() }}' -d . sweep
    open "$target_dir/debug/bundle/macos/$app.app"

# Tauri's own dmg step uses HFS+, which is broken on macOS 26+, so only the
# .app is built here and ci/scripts/make-dmg.sh packages the .dmg (APFS).

# Release build: the .app plus a .dmg (macOS).
build:
    #!/usr/bin/env bash
    set -euo pipefail
    target_dir="$(just -f '{{ justfile() }}' -d . _target-dir)"
    export CARGO_TARGET_DIR="$target_dir"
    pnpm install
    pnpm tauri build --bundles app
    '{{ source_directory() }}/scripts/make-dmg.sh'
    just -f '{{ justfile() }}' -d . sweep

# The new .app is copied next to the old one and swapped in with mv, so a failed
# copy never leaves /Applications without the app. No Finder window opens.

# Build the signed release and install it in /Applications (macOS).
install-signed: _build-signed
    #!/usr/bin/env bash
    set -euo pipefail
    target_dir="$(just -f '{{ justfile() }}' -d . _target-dir)"
    name="$(node -p 'require("./src-tauri/tauri.conf.json").productName')"
    app="$target_dir/release/bundle/macos/$name.app"
    dest="/Applications/$name.app"
    tmp="/Applications/.$name.app.tmp"
    old="/Applications/.$name.app.old"
    rm -rf "$tmp" "$old"
    ditto "$app" "$tmp"
    if [ -e "$dest" ]; then mv "$dest" "$old"; fi
    if ! mv "$tmp" "$dest"; then
        if [ -e "$old" ]; then mv "$old" "$dest"; fi
        echo "error: could not install $dest" >&2
        exit 1
    fi
    rm -rf "$old"
    echo "Installed → $dest"

# dist/ is created for the same reason as in rust.

# Type-check the whole Rust workspace without building.
check:
    mkdir -p dist
    cargo check --workspace

# The core crate is the one workspace package whose name ends in `-core`.

# Run only the core crate's tests (unit, integration and doc tests).
test-core:
    #!/usr/bin/env bash
    set -euo pipefail
    crate="$(cargo metadata --format-version 1 --no-deps | node -e 'let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => { const c = JSON.parse(s).packages.map((p) => p.name).filter((n) => n.endsWith("-core")); if (c.length !== 1) { console.error(`error: test-core needs exactly one workspace package named *-core, found ${c.length}: ${c.join(", ")}`); process.exit(1); } console.log(c[0]); })')"
    cargo test -p "$crate"

# Format Rust and the frontend.
format:
    cargo fmt --all
    pnpm format

# Cargo.toml's [workspace.package] version is the source of truth.

# Set the version in Cargo.toml, tauri.conf.json and package.json: `just version 1.2.3`.
version new:
    bash '{{ source_directory() }}/scripts/sync-version.sh' --set '{{ new }}'

# Verify the version is the same in Cargo.toml, tauri.conf.json and package.json.
version-check:
    bash '{{ source_directory() }}/scripts/sync-version.sh' --check

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
