#!/usr/bin/env bash
# Usage: next-version.sh <previous tag> <PR labels, comma-separated>
# Prints the next release tag: label `release:major` → vX+1.0.0,
# `release:minor` → vX.Y+1.0, anything else (incl. no PR, e.g. a direct push,
# or a bare `major`/`minor` label from Dependabot) → patch. PRs are required to
# carry one of release:patch/minor/major by the `Release label` workflow.
set -euo pipefail

prev=${1:-}
labels=${2:-}

if [[ ! $prev =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "next-version: previous tag '$prev' is not vX.Y.Z" >&2
  exit 1
fi

IFS=. read -r major minor patch <<< "${prev#v}"

if [[ ",$labels," == *",release:major,"* ]]; then
  echo "v$((major + 1)).0.0"
elif [[ ",$labels," == *",release:minor,"* ]]; then
  echo "v$major.$((minor + 1)).0"
else
  echo "v$major.$minor.$((patch + 1))"
fi
