"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers the `horizontal=True` variants
(#121) of bar, beeswarm, box, grouped_bar, lollipop, stacked_bar, and
violin: each `_render_horizontal_*`'s hand-derived geometry, the 1px
pull-off when the baseline lands on the frame's left axis line,
Theme.color_by_sign/show_data_labels where the vertical path supports
them, the quickplot function matching the fluent builder (concrete
and DType-generic overloads both forwarding `horizontal`),
percent=True with horizontal stacked bars, and the raise paths (a
horizontal bar in render_layers(), a negative violin bandwidth,
length mismatches).

Mark.LOLLIPOP doesn't support color_by_sign/show_data_labels in
either orientation, and isn't a valid render_layers() layer
regardless of orientation, so neither gets a horizontal-specific
test.
"""

from dataviz import (
    bar,
    beeswarm,
    box,
    grouped_bar,
    lollipop,
    stacked_bar,
    violin,
)
from dataviz.plot import Plot, render_layers_svg, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_horizontal_bar.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_bar_matches_hand_derived_rectangles() raises:
    # 2 categories, values=[10, -5], canvas 640x420, default margins (plot
    # area x:[60,620] y:[20,370]). _zero_baseline_y_extent pads [-5,10] to
    # [-5.75, 10.75]: baseline pixel 60 + 5.75/16.5*560 = 255.15 -> 255.
    # Bar A (10): 594.55 -> 595, rect x=255, width=340. Bar B (-5): 85.45
    # -> 85, rect x=85, width=170. Neither edge lands on px0=60, so no
    # pull-off applies.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = (
        Plot()
        .mark_bar(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="256" y="38" width="339" height="140" fill="#1e64b4"/>' in s,
        "bar A, extending right",
    )
    assert_true(
        '<rect x="86" y="213" width="170" height="140" fill="#1e64b4"/>' in s,
        "bar B, extending left",
    )
    assert_true(
        '<text x="255" y="391"' in s and ">0</text>" in s,
        "the 0 tick lands where the baseline math predicts",
    )


def test_render_horizontal_bar_pulls_off_axis_line_when_baseline_touches_left_edge() raises:
    # All-positive data keeps the domain's low end at exactly 0, so the
    # baseline lands on the left axis line (px0=60) and _pull_off_axis_line
    # nudges every bar's left edge to 61.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot()
        .mark_bar(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<rect x="61" y="38" width="266" height="140" fill="#1e64b4"/>' in s,
        "bar A pulled off the axis line",
    )
    assert_true(
        '<rect x="61" y="213" width="533" height="140" fill="#1e64b4"/>' in s,
        "bar B pulled off the axis line",
    )


def test_render_horizontal_bar_color_by_sign() raises:
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var plot = (
        Plot()
        .mark_bar(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(t)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<rect x="256" y="38" width="339" height="140" fill="#1e64b4"/>' in s,
        "positive bar keeps mark_color even with color_by_sign on",
    )
    assert_true(
        '<rect x="86" y="213" width="170" height="140" fill="#c83c3c"/>' in s,
        "negative bar uses mark_color_negative",
    )


def test_render_svg_horizontal_bar_supports_show_data_labels() raises:
    # Same frame as the rectangles test. Bar A (rect x=255,w=340, right
    # edge 595): label 4px right of it, left-aligned, centered on its row
    # (y=38,h=140 -> 108 + Int(12*0.35)=4 -> 112). Bar B (left edge 85):
    # label 4px left of it, right-aligned, row y=213,h=140 -> 283+4 = 287.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = (
        Plot()
        .mark_bar(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<text x="599" y="112" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="start">10</text>'
        in s,
        "bar A's label, right of the bar, left-aligned",
    )
    assert_true(
        '<text x="81" y="287" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="end">-5</text>'
        in s,
        "bar B's label, left of the bar, right-aligned",
    )


def test_bar_horizontal_matches_plot_mark_bar_horizontal() raises:
    # bar(horizontal=True) must render identically to the builder it wraps.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False)
    var from_quickplot = bar(cats, vals, theme=t, horizontal=True)
    var from_builder = (
        Plot()
        .mark_bar(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(t)
    )
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )


def test_render_horizontal_bar_raises_on_no_data() raises:
    # #206: an all-empty Plot used to render a plain background with no
    # axes and no error; _validate_categorical_encoding now raises before
    # any layout, the same as the vertical orientation.
    with assert_raises():
        var plot = (
            Plot().mark_bar(horizontal=True).size(50, 40)
        )  # no encode_categorical() call
        _ = render_svg(plot)


def test_render_layers_raises_on_horizontal_bar_in_a_combo() raises:
    var cats: List[String] = ["A", "B"]
    var bar_y: List[Float64] = [10.0, 20.0]
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [15.0, 5.0]
    var bars = (
        Plot()
        .mark_bar(horizontal=True)
        .encode_categorical(x=cats, y=bar_y)
        .size(400, 300)
    )
    var line = Plot().mark_line().encode(x=idx, y=line_y).size(400, 300)
    var plots: List[Plot] = [bars^, line^]
    with assert_raises():
        _ = render_layers_svg(plots)


# ---------------------------------------------------------------
# from tests/test_horizontal_beeswarm.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_beeswarm_matches_hand_derived_offsets() raises:
    # Same data as the vertical beeswarm test: 1 category, values
    # [10, 11, 50], canvas 400x300, no gridlines, the mirror of the
    # [60,380]x[20,250] frame. x-domain [8,52] runs left-to-right (pixels
    # 75 (v=10), 82 (v=11), 365 (v=50)); the one category spans the whole
    # y-band, center 135. Unlike the vertical case, the x-axis runs the
    # same direction as the values, so 10 sorts before 11: 10 gets offset
    # 0, 11 gets +8.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var plot = (
        Plot()
        .mark_beeswarm(horizontal=True)
        .encode_distribution(categories=cats, values=vals)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<circle cx="75" cy="135" r="4" fill="#1e64b4"/>' in s,
        "value 10 -- offset 0 (first in its row)",
    )
    assert_true(
        '<circle cx="82" cy="143" r="4" fill="#1e64b4"/>' in s,
        "value 11 -- offset +8 (second in its row)",
    )
    assert_true(
        '<circle cx="365" cy="135" r="4" fill="#1e64b4"/>' in s,
        "value 50 -- offset 0 (alone in its row)",
    )


def test_beeswarm_horizontal_matches_plot_mark_beeswarm_horizontal() raises:
    # beeswarm(horizontal=True) must render identically to the builder, and
    # the DType-generic overload must forward horizontal too.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var int_vals: List[List[Int]] = [[10, 11, 50]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = beeswarm(cats, vals, theme=t, horizontal=True)
    var from_builder = (
        Plot()
        .mark_beeswarm(horizontal=True)
        .encode_distribution(categories=cats, values=vals)
        .theme(t)
    )
    var from_dtype = beeswarm(cats, int_vals, theme=t, horizontal=True)
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )
    assert_equal(
        render_svg(from_dtype).to_string(), render_svg(from_builder).to_string()
    )


def test_render_horizontal_beeswarm_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var plot = beeswarm(cats, vals, width=200, height=150, horizontal=True)
        _ = render_svg(plot)


def test_render_horizontal_beeswarm_raises_on_no_data() raises:
    # #206: encode_distribution() now raises immediately on empty
    # categories, before beeswarm() even returns a Plot to render.
    var cats = List[String]()
    var vals = List[List[Float64]]()
    with assert_raises():
        _ = beeswarm(cats, vals, width=200, height=150, horizontal=True)


# ---------------------------------------------------------------
# from tests/test_horizontal_box.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_box_matches_hand_derived_rects_and_outlier() raises:
    # Same data as the vertical box test: "A" = [2,4,4,4,5,5,7,9,20]
    # (q1=4, median=5, q3=7, whiskers 2/9, outlier 20), "B" =
    # [10,12,14,15,18] (q1=12, median=14, q3=15, whiskers 10/18). Canvas
    # 400x300, no gridlines: domain [1.1, 20.9] runs left-to-right, 2
    # categories top-to-bottom (band centers 78/193, bandwidth 92).
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var plot = (
        Plot()
        .mark_box(horizontal=True)
        .encode_boxplot(cats, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<rect x="107" y="32" width="48" height="92" fill="#1e64b4"/>' in s,
        "A's box (q1 to q3)",
    )
    assert_true(
        '<line x1="123" y1="32" x2="123" y2="124"' in s,
        "A's median line (value 5), vertical across the box",
    )
    assert_true(
        '<rect x="236" y="147" width="48" height="92" fill="#1e64b4"/>' in s,
        "B's box (q1 to q3)",
    )
    assert_true(
        '<circle cx="365" cy="78" r="4" fill="#1e64b4"/>' in s,
        "A's single outlier, at value 20",
    )


def test_box_horizontal_matches_plot_mark_box_horizontal() raises:
    # box(horizontal=True) must render identically to the builder, and the
    # DType-generic overload must forward horizontal too.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 7.0, 9.0],
        [10.0, 12.0, 15.0, 18.0],
    ]
    var int_values: List[List[Int]] = [[2, 4, 7, 9], [10, 12, 15, 18]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = box(cats, values, theme=t, horizontal=True)
    var from_builder = (
        Plot().mark_box(horizontal=True).encode_boxplot(cats, values).theme(t)
    )
    var from_dtype = box(cats, int_values, theme=t, horizontal=True)
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )
    assert_equal(
        render_svg(from_dtype).to_string(), render_svg(from_builder).to_string()
    )


def test_render_horizontal_box_raises_on_mismatched_length() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var plot = box(cats, values, horizontal=True)
        _ = render_svg(plot)


# ---------------------------------------------------------------
# from tests/test_horizontal_grouped_bar.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_grouped_bar_matches_hand_derived_rectangles_and_legend() raises:
    # 2 categories, 2 series: values[0] (North) = [10, 20], values[1]
    # (South) = [5, 15], the same data as the vertical grouped-bar test,
    # so its domain [0, 21] carries over. Canvas 400x300, no gridlines,
    # legend reserved -> plot area x:[60,250] y:[20,250].
    #
    # Every value is non-negative, so the baseline lands on the left axis
    # line (px0=60) and every sub-bar's left edge is pulled to 61. Category
    # A's band starts at y=31.5, bandwidth 92, sub_height 46: North
    # y:[32,78), South y:[78,124). Category B's band starts at y=146.5:
    # North y:[147,193), South y:[193,239).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = (
        Plot()
        .mark_grouped_bar(horizontal=True)
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<rect x="61" y="32" width="89" height="46" fill="#1f77b4"/>' in s,
        "A/North",
    )
    assert_true(
        '<rect x="61" y="78" width="44" height="46" fill="#ff7f0e"/>' in s,
        "A/South",
    )
    assert_true(
        '<rect x="61" y="147" width="180" height="46" fill="#1f77b4"/>' in s,
        "B/North",
    )
    assert_true(
        '<rect x="61" y="193" width="135" height="46" fill="#ff7f0e"/>' in s,
        "B/South",
    )

    # Legend at (frame.x_scale.range_max + margin_right, frame.py0) =
    # (270, 20), the same corner as the vertical test on this canvas.
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "North's legend swatch",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "South's legend swatch",
    )


def test_render_svg_horizontal_grouped_bar_supports_show_data_labels_with_mixed_signs() raises:
    # values[0] (North) = [10, -5], values[1] (South) = [20, 15]: mixed
    # signs, so the baseline is no longer on the left axis line and no
    # pull-off applies.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.0], [20.0, 15.0]]
    var plot = (
        Plot()
        .mark_grouped_bar(horizontal=True)
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<rect x="103" y="32" width="69" height="46" fill="#1f77b4"/>' in s,
        "A/North (10)",
    )
    assert_true(
        '<text x="176" y="59" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="start">10</text>'
        in s,
        "A/North's label, right of its own bar, left-aligned",
    )
    assert_true(
        '<rect x="69" y="147" width="34" height="46" fill="#1f77b4"/>' in s,
        "B/North (-5)",
    )
    assert_true(
        '<text x="65" y="174" font-size="12.000" font-family="sans-serif"'
        ' fill="#282828" text-anchor="end">-5</text>'
        in s,
        "B/North's label, left of its own bar (negative), right-aligned",
    )


def test_grouped_bar_horizontal_matches_plot_mark_grouped_bar_horizontal() raises:
    # grouped_bar(horizontal=True) must render identically to the builder,
    # and the DType-generic overload must forward horizontal too.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var int_values: List[List[Int]] = [[10, 20], [5, 15]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = grouped_bar(
        cats, names, values, theme=t, horizontal=True
    )
    var from_builder = (
        Plot()
        .mark_grouped_bar(horizontal=True)
        .encode_grouped_bar(cats, names, values)
        .theme(t)
    )
    var from_dtype = grouped_bar(
        cats, names, int_values, theme=t, horizontal=True
    )
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )
    assert_equal(
        render_svg(from_dtype).to_string(), render_svg(from_builder).to_string()
    )


def test_render_horizontal_grouped_bar_raises_on_zero_length_categories() raises:
    # #206: _validate_grouped_bar_series now raises on empty
    # categories/series_names rather than rendering a blank background.
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var plot = (
            Plot()
            .mark_grouped_bar(horizontal=True)
            .encode_grouped_bar(cats, names, values)
            .size(200, 150)
        )
        _ = render_svg(plot)


# ---------------------------------------------------------------
# from tests/test_horizontal_lollipop.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_lollipop_matches_hand_derived_positions() raises:
    # Same 2-category, values=[10,-5], 640x420 frame as the horizontal bar
    # test (plot area x:[60,620] y:[20,370], baseline pixel 255). Row
    # centers: band height 175 -> A=107.5, B=282.5. Stem A (10): 594.545.
    # Stem B (-5): 85.455. Each point sits on its own stem's endpoint;
    # before Mark.LOLLIPOP moved onto Float64 coordinates the point was
    # rounded (595 and 85) and so sat a pixel off the stem it caps.
    # Neither stem start lands on px0=60, so no pull-off applies.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var plot = (
        Plot()
        .mark_lollipop(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<path d="M255.152,107.500 L594.545,107.500"' in s,
        "stem A, extending right from the baseline",
    )
    assert_true(
        '<circle cx="594.545" cy="107.500" r="4.000" fill="#1e64b4"/>' in s,
        "point A, on its stem's endpoint",
    )
    assert_true(
        '<path d="M255.152,282.500 L85.455,282.500"' in s,
        "stem B, extending left from the baseline",
    )
    assert_true(
        '<circle cx="85.455" cy="282.500" r="4.000" fill="#1e64b4"/>' in s,
        "point B, on its stem's endpoint",
    )
    assert_true(
        '<text x="255" y="391"' in s and ">0</text>" in s,
        "the 0 tick lands where the baseline math predicts",
    )


def test_render_horizontal_lollipop_pulls_off_axis_line_when_baseline_touches_left_edge() raises:
    # All-positive data keeps the baseline on the left axis line (px0=60),
    # so the stem start nudges to 61, as the vertical lollipop and
    # horizontal bar paths do at their axis lines.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, 20.0]
    var plot = (
        Plot()
        .mark_lollipop(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
    )
    var s = render_svg(plot).to_string()
    assert_true(
        '<path d="M61.000,107.500 L326.667,107.500"' in s,
        "stem A pulled off the axis line",
    )
    assert_true(
        '<path d="M61.000,282.500 L593.333,282.500"' in s,
        "stem B pulled off the axis line",
    )


def test_lollipop_horizontal_matches_plot_mark_lollipop_horizontal() raises:
    # lollipop(horizontal=True) must render identically to the builder it
    # wraps.
    var cats: List[String] = ["A", "B"]
    var vals: List[Float64] = [10.0, -5.0]
    var t = Theme(show_gridlines=False)
    var from_quickplot = lollipop(cats, vals, theme=t, horizontal=True)
    var from_builder = (
        Plot()
        .mark_lollipop(horizontal=True)
        .encode_categorical(x=cats, y=vals)
        .theme(t)
    )
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )


def test_lollipop_dtype_generic_overload_forwards_horizontal() raises:
    # The DType-generic lollipop overload must forward horizontal to the
    # concrete one; this was once missing, silently rendering vertical.
    var cats: List[String] = ["A", "B"]
    var vals: List[Int] = [10, -5]
    var float_vals: List[Float64] = [10.0, -5.0]
    var from_dtype = lollipop(cats, vals, horizontal=True)
    var from_concrete = lollipop(cats, float_vals, horizontal=True)
    assert_equal(
        render_svg(from_dtype).to_string(),
        render_svg(from_concrete).to_string(),
    )


def test_render_horizontal_lollipop_raises_on_no_data() raises:
    # #206: see test_render_horizontal_bar_raises_on_no_data above.
    with assert_raises():
        var plot = (
            Plot().mark_lollipop(horizontal=True).size(50, 40)
        )  # no encode_categorical() call
        _ = render_svg(plot)


# ---------------------------------------------------------------
# from tests/test_horizontal_stacked_bar.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_stacked_bar_matches_hand_derived_rectangles_and_legend() raises:
    # Same North=[10,20]/South=[5,15] data as the horizontal grouped-bar
    # test, stacked: category totals 15 and 35, so _zero_baseline_y_extent
    # gives [0, 36.75]. Canvas 400x300, no gridlines, legend reserved,
    # frame x:[60,250] y:[20,250].
    #
    # Each row is the full band height (92): band_y(A)=32, band_y(B)=147.
    # North's segment starts at the baseline (pulled to 61); South's picks
    # up where North's left off.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = (
        Plot()
        .mark_stacked_bar(horizontal=True)
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<rect x="61" y="32" width="51" height="92" fill="#1f77b4"/>' in s,
        "A/North",
    )
    assert_true(
        '<rect x="112" y="32" width="26" height="92" fill="#ff7f0e"/>' in s,
        "A/South, picks up where North left off",
    )
    assert_true(
        '<rect x="61" y="147" width="102" height="92" fill="#1f77b4"/>' in s,
        "B/North",
    )
    assert_true(
        '<rect x="163" y="147" width="78" height="92" fill="#ff7f0e"/>' in s,
        "B/South",
    )

    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "North's legend swatch",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "South's legend swatch",
    )


def test_render_svg_horizontal_stacked_bar_percent_fixes_x_axis_to_0_100() raises:
    # values[0] (North) = [10, 30], values[1] (South) = [20, 10]. A: total
    # 30 -> North 33.33% -> [0,33.33], South -> [33.33,100]. B: total 40 ->
    # North 75% -> [0,75], South -> [75,100]. The x-axis is fixed to
    # [0,100], confirmed by the "100" tick landing at the frame's right
    # edge (250).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 30.0], [20.0, 10.0]]
    var plot = (
        Plot()
        .mark_stacked_bar(percent=True, horizontal=True)
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<text x="250" y="271"' in s and ">100</text>" in s,
        "the x-axis is fixed to end at exactly 100",
    )
    assert_true(
        '<rect x="61" y="32" width="62" height="92" fill="#1f77b4"/>' in s,
        "A/North, 33.3% of A's total",
    )
    assert_true(
        '<rect x="123" y="32" width="127" height="92" fill="#ff7f0e"/>' in s,
        "A/South, the remaining 66.7%",
    )
    assert_true(
        '<rect x="61" y="147" width="142" height="92" fill="#1f77b4"/>' in s,
        "B/North, 75% of B's total",
    )
    assert_true(
        '<rect x="203" y="147" width="47" height="92" fill="#ff7f0e"/>' in s,
        "B/South, the remaining 25%",
    )


def test_render_horizontal_stacked_bar_percent_raises_on_a_negative_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    with assert_raises():
        var plot = (
            Plot()
            .mark_stacked_bar(percent=True, horizontal=True)
            .encode_grouped_bar(cats, names, values)
        )
        _ = render_svg(plot)


def test_stacked_bar_horizontal_matches_plot_mark_stacked_bar_horizontal() raises:
    # stacked_bar(horizontal=True) must render identically to the builder,
    # and the DType-generic overload must forward horizontal too.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var int_values: List[List[Int]] = [[10, 20], [5, 15]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = stacked_bar(
        cats, names, values, theme=t, horizontal=True
    )
    var from_builder = (
        Plot()
        .mark_stacked_bar(horizontal=True)
        .encode_grouped_bar(cats, names, values)
        .theme(t)
    )
    var from_dtype = stacked_bar(
        cats, names, int_values, theme=t, horizontal=True
    )
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )
    assert_equal(
        render_svg(from_dtype).to_string(), render_svg(from_builder).to_string()
    )


def test_render_horizontal_stacked_bar_raises_on_zero_length_categories() raises:
    # #206: see test_render_horizontal_grouped_bar_raises_on_zero_length_categories above.
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var plot = (
            Plot()
            .mark_stacked_bar(horizontal=True)
            .encode_grouped_bar(cats, names, values)
            .size(200, 150)
        )
        _ = render_svg(plot)


# ---------------------------------------------------------------
# from tests/test_horizontal_violin.mojo
# ---------------------------------------------------------------


def test_render_svg_horizontal_violin_matches_hand_derived_silhouette_points() raises:
    # 2 categories ("Section A"/"Section B", the violin docstring example's
    # data), canvas 400x300, no gridlines. The dynamic left margin grows to
    # fit those labels, so plot_x0 is 72 rather than 60. Rather than
    # re-deriving all 60 KDE points per category, this checks the first
    # sampled point (the curve's left edge at each category's min value)
    # of each closed path.
    var cats: List[String] = ["Section A", "Section B"]
    var values: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0, 74.0, 76.0, 91.0],
        [65.0, 70.0, 72.0, 88.0, 90.0, 92.0, 95.0],
    ]
    var plot = (
        Plot()
        .mark_violin(horizontal=True)
        .encode_distribution(categories=cats, values=values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()

    assert_true(
        '<path d="M151.000,103.966' in s,
        "Section A's silhouette starts at its own min(values)=72",
    )
    assert_true(
        '<path d="M86.000,215.697' in s,
        "Section B's silhouette starts at its own min(values)=65",
    )


def test_violin_horizontal_matches_plot_mark_violin_horizontal() raises:
    # violin(horizontal=True) must render identically to the builder, and
    # the DType-generic overload must forward horizontal too.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0],
        [65.0, 70.0, 88.0, 90.0],
    ]
    var int_values: List[List[Int]] = [[72, 75, 78, 80], [65, 70, 88, 90]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = violin(cats, values, theme=t, horizontal=True)
    var from_builder = (
        Plot()
        .mark_violin(horizontal=True)
        .encode_distribution(categories=cats, values=values)
        .theme(t)
    )
    var from_dtype = violin(cats, int_values, theme=t, horizontal=True)
    assert_equal(
        render_svg(from_quickplot).to_string(),
        render_svg(from_builder).to_string(),
    )
    assert_equal(
        render_svg(from_dtype).to_string(), render_svg(from_builder).to_string()
    )


def test_violin_horizontal_accepts_bandwidth_and_scale_by_count() raises:
    # bandwidth/scale_by_count are orientation-independent; this confirms
    # they still apply with horizontal=True.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0],
        [65.0, 70.0, 88.0, 90.0, 92.0],
    ]
    var plot = (
        Plot()
        .mark_violin(bandwidth=5.0, scale_by_count=True, horizontal=True)
        .encode_distribution(categories=cats, values=values)
    )
    var s = render_svg(plot).to_string()
    assert_true(
        "<path" in s,
        "still renders a silhouette with bandwidth/scale_by_count overrides",
    )


def test_render_horizontal_violin_raises_on_negative_bandwidth() raises:
    var cats: List[String] = ["A"]
    var values: List[List[Float64]] = [[1.0, 2.0, 3.0]]
    with assert_raises():
        var plot = (
            Plot()
            .mark_violin(bandwidth=-1.0, horizontal=True)
            .encode_distribution(categories=cats, values=values)
        )
        _ = render_svg(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
