"""Demo: a heatmap -- Mark.HEATMAP, one colored grid cell per (x, y)
category pair, colored by a continuous value through Theme.color_
scale_low/color_scale_high (Plot.encode_heatmap(), one row per cell --
see that method's docstring). Two categorical axes and no continuous
one at all (shared with Mark.CORRPLOT/PUNCHCARD); its axis-frame core
(_draw_grid_axis_frame, heatmap.mojo) tiles cells edge-to-edge instead
of Mark.BAR's separated bands. Built via dataviz_mojo.heatmap() --
see examples/scatter.mojo's docstring for what that trades away.

A day-of-week x hour-of-day activity grid -- the classic heatmap use
(a correlation matrix or a calendar would be the same shape, just
different category labels).

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import heatmap
from dataviz_mojo.theme import Theme


def main() raises:
    var days: List[String] = ["Mon", "Mon", "Mon", "Tue", "Tue", "Tue", "Wed", "Wed", "Wed"]
    var hours: List[String] = ["9am", "1pm", "5pm", "9am", "1pm", "5pm", "9am", "1pm", "5pm"]
    var activity: List[Float64] = [3.0, 8.0, 5.0, 4.0, 9.0, 6.0, 2.0, 7.0, 10.0]

    var c = heatmap(days, hours, activity)
    write_bmp(c, "examples/out_heatmap.bmp")
    write_png(c, "examples/out_heatmap.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_heatmap().encode_heatmap(x=days, y=hours, value=activity).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_heatmap.svg")

    print("wrote examples/out_heatmap.bmp, .png, and .svg")
