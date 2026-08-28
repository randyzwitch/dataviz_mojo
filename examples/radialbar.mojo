"""Demo: a radial (multi-ring) progress chart -- Mark.RADIALBAR, one
full concentric ring per category (Plot.encode_categorical(), the same
category + value shape pie()/bar()/polarbar() use), each ring swept
clockwise from 12 o'clock to value/max(values) of the way around a
light-gray track. Built via dataviz_mojo.radialbar() -- see examples/
scatter.mojo's docstring for what that trades away.

Quarterly OKR completion by team -- four teams, each a percentage of
their quarter's objectives completed, drawn as nested "activity
rings" (the first team's ring outermost) instead of a bar chart,
so all four read together as one shape at a glance.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/pie.mojo's docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import radialbar
from dataviz_mojo.theme import Theme


def main() raises:
    var teams: List[String] = ["Platform", "Growth", "Data", "Design"]
    var completion: List[Float64] = [92.0, 78.0, 45.0, 60.0]

    var c = radialbar(teams, completion)
    write_bmp(c, "examples/out_radialbar.bmp")
    write_png(c, "examples/out_radialbar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_radialbar().encode_categorical(x=teams, y=completion).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_radialbar.svg")

    print("wrote examples/out_radialbar.bmp, .png, and .svg")
