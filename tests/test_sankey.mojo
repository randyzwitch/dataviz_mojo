"""Tests for Mark.SANKEY: column (longest-path) layout, node/ribbon
geometry, skip-edge pass-through routing, cycle detection, encode_
chord()'s shared validation (raster + SVG) -- see sankey.mojo's docstrings for the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import sankey

from _test_helpers import BG, _assert_color


def test_render_sankey_matches_hand_derived_nodes_and_ribbon() raises:
    # 2 nodes (A, B), one edge A->B (value 10 -- both node's entire inflow/outflow, so no imbalance gap). Canvas 400x300,
    # default theme: plot area x:[60,380], y:[20,250]. 2 columns
    # (A at column 0, B at column 1): node width 12, column x
    # positions 60 (column 0) and 368 (column 1, pulled in by one
    # node-width so the last column's node doesn't clip past
    # plot_x1). Node A's rect: (60,20,12,230); node B's rect:
    # (368,20,12,230) -- both fill the plot's full height (the
    # only node in their column). The ribbon fills the gap
    # between them, (72,20)-(72,250)-(368,250)-(368,20), colored by
    # its "from" node (A). Every number confirmed against a real
    # render_svg() run first (see this file's SVG test).
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [10.0]
    var c = sankey(from_c, to_c, v, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 66, 135, palette[0], "node A's rect")
    _assert_color(c, 220, 135, palette[0], "the ribbon, well inside its bounds")
    _assert_color(c, 374, 135, palette[1], "node B's rect")


def test_render_sankey_svg_matches_confirmed_geometry() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [10.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_sankey().encode_chord(from_categories=from_c, to_categories=to_c, values=v).theme(
        Theme()
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M72.000,20.000 L72.000,250.000 L368.000,250.000 L368.000,20.000 Z" fill="#1f77b4"/>' in s,
        "the ribbon, A's column edge to B's column edge",
    )
    assert_true('<rect x="60" y="20" width="12" height="230" fill="#1f77b4"/>' in s, "node A")
    assert_true('<rect x="368" y="20" width="12" height="230" fill="#ff7f0e"/>' in s, "node B")


def test_render_sankey_skip_edge_routes_through_a_pass_through_node() raises:
    # A->B (col0->col1), B->C (col1->col2), and D->C directly (col0->
    # col2, a skip edge -- gap 2) -- every value 10, so every node/
    # pass-through node splits its column exactly in half. Canvas
    # 400x300, same no-legend plot area (x:[60,380], y:[20,250]) and
    # column x positions (60/214/368 for 3 columns, node width 12) the
    # 2-column test above already derives, extended to a third column.
    #
    # Column 0 members in node-index order (A=0, D=2): A gets the top
    # half (y 20-135), D the bottom half (135-250). Column 1 members
    # (B=1, then D's pass-through node, appended after every real
    # node): B gets the top half, the pass-through node the bottom
    # half -- competing for column-1 space exactly like a real node,
    # even though it draws no bar of its own. Column 2 has only C,
    # spanning the full height.
    #
    # Ribbons: A->B fills column0-1's top half (blue, A's color); B->C fills column1-2's top half (orange); D's skip edge becomes two chained segments, D->pass-through
    # (column0-1's bottom half) and pass-through->C (column1-2's
    # own bottom half), *both* colored green (D's color, the
    # flow's original source) even though the second segment's immediate `from` is the invisible pass-through node, not D
    # itself. Every point confirmed via a real render() run first.
    var from_c: List[String] = ["A", "B", "D"]
    var to_c: List[String] = ["B", "C", "C"]
    var v: List[Float64] = [10.0, 10.0, 10.0]
    var c = sankey(from_c, to_c, v, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 66, 77, palette[0], "node A's rect (column 0, top half)")
    _assert_color(c, 66, 192, palette[2], "node D's rect (column 0, bottom half)")
    _assert_color(c, 220, 77, palette[1], "node B's rect (column 1, top half)")
    _assert_color(c, 374, 135, palette[3], "node C's rect (column 2, full height)")
    _assert_color(c, 143, 77, palette[0], "A->B ribbon, column 0-1 gap, top half")
    _assert_color(c, 297, 77, palette[1], "B->C ribbon, column 1-2 gap, top half")
    _assert_color(
        c, 143, 192, palette[2], "D's skip edge, first segment (D -> pass-through), still D's color"
    )
    _assert_color(
        c, 297, 192, palette[2], "D's skip edge, second segment (pass-through -> C), still D's color"
    )
    # The one point that actually distinguishes this from the pre-fix
    # behavior: (220, 192) sits inside column 1's node-width strip
    # (x 214-226), in its bottom half -- the pass-through node's
    # own reserved slot. Nothing draws there (no bar for an invisible
    # pass-through node, and neither ribbon segment crosses the node-
    # width gap itself) -- background. Before this fix, D's skip
    # edge drew as one straight ribbon with no pass-through node
    # reserving column 1 space at all, so B's bar -- the column's
    # only "real" member -- claimed the *entire* column height instead
    # of just its top half, painting orange here (confirmed by
    # deliberately reverting to that behavior and re-probing before
    # writing this assertion).
    _assert_color(c, 220, 192, BG, "the pass-through node's reserved slot -- background, not node B's bar")


def test_render_sankey_raises_on_cycle() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "A"]
    var v: List[Float64] = [5.0, 5.0]
    with assert_raises():
        _ = sankey(from_c, to_c, v, width=200, height=150)


def test_render_sankey_self_loop_doesnt_raise() raises:
    var from_c: List[String] = ["A", "A"]
    var to_c: List[String] = ["A", "B"]
    var v: List[Float64] = [5.0, 5.0]
    var c = sankey(from_c, to_c, v, width=200, height=150)
    _ = c


def test_render_sankey_raises_on_negative_value() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [-1.0]
    with assert_raises():
        _ = sankey(from_c, to_c, v, width=200, height=150)


def test_render_sankey_raises_on_mismatched_length() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = sankey(from_c, to_c, v, width=200, height=150)


def test_render_sankey_empty_data_only_fills_background() raises:
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    var c = sankey(from_c, to_c, v, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no edges: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
