"""Demo: a ridgeline plot -- Mark.RIDGELINE, one overlapping kernel-
density-estimate row per category, top to bottom (Plot.encode_
distribution(), the same category-plus-raw-values shape beeswarm()/
violin() take -- see ridgeline.mojo's docstring for the baseline/
overlap rules). Mark.GANTT's horizontal categorical axis frame,
reused unchanged; each row's curve reuses Mark.VIOLIN's KDE
math exactly, just drawn upward from a row baseline instead of
left-right-symmetric. Built via dataviz_mojo.ridgeline() -- see
examples/scatter.mojo's docstring for what that trades away.

Daily temperature distributions across a few months -- the classic
ridgeline use: several distributions' shapes, stacked so they're
easy to compare at a glance, with a little overlap read as "closer to
the viewer."
"""

from dataviz_mojo.plot import save
from dataviz_mojo import ridgeline
from dataviz_mojo.theme import Theme


def main() raises:
    var months: List[String] = ["June", "July", "August", "September"]
    var temps: List[List[Float64]] = [
        [68.0, 70.0, 72.0, 74.0, 71.0, 69.0, 75.0, 73.0],
        [78.0, 80.0, 82.0, 85.0, 79.0, 81.0, 83.0, 84.0],
        [80.0, 82.0, 84.0, 86.0, 81.0, 83.0, 85.0, 87.0],
        [70.0, 72.0, 74.0, 76.0, 71.0, 73.0, 75.0, 69.0],
    ]

    var c = ridgeline(months, temps)
    save(c, "examples/out_ridgeline.svg")
    save(c, "examples/out_ridgeline.bmp")
    save(c, "examples/out_ridgeline.png")
