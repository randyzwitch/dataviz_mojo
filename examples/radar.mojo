"""Demo: a radar/spider chart -- Mark.RADAR, one spoke per named
indicator (each its own max), one filled-and-stroked polygon per named
series (Plot.encode_radar() -- see that method's own docstring). Built
via dataviz_mojo.radar() -- see examples/scatter.mojo's own docstring
for what that trades away.

Two teams compared across five attributes -- ECharts.jl's own radar()
example, the chart type's own classic use (overlapping polygons make
each team's relative strengths across dimensions immediately visible).

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/donut.mojo's own docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import radar
from dataviz_mojo.theme import Theme


def main() raises:
    var indicators: List[String] = ["Attack", "Defense", "Speed", "Stamina", "Skill"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0, 100.0, 100.0]
    var series_names: List[String] = ["Team A", "Team B"]
    var series_values: List[List[Float64]] = [
        [90.0, 60.0, 80.0, 70.0, 85.0],
        [65.0, 85.0, 55.0, 90.0, 60.0],
    ]

    var c = radar(indicators, max_values, series_names, series_values)
    write_bmp(c, "examples/out_radar.bmp")
    write_png(c, "examples/out_radar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_radar().encode_radar(
        indicators=indicators, max_values=max_values, series_names=series_names, series_values=series_values
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_radar.svg")

    print("wrote examples/out_radar.bmp, .png, and .svg")
