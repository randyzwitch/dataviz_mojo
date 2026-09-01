"""Draw an asymmetric error-bar whisker -- independent upper and lower
extents per point, instead of one shared half-width in each direction.
"""
from dataviz.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [10.0, 14.0, 11.0, 18.0, 15.0]
    var lower: List[Float64] = [1.0, 5.0, 0.5, 6.0, 1.0]
    var upper: List[Float64] = [4.0, 1.0, 3.0, 1.0, 4.0]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
        .labels(title="Measurements", subtitle="With asymmetric error bars")
    )
    save(plot, "docs/src/examples/out_error_bars_asymmetric.svg")
