"""Demo: Plot.labels() -- a chart title and both axis titles
(Plot().labels(title=..., x_title=..., y_title=...); see that method's
own docstring). A grouped bar chart of quarterly revenue by product
line: "Quarterly Revenue" as the chart title, "Quarter" captioning the
x-axis, "Revenue ($M)" captioning the y-axis -- the y-axis title
rotated -90 degrees (reads bottom-to-top, the standard convention), on
both the raster and SVG backends alike (SvgCanvas.draw_text's own
rotation support, added in canvas_mojo specifically for this).

Deliberately Mark.GROUPED_BAR here, not a plain Mark.BAR -- its own
series-name legend reserves a column on the right, narrowing the
actual data area. The chart title still centers precisely over that
narrowed area, not the full canvas width, which is exactly what
dataviz_mojo/ROADMAP.md's own "Plot.labels() precise centering" entry
fixed: before it, a title/x_title centered on the full outer bounds
regardless of how much room a legend (or a wide dynamic left margin)
took away from the actual plot area, visibly off-center whenever
either was wide enough to matter -- see that ROADMAP entry, and
test_render_svg_title_centers_on_inner_plot_rect_not_outer_bounds
(tests/test_plot.mojo), for the concrete before/after.

All three of Plot.labels()'s own strings are independent -- omitting
any one of them (leaving that argument at its own "" default) only
reserves space for the ones actually set; see _apply_labels's own
docstring (plot.mojo) for the margin math.

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
    var series_names: List[String] = ["Hardware", "Software"]
    var values: List[List[Float64]] = [[24.0, 27.0, 25.0, 33.0], [18.0, 21.0, 20.0, 28.0]]

    var c = Canvas(640 * _SUPERSAMPLE, 420 * _SUPERSAMPLE, Color(255, 255, 255))
    var raster_plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(quarters, series_names, values)
        .labels(title="Quarterly Revenue", x_title="Quarter", y_title="Revenue ($M)")
        .theme(Theme(scale=Float64(_SUPERSAMPLE)))
    )
    render(c, raster_plot)
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_titles.bmp")

    var svg = SvgCanvas(640, 420)
    var svg_plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(quarters, series_names, values)
        .labels(title="Quarterly Revenue", x_title="Quarter", y_title="Revenue ($M)")
        .theme(Theme())
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_titles.svg")

    print("wrote examples/out_titles.bmp and out_titles.svg")
