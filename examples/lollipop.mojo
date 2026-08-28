"""Demo: a lollipop chart -- Mark.LOLLIPOP, exactly Mark.BAR's categorical x-axis / zero-baseline y-axis (encode_categorical(), the
identical data shape a bar chart uses -- see plot.mojo's mark_lollipop() docstring), but each category draws a thin stem plus a
point at its value instead of a filled rect. A lollipop chart
reads well when there are enough categories that a full bar's width would start to feel heavy -- shown here with ten. Built via
dataviz_mojo.lollipop() -- see examples/scatter.mojo's docstring for what that trades away.
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import lollipop
from dataviz_mojo.colors import TEAL
from dataviz_mojo.theme import Theme


def main() raises:
    var countries: List[String] = [
        "USA", "China", "Japan", "Germany", "India",
        "UK", "France", "Italy", "Brazil", "Canada",
    ]
    var gdp: List[Float64] = [27.4, 17.8, 4.2, 4.1, 3.7, 3.3, 3.0, 2.2, 2.1, 2.1]

    var c = lollipop(countries, gdp, theme=Theme(mark_color=TEAL))
    write_bmp(c, "examples/out_lollipop.bmp")
    write_png(c, "examples/out_lollipop.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_lollipop().encode_categorical(x=countries, y=gdp).theme(
        Theme(mark_color=TEAL)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_lollipop.svg")
