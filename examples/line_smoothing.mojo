"""Demo: Theme.line_smoothing -- Mark.LINE optionally curved through
its own data points via a Catmull-Rom-derived spline instead of
straight point-to-point segments (Plot().mark_line().theme(Theme(
line_smoothing=...)); see that field's own docstring and plot.mojo's
_build_line_path for the control-point formula). Default 0.0 (plain
straight segments, byte-identical to every render from before this
feature existed); 1.0 is the full, standard Catmull-Rom curve.

The same eight-month, deliberately jagged dataset rendered twice, side
by side via render_facets() -- smoothing=0.0 on the left, smoothing=1.0
on the right -- so the difference is a direct visual comparison, not
two separate files a viewer has to hold in memory against each other.

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why
every new example does this from here on.

Run with:
    pixi run example
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_facets, render_facets_svg
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var months: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var values: List[Float64] = [20.0, 45.0, 30.0, 60.0, 40.0, 70.0, 50.0, 65.0]

    var s = Float64(_SUPERSAMPLE)
    var raster_plots = List[Plot]()
    raster_plots.append(Plot().mark_line().encode(x=months, y=values).theme(Theme(scale=s)))
    raster_plots.append(
        Plot().mark_line().encode(x=months, y=values).theme(Theme(line_smoothing=1.0, scale=s))
    )
    var c = Canvas(800 * _SUPERSAMPLE, 300 * _SUPERSAMPLE, Color(255, 255, 255))
    render_facets(c, raster_plots, cols=2)
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_line_smoothing.bmp")

    var svg_plots = List[Plot]()
    svg_plots.append(Plot().mark_line().encode(x=months, y=values))
    svg_plots.append(Plot().mark_line().encode(x=months, y=values).theme(Theme(line_smoothing=1.0)))
    var svg = SvgCanvas(800, 300)
    render_facets_svg(svg, svg_plots, cols=2)
    write_svg(svg, "examples/out_line_smoothing.svg")

    print("wrote examples/out_line_smoothing.bmp and out_line_smoothing.svg")
