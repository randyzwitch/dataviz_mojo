"""Tests for Plot.encode()'s y_err_lower/y_err_upper channels: an
asymmetric error-bar whisker, mutually exclusive with the existing
symmetric y_err (#140), given together or not at all. Hand-derived
pixel positions confirming the whisker is genuinely asymmetric (not
silently falling back to a symmetric one), the y-domain widening to
each bound's own endpoint, and every raise path.
"""

from std.testing import assert_raises, assert_true, TestSuite

from dataviz_mojo.plot import Plot, render, render_svg


def test_render_svg_asymmetric_error_bar_matches_hand_derived_positions() raises:
    # One point, x=1, y=10, y_err_lower=2, y_err_upper=6 -- a genuinely
    # asymmetric whisker from 8 to 16 (not a symmetric +/-4 or +/-2).
    # Domain data becomes [8, 16] (widened to the whisker's own
    # endpoints, same "everything actually drawn" rule the symmetric
    # case already has), span 8, padded 5% (0.4) -> domain [7.6, 16.4].
    # Canvas 400x200, default theme -> plot_y0 = margin_top (20),
    # plot_y1 = height - margin_bottom (200-50=150).
    #
    # scale() = (20-150)/(16.4-7.6) = -130/8.8 = -14.7727...
    # translate() = 150 - 7.6*scale() = 262.2727...
    # to_pixel(8)  (bottom, y - y_err_lower) = 144.0909... -> rounds to 144
    # to_pixel(16) (top, y + y_err_upper)    = 25.909...   -> rounds to 26
    # to_pixel(10) (the point itself)        = 114.545...  -> rounds to 115
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var lower: List[Float64] = [2.0]
    var upper: List[Float64] = [6.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true('cy="115"' in s, "the point itself lands at the hand-derived pixel row")
    assert_true('y1="144"' in s and 'y2="144"' in s, "the lower whisker/cap sits at y-2's hand-derived row")
    assert_true('y1="26"' in s and 'y2="26"' in s, "the upper whisker/cap sits at y+6's hand-derived row")


def test_render_raises_when_only_y_err_lower_is_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_lower=lower)
    with assert_raises():
        _ = render(plot)


def test_render_raises_when_only_y_err_upper_is_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def test_render_raises_when_y_err_and_asymmetric_bounds_are_both_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var sym: List[Float64] = [1.0, 1.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=sym, y_err_lower=lower, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_negative_asymmetric_value() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, -1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_asymmetric_bounds_with_an_incompatible_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
