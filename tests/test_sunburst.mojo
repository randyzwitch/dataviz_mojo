"""Tests for Mark.SUNBURST: ring-sector geometry per depth level,
encode_hierarchy()'s shared validation (raster + SVG) -- see
sunburst.mojo's docstrings for the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import sunburst

from _test_helpers import BG, _assert_color


def test_render_sunburst_matches_hand_derived_ring_sectors() raises:
    # root -> A (50% of root) -> A1/A2 (50/50 split of A's span);
    # root -> B (50% of root) -> B1 (100% of B's span, B's only
    # child). Canvas 400x300, show_legend=False: plot area x:[60,380],
    # y:[20,250] -> center (220,135), max radius 103.5 (the same no-
    # legend numbers every polar-family test this session already
    # derives for this exact canvas size). max_depth=2 -> ring_width
    # 51.75: ring 1 spans [0,51.75], ring 2 spans [51.75,103.5].
    #
    # A spans -90.90 degrees (bisector 0, due east); B spans 90.270
    # (bisector 180, due west). A1 spans -90.0 (bisector -45); A2
    # spans 0.90 (bisector 45); B1 spans A's full 90.270 (same
    # as B itself, bisector 180). Every one of the 5 points below (2
    # per branch's ring 2, 1 more each ring 1, all at a radius
    # safely inside their ring, away from any boundary) confirmed
    # against a real render() run first.
    var ids: List[String] = ["root", "A", "B", "A1", "A2", "B1"]
    var parents: List[String] = ["", "root", "root", "A", "A", "B"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 1.0, 1.0, 2.0]
    var t = Theme(show_legend=False)
    var c = sunburst(ids, parents, values, theme=t, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 277, 78, palette[0], "A1, ring 2, bisector -45 degrees")
    _assert_color(c, 277, 192, palette[0], "A2, ring 2, bisector 45 degrees")
    _assert_color(c, 140, 135, palette[1], "B1, ring 2, bisector 180 degrees")
    _assert_color(c, 250, 135, palette[0], "A, ring 1, bisector 0 degrees")
    _assert_color(c, 190, 135, palette[1], "B, ring 1, bisector 180 degrees")


def test_render_sunburst_raises_on_multiple_roots() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["", ""]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_no_root() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["b", "a"]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_unresolved_parent_id() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "missing"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_duplicate_id() raises:
    var ids: List[String] = ["root", "a", "a"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 1.0, 1.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_negative_value() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root"]
    var values: List[Float64] = [0.0, -1.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_all_zero_values() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 0.0, 0.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_mismatched_length() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root", "extra"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_empty_data_only_fills_background() raises:
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    var c = sunburst(ids, parents, values, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no hierarchy: nothing drawn but the background")


def test_render_sunburst_raises_on_a_cycle() raises:
    # "a" and "b" are each other's parent. Every other check passes --
    # no duplicate ids, both parent_ids resolve, exactly one empty-
    # parent root -- so nothing but a reachability check catches this.
    # Before that check existed, the traversal simply never reached
    # either row and both silently vanished from the chart, taking 16
    # of the 21 total value with them.
    var ids: List[String] = ["root", "leaf", "a", "b"]
    var parents: List[String] = ["", "root", "b", "a"]
    var values: List[Float64] = [0.0, 5.0, 7.0, 9.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def test_render_sunburst_raises_on_a_disconnected_component() raises:
    # A self-parented row: "orphan" is its parent, so it resolves
    # and is never reachable. The degenerate one-node case of the same
    # cycle bug above, caught by the same check.
    var ids: List[String] = ["root", "orphan"]
    var parents: List[String] = ["", "orphan"]
    var values: List[Float64] = [0.0, 3.0]
    with assert_raises():
        _ = sunburst(ids, parents, values, width=200, height=150)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
