# title: Diverging Bar (Positive/Negative Color)
"""Color each bar by whether its value is positive or negative, instead
of one flat color.
"""
from dataviz import bar
from dataviz.plot import save
from dataviz.theme import Theme

def main() raises:
    var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6"]
    var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

    var c_diverging = bar(quarters, net_change, theme=Theme(color_by_sign=True))
    # A distinct output filename from bar.mojo's own "Diverging bars"
    # Example (out_bar_diverging.svg) -- that block stays in bar()'s
    # own docstring purely so the Bar Examples page keeps its existing
    # Variant section; this file is now the Cookbook's own source for
    # the same technique, and both writing the same path in parallel
    # (pixi run example) would race.
    save(c_diverging, "docs/src/examples/out_diverging_bar.svg")
