"""Demo: a gantt/span chart -- Mark.GANTT, one horizontal bar per
category from a start value to an end value (Plot.encode_gantt(), a
category plus a range -- see that method's docstring). One of the
marks whose categories run along the *y*-axis instead of the x-axis
(`_draw_horizontal_categorical_axis_frame`, shared with Mark.
POPULATION_PYRAMID/RIDGELINE, the mirror image of every other
categorical mark here's vertical axis frame -- see its docstring for
why this needed a dedicated function rather than generalizing the
vertical one). Built via dataviz_mojo.
gantt() -- see examples/scatter.mojo's docstring for what that
trades away.

A five-task project schedule (day numbers, not calendar dates -- this
package has no Date/Time type; see encode_gantt()'s docstring for
why that's a deliberate, not a missing, choice), with overlapping spans
(Testing starts before Development finishes) -- the kind of at-a-glance
overlap a gantt chart is for.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import gantt
from dataviz_mojo.theme import Theme


def main() raises:
    var tasks: List[String] = ["Design", "Development", "Testing", "Documentation", "Launch"]
    var start: List[Float64] = [0.0, 5.0, 20.0, 15.0, 28.0]
    var end: List[Float64] = [8.0, 25.0, 28.0, 27.0, 30.0]

    var c = gantt(tasks, start, end)
    save(c, "examples/out_gantt.svg")
    save(c, "examples/out_gantt.bmp")
    save(c, "examples/out_gantt.png")
