"""Tests for Mark.TREEMAP (slice-and-dice hierarchy chart): the
alternating-axis split, boundary-rounding correctness across two
levels, encode_hierarchy()'s shared validation (raster + SVG) --
see treemap.mojo's docstrings for the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import treemap

from _test_helpers import BG, _assert_color


def test_render_treemap_matches_hand_derived_rects() raises:
    # root -> A (total 30: A1=20, A2=10), root -> B (total 10: B1=10,
    # B's only child). Canvas 400x300, show_legend=False: plot area
    # x:[60,380], y:[20,250] (the standard no-legend numbers every
    # mark this session derives for this exact canvas size).
    #
    # depth 0 (root's children, A/B) splits along x: A gets
    # 30/40=75% of the 320px width -> 240px, x:[60,300]; B gets the
    # remaining 80px, x:[300,380]. depth 1 (A's children) splits
    # along y instead (alternating axis): A1 gets 20/30=66.7% of the
    # 230px height -> 153px, y:[20,173]; A2 gets the rest, y:[173,250].
    # B1, B's only child, gets 100% of B's rect unchanged (see this
    # file's SVG test).
    var ids: List[String] = ["root", "A", "B", "A1", "A2", "B1"]
    var parents: List[String] = ["", "root", "root", "A", "A", "B"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 20.0, 10.0, 10.0]
    var t = Theme(show_legend=False)
    var c = treemap(ids, parents, values, theme=t, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 150, 80, palette[0], "A1's rect, well inside its bounds")
    _assert_color(c, 150, 220, palette[0], "A2's rect, well inside its bounds")
    _assert_color(c, 340, 100, palette[1], "B1's rect (all of B's space), well inside its bounds")


def test_render_treemap_svg_matches_confirmed_rects() raises:
    var ids: List[String] = ["root", "A", "B", "A1", "A2", "B1"]
    var parents: List[String] = ["", "root", "root", "A", "A", "B"]
    var values: List[Float64] = [0.0, 0.0, 0.0, 20.0, 10.0, 10.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_treemap().encode_hierarchy(ids=ids, parent_ids=parents, values=values).theme(
        Theme(show_legend=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="60" y="20" width="240" height="153" fill="#1f77b4"/>' in s, "A1")
    assert_true('<rect x="60" y="173" width="240" height="77" fill="#1f77b4"/>' in s, "A2")
    assert_true('<rect x="300" y="20" width="80" height="230" fill="#ff7f0e"/>' in s, "B1")


def test_render_treemap_raises_on_multiple_roots() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["", ""]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        _ = treemap(ids, parents, values, width=200, height=150)


def test_render_treemap_raises_on_negative_value() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root"]
    var values: List[Float64] = [0.0, -1.0]
    with assert_raises():
        _ = treemap(ids, parents, values, width=200, height=150)


def test_render_treemap_raises_on_all_zero_values() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 0.0, 0.0]
    with assert_raises():
        _ = treemap(ids, parents, values, width=200, height=150)


def test_render_treemap_raises_on_mismatched_length() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root", "extra"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        _ = treemap(ids, parents, values, width=200, height=150)


def test_render_treemap_empty_data_only_fills_background() raises:
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    var c = treemap(ids, parents, values, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no hierarchy: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
