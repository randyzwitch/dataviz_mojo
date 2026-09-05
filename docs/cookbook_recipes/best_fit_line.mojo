# title: Best-Fit Trend Line
"""Overlay a computed best-fit line directly over a scatter plot with
`Plot.annotate_best_fit()` -- no manual regression math and no second
layer needed.
"""
from dataviz.plot import Plot, save
from dataviz.colors import CORNFLOWERBLUE
from dataviz.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .annotate_best_fit(show_equation=True, show_r_squared=True)
        .theme(Theme(mark_color=CORNFLOWERBLUE))
        .labels(
            title="Response Time vs. Load",
            subtitle="With an ordinary-least-squares best-fit line",
        )
    )
    save(plot, "docs/src/examples/out_best_fit_line.svg")
