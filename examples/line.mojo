"""Demo: a basic line plot -- Mark.LINE, a custom Theme (different
mark color, thicker line, gridlines off) to show that's actually
wired through quickplot's own theme= parameter, not just the default
look. Built via dataviz_mojo.quickplot.line() -- see examples/
scatter.mojo's own docstring for what that trades away.

Supersampled 3x -- see examples/scatter.mojo's own docstring for why
every example here now renders this way (and why it isn't just "a
bigger canvas").

Run with:
    pixi run example
"""

from std.math import sin

from canvas_mojo.color import Color
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.resize import downsample
from dataviz_mojo.quickplot import line
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(40):
        var t = Float64(i) * 0.25
        x.append(t)
        y.append(sin(t) * 10.0 + t * 0.5)

    var c = line(
        x,
        y,
        theme=Theme(
            mark_color=Color(180, 60, 40),
            line_width=3.0,
            show_gridlines=False,
            scale=Float64(_SUPERSAMPLE),
        ),
        width=640 * _SUPERSAMPLE,
        height=420 * _SUPERSAMPLE,
    )
    var out = downsample(c, _SUPERSAMPLE)

    write_bmp(out, "examples/out_line.bmp")
    write_png(out, "examples/out_line.png")
    print("wrote examples/out_line.bmp and .png")
