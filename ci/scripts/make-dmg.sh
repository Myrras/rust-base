#!/usr/bin/env bash
# Build a distributable .dmg from the Tauri-built .app (APFS).
#
# Why this exists: Tauri's bundled `bundle_dmg.sh` calls
# `hdiutil create -fs HFS+ ...`, which fails with
# "hdiutil: create failed - no mountable file systems" on macOS 26+.
# Tauri has no config knob for the DMG filesystem, so callers build the .app
# only (`pnpm tauri build --bundles app`) and this script packages it.
# The output name matches Tauri's convention: <productName>_<version>_<arch>.dmg.
#
# Usage: make-dmg.sh [REPO_ROOT]
#   REPO_ROOT defaults to the current directory (the caller repo root), so the
#   shared copy is run as `$RUNNER_TEMP/rust-base/ci/scripts/make-dmg.sh` from there.
# Environment: CARGO_TARGET_DIR overrides <REPO_ROOT>/target (as set by local
#   `just` recipes); CI leaves it unset.
set -euo pipefail

REPO_ROOT="$(cd "${1:-.}" && pwd)"

# App name = tauri.conf.json productName (what Tauri names the .app and .dmg).
APP_NAME="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["productName"])' "$REPO_ROOT/src-tauri/tauri.conf.json")"
TARGET_DIR="${CARGO_TARGET_DIR:-$REPO_ROOT/target}"
APP="$TARGET_DIR/release/bundle/macos/${APP_NAME}.app"
OUT_DIR="$TARGET_DIR/release/bundle/dmg"

if [[ ! -d "$APP" ]]; then
	echo >&2 "error: $APP not found; run 'pnpm tauri build --bundles app' first."
	exit 1
fi

VERSION="$(grep -m1 '^version' "$REPO_ROOT/Cargo.toml" | sed -E 's/.*"([^"]+)".*/\1/')"
case "$(uname -m)" in
	arm64) ARCH="aarch64" ;;
	x86_64) ARCH="x64" ;;
	*) ARCH="$(uname -m)" ;;
esac

DMG="$OUT_DIR/${APP_NAME}_${VERSION}_${ARCH}.dmg"

# Staging tree: the app plus a drop-link to /Applications.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG"

echo "Creating APFS disk image -> $DMG"
hdiutil create \
	-volname "$APP_NAME" \
	-srcfolder "$STAGING" \
	-fs APFS \
	-format UDZO \
	-ov \
	"$DMG"

echo "Built $DMG"
