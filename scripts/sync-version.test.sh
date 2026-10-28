#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/sync-version.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "sync-version: $*"; exit 1; }

mkdir -p "$tmp/src-tauri"
cd "$tmp"

cat > Cargo.toml <<'TOML'
[workspace]
members = ["src-tauri"]

[workspace.package]
version = "1.0.0"
edition = "2021"
TOML

cat > package.json <<'JSON'
{
  "name": "fake-app",
  "version": "0.0.1",
  "private": true
}
JSON

cat > src-tauri/tauri.conf.json <<'JSON'
{
  "productName": "Fake App",
  "version": "0.0.2",
  "identifier": "com.example.fake"
}
JSON

# Out of sync: --check fails.
"$script" --check >/dev/null 2>&1 && fail "mismatch should fail --check"

# No argument propagates the Cargo.toml version.
"$script" >/dev/null
"$script" --check >/dev/null 2>&1 || fail "propagate should leave files in sync"
grep -q '"version": "1.0.0"' package.json || fail "package.json not synced"
grep -q '"version": "1.0.0"' src-tauri/tauri.conf.json || fail "tauri.conf.json not synced"

# --set updates all three files.
"$script" --set 2.3.4 >/dev/null
grep -q '^version = "2.3.4"$' Cargo.toml || fail "Cargo.toml not set"
grep -q '"version": "2.3.4"' package.json || fail "package.json not set"
grep -q '"version": "2.3.4"' src-tauri/tauri.conf.json || fail "tauri.conf.json not set"
grep -q '^edition = "2021"$' Cargo.toml || fail "--set touched other Cargo.toml keys"
"$script" --check >/dev/null 2>&1 || fail "--check should pass after --set"

# Drift in a single file fails --check.
sed 's/"version": "2.3.4"/"version": "9.9.9"/' package.json > package.json.new && mv package.json.new package.json
"$script" --check >/dev/null 2>&1 && fail "package.json drift should fail --check"

# Usage errors.
"$script" --set >/dev/null 2>&1 && fail "--set without a version should fail"
"$script" --bogus >/dev/null 2>&1 && fail "unknown flag should fail"

echo "sync-version: ok"
