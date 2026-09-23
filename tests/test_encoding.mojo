"""Tests for encoding and explicit scales.

Covers:

- Plot.encode()'s y_err channel on Mark.POINT/EFFECT_SCATTER: whisker
  placement in the point's own color, the y-domain widening to the
  whisker endpoints, and the raise paths.
- y_err_lower/y_err_upper: an asymmetric whisker, mutually exclusive
  with y_err, given together or not at all.
- y_err/y_err_lower/y_err_upper on Mark.LINE: a whisker per original
  data point in Theme.mark_color, independent of the path decimation,
  equivalent whether given as y_err or an equal y_err_lower/
  y_err_upper, and identical standalone, layered and faceted (#702);
  Mark.AREA still raises for either form.
- Plot.encode_categorical()'s y_err channel on Mark.BAR, and
  encode_grouped_bar()'s errors channel on Mark.GROUPED_BAR:
  whisker placement in the bar's/sub-bar's own resolved color, the
  value-axis domain widening to the whisker endpoints, and the raise
  paths (including the other categorical marks these two encode
  methods feed, which don't support either channel).
- Plot.scale_y_log()/scale_x_log(): pixel placement through the shared
  to_pixel() path and every raise path.
- render_layers() with every layer on an axis agreeing on
  scale_y_log()/scale_x_log(): a shared log domain, primary vs.
  secondary y-axis log-ness decided independently, Mark.AREA still
  excluded, and every mix-raise path (naming the disagreeing layer).
- Plot.scale_x_domain()/scale_y_domain(): a pinned domain wins
  over both the data extent and Mark.AREA's forced zero baseline, an
  out-of-domain point computes a real off-plot pixel rather than
  raising or clamping, render_facets() applies the same override per
  cell as a shared-domain equivalent, and every raise path (min >= max,
  a non-positive min on a log axis, an unsupported mark,
  render_layers()).
- Theme.show_data_labels on Mark.BAR/GROUPED_BAR/STACKED_BAR/LOLLIPOP/
  WATERFALL/BULLET/POPULATION_PYRAMID: label placement and
  formatting, and the default-off case for every one of them.
- Plot.encode()'s labels channel on Mark.POINT/EFFECT_SCATTER.
- Plot.encode()'s color_map: pinned colors, unmapped categories, the
  legend swatch, and the raise without color_categories.
"""

from std.collections import Dict
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from canvas.color import Color
from dataviz import Theme, bar
from dataviz.core.colors import TOMATO
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.plot import (
    Plot,
    render,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    save_layers,
)
from _test_helpers import _attr_values


def test_flat_categorical_encoding_rejects_duplicate_names() raises:
    var categories: List[String] = ["a", "b", "a"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises(contains='duplicate category "a" at positions 0 and 2'):
        _ = Plot().mark_bar().encode_categorical(categories, values)
    with assert_raises(contains='duplicate category "a" at positions 0 and 2'):
        _ = bar(categories, values)


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
        'cy="85.000"' in s,
        "the point itself lands at the hand-derived pixel row",
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
    # [-10, 0, 10, 20, 30]. A domain from plot._continuous.y alone would never
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
    # Mark.AREA is still excluded; Mark.LINE gained y_err support in .
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
        'cy="114.545"' in s,
        "the point itself lands at the hand-derived pixel row",
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
    # Mark.AREA is the excluded one (#702): its zero-baseline forcing is
    # a separate concern, same as test_render_raises_on_y_err_with_mark_area
    # below. Mark.LINE takes y_err_lower/y_err_upper now, matching
    # Mark.POINT/EFFECT_SCATTER -- see the "from tests/test_error_bars_on_line"
    # block for its own positive-path tests.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 20.0]
    var lower: List[Float64] = [1.0, 1.0]
    var upper: List[Float64] = [1.0, 1.0]
    var plot = (
        Plot()
        .mark_area()
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


def _has_whisker_at_row(svg: String, row: String) -> Bool:
    """Whether some `<line>` in `svg` has `y1` (or `y2`) equal to `row`
    and `stroke="#1e64b4"` (mark_color), correlated on the same
    element (#702).

    A plain `'y1="144"' in svg` substring check is blind to *which*
    element carries it: a gridline or an axis tick can land on the
    exact same row as a whisker (this module's domains do, more than
    once), and the line's own path stroke also puts `#1e64b4` in the
    document regardless of whether a whisker drew at all -- so an
    independent `'stroke="#1e64b4"' in svg` check passes even when the
    whisker loop never runs. Zipping `_attr_values` by index keeps the
    two attributes on the one `<line>` they came from; canvas_mojo
    writes every `<line>`'s attributes in the same order, so the
    indices line up.
    """
    var y1s = _attr_values(svg, "line", "y1")
    var y2s = _attr_values(svg, "line", "y2")
    var strokes = _attr_values(svg, "line", "stroke")
    for i in range(len(strokes)):
        if strokes[i] != "#1e64b4":
            continue
        if y1s[i] == row or y2s[i] == row:
            return True
    return False


def test_render_svg_asymmetric_line_error_bar_matches_hand_derived_positions() raises:
    # Two points, x=[1,2], y=[10,10], y_err_lower=[2,2], y_err_upper=[6,6]:
    # domain data [8, 16] at each point (#702). Padded 5% (0.4) ->
    # [7.6, 16.4]. Canvas 400x200 -> plot_y0=20, plot_y1=150 -- the same
    # domain the Mark.POINT asymmetric test above derives, so the same
    # pixel rows apply.
    #
    # scale() = (20-150)/(16.4-7.6) = -14.7727...
    # translate() = 150 - 7.6*scale() = 262.2727...
    # to_pixel(8) = 144.09 -> 144 (lower)
    # to_pixel(16) = 25.91 -> 26 (upper)
    # to_pixel(10) = 114.545... (the line's own row)
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 10.0]
    var lower: List[Float64] = [2.0, 2.0]
    var upper: List[Float64] = [6.0, 6.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
        .size(400, 200)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        _has_whisker_at_row(s, "144"),
        "the lower whisker/cap sits at y-2's hand-derived row, in mark_color",
    )
    assert_true(
        _has_whisker_at_row(s, "26"),
        "the upper whisker/cap sits at y+6's hand-derived row, in mark_color",
    )
    assert_true("114.545" in s, "the line itself passes through y=10's own row")


def test_symmetric_and_equal_asymmetric_line_errors_render_identically() raises:
    # The acceptance test for #702: y_err=e and y_err_lower=e,
    # y_err_upper=e describe the same whisker, so they must produce the
    # same document -- not merely the same numbers, the same bytes.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 3.0]
    var err: List[Float64] = [0.5, 1.0, 0.25]
    var symmetric = (
        Plot().mark_line().encode(x=x, y=y, y_err=err).size(300, 200)
    )
    var asymmetric = (
        Plot()
        .mark_line()
        .encode(x=x, y=y, y_err_lower=err, y_err_upper=err)
        .size(300, 200)
    )
    assert_equal(
        render_svg(symmetric).to_string(),
        render_svg(asymmetric).to_string(),
        "y_err=e and y_err_lower=e/y_err_upper=e are the same whisker",
    )


def test_a_line_with_asymmetric_errors_renders_the_same_layered_and_faceted() raises:
    # #702's "standalone, layered, and faceted rendering use the same
    # behavior" criterion: the same asymmetric line, drawn standalone
    # and as the one layer of a render_layers()/render_facets() call,
    # produces the identical whisker geometry each time. Same rows and
    # mark_color as the hand-derived test above, checked the same
    # structural way -- see _has_whisker_at_row for why a plain
    # substring check isn't enough here.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [10.0, 10.0]
    var lower: List[Float64] = [2.0, 2.0]
    var upper: List[Float64] = [6.0, 6.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y, y_err_lower=lower, y_err_upper=upper)
        .size(400, 200)
    )
    var standalone = render_svg(plot).to_string()
    assert_true(
        _has_whisker_at_row(standalone, "144")
        and _has_whisker_at_row(standalone, "26"),
        "sanity: the standalone whisker rows are present, in mark_color",
    )

    var one_layer = List[Plot]()
    one_layer.append(plot.copy())
    var layered = render_layers_svg(one_layer).to_string()
    assert_true(
        _has_whisker_at_row(layered, "144"),
        "the lower whisker survives in the layered render, in mark_color",
    )
    assert_true(
        _has_whisker_at_row(layered, "26"),
        "the upper whisker survives in the layered render, in mark_color",
    )

    var one_cell = List[Plot]()
    one_cell.append(plot.copy())
    var faceted = render_facets_svg(one_cell, 1).to_string()
    assert_true(
        _has_whisker_at_row(faceted, "144"),
        "the lower whisker survives in the faceted render, in mark_color",
    )
    assert_true(
        _has_whisker_at_row(faceted, "26"),
        "the upper whisker survives in the faceted render, in mark_color",
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
# from tests/test_error_bars_on_bar.mojo
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
        'y1="67.000"' in s and 'y2="67.000"' in s,
        "the bottom whisker/cap sits at y-2's hand-derived row",
    )
    assert_true(
        'y1="26.000"' in s and 'y2="26.000"' in s,
        "the top whisker/cap sits at y+2's hand-derived row",
    )
    assert_true(
        '<rect x="93" y="47"' in s,
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
# from tests/test_error_bars_on_grouped_bar.mojo
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
        'y1="88.000"' in s and 'y2="88.000"' in s,
        "s1's upper whisker/cap sits at 10+1's hand-derived row",
    )
    assert_true(
        'y1="99.000"' in s and 'y2="99.000"' in s,
        "s1's lower whisker/cap sits at 10-1's hand-derived row",
    )
    assert_true(
        'y1="26.000"' in s and 'y2="26.000"' in s,
        "s2's upper whisker/cap sits at 20+2's hand-derived row",
    )
    assert_true(
        'y1="49.000"' in s and 'y2="49.000"' in s,
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
    # to_pixel(1) = 239.545
    # to_pixel(10) = 135.0
    # to_pixel(100) = 30.455
    #
    # Asserted as cy substrings, since cx depends on the dynamic left
    # margin.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 10.0, 100.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300).scale_y_log()
    var s = render_svg(plot).to_string()
    assert_true('cy="239.545"' in s, "y=1 lands at the hand-derived pixel row")
    assert_true(
        'cy="135.000"' in s,
        "y=10 lands exactly one decade up (equal pixel gap to y=1's row)",
    )
    assert_true(
        'cy="30.455"' in s,
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
# from tests/test_axis_domain_overrides.mojo
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
    assert_true(
        'cy="227.000"' in s, "y=10 lands at the pinned domain's own row"
    )
    assert_true(
        'cy="135.000"' in s, "y=50 lands at the pinned domain's own row"
    )
    assert_true('cy="43.000"' in s, "y=90 lands at the pinned domain's own row")


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
    # an explicit domain wins even over Mark.AREA's usual forced
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
        'cy="-95.000"' in s,
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


def test_render_layers_takes_a_lone_scale_y_domain_as_the_shared_axis() raises:
    # Was `..._raises_on_a_layer_with_scale_y_domain` before #434: an
    # override is now taken when every layer that sets one agrees, and a
    # single layer setting one agrees with itself. The other layer then
    # scales against the same [0, 10]. The data alone would give a padded
    # [0.95, 2.05] whose ticks never reach 10, so a "10" tick label is
    # the override in use rather than merely tolerated.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var a = Plot().mark_line().encode(x=x, y=y).scale_y_domain(0.0, 10.0)
    var b = Plot().mark_point().encode(x=x, y=y)
    var plots: List[Plot] = [a^, b^]
    var s = render_layers_svg(plots).to_string()
    assert_true(">10<" in s or ">10.0<" in s, "the shared y-axis runs to 10")


def test_render_facets_svg_scale_y_domain_applies_per_cell_like_a_shared_domain() raises:
    # the same override on every cell reads as one shared domain --
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
    # render_layers() now supports a log axis when every layer on
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
    # two log-y layers, y=[1,10] and y=[10,100]. Combined domain
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
        'cx="74.545" cy="239.545"' in s,
        "the point layer's y=1 lands at its hand-derived row",
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
    # a linear primary axis alongside a log secondary axis (or the
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
        '<text x="140.000" y="26.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>'
        in s,
        "A's label, above the positive bar",
    )
    assert_true(
        '<text x="300.000" y="256.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>'
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
        '<text x="108.000" y="26.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>'
        in s,
        "A/North's label",
    )
    assert_true(
        '<text x="172.000" y="107.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">4</text>'
        in s,
        "A/South's label",
    )
    assert_true(
        '<text x="268.000" y="256.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>'
        in s,
        "B/North's label, below its negative sub-bar",
    )
    assert_true(
        '<text x="332.000" y="53.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">8</text>'
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
        '<text x="140.000" y="131.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>'
        in s,
        "A/North's label, centered inside its segment",
    )
    assert_true(
        '<text x="140.000" y="56.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">4</text>'
        in s,
        "A/South's label, centered inside its segment",
    )
    assert_true(
        '<text x="300.000" y="214.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>'
        in s,
        "B/North's label, its own segment value, not a cumulative total",
    )
    assert_true(
        '<text x="300.000" y="142.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">8</text>'
        in s,
        "B/South's label",
    )


def test_render_svg_lollipop_data_labels_match_hand_derived_positions() raises:
    # show_data_labels closes the gap on Mark.LOLLIPOP (previously
    # BAR/GROUPED_BAR/STACKED_BAR only). Same 2-category frame as the BAR
    # test above; each label sits past the dot (radius padded on, so it
    # clears the head circle, not just the stem).
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var plot = (
        Plot()
        .mark_lollipop()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="140.000" y="22.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>'
        in s,
        "A's label, above the positive dot",
    )
    assert_true(
        '<text x="300.000" y="260.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>'
        in s,
        "B's label, below the negative dot",
    )


def test_render_svg_waterfall_data_labels_match_hand_derived_positions() raises:
    # closes the gap on Mark.WATERFALL. Two plain delta bars (no
    # is_total), running total 10 then 4.5; each label shows its own
    # delta, not the running total.
    var cats: List[String] = ["A", "B"]
    var deltas: List[Float64] = [10.0, -5.5]
    var plot = (
        Plot()
        .mark_waterfall()
        .encode_waterfall(cats, deltas)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="140.000" y="27.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>'
        in s,
        "A's label, its own delta above the rising bar",
    )
    assert_true(
        '<text x="300.000" y="167.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>'
        in s,
        "B's label, its own delta below the falling bar",
    )


def test_render_svg_bullet_data_labels_match_hand_derived_positions() raises:
    # closes the gap on Mark.BULLET -- the measure value, at full
    # band width (not the narrower measure bar itself).
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [10.0, -5.5]
    var targets: List[Float64] = [8.0, -6.0]
    var ranges: List[List[Float64]] = [
        [5.0, 10.0, 15.0],
        [-10.0, -5.0, 0.0],
    ]
    var plot = (
        Plot()
        .mark_bullet()
        .encode_bullet(cats, measures, targets, ranges)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="140.000" y="76.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">10</text>'
        in s,
        "A's measure label, above the positive bar",
    )
    assert_true(
        '<text x="300.000" y="251.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">-5.5</text>'
        in s,
        "B's measure label, below the negative bar",
    )


def test_render_svg_population_pyramid_data_labels_match_hand_derived_positions() raises:
    # closes the gap on Mark.POPULATION_PYRAMID -- one label per
    # side, hanging off that side's own bar, right-aligned on the left
    # and left-aligned on the right.
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 20.0]
    var right: List[Float64] = [8.0, 15.0]
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(cats, left, right)
        .theme(
            Theme(
                show_gridlines=False, show_data_labels=True, show_legend=False
            )
        )
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="140.000" y="82.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="end">10</text>'
        in s,
        "A's left-side label, right-aligned just left of its bar",
    )
    assert_true(
        '<text x="285.000" y="82.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="start">8</text>'
        in s,
        "A's right-side label, left-aligned just right of its bar",
    )
    assert_true(
        '<text x="64.000" y="197.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="end">20</text>'
        in s,
        "B's left-side label",
    )
    assert_true(
        '<text x="338.000" y="197.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="start">15</text>'
        in s,
        "B's right-side label",
    )


def test_render_svg_lollipop_waterfall_bullet_pyramid_draw_no_labels_by_default() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.5]
    var lollipop_plot = (
        Plot()
        .mark_lollipop()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
    )
    assert_true(
        'text-anchor="middle">10</text>'
        not in render_svg(lollipop_plot).to_string(),
        "lollipop draws no value label without show_data_labels=True",
    )

    var waterfall_plot = (
        Plot()
        .mark_waterfall()
        .encode_waterfall(cats, vals)
        .theme(Theme(show_gridlines=False))
    )
    assert_true(
        'text-anchor="middle">10</text>'
        not in render_svg(waterfall_plot).to_string(),
        "waterfall draws no value label without show_data_labels=True",
    )

    var ranges: List[List[Float64]] = [
        [5.0, 10.0, 15.0],
        [-10.0, -5.0, 0.0],
    ]
    var bullet_plot = (
        Plot()
        .mark_bullet()
        .encode_bullet(cats, vals, [8.0, -6.0], ranges)
        .theme(Theme(show_gridlines=False))
    )
    assert_true(
        'text-anchor="middle">10</text>'
        not in render_svg(bullet_plot).to_string(),
        "bullet draws no measure label without show_data_labels=True",
    )

    var pyramid_plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(cats, vals, [8.0, 15.0])
        .theme(Theme(show_gridlines=False, show_legend=False))
    )
    assert_true(
        'text-anchor="end">10</text>'
        not in render_svg(pyramid_plot).to_string(),
        "population pyramid draws no side labels without show_data_labels=True",
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
        '<text x="75.000" y="232.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">a</text>'
        in s,
        "first point's label",
    )
    assert_true(
        '<text x="365.000" y="22.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">c</text>'
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
        '<text x="75.000" y="232.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">p</text>'
        in s,
        "first point's label",
    )
    assert_true(
        '<text x="365.000" y="22.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">q</text>'
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


# ==== from test_encoder_mark_check.mojo ====
# An encoder rejects a mark it does not write data for (#538).
#
# `Plot` carries every mark's data on one struct with the mark as a
# runtime field, so `Plot().mark_line().encode_boxenplot(...)` compiles.
# It used to fail later, in the render or as a chart that drew nothing,
# with an error naming neither the mark nor the encoder. Mojo 1.0 cannot
# make it a type error: a trait cannot be a collection's element type and
# `render_layers()` takes `List[Plot]` (#522).
#
# The check lives in the encoder rather than in `render()`. That costs
# the calling order -- `mark_*()` must come before `encode_*()` -- and
# buys an error at the call that is actually wrong.
#
# These tests cover the three shapes the accepted sets come in, because
# they are not one encoder to one mark:
#
# - one encoder, one mark, the common case
# - one encoder, several marks that share a payload and differ only in
#   what they draw
# - an encoder that delegates to another, where the inner one has to
#   accept every mark its callers accept


def _xs() -> List[Float64]:
    var x = List[Float64]()
    for i in range(6):
        x.append(Float64(i))
    return x^


def _ys() -> List[Float64]:
    var y = List[Float64]()
    for i in range(6):
        y.append(Float64(i) * 1.5 + 1.0)
    return y^


def _cats() -> List[String]:
    var c = List[String]()
    for i in range(3):
        c.append("c" + String(i))
    return c^


def _groups() -> List[List[Float64]]:
    var g = List[List[Float64]]()
    for i in range(3):
        var row = List[Float64]()
        for j in range(5):
            row.append(Float64((i + 1) * (j + 1)))
        g.append(row^)
    return g^


def test_a_mismatched_encoder_names_both_the_mark_and_itself() raises:
    # The whole point: the message says what was called, what it needed,
    # and what the plot actually is. Asserting on all three, because an
    # error that says only "invalid mark" would pass a weaker test.
    with assert_raises(contains="encode_boxenplot"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())
    with assert_raises(contains="Mark.BOXENPLOT"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())
    with assert_raises(contains="Mark.LINE"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())


def test_the_message_says_which_builder_would_fix_it() raises:
    with assert_raises(contains="mark_boxenplot()"):
        _ = Plot().mark_line().encode_boxenplot(_cats(), _groups())


def test_the_matching_mark_is_accepted_and_renders() raises:
    # The other half of the claim: the check rejects the wrong pairing
    # without breaking the right one.
    var p = Plot().mark_boxenplot().encode_boxenplot(_cats(), _groups())
    var c = render(p^.size(320, 240))
    assert_true(c.width == 320, "the correct pairing still renders")


def test_the_default_mark_needs_no_builder_call() raises:
    # `Plot()` starts at Mark.POINT and `encode()` accepts it, so a
    # plot that never calls a `mark_*()` still encodes. Several tests
    # rely on this to reach render-time validation errors.
    var p = Plot().encode(x=_xs(), y=_ys())
    var c = render(p^.size(200, 150))
    assert_true(c.width == 200, "the default mark encodes")


def test_an_encoder_shared_by_two_marks_accepts_both() raises:
    # BARBS and QUIVER read the same `_barbs` payload and differ only in
    # the glyph. A set, not a single mark.
    var u = List[Float64]()
    var v = List[Float64]()
    for i in range(6):
        u.append(1.0)
        v.append(Float64(i) * 0.5)
    _ = Plot().mark_barbs().encode_barbs(_xs(), _ys(), u, v)
    _ = Plot().mark_quiver().encode_barbs(_xs(), _ys(), u, v)

    # ... and still rejects one that reads a different payload.
    with assert_raises(contains="encode_barbs"):
        _ = Plot().mark_bar().encode_barbs(_xs(), _ys(), u, v)


def test_a_delegating_encoder_does_not_trip_the_inner_check() raises:
    # `encode_ecdf()` delegates to `encode_kde()`, so the inner encoder
    # has to accept Mark.ECDF even though its own name does not suggest
    # it. This is the case the first version of the table got wrong.
    var vals = _ys()
    _ = Plot().mark_ecdf().encode_ecdf(vals)
    _ = Plot().mark_ecdf().encode_kde(vals)
    _ = Plot().mark_kde().encode_kde(vals)


def test_the_reverse_order_now_raises() raises:
    # The cost of checking in the encoder rather than at render time.
    # `encode_*()` before `mark_*()` used to work and no longer does,
    # deliberately: the plot is still Mark.POINT when the encoder runs.
    with assert_raises(contains="encode_boxplot"):
        _ = Plot().encode_boxplot(_cats(), _groups()).mark_box()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
