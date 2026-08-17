"""Demo: a scatter plot with both color and size data-driven encoding
-- a "bubble chart", the classic case for a third and fourth
continuous channel beyond x/y. Both channels now draw a legend by
default (Theme.show_legend's own existing default, True) -- a
gradient bar (_draw_continuous_color_legend, 20 solid strips
approximating ColorScale's own continuous interpolation -- DrawTarget
has no gradient-fill primitive, see that constant's own docstring) for
color, three representative circles (_draw_continuous_size_legend, at
the data's own min/mid/max) for size, stacked in one column since this
plot combines both.

Supersampled 3x -- see examples/scatter.mojo's own docstring for why
every example here now renders this way (and why it isn't just "a
bigger canvas").

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why
every new/updated example does this from here on.

Run with:
    pixi run example
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]
    # color and size both driven by a third variable here (e.g. a
    # "magnitude" column) -- doesn't have to be the same column in
    # general, just convenient for one clear demo.
    var magnitude: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0, 7.0, 6.0, 8.0, 10.0, 9.0]

    var c = Canvas(640 * _SUPERSAMPLE, 420 * _SUPERSAMPLE, Color(255, 255, 255))
    var raster_theme = Theme(
        color_scale_low=Color(250, 220, 60),
        color_scale_high=Color(150, 30, 60),
        size_range_min=4.0,
        size_range_max=18.0,
        scale=Float64(_SUPERSAMPLE),
    )
    var raster_plot = Plot().mark_point().encode(x=x, y=y, color=magnitude, size=magnitude).theme(
        raster_theme
    )
    render(c, raster_plot)
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_bubble.bmp")

    var svg = SvgCanvas(640, 420)
    var svg_theme = Theme(
        color_scale_low=Color(250, 220, 60),
        color_scale_high=Color(150, 30, 60),
        size_range_min=4.0,
        size_range_max=18.0,
    )
    var svg_plot = Plot().mark_point().encode(x=x, y=y, color=magnitude, size=magnitude).theme(
        svg_theme
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_bubble.svg")

    print("wrote examples/out_bubble.bmp and out_bubble.svg")
