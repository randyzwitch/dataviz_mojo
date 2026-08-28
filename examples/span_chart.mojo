"""Demo: a span chart -- Mark.SPAN_CHART, Mark.GANTT's mirror
image: one floating vertical bar per category, from a low value to a
high value, not anchored to zero (Plot.encode_gantt(), the exact same
category + start + end shape Mark.GANTT itself uses -- see
span_chart.mojo's docstring). Built via dataviz_mojo.span_chart()
-- see examples/scatter.mojo's docstring for what that trades
away.

Monthly temperature range for Beijing -- ECharts.jl's spanchart
example, the chart type's classic use (a daily high/low range
that would misrepresent the data if drawn as a bar(), since a bar
implies "from zero," not "from the low").
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import span_chart
from dataviz_mojo.theme import Theme


def main() raises:
    var months: List[String] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    var temp_low: List[Float64] = [-3.0, -2.0, 3.0, 10.0, 15.0, 19.0, 21.0, 20.0, 15.0, 8.0, 2.0, -1.0]
    var temp_high: List[Float64] = [5.0, 7.0, 12.0, 20.0, 25.0, 29.0, 31.0, 30.0, 26.0, 18.0, 10.0, 5.0]

    var c = span_chart(months, temp_low, temp_high)
    write_bmp(c, "examples/out_span_chart.bmp")
    write_png(c, "examples/out_span_chart.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_span_chart().encode_gantt(categories=months, start=temp_low, end=temp_high).theme(
        Theme()
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_span_chart.svg")
