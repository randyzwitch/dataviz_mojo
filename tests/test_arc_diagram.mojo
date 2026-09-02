"""Tests for Mark.ARC_DIAGRAM: node line-up positions, semicircular
edge-arc geometry/width, per-from-node color, encode_chord()'s shared validation (raster + SVG) -- see arc_diagram.mojo's docstrings for the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from canvas.vector.svg import SvgCanvas
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import arc_diagram

from _test_helpers import BG, _assert_color


def test_render_arc_diagram_matches_hand_derived_arcs() raises:
    # 3 nodes (A, B, C -- first-seen order across from-then-to:
    # "A","B" then "B","C"), edges A->B (value 10, the domain's max) and B->C (value 5, half that). Canvas 400x300, default
    # theme: plot area x:[60,380], y:[20,250] -> 3 evenly spaced nodes
    # at x=60/220/380, all on the shared baseline y=250 (the bottom of
    # the inner plot rect).
    #
    # Edge A->B: center (140,250), radius 80 -- its peak (the
    # semicircle's top point, straight up from center) is (140,
    # 170). Edge B->C: center (300,250), radius 80, peak (300,170).
    # Edge width: A->B at frac 10/10=1.0 -> line_width + line_width*2
    # = 6; B->C at frac 5/10=0.5 -> line_width + line_width = 4 (not
    # directly asserted here, confirmed in this file's SVG test
    # instead, where the exact stroke-width is visible in the path
    # markup).
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var _hoisted1 = arc_diagram(from_c, to_c, v, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 140, 170, palette[0], "A->B's arc, at its peak")
    _assert_color(c, 300, 170, palette[1], "B->C's arc, at its peak")
    _assert_color(c, 60, 250, palette[0], "node A's marker")
    _assert_color(c, 220, 250, palette[1], "node B's marker")
    _assert_color(c, 380, 250, palette[2], "node C's marker")


def test_render_arc_diagram_svg_matches_confirmed_geometry() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B", "C"]
    var v: List[Float64] = [10.0, 5.0]
    var plot = Plot().mark_arc_diagram().encode_chord(from_categories=from_c, to_categories=to_c, values=v).theme(
        Theme()
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M60.000,250.000 A80.000,80.000 0 1,1 220.000,250.000" fill="none" stroke="#1f77b4"'
        ' stroke-width="6.000"' in s,
        "A->B's arc: center (140,250), radius 80, width 6 (frac 1.0)",
    )
    assert_true(
        '<path d="M220.000,250.000 A80.000,80.000 0 1,1 380.000,250.000" fill="none" stroke="#ff7f0e"'
        ' stroke-width="4.000"' in s,
        "B->C's arc: center (300,250), radius 80, width 4 (frac 0.5)",
    )


def test_render_arc_diagram_self_loop_draws_nothing_but_doesnt_raise() raises:
    var from_c: List[String] = ["A", "A"]
    var to_c: List[String] = ["A", "B"]
    var v: List[Float64] = [5.0, 5.0]
    # No assertion failure/raise means the self-loop (A->A) was safely
    # skipped rather than crashing on a zero-diameter arc.
    var _hoisted2 = arc_diagram(from_c, to_c, v, width=200, height=150)
    var c = render(_hoisted2)
    _ = c


def test_render_arc_diagram_raises_on_negative_value() raises:
    var from_c: List[String] = ["A"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted3 = arc_diagram(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted3)


def test_render_arc_diagram_raises_on_mismatched_length() raises:
    var from_c: List[String] = ["A", "B"]
    var to_c: List[String] = ["B"]
    var v: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted4 = arc_diagram(from_c, to_c, v, width=200, height=150)
        _ = render(_hoisted4)


def test_render_arc_diagram_empty_data_only_fills_background() raises:
    var from_c = List[String]()
    var to_c = List[String]()
    var v = List[Float64]()
    var _hoisted5 = arc_diagram(from_c, to_c, v, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no edges: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
