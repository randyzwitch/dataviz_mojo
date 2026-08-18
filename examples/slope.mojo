"""Demo: a slope chart -- Mark.LINE with exactly two (x, y) points,
one line showing a single value's change between two points in time.
No new dataviz code: this is exactly the same LINE mark examples/
line.mojo draws, at the specific two-point data shape a slope chart
always is -- already fully supported, so this example exists to
demonstrate and hand-verify the pattern, not a new feature. Built via
dataviz_mojo.line() -- see examples/scatter.mojo's own
docstring for what that trades away.

Honest limitation, not silently glossed over: `Mark.LINE`'s x-axis is
continuous (`encode()`, not `encode_categorical()`), so the two x
positions here (0.0 and 1.0) get numeric tick labels ("0", "1"), not
the "Before"/"After"-style category labels a slope chart's own x-axis
conventionally shows -- that needs categorical-x support on Mark.LINE,
not built yet (see the wiki's Backlog). A real slope chart also
usually compares *several* entities' own slopes on shared axes at
once, which needs the multi-series layering this whole phase's plan
builds next (see the wiki's Changelog, its own Phase 1 entry) -- this
example is deliberately the single-series, numeric-axis case that's
already possible today, not a claim that the full chart type is done.

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why,
and for why the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.color import Color
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import line
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    # x=0.0 ("2023"), x=1.0 ("2024") -- revenue, in millions.
    var x: List[Float64] = [0.0, 1.0]
    var revenue: List[Float64] = [42.0, 61.0]

    var c = line(
        x,
        revenue,
        theme=Theme(
            mark_color=Color(30, 140, 90),
            line_width=3.0,
            show_gridlines=False,
            scale=Float64(_SUPERSAMPLE),
        ),
        width=320 * _SUPERSAMPLE,
        height=420 * _SUPERSAMPLE,
    )
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_slope.bmp")
    write_png(out, "examples/out_slope.png")

    var svg = SvgCanvas(320, 420)
    var svg_plot = Plot().mark_line().encode(x=x, y=revenue).theme(
        Theme(mark_color=Color(30, 140, 90), line_width=3.0, show_gridlines=False)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_slope.svg")

    print("wrote examples/out_slope.bmp, .png, and .svg")
