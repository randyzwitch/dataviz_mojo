#!/usr/bin/env bash
# Run the whole test suite, grouped into a handful of batch drivers.
#
# Compiling the library, not running the tests, is most of a test run, and
# `tests/test_*.mojo` is one program per module today, so each compiles the
# library it imports again. scripts/build_test_batches.mojo groups modules
# into a handful of driver programs instead -- see its docstring for how and
# why -- and this script regenerates them fresh, then hands the result to
# scripts/run_parallel.sh exactly as a hand-picked list of modules would be.
#
# `.test_batches/` is a throwaway build artifact, not something to edit or
# commit. Avoids `mapfile`, since macOS runners ship bash 3.2.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf .test_batches
mkdir -p .test_batches
mojo run -I . -I scripts scripts/build_test_batches.mojo \
    > .test_batches/manifest.txt

files=()
while IFS= read -r file; do
    files+=("$file")
done < .test_batches/manifest.txt

exec bash scripts/run_parallel.sh "${files[@]}"
