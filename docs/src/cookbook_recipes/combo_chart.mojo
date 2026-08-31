# title: Combo Chart (Shared Axis)
"""Layer two series that share one y-axis and one set of units --
render_layers()'s default, no secondary_axis() needed.
"""
from dataviz_mojo.plot import Plot, save_layers
from dataviz_mojo.colors import CORNFLOWERBLUE, TOMATO
from dataviz_mojo.theme import Theme

def main() raises:
    var months: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var actual: List[Float64] = [420.0, 480.0, 450.0, 610.0, 550.0, 580.0]
    var target: List[Float64] = [400.0, 420.0, 460.0, 500.0, 540.0, 560.0]

    var actual_layer = (
        Plot()
        .mark_area()
        .encode(x=months, y=actual)
        .theme(Theme(mark_color=CORNFLOWERBLUE))
        .labels(title="Actual vs. Target Revenue", x_title="Month", y_title="Revenue ($K)")
    )
    var target_layer = (
        Plot()
        .mark_line()
        .encode(x=months, y=target)
        .theme(Theme(mark_color=TOMATO, line_width=3.0))
    )
    var plots: List[Plot] = [actual_layer^, target_layer^]
    save_layers(plots, "docs/src/examples/out_layers_combo.svg")
