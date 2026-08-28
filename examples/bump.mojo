"""Demo: a bump chart -- Mark.BUMP, one line per series tracking its *rank* (1 = highest value) among every series at each category, not
its raw value (Plot.encode_grouped_bar(), the exact same categories/
series_names/values shape grouped_bar()/stacked_bar() take -- see
bump.mojo's docstring for the rank computation). Its own hand-
rolled rank axis (rank 1 at the top) -- see that same docstring for
why a real LinearScale doesn't work here. Built via dataviz_mojo.
bump() -- see examples/scatter.mojo's docstring for what that
trades away.

Programming-language popularity rankings over a few years -- the
classic bump-chart use: which position matters more than the exact
score behind it.

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
from dataviz_mojo import bump
from dataviz_mojo.theme import Theme


def main() raises:
    var years: List[String] = ["2021", "2022", "2023", "2024"]
    var languages: List[String] = ["Python", "JavaScript", "Rust"]
    var scores: List[List[Float64]] = [
        [85.0, 90.0, 95.0, 98.0],
        [92.0, 88.0, 84.0, 80.0],
        [40.0, 55.0, 70.0, 85.0],
    ]

    var c = bump(years, languages, scores)
    write_bmp(c, "examples/out_bump.bmp")
    write_png(c, "examples/out_bump.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_bump().encode_grouped_bar(
        categories=years, series_names=languages, values=scores
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_bump.svg")

    print("wrote examples/out_bump.bmp, .png, and .svg")
