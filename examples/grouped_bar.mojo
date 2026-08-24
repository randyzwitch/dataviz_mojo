"""Demo: a grouped bar chart -- Mark.GROUPED_BAR, several bars side by
side per category instead of one (Plot().mark_grouped_bar().encode_
grouped_bar(categories, series_names, values); see that method's docstring for the values[series][category] data shape). Quarterly
revenue for three regions across four quarters -- the categorical
x-axis and zero-baseline y-axis are exactly Mark.BAR's own, shared via
_draw_categorical_axis_frame; what's new is each category's band
splitting into one sub-bar per series (default_categorical_palette(),
the same cycling convention Mark.POINT's categorical color encoding and
Mark.ARC's wedge coloring already use) plus a legend, reserved via
Theme.show_legend the same way Mark.POINT's categorical-color
legend is. Built via dataviz_mojo.grouped_bar() -- see
examples/scatter.mojo's docstring for what that trades away;
title=/x_title=/y_title= are quickplot's equivalent of Plot.
labels()'s three parameters.

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
from dataviz_mojo import grouped_bar
from dataviz_mojo.theme import Theme


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var series_names: List[String] = ["North", "South", "East"]
    var values: List[List[Float64]] = [
        [42.0, 48.0, 45.0, 61.0],
        [30.0, 35.0, 33.0, 40.0],
        [55.0, 50.0, 58.0, 66.0],
    ]

    var c = grouped_bar(
        quarters,
        series_names,
        values,
        title="Quarterly Revenue by Region",
        x_title="Quarter",
        y_title="Revenue ($M)",
    )
    write_bmp(c, "examples/out_grouped_bar.bmp")
    write_png(c, "examples/out_grouped_bar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(quarters, series_names, values)
        .labels(title="Quarterly Revenue by Region", x_title="Quarter", y_title="Revenue ($M)")
        .theme(Theme())
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_grouped_bar.svg")

    print("wrote examples/out_grouped_bar.bmp, .png, and .svg")
