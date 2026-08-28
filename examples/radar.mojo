"""Demo: a radar/spider chart -- Mark.RADAR, one spoke per named
indicator (each its max), one filled-and-stroked polygon per named
series (Plot.encode_radar() -- see that method's docstring). Built
via dataviz_mojo.radar() -- see examples/scatter.mojo's docstring
for what that trades away.

Two teams compared across five attributes -- ECharts.jl's radar()
example, the chart type's classic use (overlapping polygons make
each team's relative strengths across dimensions immediately visible).
"""

from dataviz_mojo.plot import save
from dataviz_mojo import radar
from dataviz_mojo.theme import Theme


def main() raises:
    var indicators: List[String] = ["Attack", "Defense", "Speed", "Stamina", "Skill"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0, 100.0, 100.0]
    var series_names: List[String] = ["Team A", "Team B"]
    var series_values: List[List[Float64]] = [
        [90.0, 60.0, 80.0, 70.0, 85.0],
        [65.0, 85.0, 55.0, 90.0, 60.0],
    ]

    var c = radar(indicators, max_values, series_names, series_values)
    save(c, "examples/out_radar.svg")
    save(c, "examples/out_radar.bmp")
    save(c, "examples/out_radar.png")
