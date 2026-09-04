"""Draw a lollipop chart with categories running top-to-bottom and
stems extending left-to-right instead of the default vertical layout --
`Plot.mark_lollipop(horizontal=True)`/`lollipop(..., horizontal=True)`,
the same "long or many category names" use case `horizontal_bar`
covers, with a stem-and-point instead of a filled bar per category.
"""
from dataviz.plot import Plot, save


def main() raises:
    var languages: List[String] = [
        "Python",
        "JavaScript",
        "TypeScript",
        "Rust",
        "Mojo",
    ]
    var stars_thousands: List[Int] = [62, 98, 100, 92, 24]

    var plot = (
        Plot()
        .mark_lollipop(horizontal=True)
        .encode_categorical(x=languages, y=stars_thousands)
        .labels(title="GitHub Stars by Language", x_title="Stars (thousands)")
    )
    save(plot, "docs/src/examples/out_horizontal_lollipop.svg")
