"""Recolor a waterfall's running-total checkpoint bars and widen its
delta bars -- `Theme.waterfall_total_color` keeps "Start"/"End" totals
visually distinct from plain increases/decreases, and `waterfall_
delta_width_fraction` controls how much of each band a delta bar fills.
"""
from dataviz import waterfall
from dataviz.plot import save
from dataviz.colors import SLATEGRAY
from dataviz.theme import Theme

def main() raises:
    var cats: List[String] = ["Start", "Product", "Services", "Refunds", "End"]
    var deltas: List[Float64] = [50.0, 20.0, 12.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, False, True]

    var plot = waterfall(
        cats,
        deltas,
        is_total=is_total,
        theme=Theme(waterfall_total_color=SLATEGRAY),
        delta_width_fraction=0.85,
        title="Cash Flow",
        subtitle="Starting/ending balances in a distinct color, wider delta bars",
    )
    save(plot, "docs/src/examples/out_waterfall_colors.svg")
