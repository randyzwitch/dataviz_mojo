"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.POINT (centering, theme
colors, color/size encoding, categorical color, SVG coordinates),
Mark.LINE (drawing, line_smoothing, _build_line_path), Mark.AREA
(fill region and smoothing), Mark.BAR (rectangles, negative values,
color_by_sign), encode_histogram(), Mark.LOLLIPOP, Mark.BOX,
Mark.CANDLESTICK, Mark.WATERFALL, and Mark.BULLET, each raster + SVG.
"""

from _test_helpers import (
    BG,
    Lcg,
    _assert_color,
    _assert_near_color,
    _bbox_of_color,
    _count_color,
)
from canvas.color import Color
from canvas.path import Path, PathOp
from dataviz import (
    CORNFLOWERBLUE,
    area,
    bar,
    barbs,
    box,
    bullet,
    candlestick,
    contour,
    contourf,
    tricontour,
    line,
    lollipop,
    scatter,
    waterfall,
)
from dataviz.barbs import _barb_counts, _barb_glyph
from dataviz.delaunay import _in_circumcircle, delaunay
from dataviz.tricontour import _tricontour_segments
from dataviz.contour import (
    _append_above_region,
    _auto_levels,
    _chain_segments,
    _contour_segments,
)
from dataviz.color_scale import default_categorical_palette
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
    # 135), radius 4, through render_svg(). Integer coordinates (from
    # round_to_int) can't drift between float implementations.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).size(400, 300)
    var svg = render_svg(plot)
    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in svg.to_string(),
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
    therefore prove nothing. Colouring by sign is what makes the two bars
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
    # pixel-centre convention rather than a pixel index, which places
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
    """`z = -(dx^2 + dy^2)` about the grid centre, so the isoline for
    `-r^2` is exactly the circle of radius `r`.
    """
    var centre = Float64(size - 1) / 2.0
    var z = List[List[Float64]]()
    for r in range(size):
        var row = List[Float64]()
        for c in range(size):
            var dx = Float64(c) - centre
            var dy = Float64(r) - centre
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


def test_contour_saddle_resolves_by_the_cell_centre() raises:
    """The two ambiguous cases: diagonal corners on the same side of the
    level. The cell centre decides which pair the isoline separates, and
    flipping the centre's sign flips the pairing.

    One cell, corners a=(0,0) b=(1,0) cc=(1,1) d=(0,1), level 0.

    With a=3, b=-1, cc=3, d=-1 the centre is +1, so the two *above*
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

    # Mirror: centre -1, so the below corners join and each above corner
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


def test_contourf_saddle_splits_only_when_the_centre_is_below() raises:
    """The subtle case. Diagonal corners above, the other two below: if
    the cell centre is above, the region is one shape joined through the
    middle; if it is below, it is two disjoint corner triangles and the
    middle must stay empty.

    Emitting one polygon in the second case would wrongly paint the
    middle -- the walk that is right for the other twelve cases is wrong
    here, which is why the branch exists.
    """
    # centre = (1 - 5 + 1 - 5)/4 = -2, below: two triangles.
    assert_equal(
        _above_subpaths(_one_cell(1.0, -5.0, 1.0, -5.0), 2, 2, 0.0),
        2,
        "centre below splits the saddle into two triangles",
    )
    # centre = (5 - 1 + 5 - 1)/4 = +2, above: one joined region.
    assert_equal(
        _above_subpaths(_one_cell(5.0, -1.0, 5.0, -1.0), 2, 2, 0.0),
        1,
        "centre above joins the saddle through the middle",
    )
    # The mirrored saddle (b/d above) behaves the same way.
    assert_equal(
        _above_subpaths(_one_cell(-5.0, 1.0, -5.0, 1.0), 2, 2, 0.0),
        2,
        "the mirrored saddle also splits when its centre is below",
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
    whole rect, so no pixel inside the plot area keeps the page colour --
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
    assert_equal(unpainted, 0, "no page-coloured pixels inside the plot")


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
