# title: Isolines Over a Filled Field
"""Layer a `tricontour()` over a `tricontourf()` of the same samples
with `render_layers()` -- filled bands carry the color scale, isolines
say where the levels are.

Filled bands alone leave the reader estimating a value from a color;
isolines alone leave them working out which side of a line is higher.
Drawn together, each fixes the other's weakness, which is why matplotlib
draws both onto one axes. Both marks take the samples' own padded extent
as their frame, so the shared domain is each one's own and the isolines
land exactly where the standalone chart puts them.
"""
from std.math import cos, sin

from dataviz.plot import Plot, save_layers
from dataviz.theme import Theme
from dataviz.colormaps import viridis


def main() raises:
    # A deterministic scatter of samples over a smooth field.
    var x = List[Float64]()
    var y = List[Float64]()
    var z = List[Float64]()
    var seed = 12345
    for _ in range(120):
        seed = (seed * 1103515245 + 12345) % 2147483648
        var px = Float64(seed % 1000) / 100.0
        seed = (seed * 1103515245 + 12345) % 2147483648
        var py = Float64(seed % 1000) / 100.0
        x.append(px)
        y.append(py)
        z.append(sin(px) * cos(py))

    var field = (
        Plot()
        .mark_tricontourf(levels=9)
        .encode_tricontour(x=x, y=y, z=z)
        .theme(Theme(color_ramp=viridis()))
        .labels(title="Sampled field, filled bands with isolines")
        .size(640, 440)
    )
    var isolines = (
        Plot()
        .mark_tricontour(levels=9)
        .encode_tricontour(x=x, y=y, z=z)
        .theme(Theme(color_ramp=viridis(), line_width=1.0))
        .size(640, 440)
    )

    var plots: List[Plot] = [field^, isolines^]
    save_layers(plots, "docs/src/examples/out_isolines_over_a_field.svg")
