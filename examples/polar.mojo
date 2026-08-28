"""Demo: a polar-coordinate line plot -- Mark.POLAR, (angle, radius)
pairs (Plot.encode_polar(), radians used exactly as given -- never
wrapped mod 2*pi) connected by one stroked polyline plus point
markers, drawn over a polar grid (concentric rings, angular spokes --
see polar.mojo's _draw_polar_grid docstring). Built via
dataviz_mojo.polar() -- see examples/scatter.mojo's docstring for
what that trades away.

A four-leaf rose curve -- ECharts.jl's polar() example, the polar
equation r = sin(2*theta) (each lobe traced as theta sweeps a half
turn; the sign flip on the negative half of each sine period is what
gives the curve its four separate leaves instead of two).
"""

from std.math import pi, sin

from dataviz_mojo.plot import save
from dataviz_mojo import polar
from dataviz_mojo.theme import Theme


def main() raises:
    var angle = List[Float64]()
    var radius = List[Float64]()
    var steps = 200
    for i in range(steps + 1):
        var theta = 2.0 * pi * Float64(i) / Float64(steps)
        var r = sin(2.0 * theta)
        # A negative r has no polar meaning on its own -- fold it into
        # the opposite direction (theta + pi) instead, the standard
        # way a signed polar radius is plotted, so the curve's negative lobes still draw rather than getting clipped by
        # encode_polar()'s non-negative-radius validation.
        if r < 0.0:
            angle.append(theta + pi)
            radius.append(-r)
        else:
            angle.append(theta)
            radius.append(r)

    var c = polar(angle, radius)
    save(c, "examples/out_polar.svg")
    save(c, "examples/out_polar.bmp")
    save(c, "examples/out_polar.png")
