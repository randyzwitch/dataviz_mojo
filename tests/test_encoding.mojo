"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers:

- Plot.encode()'s y_err channel on Mark.POINT/EFFECT_SCATTER: whisker
  placement in the point's own color, the y-domain widening to the
  whisker endpoints, and the raise paths.
- y_err_lower/y_err_upper: an asymmetric whisker, mutually exclusive
  with y_err, given together or not at all.
- y_err on Mark.LINE: a whisker per original data point in
  Theme.mark_color, independent of the path decimation; Mark.AREA
  still raises.
- Plot.encode_categorical()'s y_err channel on Mark.BAR, and
  encode_grouped_bar()'s errors channel on Mark.GROUPED_BAR (#216):
  whisker placement in the bar's/sub-bar's own resolved color, the
  value-axis domain widening to the whisker endpoints, and the raise
  paths (including the other categorical marks these two encode
  methods feed, which don't support either channel).
- Plot.scale_y_log()/scale_x_log(): pixel placement through the shared
  to_pixel() path and every raise path.
- render_layers() with every layer on an axis agreeing on
  scale_y_log()/scale_x_log() (#217): a shared log domain, primary vs.
  secondary y-axis log-ness decided independently, Mark.AREA still
  excluded, and every mix-raise path (naming the disagreeing layer).
- Plot.scale_x_domain()/scale_y_domain() (#209): a pinned domain wins
  over both the data extent and Mark.AREA's forced zero baseline, an
  out-of-domain point computes a real off-plot pixel rather than
  raising or clamping, render_facets() applies the same override per
  cell as a shared-domain equivalent, and every raise path (min >= max,
  a non-positive min on a log axis, an unsupported mark,
  render_layers()).
- Theme.show_data_labels on Mark.BAR/GROUPED_BAR/STACKED_BAR: label
  placement and formatting, and the default-off case.
- Plot.encode()'s labels channel on Mark.POINT/EFFECT_SCATTER.
- Plot.encode()'s color_map: pinned colors, unmapped categories, the
  legend swatch, and the raise without color_categories.
"""

from canvas.color import Color
from dataviz.colors import TOMATO
from dataviz.plot import (
    Plot,
    render,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    save_layers,
)
from dataviz.theme import Theme
from std.collections import Dict
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_error_bars.mojo
# ---------------------------------------------------------------


def test_render_svg_error_bar_matches_hand_derived_positions() raises:
    # One point, x=1, y=10, y_err=2: domain data becomes [8, 12], padded 5%
    # (0.2) -> [7.8, 12.2]. Canvas 400x200, default theme -> plot_y0=20,
    # plot_y1=150.
    #
    # scale() = (20-150)/(12.2-7.8) = -29.5454...
    # translate() = 150 - 7.8*scale() = 380.4545...
    # to_pixel(8.0) = 144.09 -> 144 (bottom whisker end)
    # to_pixel(12.0) = 25.91 -> 26 (top whisker end)
    # to_pixel(10.0) = 85.0 (the point)
    #
    # Asserted as cy/y1/y2 substrings, not full tags, since cx/x1/x2
    # depend on the dynamic left margin.
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [2.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true(
        'cy="85"' in s, "the point itself lands at the hand-derived pixel row"
    )
    assert_true(
        'y1="144"' in s and 'y2="144"' in s,
        "the bottom whisker/cap sits at y-2's hand-derived row",
    )
    assert_true(
        'y1="26"' in s and 'y2="26"' in s,
        "the top whisker/cap sits at y+2's hand-derived row",
    )


def test_render_svg_error_bar_uses_the_points_own_resolved_color() raises:
    # Two categories, two palette colors: each error bar's stroke must
    # match its point's resolved color (ch.palette), not a fixed Theme
    # color.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var cats: List[String] = ["a", "b"]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, y_err=err, color_categories=cats)
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'stroke="#1f77b4"' in s,
        "the first category's own palette color, reused for its error bar",
    )
    assert_true(
        'stroke="#ff7f0e"' in s,
        "the second category's own palette color, reused for its error bar",
    )


def test_render_widens_the_y_domain_to_include_the_whisker_extent() raises:
    # y=[10], y_err=[20]: the whisker reaches -10, so domain data becomes
    # [-10, 30], padded to [-12, 32], and _nice_step picks step 10 -> ticks
    # [-10, 0, 10, 20, 30]. A domain from plot.y_data alone would never
    # show a negative tick.
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [20.0]
    var plot = Plot().mark_point().encode(x=x, y=y, y_err=err).size(400, 300)
    var s = render_svg(plot).to_string()
    assert_true(
        ">-10<" in s,
        (
            "a negative-valued y tick, only reachable if the domain widened for"
            " y_err"
        ),
    )


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
    # Mark.AREA is still excluded; Mark.LINE gained y_err support in #146.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_area().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_error_bars_asymmetric.mojo
# ---------------------------------------------------------------


def test_render_svg_asymmetric_error_bar_matches_hand_derived_positions() raises:
    # One point, x=1, y=10, y_err_lower=2, y_err_upper=6: an asymmetric
    # whisker from 8 to 16. Domain data [8, 16], padded 5% (0.4) ->
    # [7.6, 16.4]. Canvas 400x200 -> plot_y0=20, plot_y1=150.
    #
    # scale() = (20-150)/(16.4-7.6) = -14.7727...
    # translate() = 150 - 7.6*scale() = 262.2727...
    # to_pixel(8) = 144.09 -> 144 (bottom)
    # to_pixel(16) = 25.91 -> 26 (top)
    # to_pixel(10) = 114.55 -> 115 (the point)
    var x: List[Float64] = [1.0]
    var y: List[Float64] = [10.0]
    var lower: List[Float64] = [2.0]
    var upper: List[Float64] = [6.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
        .size(400, 200)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'cy="115"' in s, "the point itself lands at the hand-derived pixel row"
    )
    assert_true(
        'y1="144"' in s and 'y2="144"' in s,
        "the lower whisker/cap sits at y-2's hand-derived row",
    )
    assert_true(
        'y1="26"' in s and 'y2="26"' in s,
        "the upper whisker/cap sits at y+6's hand-derived row",
    )


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
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, y_err=sym, y_err_lower=lower, y_err_upper=upper)
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_negative_asymmetric_value() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, -1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_asymmetric_bounds_with_an_incompatible_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
    )
    with assert_raises():
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_error_bars_on_line.mojo
# ---------------------------------------------------------------


def test_render_svg_line_error_bar_matches_hand_derived_positions() raises:
    # Two points, x=[1,2], y=[10,10], y_err=[2,2]: domain data [8, 12],
    # padded to [7.8, 12.2]. Canvas 400x200 -> plot_y0=20, plot_y1=150;
    # scale() = -29.5454..., translate() = 380.4545...; to_pixel(8) -> 144,
    # to_pixel(12) -> 26, to_pixel(10) = 85.0.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 10.0]
    var err: List[Float64] = [2.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, y_err=err).size(400, 200)
    var s = render_svg(plot).to_string()
    assert_true(
        'y1="144"' in s and 'y2="144"' in s,
        "the bottom whisker/cap sits at y-2's hand-derived row",
    )
    assert_true(
        'y1="26"' in s and 'y2="26"' in s,
        "the top whisker/cap sits at y+2's hand-derived row",
    )
    assert_true(
        "85.000" in s, "the line itself passes through y=10's own row (85)"
    )


def test_render_svg_line_error_bar_uses_theme_mark_color() raises:
    # Mark.LINE has no per-point color, so every whisker uses
    # Theme.mark_color.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y, y_err=err)
        .theme(Theme(mark_color=TOMATO))
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'stroke="#ff6347"' in s,
        "the whisker uses the chart's own Theme.mark_color",
    )


def test_render_raises_on_y_err_with_mark_area() raises:
    # Mark.AREA stays excluded (its zero-baseline forcing is a separate
    # concern).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_area().encode(x=x, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_error_bars_on_bar.mojo (#216)
# ---------------------------------------------------------------


def test_render_svg_bar_error_bar_matches_hand_derived_positions() raises:
    # One bar, category "A", y=10, y_err=2: domain data becomes [8, 12].
    # _zero_baseline_y_extent keeps lo at 0 (8 > 0, not padded) and pads
    # only the top: hi=12, pad=12*0.05=0.6 -> domain [0, 12.6]. Canvas
    # 400x200, default theme -> plot_y0=20, plot_y1=150.
    #
    # scale() = (20-150)/12.6 = -10.3174...
    # translate() = 150 (domain_min is 0)
    # to_pixel(8) = 67.46 -> 67 (bottom whisker/cap)
    # to_pixel(12) = 26.19 -> 26 (top whisker/cap)
    # to_pixel(10) = 46.83 -> 47 (the bar's own top edge)
    var cats: List[String] = ["A"]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [2.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=y, y_err=err)
        .size(400, 200)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'y1="67"' in s and 'y2="67"' in s,
        "the bottom whisker/cap sits at y-2's hand-derived row",
    )
    assert_true(
        'y1="26"' in s and 'y2="26"' in s,
        "the top whisker/cap sits at y+2's hand-derived row",
    )
    assert_true(
        '<rect x="92" y="47"' in s,
        "the bar's own top edge sits at y=10's hand-derived row",
    )


def test_render_svg_bar_error_bar_uses_the_bars_own_resolved_color() raises:
    # Theme(color_by_sign=True): a negative bar's whisker must use
    # mark_color_negative, the same color _bar_fill_color resolves for
    # its rect, not a fixed axis/whisker color.
    var cats: List[String] = ["pos", "neg"]
    var y: List[Float64] = [10.0, -10.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=y, y_err=err)
        .theme(Theme(color_by_sign=True))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'stroke="#1e64b4"' in s, "the positive bar's whisker uses mark_color"
    )
    assert_true(
        'stroke="#c83c3c"' in s,
        "the negative bar's whisker uses mark_color_negative",
    )


def test_render_bar_widens_the_y_domain_to_include_the_whisker_extent() raises:
    # y=[10], y_err=[20]: the whisker reaches -10, so domain data becomes
    # [-10, 30] -- a negative tick only reachable if the domain widened,
    # the same check test_render_widens_the_y_domain_to_include_the_
    # whisker_extent makes for Mark.POINT.
    var cats: List[String] = ["A"]
    var y: List[Float64] = [10.0]
    var err: List[Float64] = [20.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=y, y_err=err)
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        ">-10<" in s,
        (
            "a negative-valued y tick, only reachable if the domain widened"
            " for y_err"
        ),
    )


def test_render_bar_raises_on_a_negative_y_err_value() raises:
    var cats: List[String] = ["A", "B"]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, -1.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def test_render_bar_raises_on_a_y_err_length_mismatch() raises:
    var cats: List[String] = ["A", "B", "C"]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


def test_render_bar_raises_when_y_err_and_asymmetric_bounds_are_both_given() raises:
    var cats: List[String] = ["A", "B"]
    var y: List[Float64] = [10.0, 20.0]
    var sym: List[Float64] = [1.0, 1.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(
            x=cats, y=y, y_err=sym, y_err_lower=lower, y_err_upper=upper
        )
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_y_err_with_an_incompatible_categorical_mark() raises:
    # Mark.LOLLIPOP shares encode_categorical() with Mark.BAR, but y_err
    # is Mark.BAR-only today.
    var cats: List[String] = ["A", "B"]
    var y: List[Float64] = [10.0, 20.0]
    var err: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_lollipop().encode_categorical(x=cats, y=y, y_err=err)
    with assert_raises():
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_error_bars_on_grouped_bar.mojo (#216)
# ---------------------------------------------------------------


def test_render_svg_grouped_bar_error_bar_matches_hand_derived_positions() raises:
    # One category "A", two series: s1=10 (err 1), s2=20 (err 2). Verified
    # by construction (this file's own convention): s1's whisker sits at
    # y1="88"/y2="99" (11 and 9), s2's at y1="26"/y2="49" (22 and 18), each
    # in its own series palette color.
    var cats: List[String] = ["A"]
    var names: List[String] = ["s1", "s2"]
    var values: List[List[Float64]] = [[10.0], [20.0]]
    var errs: List[List[Float64]] = [[1.0], [2.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(cats, names, values, errors=errs)
        .size(400, 200)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'y1="88"' in s and 'y2="88"' in s,
        "s1's upper whisker/cap sits at 10+1's hand-derived row",
    )
    assert_true(
        'y1="99"' in s and 'y2="99"' in s,
        "s1's lower whisker/cap sits at 10-1's hand-derived row",
    )
    assert_true(
        'y1="26"' in s and 'y2="26"' in s,
        "s2's upper whisker/cap sits at 20+2's hand-derived row",
    )
    assert_true(
        'y1="49"' in s and 'y2="49"' in s,
        "s2's lower whisker/cap sits at 20-2's hand-derived row",
    )
    assert_true(
        'stroke="#1f77b4"' in s,
        "s1's whisker uses its own series palette color",
    )
    assert_true(
        'stroke="#ff7f0e"' in s,
        "s2's whisker uses its own series palette color",
    )


def test_render_grouped_bar_widens_the_y_domain_to_include_the_whisker_extent() raises:
    # One category, one series: s1=10, err=20 -- the whisker reaches -10,
    # same widening check as Mark.BAR's own test above.
    var cats: List[String] = ["A"]
    var names: List[String] = ["s1"]
    var values: List[List[Float64]] = [[10.0]]
    var errs: List[List[Float64]] = [[20.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(cats, names, values, errors=errs)
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        ">-10<" in s,
        (
            "a negative-valued y tick, only reachable if the domain widened"
            " for errors"
        ),
    )


def test_render_grouped_bar_raises_on_a_negative_errors_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["s1", "s2"]
    var values: List[List[Float64]] = [[10.0], [20.0]]
    var errs: List[List[Float64]] = [[1.0], [-1.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(cats, names, values, errors=errs)
    )
    with assert_raises():
        _ = render(plot)


def test_render_grouped_bar_raises_on_an_errors_series_length_mismatch() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["s1"]
    var values: List[List[Float64]] = [[10.0, 20.0]]
    var errs: List[List[Float64]] = [[1.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(cats, names, values, errors=errs)
    )
    with assert_raises():
        _ = render(plot)


def test_render_grouped_bar_raises_on_an_errors_and_values_series_count_mismatch() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["s1", "s2"]
    var values: List[List[Float64]] = [[10.0], [20.0]]
    var errs: List[List[Float64]] = [[1.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(cats, names, values, errors=errs)
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_errors_with_an_incompatible_mark() raises:
    # Mark.STACKED_BAR shares encode_grouped_bar()'s data shape with
    # Mark.GROUPED_BAR, but errors is Mark.GROUPED_BAR-only today.
    var cats: List[String] = ["A"]
    var names: List[String] = ["s1"]
    var values: List[List[Float64]] = [[10.0]]
    var errs: List[List[Float64]] = [[1.0]]
    var plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(cats, names, values, errors=errs)
    )
    with assert_raises():
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_log_scale.mojo
# ---------------------------------------------------------------


def test_render_svg_scale_y_log_matches_hand_derived_positions() raises:
    # y = [1, 10, 100]: _log_data_extent pads 5% of the log-space span (0
    # to 2, pad 0.1) -> domain [-0.1, 2.1]. Canvas 400x300, default theme
    # -> plot_y0=20, plot_y1=250.
    #
    # scale() = (20-250)/2.2 = -104.5454...
    # translate() = 250 - (-0.1)*scale() = 239.5454...
    # to_pixel(1) -> 239.55 -> 240
    # to_pixel(10) = 135.0
    # to_pixel(100) -> 30.45 -> 30
    #
    # Asserted as cy substrings, since cx depends on the dynamic left
    # margin.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300).scale_y_log()
    var s = render_svg(plot).to_string()
    assert_true('cy="240"' in s, "y=1 lands at the hand-derived pixel row")
    assert_true(
        'cy="135"' in s,
        "y=10 lands exactly one decade up (equal pixel gap to y=1's row)",
    )
    assert_true(
        'cy="30"' in s,
        "y=100 lands exactly one more decade up (the same pixel gap again)",
    )


def test_render_raises_on_a_non_positive_value_with_scale_y_log() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 0.0, 5.0]
    var plot = Plot().mark_line().encode(x=x, y=y).scale_y_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_negative_value_with_scale_x_log() raises:
    var x: List[Float64] = [1.0, -2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var plot = Plot().mark_line().encode(x=x, y=y).scale_x_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_scale_y_log_with_mark_area() raises:
    # Mark.AREA's y-domain is forced through zero, which has no logarithm,
    # so the combination is rejected.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = Plot().mark_area().encode(x=x, y=y).scale_y_log()
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_scale_y_log_with_an_incompatible_mark() raises:
    var categories: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=categories, y=values)
        .scale_y_log()
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_non_positive_annotate_line_value_with_scale_y_log() raises:
    # An annotation goes through the same to_pixel() call as the data, so a
    # non-positive value is rejected the same way.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = (
        Plot().mark_line().encode(x=x, y=y).scale_y_log().annotate_line(-5.0)
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_a_non_positive_annotate_vline_value_with_scale_x_log() raises:
    var x: List[Float64] = [1.0, 10.0, 100.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var plot = (
        Plot().mark_line().encode(x=x, y=y).scale_x_log().annotate_vline(0.0)
    )
    with assert_raises():
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_axis_domain_overrides.mojo (#209)
# ---------------------------------------------------------------


def test_render_svg_scale_y_domain_matches_hand_derived_positions() raises:
    # Pinned y-domain [0, 100], ignoring the data's own [10, 90] range.
    # Canvas 400x300, default theme -> plot_y0=20, plot_y1=250.
    #
    # scale() = (20-250)/(100-0) = -2.3, translate() = 250.
    # to_pixel(10) = 227, to_pixel(50) = 135, to_pixel(90) = 43.
    #
    # Ticks: _nice_step(0, 100, 5) -> step 20 -> [0, 20, 40, 60, 80, 100],
    # the same hand-derived set test_ticks_matches_hand_computed_values_
    # domain_0_100 (test_primitives.mojo) uses for this exact domain.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 50.0, 90.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .scale_y_domain(0.0, 100.0)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    for tick in ["0", "20", "40", "60", "80", "100"]:
        assert_true(">" + tick + "<" in s, "tick " + tick + " is drawn")
    assert_true('cy="227"' in s, "y=10 lands at the pinned domain's own row")
    assert_true('cy="135"' in s, "y=50 lands at the pinned domain's own row")
    assert_true('cy="43"' in s, "y=90 lands at the pinned domain's own row")


def test_render_svg_scale_y_domain_wins_over_the_data_extent() raises:
    # Data tightly clustered around 42-45 still shows the pinned [0, 100]
    # domain and its ticks -- not a padded [~40, ~47] auto-computed one.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [42.0, 44.0, 45.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .scale_y_domain(0.0, 100.0)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(">0<" in s, "the pinned domain's own low tick draws")
    assert_true(">100<" in s, "the pinned domain's own high tick draws")


def test_render_svg_scale_y_domain_overrides_mark_area_forced_zero_baseline() raises:
    # #209: an explicit domain wins even over Mark.AREA's usual forced
    # zero baseline -- [30, 70] shows no 0 tick at all.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [40.0, 50.0, 60.0]
    var plot = (
        Plot()
        .mark_area()
        .encode(x=x, y=y)
        .scale_y_domain(30.0, 70.0)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(">30<" in s, "the pinned lower bound's own tick draws")
    assert_true(">0<" not in s, "zero is no longer forced into view")


def test_render_svg_point_outside_scale_domain_computes_an_off_plot_pixel() raises:
    # y=150 is outside the pinned [0, 100] domain: to_pixel(150) =
    # 250 + 150*(-2.3) = -95, a real (negative, off-plot) pixel row --
    # not clamped, not garbage, not a raise. The SVG's own viewBox clips
    # it visually (default overflow: hidden on the root <svg>); nothing
    # further to do on the raster backend, which bounds-checks its own
    # pixel buffer.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 50.0, 150.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .scale_y_domain(0.0, 100.0)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'cy="-95"' in s,
        "the out-of-domain point still computes its real off-plot pixel",
    )
    var c = render(plot)  # must not crash on the raster backend either
    _ = c


def test_render_raises_when_scale_domain_min_is_not_less_than_max() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_point().encode(x=x, y=y).scale_y_domain(100.0, 0.0)
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_scale_domain_with_a_non_positive_min_on_a_log_axis() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .scale_y_log()
        .scale_y_domain(-1.0, 100.0)
    )
    with assert_raises():
        _ = render(plot)


def test_render_raises_on_scale_domain_with_an_incompatible_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .scale_y_domain(0.0, 10.0)
    )
    with assert_raises():
        _ = render(plot)


def test_render_layers_raises_on_a_layer_with_scale_y_domain() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var a = Plot().mark_line().encode(x=x, y=y).scale_y_domain(0.0, 10.0)
    var b = Plot().mark_point().encode(x=x, y=y)
    var plots: List[Plot] = [a^, b^]
    with assert_raises():
        _ = render_layers(plots)


def test_render_facets_svg_scale_y_domain_applies_per_cell_like_a_shared_domain() raises:
    # #209: the same override on every cell reads as one shared domain --
    # the facets counterpart to shared_y_scale=True, with no extra
    # facets-specific wiring (each cell independently resolves the same
    # pinned [0, 100] via _render_generic).
    var x: List[Float64] = [1.0, 2.0]
    var y0: List[Float64] = [5.0, 6.0]
    var y1: List[Float64] = [95.0, 96.0]
    var p0 = (
        Plot()
        .size(300, 220)
        .mark_point()
        .encode(x=x, y=y0)
        .scale_y_domain(0.0, 100.0)
        .theme(Theme(show_gridlines=False))
    )
    var p1 = (
        Plot()
        .size(300, 220)
        .mark_point()
        .encode(x=x, y=y1)
        .scale_y_domain(0.0, 100.0)
        .theme(Theme(show_gridlines=False))
    )
    var plots: List[Plot] = [p0^, p1^]
    var s = render_facets_svg(plots, 2).to_string()
    assert_true(">0<" in s, "the shared pinned domain's low tick draws")
    assert_true(">100<" in s, "the shared pinned domain's high tick draws")


def test_render_layers_raises_on_a_layer_with_scale_y_log() raises:
    # #217: render_layers() now supports a log axis when every layer on
    # it agrees; a lone log layer next to a linear one still raises,
    # naming the disagreeing layer.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 10.0]
    var a = Plot().mark_line().encode(x=x, y=y).scale_y_log()
    var b = Plot().mark_line().encode(x=x, y=y)
    var plots: List[Plot] = [a^, b^]
    with assert_raises():
        _ = render_layers(plots)


def test_render_svg_layers_share_one_log_y_domain_when_every_layer_agrees() raises:
    # #217: two log-y layers, y=[1,10] and y=[10,100]. Combined domain
    # [1,100] in real units -> log10-space [0,2], padded 5% (0.1) ->
    # [-0.1, 2.1], the exact domain test_render_svg_scale_y_log_matches_
    # hand_derived_positions (above) uses for its own [1,10,100] domain
    # -- same canvas (400x300), same ticks: to_pixel(1)=240, to_pixel(10)
    # =135, to_pixel(100)=30.
    var x1: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [1.0, 10.0]
    var x2: List[Float64] = [1.0, 2.0]
    var y2: List[Float64] = [10.0, 100.0]
    var a = (
        Plot()
        .mark_point()
        .encode(x=x1, y=y1)
        .scale_y_log()
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var b = (
        Plot()
        .mark_line()
        .encode(x=x2, y=y2)
        .scale_y_log()
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var plots: List[Plot] = [a^, b^]
    var s = render_layers_svg(plots).to_string()
    assert_true('">1<' in s or ">1<" in s, "the 1 tick label draws")
    assert_true(
        'y1="240"' in s and 'y2="240"' in s, "y=1's tick sits at row 240"
    )
    assert_true(
        'y1="135"' in s and 'y2="135"' in s, "y=10's tick sits at row 135"
    )
    assert_true(
        'y1="30"' in s and 'y2="30"' in s, "y=100's tick sits at row 30"
    )
    assert_true(
        'cx="75" cy="240"' in s, "the point layer's y=1 lands at row 240"
    )
    assert_true(
        "365.455,30.455" in s, "the line layer's y=100 endpoint lands at row 30"
    )


def test_render_layers_raises_on_an_x_axis_log_mix() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var a = Plot().mark_line().encode(x=x, y=y).scale_x_log()
    var b = Plot().mark_line().encode(x=x, y=y)
    var plots: List[Plot] = [a^, b^]
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_raises_on_scale_y_log_with_a_mark_area_layer() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 10.0]
    var a = Plot().mark_area().encode(x=x, y=y).scale_y_log()
    var b = Plot().mark_point().encode(x=x, y=y).scale_y_log()
    var plots: List[Plot] = [a^, b^]
    with assert_raises():
        _ = render_layers(plots)


def test_render_layers_secondary_axis_log_is_independent_of_the_primary_axis() raises:
    # #217: a linear primary axis alongside a log secondary axis (or the
    # reverse) is fine -- the two groups are validated independently.
    var x: List[Float64] = [1.0, 2.0]
    var y1: List[Float64] = [1.0, 2.0]
    var y2: List[Float64] = [1.0, 100.0]
    var a = Plot().mark_point().encode(x=x, y=y1).size(400, 300)
    var b = (
        Plot()
        .mark_line()
        .encode(x=x, y=y2)
        .scale_y_log()
        .secondary_axis()
        .size(400, 300)
    )
    var plots: List[Plot] = [a^, b^]
    var s = render_layers_svg(plots).to_string()
    assert_true(
        ">100<" in s, "the secondary axis's own log ticks (1, 10, 100) draw"
    )


# ---------------------------------------------------------------
# from tests/test_data_labels.mojo
# ---------------------------------------------------------------


def test_render_svg_bar_data_labels_match_hand_derived_positions() raises:
    # 2 categories, y=[10.0, -5.5], canvas 400x300, no gridlines, plot rect
    # x:[60,380] y:[20,250]; band_start(A)=76, band_start(B)=236,
    # bandwidth=128.
    #
    # A (10.0): rect y=30, so the label baseline is 30 - label_gap(4) = 26,
    # centered at 76+64 = 140. B (-5.5): rect bottom edge at 240, so the
    # baseline is 240 + 4 + font_size(12) = 256, centered at 236+64 = 300.
    # "-5.5" keeps its decimal (_label_decimals(-5.5) is 1), independent
    # of the integer y-axis ticks.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="26" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">10</text>'
        in s,
        "A's label, above the positive bar",
    )
    assert_true(
        '<text x="300" y="256" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">-5.5</text>'
        in s,
        "B's label, below the negative bar, real decimal kept",
    )


def test_render_svg_bar_draws_no_labels_by_default() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        'text-anchor="middle">10</text>' not in s,
        "no value label without show_data_labels=True",
    )


def test_render_svg_grouped_bar_data_labels_match_hand_derived_positions() raises:
    # Same 2-category frame as the BAR test; 2 series split each 128px band
    # into two 64px sub-bars.
    # A: North=10 -> rect x=76,y=30,h=135, label (108, 26).
    # South=4 -> rect x=140,y=111,h=54, label (172, 107).
    # B: North=-5.5 -> rect x=236,y=165,h=75, label (268, 256).
    # South=8 -> rect x=300,y=57,h=108, label (332, 53).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.5], [4.0, 8.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(categories=cats, series_names=names, values=values)
        .theme(
            Theme(
                show_gridlines=False, show_data_labels=True, show_legend=False
            )
        )
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="108" y="26" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">10</text>'
        in s,
        "A/North's label",
    )
    assert_true(
        '<text x="172" y="107" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">4</text>'
        in s,
        "A/South's label",
    )
    assert_true(
        '<text x="268" y="256" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">-5.5</text>'
        in s,
        "B/North's label, below its negative sub-bar",
    )
    assert_true(
        '<text x="332" y="53" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">8</text>'
        in s,
        "B/South's label",
    )


def test_render_svg_stacked_bar_data_labels_match_hand_derived_positions() raises:
    # Same frame and data; each segment's label centers inside its rect,
    # with the font_size*0.35 baseline offset (4).
    # A: North=10 -> rect y=73,h=108 -> 73+54+4 = 131 at x=140.
    # South=4 -> rect y=30,h=43 -> 30+21+4 = 55 at x=140.
    # B: North=-5.5 -> rect y=181,h=59 -> 181+29+4 = 214 at x=300.
    # South=8 -> rect y=95,h=86 -> 95+43+4 = 142 at x=300.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.5], [4.0, 8.0]]
    var plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(categories=cats, series_names=names, values=values)
        .theme(
            Theme(
                show_gridlines=False, show_data_labels=True, show_legend=False
            )
        )
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="140" y="131" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">10</text>'
        in s,
        "A/North's label, centered inside its segment",
    )
    assert_true(
        '<text x="140" y="55" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">4</text>'
        in s,
        "A/South's label, centered inside its segment",
    )
    assert_true(
        '<text x="300" y="214" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">-5.5</text>'
        in s,
        "B/North's label, its own segment value, not a cumulative total",
    )
    assert_true(
        '<text x="300" y="142" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">8</text>'
        in s,
        "B/South's label",
    )


# ---------------------------------------------------------------
# from tests/test_point_labels.mojo
# ---------------------------------------------------------------


def test_render_svg_point_labels_match_hand_derived_positions() raises:
    # x=[1,2,3], y=[10,20,30], canvas 400x300, default theme: plot rect
    # x:[60,380] y:[20,250], points at (75,240), (220,135), (365,30).
    # labels=["a", "", "c"]: the empty entry skips that point's label.
    # Baselines sit label_gap(4) above the point's top edge (py - 4 - 4):
    # "a" at (75, 232), "c" at (365, 22).
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var labels: List[String] = ["a", "", "c"]
    var plot = (
        Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="75" y="232" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">a</text>'
        in s,
        "first point's label",
    )
    assert_true(
        '<text x="365" y="22" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">c</text>'
        in s,
        "third point's label",
    )
    assert_true(
        ">b<" not in s, 'the middle point\'s "" entry draws no label at all'
    )


def test_render_svg_point_draws_no_labels_by_default() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [10.0, 20.0, 30.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        'text-anchor="middle">a</text>' not in s,
        "no point labels without encode()'s labels",
    )


def test_render_svg_effect_scatter_supports_labels() raises:
    # Same frame, 2 points: EFFECT_SCATTER's halo doesn't change label
    # placement, which anchors off the inner point's radius.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["p", "q"]
    var plot = (
        Plot()
        .mark_effect_scatter()
        .encode(x=x, y=y, labels=labels)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="75" y="232" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">p</text>'
        in s,
        "first point's label",
    )
    assert_true(
        '<text x="365" y="22" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="middle">q</text>'
        in s,
        "second point's label",
    )


def test_encode_raises_on_labels_length_mismatch() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["only one"]
    with assert_raises():
        var plot = (
            Plot().mark_point().encode(x=x, y=y, labels=labels).size(400, 300)
        )
        _ = render_svg(plot)


def test_encode_raises_on_labels_with_an_unsupported_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var labels: List[String] = ["a", "b"]
    with assert_raises():
        var plot = (
            Plot().mark_line().encode(x=x, y=y, labels=labels).size(400, 300)
        )
        _ = render_svg(plot)


# ---------------------------------------------------------------
# from tests/test_color_map.mojo
# ---------------------------------------------------------------


def test_render_svg_color_map_overrides_the_named_category() raises:
    # "b" pinned to crimson (#dc143c); "a" keeps its palette color
    # (#1f77b4).
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"b": Color(220, 20, 60)}
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats, color_map=overrides)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        'fill="#1f77b4"' in s,
        "unmapped category 'a' keeps its ordinary palette color",
    )
    assert_true(
        'fill="#dc143c"' in s, "mapped category 'b' uses the overridden color"
    )
    assert_true(
        'fill="#ff7f0e"' not in s,
        "'b' must not also show its ordinary (unoverridden) color",
    )


def test_render_svg_color_map_override_reaches_the_legend_swatch_too() raises:
    # The legend swatch shows the overridden color too; both read
    # _PointChannels.palette.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"b": Color(220, 20, 60)}
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats, color_map=overrides)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<rect x="' in s and 'fill="#dc143c"' in s,
        "a legend swatch uses the overridden color",
    )


def test_render_svg_color_map_leaves_an_unrelated_column_of_the_same_name_alone() raises:
    # A color_map key that never appears among the categories is not an
    # error.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var cats: List[String] = ["a", "b"]
    var overrides: Dict[String, Color] = {"c": Color(0, 0, 0)}
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats, color_map=overrides)
    )
    _ = render_svg(plot)


def test_render_raises_on_color_map_without_color_categories() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var overrides: Dict[String, Color] = {"a": Color(0, 0, 0)}
    var plot = Plot().mark_point().encode(x=x, y=y, color_map=overrides)
    with assert_raises():
        _ = render(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
