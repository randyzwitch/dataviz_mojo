"""Tests for Mark.TREE (top-to-bottom node-link diagram): leaf/depth
positioning, per-branch edge/marker color, encode_hierarchy()'s shared validation (raster + SVG) -- see tree.mojo's docstrings for
the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import tree

from _test_helpers import BG, _assert_color


def test_render_tree_matches_hand_derived_positions() raises:
    # root -> A, B (both leaves, no grandchildren) -- the simplest
    # non-trivial tree: 2 leaves, max_depth 1. Canvas 400x300, show_
    # legend=False: plot area x:[60,380], y:[20,250] (the standard
    # no-legend numbers every mark this session derives for this
    # exact canvas size). 2 leaves -> A's slot 0 maps to plot_x0
    # (60), B's slot 1 maps to plot_x1 (380); root's slot is
    # the average (0.5), maps to the horizontal center (220). depth 0
    # (root) maps to plot_y0 (20), depth 1 (A, B) to plot_y1 (250) --
    # every number confirmed against a real render_svg() run first
    # (see this file's SVG test).
    var ids: List[String] = ["root", "A", "B"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 1.0, 1.0]
    var t = Theme(show_legend=False)
    var c = tree(ids, parents, values, theme=t, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 220, 20, t.text_color, "root's marker -- no branch, stays text_color")
    _assert_color(c, 60, 250, palette[0], "A's marker -- root's first child, palette[0]")
    _assert_color(c, 380, 250, palette[1], "B's marker -- root's second child, palette[1]")
    # A point along the root->A edge, well clear of either marker's
    # own radius: the edge from (220,20) to (60,250), at its 25%
    # mark -> (220 - 0.25*160, 20 + 0.25*230) = (180, 77.5). The exact
    # fractional y (77.5) sits right on a pixel-row boundary, which
    # AA-blends at y=78 -- y=77 lands solidly on the stroke instead.
    _assert_color(c, 180, 77, palette[0], "along the root->A edge, 25% of the way down")


def test_render_tree_svg_matches_confirmed_geometry() raises:
    var ids: List[String] = ["root", "A", "B"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 1.0, 1.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_tree().encode_hierarchy(ids=ids, parent_ids=parents, values=values).theme(
        Theme(show_legend=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<line x1="220" y1="20" x2="60" y2="250" stroke="#1f77b4"' in s, "root->A edge")
    assert_true('<line x1="220" y1="20" x2="380" y2="250" stroke="#ff7f0e"' in s, "root->B edge")
    assert_true('<circle cx="220" cy="20" r="4" fill="#282828"/>' in s, "root's marker")
    assert_true('<circle cx="60" cy="250" r="4" fill="#1f77b4"/>' in s, "A's marker")
    assert_true('<circle cx="380" cy="250" r="4" fill="#ff7f0e"/>' in s, "B's marker")


def test_render_tree_raises_on_multiple_roots() raises:
    var ids: List[String] = ["a", "b"]
    var parents: List[String] = ["", ""]
    var values: List[Float64] = [1.0, 1.0]
    with assert_raises():
        _ = tree(ids, parents, values, width=200, height=150)


def test_render_tree_raises_on_negative_value() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root"]
    var values: List[Float64] = [0.0, -1.0]
    with assert_raises():
        _ = tree(ids, parents, values, width=200, height=150)


def test_render_tree_raises_on_mismatched_length() raises:
    var ids: List[String] = ["root", "a"]
    var parents: List[String] = ["", "root", "extra"]
    var values: List[Float64] = [0.0, 1.0]
    with assert_raises():
        _ = tree(ids, parents, values, width=200, height=150)


def test_render_tree_empty_data_only_fills_background() raises:
    var ids = List[String]()
    var parents = List[String]()
    var values = List[Float64]()
    var c = tree(ids, parents, values, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no hierarchy: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
