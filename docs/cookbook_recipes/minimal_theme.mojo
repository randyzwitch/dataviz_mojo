# title: Minimal Theme
"""Strip a chart back to its data with `minimal()` -- no gridlines, a
faded axis, tight margins -- and then drop the legend too, as an
override, on a chart that does not need one.

`minimal()` deliberately keeps the legend, because hiding it deletes the
mapping from color to category rather than reducing ink. That makes it
the wrong default for a preset and a perfectly good per-chart choice
here, where the series are already labeled by the title.
"""
from dataviz.plot import Plot, save
from dataviz.themes import minimal


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var y: List[Float64] = [12.0, 9.0, 18.0, 15.0, 22.0, 20.0]
    var region: List[String] = [
        "North",
        "South",
        "North",
        "South",
        "North",
        "South",
    ]

    var theme = minimal()
    theme.show_legend = False

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=region)
        .labels(title="Readings by Region")
        .theme(theme)
    )
    save(plot, "docs/src/examples/out_theme_minimal.svg")
