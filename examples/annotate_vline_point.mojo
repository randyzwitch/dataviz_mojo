"""Demo: a vertical reference line and a labeled point marker --
Plot.annotate_vline()/Plot.annotate_point(), the x-axis mirror of
annotate_line() and ECharts' markPoint (a fixed coordinate only,
not its "max"/"min"/"average" auto-computed modes -- see each method's docstring). Narrower mark support than annotate_line()/
annotate_area(): only Mark.POINT/LINE/AREA/EFFECT_SCATTER, the marks
with a genuine continuous x-axis to place a vertical line or a point's x coordinate against.

A launch-day marker (annotate_vline) and a peak-value callout
(annotate_point) on the same response-time series examples/annotate_
area.mojo's docstring uses, so the two annotation demos read as a
matched pair.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/donut.mojo's docstring for why. Built by hand
(not a one-call quickplot -- neither method is exposed on quickplot
functions, the same deliberate scope cut examples/annotate_line.mojo's docstring explains) via Plot() directly.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render, render_svg
from canvas_mojo.buffer import Canvas


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var latency: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0, 70.0, 63.0]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=latency)
        .labels(title="Response Time (ms)", subtitle="With a launch marker and peak callout")
        .annotate_vline(4.0, label="launch")
        .annotate_point(7.0, 70.0, label="peak")
    )

    var c = Canvas(640, 420)
    render(c, plot)
    write_bmp(c, "examples/out_annotate_vline_point.bmp")
    write_png(c, "examples/out_annotate_vline_point.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=latency)
        .labels(title="Response Time (ms)", subtitle="With a launch marker and peak callout")
        .annotate_vline(4.0, label="launch")
        .annotate_point(7.0, 70.0, label="peak")
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_annotate_vline_point.svg")

    print("wrote examples/out_annotate_vline_point.bmp, .png, and .svg")
