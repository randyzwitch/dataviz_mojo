"""Demo: a correlation plot -- Mark.CORRPLOT, one bubble per cell of a
square correlation matrix (Plot.encode_corrplot()), sized by
abs(correlation) and colored by its sign/strength through the same
continuous gradient Mark.HEATMAP uses. Built via dataviz_mojo.
corrplot() -- see examples/scatter.mojo's docstring for what that
trades away.

Pairwise correlations between a handful of car attributes -- ECharts.
jl's corrplot() classic use case (a real correlation matrix,
values invented here for a self-contained example rather than pulling
in a real dataset), upper-triangle layout with the diagonal dropped
(every self-correlation is trivially 1.0, rarely worth a bubble).

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/pie.mojo's docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import corrplot
from dataviz_mojo.theme import Theme


def main() raises:
    var variables: List[String] = ["Horsepower", "MPG", "Weight", "Price"]
    var matrix: List[List[Float64]] = [
        [1.0, -0.78, 0.66, 0.72],
        [-0.78, 1.0, -0.83, -0.55],
        [0.66, -0.83, 1.0, 0.48],
        [0.72, -0.55, 0.48, 1.0],
    ]

    var c = corrplot(variables, matrix, layout="upper", diag=False)
    write_bmp(c, "examples/out_corrplot.bmp")
    write_png(c, "examples/out_corrplot.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_corrplot(layout="upper", diag=False).encode_corrplot(
        variables=variables, matrix=matrix
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_corrplot.svg")

    print("wrote examples/out_corrplot.bmp, .png, and .svg")
