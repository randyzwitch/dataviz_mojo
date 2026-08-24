"""Demo: a pie chart -- Mark.ARC, one wedge per category, angular span
proportional to its value, colored via the same default_categorical_
palette() a categorical-color scatter plot uses. A legend (Theme.
show_legend, on by default for Mark.ARC) labels each wedge. Built via
dataviz_mojo.pie() -- see examples/scatter.mojo's docstring for what that trades away.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/donut.mojo's docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import pie
from dataviz_mojo.theme import Theme


def main() raises:
    var browsers: List[String] = ["Chrome", "Safari", "Edge", "Firefox", "Other"]
    var share: List[Float64] = [65.0, 18.0, 5.0, 7.0, 5.0]

    var c = pie(browsers, share, width=400, height=300)

    write_bmp(c, "examples/out_pie.bmp")
    write_png(c, "examples/out_pie.png")

    var svg = SvgCanvas(400, 300)
    var svg_plot = Plot().mark_arc().encode_categorical(x=browsers, y=share).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_pie.svg")

    print("wrote examples/out_pie.bmp, .png, and .svg")
