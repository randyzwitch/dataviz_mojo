#!/usr/bin/env bash
# Runs `mojo run -I . -I tests <file>` for every .mojo file path given
# as an argument, in parallel -- capped at the machine's own CPU count
# (getconf _NPROCESSORS_ONLN, not the GNU-only `nproc`: this repo
# targets both linux-64 and osx-arm64, see pixi.toml's own
# [workspace] platforms, and getconf is POSIX, available on both).
# Uncapped parallelism (xargs -P0, or a fixed count higher than what's
# actually available) would oversubscribe a CI runner's own 2-4 cores
# with a dozen-plus concurrent `mojo run` compiles at once -- capping
# at the real core count is what makes this a real speedup rather than
# a resource-contention regression. Adapted from canvas_mojo's own
# scripts/run_parallel.sh (same repo this package is built on -- see
# the wiki for how that split happened) -- the one real difference is
# the extra `-I tests` flag, unconditional for every file even though
# only tests/*.mojo actually needs it (to import tests/_test_helpers.
# mojo): an unused search path is harmless, and passing it always
# keeps this one script usable for both the test and example pixi
# tasks below, matching that same one-script-for-both-tasks choice.
#
# Not GNU parallel: xargs -P is part of findutils, already present
# everywhere `mojo`/`pixi` themselves run, nothing new to install --
# matches this repo's own "no external tool where a stdlib-adjacent
# one already does the job" stance elsewhere (see e.g. canvas_mojo's
# own DEFLATE encoder, replacing an earlier ImageMagick dependency).
#
# Each file's own full output is captured and printed as one atomic
# block after it finishes (not streamed line-by-line) -- xargs itself
# doesn't buffer per-job output, and unbuffered interleaved output from
# several concurrent `mojo run` processes would interleave their own
# "Running N tests..."/"Summary [...]" lines byte-for-byte, unreadable.
# Blocks may still print in a different order than the file list itself
# (whichever job finishes first prints first) -- expected for parallel
# execution, not a bug.
#
# Exit status: nonzero if *any* file's own `mojo run` failed (xargs's
# own semantics: 123 if any invoked command exited 1-125, 124-126 for
# xargs' own internal failures) -- `pixi run test`/`pixi run example`
# still correctly fails the surrounding CI job, not just silently
# reporting the last-finished job's own status.
set -euo pipefail

CORES="$(getconf _NPROCESSORS_ONLN)"

printf '%s\n' "$@" | xargs -P "$CORES" -I {} bash -c '
    out="$(mojo run -I . -I tests "$1" 2>&1)"
    code=$?
    printf "%s\n" "$out"
    exit "$code"
' _ {}
