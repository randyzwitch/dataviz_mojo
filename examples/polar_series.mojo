"""Demo: a multi-series polar-coordinate line plot -- Mark.POLAR over
Plot.encode_polar_series() (a shared angle domain plus one or more
named series, sharing one radius scale and a legend -- the multi-
series generalization of encode_polar(), the same relationship pie()/
donut() have to Mark.ARC). Built via dataviz_mojo.polar_series() --
see examples/scatter.mojo's docstring for what that trades away.

Average monthly temperature, Miami vs. Phoenix -- one angle per month
evenly spaced around the circle (the same "clock face" 12-month
reading examples/polarbar.mojo's rainfall example uses), two named
series sharing one radius scale so the two cities' seasonal shapes
are directly comparable at a glance: Miami's shallower curve
(consistently warm) against Phoenix's deeper one (a hot summer
peak, a cooler winter dip).
"""

from std.math import pi

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import polar_series
from dataviz_mojo.theme import Theme


def main() raises:
    var angle = List[Float64]()
    for i in range(12):
        angle.append(2.0 * pi * Float64(i) / 12.0)

    var names: List[String] = ["Miami", "Phoenix"]
    var miami: List[Float64] = [68.0, 69.0, 72.0, 76.0, 80.0, 83.0, 84.0, 85.0, 84.0, 80.0, 74.0, 69.0]
    var phoenix: List[Float64] = [57.0, 61.0, 66.0, 75.0, 84.0, 95.0, 97.0, 95.0, 90.0, 78.0, 65.0, 56.0]
    var values: List[List[Float64]] = [miami.copy(), phoenix.copy()]

    var c = polar_series(angle, names, values)
    write_bmp(c, "examples/out_polar_series.bmp")
    write_png(c, "examples/out_polar_series.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_polar().encode_polar_series(
        angle=angle, series_names=names, series_values=values
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_polar_series.svg")
