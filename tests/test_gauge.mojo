"""Tests for Mark.GAUGE: the needle's own angle, the three color-band
sectors, out-of-range value clamping, encode_gauge()'s own min/max
validation.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.theme import Theme
from dataviz_mojo import gauge

from _test_helpers import BG, _assert_color


def test_render_gauge_matches_hand_derived_needle_and_pivot() raises:
    # value=50 over the default [0, 100] range -> fraction 0.5 ->
    # needle angle = 3*pi/4 + 3*pi/2*0.5 = 3*pi/2 (270 degrees) --
    # straight up (`_polar_point`'s own convention: 270 degrees is due
    # north, since angle 0 is east and angle increases clockwise).
    # Canvas 400x300, no legend needed (a gauge has one value, nothing
    # to key one by): center (220,135), max radius 103.5 -- the same
    # no-legend numbers test_polar.mojo's own tests already derive for
    # this exact canvas size. Needle reaches 0.9*103.5=93.15; two
    # points straight up from center (at pixel rows 50 and 42, both
    # well short of that) confirmed via a real render() run to fall on
    # the needle. The center pivot dot is also theme.mark_color.
    var c = gauge(50.0, width=400, height=300)
    var mark_color = Theme().mark_color
    _assert_color(c, 220, 50, mark_color, "needle, straight up from center")
    _assert_color(c, 220, 42, mark_color, "needle, straight up from center (further out)")
    _assert_color(c, 220, 135, mark_color, "the pivot dot at the dial's own center")


def test_render_gauge_matches_hand_derived_band_colors() raises:
    # Same center/radius as above. Three points at radius 88 (inside
    # the color band ring, between its own 72.45 inner and 103.5 outer
    # radius), one per breakpoint band, each angle chosen well clear
    # of its own band boundary and of the needle's own angle (so the
    # needle line itself never explains the color): 180 degrees (west,
    # fraction (180-135)/270 = 0.167, inside the default [0, 0.2)
    # green band) -> (132, 135); 200 degrees (fraction 0.241, inside
    # [0.2, 0.8) blue) -> (137, 105); 18 degrees/378 unwrapped
    # (fraction 0.9, inside [0.8, 1.0] red) -> (304, 162). All three
    # confirmed via a real render() run first.
    var c = gauge(50.0, width=400, height=300)
    var breakpoint_colors = [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]
    _assert_color(c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167")
    _assert_color(c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241")
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_leaves_a_gap_at_the_bottom() raises:
    # The dial sweeps 270 degrees (135..405/45), leaving a 90-degree
    # gap centered on due south (90 degrees) -- a point at radius 88
    # straight down from center (220, 223) is neither a band nor the
    # needle: background.
    var c = gauge(50.0, width=400, height=300)
    _assert_color(c, 220, 223, BG, "the 90-degree gap at the bottom of the dial")


def test_render_gauge_clamps_values_beyond_the_range() raises:
    # value=1000 (way past max_value=100) clamps to fraction 1.0 ->
    # needle angle 405 degrees (= 45 degrees unwrapped), *not* an
    # error; value=-1000 clamps to fraction 0.0 -> needle angle 135
    # degrees. Both confirmed via a real render() run at a point along
    # each needle's own direction, well short of its own 93.15-pixel
    # length.
    var mark_color = Theme().mark_color
    var high = gauge(1000.0, width=400, height=300)
    _assert_color(high, 255, 170, mark_color, "clamped to max_value -- needle at 45 degrees")
    var low = gauge(-1000.0, width=400, height=300)
    _assert_color(low, 185, 170, mark_color, "clamped to min_value -- needle at 135 degrees")


def test_render_gauge_raises_when_min_value_is_not_less_than_max_value() raises:
    with assert_raises():
        _ = gauge(5.0, min_value=10.0, max_value=10.0, width=200, height=150)
    with assert_raises():
        _ = gauge(5.0, min_value=10.0, max_value=0.0, width=200, height=150)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
