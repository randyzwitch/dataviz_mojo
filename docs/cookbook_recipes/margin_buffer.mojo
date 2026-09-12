"""Pad the dynamically measured left margin with `margin_buffer`."""
from dataviz.plot import Plot, save
from dataviz.core.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var revenue: List[Float64] = [
        1250000.0,
        1480000.0,
        1390000.0,
        1620000.0,
        1750000.0,
        1690000.0,
    ]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=revenue)
        .labels(
            title="Monthly Revenue",
            subtitle="Extra padding between wide tick labels and the axis line",
        )
        .theme(Theme(margin_buffer=20))
    )
    save(plot, "docs/src/examples/out_margin_buffer.svg")
