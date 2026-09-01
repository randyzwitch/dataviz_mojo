"""Tests for Mark.CORRPLOT: bubble size/color per correlation cell,
layout/diag filtering, encode_corrplot()'s validation (raster +
SVG) -- see corrplot.mojo's docstrings for the rules verified
here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import corrplot

from _test_helpers import BG, _assert_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
