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
"""

from dataviz_mojo.plot import save
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
    save(c, "examples/out_streamgraph.svg")
    save(c, "examples/out_streamgraph.bmp")
    save(c, "examples/out_streamgraph.png")
