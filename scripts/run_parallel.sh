#!/usr/bin/env bash
# Run Mojo files in parallel, capped at the available CPU count.
# Each file's output is buffered as one block; any failure makes the task fail.
#
# A module whose `mojo run` dies -- a toolchain crash under parallel load,
# say -- can leave nothing in the interleaved output that names it, beyond
# a stack dump whose only clue is a "Program arguments:" line (#511). The
# exit code caught that, but a reader summing the "Summary [" lines of a
# test run saw only the modules that did report. So every module that
# exits nonzero is named in the tail below, with a note when it printed no
# test summary at all, which is what separates "crashed before running"
# from "ran and failed".
#
# This runner is shared by `pixi run test` and `pixi run example`, and a
# docs example prints no summary by design, so the summary is a note on a
# failure and never a failure by itself.
set -euo pipefail

if [ "$#" -eq 0 ]; then
    printf 'usage: run_parallel.sh <file.mojo> [...]\n' >&2
    exit 2
fi

CORES="$(getconf _NPROCESSORS_ONLN)"
REQUESTED=$#
STATUS_DIR="$(mktemp -d)"
trap 'rm -rf "$STATUS_DIR"' EXIT

# One status file per failing module, named after the module, so parallel
# workers never write to the same file and nothing is lost to interleaving.
code=0
printf '%s\n' "$@" | xargs -P "$CORES" -I {} bash -c '
    out="$(mojo run -I . -I tests "$1" 2>&1)"
    status=$?
    printf "%s\n" "$out"
    if [ "$status" -ne 0 ]; then
        note=""
        case "$out" in
            *"Summary ["*) ;;
            *) note=", printed no test summary" ;;
        esac
        printf "%s\t%s%s\n" "$1" "$status" "$note" \
            > "$2/$(printf "%s" "$1" | tr "/." "__")"
    fi
' _ {} "$STATUS_DIR" || code=$?

FAILED="$(find "$STATUS_DIR" -type f | wc -l)"
printf '\n%s of %s modules ran clean.\n' "$((REQUESTED - FAILED))" "$REQUESTED"
if [ "$FAILED" -ne 0 ]; then
    for status_file in "$STATUS_DIR"/*; do
        while IFS=$'\t' read -r module detail; do
            printf 'FAILED: %s (exit %s)\n' "$module" "$detail"
        done < "$status_file"
    done
    if [ "$code" -eq 0 ]; then
        code=1
    fi
fi
exit "$code"
