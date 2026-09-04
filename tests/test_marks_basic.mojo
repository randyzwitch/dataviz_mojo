"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.POINT (centering, theme
colors, color/size encoding, categorical color, SVG coordinates),
Mark.LINE (drawing, line_smoothing, _build_line_path), Mark.AREA
(fill region and smoothing), Mark.BAR (rectangles, negative values,
color_by_sign), encode_histogram(), Mark.LOLLIPOP, Mark.BOX,
Mark.CANDLESTICK, Mark.WATERFALL, and Mark.BULLET, each raster + SVG.
"""

from _test_helpers import BG, _assert_color, _assert_near_color, _count_color
from canvas.color import Color
from canvas.path import Path, _CLOSE, _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz import (
    area,
    bar,
    barbs,
    box,
    bullet,
    candlestick,
    line,
    lollipop,
    scatter,
    waterfall,
)
from dataviz.barbs import _barb_counts, _barb_glyph
from dataviz.color_scale import default_categorical_palette
from dataviz.colors import BLACK, WHITE
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
    # _round_to_int) can't drift between float implementations.
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
    # after move_to is _LINE_TO.
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
    # The uniform Catmull-Rom to Bezier conversion (control point =
    # endpoint +/- (next - previous)/6), reimplemented in python3 with the
    # same operation order so the Float64s match bit-for-bit, for 4 points
    # with a bend at each interior point; endpoints clamp to a one-sided
    # tangent.
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
    # A single negative bar: _zero_baseline_y_extent's domain is
    # [lo-pad, 0] with hi at exactly 0, so the baseline sits at the top of
    # the bar's rect.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted3)

    # Baseline (value 0) is the domain's unpadded top, pixel y=20; a pixel
    # just below it, inside the bar's band, is the mark color.
    _assert_color(
        c, 220, 25, t.mark_color, "just below the zero baseline, inside the bar"
    )
    # Well above the plot area entirely -- background regardless.
    _assert_color(c, 220, 5, BG, "above the plot area")


def test_render_svg_bar_mark_matches_confirmed_rect() raises:
    # Same 3-category data: bar 1's rect x=177, y=31, width=85; its bottom
    # sits on the axis line (250), so _pull_off_axis_line shrinks the
    # height from 219 to 218.
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
        '<rect x="177" y="31" width="85" height="218" fill="#1e64b4"/>'
        in svg.to_string(),
        (
            "BAR mark's middle bar, same rectangle render()'s hand-derived test"
            " finds"
        ),
    )


def test_render_bar_color_by_sign_colors_negative_bars_differently() raises:
    # The single-negative-bar setup (canvas 400x300, no gridlines, value
    # -10, baseline at y=20, so (220,25) is inside the bar).
    # color_by_sign=True switches that pixel to mark_color_negative.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var _hoisted4 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted4)
    _assert_color(
        c,
        220,
        25,
        t.mark_color_negative,
        "negative bar uses mark_color_negative",
    )


def test_render_bar_color_by_sign_leaves_positive_bars_at_mark_color() raises:
    # Same setup with +10: the baseline is now at the bottom (250), so the
    # inside pixel is (220, 245).
    var x: List[String] = ["a"]
    var y: List[Float64] = [10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var _hoisted5 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted5)
    _assert_color(
        c,
        220,
        245,
        t.mark_color,
        "positive bar stays mark_color even with color_by_sign on",
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
        '<circle cx="220" cy="31" r="4" fill="#1e64b4"/>' in s,
        "category b's point",
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
        '<rect x="76" y="181" width="128" height="35" fill="#1e64b4"/>' in s,
        "A's box (q1 to q3)",
    )
    assert_true(
        '<rect x="236" y="89" width="128" height="35" fill="#1e64b4"/>' in s,
        "B's box (q1 to q3)",
    )
    assert_true(
        '<circle cx="140" cy="30" r="4" fill="#1e64b4"/>' in s,
        "A's single outlier, at value 20",
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
        '<line x1="140" y1="135" x2="140" y2="240" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "A's wick, from high=135 to low=240",
    )
    assert_true(
        '<rect x="76" y="165" width="128" height="45" fill="#1e64b4"/>' in s,
        "A's body, closed up",
    )
    assert_true(
        '<line x1="300" y1="30" x2="300" y2="120" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "B's wick, from high=30 to low=120",
    )
    assert_true(
        '<rect x="236" y="60" width="128" height="45" fill="#c83c3c"/>' in s,
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
        # Bar 0's y0=0 lands on the bottom axis line, so its height shrinks 183
        # -> 182 (see _pull_off_axis_line); bars 1/2 never touch 0.
        '<rect x="71" y="67" width="85" height="182" fill="#1e64b4"/>' in s,
        "bar 0 (delta +10): y0=0 to y1=10",
    )
    assert_true(
        '<rect x="177" y="67" width="85" height="73" fill="#c83c3c"/>' in s,
        "bar 1 (delta -4): y0=10 down to y1=6, colored by sign",
    )
    assert_true(
        '<rect x="284" y="31" width="85" height="109" fill="#1e64b4"/>' in s,
        "bar 2 (delta +6): y0=6 to y1=12",
    )
    assert_true(
        '<line x1="156" y1="67" x2="177" y2="67" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        (
            "connector between bar 0 and bar 1, at the shared y1=10/y0=10 pixel"
            " height"
        ),
    )
    assert_true(
        '<line x1="263" y1="140" x2="284" y2="140" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
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
        '<rect x="68" y="94" width="64" height="155" fill="#646464"/>' in s,
        "Start (total): 0 -> 50",
    )
    assert_true(
        '<rect x="161" y="31" width="38" height="63" fill="#1e64b4"/>' in s,
        "A: 50 -> 70",
    )
    assert_true(
        '<rect x="241" y="31" width="38" height="31" fill="#c83c3c"/>' in s,
        "B: 70 -> 60",
    )
    assert_true(
        '<rect x="308" y="62" width="64" height="187" fill="#646464"/>' in s,
        "End (total): 0 -> 60",
    )
    # Connectors reference each bar's actual drawn edge (bar_x_list[i-1] +
    # bar_width_list[i-1]) once total rows are in play: Start's right edge
    # (132) -> A's left (161); A's right (199) -> B's left (241); B's
    # right (279) -> End's left (308).
    assert_true(
        '<line x1="132" y1="94" x2="161" y2="94" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "connector: Start's actual right edge -> A's left edge",
    )
    assert_true(
        '<line x1="199" y1="31" x2="241" y2="31" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
        in s,
        "connector: A's actual right edge -> B's left edge",
    )
    assert_true(
        '<line x1="279" y1="62" x2="308" y2="62" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
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
        '<rect x="76" y="162" width="128" height="87" fill="#e0e0e0"/>' in s,
        "A's lightest band [0,40]",
    )
    assert_true(
        '<rect x="76" y="97" width="128" height="65" fill="#acacac"/>' in s,
        "A's middle band [40,70]",
    )
    assert_true(
        '<rect x="76" y="31" width="128" height="66" fill="#787878"/>' in s,
        "A's darkest band [70,100]",
    )
    assert_true(
        '<rect x="118" y="130" width="45" height="119" fill="#1e64b4"/>' in s,
        "A's measure bar",
    )
    assert_true(
        '<line x1="76" y1="108" x2="204" y2="108" stroke="#505050"'
        ' stroke-width="1.000" stroke-linecap="round"/>'
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
    assert_equal(strokes[0].commands[0].kind, _MOVE_TO)
    assert_equal(strokes[0].commands[0].p1.x, 0.0)
    assert_equal(strokes[0].commands[0].p1.y, 0.0)
    assert_equal(strokes[0].commands[1].kind, _LINE_TO)
    assert_equal(strokes[0].commands[1].p1.x, 28.0)
    assert_equal(strokes[0].commands[1].p1.y, 0.0)
    # The full barb: 28 - 7 (the flag) - 3.5 (a spacing) = 17.5.
    assert_equal(strokes[0].commands[2].kind, _MOVE_TO)
    assert_equal(strokes[0].commands[2].p1.x, 17.5)
    assert_equal(strokes[0].commands[3].kind, _LINE_TO)
    assert_equal(strokes[0].commands[3].p1.x, 14.0)
    assert_equal(strokes[0].commands[3].p1.y, -11.200000000000001)
    # The half barb: one more spacing inboard, half the height.
    assert_equal(strokes[0].commands[4].kind, _MOVE_TO)
    assert_equal(strokes[0].commands[4].p1.x, 14.0)
    assert_equal(strokes[0].commands[5].kind, _LINE_TO)
    assert_equal(strokes[0].commands[5].p1.x, 12.25)
    assert_equal(strokes[0].commands[5].p1.y, -5.6000000000000005)

    # The flag is a closed triangle: tip, apex, back down the staff.
    assert_equal(len(pennants[0].commands), 4)
    assert_equal(pennants[0].commands[0].kind, _MOVE_TO)
    assert_equal(pennants[0].commands[0].p1.x, 28.0)
    assert_equal(pennants[0].commands[1].kind, _LINE_TO)
    assert_equal(pennants[0].commands[1].p1.y, -11.200000000000001)
    assert_equal(pennants[0].commands[2].kind, _LINE_TO)
    assert_equal(pennants[0].commands[2].p1.x, 21.0)
    assert_equal(pennants[0].commands[3].kind, _CLOSE)


def test_barb_glyph_lone_half_barb_insets_from_the_tip() raises:
    # A 5-knot glyph's only feature sits one spacing in from the tip, so
    # it cannot be misread as a full barb drawn short.
    var strokes = List[Path]()
    var pennants = List[Path]()
    _barb_glyph(strokes, pennants, _barb_counts(5.0), 28.0, False)
    assert_equal(len(strokes[0].commands), 4)
    assert_equal(len(pennants[0].commands), 0, "5 knots has no flag")
    assert_equal(strokes[0].commands[2].kind, _MOVE_TO)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
