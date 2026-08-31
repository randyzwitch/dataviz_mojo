"""Tests for Plot.encode()'s y_err channel: symmetric error-bar
whiskers on Mark.POINT/EFFECT_SCATTER, drawn in each point's own
resolved color (see encode()'s own docstring). Hand-derived pixel
positions for the whisker/cap placement, the y-domain correctly
widening to include each whisker's own endpoint (not just the raw
point), and every raise path (negative y_err, a length mismatch, and
y_err on an incompatible mark).
"""

from std.testing import assert_raises, assert_true, TestSuite

from dataviz_mojo.plot import Plot, render, render_svg


def test_render_svg_error_bar_matches_hand_derived_positions() raises:
    # One point, x=1, y=10, y_err=2 -- domain data becomes [8, 12]
    # (_data_extent's own "everything actually drawn" rule -- see
    # _render_generic's y_domain_data comment), padded 5% of that span
    # (4.0) -> domain [7.8, 12.2]. Canvas 400x200, default theme -> plot_y0 = margin_top (20), plot_y1 = height - margin_bottom
    # (200-50=150).
    #
    # scale() = (20-150)/(12.2-7.8) = -130/4.4 = -29.5454...
    # translate() = 150 - 7.8*scale() = 380.4545...
    # to_pixel(8.0)  (bottom whisker end) = 144.0909... -> rounds to 144
    # to_pixel(12.0) (top whisker end)    = 25.909...   -> rounds to 26
    # to_pixel(10.0) (the point itself)   = 85.0 exactly
    #
    # Asserted as `cy="..."`/`y1="..."`/`y2="..."` substrings, not full
    # tags -- `cx`/`x1`/`x2` depend on the dynamic left margin (sized
    # off the y-tick label text width), unrelated to this test's own
    # subject and already covered by every other continuous-axis test.
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [2.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true('cy="85"' in s, "the point itself lands at the hand-derived pixel row")
    assert_true('y1="144"' in s and 'y2="144"' in s, "the bottom whisker/cap sits at y-2's hand-derived row")
    assert_true('y1="26"' in s and 'y2="26"' in s, "the top whisker/cap sits at y+2's hand-derived row")


def test_render_svg_error_bar_uses_the_points_own_resolved_color() raises:
    # Two categories, two distinct palette colors -- the error bar's
    # own stroke color must match each point's own resolved color
    # (ch.palette[...]), not a fixed Theme color.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var cats: List[String] = ["a", "b"]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err, color_categories=cats).size(400, 300)
    var s = render_svg(plot).to_string()
    assert_true('stroke="#1f77b4"' in s, "the first category's own palette color, reused for its error bar")
    assert_true('stroke="#ff7f0e"' in s, "the second category's own palette color, reused for its error bar")


def test_render_widens_the_y_domain_to_include_the_whisker_extent() raises:
    # y=[10], y_err=[20] -- the whisker reaches down to -10, well
    # outside plot.y_data's own [10, 10] range. Domain data becomes
    # [-10, 30], padded 5% of that span (2.0) -> [-12, 32] ->
    # _nice_step picks a step of 10 -> ticks [-10, 0, 10, 20, 30]
    # (independently hand-derived, same algorithm test_scale.mojo's
    # own _nice_step tests already verify). If the y-domain were
    # computed from plot.y_data alone (not widened for y_err), no
    # negative tick would ever appear -- plot.y_data is a single
    # constant 10.0, nowhere near zero.
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [20.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err).size(400, 300)
    var s = render_svg(plot).to_string()
    assert_true(">-10<" in s, "a negative-valued y tick, only reachable if the domain widened for y_err")


def test_render_raises_on_a_negative_y_err_value() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, -1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_y_err_length_mismatch() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_y_err_with_an_incompatible_mark() raises:
    # Mark.AREA -- still excluded (see tests/test_error_bars_on_line.
    # mojo's own docstring for why, and its own dedicated test for this
    # exact case). Mark.LINE was the incompatible mark this test used
    # to check, before #146 added y_err support there deliberately.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_area().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
