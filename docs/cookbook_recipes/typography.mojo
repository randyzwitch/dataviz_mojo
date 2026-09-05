# title: Custom Typography
"""Override the chart's typeface, title weight, and title font size.
"""
from dataviz.plot import Plot, save
from dataviz.theme import Theme


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
    var revenue: List[Float64] = [42.0, 48.0, 55.0, 61.0]

    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=quarters, y=revenue)
        .labels(title="Quarterly Revenue")
        .theme(
            Theme(font_family="serif", title_bold=True, title_font_size=24.0)
        )
    )
    save(plot, "docs/src/examples/out_theme_typography.svg")
