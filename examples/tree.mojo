"""Demo: a tree diagram -- Mark.TREE, a hierarchy (Plot.encode_
hierarchy(), the same flattened id/parent_id/value shape Mark.SUNBURST
uses -- see tree.mojo's docstring) drawn top-to-bottom as a
node-link diagram instead of Mark.SUNBURST's radial rings. Built
via dataviz_mojo.tree() -- see examples/scatter.mojo's docstring
for what that trades away.

An org chart -- the tree diagram's classic use, two departments
each with their reports.

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
from dataviz_mojo import tree
from dataviz_mojo.theme import Theme


def main() raises:
    var ids: List[String] = [
        "CEO", "Engineering", "Sales", "Backend", "Frontend", "Enterprise", "SMB",
    ]
    var parent_ids: List[String] = ["", "CEO", "CEO", "Engineering", "Engineering", "Sales", "Sales"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]

    var c = tree(ids, parent_ids, values)
    write_bmp(c, "examples/out_tree.bmp")
    write_png(c, "examples/out_tree.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_tree().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=values).theme(
        Theme()
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_tree.svg")

    print("wrote examples/out_tree.bmp, .png, and .svg")
