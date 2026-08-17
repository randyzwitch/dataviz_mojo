"""Demo: render_layers -- multiple Plots composed on ONE shared coordinate
system (unlike render_facets, which gives each cell its OWN independent
domain; see plot.mojo's own render_layers docstring). Here a Mark.LINE
plot (actual revenue) and a Mark.POINT plot (forecast checkpoints) share
one x/y domain and one set of axes/gridlines -- the shared chrome (theme,
margins, axis styling) comes from the FIRST plot in the list, while each
individual plot keeps its own mark_color/line_width/point_radius. The
same goes for Plot.labels(): the chart title comes from the FIRST plot's
own .labels() call too, not each layer's own (one combined coordinate
system, so one shared title is the only reading that makes sense here --
contrast examples/facets.mojo's own per-cell titles).

The forecast checkpoints use Plot.encode(color_categories=...) too --
render_layers's own per-point encoding + legend support (dataviz_mojo/
ROADMAP.md's own "render_layers per-point encoding and legends" Done
entry): a Mark.POINT layer can use color/color_categories/size exactly
like a standalone Mark.POINT plot, drawing its own legend section --
here, each checkpoint colored by whether that month's actual revenue
met or missed its own forecast ("Ahead"/"Behind"), the same per-point
encoding a single-plot scatter already supports.

Honest limitations, not silently glossed over (see dataviz_mojo/ROADMAP.md's
own "Explicitly still open" section): only Mark.POINT/LINE/AREA can be
layered (not BAR/ARC, which have different domain shapes); no per-
*series* name/label concept yet for a "which layer is which" legend
built from several flat-colored layers (a separate feature from the
per-point encoding within one layer this example already uses).

Writes both a raster (.bmp, 3x supersampled) and a vector (.svg) file
from the same data -- see examples/donut.mojo's own docstring for why
every new chart-type example does this from here on.

Run with:
    pixi run example
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.resize import downsample
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_layers, render_layers_svg
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var months: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]
    var actual: List[Float64] = [42.0, 47.0, 45.0, 53.0, 58.0, 61.0]
    var forecast: List[Float64] = [40.0, 44.0, 48.0, 52.0, 56.0, 60.0]
    # "Ahead" where that month's actual revenue met or beat its own
    # forecast, "Behind" otherwise -- computed directly from the two
    # series above, not a separate hand-typed column, so it can never
    # drift out of sync with them.
    var status = List[String]()
    for i in range(len(actual)):
        status.append("Ahead" if actual[i] >= forecast[i] else "Behind")

    var c = Canvas(480 * _SUPERSAMPLE, 320 * _SUPERSAMPLE, Color(255, 255, 255))
    var raster_line = Plot().mark_line().encode(x=months, y=actual).labels(
        title="Actual vs. Forecast Revenue"
    ).theme(Theme(mark_color=Color(30, 110, 200), line_width=3.0, scale=Float64(_SUPERSAMPLE)))
    var raster_points = Plot().mark_point().encode(
        x=months, y=forecast, color_categories=status
    ).theme(Theme(point_radius=5.0, scale=Float64(_SUPERSAMPLE)))
    var raster_layers = List[Plot]()
    raster_layers.append(raster_line^)
    raster_layers.append(raster_points^)
    render_layers(c, raster_layers)
    var out = downsample(c, _SUPERSAMPLE)
    write_bmp(out, "examples/out_layers.bmp")

    var svg = SvgCanvas(480, 320)
    var svg_line = Plot().mark_line().encode(x=months, y=actual).labels(
        title="Actual vs. Forecast Revenue"
    ).theme(Theme(mark_color=Color(30, 110, 200), line_width=3.0))
    var svg_points = Plot().mark_point().encode(
        x=months, y=forecast, color_categories=status
    ).theme(Theme(point_radius=5.0))
    var svg_layers = List[Plot]()
    svg_layers.append(svg_line^)
    svg_layers.append(svg_points^)
    render_layers_svg(svg, svg_layers)
    write_svg(svg, "examples/out_layers.svg")

    print("wrote examples/out_layers.bmp and out_layers.svg")
