"""Demo: a Sankey diagram -- Mark.SANKEY, Mark.CHORD's edge list
(Plot.encode_chord()) drawn as nodes in left-to-right columns (a
node's column is the longest path reaching it from any source --
see sankey.mojo's docstring) connected by proportionally sized
flow ribbons. Built via dataviz_mojo.sankey() -- see
examples/scatter.mojo's docstring for what that trades away.

Energy flow from sources to end uses -- the Sankey diagram's classic use case.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import sankey
from dataviz_mojo.theme import Theme


def main() raises:
    var from_stage: List[String] = ["Coal", "Gas", "Coal", "Gas", "Electricity", "Electricity"]
    var to_stage: List[String] = ["Electricity", "Electricity", "Industry", "Industry", "Residential", "Industry"]
    var energy: List[Float64] = [30.0, 20.0, 15.0, 10.0, 25.0, 20.0]

    var c = sankey(from_stage, to_stage, energy)
    save(c, "examples/out_sankey.svg")
    save(c, "examples/out_sankey.bmp")
    save(c, "examples/out_sankey.png")
