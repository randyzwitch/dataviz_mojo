"""Tests for Mark.GRAPH: circular node positioning, straight-line edge
geometry/width, per-from-node color, encode_chord()'s shared
validation (raster + SVG) -- see graph.mojo's docstrings for the
rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import graph

from _test_helpers import BG, _assert_color


def test_render_graph_matches_hand_derived_edges() raises:
    # 3 nodes (A, B, C -- first-seen order across from-then-to),
    # edges A->B (value 10, the domain's max) and B->C (value 5,
    # half that). Canvas 400x300, default theme: plot area x:[60,380],
    # y:[20,250] -> center (220,135), max radius 103.5 (the same
    # no-legend-needed numbers every polar-family mark this session
    # derives for this exact canvas size -- Mark.GRAPH never reserves
    # legend space at all).
    #
    # 3 nodes evenly spaced starting at 12 o'clock, sweeping clockwise
    # (Mark.ARC's convention, reused for position only): A at -90
    # degrees -> (220,32); B at 30 degrees -> (310,187); C at 150
    # degrees -> (130,187) (see this file's SVG test). Edge
    # midpoints (well clear of either endpoint's marker) confirm
    # each edge's color follows its "from" node.
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var c = graph(from_c, to_c, v, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 265, 110, palette[0], "A->B's edge, at its midpoint")
    _assert_color(c, 220, 187, palette[1], "B->C's edge, at its midpoint")
    _assert_color(c, 220, 32, palette[0], "node A's marker")
    _assert_color(c, 310, 187, palette[1], "node B's marker")
    _assert_color(c, 130, 187, palette[2], "node C's marker")


def test_render_graph_svg_matches_confirmed_geometry() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_graph().encode_chord(from_categories=from_c, to_categories=to_c, values=v).theme(Theme())
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="220" y1="32" x2="310" y2="187" stroke="#1f77b4" stroke-width="6.000"' in s,
        "A->B: node A (220,32) to node B (310,187), width 6 (frac 1.0)",
    )
    assert_true(
        '<line x1="310" y1="187" x2="130" y2="187" stroke="#ff7f0e" stroke-width="4.000"' in s,
        "B->C: node B (310,187) to node C (130,187), width 4 (frac 0.5)",
    )


def test_render_graph_self_loop_draws_nothing_but_doesnt_raise() raises:
    var from_c: List[String] = ["A", "A"]
    var to_c: List[String] = ["A", "B"]
    var v: List[Float64] = [5.0, 5.0]
    var c = graph(from_c, to_c, v, width=200, height=150)
    _ = c


def test_render_graph_raises_on_negative_value() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [-1.0]
    with assert_raises():
        _ = graph(from_c, to_c, v, width=200, height=150)


def test_render_graph_raises_on_mismatched_length() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = graph(from_c, to_c, v, width=200, height=150)


def test_render_graph_empty_data_only_fills_background() raises:
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    var c = graph(from_c, to_c, v, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no edges: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
