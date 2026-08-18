"""Demo: a gantt/span chart -- Mark.GANTT, one horizontal bar per
category from a start value to an end value (Plot.encode_gantt(), a
category plus a range -- see that method's own docstring). The first
mark whose categories run along the *y*-axis instead of the x-axis
(`_draw_horizontal_categorical_axis_frame`, the mirror image of every
other categorical mark here's own vertical axis frame -- see its own
docstring for why this needed a dedicated function rather than
generalizing the vertical one). Built via dataviz_mojo.
gantt() -- see examples/scatter.mojo's own docstring for what that
trades away.

A five-task project schedule (day numbers, not calendar dates -- this
package has no Date/Time type; see encode_gantt()'s own docstring for
why that's a deliberate, not a missing, choice), with overlapping spans
(Testing starts before Development finishes) -- the kind of at-a-glance
overlap a gantt chart is for.

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why,
and for why the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import gantt
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var tasks: List[String] = ["Design", "Development", "Testing", "Documentation", "Launch"]
    var start: List[Float64] = [0.0, 5.0, 20.0, 15.0, 28.0]
    var end: List[Float64] = [8.0, 25.0, 28.0, 27.0, 30.0]

    var c = gantt(
        tasks,
        start,
        end,
        theme=Theme(scale=Float64(_SUPERSAMPLE)),
        width=640 * _SUPERSAMPLE,
        height=420 * _SUPERSAMPLE,
    )
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_gantt.bmp")
    write_png(out, "examples/out_gantt.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_gantt().encode_gantt(tasks, start, end).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_gantt.svg")

    print("wrote examples/out_gantt.bmp, .png, and .svg")
