"""Demo: a treemap -- Mark.TREEMAP, a hierarchy (Plot.encode_
hierarchy(), the same flattened id/parent_id/value shape Mark.SUNBURST/
TREE use -- see treemap.mojo's docstring) laid out as nested,
area-proportional rectangles via slice-and-dice. Built via
dataviz_mojo.treemap() -- see examples/scatter.mojo's docstring
for what that trades away.

Disk usage by folder -- the exact same data Mark.SUNBURST's example uses, so the two chart types' different readings of the
identical hierarchy (radial rings vs. nested rectangles) are easy to
compare directly.

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
from dataviz_mojo import treemap
from dataviz_mojo.theme import Theme


def main() raises:
    var ids: List[String] = ["root", "src", "docs", "main.py", "utils.py", "guide.md", "api.md"]
    var parent_ids: List[String] = ["", "root", "root", "src", "src", "docs", "docs"]
    var sizes: List[Float64] = [0.0, 0.0, 0.0, 45.0, 20.0, 12.0, 8.0]

    var c = treemap(ids, parent_ids, sizes)
    write_bmp(c, "examples/out_treemap.bmp")
    write_png(c, "examples/out_treemap.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_treemap().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=sizes).theme(
        Theme()
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_treemap.svg")

    print("wrote examples/out_treemap.bmp, .png, and .svg")
