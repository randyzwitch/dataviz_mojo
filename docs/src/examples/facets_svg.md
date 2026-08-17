# Facets (SVG)

The same four-region facets grid examples/facets.mojo draws, rendered to SVG instead of a raster canvas.

![Facets (SVG)](out_facets_svg.svg)

## Run it

```sh
mojo run -I . examples/facets_svg.mojo
```

(Or `pixi run example`, which runs every example in this directory in one go.)

## Source

```mojo
"""Demo: the same four-region facets grid examples/facets.mojo draws,
rendered to SVG instead of a raster canvas -- render_facets_svg() is
render_facets()'s exact counterpart (see plot.mojo's own docstring:
both share one generic _render_facets_generic core, the same relation
render()/render_svg() have), each cell's own Plot.labels() title
included. No supersampling needed here either -- see examples/
scatter_svg.mojo's own docstring.

Run with:
    pixi run example
"""

from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_facets_svg
from dataviz_mojo.theme import Theme


def main() raises:
    var quarters: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var north: List[Float64] = [120.0, 135.0, 128.0, 160.0]
    var south: List[Float64] = [80.0, 95.0, 110.0, 105.0]
    var east: List[Float64] = [200.0, 190.0, 210.0, 240.0]
    var west: List[Float64] = [60.0, 70.0, 65.0, 90.0]

    var palette = default_categorical_palette()
    var plots = List[Plot]()
    plots.append(
        Plot().mark_line().encode(x=quarters, y=north).labels(title="North").theme(Theme(mark_color=palette[0]))
    )
    plots.append(
        Plot().mark_line().encode(x=quarters, y=south).labels(title="South").theme(Theme(mark_color=palette[1]))
    )
    plots.append(
        Plot().mark_line().encode(x=quarters, y=east).labels(title="East").theme(Theme(mark_color=palette[2]))
    )
    plots.append(
        Plot().mark_line().encode(x=quarters, y=west).labels(title="West").theme(Theme(mark_color=palette[3]))
    )

    var svg = SvgCanvas(800, 600)
    render_facets_svg(svg, plots, cols=2)

    write_svg(svg, "examples/out_facets.svg")
    print("wrote examples/out_facets.svg")
```

[View `facets_svg.mojo` on GitHub](https://github.com/randyzwitch/dataviz_mojo/blob/main/examples/facets_svg.mojo)
