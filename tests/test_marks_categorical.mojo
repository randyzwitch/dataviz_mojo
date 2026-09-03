"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_grouped_bar.mojo`: Tests for Mark.GROUPED_BAR: per-series rectangles and legend (raster +
  SVG).

- `test_stacked_bar.mojo`: Tests for Mark.STACKED_BAR: per-series stacked rectangles and legend,
  including independent positive/negative stacking (raster + SVG).

- `test_percent_stacked_bar.mojo`: Tests for `Plot.mark_stacked_bar(percent=True)`: each category's
  segments rescaled to sum to exactly 100, fixed [0, 100] y-axis, the
  non-negative-value requirement, and the all-zero-category edge case.

- `test_marimekko.mojo`: Tests for Mark.MARIMEKKO (mosaic chart): proportional column
  widths, 0-100% stacked segment heights, encode_marimekko()'s validation (raster + SVG) -- see marimekko.mojo's docstrings for
  the rules verified here.

- `test_population_pyramid.mojo`: Tests for Mark.POPULATION_PYRAMID: two mirrored magnitude bars per
  category, growing outward from a shared, always-centered zero baseline
  (raster + SVG) -- see population_pyramid.mojo's docstrings for the
  domain/rendering rules verified here.

- `test_span_chart.mojo`: Tests for Mark.SPAN_CHART (Mark.GANTT's mirror image: floating
  vertical bars per category) -- raster + SVG.

- `test_gantt.mojo`: Tests for Mark.GANTT: bars from start/end spans (raster + SVG).

- `test_funnel.mojo`: Tests for Mark.FUNNEL: tapering trapezoids, largest value first
  (raster + SVG) -- see funnel.mojo's docstrings for the sort/taper
  rules verified here.

- `test_heatmap.mojo`: Tests for Mark.HEATMAP: one colored grid cell per (x, y) category
  pair (raster + SVG) -- see heatmap.mojo's docstrings for the
  grid-frame/color-scale rules verified here.

- `test_punchcard.mojo`: Tests for Mark.PUNCHCARD: bubble radius = size/scale on a
  categorical grid, independent bubbles for repeated (x, y) pairs,
  encode_punchcard()'s validation (raster + SVG) -- see
  punchcard.mojo's docstrings for the rules verified here.

- `test_corrplot.mojo`: Tests for Mark.CORRPLOT: bubble size/color per correlation cell,
  layout/diag filtering, encode_corrplot()'s validation (raster +
  SVG) -- see corrplot.mojo's docstrings for the rules verified
  here.

- `test_calendar_heatmap.mojo`: Tests for Mark.CALENDAR_HEATMAP: date-to-grid-cell placement
  (day-of-week row, week-of-year column) and color-scale reuse from
  Mark.HEATMAP (raster + SVG) -- see calendar_heatmap.mojo's docstrings for the date-math rules verified here.

"""

from _test_helpers import BG, _assert_color, _count_color
from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
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
    # 2 categories ("A"/"B", short labels -- dynamic left margin stays
    # at Theme's default 60, the same short-label convention every
    # other hand-derived test in this file relies on), 2 series
    # -- `values[0]` (North) = [10, 20] (North's value for A, then
    # B), `values[1]` (South) = [5, 15] (South's value for A, then
    # B): North_A=10, North_B=20, South_A=5, South_B=15 -- easy to
    # mis-cross with North_A/South_A both "the first number," so
    # double-check against this mapping before changing either list.
    # Canvas 400x300, default margins,
    # show_gridlines=False, show_legend left at its default (True)
    # -- grouped bar always reserves a legend column, unlike plain
    # Mark.BAR, so the OrdinalScale's range is [60, 250], not
    # [60, 380] (270 = 400 - Theme's default 130px legend_width,
    # minus margin_right=20).
    #
    # y-domain: _zero_baseline_y_extent over every value (10, 20, 5, 15)
    # -> [0, 21] (zero already exact, so unpadded; 20's +5% pad ->
    # 21). OrdinalScale over [60, 250], 2 categories, step=95,
    # bandwidth=76 (0.2 padding) -> band_start(A)=69.5, band_start(B)=
    # 164.5. sub_width = bandwidth/2 = 38. Every sub-bar's left/
    # right edge computed as a *rounded boundary*, not an independently
    # rounded width -- see _render_grouped_bar's docstring for why.
    #
    # Every position independently re-derived via python3 (LinearScale's
    # slope/intercept for the y-axis, OrdinalScale's band formula for
    # x, both re-solved for this shrunk-by-the-legend range).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = grouped_bar(cats, names, values, theme=t, width=400, height=300)
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
    # The gap between A's two sub-bars and B's two sub-bars is
    # zero (consecutive-boundary rounding, no gap within a category) --
    # but there IS a real gap *between* categories A and B (OrdinalScale's
    # 0.2 padding, band_start(B)=164.5 vs A's band ending at
    # 69.5+76=145.5): x=155 sits in that inter-category gap at any y.
    _assert_color(c, 155, 150, BG, "the inter-category gap between A and B -- background")


def test_render_svg_grouped_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    # Every sub-bar here is non-negative, so every one's bottom edge
    # lands exactly on the drawn bottom axis line -- each height
    # pulled 1px off it. See _pull_off_axis_line's docstring (plot.mojo).
    assert_true('<rect x="70" y="140" width="38" height="109" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="108" y="195" width="38" height="54" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="165" y="31" width="38" height="218" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="203" y="86" width="38" height="163" fill="#ff7f0e"/>' in s, "B/South")

    # Legend: _draw_legend's row layout (legend_swatch_size=14,
    # legend_row_gap=8) is already covered by Mark.POINT's/Mark.ARC's
    # hand-derived legend tests -- this only confirms _render_
    # grouped_bar actually calls it with the right labels/palette/
    # starting position: x=plot_x1+margin_right=250+20=270, y=plot_y0=
    # 20 (row 0), row 1 at y=20+(14+8)=42.
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch"
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch"
    )


def test_render_grouped_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var _hoisted2 = grouped_bar(cats, names, values, width=200, height=150)
    var c = render(_hoisted2)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


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
    # Same 2-category/2-series data test_render_grouped_bar_matches_
    # hand_derived_rectangles already hand-solved the axis frame for
    # (canvas 400x300, default margins, show_gridlines=False, legend
    # reserved -> OrdinalScale range [60,250], band_start(A)=69.5 ->70,
    # band_start(B)=164.5->165, bandwidth=76) -- all positive values
    # here, so only the *positive* running total ever moves. Per
    # category: North stacks first (bottom=0), South stacks on top of
    # it (bottom=North's value). y-domain: _zero_baseline_y_extent
    # over each category's *final* running total (A: 10+5=15, B:
    # 20+15=35) plus the always-included zero -> padded [0, 36.75].
    #
    # Every position independently re-derived via python3 (LinearScale's
    # slope/intercept for the y-axis against this stacked-total
    # domain, OrdinalScale's band formula for x, unchanged from
    # Mark.GROUPED_BAR's -- full band width per segment here, not
    # divided sub-bars).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = stacked_bar(cats, names, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    # A, North (bottom segment, value 10): x:[70,146), y:[187,250)
    _assert_color(c, 100, 220, palette[0], "A/North segment, well inside")
    # A, South (top segment, value 5, stacked on North): x:[70,146), y:[156,187)
    _assert_color(c, 100, 170, palette[1], "A/South segment, stacked on top of North")
    # B, North (bottom segment, value 20): x:[165,241), y:[125,250)
    _assert_color(c, 195, 200, palette[0], "B/North segment, well inside")
    # B, South (top segment, value 15, stacked on North): x:[165,241), y:[31,125)
    _assert_color(c, 195, 80, palette[1], "B/South segment, stacked on top of North")
    # Unlike Mark.GROUPED_BAR, a stacked bar's segments share the
    # *full* band width, so there's no gap between series within a
    # category -- but the inter-category gap (OrdinalScale's 0.2
    # padding) is still there: x=155 sits in it at any y.
    _assert_color(c, 155, 150, BG, "the inter-category gap between A and B -- background")


def test_render_svg_stacked_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    # Only each column's bottom-most segment (North, seg_bottom=0)
    # touches the drawn bottom axis line -- South stacks on top of
    # North, sharing North's top edge, never the axis line itself --
    # so only North's height is pulled 1px off it (63->62, 125->124).
    # See _pull_off_axis_line's docstring (plot.mojo).
    assert_true('<rect x="70" y="187" width="76" height="62" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="70" y="156" width="76" height="31" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="165" y="125" width="76" height="124" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="165" y="31" width="76" height="94" fill="#ff7f0e"/>' in s, "B/South")
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch"
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch"
    )


def test_render_svg_stacked_bar_mixed_sign_stacks_independently_each_direction() raises:
    # One category ("A"), two series: North=10 (positive), South=-5
    # (negative) -- the one case test_render_stacked_bar_matches_hand_
    # derived_rectangles' all-positive data can't exercise: a
    # negative value must stack *downward* from its running
    # negative total (independent of North's positive stack), not
    # slide North's segment down by 5. y-domain: _zero_baseline_y_
    # extent over [pos_total=10, neg_total=-5] -> padded [-5.75, 10.75]
    # (span 15, 5% pad 0.75 each end, zero always included/kept exact).
    # band_start(0)=79 (1 category spans the whole OrdinalScale range,
    # no inter-category gap to speak of), bandwidth=152.
    #
    # Every position independently re-derived via python3.
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    # North: data range [0,10] (positive stack, starts at zero).
    assert_true('<rect x="79" y="30" width="152" height="140" fill="#1f77b4"/>' in s, "North, above zero")
    # South: data range [-5,0] (negative stack, starts at zero, extends down).
    assert_true('<rect x="79" y="170" width="152" height="70" fill="#ff7f0e"/>' in s, "South, below zero")


def test_render_stacked_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var _hoisted2 = stacked_bar(cats, names, values, width=200, height=150)
    var c = render(_hoisted2)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


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
    # Same axis frame as test_stacked_bar.mojo's tests (canvas 400x300,
    # default margins, show_gridlines=False, legend reserved ->
    # x_scale range [60,250], band_start(A)=70, band_start(B)=165,
    # bandwidth=76) -- percent=True fixes the y-domain to exactly
    # [0, 100] regardless of the data, so frame.y_scale maps 0 -> py1
    # (250, the drawn axis line) and 100 -> py0 (20, the top margin),
    # a plain 230px span with no 5%-padding the way a real-valued
    # domain gets from _zero_baseline_y_extent.
    #
    # A: North=30, South=10 -> total 40 -> North 75%, South 25%.
    # B: North=20, South=30 -> total 50 -> North 40%, South 60%.
    # Every position independently re-derived via python3 (percent = value / category_total * 100 for the segment span, then 0..100 -> 250..20 linearly) and cross-checked against the rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 20.0], [10.0, 30.0]]
    var plot = Plot().mark_stacked_bar(percent=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    # A/North: bottom segment, 0..75 -> py 250..78 (230*0.75=172.5), height 171.
    assert_true('<rect x="70" y="78" width="76" height="171" fill="#1f77b4"/>' in s, "A/North (75%)")
    # A/South: stacked on top, 75..100 -> py 78..20, height 58.
    assert_true('<rect x="70" y="20" width="76" height="58" fill="#ff7f0e"/>' in s, "A/South (25%)")
    # B/North: bottom segment, 0..40 -> py 250..158 (230*0.40=92), height 91.
    assert_true('<rect x="165" y="158" width="76" height="91" fill="#1f77b4"/>' in s, "B/North (40%)")
    # B/South: stacked on top, 40..100 -> py 158..20, height 138.
    assert_true('<rect x="165" y="20" width="76" height="138" fill="#ff7f0e"/>' in s, "B/South (60%)")


def test_render_svg_percent_stacked_bar_all_zero_category_is_an_empty_column() raises:
    # Category B's values are all zero -- category_total is 0.0, so
    # scale_factor falls to the 0.0 branch (not a divide-by-zero) and
    # every segment in that column draws at zero height, sitting right
    # on the axis line. Category A (North=30, South=20, unaffected)
    # still renders normally.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 0.0], [20.0, 0.0]]
    var plot = Plot().mark_stacked_bar(percent=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="112" width="76" height="137" fill="#1f77b4"/>' in s, "A/North (60%), unaffected")
    assert_true('<rect x="70" y="20" width="76" height="92" fill="#ff7f0e"/>' in s, "A/South (40%), unaffected")
    assert_true('<rect x="165" y="250" width="76" height="0" fill="#1f77b4"/>' in s, "B/North, zero-height")
    assert_true('<rect x="165" y="250" width="76" height="0" fill="#ff7f0e"/>' in s, "B/South, zero-height")


def test_render_raises_on_percent_stacked_bar_with_a_negative_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[-5.0], [20.0]]
    with assert_raises():
        var plot = Plot().mark_stacked_bar(percent=True).encode_grouped_bar(cats, names, values)
        _ = render_svg(plot)


def test_render_svg_non_percent_stacked_bar_is_unaffected_by_percent_flag() raises:
    # percent=False (the default) must keep behaving exactly as
    # test_stacked_bar.mojo already confirms -- raw values, no
    # rescaling. Regression check against sharing the drawing loop.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="187" width="76" height="62" fill="#1f77b4"/>' in s, "A/North, raw")
    assert_true('<rect x="70" y="156" width="76" height="31" fill="#ff7f0e"/>' in s, "A/South, raw")


def test_stacked_bar_quickplot_accepts_percent_kwarg() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 20.0], [10.0, 30.0]]
    var c = stacked_bar(cats, names, values, width=400, height=300, percent=True)
    var svg = render_svg(c)
    var s = svg.to_string()
    assert_true('<rect x="70" y="78" width="76" height="171" fill="#1f77b4"/>' in s, "quickplot percent=True")

# ---------------------------------------------------------------
# from tests/test_marimekko.mojo
# ---------------------------------------------------------------

def test_render_marimekko_matches_hand_derived_columns() raises:
    # 2 categories ("A", "B"), 2 subcategories ("X", "Y"). values[X] =
    # [30, 10], values[Y] = [10, 30] -- column A totals 40 (75% X, 25%
    # Y), column B totals 40 too (25% X, 75% Y), grand total 80 -> both
    # columns get exactly half the plot width (equal totals here, not
    # a coincidence of the chart type -- just this test's data).
    # Canvas 400x300, show_gridlines=False, show_legend=False: plot
    # area x:[60,380], y:[20,250] -> each column 160px wide, column A
    # x:[60,220), column B x:[220,380). Column A: X segment (75% of
    # 230px height = 172.5 -> 172) sits at the bottom, y:[78,250);
    # column B: Y segment (75%) sits at the bottom instead, y:[193,
    # 250) (see this file's SVG test).
    var cats: List[String] = ["A", "B"]
    var subs: List[String] = ["X", "Y"]
    var values: List[List[Float64]] = [[30.0, 10.0], [10.0, 30.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = marimekko(cats, subs, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 140, 150, palette[0], "column A, well inside the X (bottom) segment")
    _assert_color(c, 140, 40, palette[1], "column A, well inside the Y (top) segment")
    _assert_color(c, 300, 220, palette[0], "column B, well inside the X (bottom) segment")
    _assert_color(c, 300, 100, palette[1], "column B, well inside the Y (top) segment")


def test_render_marimekko_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var subs: List[String] = ["X", "Y"]
    var values: List[List[Float64]] = [[30.0, 10.0], [10.0, 30.0]]
    var plot = Plot().mark_marimekko().encode_marimekko(categories=cats, subcategories=subs, values=values).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="60" y="78" width="160" height="172" fill="#1f77b4"/>' in s, "column A, X segment")
    assert_true('<rect x="60" y="20" width="160" height="58" fill="#ff7f0e"/>' in s, "column A, Y segment")
    assert_true('<rect x="220" y="193" width="160" height="57" fill="#1f77b4"/>' in s, "column B, X segment")
    assert_true('<rect x="220" y="20" width="160" height="173" fill="#ff7f0e"/>' in s, "column B, Y segment")


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


def test_render_marimekko_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var subs = List[String]()
    var values = List[List[Float64]]()
    var _hoisted6 = marimekko(cats, subs, values, width=100, height=80)
    var c = render(_hoisted6)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_population_pyramid.mojo
# ---------------------------------------------------------------

def test_render_population_pyramid_matches_hand_derived_bars() raises:
    # 2 categories ("A", "B"), left=[10, 30], right=[20, 10]. Canvas
    # 400x300, show_gridlines=False, show_legend=False (isolates the
    # bars from the legend's column reservation). The largest
    # magnitude across both sides is 30 -> 5% pad 1.5 -> symmetric
    # x-domain [-31.5, 31.5], mapped to plot x:[60, 380] (short "A"/"B"
    # labels keep the dynamic left margin at Theme's default 60,
    # the same margin test_render_gantt_matches_hand_derived_bars
    # confirms for this identical setup) -- a symmetric
    # domain's midpoint (0.0) always maps to the pixel range's midpoint, so the center baseline lands exactly on pixel 220. y is
    # the categorical axis: OrdinalScale over [20, 250] (2 categories,
    # step 115, bandwidth 92) -- the exact same numbers that same gantt
    # test confirms, since Mark.POPULATION_PYRAMID reuses Mark.
    # GANTT's horizontal frame unchanged. Every x pixel below
    # independently computed via python3 from LinearScale's to_
    # pixel formula.
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 30.0]
    var right: List[Float64] = [20.0, 10.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = population_pyramid(cats, left, right, theme=t, width=400, height=300)
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

    _assert_color(c, 190, 140, BG, "the gap between A's and B's rows -- background")


def test_render_population_pyramid_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 30.0]
    var right: List[Float64] = [20.0, 10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right
    ).theme(Theme(show_gridlines=False, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="169" y="32" width="51" height="92" fill="#1f77b4"/>' in s, "A's left bar")
    assert_true('<rect x="220" y="32" width="102" height="92" fill="#ff7f0e"/>' in s, "A's right bar")
    assert_true('<rect x="68" y="147" width="152" height="92" fill="#1f77b4"/>' in s, "B's left bar")
    assert_true('<rect x="220" y="147" width="51" height="92" fill="#ff7f0e"/>' in s, "B's right bar")


def test_render_population_pyramid_zero_magnitude_draws_no_bar() raises:
    # A zero on one side means nothing to mark there -- unlike Mark.
    # GANTT's zero-length-span-floors-to-1px rule (a real milestone
    # marker), see _render_population_pyramid's docstring for why
    # this mark deliberately does not floor.
    var cats: List[String] = ["Only"]
    var left: List[Float64] = [0.0]
    var right: List[Float64] = [10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right
    ).theme(Theme(show_gridlines=False, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('fill="#1f77b4"' not in s, "zero-magnitude left side draws no rect at all")
    assert_true('fill="#ff7f0e"' in s, "the non-zero right side still draws")


def test_render_population_pyramid_legend_uses_left_right_fallback_names() raises:
    # No left_name/right_name given -- _render_population_pyramid's docstring says the legend still draws, falling back to "Left"/
    # "Right", unlike Mark.GROUPED_BAR's legend which needs real names.
    var cats: List[String] = ["A"]
    var left: List[Float64] = [10.0]
    var right: List[Float64] = [10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">Left<" in s, "the fallback legend label for the left side")
    assert_true(">Right<" in s, "the fallback legend label for the right side")


def test_render_population_pyramid_legend_uses_given_names() raises:
    var cats: List[String] = ["A"]
    var left: List[Float64] = [10.0]
    var right: List[Float64] = [10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right, left_name="Male", right_name="Female"
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">Male<" in s, "the given left legend label")
    assert_true(">Female<" in s, "the given right legend label")


def test_render_population_pyramid_raises_on_mismatched_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = population_pyramid(cats, one, one, width=200, height=150)
        _ = render(_hoisted2)


def test_render_population_pyramid_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[Float64]()
    var _hoisted3 = population_pyramid(cats, vals, vals, width=200, height=150)
    var c = render(_hoisted3)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")

# ---------------------------------------------------------------
# from tests/test_span_chart.mojo
# ---------------------------------------------------------------

def test_render_span_chart_matches_hand_derived_bars() raises:
    # 2 categories ("A", "B" -- short labels, default left margin).
    # "A" spans [10,40], "B" spans [50,90] -- the exact same numbers
    # test_gantt.mojo's hand-derived case uses, transposed onto
    # the vertical categorical frame here instead. Canvas 400x300,
    # show_gridlines=False: plot area x:[60,380], y:[20,250]. Domain
    # data = [10,40,50,90] -> _data_extent pads 5% of the 80-span
    # (4.0) -> y-domain [6, 94]. x is now the *categorical* axis:
    # OrdinalScale over [60,380] (2 categories, step=160, padding 0.2
    # -> bandwidth 128), band A: x:[76,204], band B: x:[236,364].
    # Bar A (low 10, high 40) -> rect (76, 161, 128, 79); bar B (low
    # 50, high 90) -> rect (236, 30, 128, 105) (see this file's SVG
    # test).
    var cats: List[String] = ["A", "B"]
    var low: List[Float64] = [10.0, 50.0]
    var high: List[Float64] = [40.0, 90.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = span_chart(cats, low, high, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 200, t.mark_color, "well inside bar A's rect (76,161,128,79)")
    _assert_color(c, 300, 80, t.mark_color, "well inside bar B's rect (236,30,128,105)")
    _assert_color(c, 220, 100, BG, "the gap between the two bars")


def test_render_span_chart_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var low: List[Float64] = [10.0, 50.0]
    var high: List[Float64] = [40.0, 90.0]
    var plot = Plot().mark_span_chart().encode_gantt(categories=cats, start=low, end=high).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="76" y="161" width="128" height="79" fill="#1e64b4"/>' in s, "bar A's rect")
    assert_true('<rect x="236" y="30" width="128" height="105" fill="#1e64b4"/>' in s, "bar B's rect")


def test_render_span_chart_zero_length_span_floors_to_one_pixel() raises:
    var cats: List[String] = ["A"]
    var low: List[Float64] = [10.0]
    var high: List[Float64] = [10.0]
    var _hoisted2 = span_chart(cats, low, high, width=200, height=150)
    var c = render(_hoisted2)
    # No assertion failure means a zero-height bar didn't raise or
    # vanish -- the same "real, visible data" floor Mark.GANTT's equivalent test confirms.
    _ = c


def test_render_span_chart_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var low: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted3 = span_chart(cats, low, high, width=200, height=150)
        _ = render(_hoisted3)


def test_render_span_chart_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var low = List[Float64]()
    var high = List[Float64]()
    var _hoisted4 = span_chart(cats, low, high, width=100, height=80)
    var c = render(_hoisted4)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_gantt.mojo
# ---------------------------------------------------------------

def test_render_gantt_matches_hand_derived_bars() raises:
    # 2 categories ("A", "B" -- short labels, so the dynamic left margin
    # stays at Theme's default 60, the same "A"/short-label convention
    # test_render_left_margin_unchanged_for_short_y_axis_labels already
    # established, sidestepping real font-metric dependence). Canvas
    # 400x300, plot area x:[60,380], y:[20,250], show_gridlines=False.
    # "A" spans [10,40], "B" spans [50,90]. Domain data = every start/end
    # value = [10,40,50,90] -> _data_extent pads 5% of the 80-span (4.0)
    # -> x-domain [6, 94]. y is now the *categorical* axis: OrdinalScale
    # over [20,250] (2 categories, step=115, padding 0.2 -> bandwidth
    # 92), category 0 ("A") landing nearer the *top* (smaller pixel y)
    # than category 1 ("B") -- see below.
    # Every pixel independently computed via python3 from LinearScale's/
    # OrdinalScale's formulas.
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = gantt(cats, start, end, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 100, 60, t.mark_color, "A's bar (x:[75,184), y:[32,124)), well inside")
    _assert_color(c, 250, 180, t.mark_color, "B's bar (x:[220,365), y:[147,239)), well inside")
    _assert_color(c, 100, 140, BG, "the gap between A's and B's rows -- background")
    _assert_color(c, 200, 60, BG, "A's row, but past its bar's right edge -- background")
    _assert_color(c, 10, 60, BG, "left of the plot area entirely -- background")


def test_render_gantt_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="75" y="32" width="109" height="92" fill="#1e64b4"/>' in s, "A's bar")
    assert_true('<rect x="220" y="147" width="145" height="92" fill="#1e64b4"/>' in s, "B's bar")


def test_render_gantt_zero_length_span_floors_to_one_pixel() raises:
    # A milestone: start == end. _render_gantt's docstring is
    # explicit this is real, informative data (a deadline marker), not
    # an absent value the way Mark.BULLET's zero-measure case is --
    # floored to 1px rather than drawn as a genuinely zero-width
    # (invisible) rect the way a naive fill_rect call would.
    var cats: List[String] = ["Launch"]
    var start: List[Float64] = [50.0]
    var end: List[Float64] = [50.0]
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('width="1"' in s, "the milestone's bar, floored to a visible 1px width")


def test_render_gantt_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = gantt(cats, one, one, width=200, height=150)
        _ = render(_hoisted2)


def test_render_gantt_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var empty = List[Float64]()
    var _hoisted3 = gantt(cats, empty, empty, width=200, height=150)
    var c = render(_hoisted3)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")

# ---------------------------------------------------------------
# from tests/test_funnel.mojo
# ---------------------------------------------------------------

def test_render_funnel_matches_hand_derived_trapezoids() raises:
    # 3 categories, already given largest-to-smallest (100, 60, 20) so
    # display order matches input order -- isolates the taper/palette
    # math from the sort itself (see the dedicated sort test below for
    # that). Canvas 400x300, show_legend=False: plot area x:[60,380],
    # y:[20,250], center x=220, max_width=320, row_height=(250-20)/3 =
    # 76.667. top_width[i] = value[i]/100*320 -> 320/192/64; bottom_
    # width[i] = top_width[i+1] (192/64), except the last row, whose
    # bottom matches its top (64, flat). See this file's SVG test
    # for the exact path data. Sampled at
    # each row's vertical midpoint, x=220 (dead center -- always
    # inside every trapezoid, symmetric around cx, regardless of its
    # width), so no left/right-edge math is needed here at all.
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Float64] = [100.0, 60.0, 20.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = funnel(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 220, 58, palette[0], "row 0 (A, value 100) -- the widest row")
    _assert_color(c, 220, 134, palette[1], "row 1 (B, value 60)")
    _assert_color(c, 220, 211, palette[2], "row 2 (C, value 20) -- the narrowest row")
    _assert_color(c, 10, 10, BG, "outside the whole funnel -- background")


def test_render_funnel_svg_matches_confirmed_paths() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Float64] = [100.0, 60.0, 20.0]
    var plot = Plot().mark_funnel().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<path d="M60.000,20.000 L380.000,20.000 L316.000,96.000 L124.000,96.000 Z" fill="#1f77b4"/>' in s, "row 0")
    assert_true(
        '<path d="M124.000,96.000 L316.000,96.000 L252.000,173.000 L188.000,173.000 Z" fill="#ff7f0e"/>' in s,
        "row 1",
    )
    assert_true(
        '<path d="M188.000,173.000 L252.000,173.000 L252.000,250.000 L188.000,250.000 Z" fill="#2ca02c"/>' in s,
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
    var plot = Plot().mark_funnel().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('M60.000,20.000 L380.000,20.000' in s, "row 0's top edge spans the full plot width -- it's Big, not Small")


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


def test_render_funnel_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[Float64]()
    var _hoisted5 = funnel(cats, vals, width=200, height=150)
    var c = render(_hoisted5)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")

# ---------------------------------------------------------------
# from tests/test_heatmap.mojo
# ---------------------------------------------------------------

def test_render_heatmap_matches_hand_derived_cells() raises:
    # 2 x-categories ("Mon", "Tue"), 2 y-categories ("AM", "PM"), one
    # row per cell: (Mon,AM)=1.0, (Mon,PM)=2.0, (Tue,AM)=3.0, (Tue,PM)
    # =4.0. Canvas 400x300, show_gridlines=False, show_legend=False.
    # Short "AM"/"PM" labels keep the dynamic left margin at Theme's
    # default 60 (the same margin every other categorical-mark
    # test with short labels confirms). x_scale/y_scale both use
    # padding=0.0 (see _draw_grid_axis_frame's docstring), so with
    # exactly 2 categories on each axis and plot area x:[60,380],
    # y:[20,250], every band is exactly half that span: cell width 160
    # (x:[60,220) for "Mon", x:[220,380) for "Tue"), cell height 115
    # (y:[20,135) for "AM", y:[135,250) for "PM") -- category index 0
    # lands first (top/left), the same reading-order convention Mark.
    # GANTT's y-axis uses.
    #
    # value=1.0 is the color domain's min -> exactly Theme's
    # color_scale_low, Color(60,110,200); value=4.0 is the max ->
    # exactly color_scale_high, Color(220,90,40) -- both read directly
    # off Theme, not re-derived. The two in-between cells' colors
    # (t=1/3 and t=2/3 through the now-three-stop gradient -- low at
    # 0.0, color_scale_mid at 0.5, high at 1.0, see Theme.color_scale_
    # mid's docstring for why a middle stop exists at all) aren't
    # hand-derived here -- ColorScale's interpolation is already
    # covered by test_color_scale.mojo: Color(177,193,223) (t=1/3,
    # bracketed between low and mid) and Color(230,187,170) (t=2/3,
    # bracketed between mid and high).
    var x: List[String] = ["Mon", "Mon", "Tue", "Tue"]
    var y: List[String] = ["AM", "PM", "AM", "PM"]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = heatmap(x, y, v, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 100, 60, Color(60, 110, 200), "(Mon, AM) = 1.0, the color domain's min")
    _assert_color(c, 100, 180, Color(177, 193, 223), "(Mon, PM) = 2.0")
    _assert_color(c, 300, 60, Color(230, 187, 170), "(Tue, AM) = 3.0")
    _assert_color(c, 300, 180, Color(220, 90, 40), "(Tue, PM) = 4.0, the color domain's max")
    _assert_color(c, 10, 10, BG, "outside the plot area entirely -- background")


def test_render_heatmap_svg_matches_confirmed_rects() raises:
    var x: List[String] = ["Mon", "Mon", "Tue", "Tue"]
    var y: List[String] = ["AM", "PM", "AM", "PM"]
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var plot = Plot().mark_heatmap().encode_heatmap(x=x, y=y, value=v).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="60" y="20" width="160" height="115" fill="#3c6ec8"/>' in s, "(Mon, AM)")
    assert_true('<rect x="60" y="135" width="160" height="115" fill="#b1c1df"/>' in s, "(Mon, PM)")
    assert_true('<rect x="220" y="20" width="160" height="115" fill="#e6bbaa"/>' in s, "(Tue, AM)")
    assert_true('<rect x="220" y="135" width="160" height="115" fill="#dc5a28"/>' in s, "(Tue, PM)")


def test_render_heatmap_missing_cell_leaves_background() raises:
    # A sparse grid -- no (Tue, PM) row at all. _render_heatmap's docstring: a missing combination just isn't drawn, not an error
    # or a zero.
    var x: List[String] = ["Mon", "Mon", "Tue"]
    var y: List[String] = ["AM", "PM", "AM"]
    var v: List[Float64] = [1.0, 2.0, 3.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = heatmap(x, y, v, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 300, 180, BG, "(Tue, PM) was never given -- background shows through")


def test_render_heatmap_legend_shows_value_domain() raises:
    var x: List[String] = ["Mon", "Tue"]
    var y: List[String] = ["AM", "AM"]
    var v: List[Float64] = [1.0, 4.0]
    var plot = Plot().mark_heatmap().encode_heatmap(x=x, y=y, value=v).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">4.0<" in s, "the color domain's max, at the top of the legend bar")
    assert_true(">1.0<" in s, "the color domain's min, at the bottom of the legend bar")


def test_render_heatmap_raises_on_mismatched_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    var y: List[String] = ["a", "b", "c"]
    with assert_raises():
        var _hoisted3 = heatmap(x, y, one, width=200, height=150)
        _ = render(_hoisted3)


def test_render_heatmap_empty_data_only_fills_background() raises:
    var x = List[String]()
    var y = List[String]()
    var v = List[Float64]()
    var _hoisted4 = heatmap(x, y, v, width=200, height=150)
    var c = render(_hoisted4)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")

# ---------------------------------------------------------------
# from tests/test_punchcard.mojo
# ---------------------------------------------------------------

def test_render_punchcard_matches_hand_derived_bubbles() raises:
    # 2 x-categories ("Mon", "Tue"), 2 y-categories ("9am", "10am"),
    # 3 rows -- (Mon,9am)=50, (Mon,10am)=100, (Tue,9am)=20, scale=10.0
    # (the default): radius = size/scale -> 5, 10, 2. Canvas 400x300,
    # show_gridlines=False, show_legend=False: Mark.HEATMAP's _draw_grid_axis_frame, plot area x:[60,380], y:[20,250], 2
    # categories on each axis -> centers (140, 78)/(140, 193)/(300, 78)
    # (see this file's SVG test).
    var x: List[String] = ["Mon", "Mon", "Tue"]
    var y: List[String] = ["9am", "10am", "9am"]
    var sizes: List[Float64] = [50.0, 100.0, 20.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = punchcard(x, y, sizes, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 78, t.mark_color, "(Mon, 9am), size 50 -> radius 5")
    _assert_color(c, 140, 193, t.mark_color, "(Mon, 10am), size 100 -> radius 10")
    _assert_color(c, 300, 78, t.mark_color, "(Tue, 9am), size 20 -> radius 2")
    _assert_color(c, 300, 193, BG, "(Tue, 10am) was never given -- background")


def test_render_punchcard_svg_matches_confirmed_circles() raises:
    var x: List[String] = ["Mon", "Mon", "Tue"]
    var y: List[String] = ["9am", "10am", "9am"]
    var sizes: List[Float64] = [50.0, 100.0, 20.0]
    var plot = Plot().mark_punchcard(scale=10.0).encode_punchcard(x=x, y=y, sizes=sizes).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<circle cx="140" cy="78" r="5" fill="#1e64b4"/>' in s, "(Mon, 9am)")
    assert_true('<circle cx="140" cy="193" r="10" fill="#1e64b4"/>' in s, "(Mon, 10am)")
    assert_true('<circle cx="300" cy="78" r="2" fill="#1e64b4"/>' in s, "(Tue, 9am)")


def test_render_punchcard_repeated_cell_draws_two_independent_bubbles() raises:
    # Two rows share the exact same (x, y) cell with different sizes
    # -- both bubbles draw (the smaller nested inside the larger,
    # since both share a center), not merged/summed into one. Only one
    # x-category ("Mon") and one y-category ("9am") here, so the
    # shared center is the plot area's full midpoint (220, 135),
    # not a divided-grid cell center. A pixel just outside the smaller
    # bubble's radius (r=2) but still inside the larger one (r=10)
    # confirms the larger bubble is really there, not silently dropped
    # in favor of the last-drawn row.
    var x: List[String] = ["Mon", "Mon"]
    var y: List[String] = ["9am", "9am"]
    var sizes: List[Float64] = [20.0, 100.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = punchcard(x, y, sizes, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 220, 134, t.mark_color, "1px above center -- inside the smaller (r=2) and larger (r=10) both")
    _assert_color(c, 220, 128, t.mark_color, "7px above center -- outside r=2, inside the larger bubble (r=10)")


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


def test_render_punchcard_empty_data_only_fills_background() raises:
    var x = List[String]()
    var y = List[String]()
    var sizes = List[Float64]()
    var _hoisted5 = punchcard(x, y, sizes, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no data: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_corrplot.mojo
# ---------------------------------------------------------------

def test_render_corrplot_matches_hand_derived_bubbles() raises:
    # 2 variables ("A", "B"), matrix [[1, -0.5], [-0.5, 1]]. Canvas
    # 400x300, show_gridlines=False, show_legend=False:
    # _draw_grid_axis_frame (padding=0.0), 2 categories on each
    # axis over plot area x:[60,380], y:[20,250] -> cell width 160,
    # cell height 115. max bubble radius = min(160,115)/2*0.42 =
    # 57.5*0.42 = 24.15 -> 24 at |value|=1.0.
    #
    # Cell (A,A) [row 0, col 0, value 1.0]: center (140, 78), radius
    # 24, color exactly Theme's color_scale_high (the domain's max). Cell (A,B) [row 0, col 1, value -0.5]: center (300, 78),
    # radius round(24.15*0.5)=12, color at t=0.25 through the [-1,1]
    # gradient -- (148,173,218), bracketed between color_scale_low and
    # color_scale_mid (Theme's three-stop gradient, see that
    # field's docstring; see this file's SVG test) -- not re-derived
    # from ColorScale's interpolation math again, already covered by
    # test_color_scale.mojo.
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = corrplot(vars, m, labels=False, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 78, t.color_scale_high, "(A, A) = 1.0, the color domain's max")
    _assert_color(c, 300, 78, Color(148, 173, 218), "(A, B) = -0.5, t=0.25 through the gradient")
    _assert_color(c, 140, 193, Color(148, 173, 218), "(B, A) = -0.5, symmetric with (A, B)")
    _assert_color(c, 300, 193, t.color_scale_high, "(B, B) = 1.0, the color domain's max")
    _assert_color(c, 200, 78, BG, "between the two bubbles on row A -- no bubble reaches that far")


def test_render_corrplot_svg_matches_confirmed_circles() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var plot = Plot().mark_corrplot(labels=False).encode_corrplot(variables=vars, matrix=m).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<circle cx="140" cy="78" r="24" fill="#dc5a28"/>' in s, "(A, A)")
    assert_true('<circle cx="300" cy="78" r="12" fill="#94adda"/>' in s, "(A, B)")
    assert_true('<circle cx="140" cy="193" r="12" fill="#94adda"/>' in s, "(B, A)")
    assert_true('<circle cx="300" cy="193" r="24" fill="#dc5a28"/>' in s, "(B, B)")


def test_render_corrplot_lower_layout_without_diag_keeps_only_below_diagonal() raises:
    # layout="lower" (row >= col), diag=False (row == col dropped
    # too) over a 2x2 matrix keeps exactly one cell: (B, A), row=1 >
    # col=0. (A,A)/( B,B) (the diagonal) and (A,B) (row < col, the
    # upper triangle) all stay background.
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = corrplot(vars, m, layout="lower", diag=False, labels=False, theme=t, width=400, height=300)
    var c = render(_hoisted2)

    _assert_color(c, 140, 78, BG, "(A, A) -- diagonal, dropped by diag=False")
    _assert_color(c, 300, 78, BG, "(A, B) -- upper triangle, dropped by layout=\"lower\"")
    _assert_color(c, 140, 193, Color(148, 173, 218), "(B, A) -- the one surviving cell")
    _assert_color(c, 300, 193, BG, "(B, B) -- diagonal, dropped by diag=False")


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


def test_render_corrplot_empty_variables_only_fills_background() raises:
    var vars = List[String]()
    var m = List[List[Float64]]()
    var _hoisted6 = corrplot(vars, m, width=100, height=80)
    var c = render(_hoisted6)
    _assert_color(c, 50, 40, BG, "no variables: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_calendar_heatmap.mojo
# ---------------------------------------------------------------

def test_render_calendar_heatmap_matches_hand_derived_cells() raises:
    # 2024-01-01 (a real-world Monday), 2024-01-07 (the following
    # Sunday -- 6 days later, wrapping to the *next* week's column since Sunday starts a new week here), and 2024-12-31 (a
    # real-world Tuesday, the year's last day, in the year's last column). Values [1.0, 2.0, 3.0] -- min/mid/max of the color
    # domain, so the first and third cells read directly off Theme's
    # color_scale_low/high, no ColorScale interpolation math to
    # re-derive here.
    #
    # Canvas 900x300, show_legend=False: plot area x:[60,880],
    # y:[20,250] (top margin grows by one font-size + label-gap for
    # the month-label row above the grid). 2024 is a leap year (366
    # days) -> 53 week-columns. Every rect below (see this file's SVG test):
    # Jan 1 (Mon, row 1, col 0) -> rect(60,67,15,31); Jan 7 (Sun, row
    # 0, col 1) -> rect(75,36,15,31); Dec 31 (Tue, row 2, col 52) ->
    # rect(865,97,15,31). Interior points sampled well inside each
    # rect's bounds, not on an edge.
    #
    # value=2.0 sits at the color domain's exact midpoint (t=0.5)
    # -- lands on Theme's color_scale_mid exactly, not an
    # interpolated blend: ColorScale.from_theme() adds that as a real
    # stop at offset 0.5 (see its docstring), and _color_at_t
    # brackets an exact-offset match to itself (before == after), no
    # RGB-space interpolation involved at all. Read directly off Theme
    # the same way the min/max cells already are, not hand-derived.
    var dates: List[String] = ["2024-01-01", "2024-01-07", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = calendar_heatmap(dates, values, theme=t, width=900, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 67, 82, t.color_scale_low, "Jan 1 (Mon), value 1.0 -- the color domain's min")
    _assert_color(c, 82, 51, t.color_scale_mid, "Jan 7 (Sun), value 2.0 -- the domain's exact midpoint")
    _assert_color(c, 872, 112, t.color_scale_high, "Dec 31 (Tue), value 3.0 -- the color domain's max")
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_calendar_heatmap_svg_matches_confirmed_rects() raises:
    var dates: List[String] = ["2024-01-01", "2024-01-07", "2024-12-31"]
    var values: List[Float64] = [1.0, 2.0, 3.0]
    var plot = Plot().mark_calendar_heatmap().encode_calendar(dates=dates, values=values).theme(
        Theme(show_legend=False)
    ).size(900, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="60" y="67" width="15" height="31" fill="#3c6ec8"/>' in s, "Jan 1 (Mon), col 0")
    assert_true('<rect x="75" y="36" width="15" height="31" fill="#ebebeb"/>' in s, "Jan 7 (Sun), col 1")
    assert_true('<rect x="865" y="97" width="15" height="31" fill="#dc5a28"/>' in s, "Dec 31 (Tue), col 52")


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


def test_render_calendar_heatmap_empty_data_only_fills_background() raises:
    var dates = List[String]()
    var values = List[Float64]()
    var _hoisted4 = calendar_heatmap(dates, values, width=100, height=80)
    var c = render(_hoisted4)
    _assert_color(c, 50, 40, BG, "no dates at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
