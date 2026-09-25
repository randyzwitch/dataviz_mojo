#!/usr/bin/env bash
# Fail unless calling an encoder on a chart whose mark lacks it is a
# compile error naming the encoder (#828), and unless the same call on
# a mark that has it compiles (the positive control, so this cannot
# pass by every program failing).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT"

cat > "$WORK/wrong_mark.mojo" <<'PROG'
from dataviz import Plot, render


def main() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var c = Plot().mark_gantt().encode_categorical(cats, vals)
    _ = render(c)
PROG
cat > "$WORK/right_mark.mojo" <<'PROG'
from dataviz import Plot, render


def main() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var c = Plot().mark_bar().encode_categorical(cats, vals)
    _ = render(c)
PROG

status=0
if mojo build -I . "$WORK/wrong_mark.mojo" -o "$WORK/wrong" > "$WORK/wrong.log" 2>&1; then
    echo "check_typed_misuse: encode_categorical() on a gantt chart compiled; it must not" >&2
    status=1
elif ! grep -q "encode_categorical(): not an encoder of this mark" "$WORK/wrong.log"; then
    echo "check_typed_misuse: the wrong-mark program failed for another reason:" >&2
    grep -E "error|constraint" "$WORK/wrong.log" | head -5 >&2
    status=1
fi
if ! mojo build -I . "$WORK/right_mark.mojo" -o "$WORK/right" > "$WORK/right.log" 2>&1; then
    echo "check_typed_misuse: the positive control did not compile:" >&2
    grep -E "error" "$WORK/right.log" | head -5 >&2
    status=1
fi
if [ "$status" -eq 0 ]; then
    echo "check_typed_misuse: a misplaced encoder is a compile error naming it, and the right one compiles"
fi
exit "$status"
