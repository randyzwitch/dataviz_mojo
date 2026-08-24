"""Demo: a waterfall chart -- Mark.WATERFALL, one floating bar per
category running from the previous category's cumulative total to
the next (Plot.encode_waterfall(), a category + a *signed delta* --
see that method's docstring for the running-total bookkeeping it
does immediately). Each plain delta bar is colored by its delta's
sign unconditionally (mark_color for an increase, mark_color_negative
for a decrease -- see Theme.mark_color_negative's docstring for
why this one mark colors by sign without needing Theme.color_by_sign,
unlike Mark.BAR), narrower than a total bar so the two read as
distinct at a glance, with a thin connector line between consecutive
bars at the pixel height where one bar's running total hands off
to the next. Built via dataviz_mojo.waterfall() -- see
examples/scatter.mojo's docstring for what that trades away.

A quarterly profit bridge: a starting-balance total, several line
items that add to or subtract from it, and an ending-balance total --
the classic start-then-deltas-then-end shape `encode_waterfall()`'s `is_total` parameter exists for (both totals draw full band width, in
Theme.waterfall_total_color, a third color distinct from the
rising/falling pair -- see that field's docstring for why). The
starting total's delta (50.0) *is* the starting balance itself
(still added to the running sum, just displayed 0 -> 50 instead of
floating); the ending total's delta is 0.0 (adds nothing further,
just displays 0 -> whatever the running sum already reached).

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
from dataviz_mojo import waterfall
from dataviz_mojo.theme import Theme


def main() raises:
    var stages: List[String] = ["Starting", "Revenue", "COGS", "Opex", "Tax", "One-off", "Ending"]
    var deltas: List[Float64] = [50.0, 32.0, -18.0, -12.0, -6.0, 4.0, 0.0]
    var is_total: List[Bool] = [True, False, False, False, False, False, True]

    var c = waterfall(stages, deltas, is_total=is_total)
    write_bmp(c, "examples/out_waterfall.bmp")
    write_png(c, "examples/out_waterfall.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_waterfall().encode_waterfall(stages, deltas, is_total).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_waterfall.svg")

    print("wrote examples/out_waterfall.bmp, .png, and .svg")
