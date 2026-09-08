# title: Print-Safe (Grayscale) Theme
"""Apply `print_safe()` so lightness, line patterns, and a monotonic color
scale preserve distinctions in grayscale."""
from dataviz import bar
from dataviz.plot import save
from dataviz.themes import print_safe


def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
    var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

    var theme = print_safe()
    theme.color_by_sign = True

    var plot = bar(
        quarters,
        net_change,
        theme=theme,
        title="Net Change by Quarter",
        subtitle="Positive and negative separated by lightness, not by hue",
    )
    save(plot, "docs/src/examples/out_print_safe_theme.svg")
