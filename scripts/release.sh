#!/usr/bin/env bash
# Bumps both manifest version fields, commits, and tags the release.
#
# Usage: scripts/release.sh <new-version>
#   e.g. scripts/release.sh 0.8.0
#   or:  pixi run release 0.8.0
#
# Requires a clean working tree and matching existing version fields.
# Commits and tags locally without pushing:
#   git push origin main --tags
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: scripts/release.sh <new-version>  (e.g. scripts/release.sh 0.8.0)" >&2
    exit 1
fi

NEW_VERSION="$1"
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "release.sh: version must look like MAJOR.MINOR.PATCH (got '$NEW_VERSION')" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/pixi.toml"

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "release.sh: working tree isn't clean -- commit or stash first" >&2
    exit 1
fi

# Fails loudly (before touching anything) if the two fields have already
# drifted, rather than bumping one and silently deepening the split.
"$ROOT/scripts/check_version.sh"

OLD_VERSION="$(awk '
    $0 == "[workspace]" { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && /^version = "/ {
        gsub(/^version = "|"$/, "")
        print
        exit
    }
' "$MANIFEST")"

if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    echo "release.sh: pixi.toml is already at $NEW_VERSION" >&2
    exit 1
fi

# Every `version = "$OLD_VERSION"` line matches -- both the [workspace] and
# [package] fields, confirmed identical by check_version.sh above -- so one
# substitution bumps both in one pass; no section-scoping needed here since
# every candidate line is meant to change.
sed -i.bak "s/^version = \"$OLD_VERSION\"\$/version = \"$NEW_VERSION\"/" "$MANIFEST"
rm -f "$MANIFEST.bak"

"$ROOT/scripts/check_version.sh"

git -C "$ROOT" add "$MANIFEST"
git -C "$ROOT" commit -m "Bump version to $NEW_VERSION"
git -C "$ROOT" tag "v$NEW_VERSION"

echo "release.sh: committed and tagged v$NEW_VERSION -- review with 'git show', then 'git push origin main --tags'"
