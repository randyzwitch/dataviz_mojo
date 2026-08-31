"""Share one y-axis across every facet cell instead of each computing
its own independent one -- for small multiples meant to be compared
value-for-value, not just laid out side by side.
"""
from dataviz_mojo.plot import Plot, save_facets
from dataviz_mojo.colors import CORNFLOWERBLUE, SEAGREEN
from dataviz_mojo.theme import Theme

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var small: List[Float64] = [2.0, 3.0, 2.5, 3.5, 3.0]
    var big: List[Float64] = [50.0, 80.0, 60.0, 90.0, 70.0]

    var plot_small = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=x, y=small)
        .labels(title="Product A")
        .theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var plot_big = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=x, y=big)
        .labels(title="Product B")
        .theme(Theme(mark_color=SEAGREEN))
    )

    var plots: List[Plot] = [plot_small^, plot_big^]
    save_facets(plots, 2, "docs/src/examples/out_shared_facet_scale.svg", shared_y_scale=True)
