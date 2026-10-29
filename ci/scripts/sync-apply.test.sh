#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/sync-apply.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "sync-apply: $*"; exit 1; }

base="$tmp/base"
mkdir -p "$base/sync/files/.github/workflows" "$base/sync/files/dir"
echo "new ci" > "$base/sync/files/.github/workflows/ci.yml"
echo "new top" > "$base/sync/files/dir/top.txt"
printf '%s\n' "Shared line 1" "Shared line 2" > "$base/sync/CLAUDE.block.md"

new_app() {
  rm -rf "$tmp/app"
  mkdir -p "$tmp/app"
  echo "$tmp/app"
}

S='<!-- rust-base:start -->'
E='<!-- rust-base:end -->'

# Copy and overwrite.
app=$(new_app)
mkdir -p "$app/.github/workflows"
echo "old ci" > "$app/.github/workflows/ci.yml"
echo "keep me" > "$app/other.txt"
"$script" "$base" "$app"
[ "$(cat "$app/.github/workflows/ci.yml")" = "new ci" ] || fail "file not overwritten"
[ "$(cat "$app/dir/top.txt")" = "new top" ] || fail "file not created"
[ "$(cat "$app/other.txt")" = "keep me" ] || fail "unlisted file touched"

# Markers present: block replaced, text outside kept.
app=$(new_app)
printf '%s\n' "# My app" "" "Intro text." "" "$S" "stale block" "$E" "" "## App notes" "Mine." > "$app/CLAUDE.md"
"$script" "$base" "$app"
expected=$(printf '%s\n' "# My app" "" "Intro text." "" "$S" \
  "<!-- Synced from rust-base. Do not edit this block here; change it in rust-base. -->" \
  "Shared line 1" "Shared line 2" "$E" "" "## App notes" "Mine.")
[ "$(cat "$app/CLAUDE.md")" = "$expected" ] || fail "marker replacement wrong: $(cat "$app/CLAUDE.md")"
grep -q "stale block" "$app/CLAUDE.md" && fail "stale block left"

# Markers absent: inserted after the first heading paragraph.
app=$(new_app)
printf '%s\n' "# My app" "Tagline." "" "## Rest" "Mine." > "$app/CLAUDE.md"
"$script" "$base" "$app"
expected=$(printf '%s\n' "# My app" "Tagline." "" "$S" \
  "<!-- Synced from rust-base. Do not edit this block here; change it in rust-base. -->" \
  "Shared line 1" "Shared line 2" "$E" "" "## Rest" "Mine.")
[ "$(cat "$app/CLAUDE.md")" = "$expected" ] || fail "insertion wrong: $(cat "$app/CLAUDE.md")"

# Heading paragraph is the whole file (no trailing blank line).
app=$(new_app)
printf '%s\n' "# Only heading" > "$app/CLAUDE.md"
"$script" "$base" "$app"
head -n1 "$app/CLAUDE.md" | grep -qx "# Only heading" || fail "heading moved"
grep -qxF "$S" "$app/CLAUDE.md" || fail "block missing after lone heading"

# No `# ` heading: block goes on top, text kept.
app=$(new_app)
printf '%s\n' "## Sub only" "Mine." > "$app/CLAUDE.md"
"$script" "$base" "$app"
[ "$(head -n1 "$app/CLAUDE.md")" = "$S" ] || fail "block not on top without heading"
tail -n2 "$app/CLAUDE.md" | grep -qx "Mine." || fail "app text lost without heading"
grep -qx "## Sub only" "$app/CLAUDE.md" || fail "app heading lost"

# No CLAUDE.md: created with the block.
app=$(new_app)
"$script" "$base" "$app"
[ "$(head -n1 "$app/CLAUDE.md")" = "$S" ] || fail "CLAUDE.md not created"

# Idempotent, in every shape.
for shape in markers nomarkers noheading; do
  app=$(new_app)
  case $shape in
    markers) printf '%s\n' "# A" "" "$S" "x" "$E" "" "tail" > "$app/CLAUDE.md" ;;
    nomarkers) printf '%s\n' "# A" "para" "" "tail" > "$app/CLAUDE.md" ;;
    noheading) printf '%s\n' "just text" > "$app/CLAUDE.md" ;;
  esac
  "$script" "$base" "$app"
  cp -R "$app" "$tmp/first"
  "$script" "$base" "$app"
  diff -r "$tmp/first" "$app" >/dev/null || fail "second run changed files ($shape)"
  rm -rf "$tmp/first"
done

# Block file without trailing newline is still well-formed and stable.
printf '%s' "No newline" > "$base/sync/CLAUDE.block.md"
app=$(new_app)
printf '%s\n' "# A" > "$app/CLAUDE.md"
"$script" "$base" "$app"
grep -qx "No newline" "$app/CLAUDE.md" || fail "block without newline mangled"
grep -qxF "$E" "$app/CLAUDE.md" || fail "end marker not on its own line"

# Missing block and missing files/ are skipped.
rm -rf "$base/sync"
app=$(new_app)
echo "# A" > "$app/CLAUDE.md"
"$script" "$base" "$app"
[ "$(cat "$app/CLAUDE.md")" = "# A" ] || fail "CLAUDE.md changed without a block"

# Usage errors.
"$script" >/dev/null 2>&1 && fail "no args should fail"
"$script" "$base" "$tmp/nope" >/dev/null 2>&1 && fail "missing app dir should fail"

echo "sync-apply: ok"
