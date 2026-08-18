"""Demo: an area chart -- Mark.AREA, the same continuous (x, y) data
mark_line() draws, filled down to a zero baseline instead of stroked.
Built via dataviz_mojo.area() -- see examples/scatter.mojo's
own docstring for what that trades away.

Supersampled 3x -- see examples/scatter.mojo's own docstring for why
every example here now renders this way (and why it isn't just "a
bigger canvas").

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why,
and for why the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from std.math import sin

from canvas_mojo.color import Color
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import area
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(30):
        var t = Float64(i) * 0.3
        x.append(t)
        y.append(sin(t) * 4.0 + 6.0)

    var c = area(
        x,
        y,
        theme=Theme(mark_color=Color(60, 130, 190), scale=Float64(_SUPERSAMPLE)),
        width=640 * _SUPERSAMPLE,
        height=420 * _SUPERSAMPLE,
    )
    var out = downsample(c, _SUPERSAMPLE)

    write_bmp(out, "examples/out_area.bmp")
    write_png(out, "examples/out_area.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_area().encode(x=x, y=y).theme(
        Theme(mark_color=Color(60, 130, 190))
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_area.svg")

    print("wrote examples/out_area.bmp, .png, and .svg")
