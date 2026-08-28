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

Writes both a raster (.bmp/.png) and a vector (.svg) file per chart,
from the same data -- both backends are first-class (see the wiki),
so both get exercised by every example without doubling the file
count. Both quickplot calls sit next to each other, with each chart's
own save() calls held until after both -- see scripts/gen_example_
docs.mojo's own PageSection docstring for why that ordering matters
(each call's docs snippet stops the moment its own chart's data+call
is done, so nothing from the other chart's own save() calls leaks
into it).
"""

from dataviz_mojo.plot import save
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

    save(c, "examples/out_pie.svg")
    save(c, "examples/out_pie.bmp")
    save(c, "examples/out_pie.png")

    save(c_donut, "examples/out_pie_donut.svg")
    save(c_donut, "examples/out_pie_donut.bmp")
    save(c_donut, "examples/out_pie_donut.png")


