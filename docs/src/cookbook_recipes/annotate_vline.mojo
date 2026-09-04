# title: Vertical Reference Line
"""Add a vertical reference line at `value` on the x-axis -- the mirror
image of a horizontal reference line, for marking a point in time or
position instead of a target value.
"""
from dataviz.plot import Plot, save


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var latency: List[Float64] = [
        42.0,
        48.0,
        45.0,
        61.0,
        55.0,
        58.0,
        70.0,
        63.0,
    ]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=latency)
        .labels(title="Response Time (ms)", subtitle="With a launch marker")
        .annotate_vline(4.0, label="launch")
    )
    save(plot, "docs/src/examples/out_annotate_vline.svg")
