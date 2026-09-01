# title: Point Marker
"""Add a single labeled point at `(x, y)` -- a callout for one specific
data point, rather than a whole line/band spanning an axis.
"""
from dataviz.plot import Plot, save

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var latency: List[Float64] = [42.0, 48.0, 45.0, 61.0, 55.0, 58.0, 70.0, 63.0]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=latency)
        .labels(title="Response Time (ms)", subtitle="With a peak callout")
        .annotate_point(7.0, 70.0, label="peak")
    )
    save(plot, "docs/src/examples/out_annotate_point.svg")
