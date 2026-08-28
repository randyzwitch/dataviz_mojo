"""Demo: a radial (multi-ring) progress chart -- Mark.RADIALBAR, one
full concentric ring per category (Plot.encode_categorical(), the same
category + value shape pie()/bar()/polarbar() use), each ring swept
clockwise from 12 o'clock to value/max(values) of the way around a
light-gray track. Built via dataviz_mojo.radialbar() -- see examples/
scatter.mojo's docstring for what that trades away.

Quarterly OKR completion by team -- four teams, each a percentage of
their quarter's objectives completed, drawn as nested "activity
rings" (the first team's ring outermost) instead of a bar chart,
so all four read together as one shape at a glance.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import radialbar
from dataviz_mojo.theme import Theme


def main() raises:
    var teams: List[String] = ["Platform", "Growth", "Data", "Design"]
    var completion: List[Float64] = [92.0, 78.0, 45.0, 60.0]

    var c = radialbar(teams, completion)
    save(c, "examples/out_radialbar.svg")
    save(c, "examples/out_radialbar.bmp")
    save(c, "examples/out_radialbar.png")
