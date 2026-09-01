"""Draw larger points on a scatter plot by overriding `Theme.point_radius`
-- useful for a presentation-scale chart, or simply to make a sparse
scatter read more clearly.
"""
from dataviz.plot import Plot, save
from dataviz.colors import CORNFLOWERBLUE
from dataviz.theme import Theme

def main() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var y: List[Float64] = [12.0, 18.0, 15.0, 22.0, 19.0, 25.0]

    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .labels(title="Bold Points")
        .theme(Theme(mark_color=CORNFLOWERBLUE, point_radius=8.0))
    )
    save(plot, "docs/src/examples/out_bold_points.svg")
