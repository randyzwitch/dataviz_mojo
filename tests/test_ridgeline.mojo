"""Tests for Mark.RIDGELINE: overlapping kernel-density-estimate rows
(raster + SVG) -- see ridgeline.mojo's own docstrings for the
baseline/overlap rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import ridgeline

from _test_helpers import BG, _assert_color


def test_render_ridgeline_matches_hand_derived_rows() raises:
    # 3 categories ("A", "B", "C"), all the same symmetric values
    # [1,2,3,4,5] -- the exact same distribution Mark.VIOLIN's own test
    # uses, so the KDE math itself (bandwidth, per-sample density) is
    # already independently cross-checked there; this test is about
    # the horizontal-frame geometry and row baselines/overlap, not the
    # KDE formula again. Canvas 400x300, show_gridlines=False, default
    # margins (short "A"/"B"/"C" row labels keep the dynamic left
    # margin at 60) -> plot area x:[60,380], y:[20,250].
    # _draw_horizontal_categorical_axis_frame (Mark.GANTT's own core,
    # called with padding=0.0 -- see that function's own docstring for
    # why a ridgeline needs edge-to-edge rows, not its 0.2 default):
    # 3-category OrdinalScale y-axis, step=(250-20)/3=76.667,
    # bandwidth=step (no padding to subtract) -- row A's own baseline
    # (band_start(0) + row height) = 96.667, row B's = 173.333, row
    # C's = 250.0 -- every number confirmed against a real
    # render_svg() run before trusting it (see this file's own SVG
    # test for the exact path data).
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0],
    ]
    var t = Theme(show_gridlines=False)
    var c = ridgeline(cats, vals, theme=t, width=400, height=300)

    _assert_color(c, 220, 50, t.mark_color, "inside row A -- between its own peak (~-3) and baseline (96.667)")
    _assert_color(
        c, 220, 98, t.mark_color,
        "just below row A's own baseline (96.667) -- covered by row B's own peak rising up to ~73.667,"
        " the edge-to-edge overlap padding=0.0 fixed (this exact point used to be a background gap)",
    )
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_ridgeline_svg_matches_confirmed_path_points() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0],
    ]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_ridgeline().encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<path d="M75.000,96.667 L75.000,24.955' in s, "row A's own baseline and left-edge rise")
    assert_true('225.000,-3.000' in s, "row A's own peak, at its own two middle samples")
    assert_true('L365.000,96.667 Z' in s, "row A's own closing edge, back down to baseline")
    assert_true('<path d="M75.000,173.333 L75.000,101.622' in s, "row B's own baseline and left-edge rise")
    assert_true('<path d="M75.000,250.000 L75.000,178.289' in s, "row C's own baseline and left-edge rise")


def test_render_ridgeline_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        _ = ridgeline(cats, vals, width=200, height=150)


def test_render_ridgeline_raises_on_empty_category_distribution() raises:
    var cats: List[String] = ["a"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        _ = ridgeline(cats, vals, width=200, height=150)


def test_render_ridgeline_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var c = ridgeline(cats, vals, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
