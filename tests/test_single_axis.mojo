"""Tests for Mark.SINGLE_AXIS: one continuous axis, every point on a
fixed row (raster + SVG) -- see single_axis.mojo's docstrings for
the degenerate-y_scale trick verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import single_axis

from _test_helpers import BG, _assert_color


def test_render_single_axis_matches_hand_derived_points() raises:
    # 3 values (10, 20, 30). Canvas 400x300, show_gridlines=False,
    # default margins -> plot area x:[60,380], y:[20,250]. x-domain =
    # _data_extent([10,20,30]): span 20, 5% pad 1.0 -> [9, 31]; scale
    # = (380-60)/(31-9) = 14.5454. -> pixel x's 75/220/365 (each
    # independently computed via python3 from LinearScale's to_
    # pixel formula). Every point lands on the same row, the plot area's
    # vertical center: (20+250)/2 = 135 exactly. Default point_
    # radius 3.5 rounds to 4.
    var x: List[Float64] = [10.0, 20.0, 30.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = single_axis(x, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 75, 135, t.mark_color, "the first point (x=10)")
    _assert_color(c, 220, 135, t.mark_color, "the second point (x=20)")
    _assert_color(c, 365, 135, t.mark_color, "the third point (x=30)")
    _assert_color(c, 75, 100, BG, "same column as the first point, but off its row -- background")


def test_render_single_axis_svg_matches_confirmed_circles() raises:
    var x: List[Float64] = [10.0, 20.0, 30.0]
    var plot = Plot().mark_single_axis().encode_single_axis(x=x).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<circle cx="75" cy="135" r="4" fill="#1e64b4"/>' in s, "the first point")
    assert_true('<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s, "the second point")
    assert_true('<circle cx="365" cy="135" r="4" fill="#1e64b4"/>' in s, "the third point")


def test_render_single_axis_color_encoding_reuses_point_channels() raises:
    # Two points (x=0, x=10 -> pixel columns 75/365, the same _data_
    # extent math the first test confirms for a different pair
    # of values), colored by a continuous channel spanning the same
    # [0, 10] domain -- confirms Mark.POINT's _draw_point_layer
    # channel logic really is reused unchanged here, not just the
    # plain flat-color path.
    var x: List[Float64] = [0.0, 10.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = single_axis(x, color=color, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 75, 135, t.color_scale_low, "x=0, color=0.0 -- the color domain's min")
    _assert_color(c, 365, 135, t.color_scale_high, "x=10, color=10.0 -- the color domain's max")


def test_render_single_axis_raises_on_mismatched_channel_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var color: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted3 = single_axis(x, color=color, width=200, height=150)
        _ = render(_hoisted3)


def test_render_single_axis_empty_data_only_fills_background() raises:
    var x = List[Float64]()
    var _hoisted4 = single_axis(x, width=200, height=150)
    var c = render(_hoisted4)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
