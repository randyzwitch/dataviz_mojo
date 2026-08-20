"""Demo: a sunburst chart -- Mark.SUNBURST, a hierarchy (Plot.encode_
hierarchy(), a flattened id/parent_id/value tree -- see sunburst.mojo's
own docstring) drawn as concentric ring sectors, one ring per depth
level, each node's own angular span proportional to its own share of
its parent's own total. Built via dataviz_mojo.sunburst() -- see
examples/scatter.mojo's own docstring for what that trades away.

Disk usage by folder -- the sunburst chart's own classic use (a
directory tree, size = bytes), two top-level folders each broken down
into their own subfolders.

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
from dataviz_mojo import sunburst
from dataviz_mojo.theme import Theme


def main() raises:
    var ids: List[String] = ["root", "src", "docs", "main.py", "utils.py", "guide.md", "api.md"]
    var parent_ids: List[String] = ["", "root", "root", "src", "src", "docs", "docs"]
    var sizes: List[Float64] = [0.0, 0.0, 0.0, 45.0, 20.0, 12.0, 8.0]

    var c = sunburst(ids, parent_ids, sizes)
    write_bmp(c, "examples/out_sunburst.bmp")
    write_png(c, "examples/out_sunburst.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_sunburst().encode_hierarchy(ids=ids, parent_ids=parent_ids, values=sizes).theme(
        Theme()
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_sunburst.svg")

    print("wrote examples/out_sunburst.bmp, .png, and .svg")
