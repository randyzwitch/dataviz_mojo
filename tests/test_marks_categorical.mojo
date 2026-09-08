"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.GROUPED_BAR, Mark.STACKED_BAR
(including independent positive/negative stacking and percent=True),
Mark.MARIMEKKO, Mark.POPULATION_PYRAMID, Mark.SPAN_CHART, Mark.GANTT,
Mark.FUNNEL, Mark.HEATMAP, Mark.PUNCHCARD, Mark.CORRPLOT,
Mark.CALENDAR_HEATMAP, and the two continuous-axis grid marks
Mark.IMSHOW and Mark.PCOLORMESH, each raster + SVG plus its encode_*()
validation.
Mark.CALENDAR_HEATMAP and Mark.EVENTPLOT, each raster + SVG plus its
encode_*() validation.
"""

from _test_helpers import (
    BG,
    _assert_color,
    _assert_same_canvas,
    _attr_values,
    _bbox_of_color,
    _column_extent,
    _count_color,
    _runs_in_row,
)
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.path import PathOp
from canvas.vector.svg import SvgCanvas
from dataviz import (
    calendar_heatmap,
    corrplot,
    eventplot,
    funnel,
    gantt,
    grouped_bar,
    heatmap,
    imshow,
    marimekko,
    pcolormesh,
    population_pyramid,
    punchcard,
    span_chart,
    stacked_bar,
)
from dataviz.color_scale import ColorScale, default_categorical_palette
from dataviz.image import _edge_pixels, _fill_cells
from dataviz.colormaps import viridis
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
from dataviz.scale import LinearScale
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
        '<rect x="77" y="162" width="128" height="78" fill="#1e64b4"/>' in s,
        "bar A's rect",
    )
    assert_true(
        '<rect x="237" y="31" width="128" height="105" fill="#1e64b4"/>' in s,
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
        '<rect x="221" y="147" width="145" height="92" fill="#1e64b4"/>' in s,
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


def test_render_heatmap_honors_a_perceptual_color_ramp() raises:
    # The same four cells and the same geometry as the hand-derived test
    # above, with Theme.color_ramp set to viridis (#332). This is the
    # check that a many-stop ramp reaches the drawing rather than just
    # ColorScale: the three scalar stops are left at their defaults and
    # must not appear anywhere.
    #
    # Values 1.0/2.0/3.0/4.0 land at t = 0, 1/3, 2/3, 1 through the ramp.
    # The two ends are matplotlib's viridis endpoints exactly.
    var x: List[String] = ["Mon", "Mon", "Tue", "Tue"]
    var y: List[String] = ["AM", "PM", "AM", "PM"]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var t = Theme(show_gridlines=False, show_legend=False, color_ramp=viridis())
    var _hoisted_viridis = heatmap(x, y, v, theme=t, width=400, height=300)
    var c = render(_hoisted_viridis)

    _assert_color(
        c, 100, 60, Color(68, 1, 84), "(Mon, AM) = 1.0, viridis' dark end"
    )
    _assert_color(c, 100, 180, Color(49, 104, 142), "(Mon, PM) = 2.0")
    _assert_color(c, 300, 60, Color(53, 183, 121), "(Tue, AM) = 3.0")
    _assert_color(
        c, 300, 180, Color(253, 231, 37), "(Tue, PM) = 4.0, viridis' yellow end"
    )


def test_render_heatmap_cells_leave_no_gap_at_a_snap_tie() raises:
    # #379: adjacent cells used to disagree about where their shared
    # boundary was, leaving a one-pixel column of pure background down
    # the middle of the grid.
    #
    # Cell i's right edge was computed as (range_min + step*i) + step
    # while cell i+1's left edge was range_min + step*(i+1). Equal in
    # exact arithmetic, but floating-point addition is not associative:
    # at 420x300 with 24 categories they came out 186.99999999999997 and
    # 187.0, which snapped to 186.5 and 187.5, so column 187 was covered
    # by neither cell.
    #
    # 420 x 24 is one of exactly three geometries that failed in a sweep
    # of 170 (widths 380-460 by 5, category counts 7 to 37); the other
    # two were 405 and 435, also at 24 categories. That rarity is why
    # this asserts a property rather than a pixel: any interior
    # background column is a defect, whichever boundary it lands on.
    var xs = List[String]()
    var ys = List[String]()
    var vs = List[Float64]()
    for i in range(24):
        for j in range(9):
            xs.append(String(i))
            ys.append(String(j))
            vs.append(Float64(i) + Float64(j) * 0.01)

    var _hoisted_gap = heatmap(
        xs,
        ys,
        vs,
        theme=Theme(show_legend=False, show_gridlines=False),
        width=420,
        height=300,
    )
    var c = render(_hoisted_gap)

    # A row through the middle of the grid meets background exactly
    # twice: the left margin and the right margin. A third run is a hole
    # in the grid.
    assert_equal(
        _runs_in_row(c, 150, BG),
        2,
        (
            "row 150 should meet background only in the two margins; a third"
            " run is a gap between cells"
        ),
    )


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


def test_render_heatmap_cells_tile_without_a_seam() raises:
    # 11 columns across a 320px plot area is 29.09 per band. Drawing each
    # cell as a rounded corner plus one rounded width shared by the grid
    # gave every cell a width of 29, which falls behind the step: by the
    # sixth column one cell's right edge stopped a pixel before the next
    # one's left edge began, and the background showed through as a
    # hairline seam down the middle of the chart.
    #
    # Asserted as "no background anywhere between the first and last
    # cell pixel" rather than by pinning widths, so the test states the
    # property that matters and survives the cells being 29 or 30 wide.
    var x = List[String]()
    var y = List[String]()
    var v = List[Float64]()
    for col in range(11):
        x.append("c" + String(col))
        y.append("r")
        v.append(Float64(col))
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted_seam = heatmap(x, y, v, theme=t, width=400, height=300)
    var c = render(_hoisted_seam)

    var row = 150
    var first = -1
    var last = -1
    for px in range(c.width):
        var p = c.get_pixel(px, row)
        if not (p.r == BG.r and p.g == BG.g and p.b == BG.b):
            if first == -1:
                first = px
            last = px
    assert_true(first != -1, "the grid drew something on this row")
    assert_equal(last - first + 1, 320, "the grid spans the whole plot area")

    var seams = 0
    for px in range(first, last + 1):
        var p = c.get_pixel(px, row)
        if p.r == BG.r and p.g == BG.g and p.b == BG.b:
            seams += 1
    assert_equal(seams, 0, "no background pixel between two adjacent cells")


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
    # The radii are unchanged -- 50/100/20 at scale 10 are whole pixels
    # either way. What moved is the center: a band's center falls on a
    # half pixel here, and a disk is antialiased on every side wherever
    # it sits, so there is nothing to gain by rounding it to 78.
    assert_true(
        '<circle cx="140.000" cy="77.500" r="5.000" fill="#1e64b4"/>' in s,
        "(Mon, 9am)",
    )
    assert_true(
        '<circle cx="140.000" cy="192.500" r="10.000" fill="#1e64b4"/>' in s,
        "(Mon, 10am)",
    )
    assert_true(
        '<circle cx="300.000" cy="77.500" r="2.000" fill="#1e64b4"/>' in s,
        "(Tue, 9am)",
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
    # r = max_radius * abs(value), unrounded: 24.150 for 1.0 and 12.075
    # for -0.5, exactly half. Rounding these to 24 and 12 was harmless
    # at two variables and destructive at fifteen, where max_radius is
    # around 5 and a whole-pixel radius leaves about six distinct sizes
    # to say everything between 0 and 1 with.
    assert_true(
        '<circle cx="140.000" cy="77.500" r="24.150" fill="#dc5a28"/>' in s,
        "(A, A)",
    )
    assert_true(
        '<circle cx="300.000" cy="77.500" r="12.075" fill="#94adda"/>' in s,
        "(A, B)",
    )
    assert_true(
        '<circle cx="140.000" cy="192.500" r="12.075" fill="#94adda"/>' in s,
        "(B, A)",
    )
    assert_true(
        '<circle cx="300.000" cy="192.500" r="24.150" fill="#dc5a28"/>' in s,
        "(B, B)",
    )


def test_render_corrplot_lower_layout_without_diag_keeps_only_below_diagonal() raises:
    # layout="lower" (row >= col) with diag=False keeps exactly one cell
    # of a 2x2 matrix, (B, A). Rather than naming that cell's pixel and
    # the three empty ones, scan for the -0.5 cell color: a bounding box
    # is the union of every matching pixel, so finding one roughly square
    # blob below and left of center is the same claim -- (A, B) would
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
        "the surviving cell is left of center (column A), not (A, B)",
    )
    assert_true(
        cell.center_y() > c.height // 2,
        "the surviving cell is below center (row B), not a diagonal cell",
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
    # Cells are not all one size: 53 week columns and 7 day rows do not
    # divide the plot area evenly, so each cell runs between its own two
    # snapped edges and some come out a pixel larger than their
    # neighbors. A single rounded size for the whole grid looked tidier
    # in a test and could not tile -- it left a seam or an overlap
    # wherever the fraction accumulated past half a pixel.
    assert_true(
        '<rect x="60" y="67" width="15" height="30" fill="#3c6ec8"/>' in s,
        "Jan 1 (Mon), col 0",
    )
    assert_true(
        '<rect x="75" y="36" width="16" height="31" fill="#ebebeb"/>' in s,
        "Jan 7 (Sun), col 1",
    )
    assert_true(
        '<rect x="865" y="97" width="15" height="31" fill="#dc5a28"/>' in s,
        "Dec 31 (Tue), col 52",
    )


def _calendar_svg_at(width: Int) raises -> String:
    """A full-year calendar heatmap rendered to SVG at `width`, with no
    title or legend so the only text is the axis labels."""
    var dates: List[String] = ["2024-01-01", "2024-06-15", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var plot = (
        Plot()
        .mark_calendar_heatmap()
        .encode_calendar(dates=dates, values=values)
        .theme(Theme(show_legend=False))
        .size(width, 200)
    )
    return render_svg(plot).to_string()


def test_calendar_month_labels_are_all_drawn_when_they_fit() raises:
    # 900px is what the docs example uses, and there every month anchor
    # is far enough from the next for the widest label ("May", 23.3px at
    # the default 12px font). Nothing about #361 should change it.
    var s = _calendar_svg_at(900)
    var months: List[String] = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
    ]
    for m in months:
        assert_true(">" + m + "<" in s, m + " should still be labeled at 900px")


def test_calendar_month_labels_thin_out_rather_than_collide() raises:
    # #361: below about 530px the twelve month labels ran together into
    # an unreadable "JanFebMarApr...". They are the only thing saying
    # which column is which month, so once they merge the chart cannot be
    # read along that axis.
    #
    # At 420px the month anchors are ~15px apart and "May" alone is
    # 23.3px, so every second month is dropped: Jan Mar May Jul Sep Nov.
    var s = _calendar_svg_at(420)
    var shown: List[String] = ["Jan", "Mar", "May", "Jul", "Sep", "Nov"]
    var dropped: List[String] = ["Feb", "Apr", "Jun", "Aug", "Oct", "Dec"]
    for m in shown:
        assert_true(">" + m + "<" in s, m + " should be labeled at 420px")
    for m in dropped:
        assert_true(
            ">" + m + "<" not in s,
            m + " should be dropped at 420px -- it would overlap its neighbor",
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


# ---------------------------------------------------------------
# Mark.IMSHOW / Mark.PCOLORMESH (#341)
#
# Every test here colors through a two-stop ramp of pure blue and pure
# red over a domain of exactly [0, 1], so a cell holding 0 is
# Color(0, 0, 255) and one holding 1 is Color(255, 0, 0) -- exact
# literals, never a value read back out of the function under test.
# Anything else in the drawn region is either a blend (an anti-aliased
# shared edge) or the background showing through (a gap), which is what
# most of these are looking for.
# ---------------------------------------------------------------

comptime _IMG_LO = Color(0, 0, 255)
comptime _IMG_HI = Color(255, 0, 0)
comptime _IMG_BG = Color(0, 255, 0)


def _image_theme() -> Theme:
    """A theme whose background can't be confused with a cell: pure
    green against a blue/red ramp, no gridlines, no legend column."""
    var stops: List[Color] = [_IMG_LO, _IMG_HI]
    return Theme(
        background=_IMG_BG,
        color_ramp=stops,
        show_gridlines=False,
        show_legend=False,
    )


def _checkerboard(rows: Int, cols: Int) -> List[List[Float64]]:
    var z = List[List[Float64]]()
    for r in range(rows):
        var row = List[Float64]()
        for c in range(cols):
            row.append(Float64((r + c) % 2))
        z.append(row^)
    return z^


def test_imshow_places_every_cell_by_row_major_index() raises:
    # A 2x3 array, so a transpose changes the shape and cannot pass, and
    # a pattern that is asymmetric under a vertical flip, a horizontal
    # flip and a transpose alike:
    #
    #   z = [[0, 1, 1],      blue  red  red
    #        [1, 1, 0]]      red   red  blue
    #
    # Flipped vertically that is blue at top-right and bottom-left;
    # flipped horizontally, the same; transposed it is a 3x2 image with
    # different cell sizes. So asserting the *corner* colors pins
    # row-major order, column order, and row 0 being at the top all at
    # once. Asserting that blue appears at all, or counting blue pixels,
    # would pass under every one of those.
    var z: List[List[Float64]] = [[0.0, 1.0, 1.0], [1.0, 1.0, 0.0]]
    var c = render(imshow(z, theme=_image_theme(), width=640, height=420))

    # The drawn region is the plot rect: measured at (60, 20)-(619, 369)
    # for a 640x420 default-margin chart with no legend, which
    # test_imshow_fills_the_plot_rect_like_a_heatmap_does pins
    # separately. Sample well inside each cell, never near an edge.
    var x_left = 60 + 560 // 6
    var x_mid = 60 + 560 // 2
    var x_right = 60 + 5 * 560 // 6
    var y_top = 20 + 350 // 4
    var y_bottom = 20 + 3 * 350 // 4

    _assert_color(c, x_left, y_top, _IMG_LO, "z[0][0] = 0 -> top-left blue")
    _assert_color(c, x_mid, y_top, _IMG_HI, "z[0][1] = 1 -> top-middle red")
    _assert_color(c, x_right, y_top, _IMG_HI, "z[0][2] = 1 -> top-right red")
    _assert_color(
        c, x_left, y_bottom, _IMG_HI, "z[1][0] = 1 -> bottom-left red"
    )
    _assert_color(
        c, x_mid, y_bottom, _IMG_HI, "z[1][1] = 1 -> bottom-middle red"
    )
    _assert_color(
        c, x_right, y_bottom, _IMG_LO, "z[1][2] = 0 -> bottom-right blue"
    )


def test_imshow_y_axis_labels_count_downward() raises:
    # The pixels being upside down and the axis being upside down are
    # two different bugs, and a mark that flipped only its own drawing
    # would leave the ticks reading 0 at the bottom. This is the axis
    # half: the tick labeled "0" must sit *above* the one labeled "4",
    # which is the reverse of every other continuous mark here.
    var z = List[List[Float64]]()
    for r in range(5):
        var row = List[Float64]()
        for c in range(5):
            row.append(Float64(r))
        z.append(row^)
    var svg = render_svg(imshow(z, width=640, height=420)).to_string()
    var texts = _attr_values(svg, "text", "y")
    var labels = List[String]()
    var rest = svg
    while True:
        var at = rest.find("<text ")
        if at < 0:
            break
        var close = rest.find(">", at)
        var end = rest.find("</text>", close)
        if close < 0 or end < 0:
            break
        labels.append(String(rest[byte = close + 1 : end]))
        var tail = String(rest[byte = end + 7 :])
        rest = tail^

    var y_of_zero = -1.0
    var y_of_four = -1.0
    for i in range(len(labels)):
        if labels[i] == "0" and i < len(texts):
            y_of_zero = Float64(texts[i])
        if labels[i] == "4" and i < len(texts):
            y_of_four = Float64(texts[i])
    assert_true(y_of_zero >= 0.0, 'no y-axis tick labeled "0"')
    assert_true(y_of_four >= 0.0, 'no y-axis tick labeled "4"')
    assert_true(
        y_of_zero < y_of_four,
        (
            'row 0 must be at the top, so the "0" tick sits above the "4" tick'
            " -- got 0 at y="
            + String(y_of_zero)
            + " and 4 at y="
            + String(y_of_four)
        ),
    )


def test_pcolormesh_row_0_is_at_the_bottom() raises:
    # The deliberate difference from imshow: pcolormesh's rows are
    # positions on a real axis, so row 0 is at the bottom. Same data and
    # same theme as the imshow orientation test, so the only thing that
    # can flip the answer is the mark.
    var z: List[List[Float64]] = [[0.0, 0.0], [1.0, 1.0]]
    var edges_x: List[Float64] = [0.0, 1.0, 2.0]
    var edges_y: List[Float64] = [0.0, 1.0, 2.0]
    var c = render(
        pcolormesh(
            edges_x, edges_y, z, theme=_image_theme(), width=640, height=420
        )
    )
    _assert_color(
        c, 60 + 280, 20 + 87, _IMG_HI, "pcolormesh row 1 (value 1) is on top"
    )
    _assert_color(
        c,
        60 + 280,
        20 + 262,
        _IMG_LO,
        "pcolormesh row 0 (value 0) is at the bottom",
    )

    # And imshow, given the same array, is the other way up. Asserting
    # the difference directly is what keeps the two from silently
    # converging on one orientation later.
    var ci = render(imshow(z, theme=_image_theme(), width=640, height=420))
    _assert_color(
        ci, 60 + 280, 20 + 87, _IMG_LO, "imshow row 0 (value 0) is on top"
    )


def test_pcolormesh_cell_widths_follow_the_edges() raises:
    # x_edges 0, 1, 3, 7: widths 1, 2 and 4, so the three cells must
    # come out in a 1:2:4 ratio across the plot rect. Mark.IMSHOW would
    # give three equal columns, which is exactly what this has to rule
    # out -- and a test that only checked "three colored runs exist"
    # would not.
    var z: List[List[Float64]] = [[0.0, 1.0, 0.0]]
    var edges_x: List[Float64] = [0.0, 1.0, 3.0, 7.0]
    var edges_y: List[Float64] = [0.0, 1.0]
    var c = render(
        pcolormesh(
            edges_x, edges_y, z, theme=_image_theme(), width=640, height=420
        )
    )
    var y = 20 + 175
    var widths = List[Int]()
    var run = 0
    var current = Color(0, 0, 0)
    var open_run = False
    for x in range(60, 620):
        var p = c.get_pixel(x, y)
        var is_cell = (
            p.r == _IMG_LO.r and p.g == _IMG_LO.g and p.b == _IMG_LO.b
        ) or (p.r == _IMG_HI.r and p.g == _IMG_HI.g and p.b == _IMG_HI.b)
        if not is_cell:
            continue
        if open_run and p.r == current.r and p.b == current.b:
            run += 1
            continue
        if open_run:
            widths.append(run)
        open_run = True
        current = Color(p.r, p.g, p.b)
        run = 1
    if open_run:
        widths.append(run)

    assert_equal(len(widths), 3, "three cells, three runs of color")
    # 560 px over a span of 7 units: 80, 160, 320, give or take the
    # pixel each boundary snaps to.
    assert_true(
        widths[0] >= 79 and widths[0] <= 81,
        "cell [0, 1] is one unit wide -> ~80px, got " + String(widths[0]),
    )
    assert_true(
        widths[1] >= 159 and widths[1] <= 161,
        "cell [1, 3] is two units wide -> ~160px, got " + String(widths[1]),
    )
    assert_true(
        widths[2] >= 319 and widths[2] <= 321,
        "cell [3, 7] is four units wide -> ~320px, got " + String(widths[2]),
    )
    assert_equal(
        widths[0] + widths[1] + widths[2],
        560,
        (
            "the three cells must tile the plot rect exactly, with no pixel"
            " left over between them"
        ),
    )


def test_imshow_boundary_between_two_cells_is_sharp() raises:
    # #341's own test plan. A blend at the boundary is what an
    # anti-aliased path fill leaves and what a snapped fill_rect does
    # not, so scanning a whole row for "exactly blue or exactly red"
    # discriminates between the two implementations. Asserting a pixel
    # in the middle of either cell would pass under both.
    #
    # Three cells, not the two the plan suggests: 560 px split in two
    # puts the single boundary at x = 340.0, a whole pixel edge, where
    # an unsnapped fill lands sharp by luck and the test proves nothing
    # (measured -- it passed against an unsnapped `_edge_pixels`). Split
    # in three the boundaries fall at 246.67 and 433.33, mid-pixel both,
    # which is the case snapping exists for.
    var z: List[List[Float64]] = [[0.0, 1.0, 0.0]]
    var c = render(imshow(z, theme=_image_theme(), width=640, height=420))
    var y = 20 + 175
    var blended = 0
    var first_bad = -1
    for x in range(60, 620):
        var p = c.get_pixel(x, y)
        var lo = p.r == _IMG_LO.r and p.g == _IMG_LO.g and p.b == _IMG_LO.b
        var hi = p.r == _IMG_HI.r and p.g == _IMG_HI.g and p.b == _IMG_HI.b
        if not (lo or hi):
            blended += 1
            if first_bad < 0:
                first_bad = x
    assert_equal(
        blended,
        0,
        (
            "every pixel across the two cells must be exactly one of the two"
            " cell colors -- found "
            + String(blended)
            + " blended pixels, first at x="
            + String(first_bad)
        ),
    )


def test_imshow_dense_grid_has_no_background_gap_between_cells() raises:
    # The #315/#318/#327/#359/#360/#379 regression guard, and the reason
    # cell boundaries come from one shared array rather than from
    # `start + width` on one side and `start` on the other.
    #
    # A checkerboard is the worst case on purpose: every cell differs
    # from all four of its neighbors, so no run merges and every
    # boundary in the grid is drawn. 37x53 is deliberately not a
    # divisor of the 560x350 plot rect, which is the geometry that
    # produced the hairline in #379 -- a band 560/53 = 10.566 px wide
    # cannot be tiled by any single rounded width.
    var t = _image_theme()
    var c = render(
        imshow(_checkerboard(37, 53), theme=t, width=640, height=420)
    )
    var gaps = 0
    var blends = 0
    var first_bad = -1
    for y in range(20, 370):
        for x in range(60, 620):
            var p = c.get_pixel(x, y)
            if p.r == _IMG_LO.r and p.g == _IMG_LO.g and p.b == _IMG_LO.b:
                continue
            if p.r == _IMG_HI.r and p.g == _IMG_HI.g and p.b == _IMG_HI.b:
                continue
            if p.r == _IMG_BG.r and p.g == _IMG_BG.g and p.b == _IMG_BG.b:
                gaps += 1
            else:
                blends += 1
            if first_bad < 0:
                first_bad = y * 1000 + x
    assert_equal(
        gaps,
        0,
        (
            "the background must not show through anywhere inside the grid --"
            " found "
            + String(gaps)
            + " background pixels (first at y*1000+x = "
            + String(first_bad)
            + ")"
        ),
    )
    assert_equal(
        blends,
        0,
        (
            "no cell boundary may be anti-aliased -- found "
            + String(blends)
            + " blended pixels (first at y*1000+x = "
            + String(first_bad)
            + ")"
        ),
    )


def test_imshow_fills_the_plot_rect_like_a_heatmap_does() raises:
    # Measured off a real render, and cross-checked against Mark.HEATMAP
    # at the same size: both put their first cell pixel at (60, 20) and
    # their last at (619, 369). Asserting the two agree is what keeps
    # the continuous grid mark and the categorical one from drifting a
    # pixel apart, which is not something either mark's own numbers
    # would catch.
    var z = _checkerboard(5, 7)
    var t = _image_theme()
    var c = render(imshow(z, theme=t, width=640, height=420))
    var box = _bbox_of_color(c, _IMG_HI)
    assert_true(box.found, "the grid drew nothing")
    assert_equal(box.x0, 60, "grid starts at the plot rect's left edge")
    assert_equal(box.y0, 20, "grid starts at the plot rect's top edge")
    assert_equal(box.x1, 619, "grid ends at the plot rect's right edge")
    assert_equal(box.y1, 369, "grid ends at the plot rect's bottom edge")

    var xs = List[String]()
    var ys = List[String]()
    var vs = List[Float64]()
    for r in range(5):
        for c2 in range(7):
            xs.append(String(c2))
            ys.append(String(r))
            vs.append(Float64((r + c2) % 2))
    var hc = render(heatmap(xs, ys, vs, theme=t, width=640, height=420))
    var hbox = _bbox_of_color(hc, _IMG_HI)
    assert_true(hbox.found, "the heatmap drew nothing")
    assert_equal(box.x0, hbox.x0, "imshow and heatmap share a left edge")
    assert_equal(box.y0, hbox.y0, "imshow and heatmap share a top edge")
    assert_equal(box.x1, hbox.x1, "imshow and heatmap share a right edge")
    assert_equal(box.y1, hbox.y1, "imshow and heatmap share a bottom edge")


def test_imshow_takes_its_colors_from_the_theme_ramp() raises:
    # Mark.IMSHOW goes through ColorScale.from_theme like every other
    # color-encoded mark, so a perceptual colormap reaches it with no
    # code of its own -- which matters more here than anywhere else,
    # since a scalar field shown through three stops gets contrast the
    # data does not have. viridis()'s own first and last entries are the
    # expected colors; they come from dataviz.colormaps, not from the
    # render.
    var ramp = viridis()
    var z: List[List[Float64]] = [[0.0, 1.0]]
    var t = Theme(color_ramp=ramp, show_gridlines=False, show_legend=False)
    var c = render(imshow(z, theme=t, width=640, height=420))
    var y = 20 + 175
    _assert_color(
        c, 60 + 140, y, ramp[0], "the array's minimum takes viridis' first stop"
    )
    _assert_color(
        c,
        60 + 420,
        y,
        ramp[len(ramp) - 1],
        "the array's maximum takes viridis' last stop",
    )


def test_imshow_dtype_overload_matches_the_float64_path() raises:
    var wide: List[List[Float64]] = [[0.0, 1.0, 2.0], [3.0, 4.0, 5.0]]
    var narrow = List[List[Scalar[DType.int32]]]()
    for r in range(2):
        var row = List[Scalar[DType.int32]]()
        for c in range(3):
            row.append(Scalar[DType.int32](r * 3 + c))
        narrow.append(row^)
    var t = _image_theme()
    _assert_same_canvas(
        render(imshow(narrow, theme=t, width=320, height=240)),
        render(imshow(wide, theme=t, width=320, height=240)),
        "imshow[DType] vs imshow",
    )


def test_imshow_and_pcolormesh_validation_raises_name_what_is_wrong() raises:
    var t = _image_theme()

    var ragged: List[List[Float64]] = [[0.0, 1.0], [2.0]]
    with assert_raises(contains="z must be rectangular"):
        _ = render(imshow(ragged, theme=t, width=200, height=150))

    var empty = List[List[Float64]]()
    with assert_raises(contains="Plot.encode_imshow()"):
        _ = render(imshow(empty, theme=t, width=200, height=150))

    var nan_grid: List[List[Float64]] = [[0.0, Float64("nan")]]
    with assert_raises(contains="must be finite"):
        _ = render(imshow(nan_grid, theme=t, width=200, height=150))

    var z: List[List[Float64]] = [[0.0, 1.0], [1.0, 0.0]]
    var short_edges: List[Float64] = [0.0, 1.0]
    var ok_edges: List[Float64] = [0.0, 1.0, 2.0]
    with assert_raises(contains="one more entry than z has columns"):
        _ = render(
            pcolormesh(short_edges, ok_edges, z, theme=t, width=200, height=150)
        )

    var flat_edges: List[Float64] = [0.0, 1.0, 1.0]
    with assert_raises(contains="strictly increasing"):
        _ = render(
            pcolormesh(ok_edges, flat_edges, z, theme=t, width=200, height=150)
        )

    # The two raises Mark.name() is what makes readable: a mark paired
    # with the other one's encoding. Neither can draw what the caller
    # asked for, and the message has to say which mark is asking.
    with assert_raises(contains="Mark.PCOLORMESH"):
        _ = render(
            Plot().mark_pcolormesh().encode_imshow(z).theme(t).size(200, 150)
        )
    with assert_raises(contains="Mark.IMSHOW"):
        _ = render(
            Plot()
            .mark_imshow()
            .encode_pcolormesh(ok_edges, ok_edges, z)
            .theme(t)
            .size(200, 150)
        )


def _fill_count(z: List[List[Float64]], lo: Float64, hi: Float64) raises -> Int:
    """How many rects `_fill_cells` actually draws for `z` in the stock
    640x420 plot rect, laid out exactly as `_render_image` lays it out.
    """
    var rows = len(z)
    var cols = len(z[0])
    var xv = List[Float64]()
    for c in range(cols + 1):
        xv.append(Float64(c) - 0.5)
    var yv = List[Float64]()
    for r in range(rows + 1):
        yv.append(Float64(r) - 0.5)
    var xp = _edge_pixels(
        LinearScale(xv[0], xv[cols], 60.0, 620.0),
        xv,
    )
    var yp = _edge_pixels(
        LinearScale(yv[0], yv[rows], 20.0, 370.0),
        yv,
    )
    var canvas = Canvas(640, 420, Color(255, 255, 255))
    return _fill_cells(
        canvas, z, xp, yp, ColorScale.from_theme(Theme(), lo, hi)
    )


def test_imshow_costs_the_output_rect_not_the_array() raises:
    """#341's "do not draw one rect per cell": 512x512 is 262,144 cells
    and drawing one rect each would be absurd for an image.

    Two independent mechanisms, one assertion each, because they fail
    independently:

    - Cells finer than a pixel collapse, so the count is bounded by the
      plot rect. A checkerboard is the case where *nothing* else can
      reduce it -- every cell differs from all four neighbors -- so its
      count is exactly the bound, and it must not exceed one rect per
      pixel row per column.
    - Runs of same-colored cells merge. A binary mask has the same cell
      count and the same visible-cell count as the checkerboard, so the
      only thing that can separate the two numbers is the merge.

    Asserting a total render time, or that a large array renders at all,
    would pass with one rect per cell.
    """
    var checker = _checkerboard(512, 512)
    var checker_rects = _fill_count(checker, 0.0, 1.0)

    # 350 pixel rows in the plot rect, 512 columns: no more than one
    # rect per (row, column) pair that is actually visible. One rect per
    # cell would be 262,144.
    assert_true(
        checker_rects <= 350 * 512,
        (
            "a 512x512 checkerboard must cost at most one rect per visible"
            " cell (350 * 512 = 179200), not one per array cell (262144) --"
            " got "
            + String(checker_rects)
        ),
    )
    assert_true(
        checker_rects > 350 * 512 // 2,
        (
            "the checkerboard is the case nothing can merge, so a much"
            " smaller count means cells are being dropped rather than"
            " collapsed -- got "
            + String(checker_rects)
        ),
    )

    var mask = List[List[Float64]]()
    for r in range(512):
        var row = List[Float64]()
        for c in range(512):
            var dx = Float64(c) - 256.0
            var dy = Float64(r) - 256.0
            row.append(1.0 if dx * dx + dy * dy < 29000.0 else 0.0)
        mask.append(row^)
    var mask_rects = _fill_count(mask, 0.0, 1.0)
    assert_true(
        mask_rects * 10 < checker_rects,
        (
            "a two-valued mask has the same visible-cell count as the"
            " checkerboard, so same-colored runs must merge it down by an"
            " order of magnitude -- got "
            + String(mask_rects)
            + " against the checkerboard's "
            + String(checker_rects)
        ),
    )


# Mark.EVENTPLOT (#339)
# ---------------------------------------------------------------


def _eventplot_labels() -> List[String]:
    return ["a", "b", "c"]


def _eventplot_positions() -> List[List[Float64]]:
    """Three rows, the middle one deliberately empty: `a` fires at 1, 2
    and 5, `c` at 3 and 4, `b` never.
    """
    var out = List[List[Float64]]()
    var top: List[Float64] = [1.0, 2.0, 5.0]
    var middle = List[Float64]()
    var bottom: List[Float64] = [3.0, 4.0]
    out.append(top^)
    out.append(middle^)
    out.append(bottom^)
    return out^


def test_render_eventplot_puts_each_event_in_its_own_column() raises:
    """Three events at known x land in three known columns, and the
    row's other columns are background.

    The arithmetic, all of it by hand: at 400x300 the plot rect is
    `(60, 20)-(380, 250)` (measured from the render). The x-domain is
    `_data_extent` over the *pooled* positions `[1, 5]`, so `[0.8, 5.2]`
    across 320px, giving `x = 1` at 74.5, `x = 2` at 147.3, `x = 3` at
    220.0, `x = 4` at 292.7 and `x = 5` at 365.5. Snapped to pixel
    centers those are columns 75, 147, 220, 293 and 365 -- and no
    others, which is what the total-column count pins.
    """
    var c = render(
        eventplot(
            _eventplot_labels(), _eventplot_positions(), width=400, height=300
        )
    )
    var mark = Theme().mark_color

    var inked = List[Int]()
    for x in range(c.width):
        if _column_extent(c, x, mark).found:
            inked.append(x)
    assert_equal(len(inked), 5, "one column per event, and no other")
    assert_equal(inked[0], 75, "x = 1")
    assert_equal(inked[1], 147, "x = 2")
    assert_equal(inked[2], 220, "x = 3")
    assert_equal(inked[3], 293, "x = 4")
    assert_equal(inked[4], 365, "x = 5")


def test_render_eventplot_rows_are_where_the_labels_are() raises:
    """Which row an event lands in, and how tall its tick is -- the
    two-row spacing the issue asks to pin, done over three.

    `_draw_horizontal_categorical_axis_frame` bands the rect's 230 rows
    into three slots of 76.67 with `OrdinalScale`'s default 0.2 padding,
    so a band is 61.33 tall. Row 0 runs 27.67..89.0 and row 2 runs
    181.0..242.33; a butt-capped stroke covers the partial end rows only
    partly, so the exactly-mark-colored rows are 29..88 and 182..241.

    Row 1 is empty and must draw nothing at all -- see
    `test_render_eventplot_keeps_an_empty_row`, which is what says the
    gap between 88 and 182 is an empty row rather than a missing one.
    """
    var c = render(
        eventplot(
            _eventplot_labels(), _eventplot_positions(), width=400, height=300
        )
    )
    var mark = Theme().mark_color

    var first_row = _column_extent(c, 75, mark)
    assert_equal(first_row.y0, 29, "row 0's tick starts at the band top")
    assert_equal(first_row.y1, 88, "and ends at the band bottom")

    var third_row = _column_extent(c, 220, mark)
    assert_equal(third_row.y0, 182, "row 2 is two full slots lower")
    assert_equal(third_row.y1, 241)

    # 76.67px per slot, so row 2's top is 153 below row 0's. Asserting
    # the difference as well as the two positions is what would catch a
    # frame that put the rows in the right places for the wrong reason.
    assert_equal(
        third_row.y0 - first_row.y0, 153, "rows are one slot-height apart"
    )


def test_render_eventplot_ticks_snap_to_one_pixel_column() raises:
    """#313: a tick's fixed coordinate snaps to a pixel center, so it
    covers exactly one column instead of splitting its ink across two.
    The whole chart is thin vertical lines and a blurred one reads as a
    fainter event.

    `x = 1` falls at 74.545, which is what makes this discriminating:
    unsnapped, a 1px stroke centered there would cover 45% of column 74
    and 55% of column 75, and *neither* would come out at the exact mark
    color -- so the assertion that column 75 holds 60 exactly-mark
    pixels fails, not merely shifts.
    """
    var c = render(
        eventplot(
            _eventplot_labels(), _eventplot_positions(), width=400, height=300
        )
    )
    var mark = Theme().mark_color

    var on = _column_extent(c, 75, mark)
    assert_true(on.found, "the tick lands on the snapped column")
    assert_equal(on.height(), 60, "and covers it fully, top to bottom")
    assert_true(
        not _column_extent(c, 74, mark).found,
        "nothing bleeds into the column to the left",
    )
    assert_true(
        not _column_extent(c, 76, mark).found,
        "nothing bleeds into the column to the right",
    )


def test_render_eventplot_keeps_an_empty_row() raises:
    """A row with no events keeps its label and its place. "This sensor
    recorded nothing" is a result, and a row that vanished would
    silently renumber every row below it.

    Asserted against the same chart with `b` given an event: the two
    renders must agree on where rows `a` and `c` are, and differ only by
    `b`'s new tick.
    """
    var labels = _eventplot_labels()
    var with_gap = render(
        eventplot(labels, _eventplot_positions(), width=400, height=300)
    )
    var filled_rows = List[List[Float64]]()
    var top: List[Float64] = [1.0, 2.0, 5.0]
    var middle: List[Float64] = [3.0]
    var bottom: List[Float64] = [3.0, 4.0]
    filled_rows.append(top^)
    filled_rows.append(middle^)
    filled_rows.append(bottom^)
    var filled = render(eventplot(labels, filled_rows, width=400, height=300))
    var mark = Theme().mark_color

    # Columns 75 (x = 1) and 293 (x = 4) belong to rows 0 and 2 alone in
    # both renders, so they say where those rows are without b's new
    # tick confusing the extent.
    var gap_first = _column_extent(with_gap, 75, mark)
    var filled_first = _column_extent(filled, 75, mark)
    assert_equal(
        gap_first.y0, filled_first.y0, "row 0 did not move when b filled in"
    )
    assert_equal(gap_first.y1, filled_first.y1)
    var gap_third = _column_extent(with_gap, 293, mark)
    var filled_third = _column_extent(filled, 293, mark)
    assert_equal(gap_third.y0, filled_third.y0, "row 2 did not move either")
    assert_equal(gap_third.y1, filled_third.y1)

    # Column 220 (x = 3) is row 2's in one render and rows 1 *and* 2's
    # in the other. b's band is the middle 76.67px slot, centered on row
    # 135, so its tick covers rows 105..165 -- the gap the empty render
    # leaves between row 0's 88 and row 2's 182.
    var gap_middle = _column_extent(with_gap, 220, mark)
    assert_equal(gap_middle.y0, 182, "with b empty, column 220 is row 2 only")
    var filled_middle = _column_extent(filled, 220, mark)
    assert_equal(filled_middle.y0, 105, "with b filled, its tick is row 1's")
    assert_equal(filled_middle.y1, 241, "and row 2's is still below it")


def test_render_eventplot_line_length_shortens_every_tick() raises:
    """`line_length` scales each tick about its row's center, which is
    the one lever against crowded rows that does not drop an event.

    `0.5` halves the 61.33px band to 30.67px, so the exactly-mark rows
    go from 29..88 to 44..73 -- still centered on 58.5, which is what
    says it shrank rather than moved.
    """
    var c = render(
        eventplot(
            _eventplot_labels(),
            _eventplot_positions(),
            line_length=0.5,
            width=400,
            height=300,
        )
    )
    var mark = Theme().mark_color

    var short = _column_extent(c, 75, mark)
    assert_equal(short.height(), 30, "half the band")
    assert_equal(short.y0, 44)
    assert_equal(short.y1, 73)
    assert_equal(
        short.center_y(), 58, "shrunk about the row center, not from an edge"
    )


def test_render_eventplot_draws_every_event_and_decimates_none() raises:
    """Adding 35 events adds exactly 35 lines. A dropped event is a lie
    in a way a dropped line vertex is not -- a polyline still passes
    through where its missing vertex was, while a missing tick says
    nothing happened -- so this mark thins nothing, unlike the
    `_decimate_to_pixel_columns` pass every long polyline goes through.

    Counted as a *difference* between two charts, not as an absolute:
    the frame draws lines of its own (two axis lines, a tick per
    x-value, a gridline per x-value), and the two charts here share
    every one of them. The 35 extra events go into the middle row and
    all fall strictly inside `(1, 5)`, so the pooled extremes -- and
    therefore the domain, the ticks and the gridlines -- are
    byte-for-byte the same in both.
    """
    var labels = _eventplot_labels()
    var sparse_svg = render_svg(
        eventplot(labels, _eventplot_positions(), width=400, height=300)
    ).to_string()

    var dense_rows = List[List[Float64]]()
    var top: List[Float64] = [1.0, 2.0, 5.0]
    var middle = List[Float64]()
    for i in range(35):
        middle.append(1.0 + Float64(i + 1) * 4.0 / 36.0)
    var bottom: List[Float64] = [3.0, 4.0]
    dense_rows.append(top^)
    dense_rows.append(middle^)
    dense_rows.append(bottom^)
    var dense_svg = render_svg(
        eventplot(labels, dense_rows, width=400, height=300)
    ).to_string()

    assert_equal(
        dense_svg.count("<line") - sparse_svg.count("<line"),
        35,
        "35 more events, 35 more lines -- nothing thinned, nothing merged",
    )


def test_render_eventplot_raises_on_bad_encodings() raises:
    """The three ways to arrive with nothing drawable, each named by
    `encode_eventplot()` rather than surfacing from inside the render.
    """
    var labels = _eventplot_labels()
    var two_rows = List[List[Float64]]()
    var r0: List[Float64] = [1.0]
    var r1: List[Float64] = [2.0]
    two_rows.append(r0^)
    two_rows.append(r1^)
    with assert_raises():
        _ = eventplot(labels, two_rows, width=200, height=150)

    var no_labels = List[String]()
    var no_rows = List[List[Float64]]()
    with assert_raises():
        _ = eventplot(no_labels, no_rows, width=200, height=150)

    var all_empty = List[List[Float64]]()
    for _ in range(3):
        all_empty.append(List[Float64]())
    with assert_raises():
        _ = eventplot(labels, all_empty, width=200, height=150)

    with assert_raises():
        var _hoisted_ev = eventplot(
            labels,
            _eventplot_positions(),
            line_length=0.0,
            width=200,
            height=150,
        )
        _ = render(_hoisted_ev)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
