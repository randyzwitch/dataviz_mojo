"""Demo: a basic scatter plot -- Mark.POINT, default theme, axes and
gridlines computed automatically from the data's own domain. Built via
dataviz_mojo.scatter() -- the one-call convenience wrapper
around Plot().mark_point().encode(...).theme(...) + Canvas + render()
-- rather than the builder spelled out by hand; see plot.mojo's own
module docstring (its "one-call convenience functions" section) for
what it trades away (facets, layering, color/size encoding still need
Plot directly).

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/donut.mojo's own docstring for why, and for why
the docs page only shows the quickplot call above. scatter()'s own
raster output is supersampled internally before it's ever returned
here (see dataviz_mojo.plot._rendered's own docstring) -- nothing in
this file, or any other example, has to ask for that.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import scatter
from dataviz_mojo.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

    var c = scatter(x, y)

    write_bmp(c, "examples/out_scatter.bmp")
    write_png(c, "examples/out_scatter.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_point().encode(x=x, y=y).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_scatter.svg")

    print("wrote examples/out_scatter.bmp, .png, and .svg")
