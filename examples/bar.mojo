"""Demo: a bar chart -- Mark.BAR, a categorical x-axis (OrdinalScale)
and a y-axis that always includes a zero baseline. Includes one
negative value to show bars extending below the baseline correctly,
not just the all-positive case. Built via dataviz_mojo.bar()
-- see examples/scatter.mojo's docstring for what that trades
away.

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
from dataviz_mojo import bar
from dataviz_mojo.colors import SEAGREEN
from dataviz_mojo.theme import Theme


def main() raises:
    var categories: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var values: List[Float64] = [12.0, 19.0, 8.0, 15.0, 22.0, -4.0, 6.0]

    var c = bar(categories, values, theme=Theme(mark_color=SEAGREEN))

    write_bmp(c, "examples/out_bar.bmp")
    write_png(c, "examples/out_bar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_bar().encode_categorical(x=categories, y=values).theme(
        Theme(mark_color=SEAGREEN)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_bar.svg")

    print("wrote examples/out_bar.bmp, .png, and .svg")
