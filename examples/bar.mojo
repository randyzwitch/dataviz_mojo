"""Demo: a bar chart -- Mark.BAR, a categorical x-axis (OrdinalScale)
and a y-axis that always includes a zero baseline. Includes one
negative value to show bars extending below the baseline correctly,
not just the all-positive case.

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
    var categories: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var values: List[Float64] = [12.0, 19.0, 8.0, 15.0, 22.0, -4.0, 6.0]

    var t = Theme(mark_color=Color(40, 130, 90), scale=Float64(_SUPERSAMPLE))
    var c = Canvas(640 * _SUPERSAMPLE, 420 * _SUPERSAMPLE, Color(255, 255, 255))
    var plot = Plot().mark_bar().encode_categorical(x=categories, y=values).theme(t)
    render(c, plot)
    var out = downsample(c, _SUPERSAMPLE)

    write_bmp(out, "examples/out_bar.bmp")
    write_png(out, "examples/out_bar.png")
    print("wrote examples/out_bar.bmp and .png")
