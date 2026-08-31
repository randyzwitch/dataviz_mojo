# title: SVG Accessibility
"""Write real SVG accessibility markup alongside a rendered chart --
`role="img"`/`aria-label` on the root `<svg>` element, plus a
`<title>` (and, when given, a `<desc>`) as its first child elements,
exactly what a screen reader looks for.
"""
from dataviz_mojo.plot import Plot, render_svg, write_accessible_svg

def main() raises:
    var regions: List[String] = ["North", "South", "East", "West"]
    var revenue: List[Float64] = [420.0, 310.0, 275.0, 390.0]

    var plot = Plot().mark_bar().encode_categorical(x=regions, y=revenue).labels(
        title="Regional Revenue"
    )

    var svg = render_svg(plot)
    write_accessible_svg(
        svg,
        "docs/src/examples/out_svg_accessibility.svg",
        "Regional Revenue comparison chart",
        "A chart comparing revenue across four regions: North ($420), South ($310),"
        " East ($275), and West ($390).",
    )
