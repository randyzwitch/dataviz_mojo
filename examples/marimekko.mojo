"""Demo: a Marimekko/mosaic chart -- Mark.MARIMEKKO, column widths
proportional to each category's own share of the grand total, stacked
segment heights showing each column's own subcategory composition
(Plot.encode_marimekko() -- see that method's own docstring for the
matrix shape). Built via dataviz_mojo.marimekko() -- see
examples/scatter.mojo's own docstring for what that trades away.

Electricity generation by region and energy source -- ECharts.jl's
own marimekko() classic use case (both a region's own overall share of
total generation *and* its energy mix read at a glance, something a
plain stacked bar chart's own equal-width columns can't show at once).

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/donut.mojo's own docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import marimekko
from dataviz_mojo.theme import Theme


def main() raises:
    var regions: List[String] = ["Northeast", "Midwest", "South", "West"]
    var sources: List[String] = ["Coal", "Gas", "Renewables"]
    var generation: List[List[Float64]] = [
        [5.0, 20.0, 15.0, 3.0],
        [30.0, 35.0, 50.0, 20.0],
        [10.0, 15.0, 10.0, 27.0],
    ]

    var c = marimekko(regions, sources, generation)
    write_bmp(c, "examples/out_marimekko.bmp")
    write_png(c, "examples/out_marimekko.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_marimekko().encode_marimekko(
        categories=regions, subcategories=sources, values=generation
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_marimekko.svg")

    print("wrote examples/out_marimekko.bmp, .png, and .svg")
