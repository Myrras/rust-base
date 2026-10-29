#!/usr/bin/env bash
# Applies the rust-base sync payload to an app checkout.
#   sync-apply.sh <rust-base-dir> <app-dir>
# 1. Copies every file under <rust-base-dir>/sync/files/ into <app-dir>,
#    overwriting.
# 2. Puts <rust-base-dir>/sync/CLAUDE.block.md between the rust-base markers in
#    <app-dir>/CLAUDE.md. Without markers the block is inserted after the first
#    `# ` heading paragraph (or at the top when there is no such heading).
# Idempotent: a second run changes nothing. A missing files/ or block is skipped.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: sync-apply.sh <rust-base-dir> <app-dir>" >&2
  exit 2
fi

base=$1
app=$2
[ -d "$base" ] || { echo "sync-apply: no such directory: $base" >&2; exit 2; }
[ -d "$app" ] || { echo "sync-apply: no such directory: $app" >&2; exit 2; }

start='<!-- rust-base:start -->'
end='<!-- rust-base:end -->'
notice='<!-- Synced from rust-base. Do not edit this block here; change it in rust-base. -->'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Files.
if [ -d "$base/sync/files" ]; then
  while IFS= read -r -d '' f; do
    f=${f#./}
    mkdir -p "$app/$(dirname "$f")"
    cp "$base/sync/files/$f" "$app/$f"
  done < <(cd "$base/sync/files" && find . -type f -print0)
fi

# 2. CLAUDE.md block.
src="$base/sync/CLAUDE.block.md"
[ -f "$src" ] || exit 0

{
  echo "$start"
  echo "$notice"
  cat "$src"
  [ -z "$(tail -c1 "$src")" ] || echo
  echo "$end"
} > "$tmp/block"

target="$app/CLAUDE.md"
if [ ! -f "$target" ]; then
  cp "$tmp/block" "$target"
  exit 0
fi

# Markers must be whole lines, start before end.
s=$(grep -n -x -F -m1 "$start" "$target" | cut -d: -f1 || true)
e=$(grep -n -x -F "$end" "$target" | tail -n1 | cut -d: -f1 || true)

if [ -n "$s" ] && [ -n "$e" ] && [ "$s" -lt "$e" ]; then
  awk -v s="$s" -v e="$e" -v blk="$tmp/block" '
    NR == s { while ((getline l < blk) > 0) print l }
    NR < s || NR > e { print }
  ' "$target" > "$tmp/out"
else
  awk -v blk="$tmp/block" '
    function block(  l) { while ((getline l < blk) > 0) print l; close(blk) }
    state == 0 && /^# / { print; state = 1; next }
    state == 1 && /^[[:space:]]*$/ { print ""; block(); print ""; state = 2; next }
    { print }
    END {
      if (state == 1) { print ""; block() }
      if (state == 0) exit 3
    }
  ' "$target" > "$tmp/out" || {
    # No `# ` heading: put the block at the top.
    { cat "$tmp/block"; echo; cat "$target"; } > "$tmp/out"
  }
fi

cat "$tmp/out" > "$target"
