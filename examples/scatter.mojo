"""Demo: a basic scatter plot -- Mark.POINT, default theme, axes and
gridlines computed automatically from the data's own domain.

Supersampled 3x -- every example here is, now (see the wiki's
Changelog, its own Theme.scale/canvas_mojo.resize.downsample entries): rendered at 3x this
file's own target size (Theme.scale=3.0 on a canvas 3x as wide/tall),
then shrunk back down to that target size via downsample() -- each
final pixel is the averaged, rounded mean of a real 3x3 block of
source pixels, not one sample. This bakes genuinely finer anti-
aliasing into the output file itself, at its original dimensions, not
a trick that depends on whatever later displays or rescales it (a
larger file that merely *looks* sharper in one particular viewer,
because that viewer happens to scale it back down to fit some pane,
was tried and rejected -- see the wiki entry for why).

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

    var c = Canvas(640 * _SUPERSAMPLE, 420 * _SUPERSAMPLE, Color(255, 255, 255))
    var plot = Plot().mark_point().encode(x=x, y=y).theme(Theme(scale=Float64(_SUPERSAMPLE)))
    render(c, plot)
    var out = downsample(c, _SUPERSAMPLE)

    write_bmp(out, "examples/out_scatter.bmp")
    write_png(out, "examples/out_scatter.png")
    print("wrote examples/out_scatter.bmp and .png")
