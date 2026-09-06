"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.GROUPED_BAR, Mark.STACKED_BAR
(including independent positive/negative stacking and percent=True),
Mark.MARIMEKKO, Mark.POPULATION_PYRAMID, Mark.SPAN_CHART, Mark.GANTT,
Mark.FUNNEL, Mark.HEATMAP, Mark.PUNCHCARD, Mark.CORRPLOT, and
Mark.CALENDAR_HEATMAP, each raster + SVG plus its encode_*()
validation.
"""

from _test_helpers import (
    BG,
    _assert_color,
    _bbox_of_color,
    _count_color,
)
from canvas.color import Color
from canvas.path import PathOp
from canvas.vector.svg import SvgCanvas
from dataviz import (
    calendar_heatmap,
    corrplot,
    funnel,
    gantt,
    grouped_bar,
    heatmap,
    marimekko,
    population_pyramid,
    punchcard,
    span_chart,
    stacked_bar,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
)
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_grouped_bar.mojo
# ---------------------------------------------------------------


def test_render_grouped_bar_matches_hand_derived_rectangles() raises:
    # 2 categories ("A"/"B"), 2 series: values[0] (North) = [10, 20],
    # values[1] (South) = [5, 15] (North_A=10, North_B=20, South_A=5,
    # South_B=15). Canvas 400x300, default margins, no gridlines, legend
    # reserved -> OrdinalScale range [60, 250].
    #
    # y-domain: _zero_baseline_y_extent over every value -> [0, 21].
    # OrdinalScale over [60, 250], 2 categories: step=95, bandwidth=76 ->
    # band_start(A)=69.5, band_start(B)=164.5, sub_width=38. Each sub-bar's
    # edges are rounded boundaries, not an independently rounded width (see
    # _draw_grouped_bars).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = grouped_bar(
        cats, names, values, theme=t, width=400, height=300
    )
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    # A, North (series 0, value 10): x:[70,108), y:[140,250)
    _assert_color(c, 89, 200, palette[0], "A/North bar, well inside")
    # A, South (series 1, value 5): x:[108,146), y:[195,250)
    _assert_color(c, 127, 220, palette[1], "A/South bar, well inside")
    # B, North (series 0, value 20): x:[165,203), y:[31,250)
    _assert_color(c, 184, 100, palette[0], "B/North bar, well inside")
    # B, South (series 1, value 15): x:[203,241), y:[86,250)
    _assert_color(c, 222, 150, palette[1], "B/South bar, well inside")
    # No gap within a category (consecutive-boundary rounding), but a real
    # gap between A and B (band_start(B)=164.5 vs A's end at 145.5): x=155
    # is background at any y.
    _assert_color(
        c, 155, 150, BG, "the inter-category gap between A and B -- background"
    )


def test_render_svg_grouped_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    # Every sub-bar is non-negative, so every bottom edge lands on the axis
    # line and each height is pulled 1px (see _pull_off_axis_line).
    assert_true(
        '<rect x="70" y="141" width="38" height="109" fill="#1f77b4"/>' in s,
        "A/North",
    )
    assert_true(
        '<rect x="108" y="196" width="38" height="54" fill="#ff7f0e"/>' in s,
        "A/South",
    )
    assert_true(
        '<rect x="165" y="31" width="38" height="219" fill="#1f77b4"/>' in s,
        "B/North",
    )
    assert_true(
        '<rect x="203" y="86" width="38" height="164" fill="#ff7f0e"/>' in s,
        "B/South",
    )

    # _draw_legend's row layout is covered by the POINT/ARC legend tests;
    # this confirms the labels/palette/start: x=250+20=270, y=20 (row 0),
    # row 1 at y=42.
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "North's legend swatch",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "South's legend swatch",
    )


def test_render_grouped_bar_raises_on_zero_length_categories() raises:
    # #206: _validate_grouped_bar_series now raises on empty
    # categories/series_names rather than rendering a blank background.
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted2 = grouped_bar(cats, names, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_grouped_bar_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted3 = grouped_bar(cats, names, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_grouped_bar_raises_on_mismatched_value_series_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted4 = grouped_bar(cats, names, values, width=200, height=150)
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# from tests/test_stacked_bar.mojo
# ---------------------------------------------------------------


def test_render_stacked_bar_matches_hand_derived_rectangles() raises:
    # Same 2-category/2-series data and frame as the grouped-bar test (range
    # [60,250], band_start(A)=70, band_start(B)=165, bandwidth=76); all
    # positive, so only the positive running total moves. North stacks
    # first (bottom=0), South on top. y-domain: _zero_baseline_y_extent
    # over each category's final total (15, 35) -> [0, 36.75]. Full band
    # width per segment.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = stacked_bar(
        cats, names, values, theme=t, width=400, height=300
    )
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    # A, North (bottom segment, value 10): x:[70,146), y:[187,250)
    _assert_color(c, 100, 220, palette[0], "A/North segment, well inside")
    # A, South (top segment, value 5, stacked on North): x:[70,146), y:[156,187)
    _assert_color(
        c, 100, 170, palette[1], "A/South segment, stacked on top of North"
    )
    # B, North (bottom segment, value 20): x:[165,241), y:[125,250)
    _assert_color(c, 195, 200, palette[0], "B/North segment, well inside")
    # B, South (top segment, value 15, stacked on North): x:[165,241), y:[31,125)
    _assert_color(
        c, 195, 80, palette[1], "B/South segment, stacked on top of North"
    )
    # Segments share the full band width, so no gap within a category; the
    # inter-category gap remains: x=155 is background.
    _assert_color(
        c, 155, 150, BG, "the inter-category gap between A and B -- background"
    )


def test_render_svg_stacked_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    # Only each column's bottom segment (North, seg_bottom=0) touches the
    # axis line, so only its height is pulled 1px (63->62, 125->124).
    assert_true(
        '<rect x="70" y="188" width="76" height="62" fill="#1f77b4"/>' in s,
        "A/North",
    )
    assert_true(
        '<rect x="70" y="157" width="76" height="31" fill="#ff7f0e"/>' in s,
        "A/South",
    )
    assert_true(
        '<rect x="165" y="125" width="76" height="125" fill="#1f77b4"/>' in s,
        "B/North",
    )
    assert_true(
        '<rect x="165" y="31" width="76" height="94" fill="#ff7f0e"/>' in s,
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


def test_render_svg_stacked_bar_mixed_sign_stacks_independently_each_direction() raises:
    # One category, North=10 and South=-5: a negative value stacks downward
    # from its own running negative total rather than sliding North's
    # segment down. y-domain: _zero_baseline_y_extent over [10, -5] ->
    # [-5.75, 10.75]. band_start(0)=79, bandwidth=152.
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    var plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    # North: data range [0,10] (positive stack, starts at zero).
    assert_true(
        '<rect x="80" y="31" width="152" height="139" fill="#1f77b4"/>' in s,
        "North, above zero",
    )
    # South: data range [-5,0] (negative stack, starts at zero, extends down).
    assert_true(
        '<rect x="80" y="170" width="152" height="70" fill="#ff7f0e"/>' in s,
        "South, below zero",
    )


def test_render_stacked_bar_raises_on_zero_length_categories() raises:
    # #206: see test_render_grouped_bar_raises_on_zero_length_categories above.
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted2 = stacked_bar(cats, names, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_stacked_bar_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted3 = stacked_bar(cats, names, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_stacked_bar_raises_on_mismatched_value_series_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted4 = stacked_bar(cats, names, values, width=200, height=150)
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# from tests/test_percent_stacked_bar.mojo
# ---------------------------------------------------------------


def test_render_svg_percent_stacked_bar_matches_hand_derived_rectangles() raises:
    # Same frame as the stacked-bar tests (range [60,250],
    # band_start(A)=70, band_start(B)=165, bandwidth=76); percent=True
    # fixes the y-domain to [0, 100], so 0 -> 250 and 100 -> 20 with no
    # padding. A: North=30, South=10 -> 75%/25%. B: North=20, South=30 ->
    # 40%/60%.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 20.0], [10.0, 30.0]]
    var plot = (
        Plot()
        .mark_stacked_bar(percent=True)
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    # A/North: bottom segment, 0..75 -> py 250..78 (230*0.75=172.5), height 171.
    assert_true(
        '<rect x="70" y="78" width="76" height="172" fill="#1f77b4"/>' in s,
        "A/North (75%)",
    )
    # A/South: stacked on top, 75..100 -> py 78..20, height 58.
    assert_true(
        '<rect x="70" y="21" width="76" height="57" fill="#ff7f0e"/>' in s,
        "A/South (25%)",
    )
    # B/North: bottom segment, 0..40 -> py 250..158 (230*0.40=92), height 91.
    assert_true(
        '<rect x="165" y="159" width="76" height="91" fill="#1f77b4"/>' in s,
        "B/North (40%)",
    )
    # B/South: stacked on top, 40..100 -> py 158..20, height 138.
    assert_true(
        '<rect x="165" y="21" width="76" height="138" fill="#ff7f0e"/>' in s,
        "B/South (60%)",
    )


def test_render_svg_percent_stacked_bar_all_zero_category_is_an_empty_column() raises:
    # Category B's values are all zero: category_total is 0.0,
    # scale_factor takes the 0.0 branch, and every segment draws at zero
    # height on the axis line. Category A renders normally.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 0.0], [20.0, 0.0]]
    var plot = (
        Plot()
        .mark_stacked_bar(percent=True)
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<rect x="70" y="113" width="76" height="137" fill="#1f77b4"/>' in s,
        "A/North (60%), unaffected",
    )
    assert_true(
        '<rect x="70" y="21" width="76" height="92" fill="#ff7f0e"/>' in s,
        "A/South (40%), unaffected",
    )
    assert_true(
        '<rect x="165" y="251" width="76" height="0" fill="#1f77b4"/>' in s,
        "B/North, zero-height",
    )
    assert_true(
        '<rect x="165" y="251" width="76" height="0" fill="#ff7f0e"/>' in s,
        "B/South, zero-height",
    )


def test_render_raises_on_percent_stacked_bar_with_a_negative_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[-5.0], [20.0]]
    with assert_raises():
        var plot = (
            Plot()
            .mark_stacked_bar(percent=True)
            .encode_grouped_bar(cats, names, values)
        )
        _ = render_svg(plot)


def test_render_svg_non_percent_stacked_bar_is_unaffected_by_percent_flag() raises:
    # percent=False (the default) keeps the raw-value behavior the
    # stacked-bar tests confirm.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(cats, names, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true(
        '<rect x="70" y="188" width="76" height="62" fill="#1f77b4"/>' in s,
        "A/North, raw",
    )
    assert_true(
        '<rect x="70" y="157" width="76" height="31" fill="#ff7f0e"/>' in s,
        "A/South, raw",
    )


def test_stacked_bar_quickplot_accepts_percent_kwarg() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 20.0], [10.0, 30.0]]
    var c = stacked_bar(
        cats, names, values, width=400, height=300, percent=True
    )
    var svg = render_svg(c)
    var s = svg.to_string()
    assert_true(
        '<rect x="70" y="78" width="76" height="172" fill="#1f77b4"/>' in s,
        "quickplot percent=True",
    )


# ---------------------------------------------------------------
# from tests/test_marimekko.mojo
# ---------------------------------------------------------------


def test_render_marimekko_matches_hand_derived_columns() raises:
    # 2 categories, 2 subcategories: values[X] = [30, 10], values[Y] =
    # [10, 30]. Both columns total 40 (grand total 80), so each gets half
    # the width. Canvas 400x300, no gridlines, no legend: plot area
    # x:[60,380], y:[20,250] -> column A x:[60,220), column B x:[220,380).
    # Column A's X segment (75% of 230 = 172.5 -> 172) sits at the bottom,
    # y:[78,250); column B's Y segment (75%) sits at the bottom,
    # y:[193,250).
    var cats: List[String] = ["A", "B"]
    var subs: List[String] = ["X", "Y"]
    var values: List[List[Float64]] = [[30.0, 10.0], [10.0, 30.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = marimekko(
        cats, subs, values, theme=t, width=400, height=300
    )
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(
        c, 140, 150, palette[0], "column A, well inside the X (bottom) segment"
    )
    _assert_color(
        c, 140, 40, palette[1], "column A, well inside the Y (top) segment"
    )
    _assert_color(
        c, 300, 220, palette[0], "column B, well inside the X (bottom) segment"
    )
    _assert_color(
        c, 300, 100, palette[1], "column B, well inside the Y (top) segment"
    )


def test_render_marimekko_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var subs: List[String] = ["X", "Y"]
    var values: List[List[Float64]] = [[30.0, 10.0], [10.0, 30.0]]
    var plot = (
        Plot()
        .mark_marimekko()
        .encode_marimekko(categories=cats, subcategories=subs, values=values)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="60" y="78" width="160" height="172" fill="#1f77b4"/>' in s,
        "column A, X segment",
    )
    assert_true(
        '<rect x="60" y="20" width="160" height="58" fill="#ff7f0e"/>' in s,
        "column A, Y segment",
    )
    assert_true(
        '<rect x="220" y="193" width="160" height="57" fill="#1f77b4"/>' in s,
        "column B, X segment",
    )
    assert_true(
        '<rect x="220" y="20" width="160" height="173" fill="#ff7f0e"/>' in s,
        "column B, Y segment",
    )


def test_render_marimekko_raises_on_wrong_row_count() raises:
    var cats: List[String] = ["A", "B"]
    var subs: List[String] = ["X", "Y", "Z"]
    var values: List[List[Float64]] = [[1.0, 2.0], [3.0, 4.0]]
    with assert_raises():
        var _hoisted2 = marimekko(cats, subs, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_marimekko_raises_on_wrong_column_count() raises:
    var cats: List[String] = ["A", "B", "C"]
    var subs: List[String] = ["X"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted3 = marimekko(cats, subs, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_marimekko_raises_on_negative_value() raises:
    var cats: List[String] = ["A"]
    var subs: List[String] = ["X"]
    var values: List[List[Float64]] = [[-1.0]]
    with assert_raises():
        var _hoisted4 = marimekko(cats, subs, values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_marimekko_raises_on_all_zero_values() raises:
    var cats: List[String] = ["A", "B"]
    var subs: List[String] = ["X"]
    var values: List[List[Float64]] = [[0.0, 0.0]]
    with assert_raises():
        var _hoisted5 = marimekko(cats, subs, values, width=200, height=150)
        _ = render(_hoisted5)


def test_render_marimekko_raises_on_no_data() raises:
    # #206: an all-empty Plot used to render a plain background with no
    # error; the render-time empty check now raises before any layout.
    var cats = List[String]()
    var subs = List[String]()
    var values = List[List[Float64]]()
    with assert_raises():
        var _hoisted6 = marimekko(cats, subs, values, width=100, height=80)
        _ = render(_hoisted6)


# ---------------------------------------------------------------
# from tests/test_population_pyramid.mojo
# ---------------------------------------------------------------


def test_render_population_pyramid_matches_hand_derived_bars() raises:
    # 2 categories, left=[10, 30], right=[20, 10]. Canvas 400x300, no
    # gridlines, no legend. The largest magnitude is 30 -> pad 1.5 ->
    # symmetric x-domain [-31.5, 31.5] over x:[60, 380], so the center
    # baseline lands at pixel 220. OrdinalScale over y:[20, 250] (step
    # 115, bandwidth 92), the same numbers as the gantt test.
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 30.0]
    var right: List[Float64] = [20.0, 10.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = population_pyramid(
        cats, left, right, theme=t, width=400, height=300
    )
    var c = render(_hoisted1)

    var palette = default_categorical_palette()

    # A's row, y:[32,124) -- left bar x:[169,220), right bar x:[220,322).
    _assert_color(c, 190, 60, palette[0], "A's left bar, well inside")
    _assert_color(c, 270, 60, palette[1], "A's right bar, well inside")
    _assert_color(c, 100, 60, BG, "left of A's left bar -- background")

    # B's row, y:[147,239) -- left bar x:[68,220), right bar x:[220,271).
    _assert_color(c, 100, 180, palette[0], "B's left bar, well inside")
    _assert_color(c, 250, 180, palette[1], "B's right bar, well inside")
    _assert_color(c, 330, 180, BG, "right of B's right bar -- background")

    _assert_color(
        c, 190, 140, BG, "the gap between A's and B's rows -- background"
    )


def test_render_population_pyramid_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 30.0]
    var right: List[Float64] = [20.0, 10.0]
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(
            categories=cats, left_values=left, right_values=right
        )
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="170" y="32" width="51" height="92" fill="#1f77b4"/>' in s,
        "A's left bar",
    )
    assert_true(
        '<rect x="221" y="32" width="101" height="92" fill="#ff7f0e"/>' in s,
        "A's right bar",
    )
    assert_true(
        '<rect x="68" y="147" width="153" height="92" fill="#1f77b4"/>' in s,
        "B's left bar",
    )
    assert_true(
        '<rect x="221" y="147" width="50" height="92" fill="#ff7f0e"/>' in s,
        "B's right bar",
    )


def test_render_population_pyramid_zero_magnitude_draws_no_bar() raises:
    # A zero on one side draws no bar, unlike Mark.GANTT's 1px milestone
    # floor.
    var cats: List[String] = ["Only"]
    var left: List[Float64] = [0.0]
    var right: List[Float64] = [10.0]
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(
            categories=cats, left_values=left, right_values=right
        )
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        'fill="#1f77b4"' not in s,
        "zero-magnitude left side draws no rect at all",
    )
    assert_true('fill="#ff7f0e"' in s, "the non-zero right side still draws")


def test_render_population_pyramid_legend_uses_left_right_fallback_names() raises:
    # With no left_name/right_name the legend still draws, falling back to
    # "Left"/"Right".
    var cats: List[String] = ["A"]
    var left: List[Float64] = [10.0]
    var right: List[Float64] = [10.0]
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(
            categories=cats, left_values=left, right_values=right
        )
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">Left<" in s, "the fallback legend label for the left side")
    assert_true(">Right<" in s, "the fallback legend label for the right side")


def test_render_population_pyramid_legend_uses_given_names() raises:
    var cats: List[String] = ["A"]
    var left: List[Float64] = [10.0]
    var right: List[Float64] = [10.0]
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(
            categories=cats,
            left_values=left,
            right_values=right,
            left_name="Male",
            right_name="Female",
        )
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">Male<" in s, "the given left legend label")
    assert_true(">Female<" in s, "the given right legend label")


def test_render_population_pyramid_raises_on_mismatched_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = population_pyramid(
            cats, one, one, width=200, height=150
        )
        _ = render(_hoisted2)


def test_render_population_pyramid_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var cats = List[String]()
    var vals = List[Float64]()
    with assert_raises():
        var _hoisted3 = population_pyramid(
            cats, vals, vals, width=200, height=150
        )
        _ = render(_hoisted3)


# ---------------------------------------------------------------
# from tests/test_span_chart.mojo
# ---------------------------------------------------------------


def test_render_span_chart_matches_hand_derived_bars() raises:
    # 2 categories: "A" spans [10,40], "B" spans [50,90], the gantt test's
    # numbers on the vertical frame. Canvas 400x300, no gridlines: plot
    # area x:[60,380], y:[20,250]. _data_extent pads the 80-span by 4.0 ->
    # y-domain [6, 94]. OrdinalScale over [60,380] (step=160, bandwidth
    # 128): band A x:[76,204], band B x:[236,364]. Bar A -> rect (76, 161,
    # 128, 79); bar B -> rect (236, 30, 128, 105).
    var cats: List[String] = ["A", "B"]
    var low: List[Float64] = [10.0, 50.0]
    var high: List[Float64] = [40.0, 90.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = span_chart(cats, low, high, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c, 140, 200, t.mark_color, "well inside bar A's rect (76,161,128,79)"
    )
    _assert_color(
        c, 300, 80, t.mark_color, "well inside bar B's rect (236,30,128,105)"
    )
    _assert_color(c, 220, 100, BG, "the gap between the two bars")


def test_render_span_chart_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var low: List[Float64] = [10.0, 50.0]
    var high: List[Float64] = [40.0, 90.0]
    var plot = (
        Plot()
        .mark_span_chart()
        .encode_gantt(categories=cats, start=low, end=high)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="76" y="161" width="128" height="79" fill="#1e64b4"/>' in s,
        "bar A's rect",
    )
    assert_true(
        '<rect x="236" y="30" width="128" height="105" fill="#1e64b4"/>' in s,
        "bar B's rect",
    )


def test_render_span_chart_zero_length_span_floors_to_one_pixel() raises:
    var cats: List[String] = ["A"]
    var low: List[Float64] = [10.0]
    var high: List[Float64] = [10.0]
    var _hoisted2 = span_chart(cats, low, high, width=200, height=150)
    var c = render(_hoisted2)
    # A zero-height bar neither raises nor vanishes: floored to 1px, as
    # Mark.GANTT's is.
    _ = c


def test_render_span_chart_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var low: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted3 = span_chart(cats, low, high, width=200, height=150)
        _ = render(_hoisted3)


def test_render_span_chart_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var cats = List[String]()
    var low = List[Float64]()
    var high = List[Float64]()
    with assert_raises():
        var _hoisted4 = span_chart(cats, low, high, width=100, height=80)
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# from tests/test_gantt.mojo
# ---------------------------------------------------------------


def test_render_gantt_matches_hand_derived_bars() raises:
    # 2 categories (short labels keep the left margin at 60). Canvas
    # 400x300, plot area x:[60,380], y:[20,250], no gridlines. "A" spans
    # [10,40], "B" spans [50,90]: _data_extent pads the 80-span by 4.0 ->
    # x-domain [6, 94]. OrdinalScale over y:[20,250] (step=115, bandwidth
    # 92), with category 0 at the top.
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = gantt(cats, start, end, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c,
        100,
        60,
        t.mark_color,
        "A's bar (x:[75,184), y:[32,124)), well inside",
    )
    _assert_color(
        c,
        250,
        180,
        t.mark_color,
        "B's bar (x:[220,365), y:[147,239)), well inside",
    )
    _assert_color(
        c, 100, 140, BG, "the gap between A's and B's rows -- background"
    )
    _assert_color(
        c, 200, 60, BG, "A's row, but past its bar's right edge -- background"
    )
    _assert_color(c, 10, 60, BG, "left of the plot area entirely -- background")


def test_render_gantt_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var plot = (
        Plot()
        .mark_gantt()
        .encode_gantt(cats, start, end)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="75" y="32" width="109" height="92" fill="#1e64b4"/>' in s,
        "A's bar",
    )
    assert_true(
        '<rect x="220" y="147" width="145" height="92" fill="#1e64b4"/>' in s,
        "B's bar",
    )


def test_render_gantt_zero_length_span_floors_to_one_pixel() raises:
    # A milestone (start == end) is real data, floored to 1px rather than
    # drawn as a zero-width rect.
    var cats: List[String] = ["Launch"]
    var start: List[Float64] = [50.0]
    var end: List[Float64] = [50.0]
    var plot = (
        Plot()
        .mark_gantt()
        .encode_gantt(cats, start, end)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        'width="1"' in s, "the milestone's bar, floored to a visible 1px width"
    )


def test_render_gantt_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = gantt(cats, one, one, width=200, height=150)
        _ = render(_hoisted2)


def test_render_gantt_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var cats = List[String]()
    var empty = List[Float64]()
    with assert_raises():
        var _hoisted3 = gantt(cats, empty, empty, width=200, height=150)
        _ = render(_hoisted3)


# ---------------------------------------------------------------
# from tests/test_funnel.mojo
# ---------------------------------------------------------------


def test_render_funnel_matches_hand_derived_trapezoids() raises:
    # 3 categories already in descending order (100, 60, 20), isolating the
    # taper math from the sort. Canvas 400x300, no legend: plot area
    # x:[60,380], y:[20,250], center x=220, max_width=320,
    # row_height=76.667. top_width = 320/192/64; bottom_width = the next
    # row's top (192/64), and the last row's bottom matches its top.
    # Sampled at each row's vertical midpoint at x=220, always inside a
    # symmetric trapezoid.
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Float64] = [100.0, 60.0, 20.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = funnel(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(
        c, 220, 58, palette[0], "row 0 (A, value 100) -- the widest row"
    )
    _assert_color(c, 220, 134, palette[1], "row 1 (B, value 60)")
    _assert_color(
        c, 220, 211, palette[2], "row 2 (C, value 20) -- the narrowest row"
    )
    _assert_color(c, 10, 10, BG, "outside the whole funnel -- background")


def test_render_funnel_svg_matches_confirmed_paths() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Float64] = [100.0, 60.0, 20.0]
    var plot = (
        Plot()
        .mark_funnel()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M60.000,20.000 L380.000,20.000 L316.000,96.000'
        ' L124.000,96.000 Z" fill="#1f77b4"/>'
        in s,
        "row 0",
    )
    assert_true(
        '<path d="M124.000,96.000 L316.000,96.000 L252.000,173.000'
        ' L188.000,173.000 Z" fill="#ff7f0e"/>'
        in s,
        "row 1",
    )
    assert_true(
        '<path d="M188.000,173.000 L252.000,173.000 L252.000,250.000'
        ' L188.000,250.000 Z" fill="#2ca02c"/>'
        in s,
        "row 2 -- flat bottom, matching its top",
    )


def test_render_funnel_sorts_largest_value_first_regardless_of_input_order() raises:
    # "Small" (10) given *before* "Big" (100) -- the opposite of
    # display order. If sorting works, row 0 (drawn first, topmost) is
    # still "Big," so its top edge spans the full plot width edge
    # to edge (the largest value always does, by construction) --
    # confirmed geometrically, no need to parse the legend's text.
    var cats: List[String] = ["Small", "Big"]
    var vals: List[Float64] = [10.0, 100.0]
    var plot = (
        Plot()
        .mark_funnel()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        "M60.000,20.000 L380.000,20.000" in s,
        "row 0's top edge spans the full plot width -- it's Big, not Small",
    )


def test_render_funnel_raises_on_negative_value() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, -1.0]
    with assert_raises():
        var _hoisted2 = funnel(cats, vals, width=200, height=150)
        _ = render(_hoisted2)


def test_render_funnel_raises_on_all_zero_values() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [0.0, 0.0]
    with assert_raises():
        var _hoisted3 = funnel(cats, vals, width=200, height=150)
        _ = render(_hoisted3)


def test_render_funnel_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted4 = funnel(cats, vals, width=200, height=150)
        _ = render(_hoisted4)


def test_render_funnel_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var cats = List[String]()
    var vals = List[Float64]()
    with assert_raises():
        var _hoisted5 = funnel(cats, vals, width=200, height=150)
        _ = render(_hoisted5)


# ---------------------------------------------------------------
# from tests/test_heatmap.mojo
# ---------------------------------------------------------------


def test_render_heatmap_matches_hand_derived_cells() raises:
    # 2 x-categories ("Mon", "Tue"), 2 y-categories ("AM", "PM"), values
    # 1.0/2.0/3.0/4.0. Canvas 400x300, no gridlines, no legend; short
    # labels keep the left margin at 60. padding=0.0 on both axes, so each
    # cell is half the span: width 160 (x:[60,220) for "Mon"), height 115
    # (y:[20,135) for "AM"), index 0 at the top/left.
    #
    # value=1.0 is the domain min -> exactly color_scale_low,
    # Color(60,110,200); value=4.0 -> exactly color_scale_high,
    # Color(220,90,40). The two in-between cells (t=1/3, t=2/3 through the
    # three-stop gradient) are Color(177,193,223) and Color(230,187,170);
    # ColorScale's interpolation is covered by its own tests.
    var x: List[String] = ["Mon", "Mon", "Tue", "Tue"]
    var y: List[String] = ["AM", "PM", "AM", "PM"]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = heatmap(x, y, v, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c,
        100,
        60,
        Color(60, 110, 200),
        "(Mon, AM) = 1.0, the color domain's min",
    )
    _assert_color(c, 100, 180, Color(177, 193, 223), "(Mon, PM) = 2.0")
    _assert_color(c, 300, 60, Color(230, 187, 170), "(Tue, AM) = 3.0")
    _assert_color(
        c,
        300,
        180,
        Color(220, 90, 40),
        "(Tue, PM) = 4.0, the color domain's max",
    )
    _assert_color(c, 10, 10, BG, "outside the plot area entirely -- background")


def test_render_heatmap_svg_matches_confirmed_rects() raises:
    var x: List[String] = ["Mon", "Mon", "Tue", "Tue"]
    var y: List[String] = ["AM", "PM", "AM", "PM"]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var plot = (
        Plot()
        .mark_heatmap()
        .encode_heatmap(x=x, y=y, value=v)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="60" y="20" width="160" height="115" fill="#3c6ec8"/>' in s,
        "(Mon, AM)",
    )
    assert_true(
        '<rect x="60" y="135" width="160" height="115" fill="#b1c1df"/>' in s,
        "(Mon, PM)",
    )
    assert_true(
        '<rect x="220" y="20" width="160" height="115" fill="#e6bbaa"/>' in s,
        "(Tue, AM)",
    )
    assert_true(
        '<rect x="220" y="135" width="160" height="115" fill="#dc5a28"/>' in s,
        "(Tue, PM)",
    )


def test_render_heatmap_missing_cell_leaves_background() raises:
    # A sparse grid with no (Tue, PM) row: a missing combination just isn't
    # drawn.
    var x: List[String] = ["Mon", "Mon", "Tue"]
    var y: List[String] = ["AM", "PM", "AM"]
    var v: List[Float64] = [1.0, 2.0, 3.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = heatmap(x, y, v, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(
        c, 300, 180, BG, "(Tue, PM) was never given -- background shows through"
    )


def test_render_heatmap_legend_shows_value_domain() raises:
    var x: List[String] = ["Mon", "Tue"]
    var y: List[String] = ["AM", "AM"]
    var v: List[Float64] = [1.0, 4.0]
    var plot = (
        Plot()
        .mark_heatmap()
        .encode_heatmap(x=x, y=y, value=v)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        ">4.0<" in s, "the color domain's max, at the top of the legend bar"
    )
    assert_true(
        ">1.0<" in s, "the color domain's min, at the bottom of the legend bar"
    )


def test_render_heatmap_raises_on_mismatched_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    var y: List[String] = ["a", "b", "c"]
    with assert_raises():
        var _hoisted3 = heatmap(x, y, one, width=200, height=150)
        _ = render(_hoisted3)


def test_render_heatmap_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var x = List[String]()
    var y = List[String]()
    var v = List[Float64]()
    with assert_raises():
        var _hoisted4 = heatmap(x, y, v, width=200, height=150)
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# from tests/test_punchcard.mojo
# ---------------------------------------------------------------


def test_render_punchcard_matches_hand_derived_bubbles() raises:
    # 2 x-categories, 2 y-categories, 3 rows: (Mon,9am)=50, (Mon,10am)=100,
    # (Tue,9am)=20, scale=10.0 -> radii 5, 10, 2. Canvas 400x300, no
    # gridlines, no legend: plot area x:[60,380], y:[20,250], centers
    # (140, 78)/(140, 193)/(300, 78).
    var x: List[String] = ["Mon", "Mon", "Tue"]
    var y: List[String] = ["9am", "10am", "9am"]
    var sizes: List[Float64] = [50.0, 100.0, 20.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = punchcard(x, y, sizes, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 78, t.mark_color, "(Mon, 9am), size 50 -> radius 5")
    _assert_color(
        c, 140, 193, t.mark_color, "(Mon, 10am), size 100 -> radius 10"
    )
    _assert_color(c, 300, 78, t.mark_color, "(Tue, 9am), size 20 -> radius 2")
    _assert_color(c, 300, 193, BG, "(Tue, 10am) was never given -- background")


def test_render_punchcard_svg_matches_confirmed_circles() raises:
    var x: List[String] = ["Mon", "Mon", "Tue"]
    var y: List[String] = ["9am", "10am", "9am"]
    var sizes: List[Float64] = [50.0, 100.0, 20.0]
    var plot = (
        Plot()
        .mark_punchcard(scale=10.0)
        .encode_punchcard(x=x, y=y, sizes=sizes)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<circle cx="140" cy="78" r="5" fill="#1e64b4"/>' in s, "(Mon, 9am)"
    )
    assert_true(
        '<circle cx="140" cy="193" r="10" fill="#1e64b4"/>' in s, "(Mon, 10am)"
    )
    assert_true(
        '<circle cx="300" cy="78" r="2" fill="#1e64b4"/>' in s, "(Tue, 9am)"
    )


def test_render_punchcard_repeated_cell_draws_two_independent_bubbles() raises:
    # Two rows share the same cell with different sizes: both bubbles draw
    # (the smaller nested inside the larger), not merged. One category on
    # each axis, so the shared center is (220, 135). A pixel just outside
    # the r=2 bubble but inside the r=10 one confirms the larger is there.
    var x: List[String] = ["Mon", "Mon"]
    var y: List[String] = ["9am", "9am"]
    var sizes: List[Float64] = [20.0, 100.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = punchcard(x, y, sizes, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(
        c,
        220,
        134,
        t.mark_color,
        "1px above center -- inside the smaller (r=2) and larger (r=10) both",
    )
    _assert_color(
        c,
        220,
        128,
        t.mark_color,
        "7px above center -- outside r=2, inside the larger bubble (r=10)",
    )


def test_render_punchcard_raises_on_negative_size() raises:
    var x: List[String] = ["a"]
    var y: List[String] = ["b"]
    var sizes: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted3 = punchcard(x, y, sizes, width=200, height=150)
        _ = render(_hoisted3)


def test_render_punchcard_raises_on_mismatched_length() raises:
    var x: List[String] = ["a", "b"]
    var y: List[String] = ["c"]
    var sizes: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted4 = punchcard(x, y, sizes, width=200, height=150)
        _ = render(_hoisted4)


def test_render_punchcard_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var x = List[String]()
    var y = List[String]()
    var sizes = List[Float64]()
    with assert_raises():
        var _hoisted5 = punchcard(x, y, sizes, width=100, height=80)
        _ = render(_hoisted5)


# ---------------------------------------------------------------
# from tests/test_corrplot.mojo
# ---------------------------------------------------------------


def test_render_corrplot_matches_hand_derived_bubbles() raises:
    # 2 variables, matrix [[1, -0.5], [-0.5, 1]]. Canvas 400x300, no
    # gridlines, no legend: cells 160 x 115 over plot area x:[60,380],
    # y:[20,250]; max bubble radius = min(160,115)/2*0.42 = 24.15 -> 24 at
    # |value|=1.0.
    #
    # Cell (A,A) [value 1.0]: center (140, 78), radius 24, color exactly
    # color_scale_high. Cell (A,B) [value -0.5]: center (300, 78), radius
    # round(24.15*0.5)=12, color at t=0.25 through the [-1,1] gradient,
    # (148,173,218), between color_scale_low and color_scale_mid.
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = corrplot(
        vars, m, labels=False, theme=t, width=400, height=300
    )
    var c = render(_hoisted1)

    _assert_color(
        c, 140, 78, t.color_scale_high, "(A, A) = 1.0, the color domain's max"
    )
    _assert_color(
        c,
        300,
        78,
        Color(148, 173, 218),
        "(A, B) = -0.5, t=0.25 through the gradient",
    )
    _assert_color(
        c,
        140,
        193,
        Color(148, 173, 218),
        "(B, A) = -0.5, symmetric with (A, B)",
    )
    _assert_color(
        c, 300, 193, t.color_scale_high, "(B, B) = 1.0, the color domain's max"
    )
    _assert_color(
        c,
        200,
        78,
        BG,
        "between the two bubbles on row A -- no bubble reaches that far",
    )


def test_render_corrplot_svg_matches_confirmed_circles() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var plot = (
        Plot()
        .mark_corrplot(labels=False)
        .encode_corrplot(variables=vars, matrix=m)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<circle cx="140" cy="78" r="24" fill="#dc5a28"/>' in s, "(A, A)"
    )
    assert_true(
        '<circle cx="300" cy="78" r="12" fill="#94adda"/>' in s, "(A, B)"
    )
    assert_true(
        '<circle cx="140" cy="193" r="12" fill="#94adda"/>' in s, "(B, A)"
    )
    assert_true(
        '<circle cx="300" cy="193" r="24" fill="#dc5a28"/>' in s, "(B, B)"
    )


def test_render_corrplot_lower_layout_without_diag_keeps_only_below_diagonal() raises:
    # layout="lower" (row >= col) with diag=False keeps exactly one cell
    # of a 2x2 matrix, (B, A). Rather than naming that cell's pixel and
    # the three empty ones, scan for the -0.5 cell colour: a bounding box
    # is the union of every matching pixel, so finding one roughly square
    # blob below and left of centre is the same claim -- (A, B) would
    # stretch the box right, and either diagonal cell would stretch it
    # into a different quadrant.
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = corrplot(
        vars,
        m,
        layout="lower",
        diag=False,
        labels=False,
        theme=t,
        width=400,
        height=300,
    )
    var c = render(plot)

    var cell = _bbox_of_color(c, Color(148, 173, 218))
    assert_true(cell.found, "the (B, A) cell is drawn")
    assert_true(
        cell.center_x() < c.width // 2,
        "the surviving cell is left of centre (column A), not (A, B)",
    )
    assert_true(
        cell.center_y() > c.height // 2,
        "the surviving cell is below centre (row B), not a diagonal cell",
    )
    # One cell, not two: a 2x2 grid's cell cannot span half the plot.
    assert_true(
        cell.width() < c.width // 2 and cell.height() < c.height // 2,
        "exactly one cell is filled, not a row or column of them ("
        + String(cell.width())
        + "x"
        + String(cell.height())
        + ")",
    )


def test_render_corrplot_raises_on_non_square_matrix() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, 0.5], [0.5]]
    with assert_raises():
        var _hoisted3 = corrplot(vars, m, width=200, height=150)
        _ = render(_hoisted3)


def test_render_corrplot_raises_on_wrong_row_count() raises:
    var vars: List[String] = ["A", "B", "C"]
    var m: List[List[Float64]] = [[1.0, 0.5, 0.1], [0.5, 1.0, 0.2]]
    with assert_raises():
        var _hoisted4 = corrplot(vars, m, width=200, height=150)
        _ = render(_hoisted4)


def test_render_corrplot_raises_on_out_of_range_value() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, 1.5], [1.5, 1.0]]
    with assert_raises():
        var _hoisted5 = corrplot(vars, m, width=200, height=150)
        _ = render(_hoisted5)


def test_render_corrplot_raises_on_no_variables() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var vars = List[String]()
    var m = List[List[Float64]]()
    with assert_raises():
        var _hoisted6 = corrplot(vars, m, width=100, height=80)
        _ = render(_hoisted6)


# ---------------------------------------------------------------
# from tests/test_calendar_heatmap.mojo
# ---------------------------------------------------------------


def test_render_calendar_heatmap_matches_hand_derived_cells() raises:
    # 2024-01-01 (a Monday), 2024-01-07 (the following Sunday, which starts
    # the next week's column), and 2024-12-31 (a Tuesday, in the last
    # column). Values [1.0, 2.0, 3.0]: min/mid/max of the color domain, so
    # the cells read directly off Theme's color_scale_low/mid/high (the mid
    # value lands exactly on the 0.5 stop with no interpolation).
    #
    # Canvas 900x300, no legend: plot area x:[60,880], y:[20,250] (the top
    # margin grows by a font size + label gap for the month labels). 2024
    # is a leap year -> 53 week columns. Jan 1 (row 1, col 0) ->
    # rect(60,67,15,31); Jan 7 (row 0, col 1) -> rect(75,36,15,31); Dec 31
    # (row 2, col 52) -> rect(865,97,15,31). Sampled well inside each
    # rect.
    var dates: List[String] = ["2024-01-01", "2024-01-07", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = calendar_heatmap(
        dates, values, theme=t, width=900, height=300
    )
    var c = render(_hoisted1)

    _assert_color(
        c,
        67,
        82,
        t.color_scale_low,
        "Jan 1 (Mon), value 1.0 -- the color domain's min",
    )
    _assert_color(
        c,
        82,
        51,
        t.color_scale_mid,
        "Jan 7 (Sun), value 2.0 -- the domain's exact midpoint",
    )
    _assert_color(
        c,
        872,
        112,
        t.color_scale_high,
        "Dec 31 (Tue), value 3.0 -- the color domain's max",
    )
    _assert_color(
        c, 10, 10, BG, "well outside the whole plot area -- background"
    )


def test_render_calendar_heatmap_svg_matches_confirmed_rects() raises:
    var dates: List[String] = ["2024-01-01", "2024-01-07", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var plot = (
        Plot()
        .mark_calendar_heatmap()
        .encode_calendar(dates=dates, values=values)
        .theme(Theme(show_legend=False))
        .size(900, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="60" y="67" width="15" height="31" fill="#3c6ec8"/>' in s,
        "Jan 1 (Mon), col 0",
    )
    assert_true(
        '<rect x="75" y="36" width="15" height="31" fill="#ebebeb"/>' in s,
        "Jan 7 (Sun), col 1",
    )
    assert_true(
        '<rect x="865" y="97" width="15" height="31" fill="#dc5a28"/>' in s,
        "Dec 31 (Tue), col 52",
    )


def test_render_calendar_heatmap_raises_on_mismatched_length() raises:
    var dates: List[String] = ["2024-01-01", "2024-01-02"]
    var values: List[Float64] = [1.0]
    with assert_raises():
        var _hoisted2 = calendar_heatmap(dates, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_calendar_heatmap_raises_on_mismatched_year() raises:
    var dates: List[String] = ["2024-01-01", "2025-01-01"]
    var values: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted3 = calendar_heatmap(dates, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_calendar_heatmap_raises_on_no_data() raises:
    # #206: see test_render_marimekko_raises_on_no_data above.
    var dates = List[String]()
    var values = List[Float64]()
    with assert_raises():
        var _hoisted4 = calendar_heatmap(dates, values, width=100, height=80)
        _ = render(_hoisted4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
