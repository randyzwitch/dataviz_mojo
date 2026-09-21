#!/usr/bin/env bash
# The chart counts on the docs home page must be honest (#761).
#
# docs/src/_index.md advertises how much this package draws, in three
# places. It said "40+" while the real figures were 73 and 80 -- written
# once when it was true and never revisited, because a number in prose
# is the one thing on that page nothing generates and nothing reads.
# Everything else there comes from the source: the gallery images from
# the docstring examples, the feature matrix from Mark.supports().
#
# The page claims a round floor ("70+"), not an exact count, because
# exact counts read badly in a headline and churn every time a mark is
# added. So this checks the floor rather than an equality:
#
#   * the claim must be a multiple of ten, so the copy stays round;
#   * it must not overstate -- claiming 80+ with 73 marks is a lie;
#   * it must not understate by a whole decade -- at 80 marks, "70+"
#     is still true but is selling the package short, and that is the
#     drift that put "40+" on the page for several releases.
#
# In other words it fires exactly when a decade is crossed, which is
# when the copy genuinely wants rewriting, and stays quiet otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE="$ROOT/docs/src/_index.md"

# Marks: the sentinel one past the largest Mark value, which the layout,
# digest and callback sweeps already read.
marks="$(grep -oE '^\s+comptime COUNT = [0-9]+' "$ROOT/dataviz/core/mark.mojo" | head -1 | grep -oE '[0-9]+')"

# One-call chart functions: public names re-exported from the package
# root that are defined as a `def` returning a Plot or a Figure.
charts="$(python3 - "$ROOT" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
src = (root / "dataviz/__init__.mojo").read_text(encoding="utf-8")
names = set()
for m in re.finditer(r'^from [\w.]+ import \(([^)]*)\)', src, re.M):
    names |= {n.strip().rstrip(",") for n in m.group(1).split("\n") if n.strip().rstrip(",")}
for m in re.finditer(r'^from [\w.]+ import (.+)$', src, re.M):
    if "(" not in m.group(1):
        names |= {n.strip() for n in m.group(1).split(",") if n.strip()}
bodies = [p.read_text(encoding="utf-8") for p in (root / "dataviz").rglob("*.mojo")]
found = set()
for n in (x for x in names if x[:1].islower()):
    pat = r'^def %s(?:\[[^\]]*\])?\((?:[^()]|\([^()]*\))*\)\s*(?:raises\s*)?->\s*(\w+)' % re.escape(n)
    for body in bodies:
        if any(m.group(1) in ("Plot", "Figure") for m in re.finditer(pat, body, re.M)):
            found.add(n)
            break
print(len(found))
PY
)"

status=0

# $1 a grep -oE pattern with one \+?-suffixed number, $2 the true count,
# $3 what it counts. The pattern must match exactly once.
check() {
    local pattern="$1" actual="$2" what="$3"
    local claims claim floor
    claims="$(grep -oE "$pattern" "$PAGE" || true)"
    if [ -z "$claims" ]; then
        echo "check_doc_counts.sh: no $what claim matching /$pattern/ in _index.md" >&2
        status=1
        return
    fi
    if [ "$(echo "$claims" | grep -c .)" -ne 1 ]; then
        echo "check_doc_counts.sh: $what claim is ambiguous:" >&2
        echo "$claims" | sed 's/^/  /' >&2
        status=1
        return
    fi
    claim="$(echo "$claims" | grep -oE '[0-9]+\+')"
    floor="${claim%+}"

    if [ $((floor % 10)) -ne 0 ]; then
        echo "check_doc_counts.sh: $what claims '$claim'; keep it a round number" >&2
        status=1
    elif [ "$floor" -gt "$actual" ]; then
        echo "check_doc_counts.sh: $what claims '$claim' but there are only $actual -- overstated" >&2
        status=1
    elif [ "$actual" -ge $((floor + 10)) ]; then
        echo "check_doc_counts.sh: $what claims '$claim' and there are now $actual -- say '$((actual / 10 * 10))+'" >&2
        status=1
    fi
}

check 'covers [0-9]+\+ chart types' "$marks" "marks"
check 'Nine of the [0-9]+\+ chart types' "$marks" "marks"
check '[0-9]+\+ one-call chart functions' "$charts" "chart functions"

if [ "$status" -ne 0 ]; then
    echo >&2
    echo "Source has $marks marks and $charts one-call chart functions." >&2
    exit 1
fi

echo "check_doc_counts.sh: _index.md is honest about $marks marks and $charts chart functions"
