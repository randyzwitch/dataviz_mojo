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
"""

from dataviz_mojo.plot import save
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
    save(c, "examples/out_corrplot.svg")
    save(c, "examples/out_corrplot.bmp")
    save(c, "examples/out_corrplot.png")
