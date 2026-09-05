"""Lay out several independent Plots in an evenly sized grid -- each
cell is its own Plot, with its own data, theme, and even mark type;
this is purely a grid-layout primitive, not a "split this data by a
column" faceting feature.
"""
from dataviz.plot import Plot, save_facets
from dataviz.colors import CORNFLOWERBLUE, SEAGREEN, TOMATO, GOLD
from dataviz.theme import Theme


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var north: List[Float64] = [12.0, 15.0, 14.0, 18.0, 20.0]
    var south: List[Float64] = [9.0, 11.0, 13.0, 12.0, 16.0]
    var east: List[Float64] = [20.0, 19.0, 22.0, 24.0, 23.0]
    var west: List[Float64] = [6.0, 8.0, 7.0, 10.0, 9.0]

    var plot_north = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=x, y=north)
        .labels(title="North")
        .theme(Theme(mark_color=CORNFLOWERBLUE))
    )
    var plot_south = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=x, y=south)
        .labels(title="South")
        .theme(Theme(mark_color=SEAGREEN))
    )
    var plot_east = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=x, y=east)
        .labels(title="East")
        .theme(Theme(mark_color=TOMATO))
    )
    var plot_west = (
        Plot()
        .size(320, 240)
        .mark_line()
        .encode(x=x, y=west)
        .labels(title="West")
        .theme(Theme(mark_color=GOLD))
    )

    var plots: List[Plot] = [plot_north^, plot_south^, plot_east^, plot_west^]
    save_facets(plots, 2, "docs/src/examples/out_facets.svg")
