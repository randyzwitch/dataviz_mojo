"""Demo: a basic line plot -- Mark.LINE, a custom Theme (different
mark color, thicker line, gridlines off) to show that's actually
wired through quickplot's theme= parameter, not just the default
look. Built via dataviz_mojo.line() -- see examples/
scatter.mojo's docstring for what that trades away.
"""

from std.math import sin

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import line
from dataviz_mojo.colors import BROWN
from dataviz_mojo.theme import Theme


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
            mark_color=BROWN,
            line_width=3.0,
            show_gridlines=False,
        ),
    )

    write_bmp(c, "examples/out_line.bmp")
    write_png(c, "examples/out_line.png")

    var svg_plot = Plot().mark_line().encode(x=x, y=y).theme(
        Theme(mark_color=BROWN, line_width=3.0, show_gridlines=False)
    )
    var svg = render_svg(svg_plot)
    write_svg(svg, "examples/out_line.svg")
