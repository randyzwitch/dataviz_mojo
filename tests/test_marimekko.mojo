"""Tests for Mark.MARIMEKKO (mosaic chart): proportional column
widths, 0-100% stacked segment heights, encode_marimekko()'s validation (raster + SVG) -- see marimekko.mojo's docstrings for
the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import marimekko

from _test_helpers import BG, _assert_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
