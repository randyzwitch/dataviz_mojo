"""Demo: a chord diagram -- Mark.CHORD, ring sectors for every distinct
node across an edge list's from/to columns, connected by ribbons
sized by each flow's value (Plot.encode_chord(), one row per flow
-- see that method's docstring). Reuses Mark.ARC's start-at-
12-o'clock, sweep-clockwise ring-sector convention for nodes; ribbons
are drawn as curved filled paths through DrawTarget.
fill_path_aa (chord.mojo's _draw_chord_ribbon). Built via
dataviz_mojo.chord() -- see examples/scatter.mojo's docstring for
what that trades away.

Trade flows between four regions -- the classic chord-diagram use (who
sends how much to whom), though the mark itself is generic to any
weighted edge list.
"""

from dataviz_mojo.plot import save
from dataviz_mojo import chord
from dataviz_mojo.theme import Theme


def main() raises:
    var from_regions: List[String] = ["North", "North", "South", "East", "West"]
    var to_regions: List[String] = ["South", "East", "West", "West", "North"]
    var trade_volume: List[Float64] = [12.0, 8.0, 15.0, 6.0, 10.0]

    var c = chord(from_regions, to_regions, trade_volume)
    save(c, "examples/out_chord.svg")
    save(c, "examples/out_chord.bmp")
    save(c, "examples/out_chord.png")
