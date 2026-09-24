#!/usr/bin/env bash
# Fail if a program that draws one mark compiles other marks' families.
#
# A program should compile only the render families whose `mark_*()`
# setters it calls (#607). That holds only while `Plot._set_mark()`
# picks the family at compile time; a runtime choice compiles all ten
# families into every program. #817 made that choice at runtime, which
# took a line-only program from 30 s to 72 s cold with identical output
# and every test green. Nothing in the suite can see it, because the
# cost is in what gets compiled rather than in what runs.
#
# Unoptimized LLVM IR still names every compiled function, so it is
# checked directly: a line-only program (the basic family) must define
# no `_render_*` function from any other family package, and, so this
# check cannot pass by grepping for something that is never there, a
# hexbin program must define the binned family's `_render_hexbin`.
# Family entry points are not matched by name because a one-mark family
# (binned) has its `_render_<family>_family` folded into its renderer.
# Measured: 0 such functions before #817, 80 across all ten families
# after it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT"

cat > "$WORK/line_only.mojo" <<'EOF'
from dataviz import line, render, render_svg


def main() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [1.0, 3.0, 2.0]
    var p = line(x, y)
    _ = render(p)
    _ = render_svg(p)
EOF

cat > "$WORK/hexbin_only.mojo" <<'EOF'
from dataviz import hexbin, render_svg


def main() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [1.0, 3.0, 2.0]
    _ = render_svg(hexbin(x, y))
EOF

OTHER='aggregation|binned|categorical|distributions|grid|hierarchy_marks'
OTHER="$OTHER|multivariate|radial|relationships|spatial"
renderers() {
    grep '^define' "$1" \
        | grep -oE "dataviz::($OTHER)::[a-z_0-9]+::_render_[a-z_0-9]+" \
        | sed 's/^dataviz:://' | sort -u || true
}

mojo build -I . --emit llvm "$WORK/line_only.mojo" -o "$WORK/line_only.ll"
mojo build -I . --emit llvm "$WORK/hexbin_only.mojo" -o "$WORK/hexbin_only.ll"

status=0
found="$(renderers "$WORK/line_only.ll")"
if [ -n "$found" ]; then
    echo "check_family_isolation: a line-only program compiled renderers" >&2
    echo "from other mark families:" >&2
    printf '  %s\n' $found >&2
    echo "Plot._set_mark() must choose the family at compile time (#607)." >&2
    status=1
fi
if ! renderers "$WORK/hexbin_only.ll" | grep -qx 'binned::hexbin::_render_hexbin'; then
    echo "check_family_isolation: a hexbin program defines no" >&2
    echo "binned::hexbin::_render_hexbin, so this check can no longer see a family" >&2
    echo "in the IR and its line-only result means nothing." >&2
    status=1
fi
if [ "$status" -eq 0 ]; then
    echo "check_family_isolation: a line-only program compiles no other family's renderers"
fi
exit "$status"
