"""Replace the default blue-to-orange continuous color gradient with a
diverging red-white-blue scale, the conventional choice for a value
that reads as "above/below a midpoint" rather than a plain low-to-high
range.
"""
from canvas.color import Color
from dataviz.plot import Plot, save
from dataviz.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    var y: List[Float64] = [12.0, 18.0, 15.0, 22.0, 19.0, 25.0, 21.0, 28.0]
    var temp_anomaly: List[Float64] = [
        -1.8,
        -0.6,
        -1.2,
        0.4,
        1.5,
        -0.2,
        0.9,
        2.1,
    ]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color=temp_anomaly)
        .labels(
            title="Readings by Temperature Anomaly",
            subtitle="Deviation from the 30-year average, °C",
        )
        .theme(
            Theme(
                color_scale_low=Color(30, 60, 180),
                color_scale_mid=Color(245, 245, 245),
                color_scale_high=Color(190, 30, 30),
            )
        )
    )
    save(plot, "docs/src/examples/out_diverging_color_scale.svg")
