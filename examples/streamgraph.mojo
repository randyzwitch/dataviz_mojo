"""Demo: a streamgraph -- Mark.STREAMGRAPH, Mark.STACKED_BAR's running-total stack floated centered around zero instead of sitting on
a fixed baseline, drawn as flowing bands instead of discrete rects
(Plot.encode_grouped_bar(), the exact same categories/series_names/
values shape grouped_bar()/stacked_bar()/bump() all take -- see
streamgraph.mojo's docstring for the per-category centered-
baseline math). Reuses _draw_categorical_axis_frame unchanged. Built
via dataviz_mojo.streamgraph() -- see examples/scatter.mojo's docstring for what that trades away.

Music genre listening volume over a few years -- the classic
streamgraph use: several categories' share ebbing and flowing
over time, read as a "river" rather than a stack of bars.

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
from dataviz_mojo import streamgraph
from dataviz_mojo.theme import Theme


def main() raises:
    var years: List[String] = ["2020", "2021", "2022", "2023", "2024"]
    var genres: List[String] = ["Pop", "Rock", "Jazz"]
    var listens: List[List[Float64]] = [
        [30.0, 40.0, 55.0, 60.0, 50.0],
        [45.0, 35.0, 30.0, 25.0, 20.0],
        [10.0, 15.0, 12.0, 18.0, 25.0],
    ]

    var c = streamgraph(years, genres, listens)
    write_bmp(c, "examples/out_streamgraph.bmp")
    write_png(c, "examples/out_streamgraph.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_streamgraph().encode_grouped_bar(
        categories=years, series_names=genres, values=listens
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_streamgraph.svg")

    print("wrote examples/out_streamgraph.bmp, .png, and .svg")
