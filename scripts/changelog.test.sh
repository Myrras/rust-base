#!/usr/bin/env bash
set -euo pipefail

script="$(dirname "$0")/changelog.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export CHANGELOG="$tmp/CHANGELOG.md"

fail() { echo "changelog: $*"; exit 1; }

cat > "$CHANGELOG" <<'MD'
# Changelog

Intro.

## [Unreleased]

### Added

- **A fictitious widget.** It does widget things.

## [1.0.0] - 2026-01-01

### Fixed

- **An old fix.**
MD

got=$("$script" unreleased)
want=$'### Added\n\n- **A fictitious widget.** It does widget things.'
[ "$got" = "$want" ] || fail "unreleased body: got [$got]"

"$script" release 1.1.0 2026-02-03
want_file=$'# Changelog\n\nIntro.\n\n## [Unreleased]\n\n## [1.1.0] - 2026-02-03\n\n### Added\n\n- **A fictitious widget.** It does widget things.\n\n## [1.0.0] - 2026-01-01\n\n### Fixed\n\n- **An old fix.**'
[ "$(cat "$CHANGELOG")" = "$want_file" ] || fail "release rewrote the file wrongly: $(cat "$CHANGELOG")"

# exit_code CMD...: the command's exit status, without tripping set -e.
exit_code() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

# Freshly released: empty section → unreleased exits 1, "nothing to release"
# (the CI idempotency guard).
[ "$(exit_code "$script" unreleased)" = 1 ] || fail "empty section should exit 1"

# Subheadings without bullets still count as empty.
printf '# Changelog\n\n## [Unreleased]\n\n### Added\n\n## [1.0.0] - 2026-01-01\n\n- old\n' > "$CHANGELOG"
[ "$(exit_code "$script" unreleased)" = 1 ] || fail "subheading-only section should exit 1"

# Missing heading is a broken setup, not "nothing to release": exit 2 for both
# subcommands, and release leaves the file alone.
printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n- old\n' > "$CHANGELOG"
before=$(cat "$CHANGELOG")
[ "$(exit_code "$script" unreleased)" = 2 ] || fail "missing heading should exit 2 (unreleased)"
[ "$(exit_code "$script" release 1.0.1 2026-01-02)" = 2 ] || fail "missing heading should exit 2 (release)"
[ "$(cat "$CHANGELOG")" = "$before" ] || fail "release without heading modified the file"
err=$("$script" unreleased 2>&1 >/dev/null || true)
grep -qF "no '## [Unreleased]' heading" <<< "$err" || fail "missing heading should name the heading"

# Missing file: exit 2 for both subcommands, with a message naming the file.
rm "$CHANGELOG"
[ "$(exit_code "$script" unreleased)" = 2 ] || fail "missing file should exit 2 (unreleased)"
[ "$(exit_code "$script" release 1.0.1 2026-01-02)" = 2 ] || fail "missing file should exit 2 (release)"
err=$("$script" unreleased 2>&1 >/dev/null || true)
grep -qF "$CHANGELOG not found" <<< "$err" || fail "missing file should name the file"

echo "changelog: ok"
