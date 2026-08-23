"""Demo: a donut chart -- Mark.ARC with Theme.donut_inner_radius_
fraction set, the same browser-share data examples/pie.mojo draws,
switched from a full wedge to a ring segment (canvas_mojo.shapes.arcs.
fill_ring_sector_aa on the raster path, SvgCanvas.fill_ring_sector_aa
on the vector one -- see plot.mojo's own _render_arc docstring for
where that switch happens). Raster output built via dataviz_mojo.
pie() -- see examples/scatter.mojo's own docstring for what that
trades away; the donut_inner_radius_fraction=0.55 kwarg is the only
thing distinguishing this file from examples/pie.mojo's own call.

Writes both a raster (.bmp) and a vector (.svg) file from the same
Plot -- both backends are first-class (see the wiki), so both get
exercised by every example without doubling the file count. The docs
page for this example (see scripts/gen_example_docs.mojo) shows only
the quickplot call above, not the render_svg() block below -- both
produce the identical chart, and the quickplot one is the cleaner
reconstruction of "how would I actually write this."

Run with:
    pixi run example
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import pie
from dataviz_mojo.theme import Theme


def main() raises:
    var browsers: List[String] = ["Chrome", "Safari", "Edge", "Firefox", "Other"]
    var share: List[Float64] = [65.0, 18.0, 5.0, 7.0, 5.0]

    var c = pie(
        browsers,
        share,
        theme=Theme(donut_inner_radius_fraction=0.55),
        width=400,
        height=300,
    )
    write_bmp(c, "examples/out_donut.bmp")
    write_png(c, "examples/out_donut.png")

    var svg = SvgCanvas(400, 300)
    var svg_plot = Plot().mark_arc().encode_categorical(x=browsers, y=share).theme(
        Theme(donut_inner_radius_fraction=0.55)
    )
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_donut.svg")

    print("wrote examples/out_donut.bmp, .png, and .svg")
