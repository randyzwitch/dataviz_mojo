"""Draw a violin plot with categories running top-to-bottom and each
silhouette bulging up-down around its own row instead of the default
vertical layout -- `Plot.mark_violin(horizontal=True)`/`violin(...,
horizontal=True)`, the same "long or many category names" use case
`horizontal_bar` covers.
"""
from dataviz.plot import Plot, save


def main() raises:
    var classes: List[String] = ["Section A", "Section B", "Section C"]
    var scores: List[List[Int]] = [
        [72, 75, 78, 80, 74, 76, 91],
        [65, 70, 72, 88, 90, 92, 95],
        [80, 82, 83, 84, 81, 79, 85],
    ]

    var plot = (
        Plot()
        .mark_violin(horizontal=True)
        .encode_distribution(categories=classes, values=scores)
    )
    save(plot, "docs/src/examples/out_horizontal_violin.svg")
