"""Demo: a funnel chart -- Mark.FUNNEL, one tapering trapezoid per
category, drawn largest-value-first top to bottom (Plot.
encode_categorical(), the same category+value shape bar()/pie() take
-- see funnel.mojo's docstring for the sort/taper rules). No x/y
axis frame at all, the same as pie()'s Mark.ARC. Built via
dataviz_mojo.funnel() -- see examples/scatter.mojo's docstring
for what that trades away.

A marketing conversion funnel -- the classic funnel-chart use: how a
count shrinks stage by stage (impressions to clicks to orders).
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import funnel
from dataviz_mojo.theme import Theme


def main() raises:
    var stages: List[String] = ["Impressions", "Clicks", "Add to Cart", "Orders"]
    var counts: List[Float64] = [10000.0, 3200.0, 950.0, 400.0]

    var c = funnel(stages, counts)
    write_bmp(c, "examples/out_funnel.bmp")
    write_png(c, "examples/out_funnel.png")

    var svg_plot = Plot().mark_funnel().encode_categorical(x=stages, y=counts).theme(Theme())
    var svg = render_svg(svg_plot)
    write_svg(svg, "examples/out_funnel.svg")
