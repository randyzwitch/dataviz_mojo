"""Demo: a bar chart -- Mark.BAR, a categorical x-axis (OrdinalScale)
and a y-axis that always includes a zero baseline. Includes one
negative value to show bars extending below the baseline correctly,
not just the all-positive case. Built via dataviz_mojo.bar()
-- see examples/scatter.mojo's docstring for what that trades
away.

A second chart below builds a genuinely *diverging* bar chart on top
of that same call -- Theme.color_by_sign, coloring each bar by
whether its value is negative (mark_color_negative) or not
(mark_color) instead of one flat mark_color, so the sign reads at a
glance rather than only from which direction the bar points. Bars
already extend below the zero baseline for negative values with no
changes needed, per the chart above; color_by_sign is the one further
thing a diverging bar chart adds. Both quickplot calls sit next to
each other, with each chart's own write_bmp/png/svg calls held until
after both -- see scripts/gen_example_docs.mojo's own PageSection
docstring for why that ordering matters (each call's docs snippet
stops the moment its own chart's data+call is done, so nothing from
the other chart's own I/O block leaks into it).
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

    # Diverging bars (color_by_sign)
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
    var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

    var c_diverging = bar(quarters, net_change, theme=Theme(color_by_sign=True))

    write_bmp(c, "examples/out_bar.bmp")
    write_png(c, "examples/out_bar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_bar().encode_categorical(x=categories, y=values).theme(
        Theme(mark_color=SEAGREEN)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_bar.svg")

    write_bmp(c_diverging, "examples/out_bar_diverging.bmp")
    write_png(c_diverging, "examples/out_bar_diverging.png")

    var svg_diverging = SvgCanvas(640, 420)
    var svg_plot_diverging = Plot().mark_bar().encode_categorical(x=quarters, y=net_change).theme(
        Theme(color_by_sign=True)
    )
    render_svg(svg_diverging, svg_plot_diverging)
    write_svg(svg_diverging, "examples/out_bar_diverging.svg")
