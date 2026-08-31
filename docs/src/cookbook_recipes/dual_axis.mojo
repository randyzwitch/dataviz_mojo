# title: Dual Y-Axis
"""Draw one layer's y values against a second, independent y-domain on
the plot's right edge, instead of `render_layers()`'s usual shared
left-axis domain -- for a revenue-bars-plus-growth-rate-line combo
chart, where the two series' units/scales are too different to share
one axis without one of them going flat.
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

    save_layers(plots, "docs/src/examples/out_dual_axis.svg")
