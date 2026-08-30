from dataviz_mojo import scatter, save
from dataviz_mojo.colors import SEAGREEN
from dataviz_mojo.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1]

    var plot = scatter(
        x,
        y,
        theme=Theme(mark_color=SEAGREEN, point_radius=6.0),
        title="Weekly Revenue",
        x_title="Day",
        y_title="Revenue ($k)",
    )
    save(plot, "docs/src/examples/quickstart/out_step5_quickplot.svg")
