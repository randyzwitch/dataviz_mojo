"""Lower a radar chart's own filled-polygon opacity so three or more
overlapping series all stay visible -- the default opacity reads fine
for one or two series, but a third series' fill starts to bury
whichever one is drawn underneath it.
"""
from dataviz import radar
from dataviz.plot import save
from dataviz.theme import Theme

def main() raises:
    var indicators: List[String] = ["Speed", "Power", "Defense", "Stamina", "Agility"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0, 100.0, 100.0]
    var series_names: List[String] = ["Team A", "Team B", "Team C"]
    var series_values: List[List[Float64]] = [
        [85.0, 70.0, 60.0, 75.0, 90.0],
        [65.0, 90.0, 80.0, 60.0, 55.0],
        [75.0, 60.0, 85.0, 80.0, 70.0],
    ]

    var plot = radar(
        indicators,
        max_values,
        series_names,
        series_values,
        theme=Theme(radar_fill_alpha=45),
        title="Player Attributes",
        subtitle="Three overlapping series, each still visible through the others",
    )
    save(plot, "docs/src/examples/out_radar_fill_alpha.svg")
