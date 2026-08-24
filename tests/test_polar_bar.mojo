"""Tests for Mark.POLAR_BAR (circular column chart): equal-slot bar
colors, the angular gap between bars, SVG bar paths.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import polarbar

from _test_helpers import BG, _assert_color


def test_render_polar_bar_matches_hand_derived_bar_colors() raises:
    # Three equal-value categories -- same equal-angle slots (2*pi/3,
    # bisectors -30/90/210 degrees) and center/radius (400x300,
    # default margins, single-char labels -> center (155,135), max
    # radius 85.5) test_nightingale.mojo's three-category case
    # uses -- the 20% angular padding narrows each bar's span
    # around that same bisector but doesn't move it, so the same
    # radius-50 test points along each bisector stay inside their bar.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var c = polarbar(x, y, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 198, 110, palette[0], "bar 0, bisector -30 degrees")
    _assert_color(c, 155, 185, palette[1], "bar 1, bisector 90 degrees (straight down)")
    _assert_color(c, 112, 110, palette[2], "bar 2, bisector 210 degrees")


def test_render_polar_bar_leaves_a_gap_between_bars() raises:
    # Same three-category setup as above. Slot boundaries sit at
    # -90/30/150 degrees; the 20% padding (_POLAR_BAR_PADDING) carves
    # a 24-degree gap (2*pi/3 * 0.2) centered on each boundary, so at
    # radius 50 along the boundary between bar 0 and bar 1 (angle 30
    # degrees exactly -- offset (155 + 50*cos(30), 135 + 50*sin(30)) =
    # (198.3, 160)) neither bar has reached yet: background, not
    # either bar's color -- the one thing that actually distinguishes
    # this mark from Mark.NIGHTINGALE's edge-to-edge wedges (see
    # test_nightingale.mojo, which has no such gap to test).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var c = polarbar(x, y, width=400, height=300)
    _assert_color(c, 198, 160, BG, "the gap between bar 0 and bar 1, at their shared slot boundary")


def test_render_polar_bar_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    with assert_raises():
        _ = polarbar(x, y, width=200, height=150)


def test_render_polar_bar_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    with assert_raises():
        _ = polarbar(x, y, width=200, height=150)


def test_render_polar_bar_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = polarbar(x, y, width=200, height=150)


def test_render_polar_bar_empty_categories_only_fills_background() raises:
    var x = List[String]()
    var y = List[Float64]()
    var c = polarbar(x, y, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
