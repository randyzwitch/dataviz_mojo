"""Demo: a punchcard -- Mark.PUNCHCARD, a scatter plot on a categorical
grid where bubble size (Plot.encode_punchcard(), size/scale -- see
punchcard.mojo's docstring) encodes a third variable, GitHub-
style. Built via dataviz_mojo.punchcard() -- see examples/scatter.mojo's docstring for what that trades away.

Website visitors by day of week and hour of day -- ECharts.jl's punchcard() example, the chart type's classic use (peak traffic
during weekday business hours reads immediately as a cluster of large
bubbles).
"""

from dataviz_mojo.plot import save
from dataviz_mojo import punchcard
from dataviz_mojo.theme import Theme


def main() raises:
    var days: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var hours: List[String] = ["9am", "12pm", "3pm", "6pm", "9pm"]

    var x = List[String]()
    var y = List[String]()
    var counts = List[Float64]()
    for day_i in range(len(days)):
        var is_weekend = day_i >= 5
        for hour in hours:
            x.append(days[day_i])
            y.append(hour)
            counts.append(15.0 if is_weekend else 60.0)

    var c = punchcard(x, y, counts)
    save(c, "examples/out_punchcard.svg")
    save(c, "examples/out_punchcard.bmp")
    save(c, "examples/out_punchcard.png")
