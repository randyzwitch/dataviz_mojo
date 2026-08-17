"""Demo: a pie chart -- Mark.ARC, one wedge per category, angular span
proportional to its value, colored via the same default_categorical_
palette() a categorical-color scatter plot uses. A legend (Theme.
show_legend, on by default for Mark.ARC) labels each wedge.

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
    var browsers: List[String] = ["Chrome", "Safari", "Edge", "Firefox", "Other"]
    var share: List[Float64] = [65.0, 18.0, 5.0, 7.0, 5.0]

    var c = Canvas(400 * _SUPERSAMPLE, 300 * _SUPERSAMPLE, Color(255, 255, 255))
    var plot = Plot().mark_arc().encode_categorical(x=browsers, y=share).theme(
        Theme(scale=Float64(_SUPERSAMPLE))
    )
    render(c, plot)
    var out = downsample(c, _SUPERSAMPLE)

    write_bmp(out, "examples/out_pie.bmp")
    write_png(out, "examples/out_pie.png")
    print("wrote examples/out_pie.bmp and .png")
