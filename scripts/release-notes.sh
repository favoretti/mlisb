#!/bin/sh
# Print the CHANGELOG.md section for a version; fail if there is none.
# usage: scripts/release-notes.sh 0.1.5
set -eu
cd "$(dirname "$0")/.."
version=$1
notes=$(awk -v heading="## [$version]" '
  index($0, heading) == 1 { on = 1; next }
  on && /^## \[/ { exit }
  on && /^\[[^]]+\]: / { exit }
  on { print }
' CHANGELOG.md | sed -e '/./,$!d')
[ -n "$notes" ] || { echo "CHANGELOG.md has no section for $version" >&2; exit 1; }
printf '%s\n' "$notes"
