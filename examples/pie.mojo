"""Demo: a pie chart -- Mark.ARC, one wedge per category, angular span
proportional to its value, colored via the same default_categorical_
palette() a categorical-color scatter plot uses. A legend (Theme.
show_legend, on by default for Mark.ARC) labels each wedge. Built via
dataviz_mojo.pie() -- see examples/scatter.mojo's docstring for what
that trades away.

A second chart below draws the same browser-share data as a donut --
Theme.donut_inner_radius_fraction set, switching Mark.ARC from a full
wedge to a ring segment (canvas_mojo.shapes.arcs.fill_ring_sector_aa
on the raster path, SvgCanvas.fill_ring_sector_aa on the vector one --
see plot.mojo's _render_arc docstring for where that switch happens).
Still built via the same dataviz_mojo.pie() -- donut isn't a separate
quickplot function, just pie() with donut_inner_radius_fraction set,
which is the one thing distinguishing the second call below from the
first.

Writes both a raster (.bmp) and a vector (.svg) file per chart, from
the same data -- both backends are first-class (see the wiki), so
both get exercised by every example without doubling the file count.
The docs page for this example (see scripts/gen_example_docs.mojo)
shows only the quickplot calls above, not the render_svg() blocks
below -- both produce the identical charts, and the quickplot calls
are the cleaner reconstruction of "how would I actually write this."
"""

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import pie
from dataviz_mojo.theme import Theme


def main() raises:
    var browsers: List[String] = ["Chrome", "Safari", "Edge", "Firefox", "Other"]
    var share: List[Float64] = [65.0, 18.0, 5.0, 7.0, 5.0]

    var c = pie(browsers, share, width=400, height=300)

    # Donut (donut_inner_radius_fraction)
    var c_donut = pie(
        browsers,
        share,
        theme=Theme(donut_inner_radius_fraction=0.55),
        width=400,
        height=300,
    )

    write_bmp(c, "examples/out_pie.bmp")
    write_png(c, "examples/out_pie.png")

    var svg_plot = Plot().mark_arc().encode_categorical(x=browsers, y=share).theme(Theme()).size(400, 300)
    var svg = render_svg(svg_plot)
    write_svg(svg, "examples/out_pie.svg")

    write_bmp(c_donut, "examples/out_pie_donut.bmp")
    write_png(c_donut, "examples/out_pie_donut.png")

    var svg_plot_donut = Plot().mark_arc().encode_categorical(x=browsers, y=share).theme(
        Theme(donut_inner_radius_fraction=0.55)
    ).size(400, 300)
    var svg_donut = render_svg(svg_plot_donut)
    write_svg(svg_donut, "examples/out_pie_donut.svg")
