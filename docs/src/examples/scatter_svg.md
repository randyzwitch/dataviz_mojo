# Scatter (SVG)

The same scatter plot examples/scatter.mojo draws, rendered to SVG instead of a raster canvas.

![Scatter (SVG)](out_scatter_svg.svg)

## Run it

```sh
mojo run -I . examples/scatter_svg.mojo
```

(Or `pixi run example`, which runs every example in this directory in one go.)

## Source

```mojo
"""Demo: the same scatter plot examples/scatter.mojo draws, rendered
to SVG instead of a raster canvas -- Plot itself is unaware which one
it's targeting (see plot.mojo's own module docstring: both render()
and render_svg() share one generic core). No supersampling needed
here the way examples/scatter.mojo's own docstring explains every
raster example needs -- SVG has no fixed pixel resolution to lose
sharpness at in the first place; open the output file directly (or in
any SVG-aware viewer) at any zoom level and the text/lines stay crisp.

Run with:
    pixi run example
"""

from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg


def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]

    var svg = SvgCanvas(640, 420)
    var plot = Plot().mark_point().encode(x=x, y=y)
    render_svg(svg, plot)

    write_svg(svg, "examples/out_scatter.svg")
    print("wrote examples/out_scatter.svg")
```

[View `scatter_svg.mojo` on GitHub](https://github.com/randyzwitch/dataviz_mojo/blob/main/examples/scatter_svg.mojo)
