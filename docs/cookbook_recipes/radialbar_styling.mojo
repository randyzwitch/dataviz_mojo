"""Darken a radial bar chart's own unfilled track and widen the gap
between rings -- the classic "activity rings" look needs more
separation between rings than the default gap gives, and a darker
track reads better against a light background than the default light
gray.
"""
from dataviz import radialbar
from dataviz.plot import save
from dataviz.theme import Theme
from canvas.color import Color


def main() raises:
    var goals: List[String] = ["Move", "Exercise", "Stand"]
    var percent_complete: List[Float64] = [92.0, 68.0, 100.0]

    var plot = radialbar(
        goals,
        percent_complete,
        theme=Theme(radialbar_track_color=Color(200, 200, 200)),
        ring_gap_fraction=0.45,
        title="Daily Activity",
    )
    save(plot, "docs/src/examples/out_radialbar_styling.svg")
