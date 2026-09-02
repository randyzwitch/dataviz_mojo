"""Tests for Mark.CANDLESTICK: wicks and bodies (raster + SVG).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
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
    _index_of,
    _unique_categories,
)
from dataviz.theme import Theme
from dataviz import candlestick

from _test_helpers import BG, _count_color, _assert_color, _assert_near_color


def test_render_candlestick_matches_hand_derived_wicks_and_bodies() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = O10/H15/L8/C13
    # (closed up, close >= open); "B" = O20/H22/L16/C17 (closed down).
    # Domain = _data_extent over every O/H/L/C value ([8,22]; no zero
    # baseline, matching Mark.BOX's reasoning) padded 5% of the
    # 14-span = [7.3, 22.7]. Same 2-category OrdinalScale over [60,380]
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier
    # already worked out (bands at x=76/236, width 128, centers 140/300)
    # -- only the y-domain and per-category shape differ here. Every
    # pixel below independently computed via python3 from
    # LinearScale's slope/intercept formula.
    # Built via Plot/Canvas/render() directly, not candlestick() -- see
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_
    # outlier's comment for why an exact hand-derived pixel check
    # uses render() itself rather than the (now internally
    # supersampled) quickplot wrapper.
    #
    # The 4 wick checks use `_assert_near_color()`, not `_assert_
    # color()` -- a wick is a 1px-wide stroke, the same reason every
    # other mark's axis-line/gridline checks already need the
    # tolerant helper (see its docstring, tests/_test_helpers.mojo).
    # The 2 body checks (solid interior) and the background check (a
    # wide-open empty area) stay exact -- both robust by construction.
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 200, t.mark_color, "A: inside the body (open=210 to close=165), closed up")
    _assert_near_color(c, 140, 150, t.axis_color, 60, "A: the wick, above the body (between high=135 and the body top)")
    _assert_near_color(c, 140, 225, t.axis_color, 60, "A: the wick, below the body (between the body bottom and low=240)")
    _assert_color(c, 300, 80, t.mark_color_negative, "B: inside the body (open=60 to close=105), closed down")
    _assert_near_color(c, 300, 45, t.axis_color, 60, "B: the wick, above the body (between high=30 and the body top)")
    _assert_near_color(c, 300, 115, t.axis_color, 60, "B: the wick, below the body (between the body bottom and low=120)")
    _assert_color(c, 190, 150, BG, "no ink here -- off the wick's x, above A's body")


def test_render_candlestick_svg_matches_confirmed_wicks_and_bodies() raises:
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="140" y1="135" x2="140" y2="240" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "A's wick, from high=135 to low=240",
    )
    assert_true('<rect x="76" y="165" width="128" height="45" fill="#1e64b4"/>' in s, "A's body, closed up")
    assert_true(
        '<line x1="300" y1="30" x2="300" y2="120" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "B's wick, from high=30 to low=120",
    )
    assert_true(
        '<rect x="236" y="60" width="128" height="45" fill="#c83c3c"/>' in s, "B's body, closed down"
    )


def test_render_candlestick_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = candlestick(cats, open, high, low, close, width=200, height=150)
        _ = render(_hoisted2)


def test_render_candlestick_raises_on_mismatched_ohlc_length() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0]
    with assert_raises():
        var _hoisted3 = candlestick(cats, open, high, low, close, width=200, height=150)
        _ = render(_hoisted3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
