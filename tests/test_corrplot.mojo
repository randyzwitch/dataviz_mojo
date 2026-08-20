"""Tests for Mark.CORRPLOT: bubble size/color per correlation cell,
layout/diag filtering, encode_corrplot()'s own validation (raster +
SVG) -- see corrplot.mojo's own docstrings for the rules verified
here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import corrplot

from _test_helpers import BG, _assert_color


def test_render_corrplot_matches_hand_derived_bubbles() raises:
    # 2 variables ("A", "B"), matrix [[1, -0.5], [-0.5, 1]]. Canvas
    # 400x300, show_gridlines=False, show_legend=False: Mark.HEATMAP's
    # own _draw_grid_axis_frame (padding=0.0), 2 categories on each
    # axis over plot area x:[60,380], y:[20,250] -> cell width 160,
    # cell height 115. max bubble radius = min(160,115)/2*0.42 =
    # 57.5*0.42 = 24.15 -> 24 at |value|=1.0.
    #
    # Cell (A,A) [row 0, col 0, value 1.0]: center (140, 78), radius
    # 24, color exactly Theme's own color_scale_high (the domain's own
    # max). Cell (A,B) [row 0, col 1, value -0.5]: center (300, 78),
    # radius round(24.15*0.5)=12, color at t=0.25 through the [-1,1]
    # gradient -- (100,105,160), confirmed via a real render_svg() run
    # first (see this file's own SVG test), not re-derived from
    # ColorScale's own interpolation math again (already covered by
    # test_color_scale.mojo).
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var c = corrplot(vars, m, labels=False, theme=t, width=400, height=300)

    _assert_color(c, 140, 78, t.color_scale_high, "(A, A) = 1.0, the color domain's own max")
    _assert_color(c, 300, 78, Color(100, 105, 160), "(A, B) = -0.5, t=0.25 through the gradient")
    _assert_color(c, 140, 193, Color(100, 105, 160), "(B, A) = -0.5, symmetric with (A, B)")
    _assert_color(c, 300, 193, t.color_scale_high, "(B, B) = 1.0, the color domain's own max")
    _assert_color(c, 200, 78, BG, "between the two bubbles on row A -- no bubble reaches that far")


def test_render_corrplot_svg_matches_confirmed_circles() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_corrplot(labels=False).encode_corrplot(variables=vars, matrix=m).theme(
        Theme(show_gridlines=False, show_legend=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<circle cx="140" cy="78" r="24" fill="#dc5a28"/>' in s, "(A, A)")
    assert_true('<circle cx="300" cy="78" r="12" fill="#6469a0"/>' in s, "(A, B)")
    assert_true('<circle cx="140" cy="193" r="12" fill="#6469a0"/>' in s, "(B, A)")
    assert_true('<circle cx="300" cy="193" r="24" fill="#dc5a28"/>' in s, "(B, B)")


def test_render_corrplot_lower_layout_without_diag_keeps_only_below_diagonal() raises:
    # layout="lower" (row >= col), diag=False (row == col dropped
    # too) over a 2x2 matrix keeps exactly one cell: (B, A), row=1 >
    # col=0. (A,A)/( B,B) (the diagonal) and (A,B) (row < col, the
    # upper triangle) all stay background.
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, -0.5], [-0.5, 1.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var c = corrplot(vars, m, layout="lower", diag=False, labels=False, theme=t, width=400, height=300)

    _assert_color(c, 140, 78, BG, "(A, A) -- diagonal, dropped by diag=False")
    _assert_color(c, 300, 78, BG, "(A, B) -- upper triangle, dropped by layout=\"lower\"")
    _assert_color(c, 140, 193, Color(100, 105, 160), "(B, A) -- the one surviving cell")
    _assert_color(c, 300, 193, BG, "(B, B) -- diagonal, dropped by diag=False")


def test_render_corrplot_raises_on_non_square_matrix() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, 0.5], [0.5]]
    with assert_raises():
        _ = corrplot(vars, m, width=200, height=150)


def test_render_corrplot_raises_on_wrong_row_count() raises:
    var vars: List[String] = ["A", "B", "C"]
    var m: List[List[Float64]] = [[1.0, 0.5, 0.1], [0.5, 1.0, 0.2]]
    with assert_raises():
        _ = corrplot(vars, m, width=200, height=150)


def test_render_corrplot_raises_on_out_of_range_value() raises:
    var vars: List[String] = ["A", "B"]
    var m: List[List[Float64]] = [[1.0, 1.5], [1.5, 1.0]]
    with assert_raises():
        _ = corrplot(vars, m, width=200, height=150)


def test_render_corrplot_empty_variables_only_fills_background() raises:
    var vars = List[String]()
    var m = List[List[Float64]]()
    var c = corrplot(vars, m, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no variables: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
