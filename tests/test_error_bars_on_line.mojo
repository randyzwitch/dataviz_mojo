"""Tests for Plot.encode(y_err=...) on Mark.LINE (#140 was Mark.POINT/
EFFECT_SCATTER only): a whisker per original data point, drawn in
Theme.mark_color (Mark.LINE has no per-point color the way Mark.POINT's
color/color_categories channels do), independent of _draw_line_layer's
own point-decimation for the stroked path. Hand-derived pixel positions
and confirmation Mark.AREA (still excluded) raises.
"""

from std.testing import assert_raises, assert_true, TestSuite

from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo.colors import TOMATO


def test_render_svg_line_error_bar_matches_hand_derived_positions() raises:
    # Two points, x=[1,2], y=[10,10], y_err=[2,2] -- domain data becomes
    # [8, 12] (widened to the whisker endpoints), span 4, padded 5%
    # (0.2) -> domain [7.8, 12.2]. Canvas 400x200, default theme ->
    # plot_y0 = margin_top (20), plot_y1 = height - margin_bottom
    # (200-50=150).
    #
    # scale() = (20-150)/(12.2-7.8) = -130/4.4 = -29.5454...
    # translate() = 150 - 7.8*scale() = 380.4545...
    # to_pixel(8)  (bottom whisker end) = 144.09... -> rounds to 144
    # to_pixel(12) (top whisker end)    = 25.909...  -> rounds to 26
    # to_pixel(10) (the line itself, both points)    = 85.0 exactly
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 10.0]
    var err: List[Float64] = [2.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err=err).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true('y1="144"' in s and 'y2="144"' in s, "the bottom whisker/cap sits at y-2's hand-derived row")
    assert_true('y1="26"' in s and 'y2="26"' in s, "the top whisker/cap sits at y+2's hand-derived row")
    assert_true('85.000' in s, "the line itself passes through y=10's own row (85)")


def test_render_svg_line_error_bar_uses_theme_mark_color() raises:
    # Mark.LINE has no per-point color channel -- every whisker must
    # use the plain Theme.mark_color, the same ink the line strokes
    # with, not a fixed default unrelated to the chart's own color.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err=err).theme(Theme(mark_color=TOMATO))
    var s = render_svg(plot).to_string()
    assert_true('stroke="#ff6347"' in s, "the whisker uses the chart's own Theme.mark_color")


def test_render_raises_on_y_err_with_mark_area() raises:
    # Mark.AREA stays excluded (its own zero-baseline forcing is a
    # separate concern from this issue, not addressed here).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_area().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
