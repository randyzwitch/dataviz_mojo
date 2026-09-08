# title: High-Contrast Theme
"""Make a chart readable at low vision, on a washed-out projector or in
bright sun with `high_contrast()`: black axes and type, larger
everything, gridlines raised from near-invisible to 4.4:1, and category
identity carried by marker shape as well as by hue.

The mark ink is Okabe & Ito's blue darkened to a 7.5:1 ratio against the
ground, the continuous scale is `cividis()` -- the colormap in
`dataviz.colormaps` built so a viewer with deuteranopia reads the same
ordering as everyone else -- and `shape_by_category` is on, so losing
the palette's hues costs no information.
"""
from dataviz.plot import Plot, save
from dataviz.themes import high_contrast


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [12.0, 9.0, 18.0, 15.0, 22.0, 20.0, 26.0, 24.0]
    var region: List[String] = [
        "North",
        "South",
        "East",
        "North",
        "South",
        "East",
        "North",
        "South",
    ]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=region)
        .labels(
            title="Readings by Region",
            subtitle="Circle, square and triangle, not just three colors",
            x_title="Week",
            y_title="Reading",
        )
        .theme(high_contrast())
    )
    save(plot, "docs/src/examples/out_high_contrast_theme.svg")
