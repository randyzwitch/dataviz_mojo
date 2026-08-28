"""Demo: a treemap -- Mark.TREEMAP, a hierarchy (Plot.encode_
hierarchy(), the same flattened id/parent_id/value shape Mark.SUNBURST/
TREE use -- see treemap.mojo's docstring) laid out as nested,
area-proportional rectangles via slice-and-dice. Built via
dataviz_mojo.treemap() -- see examples/scatter.mojo's docstring
for what that trades away.

Disk usage by folder -- the exact same data Mark.SUNBURST's example uses, so the two chart types' different readings of the
identical hierarchy (radial rings vs. nested rectangles) are easy to
compare directly.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import treemap
from dataviz_mojo.theme import Theme


def main() raises:
    var ids: List[String] = ["root", "src", "docs", "main.py", "utils.py", "guide.md", "api.md"]
    var parent_ids: List[String] = ["", "root", "root", "src", "src", "docs", "docs"]
    var sizes: List[Float64] = [0.0, 0.0, 0.0, 45.0, 20.0, 12.0, 8.0]

    var c = treemap(ids, parent_ids, sizes)
    save(c, "examples/out_treemap.svg")
    save(c, "examples/out_treemap.bmp")
    save(c, "examples/out_treemap.png")
