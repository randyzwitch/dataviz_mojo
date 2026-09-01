"""Label individual points directly on a scatter plot with
`Plot.encode()`'s `labels` channel -- an opt-in per-point text column,
since (unlike a bar's own value) a point has no one obvious default
label; pass `""` for any point that shouldn't get one.
"""
from dataviz_mojo.plot import Plot, save
from dataviz_mojo.theme import Theme

def main() raises:
    var city: List[String] = ["Tokyo", "Delhi", "Shanghai", "Chicago", "Lagos"]
    var x: List[Float64] = [37.4, 32.9, 29.2, 8.9, 15.4]
    var y: List[Float64] = [1.0, 1.4, 4.3, 2.7, 3.6]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, labels=city)
        .theme(Theme(point_radius=6.0))
        .labels(
            title="Metro Population vs. Growth Rate",
            x_title="Population (millions)",
            y_title="Growth Rate (%)",
        )
    )
    save(plot, "docs/src/examples/out_point_labels.svg")
