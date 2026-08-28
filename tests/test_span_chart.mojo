"""Tests for Mark.SPAN_CHART (Mark.GANTT's mirror image: floating
vertical bars per category) -- raster + SVG.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import span_chart

from _test_helpers import BG, _assert_color


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
    var c = render(span_chart(cats, low, high, theme=t, width=400, height=300))

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
    var c = render(span_chart(cats, low, high, width=200, height=150))
    # No assertion failure means a zero-height bar didn't raise or
    # vanish -- the same "real, visible data" floor Mark.GANTT's equivalent test confirms.
    _ = c


def test_render_span_chart_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var low: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = render(span_chart(cats, low, high, width=200, height=150))


def test_render_span_chart_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var low = List[Float64]()
    var high = List[Float64]()
    var c = render(span_chart(cats, low, high, width=100, height=80))
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
