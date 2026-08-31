"""Draw error-bar whiskers on a line chart -- a confidence band per
measurement, connected by the trend line itself, instead of a bare
scatter of uncertain points.
"""
from dataviz_mojo.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [10.0, 14.0, 11.0, 18.0, 15.0]
    var err: List[Float64] = [1.5, 2.0, 0.5, 3.0, 1.0]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y, y_err=err)
        .labels(title="Measurements Over Time", subtitle="With error bars on each point")
    )
    save(plot, "docs/src/examples/out_error_bars_on_line.svg")
