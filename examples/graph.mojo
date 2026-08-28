"""Demo: a network graph -- Mark.GRAPH, Mark.CHORD's edge list
(Plot.encode_chord()) drawn as nodes evenly spaced around a circle,
connected by straight lines cutting across the interior -- a third
genuinely different layout from Mark.CHORD's ring-sectors-plus-
ribbons and Mark.ARC_DIAGRAM's nodes-on-a-line-plus-arcs. Built
via dataviz_mojo.graph() -- see examples/scatter.mojo's docstring
for what that trades away.

A small social network -- who's connected to whom, edge width reading
as connection strength.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import graph
from dataviz_mojo.theme import Theme


def main() raises:
    var from_people: List[String] = ["Alice", "Alice", "Bob", "Carol", "Dave"]
    var to_people: List[String] = ["Bob", "Carol", "Dave", "Dave", "Eve"]
    var connection_strength: List[Float64] = [8.0, 3.0, 5.0, 6.0, 4.0]

    var c = graph(from_people, to_people, connection_strength)
    write_bmp(c, "examples/out_graph.bmp")
    write_png(c, "examples/out_graph.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_graph().encode_chord(
        from_categories=from_people, to_categories=to_people, values=connection_strength
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_graph.svg")

    print("wrote examples/out_graph.bmp, .png, and .svg")
