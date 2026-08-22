"""Demo: real SVG accessibility markup -- accessible_svg_string()/
write_accessible_svg(). Adds role="img" + aria-label to the root <svg>
element, plus <title> (and, when given, <desc>) as its own leading
child elements -- exactly what the SVG accessibility spec, and every
screen reader that supports SVG at all, looks for.

Only helps when the SVG's own accessible tree actually gets walked --
inline <svg> markup, a standalone .svg opened directly, or an
<object>/<iframe> embed all expose it. A plain <img src="chart.svg">
(how this project's own docs site embeds every other example) does
not -- see accessible_svg_string()'s own docstring for the full story,
which is also why this one example gets its own dedicated page here
rather than being folded into every other chart's own file.

Writes only a vector (.svg) file -- this feature has no raster
counterpart at all (role/aria-label/title/desc are SVG-only concepts;
a raster PNG/BMP has no accessible-tree equivalent to attach them to).

Run with:
    pixi run example
"""

from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg, write_accessible_svg


def main() raises:
    var regions: List[String] = ["North", "South", "East", "West"]
    var revenue: List[Float64] = [420.0, 310.0, 275.0, 390.0]

    var plot = Plot().mark_bar().encode_categorical(x=regions, y=revenue).labels(
        title="Regional Revenue"
    )

    var svg = SvgCanvas(640, 420)
    render_svg(svg, plot)
    write_accessible_svg(
        svg,
        "examples/out_svg_accessibility.svg",
        "Regional Revenue comparison chart",
        "A chart comparing revenue across four regions: North ($420), South ($310),"
        " East ($275), and West ($390).",
    )

    print("wrote examples/out_svg_accessibility.svg")
