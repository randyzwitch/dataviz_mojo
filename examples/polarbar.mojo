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

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import polarbar
from dataviz_mojo.theme import Theme


def main() raises:
    var months: List[String] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    var rainfall: List[Float64] = [2.6, 5.9, 9.0, 26.4, 28.7, 70.7, 175.6, 182.2, 48.7, 18.8, 6.0, 2.3]

    var c = polarbar(months, rainfall)
    write_bmp(c, "examples/out_polarbar.bmp")
    write_png(c, "examples/out_polarbar.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_polar_bar().encode_categorical(x=months, y=rainfall).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_polarbar.svg")
