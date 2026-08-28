"""Demo: a reference line annotation -- Plot.annotate_line(), ECharts' markLine (a fixed value only, not its "average"/"max"/"min" auto-
computed modes -- see that method's docstring). Draws a solid
horizontal line at a given y value across the full plot width, with an
optional right-aligned label, in Theme.annotation_color. Only meaningful
on a mark with a genuine continuous y-axis (Mark.BAR here) -- see
annotate_line()'s docstring for the full list and why not every
mark type supports it yet.

Monthly revenue against a target -- a real editorial-chart convention
(a reference line reads as "how are we doing against a fixed goal,"
not something a legend/tooltip is needed to explain), built on the
same data grouped_bar()'s example uses for a single region.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/pie.mojo's docstring for why, and for why
the docs page only shows the quickplot call above. Built by hand (not
a one-call quickplot -- annotate_line() isn't exposed on quickplot
functions, a deliberate scope cut; see that method's docstring)
via Plot() directly, the same way render_layers()/render_facets()
already have to be.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from canvas_mojo.buffer import Canvas


def main() raises:
    var months: List[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
    var revenue: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0]

    var plot = Plot().mark_bar().encode_categorical(x=months, y=revenue).labels(
        title="Monthly Revenue", subtitle="Actual vs. target, $M"
    ).annotate_line(60.0, label="target").annotate_line(51.5, label="average")

    var c = Canvas(640, 420)
    render(c, plot)
    write_bmp(c, "examples/out_annotate_line.bmp")
    write_png(c, "examples/out_annotate_line.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=months, y=revenue)
        .labels(title="Monthly Revenue", subtitle="Actual vs. target, $M")
        .annotate_line(60.0, label="target")
        .annotate_line(51.5, label="average")
        .theme(Theme())
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_annotate_line.svg")

    print("wrote examples/out_annotate_line.bmp, .png, and .svg")
