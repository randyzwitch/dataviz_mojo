# title: Best-Fit Trend Line
"""Overlay a computed best-fit line as a second layer on top of a
scatter plot.
"""
from dataviz_mojo.plot import Plot, save_layers
from dataviz_mojo.colors import CORNFLOWERBLUE, TOMATO
from dataviz_mojo.theme import Theme

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

    # Ordinary least squares -- the standard closed-form slope/
    # intercept for a straight best-fit line through (x, y).
    var n = Float64(len(x))
    var sum_x = 0.0
    var sum_y = 0.0
    var sum_xy = 0.0
    var sum_xx = 0.0
    for i in range(len(x)):
        sum_x += x[i]
        sum_y += y[i]
        sum_xy += x[i] * y[i]
        sum_xx += x[i] * x[i]
    var slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
    var intercept = (sum_y - slope * sum_x) / n

    var fit_x: List[Float64] = [x[0], x[len(x) - 1]]
    var fit_y: List[Float64] = [slope * fit_x[0] + intercept, slope * fit_x[1] + intercept]

    var points = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .theme(Theme(mark_color=CORNFLOWERBLUE))
        .labels(title="Response Time vs. Load", subtitle="With an ordinary-least-squares best-fit line")
    )
    var trend = (
        Plot()
        .mark_line()
        .encode(x=fit_x, y=fit_y)
        .theme(Theme(mark_color=TOMATO, line_width=2.0))
    )
    var plots: List[Plot] = [points^, trend^]
    save_layers(plots, "docs/src/examples/out_layers_trend.svg")
