"""Tests for Mark.LINE: drawing, line_smoothing (raster + SVG), and the
_build_line_path Catmull-Rom-to-Bezier helper it's built on -- split out
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


def test_render_line_mark_draws_ink_between_the_two_endpoints() raises:
    # A horizontal line from (0,0) to (10,0) -- constant y means the
    # y-domain has zero span, padded to [-1.0, 1.0], so y=0.0 maps to
    # the exact vertical midpoint of the plot area. The line's own
    # midpoint in x similarly lands at the plot area's horizontal
    # midpoint. Checked as "not background" (real ink is present),
    # not an exact color match -- stroke_path_aa's own coverage math
    # is already exhaustively tested in canvas itself; this only needs
    # to confirm Plot actually calls it, with a path that passes
    # through the expected point.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var plot = Plot().mark_line().encode(x=x, y=y)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var mid = c.get_pixel(220, 135)  # plot area's horizontal/vertical midpoint
    assert_true(mid.r != 255 or mid.g != 255 or mid.b != 255)


def test_build_line_path_zero_smoothing_is_a_plain_polyline() raises:
    # smoothing=0.0 must take the early "no curve math at all" branch,
    # not a degenerate curve formula -- confirmed directly by kind, not
    # just by the resulting shape: every command after the initial
    # move_to is a plain _LINE_TO, never _CUBIC_TO.
    var px: List[Float64] = [0.0, 10.0, 30.0, 50.0]
    var py: List[Float64] = [0.0, 20.0, 5.0, 25.0]
    var path = _build_line_path(px, py, 0.0)
    assert_equal(len(path.commands), 4)
    assert_equal(path.commands[0].kind, _MOVE_TO)
    for i in range(1, 4):
        assert_equal(path.commands[i].kind, _LINE_TO)
        assert_equal(path.commands[i].p1.x, px[i])
        assert_equal(path.commands[i].p1.y, py[i])


def test_build_line_path_full_smoothing_matches_hand_derived_control_points() raises:
    # The standard "uniform Catmull-Rom to Bezier" conversion (control
    # point = endpoint +/- (next-point minus previous-point)/6),
    # independently reimplemented in python3 with the exact same
    # operation order (so the resulting Float64s match bit-for-bit, not
    # just "close"), for 4 points with a real bend at each interior
    # point (endpoints clamp to a one-sided tangent, the conventional
    # open-curve rule).
    var px: List[Float64] = [0.0, 10.0, 30.0, 50.0]
    var py: List[Float64] = [0.0, 20.0, 5.0, 25.0]
    var path = _build_line_path(px, py, 1.0)
    assert_equal(len(path.commands), 4)
    assert_equal(path.commands[0].kind, _MOVE_TO)

    assert_equal(path.commands[1].kind, _CUBIC_TO)
    assert_equal(path.commands[1].p1.x, 1.6666666666666667)
    assert_equal(path.commands[1].p1.y, 3.3333333333333335)
    assert_equal(path.commands[1].p2.x, 5.0)
    assert_equal(path.commands[1].p2.y, 19.166666666666668)
    assert_equal(path.commands[1].p3.x, 10.0)
    assert_equal(path.commands[1].p3.y, 20.0)

    assert_equal(path.commands[2].kind, _CUBIC_TO)
    assert_equal(path.commands[2].p1.x, 15.0)
    assert_equal(path.commands[2].p1.y, 20.833333333333332)
    assert_equal(path.commands[2].p2.x, 23.333333333333332)
    assert_equal(path.commands[2].p2.y, 4.166666666666667)
    assert_equal(path.commands[2].p3.x, 30.0)
    assert_equal(path.commands[2].p3.y, 5.0)

    assert_equal(path.commands[3].kind, _CUBIC_TO)
    assert_equal(path.commands[3].p1.x, 36.666666666666664)
    assert_equal(path.commands[3].p1.y, 5.833333333333333)
    assert_equal(path.commands[3].p2.x, 46.666666666666664)
    assert_equal(path.commands[3].p2.y, 21.666666666666668)
    assert_equal(path.commands[3].p3.x, 50.0)
    assert_equal(path.commands[3].p3.y, 25.0)


def test_render_line_smoothing_default_matches_straight_line_output_exactly() raises:
    # line_smoothing's own default (0.0) must reproduce the exact
    # pre-existing straight-segment render byte-for-byte -- not just
    # "close", the same "purely additive" bar every other Theme field
    # added to this package has had to clear (see e.g. Theme.scale's
    # own equivalent test). A real 3-point line (a peak shape, not the
    # 2-point flat line the very first LINE test uses), compared
    # pixel-for-pixel across the whole canvas between Theme's own bare
    # default and an explicit Theme(line_smoothing=0.0).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var c_default = Canvas(400, 300, BG)
    render(c_default, Plot().mark_line().encode(x=x, y=y))
    var c_explicit = Canvas(400, 300, BG)
    render(c_explicit, Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=0.0)))

    for yy in range(c_default.height):
        for xx in range(c_default.width):
            var p_default = c_default.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_line_smoothing_bows_the_curve_away_from_the_straight_path() raises:
    # x=[0,10,20], y=[0,10,0] -- a symmetric peak, canvas 400x300,
    # default margins (plot area x:[60,380], y:[20,250]),
    # show_gridlines=False. The straight-line path's own first segment
    # runs from (74.545,239.545) to (220,30.455) -- its exact midpoint
    # is (147.27,135.0). A fully (1.0) smoothed Catmull-Rom curve
    # through the same three points bows well away from that point at
    # the same parameter: hand-derived via python3, the cubic Bezier's
    # own t=0.5 point lands at (138.18,121.93), about 13px away -- far
    # more than line_width=2.0 plus any AA fringe could reach. So
    # (147,135) is real ink under the straight line but background
    # under the fully smoothed one -- confirmed via a real render() run
    # first, not assumed from the hand-derived point alone.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var c_straight = Canvas(400, 300, BG)
    render(c_straight, Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=0.0, show_gridlines=False)))
    var c_smooth = Canvas(400, 300, BG)
    render(c_smooth, Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=1.0, show_gridlines=False)))

    var straight_p = c_straight.get_pixel(147, 135)
    var smooth_p = c_smooth.get_pixel(147, 135)
    assert_true(
        straight_p.r != BG.r or straight_p.g != BG.g or straight_p.b != BG.b,
        "the straight line passes through its own exact segment midpoint",
    )
    assert_equal(smooth_p.r, BG.r)
    assert_equal(smooth_p.g, BG.g)
    assert_equal(smooth_p.b, BG.b)


def test_render_svg_line_smoothing_matches_confirmed_cubic_path() raises:
    # Same x=[0,10,20], y=[0,10,0] peak as the raster test above --
    # every control-point coordinate independently derived via python3
    # from LinearScale's own slope/intercept formula composed with the
    # Catmull-Rom tangent formula, then cross-checked against a real
    # render_svg() run before being trusted here (the same discipline
    # every other exact-string SVG test in this file already follows).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=1.0, show_gridlines=False))
    render_svg(svg, plot)
    assert_true(
        '<path d="M74.545,239.545 C98.788,204.697 171.515,30.455 220.000,30.455'
        ' C268.485,30.455 341.212,204.697 365.455,239.545" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in svg.to_string(),
        "the fully-smoothed LINE mark's own two cubic segments",
    )


def test_render_line_raises_on_out_of_range_smoothing() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=-0.1)))
    with assert_raises():
        render(c, Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=1.1)))


def test_render_raises_when_color_encoding_used_with_line_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, color=color)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_svg_line_mark_matches_confirmed_path_coordinates() raises:
    # x=[0,10], y=[5,5] (horizontal, zero-span y padded to [4,6] the
    # same way test_render_line_mark_draws_ink_between_the_two_
    # endpoints' own data is) -- Path stores raw (unrounded) Float64
    # pixel coordinates, so unlike the point test above, this asserts
    # against values confirmed by directly running render_svg() once
    # first and reading its real output (not a hand-rolled formula
    # assumed to match LinearScale.to_pixel()'s own exact operation
    # order/rounding), then formatted through SvgCanvas's own
    # `_format_svg_float` (3 decimal places -- see that function's own
    # docstring for why raw `String(Float64)` isn't safe to assert
    # against here: it's what originally caught the 1-ULP cross-
    # context float discrepancy that motivated `_format_svg_float` to
    # exist at all).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_line().encode(x=x, y=y).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    assert_true(
        '<path d="M74.545,135.000 L365.455,135.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in svg.to_string(),
        "LINE mark's own stroked path, endpoints confirmed via a real render_svg() run",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
