"""Demo: an area chart -- Mark.AREA, the same continuous (x, y) data
mark_line() draws, filled down to a zero baseline instead of stroked.
Built via dataviz_mojo.area() -- see examples/scatter.mojo's docstring for what that trades away.
"""

from std.math import sin

from dataviz_mojo.plot import save
from dataviz_mojo import area
from dataviz_mojo.colors import STEELBLUE
from dataviz_mojo.theme import Theme


def main() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(30):
        var t = Float64(i) * 0.3
        x.append(t)
        y.append(sin(t) * 4.0 + 6.0)

    var c = area(x, y, theme=Theme(mark_color=STEELBLUE))
    save(c, "examples/out_area.svg")
    save(c, "examples/out_area.bmp")
    save(c, "examples/out_area.png")

