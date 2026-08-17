"""Demo: a stacked bar chart -- Mark.STACKED_BAR, each category's own
series stacked as segments on top of each other instead of Mark.
GROUPED_BAR's side-by-side sub-bars (Plot().mark_stacked_bar().encode_
grouped_bar(categories, series_names, values) -- the exact same data
shape/encode method Mark.GROUPED_BAR uses, only the mark differs; see
that method's own docstring). Same quarterly-revenue-by-region data
examples/grouped_bar.mojo uses, so the two examples read as a direct
before/after comparison of the same numbers under each mark's own
convention: grouped answers "how do the regions compare to each other
each quarter," stacked answers "what's the total, and how is it
composed."

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why
every new example does this from here on.

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
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var series_names: List[String] = ["North", "South", "East"]
    var values: List[List[Float64]] = [
        [42.0, 48.0, 45.0, 61.0],
        [30.0, 35.0, 33.0, 40.0],
        [55.0, 50.0, 58.0, 66.0],
    ]

    var c = Canvas(640 * _SUPERSAMPLE, 420 * _SUPERSAMPLE, Color(255, 255, 255))
    var raster_plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(quarters, series_names, values)
        .labels(title="Quarterly Revenue by Region (stacked)", x_title="Quarter", y_title="Revenue ($M)")
        .theme(Theme(scale=Float64(_SUPERSAMPLE)))
    )
    render(c, raster_plot)
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_stacked_bar.bmp")

    var svg = SvgCanvas(640, 420)
    var svg_plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(quarters, series_names, values)
        .labels(title="Quarterly Revenue by Region (stacked)", x_title="Quarter", y_title="Revenue ($M)")
        .theme(Theme())
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_stacked_bar.svg")

    print("wrote examples/out_stacked_bar.bmp and out_stacked_bar.svg")
