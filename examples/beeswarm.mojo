"""Demo: a beeswarm plot -- Mark.BEESWARM, one point per raw value,
jittered sideways within its category's band to avoid overlap
(Plot.encode_distribution(), a category plus a *list* of raw values --
see that method's docstring; the same shape Mark.VIOLIN/RIDGELINE
will take). Reuses the same vertical categorical axis frame Mark.BOX
does. Built via dataviz_mojo.beeswarm() -- see examples/scatter.mojo's docstring for what that trades away.

Exam scores by class -- the classic beeswarm use: seeing every
individual data point's position within its group, not just a
box's five-number summary.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import beeswarm
from dataviz_mojo.theme import Theme


def main() raises:
    var classes: List[String] = ["Section A", "Section B", "Section C"]
    var scores: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0, 74.0, 76.0, 91.0],
        [65.0, 70.0, 72.0, 88.0, 90.0, 92.0, 95.0],
        [80.0, 82.0, 83.0, 84.0, 81.0, 79.0, 85.0],
    ]

    var c = beeswarm(classes, scores)
    save(c, "examples/out_beeswarm.svg")
    save(c, "examples/out_beeswarm.bmp")
    save(c, "examples/out_beeswarm.png")
