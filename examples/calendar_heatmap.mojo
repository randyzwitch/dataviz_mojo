"""Demo: a calendar heatmap -- Mark.CALENDAR_HEATMAP, daily values laid
out in a GitHub-contributions-style calendar grid (Plot.encode_
calendar(), plain "YYYY-MM-DD" date strings -- see calendar_heatmap.
mojo's docstring), colored through the same continuous gradient
Mark.HEATMAP uses. Built via dataviz_mojo.calendar_heatmap() -- see
examples/scatter.mojo's docstring for what that trades away.

Simulated activity across 2024 -- ECharts.jl's calendarheatmap
example (GitHub commit counts), a value that cycles by day-of-month so
the grid reads as varied rather than flatly banded.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/pie.mojo's docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import calendar_heatmap
from dataviz_mojo.theme import Theme


def main() raises:
    var dates = List[String]()
    var values = List[Float64]()
    var days_in_month: List[Int] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    for month in range(1, 13):
        var month_str = "0" + String(month) if month < 10 else String(month)
        for day in range(1, days_in_month[month - 1] + 1):
            var day_str = "0" + String(day) if day < 10 else String(day)
            dates.append(String(2024) + "-" + month_str + "-" + day_str)
            values.append(Float64((day * 7 + month) % 10))

    var c = calendar_heatmap(dates, values, width=900, height=250)
    write_bmp(c, "examples/out_calendar_heatmap.bmp")
    write_png(c, "examples/out_calendar_heatmap.png")

    var svg = SvgCanvas(900, 250)
    var svg_plot = Plot().mark_calendar_heatmap().encode_calendar(dates=dates, values=values).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_calendar_heatmap.svg")

    print("wrote examples/out_calendar_heatmap.bmp, .png, and .svg")
