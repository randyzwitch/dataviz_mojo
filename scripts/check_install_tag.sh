#!/usr/bin/env bash
# The documented install tag must be the version in pixi.toml (#765).
#
# README.md and docs/src/quickstart.md both tell a new user which ref to
# depend on. They used to say `branch = "main"`, which is a moving target
# for a package that renames and removes API without deprecation cycles.
# They now name a tag -- and a hand-written version number in prose is
# exactly the kind of thing that is right on the day it is written and
# wrong two releases later, with nothing to notice.
#
# release.sh rewrites both as part of a bump, so in normal use this check
# never fires. It exists for the bump that is done by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version="$(awk '
    $0 == "[workspace]" { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && /^version = "/ { gsub(/^version = "|"$/, ""); print; exit }
' "$ROOT/pixi.toml")"

if [ -z "$version" ]; then
    echo "check_install_tag.sh: couldn't read [workspace].version" >&2
    exit 1
fi

expected="dataviz_mojo = { git = \"https://github.com/randyzwitch/dataviz_mojo.git\", tag = \"v$version\" }"
status=0

for f in README.md docs/src/quickstart.md; do
    if ! grep -qF "$expected" "$ROOT/$f"; then
        echo "check_install_tag.sh: $f does not pin v$version. It has:" >&2
        grep -nE '^dataviz_mojo = \{' "$ROOT/$f" >&2 || echo "  (no install line at all)" >&2
        status=1
    fi
done

if [ "$status" -ne 0 ]; then
    echo >&2
    echo "Expected this line:" >&2
    echo "  $expected" >&2
    echo "'pixi run release <version>' rewrites both files for you." >&2
    exit 1
fi

echo "check_install_tag.sh: README and quickstart both pin v$version"
