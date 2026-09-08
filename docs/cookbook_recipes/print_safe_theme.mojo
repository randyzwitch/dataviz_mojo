# title: Print-Safe (Grayscale) Theme
"""Keep a chart readable after it is printed, photocopied or faxed with
`print_safe()`, which carries every distinction in lightness instead of
in hue.

The default theme is unreadable in grayscale in a way that is easy to
miss on screen: its `mark_color` and `mark_color_negative` are Rec.709
luma 90.9 and 89.8, so the bars below would print as one flat shade.
`print_safe()` puts them 145 levels apart, dots the gridlines and dashes
the reference line so neither can be mistaken for a series, and swaps
the diverging color scale -- whose two ends are 8.2 levels apart in
grayscale -- for `viridis()`, which is monotonic in lightness across all
64 stops.
"""
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
