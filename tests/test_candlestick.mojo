"""Tests for Mark.CANDLESTICK: wicks and bodies (raster + SVG) -- split out
of what used to be one big test_plot.mojo.
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

from _test_helpers import BG, _count_color, _assert_color


def test_render_candlestick_matches_hand_derived_wicks_and_bodies() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = O10/H15/L8/C13
    # (closed up, close >= open); "B" = O20/H22/L16/C17 (closed down).
    # Domain = _data_extent over every O/H/L/C value ([8,22]; no zero
    # baseline, matching Mark.BOX's own reasoning) padded 5% of the
    # 14-span = [7.3, 22.7]. Same 2-category OrdinalScale over [60,380]
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier
    # already worked out (bands at x=76/236, width 128, centers 140/300)
    # -- only the y-domain and per-category shape differ here. Every
    # pixel below independently computed via python3 from LinearScale's
    # own slope/intercept formula, then confirmed against a real
    # render() run before trusting it.
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 140, 200, t.mark_color, "A: inside the body (open=210 to close=165), closed up")
    _assert_color(c, 140, 150, t.axis_color, "A: the wick, above the body (between high=135 and the body top)")
    _assert_color(c, 140, 225, t.axis_color, "A: the wick, below the body (between the body bottom and low=240)")
    _assert_color(c, 300, 80, t.mark_color_negative, "B: inside the body (open=60 to close=105), closed down")
    _assert_color(c, 300, 45, t.axis_color, "B: the wick, above the body (between high=30 and the body top)")
    _assert_color(c, 300, 115, t.axis_color, "B: the wick, below the body (between the body bottom and low=120)")
    _assert_color(c, 190, 150, BG, "no ink here -- off the wick's own x, above A's own body")


def test_render_candlestick_svg_matches_confirmed_wicks_and_bodies() raises:
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="140" y1="135" x2="140" y2="240" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "A's own wick, from high=135 to low=240",
    )
    assert_true('<rect x="76" y="165" width="128" height="45" fill="#1e64b4"/>' in s, "A's own body, closed up")
    assert_true(
        '<line x1="300" y1="30" x2="300" y2="120" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "B's own wick, from high=30 to low=120",
    )
    assert_true(
        '<rect x="236" y="60" width="128" height="45" fill="#c83c3c"/>' in s, "B's own body, closed down"
    )


def test_render_candlestick_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_candlestick_raises_on_mismatched_ohlc_length() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0]
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
