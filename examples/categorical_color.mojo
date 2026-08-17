"""Demo: a scatter plot colored by category -- Plot.encode(color_
categories=...), mapping discrete group names through
default_categorical_palette() instead of a continuous ColorScale. A
legend (Theme.show_legend, on by default whenever color_categories is
used) draws itself automatically -- nothing extra to opt into here.

Supersampled 3x -- see examples/scatter.mojo's own docstring for why
every example here now renders this way (and why it isn't just "a
bigger canvas").

Run with:
    pixi run example
"""

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.resize import downsample
from dataviz_mojo.plot import Plot, render
from dataviz_mojo.theme import Theme

comptime _SUPERSAMPLE = 3


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]
    var species: List[String] = [
        "setosa", "setosa", "setosa", "versicolor", "versicolor",
        "versicolor", "virginica", "virginica", "virginica", "virginica",
    ]

    var c = Canvas(640 * _SUPERSAMPLE, 420 * _SUPERSAMPLE, Color(255, 255, 255))
    var plot = Plot().mark_point().encode(
        x=x, y=y, color_categories=species
    ).theme(Theme(scale=Float64(_SUPERSAMPLE)))
    render(c, plot)
    var out = downsample(c, _SUPERSAMPLE)

    write_bmp(out, "examples/out_categorical_color.bmp")
    write_png(out, "examples/out_categorical_color.png")
    print("wrote examples/out_categorical_color.bmp and .png")
