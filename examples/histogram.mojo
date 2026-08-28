"""Demo: a histogram -- Plot.encode_histogram() bins continuous data
into equal-width intervals and maps the result onto Mark.BAR's categorical x-axis (bin range labels) / continuous y-axis (counts)
shape -- the same render path examples/bar.mojo's bar chart uses,
just fed computed categories instead of given ones (see plot.mojo's encode_histogram() docstring). Raster output built via
dataviz_mojo.histogram() -- see examples/scatter.mojo's docstring
for what that trades away.
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import histogram
from dataviz_mojo.colors import REBECCAPURPLE
from dataviz_mojo.theme import Theme


def main() raises:
    # Exam scores out of 100 -- a real bell-ish spread, not a uniform
    # or already-sorted list, so the binning has genuine work to do.
    var scores: List[Float64] = [
        52.0, 61.0, 65.0, 68.0, 70.0, 71.0, 72.0, 74.0, 75.0, 76.0,
        77.0, 78.0, 78.0, 79.0, 80.0, 81.0, 81.0, 82.0, 83.0, 84.0,
        85.0, 86.0, 87.0, 88.0, 89.0, 90.0, 91.0, 93.0, 95.0, 98.0,
    ]

    var c = histogram(scores, bins=8, theme=Theme(mark_color=REBECCAPURPLE))
    write_bmp(c, "examples/out_histogram.bmp")
    write_png(c, "examples/out_histogram.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_bar().encode_histogram(scores, bins=8).theme(
        Theme(mark_color=REBECCAPURPLE)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_histogram.svg")
