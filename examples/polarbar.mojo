"""Demo: a polar bar chart -- Mark.POLAR_BAR, bars radiating outward
from the chart's center, one equal-width angular slot per category
(Plot.encode_categorical(), the same category + value shape pie()/
bar()/nightingale() use), length proportional to value/max(values).
Built via dataviz_mojo.polarbar() -- see examples/scatter.mojo's docstring for what that trades away.

Monthly rainfall -- ECharts.jl's polarbar example, a good fit for
the chart type (12 categories share the full circle evenly, a natural
"clock face" reading for a 12-month cycle a linear bar chart doesn't
give for free).
"""

from dataviz_mojo.plot import save
from dataviz_mojo import polarbar
from dataviz_mojo.theme import Theme


def main() raises:
    var months: List[String] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    var rainfall: List[Float64] = [2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3]

    var c = polarbar(months, rainfall)
    save(c, "examples/out_polarbar.svg")
    save(c, "examples/out_polarbar.bmp")
    save(c, "examples/out_polarbar.png")
