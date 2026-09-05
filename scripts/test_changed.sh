#!/usr/bin/env bash
# Runs only the test family modules a change could plausibly affect,
# for local iteration (#229, item 4). The full suite recompiles the
# package once per file and takes tens of minutes; one family module
# takes a few, so the cost of a quick check should scale with what you
# touched rather than with the suite.
#
# What counts as changed: anything differing from origin/main, plus
# staged and unstaged working-tree edits. Pass explicit paths to
# override that ("scripts/test_changed.sh dataviz/contour.mojo").
#
# How a source file maps to a test module: by name. tests/ has no
# declared ownership of dataviz/ modules, so a changed dataviz/foo.mojo
# selects every tests/test_*.mojo mentioning the token "foo" -- which
# works because a mark's tests name its function and module (contour,
# violin, sankey). Two consequences worth knowing:
#
#   - It over-selects on common tokens ("plot", "scale", "theme" appear
#     nearly everywhere), which is the safe direction.
#   - It under-selects when a test exercises a module without naming it,
#     which is the unsafe direction. So this is an iteration aid, not a
#     gate: CI still runs `pixi run test` over everything, and you
#     should too before pushing.
#
# A change to tests/_test_helpers.mojo, pixi.toml, or anything under
# dataviz/ that nothing names selects the whole suite rather than
# guessing.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ "$#" -gt 0 ]; then
    changed=("$@")
else
    mapfile -t changed < <(
        {
            git diff --name-only origin/main...HEAD 2>/dev/null || true
            git diff --name-only 2>/dev/null || true
            git diff --name-only --cached 2>/dev/null || true
        } | sort -u
    )
fi

if [ "${#changed[@]}" -eq 0 ]; then
    echo "test_changed: nothing changed against origin/main; nothing to run."
    exit 0
fi

selected=()
run_everything=""

for path in "${changed[@]}"; do
    [ -n "$path" ] || continue
    case "$path" in
        tests/_test_helpers.mojo)
            run_everything="every module uses tests/_test_helpers.mojo"
            ;;
        tests/test_*.mojo)
            [ -f "$path" ] && selected+=("$path")
            ;;
        dataviz/*.mojo)
            token="$(basename "$path" .mojo)"
            hits="$(grep -l -- "$token" tests/test_*.mojo 2>/dev/null || true)"
            if [ -z "$hits" ]; then
                run_everything="no test module names '$token'"
            else
                while IFS= read -r hit; do
                    selected+=("$hit")
                done <<<"$hits"
            fi
            ;;
    esac
done

if [ -n "$run_everything" ]; then
    echo "test_changed: running the whole suite -- $run_everything."
    mapfile -t selected < <(ls tests/test_*.mojo)
elif [ "${#selected[@]}" -gt 0 ]; then
    # Guarded: printf on an empty array still emits one blank line, which
    # would come back as a single empty "module" to run.
    mapfile -t selected < <(printf '%s\n' "${selected[@]}" | sort -u)
fi

if [ "${#selected[@]}" -eq 0 ]; then
    echo "test_changed: no test module matched the changed files:"
    printf '  %s\n' "${changed[@]}"
    echo "Run 'pixi run test' if you want the whole suite."
    exit 0
fi

echo "test_changed: ${#selected[@]} module(s):"
printf '  %s\n' "${selected[@]}"
exec bash scripts/run_parallel.sh "${selected[@]}"
