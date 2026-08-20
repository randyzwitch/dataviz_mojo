"""Demo: a Sankey diagram -- Mark.SANKEY, Mark.CHORD's own edge list
(Plot.encode_chord()) drawn as nodes in left-to-right columns (a
node's own column is the longest path reaching it from any source --
see sankey.mojo's own docstring) connected by proportionally sized
flow ribbons. Built via dataviz_mojo.sankey() -- see
examples/scatter.mojo's own docstring for what that trades away.

Energy flow from sources to end uses -- the Sankey diagram's own
classic use case.

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
from dataviz_mojo import sankey
from dataviz_mojo.theme import Theme


def main() raises:
    var from_stage: List[String] = ["Coal", "Gas", "Coal", "Gas", "Electricity", "Electricity"]
    var to_stage: List[String] = ["Electricity", "Electricity", "Industry", "Industry", "Residential", "Industry"]
    var energy: List[Float64] = [30.0, 20.0, 15.0, 10.0, 25.0, 20.0]

    var c = sankey(from_stage, to_stage, energy)
    write_bmp(c, "examples/out_sankey.bmp")
    write_png(c, "examples/out_sankey.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_sankey().encode_chord(
        from_categories=from_stage, to_categories=to_stage, values=energy
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_sankey.svg")

    print("wrote examples/out_sankey.bmp, .png, and .svg")
