"""Demo: a box plot -- Mark.BOX, one box-and-whiskers per category
summarizing a whole distribution of raw values (Plot.encode_boxplot(),
a category + a *list* of values -- see that method's own docstring for
the quartile/whisker/outlier computation it does immediately, via
_box_stats()). Unlike Mark.BAR/LOLLIPOP/WATERFALL, the y-axis doesn't
force in a zero baseline -- a distribution's own spread has no inherent
reason to include zero (see _render_box's own docstring). Built via
dataviz_mojo.box() -- see examples/scatter.mojo's own
docstring for what that trades away.

Four groups' exam scores, each a real (not perfectly symmetric)
distribution, one of them (Group C) with a genuine low outlier -- the
kind of comparison a box plot is for: not each group's own single
summary number (a bar chart's job), but each group's own spread, and
whether any individual value falls unusually far from the rest.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/donut.mojo's own docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.color import Color
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import box
from dataviz_mojo.theme import Theme


def main() raises:
    var groups: List[String] = ["Group A", "Group B", "Group C", "Group D"]
    var scores: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0, 81.0, 83.0, 85.0, 88.0, 90.0],
        [60.0, 65.0, 68.0, 70.0, 72.0, 74.0, 77.0, 79.0],
        [55.0, 70.0, 73.0, 75.0, 76.0, 78.0, 80.0, 82.0, 20.0],
        [82.0, 84.0, 85.0, 86.0, 87.0, 88.0, 89.0, 91.0, 93.0],
    ]

    var c = box(groups, scores, theme=Theme(mark_color=Color(70, 110, 190)))
    write_bmp(c, "examples/out_box.bmp")
    write_png(c, "examples/out_box.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_box().encode_boxplot(groups, scores).theme(
        Theme(mark_color=Color(70, 110, 190))
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_box.svg")

    print("wrote examples/out_box.bmp, .png, and .svg")
