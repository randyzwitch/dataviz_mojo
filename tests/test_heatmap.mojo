"""Tests for Mark.HEATMAP: one colored grid cell per (x, y) category
pair (raster + SVG) -- see heatmap.mojo's docstrings for the
grid-frame/color-scale rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import heatmap

from _test_helpers import BG, _assert_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
