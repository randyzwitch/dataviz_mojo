"""Demo: a single-axis chart -- Mark.SINGLE_AXIS, every value plotted
along one horizontal axis with no y-axis at all (Plot.encode_single_
axis(), a plain x plus the usual optional color/color_categories/size
channels -- see that method's docstring). Every point lands on a
single fixed pixel row via a degenerate zero-span y_scale, reusing
Mark.POINT's _draw_point_layer completely unchanged (single_axis.
mojo). Built via dataviz_mojo.single_axis() -- see examples/scatter.
mojo's docstring for what that trades away.

Response-time samples for one endpoint -- the classic single-axis use:
seeing the distribution/clustering of one-dimensional data (a cluster
of fast responses, a scattering of slow outliers) that a strip of
points along one line shows more directly than a histogram's binning
would.
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import single_axis
from dataviz_mojo.theme import Theme


def main() raises:
    var response_ms: List[Float64] = [
        12.0, 14.0, 13.0, 15.0, 11.0, 14.0, 13.0, 12.0, 45.0, 15.0, 13.0, 14.0, 12.0, 90.0, 14.0,
    ]

    var c = single_axis(response_ms)
    write_bmp(c, "examples/out_single_axis.bmp")
    write_png(c, "examples/out_single_axis.png")

    var svg_plot = Plot().mark_single_axis().encode_single_axis(x=response_ms).theme(Theme())
    var svg = render_svg(svg_plot)
    write_svg(svg, "examples/out_single_axis.svg")
