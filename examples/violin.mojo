"""Demo: a violin plot -- Mark.VIOLIN, a symmetric kernel-density-
estimate silhouette per category (Plot.encode_distribution(), the same
category-plus-raw-values shape beeswarm()/ridgeline() take -- see
violin.mojo's docstring for the bandwidth/sampling/width-scaling
rules). Reuses the same vertical categorical axis frame Mark.BOX/
BEESWARM do. Built via dataviz_mojo.violin() -- see examples/scatter.
mojo's docstring for what that trades away.

Exam scores by class -- the same data examples/beeswarm.mojo uses, so
the two are directly comparable: a violin shows the smoothed shape of
each distribution, beeswarm shows every individual point.

Writes both a raster (.bmp) and a vector (.svg) file from the same
data -- see examples/pie.mojo's docstring for why, and for why
the docs page only shows the quickplot call above.

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import violin
from dataviz_mojo.theme import Theme


def main() raises:
    var classes: List[String] = ["Section A", "Section B", "Section C"]
    var scores: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0, 74.0, 76.0, 91.0],
        [65.0, 70.0, 72.0, 88.0, 90.0, 92.0, 95.0],
        [80.0, 82.0, 83.0, 84.0, 81.0, 79.0, 85.0],
    ]

    var c = violin(classes, scores)
    write_bmp(c, "examples/out_violin.bmp")
    write_png(c, "examples/out_violin.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_violin().encode_distribution(categories=classes, values=scores).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_violin.svg")

    print("wrote examples/out_violin.bmp, .png, and .svg")
