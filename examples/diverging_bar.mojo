"""Demo: a diverging bar chart -- Mark.BAR with Theme.color_by_sign
set, coloring each bar by whether its own value is negative
(mark_color_negative) or not (mark_color) -- bars extending below the
zero baseline for negative values already works with no changes
needed (see examples/bar.mojo's own negative-value bar); color_by_sign
is the one further thing a genuinely *diverging* bar chart adds, so
the sign reads at a glance, not just from which direction the bar
points. Raster output built via dataviz_mojo.bar() -- see
examples/scatter.mojo's own docstring for what that trades away; the
color_by_sign=True kwarg is the only thing distinguishing this file
from examples/bar.mojo's own call.

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same Plot -- see examples/donut.mojo's own docstring for why,
and for why the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import bar
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
    var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

    var c = bar(
        quarters,
        net_change,
        theme=Theme(color_by_sign=True, scale=Float64(_SUPERSAMPLE)),
        width=640 * _SUPERSAMPLE,
        height=420 * _SUPERSAMPLE,
    )
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_diverging_bar.bmp")
    write_png(out, "examples/out_diverging_bar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_bar().encode_categorical(x=quarters, y=net_change).theme(
        Theme(color_by_sign=True)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_diverging_bar.svg")

    print("wrote examples/out_diverging_bar.bmp, .png, and .svg")
