"""#732: the smallest thing that crashes, with no test harness.

`test_render_polar_draws_a_grid_even_with_no_data_on_it` is where every
crash lands. It renders a polar chart whose one point sits at radius 0,
so the radial scale's maximum is 0 -- a degenerate case the drawing code
guards with `if max_r > 0.0 else 0.0` in several places.

Each iteration is named on stderr, which is unbuffered, so the last line
is the iteration that died.

Delete with #732.
"""
from std.sys import stderr

from dataviz import polar
from dataviz.plot import render


def main() raises:
    var angle: List[Float64] = [0.0]
    var radius: List[Float64] = [0.0]
    for i in range(40):
        print("iter", i, file=stderr)
        var plot = polar(angle, radius, width=400, height=300)
        var c = render(plot)
        # Read a pixel so nothing can be optimized away.
        _ = c.get_pixel(220, 30)
    print("ALL DONE", file=stderr)
