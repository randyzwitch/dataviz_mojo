# title: Smoothed Line
"""Curve a line (or an area's top edge) through its data points instead
of drawing straight segments.
"""
from dataviz import line
from dataviz.plot import save
from dataviz.colors import CORNFLOWERBLUE
from dataviz.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [12.0, 19.0, 14.0, 25.0, 18.0, 29.0, 22.0, 31.0]

    var c = line(
        x,
        y,
        theme=Theme(mark_color=CORNFLOWERBLUE, line_smoothing=1.0),
    )
    save(c, "docs/src/examples/out_line_smoothed.svg")
