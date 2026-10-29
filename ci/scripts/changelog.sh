#!/usr/bin/env bash
# Manage the `## [Unreleased]` section of CHANGELOG.md.
#
#   changelog.sh unreleased              print its body; exit 1 if it has no `- ` entry
#   changelog.sh release X.Y.Z DATE      rename it to `## [X.Y.Z] - DATE` and add a
#                                        fresh empty `## [Unreleased]` above it
#
# Exit 2 (both subcommands) when the file or the `## [Unreleased]` heading is
# missing, or on bad usage: a broken setup, as opposed to exit 1 for "no entries"
# (nothing to release).
#
# Run it from the app repo root: the file is CHANGELOG.md in the current
# directory, not next to this script (in CI it lives in $RUNNER_TEMP/rust-base/ci/scripts/).
# CHANGELOG overrides the file (tests). perl/awk only, so it runs on macOS and ubuntu.
set -euo pipefail

FILE="${CHANGELOG:-$PWD/CHANGELOG.md}"
HEADING='## [Unreleased]'

require_heading() {
  [ -f "$FILE" ] || { echo "changelog: $FILE not found" >&2; exit 2; }
  grep -qxF "$HEADING" "$FILE" \
    || { echo "changelog: no '$HEADING' heading in $FILE; add it (Keep a Changelog format)" >&2; exit 2; }
}

case "${1:-}" in
  unreleased)
    require_heading
    # Body = lines after the heading up to the next `## ` heading, outer blank lines trimmed.
    body=$(awk -v h="$HEADING" '
      $0 == h { on = 1; next }
      on && /^## / { exit }
      on { print }
    ' "$FILE" | awk 'NF { started = 1 } started' | perl -0pe 's/\s+\z/\n/')
    if ! grep -q '^- ' <<< "$body"; then
      echo "changelog: '$HEADING' in $FILE has no entries" >&2
      exit 1
    fi
    printf '%s\n' "$body"
    ;;
  release)
    ver=${2:-}
    date=${3:-}
    [[ $ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
      || { echo "usage: changelog.sh release X.Y.Z YYYY-MM-DD" >&2; exit 2; }
    require_heading
    V="$ver" D="$date" perl -i -pe '
      if (!$done && $_ eq "## [Unreleased]\n") { $_ = "## [Unreleased]\n\n## [$ENV{V}] - $ENV{D}\n"; $done = 1 }
    ' "$FILE"
    ;;
  *)
    echo "usage: changelog.sh unreleased | release X.Y.Z YYYY-MM-DD" >&2
    exit 2
    ;;
esac
