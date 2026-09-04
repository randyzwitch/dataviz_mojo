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
- Plot.scale_y_log()/scale_x_log(): pixel placement through the shared
  to_pixel() path and every raise path.
- Theme.show_data_labels on Mark.BAR/GROUPED_BAR/STACKED_BAR: label
  placement and formatting, and the default-off case.
- Plot.encode()'s labels channel on Mark.POINT/EFFECT_SCATTER.
- Plot.encode()'s color_map: pinned colors, unmapped categories, the
  legend swatch, and the raise without color_categories.
"""

from canvas.color import Color
from dataviz.colors import TOMATO
from dataviz.plot import Plot, render, render_layers, render_svg, save_layers
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


def test_render_layers_raises_on_a_layer_with_scale_y_log() raises:
    # render_layers() combines every layer into one shared linear domain;
    # a log-scaled layer is rejected.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 10.0]
    var a = Plot().mark_line().encode(x=x, y=y).scale_y_log()
    var b = Plot().mark_line().encode(x=x, y=y)
    var plots: List[Plot] = [a^, b^]
    with assert_raises():
        _ = render_layers(plots)


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
