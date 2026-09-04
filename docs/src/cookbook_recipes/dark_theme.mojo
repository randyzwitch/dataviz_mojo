"""Recolor every structural piece of a chart -- background, axis lines,
gridlines, and text -- for a dark-background dashboard tile, not just
the mark itself.
"""
from canvas.color import Color
from dataviz.plot import Plot, save
from dataviz.colors import DODGERBLUE
from dataviz.theme import Theme


def main() raises:
    var days: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
    var active_users: List[Float64] = [
        820.0,
        910.0,
        875.0,
        1040.0,
        1180.0,
        1120.0,
        1260.0,
    ]

    var plot = (
        Plot()
        .mark_line()
        .encode(x=days, y=active_users)
        .labels(title="Daily Active Users", x_title="Day", y_title="Users")
        .theme(
            Theme(
                background=Color(30, 32, 38),
                axis_color=Color(150, 152, 160),
                gridline_color=Color(55, 57, 64),
                text_color=Color(225, 226, 230),
                mark_color=DODGERBLUE,
            )
        )
    )
    save(plot, "docs/src/examples/out_dark_theme.svg")
