"""Tests for Mark.GAUGE: the needle's angle, the three color-band
sectors, out-of-range value clamping, encode_gauge()'s min/max
validation, and custom breakpoints/band_colors.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from canvas.buffer import Canvas
from dataviz.theme import Theme
from dataviz import gauge, render

from _test_helpers import BG, _assert_color


def test_render_gauge_matches_hand_derived_needle_and_pivot() raises:
    # value=50 over the default [0, 100] range -> fraction 0.5 ->
    # needle angle = 3*pi/4 + 3*pi/2*0.5 = 3*pi/2 (270 degrees) --
    # straight up (`_polar_point`'s convention: 270 degrees is due
    # north, since angle 0 is east and angle increases clockwise).
    # Canvas 400x300, no legend needed (a gauge has one value, nothing
    # to key one by): center (220,135), max radius 103.5 -- the same
    # no-legend numbers test_polar.mojo's tests derive for
    # this exact canvas size. Needle reaches 0.9*103.5=93.15; two
    # points straight up from center (at pixel rows 50 and 42, both
    # well short of that) fall on the needle. The center pivot dot is
    # also theme.mark_color.
    var _hoisted1 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted1)
    var mark_color = Theme().mark_color
    _assert_color(c, 220, 50, mark_color, "needle, straight up from center")
    _assert_color(c, 220, 42, mark_color, "needle, straight up from center (further out)")
    _assert_color(c, 220, 135, mark_color, "the pivot dot at the dial's center")


def test_render_gauge_matches_hand_derived_band_colors() raises:
    # Same center/radius as above. Three points at radius 88 (inside
    # the color band ring, between its 72.45 inner and 103.5 outer
    # radius), one per breakpoint band, each angle chosen well clear
    # of its band boundary and of the needle's angle (so the
    # needle line itself never explains the color): 180 degrees (west,
    # fraction (180-135)/270 = 0.167, inside the default [0, 0.2)
    # green band) -> (132, 135); 200 degrees (fraction 0.241, inside
    # [0.2, 0.8) blue) -> (137, 105); 18 degrees/378 unwrapped
    # (fraction 0.9, inside [0.8, 1.0] red) -> (304, 162).
    var _hoisted2 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted2)
    var breakpoint_colors = [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]
    _assert_color(c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167")
    _assert_color(c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241")
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_leaves_a_gap_at_the_bottom() raises:
    # The dial sweeps 270 degrees (135.405/45), leaving a 90-degree
    # gap centered on due south (90 degrees) -- a point at radius 88
    # straight down from center (220, 223) is neither a band nor the
    # needle: background.
    var _hoisted3 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted3)
    _assert_color(c, 220, 223, BG, "the 90-degree gap at the bottom of the dial")


def test_render_gauge_clamps_values_beyond_the_range() raises:
    # value=1000 (way past max_value=100) clamps to fraction 1.0 ->
    # needle angle 405 degrees (= 45 degrees unwrapped), *not* an
    # error; value=-1000 clamps to fraction 0.0 -> needle angle 135
    # degrees. Both checked at a point along each needle's direction,
    # well short of its 93.15-pixel length.
    var mark_color = Theme().mark_color
    var _hoisted4 = gauge(1000.0, width=400, height=300)
    var high = render(_hoisted4)
    _assert_color(high, 255, 170, mark_color, "clamped to max_value -- needle at 45 degrees")
    var _hoisted5 = gauge(-1000.0, width=400, height=300)
    var low = render(_hoisted5)
    _assert_color(low, 185, 170, mark_color, "clamped to min_value -- needle at 135 degrees")


def test_render_gauge_raises_when_min_value_is_not_less_than_max_value() raises:
    with assert_raises():
        var _hoisted6 = gauge(5.0, min_value=10.0, max_value=10.0, width=200, height=150)
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = gauge(5.0, min_value=10.0, max_value=0.0, width=200, height=150)
        _ = render(_hoisted7)


def test_render_gauge_custom_breakpoints_matches_hand_derived_band_colors() raises:
    # Same center (220,135)/radius (103.5 outer, 72.45 inner) as every
    # other test above -- breakpoints/band_colors only change which
    # color a given angle falls under, not the dial's geometry, so
    # the same three test points reused: (132,135) and (137,105) sit at
    # fractions 0.167/0.241 (both test_render_gauge_matches_hand_
    # derived_band_colors' green/blue bands under the *default*
    # split), which a two-band [0.5, 1.0] split both place in band
    # 0; (304,162) sits at fraction 0.9, in band 1 either way.
    var bps: List[Float64] = [0.5, 1.0]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    var _hoisted8 = gauge(50.0, width=400, height=300, breakpoints=bps, band_colors=cols)
    var c = render(_hoisted8)
    _assert_color(c, 132, 135, cols[0], "band 0, fraction 0.167")
    _assert_color(c, 137, 105, cols[0], "band 0, fraction 0.241")
    _assert_color(c, 304, 162, cols[1], "band 1, fraction 0.9")


def test_render_gauge_custom_breakpoints_default_empty_matches_original() raises:
    # Leaving breakpoints/band_colors at their default (empty lists)
    # must reproduce the fixed 20%/80%/100% green/blue/red default
    # exactly -- the same "purely additive" guarantee every other
    # optional feature in this package makes. Same test points/colors
    # as test_render_gauge_matches_hand_derived_band_colors, called
    # through the explicit-empty-list form instead of omitting the
    # parameters, so this exercises the actual sentinel-check code path.
    var empty_bps = List[Float64]()
    var empty_cols = List[Color]()
    var _hoisted9 = gauge(50.0, width=400, height=300, breakpoints=empty_bps, band_colors=empty_cols)
    var c = render(_hoisted9)
    var breakpoint_colors = [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]
    _assert_color(c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167")
    _assert_color(c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241")
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_raises_on_mismatched_breakpoints_and_band_colors_length() raises:
    var bps: List[Float64] = [0.5, 1.0]
    var cols: List[Color] = [Color(10, 20, 30)]
    with assert_raises():
        var _hoisted10 = gauge(50.0, width=200, height=150, breakpoints=bps, band_colors=cols)
        _ = render(_hoisted10)


def test_render_gauge_raises_on_non_ascending_breakpoints() raises:
    var bps: List[Float64] = [0.5, 0.3]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    with assert_raises():
        var _hoisted11 = gauge(50.0, width=200, height=150, breakpoints=bps, band_colors=cols)
        _ = render(_hoisted11)


def test_render_gauge_raises_on_out_of_range_breakpoint() raises:
    var too_high: List[Float64] = [0.5, 1.5]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    with assert_raises():
        var _hoisted12 = gauge(50.0, width=200, height=150, breakpoints=too_high, band_colors=cols)
        _ = render(_hoisted12)
    var zero_start: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted13 = gauge(50.0, width=200, height=150, breakpoints=zero_start, band_colors=cols)
        _ = render(_hoisted13)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
