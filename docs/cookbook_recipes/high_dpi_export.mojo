# title: High-DPI Export
"""Render the same chart at a higher pixel density for a crisp export.
"""
from dataviz.plot import Plot, save
from dataviz.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [12.0, 18.0, 15.0, 22.0, 19.0]

    # Twice the pixel size, paired with scale=2.0, renders the
    # exact same layout at double the pixel density -- crisp at
    # 2x zoom instead of upscaled and blurry.
    var plot = (
        Plot()
        .size(1280, 840)
        .mark_line()
        .encode(x=x, y=y)
        .labels(title="High-Resolution Export")
        .theme(Theme(scale=2.0))
    )
    save(plot, "docs/src/examples/out_theme_high_dpi.png")
