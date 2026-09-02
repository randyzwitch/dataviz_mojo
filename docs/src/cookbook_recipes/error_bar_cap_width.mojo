"""Narrow an error bar's own end caps so closely spaced points don't
run their whiskers into each other -- the default cap width reads
fine with room to spare between points, but starts to visually
collide once points sit close together on the x-axis.
"""
from dataviz.plot import Plot, save
from dataviz.theme import Theme

def main() raises:
    var x: List[Float64] = [1.0, 1.4, 1.8, 2.2, 2.6, 3.0, 3.4, 3.8]
    var y: List[Float64] = [10.0, 11.5, 10.8, 13.0, 12.2, 14.5, 13.8, 15.0]
    var err: List[Float64] = [0.8, 1.0, 0.6, 1.2, 0.9, 1.1, 0.7, 1.0]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, y_err=err)
        .labels(title="Closely Spaced Measurements", subtitle="Narrower error-bar caps avoid visual collisions")
        .theme(Theme(error_bar_cap_width=2.0))
    )
    save(plot, "docs/src/examples/out_error_bar_cap_width.svg")
