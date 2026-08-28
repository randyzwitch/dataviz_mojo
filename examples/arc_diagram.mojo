"""Demo: an arc diagram -- Mark.ARC_DIAGRAM, Mark.CHORD's edge
list (Plot.encode_chord()) drawn as nodes on one line connected by
semicircular arcs instead of a circular ribbon diagram -- see
arc_diagram.mojo's docstring for the naming-collision note versus
this package's Mark.ARC (pie/donut wedges). Built via
dataviz_mojo.arc_diagram() -- see examples/scatter.mojo's docstring for what that trades away.

Character co-occurrence in a handful of scenes -- the arc diagram's classic use (a network small enough to read as one open row of
nodes, unlike Mark.CHORD's circular layout, which reads better
once there are enough nodes to fill a ring).
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import arc_diagram
from dataviz_mojo.theme import Theme


def main() raises:
    var from_characters: List[String] = ["Alice", "Bob", "Alice", "Carol", "Dave"]
    var to_characters: List[String] = ["Bob", "Carol", "Carol", "Dave", "Eve"]
    var scenes_together: List[Float64] = [8.0, 5.0, 3.0, 6.0, 4.0]

    var c = arc_diagram(from_characters, to_characters, scenes_together)
    write_bmp(c, "examples/out_arc_diagram.bmp")
    write_png(c, "examples/out_arc_diagram.png")

    var svg_plot = Plot().mark_arc_diagram().encode_chord(
        from_categories=from_characters, to_categories=to_characters, values=scenes_together
    ).theme(Theme())
    var svg = render_svg(svg_plot)
    write_svg(svg, "examples/out_arc_diagram.svg")
