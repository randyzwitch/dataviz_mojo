#!/usr/bin/env bash
# Fail if a program that draws one mark compiles any other mark's renderer.
#
# Each `mark_*()` setter binds its own renderer (`Plot._bind`), so a
# program compiles only the renderers of the marks whose setters it
# calls. That property is easy to lose without any test noticing: #817
# routed every setter through one runtime choice over all the families,
# which took a line-only program from 30 s to 72 s cold with identical
# output and every test green. The suite cannot see it because the cost
# is in what gets compiled, not in what runs.
#
# Unoptimized LLVM IR still names every compiled function, so it is
# checked directly:
# - a line-only program (the shared continuous path) must define no
#   `_render_*` function from any mark package but `basic`;
# - a heatmap-only program must define `grid::heatmap::_render_heatmap`
#   and no other mark renderer. That is also this check's positive
#   control: it cannot pass by grepping for a name that never appears.
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

cat > "$WORK/heatmap_only.mojo" <<'EOF'
from dataviz import Plot, render, render_svg


def main() raises:
    var x: List[String] = ["a", "b", "a", "b"]
    var y: List[String] = ["p", "p", "q", "q"]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var p = Plot().mark_heatmap().encode_heatmap(x, y, v)
    _ = render(p)
    _ = render_svg(p)
EOF

PACKAGES='aggregation|binned|categorical|distributions|grid|hierarchy_marks'
PACKAGES="$PACKAGES|multivariate|radial|relationships|spatial"
renderers() {
    grep '^define' "$1" \
        | grep -oE "dataviz::($PACKAGES)::[a-z_0-9]+::_render_[a-z_0-9]+" \
        | sed 's/^dataviz:://' | sort -u || true
}

mojo build -I . --emit llvm "$WORK/line_only.mojo" -o "$WORK/line_only.ll"
mojo build -I . --emit llvm "$WORK/heatmap_only.mojo" -o "$WORK/heatmap_only.ll"

status=0
found="$(renderers "$WORK/line_only.ll")"
if [ -n "$found" ]; then
    echo "check_mark_isolation: a line-only program compiled these renderers:" >&2
    printf '  %s\n' $found >&2
    status=1
fi
found="$(renderers "$WORK/heatmap_only.ll")"
if [ "$found" != "grid::heatmap::_render_heatmap" ]; then
    echo "check_mark_isolation: a heatmap-only program should compile" >&2
    echo "grid::heatmap::_render_heatmap and no other renderer; it compiled:" >&2
    printf '  %s\n' ${found:-(none)} >&2
    status=1
fi
if [ "$status" -ne 0 ]; then
    echo "Each mark_*() setter must bind its own renderer with Plot._bind." >&2
else
    echo "check_mark_isolation: each program compiles only its own mark's renderer"
fi
exit "$status"
