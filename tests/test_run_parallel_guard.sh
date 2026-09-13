#!/usr/bin/env bash
# The module-timeout guard, exercised in all three of its states.
#
# `pixi run test` runs Mojo modules and cannot see any of this: the guard
# lives in the runner that launches those modules, so a broken guard
# produces a green suite and a run that never ends. That is what #543 was
# -- half the CI matrix unguarded for weeks behind passing jobs -- so the
# guard needs a test of its own.
#
# Run with `pixi run test-runner`. No toolchain needed: a stub stands in
# for `mojo`, and the module name tells it what to do.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run_parallel.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
skips=0

skip() {
    printf '  SKIP  %s\n' "$1"
    skips=$((skips + 1))
}

check() {
    # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf '  PASS  %s\n' "$1"
    else
        printf '  FAIL  %s: expected [%s], got [%s]\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}

# A stand-in for `mojo run`. The module's name says what it should do, so
# a wedge, a crash and an honest failure can all be staged without the
# toolchain.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/mojo" <<'STUB'
#!/bin/sh
case "$*" in
    # A child that outlives its parent and holds the output pipe open:
    # the case a guard that kills only the process reports on schedule
    # and then waits out anyway.
    *wedge*) sleep 90 & sleep 90 ;;
    *segv*)  kill -SEGV $$ ;;
    *fail*)  echo "Summary [ 0.1 ] 1 tests run: 0 passed , 1 failed"; exit 1 ;;
    *)       echo "Summary [ 0.1 ] 1 tests run: 1 passed , 0 failed" ;;
esac
STUB
chmod +x "$WORK/bin/mojo"

# A PATH holding only what the runner needs, so a guard can be removed
# from it. `perl` present and `timeout` absent is a stock macOS.
build_path() {
    local dir="$1"
    shift
    mkdir -p "$dir"
    local tool src
    for tool in bash sh xargs mktemp find wc getconf dirname rm tr sleep \
        date kill grep sed cat ls env perl timeout gtimeout; do
        src="$(command -v -- "$tool" 2> /dev/null || true)"
        # Skip a shell function or builtin shadowing a real binary.
        case "$src" in
            /*) ln -sf "$src" "$dir/$tool" ;;
        esac
    done
    ln -sf "$WORK/bin/mojo" "$dir/mojo"
    for tool in "$@"; do
        rm -f "$dir/$tool"
    done
}

run_guard() {
    # run_guard <path dir> <timeout> <modules...>; prints "exit elapsed".
    local dir="$1" limit="$2"
    shift 2
    local start end code
    start="$(date +%s)"
    env -i PATH="$dir" HOME="$HOME" MOJO_MODULE_TIMEOUT="$limit" \
        "$dir/bash" "$RUNNER" "$@" > "$WORK/out" 2>&1
    code=$?
    end="$(date +%s)"
    printf '%s %s\n' "$code" "$((end - start))"
}

MODULES=(tests/ok_one.mojo tests/wedge_two.mojo tests/segv_three.mojo
    tests/fail_four.mojo)

# A state can only be exercised where the host has the program it needs.
# A macOS runner has no `timeout(1)` to put on a simulated PATH, which is
# the whole reason #543 existed, so the GNU block is skipped there rather
# than asserted and failed -- and the skip is printed, because a state
# that quietly went unchecked is what this file exists to prevent.
if command -v timeout > /dev/null 2>&1; then
    printf 'A PATH with timeout(1) picks it\n'
    build_path "$WORK/gnu"
    result=($(run_guard "$WORK/gnu" 3 "${MODULES[@]}"))
    check "names timeout" "yes" \
        "$(grep -q 'via timeout' "$WORK/out" && echo yes || echo no)"
    check "breaks the wedge instead of waiting it out" "yes" \
        "$([ "${result[1]}" -lt 30 ] && echo yes || echo no)"
    check "reports the timeout as 124" "yes" \
        "$(grep -q 'wedge_two.mojo (exit 124' "$WORK/out" && echo yes || echo no)"
    check "reports a crash as 139 with no summary" "yes" \
        "$(grep -q 'segv_three.mojo (exit 139, printed no test summary)' \
            "$WORK/out" && echo yes || echo no)"
    check "reports an honest failure as 1" "yes" \
        "$(grep -q 'fail_four.mojo (exit 1)' "$WORK/out" && echo yes || echo no)"
    check "counts the clean modules" "yes" \
        "$(grep -q '1 of 4 modules ran clean' "$WORK/out" && echo yes || echo no)"
else
    printf 'A PATH with timeout(1) picks it\n'
    skip "no timeout(1) on this host, so the GNU path cannot be exercised"
fi

printf 'A stock macOS PATH has no timeout or gtimeout and picks perl (#543)\n'
build_path "$WORK/mac" timeout gtimeout
result=($(run_guard "$WORK/mac" 3 "${MODULES[@]}"))
check "names perl" "yes" \
    "$(grep -q 'via perl' "$WORK/out" && echo yes || echo no)"
# The defect this is really testing. A guard that kills the process and
# not its process group prints the timeout on time and then blocks until
# the orphaned child finishes, so only the clock tells the two apart.
check "breaks the wedge instead of waiting it out" "yes" \
    "$([ "${result[1]}" -lt 30 ] && echo yes || echo no)"
check "reports the timeout as 124" "yes" \
    "$(grep -q 'wedge_two.mojo (exit 124' "$WORK/out" && echo yes || echo no)"
check "reports a crash as 139 with no summary" "yes" \
    "$(grep -q 'segv_three.mojo (exit 139, printed no test summary)' \
        "$WORK/out" && echo yes || echo no)"
check "reports an honest failure as 1" "yes" \
    "$(grep -q 'fail_four.mojo (exit 1)' "$WORK/out" && echo yes || echo no)"
check "counts the clean modules" "yes" \
    "$(grep -q '1 of 4 modules ran clean' "$WORK/out" && echo yes || echo no)"

printf 'No guard at all says so rather than passing quietly\n'
build_path "$WORK/bare" timeout gtimeout perl
result=($(run_guard "$WORK/bare" 3 tests/ok_one.mojo tests/fail_four.mojo))
check "says UNGUARDED" "yes" \
    "$(grep -q 'UNGUARDED' "$WORK/out" && echo yes || echo no)"
check "still runs and still reports" "yes" \
    "$(grep -q '1 of 2 modules ran clean' "$WORK/out" && echo yes || echo no)"

printf 'MOJO_MODULE_TIMEOUT=0 disables the guard on purpose\n'
build_path "$WORK/off"
result=($(run_guard "$WORK/off" 0 tests/ok_one.mojo))
check "says it was disabled" "yes" \
    "$(grep -q 'disabled by MOJO_MODULE_TIMEOUT=0' "$WORK/out" \
        && echo yes || echo no)"
check "exits clean" "0" "${result[0]}"

printf '\n'
if [ "$failures" -ne 0 ]; then
    printf '%s check(s) failed, %s skipped.\n' "$failures" "$skips"
    exit 1
fi
printf 'All guard checks passed, %s skipped.\n' "$skips"
