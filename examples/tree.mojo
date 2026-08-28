"""Demo: a tree diagram -- Mark.TREE, a hierarchy (Plot.encode_
hierarchy(), the same flattened id/parent_id/value shape Mark.SUNBURST
uses -- see tree.mojo's docstring) drawn top-to-bottom as a
node-link diagram instead of Mark.SUNBURST's radial rings. Built
via dataviz_mojo.tree() -- see examples/scatter.mojo's docstring
for what that trades away.

An org chart -- the tree diagram's classic use, two departments
each with their reports.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import tree
from dataviz_mojo.theme import Theme


def main() raises:
    var ids: List[String] = [
        "CEO", "Engineering", "Sales", "Backend", "Frontend", "Enterprise", "SMB",
    ]
    var parent_ids: List[String] = ["", "CEO", "CEO", "Engineering", "Engineering", "Sales", "Sales"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]

    var c = tree(ids, parent_ids, values)
    save(c, "examples/out_tree.svg")
    save(c, "examples/out_tree.bmp")
    save(c, "examples/out_tree.png")
