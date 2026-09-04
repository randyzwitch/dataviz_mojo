#!/usr/bin/env bash
# Checks that pixi.toml's [workspace].version and [package].version agree,
# and, when given a git ref/tag as an argument, that it matches too (#228).
# Nothing enforced this before: each of the three release-bump PRs (#164,
# #187, #201) edited both fields by hand, and the git tag is a third,
# independently hand-created copy.
#
# Usage:
#   scripts/check_version.sh              # just checks the two manifest fields
#   scripts/check_version.sh v0.8.0       # also checks a tag/ref against them
#
# `v0.8.0` and `0.8.0` are both accepted as the tag form (a leading `v` is
# stripped before comparing), matching this repo's own tag naming
# (`v0.3.0`, `v0.4.0`, ... in `git tag`).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/pixi.toml"

# Scoped by section (awk, not a bare grep) so a `version = "..."` inside
# some other table -- [package.build.config.pkg]'s own dependency specs,
# say -- can never be mistaken for the workspace/package version. Matches
# `^version = "..."` only, so `backend = { name = "...", version = "0.*" }`
# (an inline table value, not a line of its own) is never a candidate.
_section_version() {
    awk -v section="$1" '
        $0 == "[" section "]" { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^version = "/ {
            gsub(/^version = "|"$/, "")
            print
            exit
        }
    ' "$MANIFEST"
}

workspace_version="$(_section_version workspace)"
package_version="$(_section_version package)"

if [ -z "$workspace_version" ]; then
    echo "check_version.sh: couldn't find [workspace].version in $MANIFEST" >&2
    exit 1
fi
if [ -z "$package_version" ]; then
    echo "check_version.sh: couldn't find [package].version in $MANIFEST" >&2
    exit 1
fi

if [ "$workspace_version" != "$package_version" ]; then
    echo "check_version.sh: [workspace].version ($workspace_version) and [package].version" \
        "($package_version) disagree" >&2
    exit 1
fi

echo "check_version.sh: [workspace].version and [package].version agree ($workspace_version)"

if [ $# -ge 1 ]; then
    tag="${1#v}"
    if [ "$tag" != "$workspace_version" ]; then
        echo "check_version.sh: ref '$1' (version $tag) doesn't match pixi.toml's version" \
            "($workspace_version)" >&2
        exit 1
    fi
    echo "check_version.sh: ref '$1' matches pixi.toml's version"
fi
