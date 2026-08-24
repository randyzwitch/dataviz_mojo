"""Tests for Mark.WATERFALL: sign-colored bars, running total rows,
connectors (raster + SVG).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
    _index_of,
    _unique_categories,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo import waterfall

from _test_helpers import BG, _count_color, _assert_color


def test_render_waterfall_colors_by_sign_and_matches_hand_derived_bars() raises:
    # 3 categories, deltas=[10, -4, 6] -- running totals y0/y1 = [0,10,
    # 10,6, 6,12]. Combined domain [0, 12.6] (_zero_baseline_y_extent
    # over y0 union y1) lands each category's band at the *same*
    # x positions test_render_bar_mark_matches_hand_derived_bar_
    # rectangles already confirmed (113/220/327 centers) since both use
    # the identical 3-category OrdinalScale over the same [60,380]
    # range -- only the y-domain and per-bar y0/y1 differ. Per bar:
    # bar 0 (delta +10) mark_color, bar 1 (delta -4) mark_color_
    # negative -- unconditional sign coloring, no Theme.color_by_sign
    # flag needed, unlike Mark.BAR -- bar 2 (delta +6) mark_color again,
    # and the two connector lines (gridline_color) at the pixel height
    # where consecutive bars' running totals hand off.
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var t = Theme(show_gridlines=False)
    var c = waterfall(cats, deltas, theme=t, width=400, height=300)

    _assert_color(c, 113, 150, t.mark_color, "bar 0 (delta +10), well inside its rect")
    _assert_color(c, 220, 100, t.mark_color_negative, "bar 1 (delta -4), colored by sign")
    _assert_color(c, 327, 80, t.mark_color, "bar 2 (delta +6), back to mark_color")
    _assert_color(c, 165, 67, t.axis_color, "connector between bar 0 and bar 1")
    _assert_color(c, 273, 140, t.axis_color, "connector between bar 1 and bar 2")
    _assert_color(c, 350, 10, BG, "far from every bar -- background")


def test_render_waterfall_svg_matches_confirmed_rects_and_connectors() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="71" y="67" width="85" height="183" fill="#1e64b4"/>' in s, "bar 0 (delta +10): y0=0 to y1=10"
    )
    assert_true(
        '<rect x="177" y="67" width="85" height="73" fill="#c83c3c"/>' in s,
        "bar 1 (delta -4): y0=10 down to y1=6, colored by sign",
    )
    assert_true(
        '<rect x="284" y="31" width="85" height="109" fill="#1e64b4"/>' in s, "bar 2 (delta +6): y0=6 to y1=12"
    )
    assert_true(
        '<line x1="156" y1="67" x2="177" y2="67" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector between bar 0 and bar 1, at the shared y1=10/y0=10 pixel height",
    )
    assert_true(
        '<line x1="263" y1="140" x2="284" y2="140" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector between bar 1 and bar 2, at the shared y1=6/y0=6 pixel height",
    )


def test_render_waterfall_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = waterfall(cats, deltas, width=200, height=150)


def test_render_waterfall_total_rows_matches_hand_derived_bars() raises:
    # 4 categories: "Start" (total, delta=50 -- a starting-balance total
    # still *adds* its delta to the running sum, just displays 0 ->
    # the result instead of floating -- see encode_waterfall()'s docstring), "A" (delta +20, plain), "B" (delta -10, plain), "End"
    # (total, delta=0 -- contributes nothing further, displays 0 -> the
    # final running sum). Running sum: Start 0+50=50 (y0=0,y1=50), A
    # 50+20=70 (y0=50,y1=70), B 70-10=60 (y0=70,y1=60), End 60+0=60
    # (y0=0,y1=60). Canvas 400x300, default margins, show_gridlines=
    # False. _zero_baseline_y_extent over the combined y0/y1 set
    # {0,50,70,60} -> domain [0, 73.5] (70's +5% pad).
    #
    # OrdinalScale over [60,380], 4 categories, step=80, bandwidth=64 ->
    # band_start: Start=68, A=148, B=228, End=308. Total bars draw full
    # band width (64px); delta bars draw _WATERFALL_DELTA_WIDTH_FRACTION
    # (0.6) of it, centered -- narrow=38.4, inset=12.8, so A/B's bars are inset ~13px from their band's edges on both sides.
    #
    # Every position independently re-derived via python3 (LinearScale's
    # slope/intercept for y, OrdinalScale's band formula for x).
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var t = Theme(show_gridlines=False)
    var c = waterfall(cats, deltas, is_total=is_total, theme=t, width=400, height=300)

    # Start (total): x:[68,132), y:[94,250) -- full band width.
    _assert_color(c, 100, 200, t.waterfall_total_color, "Start (total), well inside")
    # A (delta +20, narrower): x:[161,199), y:[31,94).
    _assert_color(c, 180, 60, t.mark_color, "A (delta +20), well inside its narrower rect")
    # A's band still has real background on either side of the
    # narrow bar -- confirming it actually IS narrower, not just a
    # differently-colored full-width bar.
    _assert_color(c, 150, 60, BG, "A's band, left of its narrow bar -- background")
    # B (delta -10, narrower): x:[241,279), y:[31,62).
    _assert_color(c, 260, 45, t.mark_color_negative, "B (delta -10), colored by sign")
    # End (total): x:[308,372), y:[62,250) -- full band width again.
    _assert_color(c, 340, 150, t.waterfall_total_color, "End (total), well inside")


def test_render_svg_waterfall_total_rows_matches_confirmed_rects() raises:
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas, is_total).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="68" y="94" width="64" height="156" fill="#646464"/>' in s, "Start (total): 0 -> 50"
    )
    assert_true('<rect x="161" y="31" width="38" height="63" fill="#1e64b4"/>' in s, "A: 50 -> 70")
    assert_true('<rect x="241" y="31" width="38" height="31" fill="#c83c3c"/>' in s, "B: 70 -> 60")
    assert_true(
        '<rect x="308" y="62" width="64" height="188" fill="#646464"/>' in s, "End (total): 0 -> 60"
    )
    # Connectors reference each bar's *actual* drawn edge (`bar_x_
    # list[i-1] + bar_width_list[i-1]`, not a formula re-derived from
    # the band directly) once total rows are in play -- guards
    # against a 1px mismatch between a full-width bar's
    # independently-rounded width and a boundary-rounded connector
    # position. Start's right edge (68+64=132) ->
    # A's left edge (161); A's right edge (161+38=199) -> B's
    # own left edge (241); B's right edge (241+38=279) -> End's left edge (308).
    assert_true(
        '<line x1="132" y1="94" x2="161" y2="94" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: Start's actual right edge -> A's left edge",
    )
    assert_true(
        '<line x1="199" y1="31" x2="241" y2="31" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: A's actual right edge -> B's left edge",
    )
    assert_true(
        '<line x1="279" y1="62" x2="308" y2="62" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: B's actual right edge -> End's left edge",
    )


def test_render_waterfall_raises_on_mismatched_is_total_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var is_total: List[Bool] = [True, False]
    with assert_raises():
        _ = waterfall(cats, deltas, is_total=is_total, width=400, height=300)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
