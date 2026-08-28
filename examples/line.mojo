"""Demo: a basic line plot -- Mark.LINE, a custom Theme (different
mark color, thicker line, gridlines off) to show that's actually
wired through quickplot's theme= parameter, not just the default
look. Built via dataviz_mojo.line() -- see examples/
scatter.mojo's docstring for what that trades away.
"""

from std.math import sin

from dataviz_mojo.plot import save
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
    save(c, "examples/out_line.svg")
    save(c, "examples/out_line.bmp")
    save(c, "examples/out_line.png")

