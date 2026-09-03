#!/usr/bin/env bash
# Runs `mojo run -I . -I tests <file>` for every .mojo file given, in
# parallel, capped at the machine's CPU count (getconf _NPROCESSORS_ONLN
# is POSIX and works on both linux-64 and osx-arm64; uncapped
# parallelism would oversubscribe a CI runner's 2-4 cores). Adapted from
# canvas_mojo's scripts/run_parallel.sh; the extra `-I tests` (for
# tests/_test_helpers.mojo) is passed for every file so the one script
# serves both the test and example tasks.
#
# xargs -P (findutils) rather than GNU parallel, so nothing new to
# install.
#
# Each file's output is captured and printed as one block after it
# finishes, so concurrent runs don't interleave their lines; blocks may
# print in a different order than the file list.
#
# Exit status is nonzero if any file's `mojo run` failed (xargs returns
# 123 if any command exited 1-125), so the surrounding pixi task fails.
set -euo pipefail

CORES="$(getconf _NPROCESSORS_ONLN)"

printf '%s\n' "$@" | xargs -P "$CORES" -I {} bash -c '
    out="$(mojo run -I . -I tests "$1" 2>&1)"
    code=$?
    printf "%s\n" "$out"
    exit "$code"
' _ {}
