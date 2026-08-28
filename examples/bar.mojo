"""Demo: a bar chart -- Mark.BAR, a categorical x-axis (OrdinalScale)
and a y-axis that always includes a zero baseline. Includes one
negative value to show bars extending below the baseline correctly,
not just the all-positive case. Built via dataviz_mojo.bar()
-- see examples/scatter.mojo's docstring for what that trades
away.

A second chart below builds a genuinely *diverging* bar chart on top
of that same call -- Theme.color_by_sign, coloring each bar by
whether its value is negative (mark_color_negative) or not
(mark_color) instead of one flat mark_color, so the sign reads at a
glance rather than only from which direction the bar points. Bars
already extend below the zero baseline for negative values with no
changes needed, per the chart above; color_by_sign is the one further
thing a diverging bar chart adds. Both quickplot calls sit next to
each other, with each chart's own save() calls held until after both
-- see scripts/gen_example_docs.mojo's own PageSection docstring for
why that ordering matters (each call's docs snippet stops the moment
its own chart's data+call is done, so nothing from the other chart's
own save() calls leaks into it).
"""

from dataviz_mojo.plot import save
from dataviz_mojo import bar
from dataviz_mojo.colors import SEAGREEN
from dataviz_mojo.theme import Theme


def main() raises:
    var categories: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var values: List[Float64] = [12.0, 19.0, 8.0, 15.0, 22.0, -4.0, 6.0]

    var c = bar(categories, values, theme=Theme(mark_color=SEAGREEN))

    # Diverging bars (color_by_sign)
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
    var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

    var c_diverging = bar(quarters, net_change, theme=Theme(color_by_sign=True))

    save(c, "examples/out_bar.svg")
    save(c, "examples/out_bar.bmp")
    save(c, "examples/out_bar.png")

    save(c_diverging, "examples/out_bar_diverging.svg")
    save(c_diverging, "examples/out_bar_diverging.bmp")
    save(c_diverging, "examples/out_bar_diverging.png")


