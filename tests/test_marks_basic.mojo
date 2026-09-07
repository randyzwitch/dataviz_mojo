"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.POINT (centering, theme
colors, color/size encoding, categorical color, SVG coordinates),
Mark.LINE (drawing, line_smoothing, _build_line_path, step), Mark.AREA
(fill region, smoothing and step), Mark.BAR (rectangles, negative values,
color_by_sign), encode_histogram(), Mark.LOLLIPOP, Mark.BOX,
Mark.CANDLESTICK, Mark.WATERFALL, and Mark.BULLET, each raster + SVG.
"""

from _test_helpers import (
    BG,
    Lcg,
    _assert_color,
    _assert_near_color,
    _attr_values,
    _bbox_of_color,
    _count_color,
    _count_tag,
    _row_extent,
    _runs_in_row,
)
from canvas.color import Color
from canvas.path import Path, PathOp
from dataviz import (
    CORNFLOWERBLUE,
    StepStyle,
    area,
    bar,
    barbs,
    box,
    bullet,
    candlestick,
    contour,
    contourf,
    tricontour,
    tricontourf,
    triplot,
    tripcolor,
    line,
    lollipop,
    scatter,
    waterfall,
)
from dataviz.barbs import _barb_counts, _barb_glyph
from dataviz.continuous import _step_points
from dataviz.delaunay import _in_circumcircle, delaunay
from dataviz.tricontour import _tricontour_segments
from dataviz.triplot import _triangle_means, _triplot_edges
from dataviz.contour import (
    _append_above_region,
    _auto_levels,
    _chain_segments,
    _contour_segments,
)
from dataviz.color_ramp import ColorRamp
from dataviz.color_scale import ColorScale, default_categorical_palette
from dataviz.colors import BLACK, WHITE
from dataviz.scale import LinearScale
from dataviz.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
)
from dataviz.theme import Theme
from std.math import sqrt
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_point.mojo
# ---------------------------------------------------------------


def test_render_point_mark_centers_on_the_hand_derived_pixel() raises:
    # Single point (5.0, 5.0): zero domain span, so _data_extent pads
    # +/-1.0 to [4.0, 6.0] on both axes. Canvas 400x300 with default
    # margins (60/20/20/50) gives plot area x:[60,380], y:[20,250], so
    # x_scale.to_pixel(5.0) = 220 and y_scale.to_pixel(5.0) = 135, both
    # exact integers. point_radius 3.5 rounds to 4, so (220,135) is deep
    # inside the disk.
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var _hoisted1 = scatter(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var p = c.get_pixel(220, 135)
    var expected = Theme.default().mark_color
    assert_equal(p.r, expected.r)
    assert_equal(p.g, expected.g)
    assert_equal(p.b, expected.b)


def test_render_color_encoding_matches_hand_derived_colors() raises:
    # Two points at x=[0,10], y=[0,0] (zero-span y padded to [-1,1], so
    # y=0.0 maps to the vertical midpoint, 135). x-domain [0,10] pads to
    # [-0.5,10.5], landing the points at x=75 and x=365.
    #
    # color_data=[0.0,10.0] over a theme whose color_scale_low/high are
    # black/white (the same domain and stops the color-scale test uses), so
    # the two points must be exactly black and white. show_legend=False
    # keeps the continuous legend from shifting these positions; legend
    # layout is covered separately.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(
        color_scale_low=BLACK, color_scale_high=WHITE, show_legend=False
    )
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color=color)
        .theme(t)
        .size(400, 300)
    )
    var c = render(plot)

    var p0 = c.get_pixel(75, 135)
    assert_equal(p0.r, 0)
    assert_equal(p0.g, 0)
    assert_equal(p0.b, 0)

    var p1 = c.get_pixel(365, 135)
    assert_equal(p1.r, 255)
    assert_equal(p1.g, 255)
    assert_equal(p1.b, 255)


def test_render_size_encoding_matches_hand_derived_radii() raises:
    # Same positions (75,135)/(365,135). size_data=[0.0,100.0] over
    # size_range [2.0,10.0]: point 0 gets radius 2, point 1 radius 10.
    # Checked by coverage at increasing distance from each center: 3px from
    # the radius-2 point is background, 3px from the radius-10 point is
    # still the mark color. show_legend=False for the same reason as the
    # color test.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var size: List[Float64] = [0.0, 100.0]
    var t = Theme(
        size_range_min=2.0,
        size_range_max=10.0,
        show_gridlines=False,
        show_legend=False,
    )
    var plot = (
        Plot().mark_point().encode(x=x, y=y, size=size).theme(t).size(400, 300)
    )
    var c = render(plot)

    var mark_color = t.mark_color
    _assert_color(c, 75, 135, mark_color, "small point center")
    _assert_color(c, 78, 135, BG, "3px from small (radius 2) point -- outside")

    _assert_color(c, 365, 135, mark_color, "large point center")
    _assert_color(
        c,
        368,
        135,
        mark_color,
        "3px from large (radius 10) point -- still inside",
    )
    _assert_color(
        c, 376, 135, BG, "11px from large (radius 10) point -- outside"
    )


def test_render_categorical_color_matches_hand_derived_palette_entries() raises:
    # color_categories reserves a 130px legend column, so the plot area is
    # x:[60,250] and the same x domain lands the points at x=69/241.
    # color_categories = ["A","B"]: point 0 gets
    # default_categorical_palette()[0], point 1 gets [1].
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .size(400, 300)
    )
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 69, 135, palette[0], "category A -> palette[0]")
    _assert_color(c, 241, 135, palette[1], "category B -> palette[1]")


def test_render_svg_point_mark_matches_hand_derived_coordinates() raises:
    # The same single-(5.0, 5.0)-point setup as the raster test: (220,
    # 135), radius 4, through render_svg(). The center is Float64 now, so
    # it prints with SVG's three decimals -- this point lands on whole
    # pixels exactly, which is why the digits after the dot are zeros
    # rather than a value that could drift between float implementations.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).size(400, 300)
    var svg = render_svg(plot)
    assert_true(
        '<circle cx="220.000" cy="135.000" r="4.000" fill="#1e64b4"/>'
        in svg.to_string(),
        "encode()'s point, same pixel render() already hand-derives",
    )


# ---------------------------------------------------------------
# from tests/test_line.mojo
# ---------------------------------------------------------------


def test_render_line_mark_draws_ink_between_the_two_endpoints() raises:
    # A horizontal line from (0,0) to (10,0): zero-span y padded to
    # [-1.0, 1.0], so y=0.0 maps to the vertical midpoint, and the line's
    # x midpoint lands at the horizontal midpoint. Checked as "not
    # background", since stroke_path_aa's coverage math is tested in
    # canvas.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var _hoisted1 = line(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var mid = c.get_pixel(220, 135)  # plot area's horizontal/vertical midpoint
    assert_true(mid.r != 255 or mid.g != 255 or mid.b != 255)


def test_build_line_path_zero_smoothing_is_a_plain_polyline() raises:
    # smoothing=0.0 takes the early no-curve-math branch: every command
    # after move_to is PathOp.LINE_TO.
    var px: List[Float64] = [0.0, 10.0, 30.0, 50.0]
    var py: List[Float64] = [0.0, 20.0, 5.0, 25.0]
    var path = _build_line_path(px, py, 0.0)
    assert_equal(len(path.commands), 4)
    assert_equal(path.commands[0].op, PathOp.MOVE_TO)
    for i in range(1, 4):
        assert_equal(path.commands[i].op, PathOp.LINE_TO)
        assert_equal(path.commands[i].p1.x, px[i])
        assert_equal(path.commands[i].p1.y, py[i])


def test_build_line_path_full_smoothing_matches_hand_derived_control_points() raises:
    # The uniform Catmull-Rom to Bezier conversion (control point =
    # endpoint +/- (next - previous)/6), reimplemented in python3 for 4
    # points with a bend at each interior point; endpoints clamp to a
    # one-sided tangent. `Path.curve_through` (canvas_mojo v0.18.1)
    # divides then scales per component, the same order these
    # expectations were computed in, so this stays an exact comparison.
    var px: List[Float64] = [0.0, 10.0, 30.0, 50.0]
    var py: List[Float64] = [0.0, 20.0, 5.0, 25.0]
    var path = _build_line_path(px, py, 1.0)
    assert_equal(len(path.commands), 4)
    assert_equal(path.commands[0].op, PathOp.MOVE_TO)

    assert_equal(path.commands[1].op, PathOp.CUBIC_TO)
    assert_equal(path.commands[1].p1.x, 1.6666666666666667)
    assert_equal(path.commands[1].p1.y, 3.3333333333333335)
    assert_equal(path.commands[1].p2.x, 5.0)
    assert_equal(path.commands[1].p2.y, 19.166666666666668)
    assert_equal(path.commands[1].p3.x, 10.0)
    assert_equal(path.commands[1].p3.y, 20.0)

    assert_equal(path.commands[2].op, PathOp.CUBIC_TO)
    assert_equal(path.commands[2].p1.x, 15.0)
    assert_equal(path.commands[2].p1.y, 20.833333333333332)
    assert_equal(path.commands[2].p2.x, 23.333333333333332)
    assert_equal(path.commands[2].p2.y, 4.166666666666667)
    assert_equal(path.commands[2].p3.x, 30.0)
    assert_equal(path.commands[2].p3.y, 5.0)

    assert_equal(path.commands[3].op, PathOp.CUBIC_TO)
    assert_equal(path.commands[3].p1.x, 36.666666666666664)
    assert_equal(path.commands[3].p1.y, 5.833333333333333)
    assert_equal(path.commands[3].p2.x, 46.666666666666664)
    assert_equal(path.commands[3].p2.y, 21.666666666666668)
    assert_equal(path.commands[3].p3.x, 50.0)
    assert_equal(path.commands[3].p3.y, 25.0)


def test_render_line_smoothing_default_matches_straight_line_output_exactly() raises:
    # line_smoothing's default (0.0) must reproduce the straight-segment
    # render byte-for-byte. A 3-point peak, compared pixel-for-pixel
    # between Theme's default and an explicit Theme(line_smoothing=0.0).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var _hoisted2 = line(x, y, width=400, height=300)
    var c_default = render(_hoisted2)
    var _hoisted3 = line(
        x, y, theme=Theme(line_smoothing=0.0), width=400, height=300
    )
    var c_explicit = render(_hoisted3)

    for yy in range(c_default.height):
        for xx in range(c_default.width):
            var p_default = c_default.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_line_smoothing_bows_the_curve_away_from_the_straight_path() raises:
    # x=[0,10,20], y=[0,10,0], canvas 400x300, default margins (plot area
    # x:[60,380], y:[20,250]), no gridlines. The straight path's first
    # segment runs (74.545,239.545) to (220,30.455), midpoint
    # (147.27,135.0). The fully smoothed curve's t=0.5 point lands at
    # (138.18,121.93), about 13px away, far more than line_width plus AA
    # reaches, so (147,135) is ink under the straight line and background
    # under the smoothed one.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var _hoisted4 = line(
        x,
        y,
        theme=Theme(line_smoothing=0.0, show_gridlines=False),
        width=400,
        height=300,
    )
    var c_straight = render(_hoisted4)
    var _hoisted5 = line(
        x,
        y,
        theme=Theme(line_smoothing=1.0, show_gridlines=False),
        width=400,
        height=300,
    )
    var c_smooth = render(_hoisted5)

    var straight_p = c_straight.get_pixel(147, 135)
    var smooth_p = c_smooth.get_pixel(147, 135)
    assert_true(
        straight_p.r != BG.r or straight_p.g != BG.g or straight_p.b != BG.b,
        "the straight line passes through its exact segment midpoint",
    )
    assert_equal(smooth_p.r, BG.r)
    assert_equal(smooth_p.g, BG.g)
    assert_equal(smooth_p.b, BG.b)


def test_render_svg_line_smoothing_matches_confirmed_cubic_path() raises:
    # Same peak as the raster test; every control point derived from
    # LinearScale's slope/intercept composed with the Catmull-Rom tangent
    # formula.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .theme(Theme(line_smoothing=1.0, show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,239.545 C98.788,204.697 171.515,30.455 220.000,30.455'
        ' C268.485,30.455 341.212,204.697 365.455,239.545" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in svg.to_string(),
        "the fully-smoothed LINE mark's two cubic segments",
    )


def test_render_line_raises_on_out_of_range_smoothing() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    with assert_raises():
        var _hoisted6 = line(
            x, y, theme=Theme(line_smoothing=-0.1), width=200, height=150
        )
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = line(
            x, y, theme=Theme(line_smoothing=1.1), width=200, height=150
        )
        _ = render(_hoisted7)


def test_render_raises_when_color_encoding_used_with_line_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, color=color).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_render_svg_line_mark_matches_confirmed_path_coordinates() raises:
    # x=[0,10], y=[5,5] (zero-span y padded to [4,6]): Path stores raw
    # Float64 pixel coordinates, formatted through SvgCanvas's
    # `_format_svg_float` (3 decimals).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,135.000 L365.455,135.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in svg.to_string(),
        "LINE mark's stroked path",
    )


# ---------------------------------------------------------------
# Mark.LINE's step (stairs) interpolation, #336
#
# The pixel coordinates every assertion below uses come from one
# projection, derived once here and reused:
#
#   x=[0,10,20] pads 5% of its span to [-1,21]; the 400x300 canvas's
#   default margins (60/20/20/50) give a plot area x:[60,380], so
#   to_pixel(x) = 60 + 320*(x+1)/22 -> 74.545, 220.000, 365.455.
#   y=[5,9,7] pads to [4.8,9.2] over y:[20,250] inverted, so
#   to_pixel(y) = 250 - 230*(y-4.8)/4.4 -> 239.545, 30.455, 135.000.
#
# The three styles draw the same three y values at the same three x
# values; only the order the path visits them in differs, which is the
# whole content of StepStyle.
# ---------------------------------------------------------------


def test_step_points_matches_matplotlibs_own_step_expansion() raises:
    # The oracle is matplotlib's cbook.pts_to_prestep/pts_to_midstep/
    # pts_to_poststep, run on this same x/y in a scratch environment
    # (matplotlib 3.x). Its output, pasted verbatim:
    #
    #   PRE  [(0,0), (0,20), (10,20), (10,5), (30,5)]
    #   MID  [(0,0), (5,0), (5,20), (20,20), (20,5), (30,5)]
    #   POST [(0,0), (10,0), (10,20), (30,20), (30,5)]
    #
    # Point counts included: MID's 6 (2n) against PRE/POST's 5 (2n-1)
    # is not an off-by-one, it is MID needing a closing plateau the
    # other two get for free from the last sample.
    var px: List[Float64] = [0.0, 10.0, 30.0]
    var py: List[Float64] = [0.0, 20.0, 5.0]

    var pre = _step_points(px, py, StepStyle.PRE)
    var pre_x: List[Float64] = [0.0, 0.0, 10.0, 10.0, 30.0]
    var pre_y: List[Float64] = [0.0, 20.0, 20.0, 5.0, 5.0]
    assert_equal(len(pre.px), len(pre_x), "PRE point count")
    for i in range(len(pre_x)):
        assert_equal(pre.px[i], pre_x[i], "PRE x[" + String(i) + "]")
        assert_equal(pre.py[i], pre_y[i], "PRE y[" + String(i) + "]")

    var mid = _step_points(px, py, StepStyle.MID)
    var mid_x: List[Float64] = [0.0, 5.0, 5.0, 20.0, 20.0, 30.0]
    var mid_y: List[Float64] = [0.0, 0.0, 20.0, 20.0, 5.0, 5.0]
    assert_equal(len(mid.px), len(mid_x), "MID point count")
    for i in range(len(mid_x)):
        assert_equal(mid.px[i], mid_x[i], "MID x[" + String(i) + "]")
        assert_equal(mid.py[i], mid_y[i], "MID y[" + String(i) + "]")

    var post = _step_points(px, py, StepStyle.POST)
    var post_x: List[Float64] = [0.0, 10.0, 10.0, 30.0, 30.0]
    var post_y: List[Float64] = [0.0, 0.0, 20.0, 20.0, 5.0]
    assert_equal(len(post.px), len(post_x), "POST point count")
    for i in range(len(post_x)):
        assert_equal(post.px[i], post_x[i], "POST x[" + String(i) + "]")
        assert_equal(post.py[i], post_y[i], "POST y[" + String(i) + "]")


def test_step_points_duplicates_a_repeated_x_the_way_matplotlib_does() raises:
    # #405. Two consecutive samples sharing an x make PRE emit the same
    # point twice, and POST does the same when two consecutive samples
    # share a y. matplotlib does both, so this is the oracle match
    # holding rather than a defect, and this test exists to keep a
    # future "cleanup" from silently breaking it.
    #
    # Oracle: matplotlib 3.11.1, cbook.pts_to_prestep/pts_to_midstep/
    # pts_to_poststep, pasted verbatim.
    #
    #   x = [0, 100, 100, 200], y = [10, 40, 20, 30]
    #   PRE  n=7  (0,10) (0,40) (100,40) (100,20) (100,20) (100,30) (200,30)
    #   MID  n=8  (0,10) (50,10) (50,40) (100,40) (100,20) (150,20)
    #             (150,30) (200,30)
    #   POST n=7  (0,10) (100,10) (100,40) (100,40) (100,20) (200,20) (200,30)
    #
    # The point *counts* are what discriminate: dropping the duplicate
    # takes PRE and POST to 6, which is neither 2n-1 nor anything
    # matplotlib produces. The pairwise-equality assertions below name
    # the duplicated index directly, so a dedup fails on the count and
    # again on the pair.
    var px: List[Float64] = [0.0, 100.0, 100.0, 200.0]
    var py: List[Float64] = [10.0, 40.0, 20.0, 30.0]

    var pre = _step_points(px, py, StepStyle.PRE)
    var pre_x: List[Float64] = [0.0, 0.0, 100.0, 100.0, 100.0, 100.0, 200.0]
    var pre_y: List[Float64] = [10.0, 40.0, 40.0, 20.0, 20.0, 30.0, 30.0]
    assert_equal(len(pre.px), len(pre_x), "PRE keeps matplotlib's 2n-1 points")
    for i in range(len(pre_x)):
        assert_equal(pre.px[i], pre_x[i], "PRE x[" + String(i) + "]")
        assert_equal(pre.py[i], pre_y[i], "PRE y[" + String(i) + "]")
    assert_equal(pre.px[3], pre.px[4], "PRE's duplicated point, x")
    assert_equal(pre.py[3], pre.py[4], "PRE's duplicated point, y")

    var mid = _step_points(px, py, StepStyle.MID)
    var mid_x: List[Float64] = [
        0.0,
        50.0,
        50.0,
        100.0,
        100.0,
        150.0,
        150.0,
        200.0,
    ]
    var mid_y: List[Float64] = [10.0, 10.0, 40.0, 40.0, 20.0, 20.0, 30.0, 30.0]
    assert_equal(len(mid.px), len(mid_x), "MID keeps matplotlib's 2n points")
    for i in range(len(mid_x)):
        assert_equal(mid.px[i], mid_x[i], "MID x[" + String(i) + "]")
        assert_equal(mid.py[i], mid_y[i], "MID y[" + String(i) + "]")
    # MID is the control: the midpoint of two equal x is that x, but the
    # two points emitted there carry different y, so nothing repeats.
    # A dedup would leave this style untouched, which is why asserting
    # it here separates "matched matplotlib" from "emitted 2n points".
    for i in range(1, len(mid.px)):
        assert_true(
            mid.px[i] != mid.px[i - 1] or mid.py[i] != mid.py[i - 1],
            "MID emits no duplicate at index " + String(i),
        )

    var post = _step_points(px, py, StepStyle.POST)
    var post_x: List[Float64] = [0.0, 100.0, 100.0, 100.0, 100.0, 200.0, 200.0]
    var post_y: List[Float64] = [10.0, 10.0, 40.0, 40.0, 20.0, 20.0, 30.0]
    assert_equal(
        len(post.px), len(post_x), "POST keeps matplotlib's 2n-1 points"
    )
    for i in range(len(post_x)):
        assert_equal(post.px[i], post_x[i], "POST x[" + String(i) + "]")
        assert_equal(post.py[i], post_y[i], "POST y[" + String(i) + "]")
    assert_equal(post.px[2], post.px[3], "POST's duplicated point, x")
    assert_equal(post.py[2], post.py[3], "POST's duplicated point, y")


def test_step_points_duplicates_a_repeated_y_the_way_matplotlib_does() raises:
    # The other degenerate step, and the more common one: two
    # consecutive samples sharing a y collapse the riser. #405 names
    # this only for POST, but it hits all three styles -- PRE's
    # (x[i], y[i+1]) repeats the point before it, POST's two emissions
    # at x[i+1] become one, and MID's two at the midpoint likewise. A
    # held reading is the exact shape a step chart is drawn for, so
    # this is not an exotic input.
    #
    # Oracle: matplotlib 3.11.1, x = [0, 100, 200], y = [10, 10, 30],
    # pasted verbatim:
    #
    #   PRE  n=5  (0,10) (0,10) (100,10) (100,30) (200,30)
    #   MID  n=6  (0,10) (50,10) (50,10) (150,10) (150,30) (200,30)
    #   POST n=5  (0,10) (100,10) (100,10) (200,10) (200,30)
    #
    # The control is the same series with no repeated y, at the bottom:
    # it must produce no duplicate at all, which is what separates
    # "matched matplotlib" from "emits duplicates everywhere".
    var px: List[Float64] = [0.0, 100.0, 200.0]
    var py: List[Float64] = [10.0, 10.0, 30.0]

    var pre = _step_points(px, py, StepStyle.PRE)
    var pre_x: List[Float64] = [0.0, 0.0, 100.0, 100.0, 200.0]
    var pre_y: List[Float64] = [10.0, 10.0, 10.0, 30.0, 30.0]
    assert_equal(len(pre.px), len(pre_x), "PRE keeps matplotlib's 5 points")
    for i in range(len(pre_x)):
        assert_equal(pre.px[i], pre_x[i], "PRE x[" + String(i) + "]")
        assert_equal(pre.py[i], pre_y[i], "PRE y[" + String(i) + "]")
    assert_equal(pre.px[0], pre.px[1], "PRE's duplicated point, x")
    assert_equal(pre.py[0], pre.py[1], "PRE's duplicated point, y")

    var mid = _step_points(px, py, StepStyle.MID)
    var mid_x: List[Float64] = [0.0, 50.0, 50.0, 150.0, 150.0, 200.0]
    var mid_y: List[Float64] = [10.0, 10.0, 10.0, 10.0, 30.0, 30.0]
    assert_equal(len(mid.px), len(mid_x), "MID keeps matplotlib's 6 points")
    for i in range(len(mid_x)):
        assert_equal(mid.px[i], mid_x[i], "MID x[" + String(i) + "]")
        assert_equal(mid.py[i], mid_y[i], "MID y[" + String(i) + "]")
    assert_equal(mid.px[1], mid.px[2], "MID's duplicated point, x")
    assert_equal(mid.py[1], mid.py[2], "MID's duplicated point, y")

    var post = _step_points(px, py, StepStyle.POST)
    var post_x: List[Float64] = [0.0, 100.0, 100.0, 200.0, 200.0]
    var post_y: List[Float64] = [10.0, 10.0, 10.0, 10.0, 30.0]
    assert_equal(len(post.px), len(post_x), "POST keeps matplotlib's 5 points")
    for i in range(len(post_x)):
        assert_equal(post.px[i], post_x[i], "POST x[" + String(i) + "]")
        assert_equal(post.py[i], post_y[i], "POST y[" + String(i) + "]")
    assert_equal(post.px[1], post.px[2], "POST's duplicated point, x")
    assert_equal(post.py[1], post.py[2], "POST's duplicated point, y")

    # The control: same x, no two consecutive y equal. matplotlib
    # reports no duplicate in any style here, so neither may this.
    var cy: List[Float64] = [10.0, 40.0, 30.0]
    for style in [StepStyle.PRE, StepStyle.MID, StepStyle.POST]:
        var clean = _step_points(px, cy, style)
        for i in range(1, len(clean.px)):
            assert_true(
                clean.px[i] != clean.px[i - 1]
                or clean.py[i] != clean.py[i - 1],
                "a non-degenerate series duplicates nothing, at index "
                + String(i),
            )


def test_a_repeated_x_reaches_the_rendered_step_path_as_a_repeated_command() raises:
    # The end-to-end half of #405: the duplicate is not swallowed
    # between _step_points and the emitted `d`. _decimate_to_pixel_columns
    # keeps a column's min and max y, which for a duplicated sample are
    # the same point twice, so it collapses nothing here.
    #
    # Asserted on the substring "L120.000,61.905 L120.000,61.905" rather
    # than on a point count, because that is the artifact a reader of
    # the SVG actually sees, and it is what #405 quoted. The values come
    # from a real render_svg() of this plot, not from the projection
    # arithmetic repeated here.
    var x: List[Float64] = [0.0, 1.0, 1.0, 2.0]
    var y: List[Float64] = [1.0, 4.0, 2.0, 3.0]
    var svg = render_svg(
        area(x, y, step=StepStyle.PRE, width=200, height=150)
    ).to_string()
    assert_true(
        "L120.000,61.905 L120.000,61.905" in svg,
        "PRE's repeated x reaches the path as two identical commands",
    )

    var svg_post = render_svg(
        area(x, y, step=StepStyle.POST, width=200, height=150)
    ).to_string()
    assert_true(
        "L120.000,23.810 L120.000,23.810" in svg_post,
        "POST's collision reaches the path as two identical commands",
    )

    # MID over the same samples emits no repeat, which is what makes the
    # two assertions above about PRE/POST specifically and not about the
    # path writer.
    var svg_mid = render_svg(
        area(x, y, step=StepStyle.MID, width=200, height=150)
    ).to_string()
    assert_true(
        "L120.000,61.905 L120.000,61.905" not in svg_mid
        and "L120.000,23.810 L120.000,23.810" not in svg_mid,
        "MID's path has no repeated command over the same samples",
    )


def test_step_points_passes_through_none_and_a_one_point_series() raises:
    # NONE is the default every existing caller passes, so it has to be
    # a pure pass-through, not "the same shape by coincidence". A
    # one-point series has no pair to put a riser between and is
    # returned as-is whatever the style.
    var px: List[Float64] = [0.0, 10.0, 30.0]
    var py: List[Float64] = [0.0, 20.0, 5.0]
    var none = _step_points(px, py, StepStyle.NONE)
    assert_equal(len(none.px), 3, "NONE keeps the point count")
    for i in range(3):
        assert_equal(none.px[i], px[i])
        assert_equal(none.py[i], py[i])

    var one_x: List[Float64] = [4.0]
    var one_y: List[Float64] = [7.0]
    var single = _step_points(one_x, one_y, StepStyle.POST)
    assert_equal(len(single.px), 1, "a single point has nothing to step")
    assert_equal(single.px[0], 4.0)
    assert_equal(single.py[0], 7.0)


def test_render_svg_line_step_post_matches_confirmed_path() raises:
    # POST holds each y until the next sample's x: flat at 239.545 out
    # to 220, riser there, flat at 30.455 out to 365.455, riser there.
    # The final sample (365.455, 135.000) is a bare riser with no
    # plateau after it, which is what steps-post means at the last
    # point -- matplotlib draws it the same way.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [5.0, 9.0, 7.0]
    var plot = (
        Plot()
        .mark_line(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,239.545 L220.000,239.545 L220.000,30.455'
        ' L365.455,30.455 L365.455,135.000" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in svg.to_string(),
        "StepStyle.POST's staircase",
    )


def test_render_svg_line_step_pre_matches_confirmed_path() raises:
    # PRE is POST's mirror: the riser comes first, at the earlier x, so
    # the bare riser lands at the start (74.545) instead of the end.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [5.0, 9.0, 7.0]
    var plot = (
        Plot()
        .mark_line(step=StepStyle.PRE)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,239.545 L74.545,30.455 L220.000,30.455'
        ' L220.000,135.000 L365.455,135.000" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in svg.to_string(),
        "StepStyle.PRE's staircase",
    )


def test_render_svg_line_step_mid_matches_confirmed_path() raises:
    # MID's risers sit at the pixel midpoints (74.545+220)/2 = 147.273
    # and (220+365.455)/2 = 292.727, and the path needs one extra
    # vertex over PRE/POST to close the last plateau at 365.455. Every
    # sample keeps a plateau centered on it, which is the property MID
    # exists for.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [5.0, 9.0, 7.0]
    var plot = (
        Plot()
        .mark_line(step=StepStyle.MID)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,239.545 L147.273,239.545 L147.273,30.455'
        ' L292.727,30.455 L292.727,135.000 L365.455,135.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in svg.to_string(),
        "StepStyle.MID's staircase",
    )


def test_render_line_step_holds_the_value_where_a_straight_line_sags() raises:
    # The raster counterpart of the POST path test, at x=293 -- inside
    # the plateau that runs from 220 to 365.455 at y=30.455, and inside
    # the diagonal a plain line draws from (220,30.455) down to
    # (365.455,135.000), which passes y=83 there.
    #
    # Both probes are stroke interiors, not edges: a 2px-wide
    # horizontal stroke centered on 30.455 covers row 30 completely, so
    # the downsampled pixel is the exact mark color rather than a
    # blend. Measured from a real render at both pixels in both modes
    # before being written down.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [5.0, 9.0, 7.0]
    var t = Theme(show_gridlines=False)
    var stepped = (
        Plot()
        .mark_line(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(t)
        .size(400, 300)
    )
    var straight = Plot().mark_line().encode(x=x, y=y).theme(t).size(400, 300)
    var c_step = render(stepped)
    var c_straight = render(straight)

    _assert_color(c_step, 293, 30, t.mark_color, "POST's plateau at y=30.455")
    _assert_color(c_straight, 293, 30, BG, "no plateau without a step")
    _assert_color(c_step, 293, 83, BG, "POST never crosses the diagonal")
    var diag = c_straight.get_pixel(293, 83)
    assert_true(
        diag.r != BG.r or diag.g != BG.g or diag.b != BG.b,
        "the straight line does pass through (293, 83)",
    )


def test_render_line_step_raises_when_combined_with_line_smoothing() raises:
    # The two are mutually exclusive: a smoothed staircase rounds off
    # the corners that carry its meaning, and a riser's two points
    # share an x, so a Catmull-Rom tangent through them is horizontal
    # and bows the curve sideways past the samples.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [5.0, 9.0, 7.0]
    with assert_raises(
        contains=(
            "Theme.line_smoothing and Plot.mark_line(step=...) are mutually"
            " exclusive"
        )
    ):
        var plot = (
            Plot()
            .mark_line(step=StepStyle.MID)
            .encode(x=x, y=y)
            .theme(Theme(line_smoothing=0.5))
            .size(200, 150)
        )
        _ = render_svg(plot)
    # Smoothing with the default StepStyle.NONE is still fine.
    var ok = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .theme(Theme(line_smoothing=0.5))
        .size(200, 150)
    )
    _ = render_svg(ok)


def test_render_line_step_keeps_at_most_two_points_per_pixel_column() raises:
    # _decimate_to_pixel_columns exists to cap a dense series at two
    # points per horizontal pixel column, and _draw_line_layer steps
    # *before* decimating so that cap applies to the staircase that is
    # actually drawn. Decimating first and stepping afterwards would
    # expand each surviving point back into a plateau and a riser --
    # up to four points per column, roughly undoing the thinning
    # (measured on a 5000-sample series: 2241 points that way against
    # 1121 this way).
    #
    # 5000 samples over a 640-wide canvas' ~560px plot area is ~9 per
    # column, well past the `n > 2 * columns` threshold. y cycles
    # through 17 values so a column's samples really do differ and
    # decimation has a min and a max to choose.
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(5000):
        x.append(Float64(i))
        y.append(Float64(i % 17))
    var plot = (
        Plot()
        .mark_line(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(640, 420)
    )
    var paths = _attr_values(render_svg(plot).to_string(), "path", "d")
    assert_equal(len(paths), 1, "one stroked path for the line")

    var tokens = paths[0].split(" ")
    assert_true(
        len(tokens) < 5000,
        (
            "decimation ran at all (kept "
            + String(len(tokens))
            + " of 9999 stepped points)"
        ),
    )

    # Counted as a total against the span rather than per column: the
    # `d` attribute carries three decimals, so a point at 375.9996
    # prints as "376.000" and would be filed under the wrong column by
    # a per-column tally. The total is immune to that -- each true
    # column contributes at most two points however they round -- and
    # still separates the two orderings by a factor of two. The +2
    # absorbs the same rounding at the two ends of the span.
    var lo_col = 1 << 30
    var hi_col = -1
    for token in tokens:
        # "M74.545,239.545" / "L220.000,239.545" -- drop the command
        # letter, keep the integer part of x.
        var comma = token.find(",")
        var xs = String(token[byte=1:comma])
        var dot = xs.find(".")
        var col = Int(String(xs[byte=0:dot]) if dot != -1 else xs)
        if col < lo_col:
            lo_col = col
        if col > hi_col:
            hi_col = col
    var columns = hi_col - lo_col + 1
    assert_true(
        len(tokens) <= 2 * columns + 2,
        (
            "the drawn staircase has "
            + String(len(tokens))
            + " points over "
            + String(columns)
            + " pixel columns; decimation caps it at two per column"
        ),
    )


def test_render_svg_line_step_survives_decimation_of_a_long_series() raises:
    # 1600 samples crammed into x=[0,1] trip decimation for the whole
    # series (1604 points over ~321 pixel columns, well past
    # `n > 2 * columns`), while the four samples at x=2..5 sit alone in
    # their own columns. Their plateaus must come through untouched:
    # decimation is a rendering optimization, and a step that lost a
    # riser to it would be showing data that was never measured.
    #
    # Derived from the same projection rules as the tests above.
    # x=[0,5] pads to [-0.25,5.25], so to_pixel(2..5) = 190.909,
    # 249.091, 307.273, 365.455; y=[2,9] pads to [1.65,9.35], so
    # to_pixel(8,2,9,3) = 60.325, 239.545, 30.455, 209.675.
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(1600):
        x.append(Float64(i) / 1599.0)
        y.append(4.0 + Float64(i % 7) * 0.1)
    var sparse_x: List[Float64] = [2.0, 3.0, 4.0, 5.0]
    var sparse_y: List[Float64] = [8.0, 2.0, 9.0, 3.0]
    for i in range(len(sparse_x)):
        x.append(sparse_x[i])
        y.append(sparse_y[i])
    var plot = (
        Plot()
        .mark_line(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    assert_true(
        "L190.909,60.325 L249.091,60.325 L249.091,239.545"
        " L307.273,239.545 L307.273,30.455 L365.455,30.455"
        ' L365.455,209.675" fill="none"'
        in svg,
        "the sparse samples' plateaus and risers, intact after decimation",
    )


def test_line_one_call_step_matches_the_builder() raises:
    # line(step=...) has to be the same chart Plot().mark_line(step=...)
    # builds, not a second implementation of it.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [5.0, 9.0, 7.0]
    var t = Theme(show_gridlines=False)
    var one_call = line(
        x, y, step=StepStyle.MID, theme=t, width=400, height=300
    )
    var built = (
        Plot()
        .mark_line(step=StepStyle.MID)
        .encode(x=x, y=y)
        .theme(t)
        .size(400, 300)
    )
    assert_equal(
        render_svg(one_call).to_string(), render_svg(built).to_string()
    )


# ---------------------------------------------------------------
# from tests/test_area.mojo
# ---------------------------------------------------------------


def test_render_area_mark_matches_hand_derived_fill_region() raises:
    # x=[0,10], y=[0,10] on 400x300, default margins (plot area x:[60,380],
    # y:[20,250]). x lands at pixel 75/365. _zero_baseline_y_extent([0,10])
    # pads only the non-zero end to [0,10.5]: baseline y=250, top-right
    # point y=31, so the fill runs from (75,250) up to (365,31). The top
    # edge at x=220 sits at y=140.5: y=200 must be filled, y=50 background.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = area(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 200, t.mark_color, "inside the filled area")
    _assert_color(c, 220, 50, BG, "above the area's top edge -- background")


def test_render_svg_area_smoothing_matches_hand_derived_curve() raises:
    # x=[0,10,20], y=[2,10,4] (a peak not touching zero, so the closing
    # line_to()s aren't degenerate). Canvas 400x300, default margins, no
    # gridlines. _zero_baseline_y_extent gives [0, 10.5]. Only the top
    # edge is smoothed; the closing segments to the baseline
    # (to_pixel(0.0)=250) stay straight, and since that baseline sits on
    # the axis line it is pulled to 249 first (see _pull_off_axis_line).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var plot = (
        Plot()
        .mark_area()
        .encode(x=x, y=y)
        .theme(Theme(line_smoothing=1.0, show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,206.190 C98.788,176.984 171.515,38.254 220.000,30.952'
        " C268.485,23.651 341.212,140.476 365.455,162.381 L365.455,249.000"
        ' L74.545,249.000 Z" fill="#1e64b4"/>'
        in svg.to_string(),
        (
            "the smoothed top edge, then two straight line_to()s down to"
            " baseline, closed"
        ),
    )


def test_render_area_smoothing_default_matches_straight_output_exactly() raises:
    # line_smoothing's default (0.0) must reproduce the straight-edged
    # Mark.AREA render byte-for-byte.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var _hoisted2 = area(x, y, width=400, height=300)
    var c_default = render(_hoisted2)
    var _hoisted3 = area(
        x, y, theme=Theme(line_smoothing=0.0), width=400, height=300
    )
    var c_explicit = render(_hoisted3)

    for yy in range(c_default.height):
        for xx in range(c_default.width):
            var p_default = c_default.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_area_raises_on_out_of_range_smoothing() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    with assert_raises():
        var _hoisted4 = area(
            x, y, theme=Theme(line_smoothing=-0.1), width=200, height=150
        )
        _ = render(_hoisted4)
    with assert_raises():
        var _hoisted5 = area(
            x, y, theme=Theme(line_smoothing=1.1), width=200, height=150
        )
        _ = render(_hoisted5)


# ---------------------------------------------------------------
# Mark.AREA's step (stairs) interpolation, #384
#
# One projection backs every assertion below, the same one
# test_render_svg_area_smoothing_matches_hand_derived_curve uses:
#
#   x=[0,10,20] pads 5% of its span to [-1,21]; the 400x300 canvas's
#   default margins (60/20/20/50) give a plot area x:[60,380], so
#   to_pixel(x) = 60 + 320*(x+1)/22 -> 74.545, 220.000, 365.455.
#   y=[2,10,4] goes through _zero_baseline_y_extent, which forces zero
#   into the domain and pads only the far end, giving [0,10.5] over
#   y:[20,250] inverted: to_pixel(y) = 250 - 230*y/10.5 -> 206.190,
#   30.952, 162.381, and to_pixel(0) = 250, pulled to 249 because it
#   lands on the axis line (_pull_off_axis_line).
#
# The peak at y=10 never touches zero, so the two closing segments are
# real geometry rather than degenerate -- which is the point: they must
# come through a step unchanged.
# ---------------------------------------------------------------


def test_render_svg_area_step_post_matches_confirmed_path() raises:
    # POST holds each y until the next sample's x, so the top edge is
    # flat at 206.190 out to 220, riser, flat at 30.952 out to 365.455,
    # riser down to 162.381. Then the two closing line_to()s -- down to
    # the baseline at the last x, back along it to the first -- exactly
    # the pair the unstepped and the smoothed renders both end with.
    #
    # The last riser and the closing drop are both at x=365.455, so
    # they read as one vertical run in the `d`: that is the closing
    # segment meeting the staircase's end head-on, with no sliver of
    # fill left over and no crossing back over itself.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var plot = (
        Plot()
        .mark_area(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    assert_true(
        '<path d="M74.545,206.190 L220.000,206.190 L220.000,30.952'
        " L365.455,30.952 L365.455,162.381 L365.455,249.000"
        ' L74.545,249.000 Z" fill="#1e64b4"/>'
        in render_svg(plot).to_string(),
        "StepStyle.POST's staircase, closed down to the baseline",
    )


def test_render_svg_area_step_pre_matches_confirmed_path() raises:
    # PRE's mirror of the above: the riser comes at the earlier x, so
    # the bare riser is the first segment, at 74.545 -- and it shares
    # that x with the closing segment back up from the baseline, which
    # is what "no sliver at the ends" looks like on the left.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var plot = (
        Plot()
        .mark_area(step=StepStyle.PRE)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    assert_true(
        '<path d="M74.545,206.190 L74.545,30.952 L220.000,30.952'
        " L220.000,162.381 L365.455,162.381 L365.455,249.000"
        ' L74.545,249.000 Z" fill="#1e64b4"/>'
        in render_svg(plot).to_string(),
        "StepStyle.PRE's staircase, closed down to the baseline",
    )


def test_render_svg_area_step_mid_matches_confirmed_path() raises:
    # MID's risers sit at the pixel midpoints (74.545+220)/2 = 147.273
    # and (220+365.455)/2 = 292.727, leaving each sample a plateau
    # centered on it and half-width plateaus at the two ends. The
    # closing pair is unchanged again: MID keeps the first and last x,
    # so the fill still meets the baseline directly under the outermost
    # samples rather than under a midpoint.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var plot = (
        Plot()
        .mark_area(step=StepStyle.MID)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    assert_true(
        '<path d="M74.545,206.190 L147.273,206.190 L147.273,30.952'
        " L292.727,30.952 L292.727,162.381 L365.455,162.381"
        ' L365.455,249.000 L74.545,249.000 Z" fill="#1e64b4"/>'
        in render_svg(plot).to_string(),
        "StepStyle.MID's staircase, closed down to the baseline",
    )


def test_render_area_step_fills_the_plateau_and_not_the_diagonal() raises:
    # The raster counterpart. Every probe below is a fill interior --
    # tens of pixels from the nearest edge in every direction, so the
    # downsampled pixel is the exact mark color or the exact background
    # rather than a blend -- and every one of them was measured on a
    # real render of all four styles before being written down.
    #
    # The probes are chosen to discriminate, which for a fill means each
    # one has to separate two styles that disagree there, not merely sit
    # inside the shape:
    #
    #   (100, 60)  NONE background, PRE filled.  The unstepped top edge
    #              passes y=175.5 at x=100, so this is 115px of clear
    #              air above it; PRE's first plateau is already up at
    #              30.952. Separates PRE from NONE *and* from MID/POST,
    #              whose first plateau is the low one at 206.190.
    #   (180, 60)  NONE background (its edge is at 79.1 there), MID and
    #              PRE filled, POST background. This is the probe that
    #              catches a step that was ignored entirely.
    #   (200, 60)  NONE filled (edge at 55.0), POST background. The one
    #              that runs the other way: POST *removes* fill the
    #              straight interpolation claimed, so a "step draws more
    #              ink" bug cannot pass it.
    #   (293, 60)  NONE background (edge at 96.9), POST filled.
    #   (360, 40)  NONE background (edge at 157.5), POST filled -- deep
    #              inside the plateau, where a straight edge is 117px
    #              lower.
    #
    # x=147/293 are skipped for MID: its risers land at 147.273 and
    # 292.727, so those columns are antialiased edge, not interior.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var t = Theme(show_gridlines=False)
    var mc = t.mark_color

    var straight = Plot().mark_area().encode(x=x, y=y).theme(t).size(400, 300)
    var c_none = render(straight)
    _assert_color(c_none, 100, 60, BG, "no plateau without a step")
    _assert_color(c_none, 180, 60, BG, "the straight edge is still climbing")
    _assert_color(c_none, 200, 60, mc, "the straight edge has passed y=60")
    _assert_color(c_none, 293, 60, BG, "the straight descent is well below")
    _assert_color(c_none, 360, 40, BG, "and further below still at x=360")

    var pre = (
        Plot()
        .mark_area(step=StepStyle.PRE)
        .encode(x=x, y=y)
        .theme(t)
        .size(400, 300)
    )
    var c_pre = render(pre)
    _assert_color(c_pre, 100, 60, mc, "PRE's first plateau is the high one")
    _assert_color(c_pre, 180, 60, mc, "still that plateau at x=180")
    _assert_color(c_pre, 360, 40, BG, "PRE's last plateau is the low one")

    var mid = (
        Plot()
        .mark_area(step=StepStyle.MID)
        .encode(x=x, y=y)
        .theme(t)
        .size(400, 300)
    )
    var c_mid = render(mid)
    _assert_color(c_mid, 100, 60, BG, "MID's first half-plateau is the low one")
    _assert_color(c_mid, 180, 60, mc, "MID has risen by x=180")
    _assert_color(c_mid, 360, 40, BG, "MID's last half-plateau is the low one")

    var post = (
        Plot()
        .mark_area(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(t)
        .size(400, 300)
    )
    var c_post = render(post)
    _assert_color(c_post, 180, 60, BG, "POST still holds the low first value")
    _assert_color(c_post, 200, 60, BG, "and holds it past where NONE has risen")
    _assert_color(c_post, 293, 60, mc, "POST's plateau reaches x=293")
    _assert_color(c_post, 360, 40, mc, "and holds it to the last sample")


def test_render_area_step_leaves_the_baseline_and_the_ends_flat() raises:
    # The step belongs to the top edge only. Three properties, none of
    # which depends on where the margins put the frame:
    #
    #  - the filled silhouette spans exactly the same columns and rows
    #    under all four styles, so no style overshoots the outermost
    #    sample or leaves a gap short of it;
    #  - the row just above the baseline is one unbroken run of fill in
    #    all four, so the closing segments never cross back over the
    #    staircase and pinch it in two;
    #  - and that run is the identical span in all four, so the bottom
    #    edge is still straight rather than having picked up risers of
    #    its own.
    #
    # Row 245 is 4px above the baseline at 249 and clear of the axis
    # line beneath it.
    #
    # Invariance on its own would pass on a build that ignored `step`
    # entirely, so the last block asserts the opposite for a row that
    # crosses the staircase. Row 200 is 6px below the low plateau at
    # 206.190, so where the fill starts on that row is exactly where
    # that style's top edge last dropped below it, and the four
    # disagree: PRE is up on the high plateau from the left edge (76),
    # the unstepped diagonal crosses y=200 a little later (81), MID
    # holds the low value until its first riser (148) and POST until
    # the second sample (221). Measured, then written down as strict
    # inequalities so an antialiasing change of a pixel does not
    # relitigate them.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var t = Theme(show_gridlines=False)
    var mc = t.mark_color
    var styles: List[StepStyle] = [
        StepStyle.NONE,
        StepStyle.PRE,
        StepStyle.MID,
        StepStyle.POST,
    ]
    var c_none = render(
        Plot().mark_area().encode(x=x, y=y).theme(t).size(400, 300)
    )
    var reference = _bbox_of_color(c_none, mc)
    var ref_row = _row_extent(c_none, 245, mc)
    var none_200 = _row_extent(c_none, 200, mc)
    assert_true(reference.found, "the unstepped area fills something")
    var start_200: List[Int] = []
    for s in styles:
        var c = render(
            Plot().mark_area(step=s).encode(x=x, y=y).theme(t).size(400, 300)
        )
        var box = _bbox_of_color(c, mc)
        assert_equal(box.x0, reference.x0, "left edge, step=" + s.name())
        assert_equal(box.x1, reference.x1, "right edge, step=" + s.name())
        assert_equal(box.y0, reference.y0, "top edge, step=" + s.name())
        assert_equal(box.y1, reference.y1, "bottom edge, step=" + s.name())
        assert_equal(
            _runs_in_row(c, 245, mc),
            1,
            "the fill above the baseline is unbroken, step=" + s.name(),
        )
        var row = _row_extent(c, 245, mc)
        assert_equal(row.x0, ref_row.x0, "baseline run start, step=" + s.name())
        assert_equal(row.x1, ref_row.x1, "baseline run end, step=" + s.name())
        start_200.append(_row_extent(c, 200, mc).x0)

    # styles is [NONE, PRE, MID, POST].
    assert_equal(start_200[0], none_200.x0, "NONE is the unstepped render")
    assert_true(
        start_200[1] < start_200[0],
        (
            "PRE's high first plateau reaches row 200 left of the straight"
            " edge (got "
            + String(start_200[1])
            + " against "
            + String(start_200[0])
            + ")"
        ),
    )
    assert_true(
        start_200[0] < start_200[2],
        (
            "MID holds the low first value past where the straight edge has"
            " climbed (got "
            + String(start_200[2])
            + " against "
            + String(start_200[0])
            + ")"
        ),
    )
    assert_true(
        start_200[2] < start_200[3],
        (
            "POST holds it further still, to the second sample (got "
            + String(start_200[3])
            + " against "
            + String(start_200[2])
            + ")"
        ),
    )


def test_render_area_step_raises_when_combined_with_line_smoothing() raises:
    # Same mutual exclusion Mark.LINE has, and for a sharper reason: a
    # Catmull-Rom tangent through a riser's two same-x points is
    # horizontal, so the curve bows sideways past the samples -- on a
    # stroked line that is a thin overshoot, on a fill it is a whole
    # column of ink down to the baseline under an x the data never
    # reached. The message names mark_area(), not mark_line(), so it
    # points at the method the caller actually called.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    with assert_raises(
        contains=(
            "Theme.line_smoothing and Plot.mark_area(step=...) are mutually"
            " exclusive"
        )
    ):
        var plot = (
            Plot()
            .mark_area(step=StepStyle.MID)
            .encode(x=x, y=y)
            .theme(Theme(line_smoothing=0.5))
            .size(200, 150)
        )
        _ = render_svg(plot)
    # Smoothing with the default StepStyle.NONE is still fine.
    var ok = (
        Plot()
        .mark_area()
        .encode(x=x, y=y)
        .theme(Theme(line_smoothing=0.5))
        .size(200, 150)
    )
    _ = render_svg(ok)


def test_render_area_step_keeps_at_most_two_points_per_pixel_column() raises:
    # _draw_area_layer steps *before* decimating, the order
    # _draw_line_layer uses, so the two-points-per-column cap applies to
    # the staircase that is actually filled. Expanding afterwards would
    # turn each surviving point back into a plateau and a riser, putting
    # the segments straight back.
    #
    # Both orders were measured on this series by building each and
    # reading the rendered `d`: 1023 points this way, 2042 the other,
    # over the same 510 pixel columns. The bound below allows 2 per
    # column plus 8 for the two closing points, the Z, and the rounding
    # at the ends of the span (the `d` prints three decimals, so a point
    # at 375.9996 files under column 376) -- 1028, which the right order
    # clears and the wrong one misses by a factor of two.
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(5000):
        x.append(Float64(i))
        y.append(Float64(i % 17))
    var plot = (
        Plot()
        .mark_area(step=StepStyle.POST)
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(640, 420)
    )
    var paths = _attr_values(render_svg(plot).to_string(), "path", "d")
    var longest = String("")
    for p in paths:
        if p.byte_length() > longest.byte_length():
            longest = p.copy()
    var tokens = longest.split(" ")
    assert_true(
        len(tokens) < 5000,
        (
            "decimation ran at all (kept "
            + String(len(tokens))
            + " of 9999 stepped points plus the closing pair)"
        ),
    )

    var lo_col = 1 << 30
    var hi_col = -1
    for token in tokens:
        # "M74.545,239.545" / "L220.000,239.545" / a bare "Z".
        var comma = token.find(",")
        if comma == -1:
            continue
        var xs = String(token[byte=1:comma])
        var dot = xs.find(".")
        var col = Int(String(xs[byte=0:dot]) if dot != -1 else xs)
        if col < lo_col:
            lo_col = col
        if col > hi_col:
            hi_col = col
    var columns = hi_col - lo_col + 1
    assert_true(
        len(tokens) <= 2 * columns + 8,
        (
            "the filled staircase has "
            + String(len(tokens))
            + " points over "
            + String(columns)
            + " pixel columns; decimation caps it at two per column"
        ),
    )


def test_area_one_call_step_matches_the_builder() raises:
    # area(step=...) has to be the same chart Plot().mark_area(step=...)
    # builds, not a second implementation of it. Equality alone would
    # also hold if both ends dropped `step` on the floor, so the second
    # assertion pins that they did not: the stepped render has to differ
    # from the default one.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var t = Theme(show_gridlines=False)
    var one_call = area(
        x, y, step=StepStyle.MID, theme=t, width=400, height=300
    )
    var built = (
        Plot()
        .mark_area(step=StepStyle.MID)
        .encode(x=x, y=y)
        .theme(t)
        .size(400, 300)
    )
    var stepped_svg = render_svg(one_call).to_string()
    assert_equal(stepped_svg, render_svg(built).to_string())
    var plain = area(x, y, theme=t, width=400, height=300)
    assert_true(
        stepped_svg != render_svg(plain).to_string(),
        "area(step=MID) draws something the default area() does not",
    )


# ---------------------------------------------------------------
# from tests/test_bar.mojo
# ---------------------------------------------------------------


def test_render_bar_mark_matches_hand_derived_bar_rectangles() raises:
    # 3 categories, y=[10,20,15], canvas 400x300 with default margins (plot
    # area x:[60,380], y:[20,250]). _zero_baseline_y_extent pads [0,20] to
    # [0,21.0]: baseline y=250, tops at y=140/31/86. OrdinalScale's 0.2
    # padding over [60,380] (step 106.667, bandwidth 85.333) puts each
    # band's left edge at x=71/177/284. Gridlines off.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var mark_color = t.mark_color

    # Inside each bar (well within both its x-span and its height).
    _assert_color(c, 113, 200, mark_color, "inside bar 0 (value 10)")
    _assert_color(c, 220, 50, mark_color, "inside bar 1 (value 20)")
    _assert_color(c, 327, 200, mark_color, "inside bar 2 (value 15)")

    # Above bar 0's top (y=140) -- outside the bar, background.
    _assert_color(c, 113, 100, BG, "above bar 0's top -- background")

    # Between bar 0 (ends x=156) and bar 1 (starts x=177) -- the
    # padding gap, background.
    _assert_color(c, 165, 200, BG, "gap between bar 0 and bar 1")


def test_render_bar_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = bar(x, y, width=200, height=150)
        _ = render(_hoisted2)


def test_render_bar_raises_on_no_data() raises:
    # #206: an all-empty Plot used to render a plain background with no
    # axes and no error; _validate_categorical_encoding now raises before
    # any layout.
    with assert_raises():
        var plot = (
            Plot().mark_bar().size(50, 40)
        )  # no encode_categorical() call
        _ = render(plot)


def test_render_bar_negative_values_extend_below_the_baseline() raises:
    """A negative bar hangs below the zero baseline and a positive one
    rises above it, so in one chart carrying both they occupy opposite
    sides and do not overlap at all.

    Located by scanning rather than by hand-derived pixel (#218), and
    stated with both signs in one chart on purpose. A single bar is not
    the test it looks like: `_zero_baseline_y_extent` pads only the end
    that is not zero, so a lone -10 spans y 20-238 and a lone +10 spans
    31-248 -- each anchored to its own end of the plot, but overlapping
    each other almost entirely. Comparing two separate charts would
    therefore prove nothing. Coloring by sign is what makes the two bars
    separately findable here.

    The exact baseline pixel stays anchored by
    `test_render_bar_mark_matches_hand_derived_bar_rectangles` above.
    """
    var cats: List[String] = ["pos", "neg"]
    var vals: List[Float64] = [10.0, -10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var c = render(bar(cats, vals, theme=t, width=400, height=300))

    var above = _bbox_of_color(c, t.mark_color)
    var below = _bbox_of_color(c, t.mark_color_negative)
    assert_true(above.found, "the positive bar was drawn")
    assert_true(below.found, "the negative bar was drawn")
    assert_true(
        above.y1 < below.y0,
        "the positive bar sits entirely above the negative one (positive y "
        + String(above.y0)
        + "-"
        + String(above.y1)
        + ", negative y "
        + String(below.y0)
        + "-"
        + String(below.y1)
        + ")",
    )
    # They meet at the baseline rather than leaving a gap: one pixel of
    # separation is the boundary between the two rects.
    assert_true(
        below.y0 - above.y1 <= 2,
        "the two bars meet at the shared zero baseline",
    )


def test_render_svg_bar_mark_matches_confirmed_rect() raises:
    # Same 3-category data: bar 1's rect x=177, y=31, width=85; its bottom
    # sits on the axis line (250), so _pull_off_axis_line shrinks the
    # height from 219 to 218.
    # Coordinates re-derived when Mark.BAR moved onto canvas's Float64
    # overloads: a coordinate is now a geometric edge under the
    # pixel-center convention rather than a pixel index, which places
    # each edge closer to the exact scale position (measured: total
    # edge error across the three bands 4.00px before, 1.67px after).
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [10.0, 20.0, 15.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    assert_true(
        '<rect x="178" y="31" width="85" height="219" fill="#1e64b4"/>'
        in svg.to_string(),
        (
            "BAR mark's middle bar, same rectangle render()'s hand-derived test"
            " finds"
        ),
    )


def test_render_bar_color_by_sign_colors_negative_bars_differently() raises:
    """A negative bar under `color_by_sign` is drawn in
    `mark_color_negative` -- and the ordinary `mark_color` appears
    nowhere, which a single sampled pixel could not tell you.
    """
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var c = render(bar(x, y, theme=t, width=400, height=300))

    assert_true(
        _bbox_of_color(c, t.mark_color_negative).found,
        "the negative bar uses mark_color_negative",
    )
    assert_true(
        not _bbox_of_color(c, t.mark_color).found,
        "and no part of it is drawn in the ordinary mark_color",
    )


def test_render_bar_color_by_sign_leaves_positive_bars_at_mark_color() raises:
    """The mirror: a positive bar stays `mark_color` with `color_by_sign`
    on, and `mark_color_negative` is not drawn at all.
    """
    var x: List[String] = ["a"]
    var y: List[Float64] = [10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var c = render(bar(x, y, theme=t, width=400, height=300))

    assert_true(
        _bbox_of_color(c, t.mark_color).found,
        "the positive bar stays mark_color",
    )
    assert_true(
        not _bbox_of_color(c, t.mark_color_negative).found,
        "and mark_color_negative is never drawn",
    )


def test_render_bar_color_by_sign_defaults_off() raises:
    # color_by_sign's default (False) leaves a negative bar at mark_color.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False)
    var _hoisted6 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted6)
    _assert_color(
        c, 220, 25, t.mark_color, "color_by_sign defaults off: still mark_color"
    )


# ---------------------------------------------------------------
# from tests/test_histogram.mojo
# ---------------------------------------------------------------


def test_encode_histogram_bins_match_hand_derived_counts() raises:
    # 10 values, 5 bins: bin_width=(9.0-1.0)/5=1.6, counts [3, 3, 2, 0, 2].
    # Bin 3 ([5.8,7.4)) is empty and still a 0-count category. 9.0 (the
    # max) lands in the last bin.
    var data: List[Float64] = [1.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 8.0, 9.0]
    var plot = Plot().mark_bar().encode_histogram(data, bins=5)
    assert_equal(len(plot.x_categories), 5)
    assert_equal(plot.x_categories[0], "1.0-2.6")
    assert_equal(plot.x_categories[1], "2.6-4.2")
    assert_equal(plot.x_categories[2], "4.2-5.8")
    assert_equal(plot.x_categories[3], "5.8-7.4")
    assert_equal(plot.x_categories[4], "7.4-9.0")
    assert_equal(plot.y_data[0], 3.0)
    assert_equal(plot.y_data[1], 3.0)
    assert_equal(plot.y_data[2], 2.0)
    assert_equal(plot.y_data[3], 0.0)
    assert_equal(plot.y_data[4], 2.0)


def test_encode_histogram_raises_on_empty_data() raises:
    var data = List[Float64]()
    with assert_raises():
        _ = Plot().mark_bar().encode_histogram(data, bins=5)


def test_encode_histogram_raises_on_non_positive_bins() raises:
    var data: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        _ = Plot().mark_bar().encode_histogram(data, bins=0)


def test_encode_histogram_raises_on_zero_span_data() raises:
    var data: List[Float64] = [5.0, 5.0, 5.0]
    with assert_raises():
        _ = Plot().mark_bar().encode_histogram(data, bins=5)


def test_render_histogram_draws_as_an_ordinary_bar_chart() raises:
    # A smoke test for the wiring; Mark.BAR's rendering math is covered by
    # its own tests.
    var data: List[Float64] = [1.0, 1.0, 1.0, 5.0, 9.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_histogram(data, bins=3)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var c = render(plot)
    # Bin 0 ([1.0, 3.667)) holds 3 of the 5 values, so its bar is the
    # tallest and covers the plot's vertical center.
    var mid_of_plot_area = c.get_pixel(113, 135)
    assert_true(
        mid_of_plot_area.r != 255
        or mid_of_plot_area.g != 255
        or mid_of_plot_area.b != 255,
        (
            "bin 0's bar (3 of 5 values) reaches well above the plot area's"
            " midpoint"
        ),
    )


# ---------------------------------------------------------------
# from tests/test_lollipop.mojo
# ---------------------------------------------------------------


def test_render_lollipop_matches_hand_derived_stem_and_point() raises:
    # Same data/canvas/theme as the bar rectangles test: category "b"'s
    # band center is 220.0 (band_start(1)=177.333 + 42.667) and its
    # value-20 pixel is 30.952 -> 31; only the shape drawn there differs.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = lollipop(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c, 220, 31, t.mark_color, "circle center, category b's value pixel"
    )
    _assert_color(
        c,
        220,
        150,
        t.mark_color,
        "stem midpoint, well within the 2px-wide stroke",
    )
    _assert_color(c, 210, 150, BG, "off the stem entirely -- background")
    _assert_color(c, 220, 10, BG, "above the point -- nothing drawn there")


def test_render_lollipop_svg_matches_confirmed_stem_and_point() raises:
    # The baseline (250.000) sits on the bottom axis line, so the stem
    # starts at 249.000 (see _pull_off_axis_line).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var plot = (
        Plot()
        .mark_lollipop()
        .encode_categorical(x=x, y=y)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,249.000 L220.000,30.952" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>'
        in s,
        "category b's stem",
    )
    assert_true(
        '<circle cx="220.000" cy="30.952" r="4.000" fill="#1e64b4"/>' in s,
        (
            "category b's point, now at the stem's own endpoint rather than"
            " rounded a pixel off it"
        ),
    )


def test_render_lollipop_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = lollipop(x, y, width=200, height=150)
        _ = render(_hoisted2)


# ---------------------------------------------------------------
# from tests/test_box.mojo
# ---------------------------------------------------------------


def test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier() raises:
    # 2 categories: "A" = [2,4,4,4,5,5,7,9,20] (q1=4, median=5, q3=7,
    # whiskers 2/9, fence [-0.5, 11.5] so 20 is the one outlier), "B" =
    # [10,12,14,15,18] (q1=12, median=14, q3=15, whiskers 10/18, no
    # outliers), computed with the same linear-interpolation percentile
    # _box_stats uses. Domain = _data_extent over [2,9,10,18,20] =
    # [1.1, 20.9]; 2 categories over [60,380] (band centers 140/300,
    # bandwidth 128, half-width 64, cap half-width 32).
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = (
        Plot().mark_box().encode_boxplot(cats, values).theme(t).size(400, 300)
    )
    var c = render(_hoisted1)

    _assert_color(
        c, 140, 200, t.mark_color, "A: inside the box (between q1 and q3)"
    )
    # Median line and whisker checks use _assert_near_color(), since both
    # are 1px strokes; the high-whisker cap lands exact at its sampled
    # position.
    _assert_near_color(
        c,
        140,
        205,
        t.axis_color,
        70,
        "A: the median line, drawn over the box fill",
    )
    _assert_near_color(
        c,
        140,
        170,
        t.axis_color,
        60,
        "A: the upper whisker, between q3 and high",
    )
    _assert_color(c, 120, 158, t.axis_color, "A: the high-whisker cap")
    _assert_color(
        c, 140, 30, t.mark_color, "A: the one outlier point, at value 20"
    )
    _assert_color(c, 300, 105, t.mark_color, "B: inside the box")
    _assert_near_color(c, 300, 100, t.axis_color, 40, "B: the median line")
    _assert_near_color(
        c, 300, 70, t.axis_color, 60, "B: the lower whisker, between q1 and low"
    )
    _assert_color(
        c, 190, 150, BG, "the gap between A's and B's bands -- background"
    )


def test_render_boxplot_svg_matches_confirmed_rects_and_outlier() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var plot = (
        Plot()
        .mark_box()
        .encode_boxplot(cats, values)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="77" y="182" width="128" height="35" fill="#1e64b4"/>' in s,
        "A's box (q1 to q3)",
    )
    assert_true(
        '<rect x="237" y="89" width="128" height="35" fill="#1e64b4"/>' in s,
        "B's box (q1 to q3)",
    )
    assert_true(
        '<circle cx="140.000" cy="30.455" r="4.000" fill="#1e64b4"/>' in s,
        "A's single outlier, now at value 20's exact position",
    )


def test_encode_boxplot_raises_on_mismatched_length() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted2 = box(cats, values)
        _ = render(_hoisted2)


def test_encode_boxplot_raises_on_empty_category_values() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0], List[Float64]()]
    with assert_raises():
        var _hoisted3 = box(cats, values)
        _ = render(_hoisted3)


# ---------------------------------------------------------------
# from tests/test_candlestick.mojo
# ---------------------------------------------------------------


def test_render_candlestick_matches_hand_derived_wicks_and_bodies() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,380],
    # y:[20,250]), no gridlines. "A" = O10/H15/L8/C13 (closed up); "B" =
    # O20/H22/L16/C17 (closed down). Domain = _data_extent over every
    # O/H/L/C value [8,22] padded 5% = [7.3, 22.7]; bands at x=76/236,
    # width 128, centers 140/300.
    #
    # Wick checks use _assert_near_color(), since a wick is a 1px stroke;
    # the body and background checks stay exact.
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = (
        Plot()
        .mark_candlestick()
        .encode_candlestick(cats, open, high, low, close)
        .theme(t)
        .size(400, 300)
    )
    var c = render(_hoisted1)

    _assert_color(
        c,
        140,
        200,
        t.mark_color,
        "A: inside the body (open=210 to close=165), closed up",
    )
    _assert_near_color(
        c,
        140,
        150,
        t.axis_color,
        60,
        "A: the wick, above the body (between high=135 and the body top)",
    )
    _assert_near_color(
        c,
        140,
        225,
        t.axis_color,
        60,
        "A: the wick, below the body (between the body bottom and low=240)",
    )
    _assert_color(
        c,
        300,
        80,
        t.mark_color_negative,
        "B: inside the body (open=60 to close=105), closed down",
    )
    _assert_near_color(
        c,
        300,
        45,
        t.axis_color,
        60,
        "B: the wick, above the body (between high=30 and the body top)",
    )
    _assert_near_color(
        c,
        300,
        115,
        t.axis_color,
        60,
        "B: the wick, below the body (between the body bottom and low=120)",
    )
    _assert_color(
        c, 190, 150, BG, "no ink here -- off the wick's x, above A's body"
    )


def test_render_candlestick_svg_matches_confirmed_wicks_and_bodies() raises:
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var plot = (
        Plot()
        .mark_candlestick()
        .encode_candlestick(cats, open, high, low, close)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="140.000" y1="135.000" x2="140.000" y2="239.545"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "A's wick: the fixed column snaps, the two ends keep the"
            " high and low prices' exact rows"
        ),
    )
    assert_true(
        '<rect x="77" y="165" width="128" height="45" fill="#1e64b4"/>' in s,
        "A's body, closed up",
    )
    assert_true(
        '<line x1="300.000" y1="30.455" x2="300.000" y2="120.065"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "B's wick, from high=30 to low=120",
    )
    assert_true(
        '<rect x="237" y="61" width="128" height="45" fill="#c83c3c"/>' in s,
        "B's body, closed down",
    )


def test_render_candlestick_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = candlestick(
            cats, open, high, low, close, width=200, height=150
        )
        _ = render(_hoisted2)


def test_render_candlestick_raises_on_mismatched_ohlc_length() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0]
    with assert_raises():
        var _hoisted3 = candlestick(
            cats, open, high, low, close, width=200, height=150
        )
        _ = render(_hoisted3)


# ---------------------------------------------------------------
# from tests/test_waterfall.mojo
# ---------------------------------------------------------------


def test_render_waterfall_colors_by_sign_and_matches_hand_derived_bars() raises:
    # 3 categories, deltas=[10, -4, 6]: running totals y0/y1 = [0,10, 10,6,
    # 6,12]. Domain [0, 12.6] (_zero_baseline_y_extent over y0 union y1);
    # band centers 113/220/327 as in the bar test. Bar 0 (+10) mark_color,
    # bar 1 (-4) mark_color_negative (unconditional, no color_by_sign
    # needed), bar 2 (+6) mark_color, plus two connector lines where
    # consecutive running totals hand off.
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = waterfall(cats, deltas, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c, 113, 150, t.mark_color, "bar 0 (delta +10), well inside its rect"
    )
    _assert_color(
        c, 220, 100, t.mark_color_negative, "bar 1 (delta -4), colored by sign"
    )
    _assert_color(
        c, 327, 80, t.mark_color, "bar 2 (delta +6), back to mark_color"
    )
    _assert_color(c, 165, 67, t.axis_color, "connector between bar 0 and bar 1")
    _assert_color(
        c, 273, 140, t.axis_color, "connector between bar 1 and bar 2"
    )
    _assert_color(c, 350, 10, BG, "far from every bar -- background")


def test_render_waterfall_svg_matches_confirmed_rects_and_connectors() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var plot = (
        Plot()
        .mark_waterfall()
        .encode_waterfall(cats, deltas)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        # Bar 0's y0=0 lands on the bottom axis line, so its height shrinks
        # (see _pull_off_axis_line_f); bars 1/2 never touch 0. Connector
        # ends now sit on the band edges they join rather than rounded to
        # them, while the shared row they run along still snaps.
        '<rect x="71" y="68" width="86" height="182" fill="#1e64b4"/>' in s,
        "bar 0 (delta +10): y0=0 to y1=10",
    )
    assert_true(
        '<rect x="178" y="68" width="85" height="73" fill="#c83c3c"/>' in s,
        "bar 1 (delta -4): y0=10 down to y1=6, colored by sign",
    )
    assert_true(
        '<rect x="285" y="31" width="85" height="110" fill="#1e64b4"/>' in s,
        "bar 2 (delta +6): y0=6 to y1=12",
    )
    assert_true(
        '<line x1="156.000" y1="67.000" x2="177.333" y2="67.000"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "connector between bar 0 and bar 1, at the shared y1=10/y0=10 pixel"
            " height"
        ),
    )
    assert_true(
        '<line x1="262.667" y1="140.000" x2="284.000" y2="140.000"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "connector between bar 1 and bar 2, at the shared y1=6/y0=6 pixel"
            " height"
        ),
    )


def test_render_waterfall_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = waterfall(cats, deltas, width=200, height=150)
        _ = render(_hoisted2)


def test_render_waterfall_total_rows_matches_hand_derived_bars() raises:
    # 4 categories: "Start" (total, delta=50, displayed 0 -> 50), "A"
    # (+20), "B" (-10), "End" (total, delta=0, displayed 0 -> 60). Running
    # sum: Start (y0=0,y1=50), A (50,70), B (70,60), End (0,60). Canvas
    # 400x300, default margins, no gridlines; _zero_baseline_y_extent over
    # {0,50,70,60} -> [0, 73.5].
    #
    # OrdinalScale over [60,380], 4 categories, step=80, bandwidth=64 ->
    # band_start: Start=68, A=148, B=228, End=308. Total bars draw the full
    # 64px; delta bars draw 0.6 of it (narrow=38.4, inset=12.8).
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var t = Theme(show_gridlines=False)
    # mark_waterfall()'s own default, now that it isn't a Theme field.
    var total_color = Color(100, 100, 100)
    var _hoisted3 = waterfall(
        cats, deltas, is_total=is_total, theme=t, width=400, height=300
    )
    var c = render(_hoisted3)

    # Start (total): x:[68,132), y:[94,250) -- full band width.
    _assert_color(c, 100, 200, total_color, "Start (total), well inside")
    # A (delta +20, narrower): x:[161,199), y:[31,94).
    _assert_color(
        c, 180, 60, t.mark_color, "A (delta +20), well inside its narrower rect"
    )
    # A's band still has real background on either side of the
    # narrow bar -- confirming it actually IS narrower, not just a
    # differently-colored full-width bar.
    _assert_color(
        c, 150, 60, BG, "A's band, left of its narrow bar -- background"
    )
    # B (delta -10, narrower): x:[241,279), y:[31,62).
    _assert_color(
        c, 260, 45, t.mark_color_negative, "B (delta -10), colored by sign"
    )
    # End (total): x:[308,372), y:[62,250) -- full band width again.
    _assert_color(c, 340, 150, total_color, "End (total), well inside")


def test_render_svg_waterfall_total_rows_matches_confirmed_rects() raises:
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var plot = (
        Plot()
        .mark_waterfall()
        .encode_waterfall(cats, deltas, is_total)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        # Both total rows' y0=0 lands on the bottom axis line, so each height
        # is pulled 1px (156->155, 188->187); A/B never touch 0.
        '<rect x="69" y="94" width="64" height="156" fill="#646464"/>' in s,
        "Start (total): 0 -> 50",
    )
    assert_true(
        '<rect x="161" y="31" width="39" height="63" fill="#1e64b4"/>' in s,
        "A: 50 -> 70",
    )
    assert_true(
        '<rect x="241" y="31" width="39" height="32" fill="#c83c3c"/>' in s,
        "B: 70 -> 60",
    )
    assert_true(
        '<rect x="309" y="63" width="64" height="187" fill="#646464"/>' in s,
        "End (total): 0 -> 60",
    )
    # Connectors reference each bar's actual drawn edge (bar_x1_list[i-1])
    # once total rows are in play. The ends are the bars' exact geometric
    # edges rather than the snapped pixel columns, so they can sit a
    # fraction inside the bar they meet (160.800 against A's drawn 161);
    # the shared row the connector runs along still snaps.
    assert_true(
        '<line x1="132.000" y1="94.000" x2="160.800" y2="94.000"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "connector: Start's actual right edge -> A's left edge",
    )
    assert_true(
        '<line x1="199.200" y1="31.000" x2="240.800" y2="31.000"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "connector: A's actual right edge -> B's left edge",
    )
    assert_true(
        '<line x1="279.200" y1="62.000" x2="308.000" y2="62.000"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "connector: B's actual right edge -> End's left edge",
    )


def test_render_waterfall_raises_on_mismatched_is_total_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var is_total: List[Bool] = [True, False]
    with assert_raises():
        var _hoisted4 = waterfall(
            cats, deltas, is_total=is_total, width=400, height=300
        )
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# from tests/test_bullet.mojo
# ---------------------------------------------------------------


def test_render_bullet_matches_hand_derived_bands_measure_and_target() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,380],
    # y:[20,250]), no gridlines. "A" = ranges=[40,70,100], measure=55,
    # target=65; "B" = ranges=[30,60,90], measure=75, target=50. Domain
    # data {0, range-top, measure, target} per category ->
    # _zero_baseline_y_extent gives [0, 105]. Bands at x=76/236, width 128,
    # centers 140/300; scale=(20-250)/105=-2.190476, translate=250.
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = (
        Plot()
        .mark_bullet()
        .encode_bullet(cats, measures, targets, ranges)
        .theme(t)
        .size(400, 300)
    )
    var c = render(_hoisted1)

    _assert_color(
        c,
        90,
        200,
        Color(224, 224, 224),
        "A: lightest range band [0,40], off the measure bar",
    )
    _assert_color(
        c,
        90,
        130,
        Color(172, 172, 172),
        "A: middle range band [40,70], off the measure bar",
    )
    _assert_color(
        c,
        90,
        60,
        Color(120, 120, 120),
        "A: darkest range band [70,100], off the measure bar",
    )
    _assert_color(
        c,
        140,
        200,
        t.mark_color,
        "A: inside the measure bar (0 to 55), over the bands",
    )
    # A's target tick rather than B's: supersampling doesn't land this
    # particular 1px stroke fully opaque at this column, while B's tick
    # below does.
    _assert_near_color(
        c,
        90,
        108,
        t.axis_color,
        65,
        "A: the target tick (65), off the measure bar",
    )
    _assert_color(c, 140, 10, BG, "A: above every band -- background")
    _assert_color(
        c, 300, 150, t.mark_color, "B: inside the measure bar (0 to 75)"
    )
    _assert_color(
        c,
        250,
        140,
        t.axis_color,
        "B: the target tick (50), off the measure bar",
    )
    _assert_color(
        c, 220, 150, BG, "the gap between A's and B's bands -- background"
    )


def test_render_bullet_svg_matches_confirmed_bands_measure_and_target() raises:
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var plot = (
        Plot()
        .mark_bullet()
        .encode_bullet(cats, measures, targets, ranges)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    # The lightest band's bottom (prev_threshold=0) and the measure bar's
    # bottom (baseline=0) both land on the bottom axis line, so both
    # heights are pulled 1px (88->87, 120->119); the other bands and the
    # target tick never touch 0.
    assert_true(
        '<rect x="77" y="163" width="128" height="87" fill="#e0e0e0"/>' in s,
        "A's lightest band [0,40]",
    )
    assert_true(
        '<rect x="77" y="97" width="128" height="66" fill="#acacac"/>' in s,
        "A's middle band [40,70]",
    )
    assert_true(
        '<rect x="77" y="31" width="128" height="66" fill="#787878"/>' in s,
        "A's darkest band [70,100]",
    )
    assert_true(
        '<rect x="118" y="130" width="45" height="120" fill="#1e64b4"/>' in s,
        "A's measure bar",
    )
    assert_true(
        '<line x1="76.000" y1="108.000" x2="204.000" y2="108.000"'
        ' stroke="#505050" stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "A's target tick, full band width",
    )


def test_render_bullet_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], [1.0]]
    with assert_raises():
        var _hoisted2 = bullet(cats, one, one, ranges, width=200, height=150)
        _ = render(_hoisted2)


def test_render_bullet_raises_on_empty_range_thresholds() raises:
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], List[Float64]()]
    with assert_raises():
        var _hoisted3 = bullet(cats, one, one, ranges, width=200, height=150)
        _ = render(_hoisted3)


def test_render_bullet_raises_on_non_ascending_range_thresholds() raises:
    var cats: List[String] = ["a"]
    var one: List[Float64] = [1.0]
    var ranges: List[List[Float64]] = [[50.0, 30.0, 100.0]]
    with assert_raises():
        var _hoisted4 = bullet(cats, one, one, ranges, width=200, height=150)
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# Mark.BARBS
# ---------------------------------------------------------------


def test_barb_counts_decomposes_speed_against_the_knot_increments() raises:
    # Speed rounds to the nearest 5 first (matplotlib's _find_tails), so
    # the boundary cases are the interesting ones: 2.4 rounds to 0 and is
    # calm, 2.6 rounds to 5 and draws a half barb.
    var calm = _barb_counts(0.0)
    assert_true(calm.calm, "0 knots is calm")
    assert_equal(calm.flags, 0)
    assert_equal(calm.barbs, 0)
    assert_true(not calm.half, "0 knots has no half barb")

    assert_true(_barb_counts(2.4).calm, "2.4 rounds down to nothing")
    assert_true(not _barb_counts(2.6).calm, "2.6 rounds up to a half barb")
    assert_true(_barb_counts(2.6).half, "2.6 rounds up to a half barb")

    var seven = _barb_counts(7.4)
    assert_equal(seven.barbs, 0, "7.4 rounds to 5, not 10")
    assert_true(seven.half, "7.4 rounds to a half barb")

    var thirteen = _barb_counts(12.6)
    assert_equal(thirteen.barbs, 1, "12.6 rounds to 15: a barb plus a half")
    assert_true(thirteen.half, "12.6 rounds to 15: a barb plus a half")

    var sixty_five = _barb_counts(65.0)
    assert_equal(sixty_five.flags, 1)
    assert_equal(sixty_five.barbs, 1)
    assert_true(sixty_five.half, "65 = 50 + 10 + 5")

    assert_equal(_barb_counts(100.0).flags, 2, "100 is two flags")
    assert_equal(_barb_counts(100.0).barbs, 0)


def test_barb_glyph_places_features_from_the_tip_inward() raises:
    # 65 knots on a 28px staff: one flag (width 0.25*28 = 7) at the tip,
    # then one spacing (0.125*28 = 3.5) of clear staff, a full barb
    # (height 0.4*28 = 11.2), and the half barb, each stepping one
    # spacing further inboard. Features hang to -y before rotation.
    var strokes = List[Path]()
    var pennants = List[Path]()
    _barb_glyph(strokes, pennants, _barb_counts(65.0), 28.0, False)

    assert_equal(len(strokes), 1, "one stroke path appended")
    assert_equal(len(pennants), 1, "one pennant path appended")

    assert_equal(len(strokes[0].commands), 6)
    # The staff, origin to tip along +x.
    assert_equal(strokes[0].commands[0].op, PathOp.MOVE_TO)
    assert_equal(strokes[0].commands[0].p1.x, 0.0)
    assert_equal(strokes[0].commands[0].p1.y, 0.0)
    assert_equal(strokes[0].commands[1].op, PathOp.LINE_TO)
    assert_equal(strokes[0].commands[1].p1.x, 28.0)
    assert_equal(strokes[0].commands[1].p1.y, 0.0)
    # The full barb: 28 - 7 (the flag) - 3.5 (a spacing) = 17.5.
    assert_equal(strokes[0].commands[2].op, PathOp.MOVE_TO)
    assert_equal(strokes[0].commands[2].p1.x, 17.5)
    assert_equal(strokes[0].commands[3].op, PathOp.LINE_TO)
    assert_equal(strokes[0].commands[3].p1.x, 14.0)
    assert_equal(strokes[0].commands[3].p1.y, -11.200000000000001)
    # The half barb: one more spacing inboard, half the height.
    assert_equal(strokes[0].commands[4].op, PathOp.MOVE_TO)
    assert_equal(strokes[0].commands[4].p1.x, 14.0)
    assert_equal(strokes[0].commands[5].op, PathOp.LINE_TO)
    assert_equal(strokes[0].commands[5].p1.x, 12.25)
    assert_equal(strokes[0].commands[5].p1.y, -5.6000000000000005)

    # The flag is a closed triangle: tip, apex, back down the staff.
    assert_equal(len(pennants[0].commands), 4)
    assert_equal(pennants[0].commands[0].op, PathOp.MOVE_TO)
    assert_equal(pennants[0].commands[0].p1.x, 28.0)
    assert_equal(pennants[0].commands[1].op, PathOp.LINE_TO)
    assert_equal(pennants[0].commands[1].p1.y, -11.200000000000001)
    assert_equal(pennants[0].commands[2].op, PathOp.LINE_TO)
    assert_equal(pennants[0].commands[2].p1.x, 21.0)
    assert_equal(pennants[0].commands[3].op, PathOp.CLOSE)


def test_barb_glyph_lone_half_barb_insets_from_the_tip() raises:
    # A 5-knot glyph's only feature sits one spacing in from the tip, so
    # it cannot be misread as a full barb drawn short.
    var strokes = List[Path]()
    var pennants = List[Path]()
    _barb_glyph(strokes, pennants, _barb_counts(5.0), 28.0, False)
    assert_equal(len(strokes[0].commands), 4)
    assert_equal(len(pennants[0].commands), 0, "5 knots has no flag")
    assert_equal(strokes[0].commands[2].op, PathOp.MOVE_TO)
    assert_equal(strokes[0].commands[2].p1.x, 24.5, "28 - one 3.5 spacing")


def test_barb_glyph_flip_mirrors_features_across_the_staff() raises:
    # flip=True is the southern-hemisphere convention: same staff, every
    # feature on the other side.
    var strokes = List[Path]()
    var pennants = List[Path]()
    _barb_glyph(strokes, pennants, _barb_counts(65.0), 28.0, True)
    assert_equal(strokes[0].commands[1].p1.x, 28.0, "staff is unchanged")
    assert_equal(strokes[0].commands[1].p1.y, 0.0, "staff is unchanged")
    assert_equal(strokes[0].commands[3].p1.y, 11.200000000000001)
    assert_equal(pennants[0].commands[1].p1.y, 11.200000000000001)


def test_render_svg_barbs_staff_points_upwind() raises:
    # A pure easterly component (u > 0, v = 0) is wind blowing east, so it
    # comes *from* the west and the staff points west: same y on both
    # endpoints, x decreasing by exactly the 28px staff length. The barb
    # then hangs off the tip, which is the far (west) end.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var u: List[Float64] = [10.0, 10.0]
    var v: List[Float64] = [0.0, 0.0]
    var plot = (
        Plot().mark_barbs().encode_barbs(x=x, y=y, u=u, v=v).size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    assert_true(
        '<path d="M74.545,239.545 L46.545,239.545' in svg,
        "staff runs 28px due west from the first point",
    )
    assert_true(
        "M46.545,239.545 L50.045,250.745" in svg,
        "the full barb hangs off the west tip",
    )


def test_render_svg_barbs_calm_point_draws_a_circle_not_a_staff() raises:
    # Under 2.5 knots there is no staff at all, just the small circle
    # (0.15 * length) meteorologists read as calm.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var u: List[Float64] = [0.0, 10.0]
    var v: List[Float64] = [0.0, 0.0]
    var plot = (
        Plot().mark_barbs().encode_barbs(x=x, y=y, u=u, v=v).size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    assert_true("<ellipse" in svg, "the calm point draws its circle")
    assert_equal(svg.count("<path"), 1, "only the 10-knot point draws a staff")


def test_render_barbs_draws_ink_for_every_point() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0, 2.0]
    var u: List[Float64] = [10.0, 20.0, 60.0]
    var v: List[Float64] = [5.0, -5.0, 0.0]
    var plot = (
        Plot().mark_barbs().encode_barbs(x=x, y=y, u=u, v=v).size(400, 300)
    )
    var c = render(plot)
    assert_true(
        _count_color(c, Color(30, 100, 180)) > 0,
        "the barb field puts the mark color on the canvas",
    )


def test_barbs_dtype_overload_matches_the_float64_path() raises:
    var xi: List[Int32] = [0, 1]
    var yi: List[Int32] = [0, 1]
    var ui: List[Int32] = [10, 10]
    var vi: List[Int32] = [0, 0]
    var xf: List[Float64] = [0.0, 1.0]
    var yf: List[Float64] = [0.0, 1.0]
    var uf: List[Float64] = [10.0, 10.0]
    var vf: List[Float64] = [0.0, 0.0]
    var from_int = barbs(xi, yi, ui, vi, width=400, height=300)
    var from_float = barbs(xf, yf, uf, vf, width=400, height=300)
    assert_equal(
        render_svg(from_int).to_string(),
        render_svg(from_float).to_string(),
        "List[Int32] renders identically to List[Float64]",
    )


def test_render_barbs_raises_on_mismatched_channel_lengths() raises:
    var x: List[Float64] = [0.0, 1.0]
    var short: List[Float64] = [0.0]
    with assert_raises():
        var _hoisted_barbs1 = (
            Plot()
            .mark_barbs()
            .encode_barbs(x=x, y=x, u=x, v=short)
            .size(200, 150)
        )
        _ = render(_hoisted_barbs1)


def test_render_barbs_raises_on_empty_data() raises:
    var empty = List[Float64]()
    with assert_raises():
        var _hoisted_barbs2 = (
            Plot()
            .mark_barbs()
            .encode_barbs(x=empty, y=empty, u=empty, v=empty)
            .size(200, 150)
        )
        _ = render(_hoisted_barbs2)


def test_render_barbs_raises_on_nonpositive_length() raises:
    var x: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted_barbs3 = (
            Plot()
            .mark_barbs(length=0.0)
            .encode_barbs(x=x, y=x, u=x, v=x)
            .size(200, 150)
        )
        _ = render(_hoisted_barbs3)


# ---------------------------------------------------------------
# Mark.CONTOUR (#259)
# ---------------------------------------------------------------


def _ramp_grid(rows: Int, cols: Int) -> List[List[Float64]]:
    """`z[r][c] = c`: a linear ramp along x, so the isoline for any level
    `L` is exactly the straight vertical line `x = L`.
    """
    var z = List[List[Float64]]()
    for _ in range(rows):
        var row = List[Float64]()
        for c in range(cols):
            row.append(Float64(c))
        z.append(row^)
    return z^


def _bowl_grid(size: Int) -> List[List[Float64]]:
    """`z = -(dx^2 + dy^2)` about the grid center, so the isoline for
    `-r^2` is exactly the circle of radius `r`.
    """
    var center = Float64(size - 1) / 2.0
    var z = List[List[Float64]]()
    for r in range(size):
        var row = List[Float64]()
        for c in range(size):
            var dx = Float64(c) - center
            var dy = Float64(r) - center
            row.append(-(dx * dx + dy * dy))
        z.append(row^)
    return z^


def test_contour_traces_a_linear_ramp_as_one_straight_line() raises:
    """On `z = c`, level 5 is the vertical line x = 5. Every crossing is
    an exact interpolation, so every point lands on x = 5 exactly, and
    chaining turns the 8 per-cell segments into a single polyline.
    """
    var z = _ramp_grid(9, 11)
    var segs = _contour_segments(z, 9, 11, 5.0)
    var lines = _chain_segments(segs)

    assert_equal(len(segs.ea), 8, "one segment per cell row")
    assert_equal(len(lines), 1, "chained into a single polyline")
    assert_equal(len(lines[0].xs), 9, "n segments chain into n+1 points")
    for i in range(len(lines[0].xs)):
        assert_equal(lines[0].xs[i], 5.0, "every point sits exactly on x = 5")


def test_contour_traces_a_radial_bowl_as_one_closed_circle() raises:
    """On `z = -(dx^2 + dy^2)`, level -36 is the circle of radius 6. The
    chained line closes on itself, and every point sits within the
    sagitta a unit-cell chord approximation can be off by (~1/(8r)).
    """
    var z = _bowl_grid(21)
    var segs = _contour_segments(z, 21, 21, -36.0)
    var lines = _chain_segments(segs)

    assert_equal(len(lines), 1, "one closed isoline, not a pile of pieces")
    ref line = lines[0]
    var last = len(line.xs) - 1
    assert_equal(line.xs[0], line.xs[last], "closes in x")
    assert_equal(line.ys[0], line.ys[last], "closes in y")

    var worst = 0.0
    for i in range(len(line.xs)):
        var dx = line.xs[i] - 10.0
        var dy = line.ys[i] - 10.0
        var err = abs(sqrt(dx * dx + dy * dy) - 6.0)
        if err > worst:
            worst = err
    assert_true(
        worst < 0.03,
        "worst radius error " + String(worst) + " within a chord's sagitta",
    )


def test_contour_chaining_consumes_every_segment_exactly_once() raises:
    """A chain of n segments is n+1 points, so summed over every polyline
    the point count is segments + lines. Anything else means a segment
    was dropped or walked twice.
    """
    var z = _bowl_grid(21)
    var segs = _contour_segments(z, 21, 21, -36.0)
    var lines = _chain_segments(segs)
    var points = 0
    for k in range(len(lines)):
        points += len(lines[k].xs)
    assert_equal(
        points, len(segs.ea) + len(lines), "every segment used exactly once"
    )


def test_contour_saddle_resolves_by_the_cell_center() raises:
    """The two ambiguous cases: diagonal corners on the same side of the
    level. The cell center decides which pair the isoline separates, and
    flipping the center's sign flips the pairing.

    One cell, corners a=(0,0) b=(1,0) cc=(1,1) d=(0,1), level 0.

    With a=3, b=-1, cc=3, d=-1 the center is +1, so the two *above*
    corners join through the middle and each *below* corner is cut off in
    its own corner: bottom-right by a bottom/right segment, top-left by a
    top/left one.
    """
    var above = List[List[Float64]]()
    var r0 = List[Float64]()
    r0.append(3.0)
    r0.append(-1.0)
    above.append(r0^)
    var r1 = List[Float64]()
    r1.append(-1.0)
    r1.append(3.0)
    above.append(r1^)

    var segs = _contour_segments(above, 2, 2, 0.0)
    assert_equal(len(segs.ea), 2, "a saddle emits two segments")
    # Hand-derived crossings: bottom (0.75, 0), right (1, 0.25),
    # top (0.25, 1), left (0, 0.75).
    assert_equal(segs.ax[0], 0.75, "first segment starts on the bottom edge")
    assert_equal(segs.ay[0], 0.0, "on the bottom edge")
    assert_equal(segs.bx[0], 1.0, "and ends on the right edge")
    assert_equal(segs.by[0], 0.25, "on the right edge")
    assert_equal(segs.ax[1], 0.25, "second segment starts on the top edge")
    assert_equal(segs.ay[1], 1.0, "on the top edge")
    assert_equal(segs.bx[1], 0.0, "and ends on the left edge")
    assert_equal(segs.by[1], 0.75, "on the left edge")

    # Mirror: center -1, so the below corners join and each above corner
    # is cut off instead -- bottom-left by a left/bottom segment,
    # top-right by a right/top one.
    var below = List[List[Float64]]()
    var s0 = List[Float64]()
    s0.append(1.0)
    s0.append(-3.0)
    below.append(s0^)
    var s1 = List[Float64]()
    s1.append(-3.0)
    s1.append(1.0)
    below.append(s1^)

    var segs2 = _contour_segments(below, 2, 2, 0.0)
    assert_equal(len(segs2.ea), 2, "still two segments")
    assert_equal(segs2.ax[0], 0.0, "first segment starts on the left edge")
    assert_equal(segs2.ay[0], 0.25, "on the left edge")
    assert_equal(segs2.bx[0], 0.25, "and ends on the bottom edge")
    assert_equal(segs2.by[0], 0.0, "on the bottom edge")


def test_contour_auto_levels_sit_strictly_inside_the_data_range() raises:
    """Levels are placed inside the range, never on it: a level exactly
    at the minimum or maximum traces the grid boundary or a single point.
    """
    var z = _ramp_grid(4, 11)  # values 0 through 10
    var levels = _auto_levels(z, 4)
    assert_equal(len(levels), 4, "the requested count")
    for i in range(len(levels)):
        assert_true(levels[i] > 0.0, "above the minimum")
        assert_true(levels[i] < 10.0, "below the maximum")
    for i in range(1, len(levels)):
        assert_true(levels[i] > levels[i - 1], "ascending")
    # Evenly spaced at lo + span * i/(n+1): 2, 4, 6, 8.
    assert_equal(levels[0], 2.0, "first level")
    assert_equal(levels[3], 8.0, "last level")


def test_contour_flat_grid_produces_no_levels_and_still_renders() raises:
    """A constant field has no interior to divide, so it draws an empty
    frame rather than raising -- the axes still report the extent.
    """
    var z = List[List[Float64]]()
    for _ in range(3):
        var row = List[Float64]()
        for _ in range(3):
            row.append(7.0)
        z.append(row^)
    assert_equal(len(_auto_levels(z, 5)), 0, "no levels for a flat grid")

    var svg = render_svg(contour(z, width=200, height=150)).to_string()
    assert_true("<svg" in svg, "renders a frame anyway")


def test_render_contour_svg_draws_one_stroked_path_per_isoline() raises:
    """A ramp with two explicit levels draws exactly two lines, each a
    stroked path with no fill."""
    var z = _ramp_grid(5, 11)
    var levels: List[Float64] = [3.0, 7.0]
    var svg = render_svg(
        contour(z, levels=levels, width=300, height=200)
    ).to_string()
    assert_equal(svg.count('fill="none"'), 2, "one stroked path per level")


def test_render_contour_draws_ink() raises:
    var z = _bowl_grid(15)
    var c = render(contour(z, level_count=5, width=300, height=220))
    assert_true(
        _count_color(c, WHITE) < 300 * 220, "something was drawn over the page"
    )


def test_contour_dtype_overload_matches_the_float64_path() raises:
    var zf = List[List[Float64]]()
    var zi = List[List[Int]]()
    for r in range(6):
        var rowf = List[Float64]()
        var rowi = List[Int]()
        for c in range(7):
            var v = (r * 7 + c) % 5
            rowf.append(Float64(v))
            rowi.append(v)
        zf.append(rowf^)
        zi.append(rowi^)

    var a = render_svg(contour(zf, level_count=3, width=250, height=180))
    var b = render_svg(contour(zi, level_count=3, width=250, height=180))
    assert_equal(
        a.to_string(), b.to_string(), "List[Int] matches List[Float64]"
    )


def test_render_contour_raises_on_a_ragged_grid() raises:
    var z = List[List[Float64]]()
    var r0 = List[Float64]()
    r0.append(1.0)
    r0.append(2.0)
    z.append(r0^)
    var r1 = List[Float64]()
    r1.append(3.0)
    z.append(r1^)
    with assert_raises():
        _ = render(contour(z, width=200, height=150))


def test_render_contour_raises_on_a_grid_too_small_to_have_cells() raises:
    var z = List[List[Float64]]()
    var only = List[Float64]()
    only.append(1.0)
    only.append(2.0)
    z.append(only^)
    with assert_raises():
        _ = render(contour(z, width=200, height=150))


def test_render_contour_raises_on_non_positive_level_count() raises:
    var z = _ramp_grid(4, 4)
    with assert_raises():
        _ = render(contour(z, level_count=0, width=200, height=150))


# ---------------------------------------------------------------
# Mark.CONTOURF (#260)
# ---------------------------------------------------------------


def _one_cell(
    a: Float64, b: Float64, cc: Float64, d: Float64
) -> List[List[Float64]]:
    """A single-cell grid with the four corners in `_append_above_region`'s
    own rotation: `a` at (col 0, row 0), `b` at (col 1, row 0), `cc` at
    (col 1, row 1), `d` at (col 0, row 1).
    """
    var z = List[List[Float64]]()
    var r0 = List[Float64]()
    r0.append(a)
    r0.append(b)
    z.append(r0^)
    var r1 = List[Float64]()
    r1.append(d)
    r1.append(cc)
    z.append(r1^)
    return z^


def _above_subpaths(
    z: List[List[Float64]], rows: Int, cols: Int, level: Float64
) raises -> Int:
    var unit_x = LinearScale(0.0, 1.0, 0.0, 100.0)
    var unit_y = LinearScale(0.0, 1.0, 0.0, 100.0)
    var path = Path()
    return _append_above_region(path, z, rows, cols, level, unit_x, unit_y)


def test_contourf_fills_whole_cells_and_skips_empty_ones() raises:
    """A cell entirely above the level is one sub-path; entirely below is
    none. A 4x4 grid all above is one per cell, not one per grid.
    """
    assert_equal(
        _above_subpaths(_one_cell(1.0, 1.0, 1.0, 1.0), 2, 2, 0.0),
        1,
        "a fully-above cell fills once",
    )
    assert_equal(
        _above_subpaths(_one_cell(-1.0, -1.0, -1.0, -1.0), 2, 2, 0.0),
        0,
        "a fully-below cell fills nothing",
    )

    var z = List[List[Float64]]()
    for _ in range(4):
        var row = List[Float64]()
        for _ in range(4):
            row.append(10.0)
        z.append(row^)
    assert_equal(
        _above_subpaths(z, 4, 4, 0.0), 9, "one sub-path per cell, 3x3 cells"
    )


def test_contourf_saddle_splits_only_when_the_center_is_below() raises:
    """The subtle case. Diagonal corners above, the other two below: if
    the cell center is above, the region is one shape joined through the
    middle; if it is below, it is two disjoint corner triangles and the
    middle must stay empty.

    Emitting one polygon in the second case would wrongly paint the
    middle -- the walk that is right for the other twelve cases is wrong
    here, which is why the branch exists.
    """
    # center = (1 - 5 + 1 - 5)/4 = -2, below: two triangles.
    assert_equal(
        _above_subpaths(_one_cell(1.0, -5.0, 1.0, -5.0), 2, 2, 0.0),
        2,
        "center below splits the saddle into two triangles",
    )
    # center = (5 - 1 + 5 - 1)/4 = +2, above: one joined region.
    assert_equal(
        _above_subpaths(_one_cell(5.0, -1.0, 5.0, -1.0), 2, 2, 0.0),
        1,
        "center above joins the saddle through the middle",
    )
    # The mirrored saddle (b/d above) behaves the same way.
    assert_equal(
        _above_subpaths(_one_cell(-5.0, 1.0, -5.0, 1.0), 2, 2, 0.0),
        2,
        "the mirrored saddle also splits when its center is below",
    )


def test_render_contourf_paints_bands_in_level_order() raises:
    """On a ramp `z = c`, the bands run left to right in level order, so
    a pixel on the left sits in a lower band than one on the right and
    the two differ. Painting back to front is what makes that hold.
    """
    var z = List[List[Float64]]()
    for _ in range(8):
        var row = List[Float64]()
        for c in range(21):
            row.append(Float64(c))
        z.append(row^)

    var c = render(
        contourf(
            z,
            level_count=4,
            theme=Theme(show_gridlines=False),
            width=400,
            height=300,
        )
    )
    var left = c.get_pixel(80, 150)
    var right = c.get_pixel(360, 150)
    assert_true(
        left.r != right.r or left.g != right.g or left.b != right.b,
        "the low and high ends of the ramp are in different bands",
    )


def test_render_contourf_leaves_no_unpainted_gaps_inside_the_plot() raises:
    """Every band paints over the last, and the lowest band covers the
    whole rect, so no pixel inside the plot area keeps the page color --
    a gap would mean a cell's region was missed.
    """
    var z = List[List[Float64]]()
    for r in range(12):
        var row = List[Float64]()
        for c in range(12):
            row.append(Float64(r * c % 7))
        z.append(row^)

    var c = render(
        contourf(
            z,
            level_count=5,
            theme=Theme(show_gridlines=False),
            width=360,
            height=280,
        )
    )
    var unpainted = 0
    for y in range(120, 180):
        for x in range(120, 260):
            var p = c.get_pixel(x, y)
            if p.r == WHITE.r and p.g == WHITE.g and p.b == WHITE.b:
                unpainted += 1
    assert_equal(unpainted, 0, "no page-colored pixels inside the plot")


def test_render_contourf_svg_fills_one_path_per_level() raises:
    """Each level is a single filled path of per-cell sub-paths, not one
    path per cell -- filling per cell would leave an anti-aliased seam at
    every shared edge.
    """
    var z = List[List[Float64]]()
    for r in range(6):
        var row = List[Float64]()
        for c in range(6):
            row.append(Float64(r + c))
        z.append(row^)

    var levels: List[Float64] = [3.0, 6.0]
    var svg = render_svg(
        contourf(
            z,
            levels=levels,
            theme=Theme(show_gridlines=False),
            width=320,
            height=240,
        )
    ).to_string()
    assert_equal(
        svg.count('fill-rule="evenodd"'), 0, "bands fill nonzero, not even-odd"
    )
    # One <path> per level; the background band is a <rect>.
    assert_equal(svg.count("<path"), 2, "one filled path per level")


def test_contourf_flat_grid_renders_without_raising() raises:
    var z = List[List[Float64]]()
    for _ in range(3):
        var row = List[Float64]()
        for _ in range(3):
            row.append(4.0)
        z.append(row^)
    var svg = render_svg(contourf(z, width=200, height=150)).to_string()
    assert_true("<svg" in svg, "a flat field still renders its frame")


def test_contourf_dtype_overload_matches_the_float64_path() raises:
    var zf = List[List[Float64]]()
    var zi = List[List[Int]]()
    for r in range(6):
        var rowf = List[Float64]()
        var rowi = List[Int]()
        for c in range(7):
            var v = (r * 7 + c) % 5
            rowf.append(Float64(v))
            rowi.append(v)
        zf.append(rowf^)
        zi.append(rowi^)
    var a = render_svg(contourf(zf, level_count=3, width=250, height=180))
    var b = render_svg(contourf(zi, level_count=3, width=250, height=180))
    assert_equal(
        a.to_string(), b.to_string(), "List[Int] matches List[Float64]"
    )


def test_render_contourf_raises_on_a_ragged_grid() raises:
    var z = List[List[Float64]]()
    var r0 = List[Float64]()
    r0.append(1.0)
    r0.append(2.0)
    z.append(r0^)
    var r1 = List[Float64]()
    r1.append(3.0)
    z.append(r1^)
    with assert_raises():
        _ = render(contourf(z, width=200, height=150))


def test_render_contourf_raises_on_non_positive_level_count() raises:
    var z = List[List[Float64]]()
    for _ in range(3):
        var row = List[Float64]()
        for c in range(3):
            row.append(Float64(c))
        z.append(row^)
    with assert_raises():
        _ = render(contourf(z, level_count=0, width=200, height=150))


# ---------------------------------------------------------------
# Delaunay triangulation and Mark.TRICONTOUR (#261)
# ---------------------------------------------------------------


def test_delaunay_triangulates_simple_point_sets() raises:
    """A square is two triangles; an n x n grid of points is
    `2 * (n-1)^2`, the count for a triangulated rectangle.
    """
    var sx: List[Float64] = [0.0, 1.0, 1.0, 0.0]
    var sy: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    assert_equal(delaunay(sx, sy).count(), 2, "a square is two triangles")

    var gx = List[Float64]()
    var gy = List[Float64]()
    for r in range(5):
        for c in range(5):
            gx.append(Float64(c))
            gy.append(Float64(r))
    assert_equal(
        delaunay(gx, gy).count(), 32, "a 5x5 grid is 2 * 4 * 4 triangles"
    )


def test_delaunay_handles_the_degenerate_inputs() raises:
    """Fewer than three points, all-collinear, and all-identical each
    triangulate to nothing rather than raising -- a caller contouring
    them draws an empty frame, which is what the data supports. A
    duplicate alongside real points is simply dropped.
    """
    var two_x: List[Float64] = [0.0, 1.0]
    var two_y: List[Float64] = [0.0, 1.0]
    assert_equal(delaunay(two_x, two_y).count(), 0, "two points")

    var col_x: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var col_y: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    assert_equal(delaunay(col_x, col_y).count(), 0, "collinear points")

    var same_x: List[Float64] = [2.0, 2.0, 2.0]
    var same_y: List[Float64] = [3.0, 3.0, 3.0]
    assert_equal(delaunay(same_x, same_y).count(), 0, "identical points")

    var dup_x: List[Float64] = [0.0, 1.0, 0.5, 0.5]
    var dup_y: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    assert_equal(delaunay(dup_x, dup_y).count(), 1, "a duplicate is dropped")

    with assert_raises():
        var short_y: List[Float64] = [0.0]
        _ = delaunay(col_x, short_y)


def test_delaunay_satisfies_the_empty_circumcircle_property() raises:
    """The defining property, swept over random point sets: no vertex
    lies inside any triangle's circumcircle. Counting triangles says
    nothing about this -- a wrong triangulation of the same points has
    the same count.
    """
    var rng = Lcg(20260905)
    var violations = 0
    var checks = 0
    for _ in range(12):
        var n = 8 + rng.below(20)
        var xs = List[Float64]()
        var ys = List[Float64]()
        for _ in range(n):
            xs.append(rng.uniform(-50.0, 50.0))
            ys.append(rng.uniform(-50.0, 50.0))
        var t = delaunay(xs, ys)
        for k in range(t.count()):
            var i0 = t.tri[3 * k]
            var i1 = t.tri[3 * k + 1]
            var i2 = t.tri[3 * k + 2]
            for pt in range(len(xs)):
                if pt == i0 or pt == i1 or pt == i2:
                    continue
                checks += 1
                if _in_circumcircle(
                    xs[i0],
                    ys[i0],
                    xs[i1],
                    ys[i1],
                    xs[i2],
                    ys[i2],
                    xs[pt],
                    ys[pt],
                ):
                    violations += 1
    assert_true(checks > 1000, "the sweep actually checked something")
    assert_equal(violations, 0, "no vertex inside any circumcircle")


def test_tricontour_traces_a_linear_ramp_as_a_straight_line() raises:
    """On scattered points carrying `z = x`, the isoline for 5.0 is the
    vertical line x = 5 -- every crossing is an exact interpolation along
    a triangle edge, so every point lands on it regardless of how the
    triangulation happened to connect the samples.
    """
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var rng = Lcg(4242)
    for _ in range(120):
        var px = rng.uniform(0.0, 10.0)
        var py = rng.uniform(0.0, 10.0)
        xs.append(px)
        ys.append(py)
        zs.append(px)

    var t = delaunay(xs, ys)
    var segs = _tricontour_segments(t, zs, 5.0)
    assert_true(len(segs.ea) > 0, "the level crosses the field")
    for i in range(len(segs.ea)):
        assert_true(
            abs(segs.ax[i] - 5.0) < 1e-9 and abs(segs.bx[i] - 5.0) < 1e-9,
            "every crossing sits on x = 5",
        )


def test_tricontour_emits_at_most_one_segment_per_triangle() raises:
    """A triangle has only two cases: all three corners on one side of
    the level, or exactly one alone -- so a crossed triangle yields one
    segment and there is no saddle to resolve. That is the whole reason
    scattered contouring goes through a triangulation.
    """
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var rng = Lcg(99)
    for _ in range(80):
        var px = rng.uniform(0.0, 10.0)
        var py = rng.uniform(0.0, 10.0)
        xs.append(px)
        ys.append(py)
        zs.append(px + py)

    var t = delaunay(xs, ys)
    var segs = _tricontour_segments(t, zs, 10.0)
    assert_true(
        len(segs.ea) <= t.count(),
        "never more segments than triangles ("
        + String(len(segs.ea))
        + " vs "
        + String(t.count())
        + ")",
    )


def test_tricontour_segments_chain_into_whole_isolines() raises:
    """Segment ends carry the same kind of integer edge id the grid
    contour uses, so `_chain_segments` joins them unchanged: a chain of n
    segments is n+1 points, so the totals must come to segments + lines.
    """
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var rng = Lcg(31337)
    for _ in range(150):
        var px = rng.uniform(-6.0, 6.0)
        var py = rng.uniform(-6.0, 6.0)
        xs.append(px)
        ys.append(py)
        zs.append(-(px * px + py * py))

    var t = delaunay(xs, ys)
    var segs = _tricontour_segments(t, zs, -16.0)
    var lines = _chain_segments(segs)
    assert_true(len(lines) > 0, "the level produced at least one isoline")
    var points = 0
    for k in range(len(lines)):
        points += len(lines[k].xs)
    assert_equal(
        points, len(segs.ea) + len(lines), "every segment used exactly once"
    )


def test_render_tricontour_draws_ink_and_one_path_per_isoline() raises:
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var rng = Lcg(777)
    for _ in range(150):
        var px = rng.uniform(0.0, 10.0)
        var py = rng.uniform(0.0, 10.0)
        xs.append(px)
        ys.append(py)
        zs.append(px * py)

    var plot = tricontour(xs, ys, zs, level_count=4, width=360, height=280)
    var svg = render_svg(plot).to_string()
    assert_true(svg.count('fill="none"') > 0, "isolines are stroked paths")

    var c = render(plot)
    assert_true(
        _count_color(c, WHITE) < 360 * 280, "something was drawn on the page"
    )


def test_render_tricontourf_fills_far_more_than_tricontour_strokes() raises:
    """The filled variant covers area where the line variant covers only
    the isolines, over the same samples and the same levels."""
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var rng = Lcg(777)
    for _ in range(150):
        var px = rng.uniform(0.0, 10.0)
        var py = rng.uniform(0.0, 10.0)
        xs.append(px)
        ys.append(py)
        zs.append(px * py)

    var lines = render(
        tricontour(xs, ys, zs, level_count=4, width=360, height=280)
    )
    var filled = render(
        tricontourf(xs, ys, zs, level_count=4, width=360, height=280)
    )
    var line_ink = 360 * 280 - _count_color(lines, WHITE)
    var fill_ink = 360 * 280 - _count_color(filled, WHITE)
    assert_true(
        fill_ink > line_ink * 5,
        (
            "a filled contour covers area, not just its isolines (filled "
            + String(fill_ink)
            + " vs stroked "
            + String(line_ink)
            + ")"
        ),
    )


def test_render_tricontourf_fills_solidly_with_no_seams() raises:
    """Adjacent triangles are emitted as subpaths of one nonzero fill, so
    the edges they share are interior and leave no pale seam.

    Filling each triangle separately antialiases every shared edge twice,
    and two half-covered pixels over the background do not add up to a
    covered one -- the fill comes out webbed with background-colored
    lines. Asserted by counting how many pixels inside the filled region
    are lighter than both of their horizontal neighbours, which is what
    such a seam looks like and what a smooth band ramp does not produce.

    Only pixels whose neighbours are *colored* count: the axis line
    and the antialiased tick labels are gray one-pixel features that
    would otherwise read as seams, and they are furniture, not fill.
    """
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    var rng = Lcg(4242)
    for _ in range(300):
        var px = rng.uniform(0.0, 10.0)
        var py = rng.uniform(0.0, 10.0)
        xs.append(px)
        ys.append(py)
        zs.append(-((px - 5.0) ** 2) - (py - 5.0) ** 2)

    var c = render(
        tricontourf(xs, ys, zs, level_count=6, width=320, height=240)
    )
    var seams = 0
    for y in range(1, c.height - 1):
        for x in range(1, c.width - 1):
            var left = c.get_pixel(x - 1, y)
            var mid = c.get_pixel(x, y)
            var right = c.get_pixel(x + 1, y)
            if left.r == 255 and left.g == 255 and left.b == 255:
                continue
            if right.r == 255 and right.g == 255 and right.b == 255:
                continue
            # Gray means furniture (the axis line, an antialiased tick
            # label), not fill.
            if abs(Int(left.r) - Int(left.b)) < 6:
                continue
            if abs(Int(right.r) - Int(right.b)) < 6:
                continue
            # A one-pixel-wide lighter notch between two darker
            # neighbours that match each other: a seam, not a band edge.
            if (
                Int(mid.r) > Int(left.r) + 8
                and Int(mid.r) > Int(right.r) + 8
                and abs(Int(left.r) - Int(right.r)) < 4
            ):
                seams += 1
    assert_equal(seams, 0, "no pale one-pixel seams inside the fill")


def test_tricontour_dtype_overload_matches_the_float64_path() raises:
    var xf = List[Float64]()
    var yf = List[Float64]()
    var zf = List[Float64]()
    var xi = List[Int]()
    var yi = List[Int]()
    var zi = List[Int]()
    for i in range(40):
        var a = i % 7
        var b = (i * 3) % 8
        xf.append(Float64(a))
        yf.append(Float64(b))
        zf.append(Float64(a + b))
        xi.append(a)
        yi.append(b)
        zi.append(a + b)
    var p = render_svg(
        tricontour(xf, yf, zf, level_count=3, width=250, height=180)
    )
    var q = render_svg(
        tricontour(xi, yi, zi, level_count=3, width=250, height=180)
    )
    assert_equal(
        p.to_string(), q.to_string(), "List[Int] matches List[Float64]"
    )


def test_render_tricontour_raises_on_mismatched_lengths() raises:
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [0.0, 1.0]
    var zs: List[Float64] = [0.0, 1.0, 2.0]
    with assert_raises():
        _ = render(tricontour(xs, ys, zs, width=200, height=150))


def test_render_tricontour_raises_on_empty_data() raises:
    var e = List[Float64]()
    with assert_raises():
        _ = render(tricontour(e, e, e, width=200, height=150))


def test_render_tricontour_collinear_samples_render_an_empty_frame() raises:
    """Collinear samples triangulate to nothing, so the chart draws its
    axes and no isolines rather than raising."""
    var xs: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var ys: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var zs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var svg = render_svg(
        tricontour(xs, ys, zs, width=240, height=200)
    ).to_string()
    assert_true("<svg" in svg, "the frame still renders")


# ---------------------------------------------------------------
# Mark.TRIPLOT and Mark.TRIPCOLOR (#344)
# ---------------------------------------------------------------


def test_triplot_edges_are_deduplicated_across_shared_triangles() raises:
    """Every interior edge belongs to two triangles, so emitting three
    edges per triangle yields most of them twice.

    A square is two triangles: four hull edges plus the one diagonal they
    share, so five distinct edges and not six. A 5x5 grid of points is 32
    triangles (`test_delaunay_triangulates_simple_point_sets`) with 16
    edges on its hull, and 3 * 32 = 96 counts every interior edge twice
    and every hull edge once, so there are (96 + 16) / 2 = 56 distinct
    ones and not 96.

    Both numbers discriminate: an undeduplicated walk returns exactly 6
    and exactly 96, which is what the counts are chosen against.
    """
    var sx: List[Float64] = [0.0, 1.0, 1.0, 0.0]
    var sy: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    var square = _triplot_edges(delaunay(sx, sy))
    assert_equal(
        len(square[0]), 5, "a square's two triangles share their diagonal"
    )
    assert_equal(len(square[1]), 5, "both endpoint lists stay in step")

    var gx = List[Float64]()
    var gy = List[Float64]()
    for r in range(5):
        for c in range(5):
            gx.append(Float64(c))
            gy.append(Float64(r))
    var grid = _triplot_edges(delaunay(gx, gy))
    assert_equal(len(grid[0]), 56, "a 5x5 grid has 56 distinct edges")


def test_triplot_edges_name_real_vertex_pairs() raises:
    """Deduplication must not lose the endpoints: every edge returned has
    to be an edge of some triangle, both ends in range and distinct.

    The count test above passes just as well if the two lists drift out
    of alignment, so this checks the pairs themselves against the
    triangles they came from.
    """
    var rng = Lcg(7788)
    var xs = List[Float64]()
    var ys = List[Float64]()
    for _ in range(40):
        xs.append(rng.uniform(-10.0, 10.0))
        ys.append(rng.uniform(-10.0, 10.0))
    var t = delaunay(xs, ys)
    var edges = _triplot_edges(t)
    assert_true(len(edges[0]) > 0, "the sweep has edges to check")
    for i in range(len(edges[0])):
        var a = edges[0][i]
        var b = edges[1][i]
        assert_true(a != b, "an edge joins two different vertices")
        assert_true(
            a >= 0 and a < len(xs) and b >= 0 and b < len(xs),
            "endpoints index the input points",
        )
        var found = False
        for k in range(t.count()):
            var v0 = t.tri[3 * k]
            var v1 = t.tri[3 * k + 1]
            var v2 = t.tri[3 * k + 2]
            if (
                (a == v0 and b == v1)
                or (a == v1 and b == v2)
                or (a == v2 and b == v0)
            ):
                found = True
                break
        assert_true(found, "every returned edge belongs to a triangle")


def test_render_triplot_strokes_the_whole_mesh_as_one_path() raises:
    """The four corners of a square triangulate into two triangles, and
    the mesh must reach the SVG as a single stroked `<path>` whose `d`
    holds one `M` per distinct edge -- five, not six.

    This is the render-level half of the dedup assertion: `_triplot_edges`
    could be right while the render walked `tri.tri` itself. Stroking the
    shared diagonal twice would put a sixth `M` in the same `d`, and
    stroking each edge as its own path would make the `<path>` count 5.
    """
    var x: List[Float64] = [0.0, 1.0, 1.0, 0.0]
    var y: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    var svg = render_svg(triplot(x, y, width=240, height=200)).to_string()

    assert_equal(_count_tag(svg, "path"), 1, "one path for the whole mesh")
    var start = svg.find('<path d="')
    assert_true(start != -1, "the mesh path is in the document")
    var end = svg.find('"', start + 9)
    var d = String(svg[byte = start + 9 : end])
    assert_equal(d.count("M"), 5, "five distinct edges, each moved to once")
    assert_equal(d.count("L"), 5, "and a line drawn for each of them")
    assert_equal(_count_tag(svg, "circle"), 4, "a dot at each sample")


def test_render_triplot_show_points_controls_the_vertex_dots() raises:
    """`show_points=False` drops the dots and nothing else: the mesh path
    is byte-identical, and the only difference in the document is the
    four circles.
    """
    var x: List[Float64] = [0.0, 1.0, 1.0, 0.0]
    var y: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    var with_dots = render_svg(triplot(x, y, width=240, height=200)).to_string()
    var without = render_svg(
        triplot(x, y, show_points=False, width=240, height=200)
    ).to_string()

    assert_equal(_count_tag(without, "circle"), 0, "no dots when asked")
    assert_equal(_count_tag(with_dots, "circle"), 4, "dots by default")
    assert_equal(
        _count_tag(without, "path"), 1, "the mesh is still drawn without dots"
    )

    var a = with_dots.find('<path d="')
    var b = without.find('<path d="')
    assert_equal(
        String(with_dots[byte = a : with_dots.find('"', a + 9)]),
        String(without[byte = b : without.find('"', b + 9)]),
        "the mesh itself is unchanged by the dots",
    )

    var lit = render(triplot(x, y, width=240, height=200))
    var bare = render(triplot(x, y, show_points=False, width=240, height=200))
    var mark = Theme.default().mark_color
    assert_true(
        _count_color(lit, mark) > _count_color(bare, mark),
        "the dots add ink in the mark color",
    )


def test_render_triplot_still_shows_samples_that_support_no_triangle() raises:
    """Collinear samples triangulate to nothing. The chart draws the
    points anyway rather than raising or going blank, so it says "here
    are your samples, they support no mesh".

    Discriminating because the no-mesh case is exactly where an early
    return would skip the dots too: with `show_points=False` the same
    data leaves no mark-colored ink at all, so the count below is the
    dots and only the dots.
    """
    var xs: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var ys: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var svg = render_svg(triplot(xs, ys, width=240, height=200)).to_string()
    assert_true("<svg" in svg, "the frame still renders")
    assert_equal(_count_tag(svg, "path"), 0, "no mesh to draw")
    assert_equal(_count_tag(svg, "circle"), 4, "the samples are still shown")

    var mark = Theme.default().mark_color
    var dotted = render(triplot(xs, ys, width=240, height=200))
    var bare = render(triplot(xs, ys, show_points=False, width=240, height=200))
    assert_true(_count_color(dotted, mark) > 0, "the dots are real ink")
    assert_equal(
        _count_color(bare, mark), 0, "and they are the only ink there is"
    )


def test_render_triplot_raises_on_mismatched_lengths() raises:
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [0.0, 1.0]
    with assert_raises():
        _ = render(triplot(xs, ys, width=200, height=150))


def test_render_triplot_raises_on_empty_data() raises:
    var e = List[Float64]()
    with assert_raises():
        _ = render(triplot(e, e, width=200, height=150))


def test_triplot_dtype_overload_matches_the_float64_path() raises:
    var xf = List[Float64]()
    var yf = List[Float64]()
    var xi = List[Int]()
    var yi = List[Int]()
    for i in range(40):
        var a = i % 7
        var b = (i * 3) % 8
        xf.append(Float64(a))
        yf.append(Float64(b))
        xi.append(a)
        yi.append(b)
    assert_equal(
        render_svg(triplot(xf, yf, width=250, height=180)).to_string(),
        render_svg(triplot(xi, yi, width=250, height=180)).to_string(),
        "List[Int] matches List[Float64]",
    )


def test_triangle_means_average_all_three_vertex_values() raises:
    """Three points make one triangle, so its flat-shading value is the
    mean of all three `z` -- (1 + 2 + 6) / 3 = 3.

    The three inputs are deliberately unequal and their mean is none of
    them, so picking any single vertex instead of averaging gives 1, 2 or
    6 and fails here. `_triangle_means` is the piece the render's whole
    color mapping hangs off, and the render-level test below no longer
    calls it, so this is where it is pinned.
    """
    var xs: List[Float64] = [0.0, 4.0, 1.0]
    var ys: List[Float64] = [0.0, 0.0, 3.0]
    var zs: List[Float64] = [1.0, 2.0, 6.0]
    var t = delaunay(xs, ys)
    assert_equal(t.count(), 1, "three points are one triangle")
    var means = _triangle_means(t, zs)
    assert_equal(len(means), 1, "one value per triangle")
    assert_equal(means[0], 3.0, "the mean of 1, 2 and 6")


def test_tripcolor_paints_each_triangle_its_own_vertex_mean() raises:
    """Flat shading: a triangle's color is `ColorScale.from_theme` at the
    mean of its three vertex values, over the range of those means.

    Checked against a render rather than against the helper alone --
    every triangle's expected color has to actually appear in the raster,
    and the interior of a filled triangle is solid, so the match is
    exact. Ten well-spread samples keep the triangles large enough to
    have an interior.

    Discriminating three ways at once. Coloring by a vertex value instead
    of the mean, or normalizing over `z`'s own range instead of the
    means', or building a ramp other than the theme's, each moves nearly
    every one of these colors -- and the assertion is equality on all of
    them, not a tolerance.
    """
    var xs: List[Float64] = [0.0, 5.0, 10.0, 1.0, 9.0, 5.0, 0.0, 10.0, 3.0, 7.0]
    var ys: List[Float64] = [0.0, 0.0, 0.0, 4.0, 4.0, 6.5, 10.0, 10.0, 8.0, 8.0]
    var zs = List[Float64]()
    for v in xs:
        zs.append(v)

    var t = delaunay(xs, ys)
    assert_true(t.count() >= 6, "the sample set makes a real mesh")
    # Averaged here rather than through `_triangle_means`: taking the
    # expectation from the function under test made this pass for *any*
    # definition of a triangle's value, which was checked by breaking
    # that function to return its first vertex -- every assertion still
    # passed. Now it does not.
    var means = List[Float64]()
    for k in range(t.count()):
        means.append(
            (zs[t.tri[3 * k]] + zs[t.tri[3 * k + 1]] + zs[t.tri[3 * k + 2]])
            / 3.0
        )
    var lo = means[0]
    var hi = means[0]
    for v in means:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    assert_true(hi > lo, "the means actually span a range")
    var scale = ColorScale.from_theme(Theme.default(), lo, hi)

    var c = render(tripcolor(xs, ys, zs, width=520, height=400))
    for k in range(t.count()):
        var want = scale.color_at(means[k])
        assert_true(
            _count_color(c, want) > 0,
            (
                "triangle "
                + String(k)
                + " (mean "
                + String(means[k])
                + ") is painted its own mean's color"
            ),
        )


def test_tripcolor_reads_the_theme_color_ramp_end_to_end() raises:
    """A two-stop `Theme.color_ramp` puts its first color on the lowest
    triangle mean and its last on the highest, so both endpoints appear
    in the render exactly.

    One assertion covering two things that could each be wrong on their
    own. Building a ramp of this mark's own instead of going through
    `ColorScale.from_theme` would ignore `color_ramp` entirely and paint
    the theme's default blue scale. Normalizing over the vertex values
    rather than the triangle means would leave *no* triangle at either
    endpoint, since averaging pulls every mean strictly inside `z`'s
    range -- so neither pure color would appear at all.

    Red and blue rather than black and white: a white extreme is
    indistinguishable from the page, so counting it would prove nothing.
    They also cannot be reached by the theme's own blue scale or by any
    blend of it with the page -- those all have `g <= b` -- so finding
    the low stop at all is itself proof the ramp was read.
    """
    var xs: List[Float64] = [0.0, 5.0, 10.0, 1.0, 9.0, 5.0, 0.0, 10.0, 3.0, 7.0]
    var ys: List[Float64] = [0.0, 0.0, 0.0, 4.0, 4.0, 6.5, 10.0, 10.0, 8.0, 8.0]
    var zs = List[Float64]()
    for v in xs:
        zs.append(v)

    var low = Color(220, 20, 20)
    var high = Color(20, 20, 220)
    var stops: List[Color] = [low, high]
    var theme = Theme(color_ramp=ColorRamp(stops))
    var c = render(tripcolor(xs, ys, zs, theme=theme, width=520, height=400))

    assert_true(
        _count_color(c, low) > 0, "the lowest triangle mean gets the low stop"
    )
    assert_true(_count_color(c, high) > 0, "the highest gets the high stop")


def test_tripcolor_lets_no_background_through_between_triangles() raises:
    """The seam property, measured rather than eyeballed: render the same
    mesh twice, once on a white page and once on a black one, and compare
    the interior pixels.

    Adjacent triangles filled independently each antialias the edge they
    share, and two half-covered pixels composited over the page do not
    add up to a covered one -- the fill comes out webbed with pale lines
    (#315, #318, #327, #359, #360). A pixel where that happens shows some
    of the page, so it *changes* when the page changes; a pixel that is
    genuinely solid cannot.

    That is a sharper instrument than looking for pale pixels: it does
    not care what colors the triangles are, so a legitimately light
    sliver between two darker neighbors never reads as a defect, and a
    seam of any color is caught. Against a 255-level swing in what is
    underneath, the worst interior pixel moves 1 level with
    `_SEAM_STROKE_WIDTH` in place and 86 without it, so the bound below
    is nowhere near either.

    Gridlines are off because they are drawn on the page before the
    fills, so they would change with it too and be counted as bleed. The
    four corners are pinned so the hull is the whole square and the
    sampled middle is well inside it.
    """
    var xs: List[Float64] = [0.0, 10.0, 10.0, 0.0]
    var ys: List[Float64] = [0.0, 0.0, 10.0, 10.0]
    var rng = Lcg(20260907)
    for _ in range(200):
        xs.append(rng.uniform(0.0, 10.0))
        ys.append(rng.uniform(0.0, 10.0))
    var zs = List[Float64]()
    for i in range(len(xs)):
        zs.append(-((xs[i] - 5.0) ** 2) - (ys[i] - 5.0) ** 2)

    var w = 300
    var h = 220
    var on_white = render(
        tripcolor(
            xs,
            ys,
            zs,
            width=w,
            height=h,
            theme=Theme(
                background=WHITE, show_gridlines=False, raster_supersample=1
            ),
        )
    )
    var on_black = render(
        tripcolor(
            xs,
            ys,
            zs,
            width=w,
            height=h,
            theme=Theme(
                background=BLACK, show_gridlines=False, raster_supersample=1
            ),
        )
    )

    var worst = 0
    var checked = 0
    for y in range(h // 3, 2 * h // 3):
        for x in range(w // 3, 2 * w // 3):
            checked += 1
            var a = on_white.get_pixel(x, y)
            var b = on_black.get_pixel(x, y)
            var d = abs(Int(a.r) - Int(b.r))
            if abs(Int(a.g) - Int(b.g)) > d:
                d = abs(Int(a.g) - Int(b.g))
            if abs(Int(a.b) - Int(b.b)) > d:
                d = abs(Int(a.b) - Int(b.b))
            if d > worst:
                worst = d
    assert_true(checked > 4000, "the sweep actually looked at the fill")
    assert_true(
        worst <= 2,
        (
            "no page shows through between the triangles (worst pixel moved "
            + String(worst)
            + " levels of 255 when the page went white to black)"
        ),
    )


def test_tripcolor_covers_the_interior_that_triplot_only_outlines() raises:
    """With the four corners of the sample square pinned, the
    triangulation's hull is the whole data rect, so `tripcolor` has to
    leave *no* page showing anywhere inside it -- every pixel of the
    sampled interior box is painted. `triplot` over the same points
    covers only its edges, so most of that same box stays the page color.

    An ink *ratio* was tried first and rejected: counting non-white
    pixels over the whole canvas counts the gridlines, axis and tick
    labels too, which both charts have equally, so the ratio was
    dominated by furniture and came out near 2 either way -- it would
    have passed on a fill riddled with holes. Requiring exactly zero
    unpainted pixels in a box that is inside the hull does not.

    The box is well inside the plot rect (x 60..300, y 20..230 at this
    size, with `_data_extent`'s padding pulling the hull in a further
    5%), so it never reaches the antialiased hull boundary.
    """
    var xs: List[Float64] = [0.0, 10.0, 10.0, 0.0]
    var ys: List[Float64] = [0.0, 0.0, 10.0, 10.0]
    var rng = Lcg(515)
    for _ in range(120):
        xs.append(rng.uniform(0.0, 10.0))
        ys.append(rng.uniform(0.0, 10.0))
    var zs = List[Float64]()
    for i in range(len(xs)):
        zs.append(xs[i] * ys[i])

    var filled = render(tripcolor(xs, ys, zs, width=360, height=280))
    var mesh = render(triplot(xs, ys, width=360, height=280))

    var fill_gaps = 0
    var mesh_gaps = 0
    var cells = 0
    for y in range(60, 200):
        for x in range(100, 300):
            cells += 1
            var f = filled.get_pixel(x, y)
            if f.r == 255 and f.g == 255 and f.b == 255:
                fill_gaps += 1
            var m = mesh.get_pixel(x, y)
            if m.r == 255 and m.g == 255 and m.b == 255:
                mesh_gaps += 1
    assert_true(cells > 20000, "the box is a real area")
    assert_equal(
        fill_gaps, 0, "tripcolor leaves no page showing inside the hull"
    )
    assert_true(
        mesh_gaps > cells // 2,
        (
            "triplot only outlines it ("
            + String(mesh_gaps)
            + " of "
            + String(cells)
            + " still the page)"
        ),
    )


def test_render_tripcolor_raises_on_mismatched_lengths() raises:
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [0.0, 1.0, 2.0]
    var zs: List[Float64] = [0.0, 1.0]
    with assert_raises():
        _ = render(tripcolor(xs, ys, zs, width=200, height=150))


def test_render_tripcolor_raises_on_empty_data() raises:
    var e = List[Float64]()
    with assert_raises():
        _ = render(tripcolor(e, e, e, width=200, height=150))


def test_render_tripcolor_collinear_samples_render_an_empty_frame() raises:
    """Collinear samples triangulate to nothing, so the chart draws its
    axes and no fills rather than raising."""
    var xs: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var ys: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var zs: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var svg = render_svg(
        tripcolor(xs, ys, zs, width=240, height=200)
    ).to_string()
    assert_true("<svg" in svg, "the frame still renders")
    assert_equal(_count_tag(svg, "path"), 0, "and nothing is filled")


def test_tripcolor_dtype_overload_matches_the_float64_path() raises:
    var xf = List[Float64]()
    var yf = List[Float64]()
    var zf = List[Float64]()
    var xi = List[Int]()
    var yi = List[Int]()
    var zi = List[Int]()
    for i in range(40):
        var a = i % 7
        var b = (i * 3) % 8
        xf.append(Float64(a))
        yf.append(Float64(b))
        zf.append(Float64(a + b))
        xi.append(a)
        yi.append(b)
        zi.append(a + b)
    assert_equal(
        render_svg(tripcolor(xf, yf, zf, width=250, height=180)).to_string(),
        render_svg(tripcolor(xi, yi, zi, width=250, height=180)).to_string(),
        "List[Int] matches List[Float64]",
    )


def test_named_color_works_as_a_theme_mark_color_through_a_real_render() raises:
    # A named color reaches the renderer like any other Color literal. A
    # non-zero count rather than a hand-derived pixel; bar() layout is
    # covered in its own tests.
    #
    # Lives here rather than in test_primitives.mojo with the rest of
    # colors.mojo's tests: it is the only one of them that rasterizes,
    # and this is a raster module already.
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [3.0, 5.0]
    var _hoisted1 = bar(cats, values, theme=Theme(mark_color=CORNFLOWERBLUE))
    var c = render(_hoisted1)

    assert_equal(
        _count_color(c, CORNFLOWERBLUE) > 0,
        True,
        "bar filled with a named color renders that exact color",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
