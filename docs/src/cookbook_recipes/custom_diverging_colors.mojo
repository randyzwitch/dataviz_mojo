"""Pick a diverging bar chart's own positive/negative colors instead of
the default red -- `color_by_sign` alone always pairs `mark_color`
with `mark_color_negative`, so recoloring one to match a report's own
palette means overriding both together.
"""
from dataviz import bar
from dataviz.plot import save
from dataviz.colors import SEAGREEN, GOLDENROD
from dataviz.theme import Theme


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
    var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

    var plot = bar(
        quarters,
        net_change,
        theme=Theme(
            color_by_sign=True,
            mark_color=SEAGREEN,
            mark_color_negative=GOLDENROD,
        ),
    )
    save(plot, "docs/src/examples/out_custom_diverging_colors.svg")
