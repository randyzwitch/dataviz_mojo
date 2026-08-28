"""Demo: an effect scatter -- Mark.EFFECT_SCATTER, a scatter plot with
a halo drawn under each point, the static equivalent of ECharts' animated-ripple effect scatter (Plot.mark_effect_scatter().encode(),
Mark.POINT's encode() unchanged -- see that mark's docstring
in mark.mojo for why a raster/SVG renderer approximates the animation
this way). Built via dataviz_mojo.effect_scatter() -- see examples/
scatter.mojo's docstring for what that trades away.

A handful of highlighted store locations -- the classic effect-scatter
use: drawing the eye to specific points on a map or chart, the halo
doing statically what ECharts' ripple animation does over time.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import effect_scatter
from dataviz_mojo.theme import Theme


def main() raises:
    var longitude: List[Float64] = [10.0, 25.0, 40.0, 60.0, 80.0]
    var latitude: List[Float64] = [15.0, 40.0, 20.0, 55.0, 30.0]

    var c = effect_scatter(longitude, latitude)
    save(c, "examples/out_effect_scatter.svg")
    save(c, "examples/out_effect_scatter.bmp")
    save(c, "examples/out_effect_scatter.png")
