"""Demo: a parallel-coordinates chart -- Mark.PARALLEL, one evenly
spaced vertical axis per dimension (Plot.encode_parallel(), each
independently scaled to its column's [min, max]), one polyline
per named row connecting its per-dimension positions. Built via
dataviz_mojo.parallel() -- see examples/scatter.mojo's docstring
for what that trades away.

Vehicle attribute comparison -- ECharts.jl's parallel() example,
the chart type's classic use (several wildly-differently-scaled
numeric dimensions -- horsepower, MPG, weight, 0-60 time, price -- laid
out so every vehicle's tradeoffs read as one connected shape).
"""

from dataviz_mojo.plot import save
from dataviz_mojo import parallel
from dataviz_mojo.theme import Theme


def main() raises:
    var dims: List[String] = ["Horsepower", "MPG", "Weight (100 lbs)", "0-60 (sec)", "Price ($k)"]
    var row_names: List[String] = ["Sedan", "SUV", "Sports Car"]
    var data: List[List[Float64]] = [
        [180.0, 32.0, 30.0, 8.5, 28.0],
        [280.0, 22.0, 45.0, 6.5, 42.0],
        [450.0, 16.0, 34.0, 3.5, 85.0],
    ]

    var c = parallel(data, dims, row_names)
    save(c, "examples/out_parallel.svg")
    save(c, "examples/out_parallel.bmp")
    save(c, "examples/out_parallel.png")
