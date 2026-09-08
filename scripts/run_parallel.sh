#!/usr/bin/env bash
# Run Mojo files in parallel, capped at the available CPU count.
# Each file's output is buffered as one block; any failure makes the task fail.
set -euo pipefail

CORES="$(getconf _NPROCESSORS_ONLN)"

printf '%s\n' "$@" | xargs -P "$CORES" -I {} bash -c '
    out="$(mojo run -I . -I tests "$1" 2>&1)"
    code=$?
    printf "%s\n" "$out"
    exit "$code"
' _ {}
