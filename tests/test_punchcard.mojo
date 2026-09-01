"""Tests for Mark.PUNCHCARD: bubble radius = size/scale on a
categorical grid, independent bubbles for repeated (x, y) pairs,
encode_punchcard()'s validation (raster + SVG) -- see
punchcard.mojo's docstrings for the rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import punchcard

from _test_helpers import BG, _assert_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
