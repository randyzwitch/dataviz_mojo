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

from canvas_mojo.io.bmp import write_bmp
from canvas_mojo.io.png import write_png
from canvas_mojo.vector.svg import SvgCanvas, write_svg
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo import chord
from dataviz_mojo.theme import Theme


def main() raises:
    var from_regions: List[String] = ["North", "North", "South", "East", "West"]
    var to_regions: List[String] = ["South", "East", "West", "West", "North"]
    var trade_volume: List[Float64] = [12.0, 8.0, 15.0, 6.0, 10.0]

    var c = chord(from_regions, to_regions, trade_volume)
    write_bmp(c, "examples/out_chord.bmp")
    write_png(c, "examples/out_chord.png")

    var svg = SvgCanvas(640, 420)
    var svg_plot = Plot().mark_chord().encode_chord(
        from_categories=from_regions, to_categories=to_regions, values=trade_volume
    ).theme(Theme())
    render_svg(svg, svg_plot)
    write_svg(svg, "examples/out_chord.svg")
