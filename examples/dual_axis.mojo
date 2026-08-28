"""Demo: a dual-y-axis combo chart -- Plot.secondary_axis(), ECharts' `yAxisIndex: 1` (simplified to a boolean, see that method's docstring). A revenue-bars-and-growth-rate-line combination, the
textbook case a second y-axis exists for: the two series' units
($ millions vs. a percentage) are too different in scale to share one
axis without one of them going flat.

Monthly revenue (Mark.AREA, left/primary axis) and month-over-month
growth rate (Mark.LINE, right/secondary axis via .secondary_axis()) --
built by hand via render_layers() (not a one-call quickplot -- layering
itself isn't exposed on one; see examples/annotate_line.mojo's docstring for the same reasoning applied to a different Plot feature).
Each axis captioned via that same layer's .labels(y_title=...) --
the secondary layer's caption mirrors onto the plot's right edge
(see Plot.secondary_axis()'s docstring for why this reads from the
layer itself, not a title shared from plots[0] the way the chart's title/x_title are).

Writes all three formats from one `plots` list via save_layers() --
no `canvas_mojo` import needed at all (see that function's docstring).
"""

from canvas_mojo.color import Color
from dataviz_mojo.plot import Plot, save_layers
from dataviz_mojo.theme import Theme


def main() raises:
    var months: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var revenue: List[Float64] = [420.0, 480.0, 450.0, 610.0, 550.0, 580.0]
    var growth: List[Float64] = [2.1, 3.4, -1.2, 8.7, 4.0, 5.2]

    var revenue_layer = Plot().mark_area().encode(x=months, y=revenue).theme(
        Theme(mark_color=Color(70, 130, 180))
    ).labels(title="Revenue & Growth", x_title="Month", y_title="Revenue ($M)")
    var growth_layer = (
        Plot()
        .mark_line()
        .encode(x=months, y=growth)
        .theme(Theme(mark_color=Color(220, 80, 60)))
        .secondary_axis()
        .labels(y_title="Growth (%)")
    )
    var plots = List[Plot]()
    plots.append(revenue_layer^)
    plots.append(growth_layer^)

    save_layers(plots, "examples/out_dual_axis.bmp")
    save_layers(plots, "examples/out_dual_axis.png")
    save_layers(plots, "examples/out_dual_axis.svg")
