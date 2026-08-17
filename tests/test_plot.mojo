"""Tests for plot.mojo: Plot's builder chain and render()'s actual
pixel output -- render() delegates its hard math (scales, ticks,
number formatting) to scale.mojo, already covered by test_scale.mojo,
so these focus on what render() itself is responsible for: turning a
Plot into the right pixels, in the right place, respecting Theme.
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

comptime BG = Color(255, 255, 255)


def _count_color(c: Canvas, color: Color) -> Int:
    var count = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == color.r and p.g == color.g and p.b == color.b:
                count += 1
    return count


def test_render_raises_on_mismatched_x_y_lengths() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_empty_data_only_fills_background() raises:
    # render() always fills with theme.background regardless of
    # whatever the canvas was constructed with (Plot owns the whole
    # canvas it's given -- see plot.mojo's own docstring), so the
    # canvas's own initial fill color (10,20,30) must NOT survive.
    var plot = Plot()  # no encode() call -- x_data/y_data both empty
    var c = Canvas(50, 40, Color(10, 20, 30))
    render(c, plot)
    var expected = Theme.default().background
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, expected.r)
            assert_equal(p.g, expected.g)
            assert_equal(p.b, expected.b)


def test_render_point_mark_centers_on_the_hand_derived_pixel() raises:
    # Single data point (5.0, 5.0) -- zero domain span, so
    # _data_extent pads +/-1.0 on each side, giving domain [4.0, 6.0]
    # for both axes. Canvas is 400x300 with Theme's default margins
    # (left=60, right=20, top=20, bottom=50), so the plot area is
    # x:[60,380], y:[20,250] -- exact integers throughout, hand-solved
    # from LinearScale's own slope/intercept formula (not read off the
    # code's output): x_scale.to_pixel(5.0) = 220, y_scale.to_pixel
    # (5.0) = 135 (both land exactly on an integer, no rounding
    # ambiguity to worry about). Default point_radius=3.5 rounds
    # (round-half-away-from-zero) to a 4px radius, so (220,135) is
    # deep in the disk's fully-covered interior -- exact color match,
    # not just "some ink present".
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=x, y=y)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var p = c.get_pixel(220, 135)
    var expected = Theme.default().mark_color
    assert_equal(p.r, expected.r)
    assert_equal(p.g, expected.g)
    assert_equal(p.b, expected.b)


def test_render_respects_custom_theme_colors() raises:
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var custom = Theme(background=Color(20, 20, 20), mark_color=Color(255, 0, 0))
    var plot = Plot().mark_point().encode(x=x, y=y).theme(custom)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    # Far corner, untouched by any mark/axis/gridline -- pure background.
    var corner = c.get_pixel(399, 0)
    assert_equal(corner.r, 20)
    assert_equal(corner.g, 20)
    assert_equal(corner.b, 20)

    var mark_pixel = c.get_pixel(220, 135)
    assert_equal(mark_pixel.r, 255)
    assert_equal(mark_pixel.g, 0)
    assert_equal(mark_pixel.b, 0)


def test_render_gridlines_flag_actually_controls_gridline_pixels() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var gridline_color = Color(225, 225, 225)

    var c_on = Canvas(400, 300, BG)
    render(c_on, Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=True)))
    assert_true(_count_color(c_on, gridline_color) > 0)

    var c_off = Canvas(400, 300, BG)
    render(c_off, Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=False)))
    assert_equal(_count_color(c_off, gridline_color), 0)


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


def test_render_raises_on_mismatched_color_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y, color=color)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_raises_on_mismatched_size_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var size: List[Float64] = [1.0, 2.0]
    var plot = Plot().encode(x=x, y=y, size=size)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_raises_when_color_encoding_used_with_line_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, color=color)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_color_encoding_matches_hand_derived_colors() raises:
    # Two points at x=[0,10], y=[0,0] (constant y -> zero-span domain,
    # padded to [-1,1], so y=0.0 maps to the plot area's exact
    # vertical midpoint, y=135 -- same hand-derivation as the size
    # test below). x-domain [0,10] pads to [-0.5,10.5], landing the
    # two points at pixel x=75 and x=365 (solved directly from
    # LinearScale's slope/intercept formula, cross-checked in Python,
    # not read off the code's own output).
    #
    # color_data=[0.0,10.0] over a theme whose color_scale_low/high
    # are pure black/white -- the exact same domain and stops
    # test_color_scale.mojo's own hand-verified test uses, so the two
    # points must land on exactly black and exactly white.
    # show_legend=False: this test is about the color-scale math, not
    # legend layout -- has_color now draws a continuous legend by
    # default (see the "Continuous color/size legends" ROADMAP entry),
    # which would reserve horizontal space and shift these hand-derived
    # pixel positions. Legend layout itself is covered separately by
    # test_render_svg_continuous_color_legend_matches_hand_derived_strips.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(
        color_scale_low=Color(0, 0, 0), color_scale_high=Color(255, 255, 255), show_legend=False
    )
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var p0 = c.get_pixel(75, 135)
    assert_equal(p0.r, 0)
    assert_equal(p0.g, 0)
    assert_equal(p0.b, 0)

    var p1 = c.get_pixel(365, 135)
    assert_equal(p1.r, 255)
    assert_equal(p1.g, 255)
    assert_equal(p1.b, 255)


def test_render_size_encoding_matches_hand_derived_radii() raises:
    # Same two point positions (75,135)/(365,135) as the color test
    # above. size_data=[0.0,100.0] over a theme with a clean
    # size_range [2.0,10.0] -- point 0 gets radius 2, point 1 gets
    # radius 10 (both round-half-away-from-zero exact, no rounding
    # ambiguity). Checked by coverage at increasing distance from each
    # center, not by re-deriving fill_circle_aa's own coverage math
    # (already exhaustively tested in canvas itself): a pixel 3px from
    # the radius-2 point must be background (outside), the same
    # distance from the radius-10 point must still be the mark color
    # (well inside) -- together these confirm the two points actually
    # got different radii, not just "some circle was drawn".
    # show_legend=False: same reasoning as the color test above --
    # has_size now draws a continuous size legend by default, which
    # would shift these hand-derived pixel positions. Legend layout
    # itself is covered separately by
    # test_render_svg_continuous_size_legend_matches_hand_derived_circles.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var size: List[Float64] = [0.0, 100.0]
    var t = Theme(
        size_range_min=2.0, size_range_max=10.0, show_gridlines=False, show_legend=False
    )
    var plot = Plot().mark_point().encode(x=x, y=y, size=size).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var mark_color = t.mark_color
    _assert_color(c, 75, 135, mark_color, "small point center")
    _assert_color(c, 78, 135, BG, "3px from small (radius 2) point -- outside")

    _assert_color(c, 365, 135, mark_color, "large point center")
    _assert_color(c, 368, 135, mark_color, "3px from large (radius 10) point -- still inside")
    _assert_color(c, 376, 135, BG, "11px from large (radius 10) point -- outside")


def _assert_color(c: Canvas, x: Int, y: Int, expected: Color, label: String) raises:
    var p = c.get_pixel(x, y)
    assert_equal(p.r, expected.r, label)
    assert_equal(p.g, expected.g, label)
    assert_equal(p.b, expected.b, label)


def test_render_bar_mark_matches_hand_derived_bar_rectangles() raises:
    # 3 categories, y=[10,20,15], canvas 400x300 with default margins
    # (plot area x:[60,380], y:[20,250]). _bar_y_extent pads [0,20] up
    # to [0,21.0] (5% of the 20-span, only on the non-zero end -- see
    # that function's own docstring), giving baseline pixel y=250 and
    # tops at y=140/31/86 for values 10/20/15 respectively.
    # OrdinalScale's default 0.2 padding over range [60,380] (step
    # 106.667, bandwidth 85.333) puts each band's left edge at
    # x=71/177/284, all solved directly from LinearScale/OrdinalScale's
    # own formulas (cross-checked in Python), not read off the code's
    # own output. Gridlines off to keep the checked pixels unambiguous.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var mark_color = t.mark_color

    # Inside each bar (well within both its x-span and its height).
    _assert_color(c, 113, 200, mark_color, "inside bar 0 (value 10)")
    _assert_color(c, 220, 50, mark_color, "inside bar 1 (value 20)")
    _assert_color(c, 327, 200, mark_color, "inside bar 2 (value 15)")

    # Above bar 0's own top (y=140) -- outside the bar, background.
    _assert_color(c, 113, 100, BG, "above bar 0's top -- background")

    # Between bar 0 (ends x=156) and bar 1 (starts x=177) -- the
    # padding gap, background.
    _assert_color(c, 165, 200, BG, "gap between bar 0 and bar 1")


def test_render_bar_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_bar_empty_data_only_fills_background() raises:
    var plot = Plot().mark_bar()  # no encode_categorical() call
    var c = Canvas(50, 40, Color(10, 20, 30))
    render(c, plot)
    var expected = Theme.default().background
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, expected.r)
            assert_equal(p.g, expected.g)
            assert_equal(p.b, expected.b)


def test_render_bar_negative_values_extend_below_the_baseline() raises:
    # A single negative bar -- _bar_y_extent's domain is [lo-pad, 0]
    # (hi stays exactly 0, unpadded, since no value is above zero --
    # see that function's own docstring), so the baseline sits at the
    # *top* of the bar's own drawn rectangle, not its bottom the way
    # every positive-only bar in the test above has it.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    # Baseline (value 0) is the domain's own unpadded top edge, so it
    # lands exactly at the plot area's own top, pixel y=20 -- a
    # pixel just below that, well inside the bar's single wide band,
    # must already be the mark color.
    _assert_color(c, 220, 25, t.mark_color, "just below the zero baseline, inside the bar")
    # Well above the plot area entirely -- background regardless.
    _assert_color(c, 220, 5, BG, "above the plot area")


def test_unique_categories_preserves_first_seen_order() raises:
    var data: List[String] = ["b", "a", "b", "c", "a"]
    var unique = _unique_categories(data)
    assert_equal(len(unique), 3)
    assert_equal(unique[0], "b")
    assert_equal(unique[1], "a")
    assert_equal(unique[2], "c")


def test_index_of_finds_positions_and_reports_missing_as_negative_one() raises:
    var data: List[String] = ["x", "y", "z"]
    assert_equal(_index_of(data, "x"), 0)
    assert_equal(_index_of(data, "z"), 2)
    assert_equal(_index_of(data, "q"), -1)


def test_render_categorical_color_matches_hand_derived_palette_entries() raises:
    # Different pixel centers than the continuous color test above --
    # color_categories automatically reserves a 130px legend column on
    # the right (see render()'s own show_legend/legend_reserve), so
    # the plot area is narrower here (x range [60,250], not [60,380]):
    # the same x domain [-0.5,10.5] now lands the two points at pixel
    # x=69/241, not 75/365 -- solved directly from LinearScale's own
    # formula against the *narrowed* range, cross-checked in Python,
    # not read off the code's own output. color_categories = ["A","B"]
    # -- two distinct categories in first-seen order, so point 0 gets
    # default_categorical_palette()[0], point 1 gets [1], not the
    # theme's continuous color_scale_low/high at all.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var palette = default_categorical_palette()
    _assert_color(c, 69, 135, palette[0], "category A -> palette[0]")
    _assert_color(c, 241, 135, palette[1], "category B -> palette[1]")


def test_render_raises_when_color_and_color_categories_both_given() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().encode(x=x, y=y, color=color, color_categories=cats)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_raises_on_mismatched_color_categories_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().encode(x=x, y=y, color_categories=cats)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_area_mark_matches_hand_derived_fill_region() raises:
    # x=[0,10], y=[0,10] on a 400x300 canvas, default margins (plot
    # area x:[60,380], y:[20,250]). x lands at pixel 75/365 (same
    # domain math as every other continuous-x test above).
    # _zero_baseline_y_extent([0,10]) pads only the non-zero end,
    # giving domain [0,10.5], baseline pixel y=250, top-right point
    # pixel y=31 -- so the filled region is a right-triangle-ish area
    # from (75,250) up to (365,31) then back down to the baseline
    # (both solved directly from LinearScale's own formula, cross-
    # checked in Python). Interpolating that top edge at pixel x=220
    # (the plot's own horizontal midpoint) puts it at y=140.5 -- a
    # point comfortably below that (y=200) must be filled, a point
    # comfortably above it (y=50) must still be background.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_area().encode(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 220, 200, t.mark_color, "inside the filled area")
    _assert_color(c, 220, 50, BG, "above the area's top edge -- background")


def test_render_svg_area_smoothing_matches_hand_derived_curve() raises:
    # x=[0,10,20], y=[2,10,4] (a peak, deliberately not touching zero at
    # either end -- unlike this data's own y=0 endpoints would, which
    # would make the closing line_to()s down to baseline degenerate,
    # zero-length segments landing exactly on the curve's own last
    # point; not wrong, just a less illustrative hand-derivation).
    # Canvas 400x300, default margins, show_gridlines=False.
    # _zero_baseline_y_extent([2,10,4]) -> domain [0, 10.5] (zero
    # already exact; 10's own +5% pad -> 10.5) -- the *top* edge only
    # (px/py, the same LinearScale math Mark.LINE's own equivalent test
    # already established the technique for) is smoothed; the two
    # line_to()s down to/along baseline (pixel y=250, to_pixel(0.0))
    # stay straight. Every control-point coordinate independently re-
    # derived via python3, then confirmed against a real render_svg()
    # run before trusting it here.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=1.0, show_gridlines=False))
    render_svg(svg, plot)
    assert_true(
        '<path d="M74.545,206.190 C98.788,176.984 171.515,38.254 220.000,30.952'
        ' C268.485,23.651 341.212,140.476 365.455,162.381 L365.455,250.000'
        ' L74.545,250.000 Z" fill="#1e64b4"/>' in svg.to_string(),
        "the smoothed top edge, then two straight line_to()s down to baseline, closed",
    )


def test_render_area_smoothing_default_matches_straight_output_exactly() raises:
    # line_smoothing's own default (0.0) must reproduce the exact pre-
    # existing straight-edged Mark.AREA render byte-for-byte -- the same
    # "purely additive" bar every optional Theme field has had to clear
    # (see e.g. Mark.LINE's own equivalent test). Compared pixel-for-
    # pixel across the whole canvas between Theme's own bare default and
    # an explicit Theme(line_smoothing=0.0).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var c_default = Canvas(400, 300, BG)
    render(c_default, Plot().mark_area().encode(x=x, y=y))
    var c_explicit = Canvas(400, 300, BG)
    render(c_explicit, Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=0.0)))

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
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=-0.1)))
    with assert_raises():
        render(c, Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=1.1)))


def test_render_arc_mark_matches_hand_derived_wedge_colors() raises:
    # Two equal-value wedges -- each spans exactly half the circle.
    # Wedges start at 12 o'clock (-pi/2) and sweep clockwise (see
    # _render_arc's own docstring for why increasing angle is
    # clockwise here): wedge 0 covers -pi/2 -> pi/2 (12 o'clock down
    # to 6 o'clock, passing through 3 o'clock/angle 0) -- a point
    # straight right of center is inside it. Wedge 1 covers pi/2 ->
    # 3pi/2 (6 o'clock back up to 12, passing through 9 o'clock/angle
    # pi) -- a point straight left of center is inside it. Center and
    # radius solved directly from the same margin-box math every
    # other mark uses, minus the 130px legend column reserved on the
    # right by default (theme.show_legend defaults True -- see
    # _render_arc's own docstring): canvas 400x300, default margins ->
    # plot area x:[60,250], y:[20,250], center (155,135), radius =
    # min(190,230)/2*0.9 = 85.5 -- both test points sit only 50px out,
    # well inside that.
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, 1.0]
    var plot = Plot().mark_arc().encode_categorical(x=x, y=y)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var palette = default_categorical_palette()
    _assert_color(c, 205, 135, palette[0], "right of center -- wedge 0 (a)")
    _assert_color(c, 105, 135, palette[1], "left of center -- wedge 1 (b)")


def test_render_arc_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    var plot = Plot().mark_arc().encode_categorical(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_arc_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    var plot = Plot().mark_arc().encode_categorical(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_arc_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_arc().encode_categorical(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_legend_swatches_match_hand_derived_positions_and_colors() raises:
    # Same setup as the categorical color test above (canvas 400x300,
    # default theme, plot area narrowed to x:[60,250] by the 130px
    # legend reserve). The legend column starts at x = plot_x1 +
    # margin_right = 250+20 = 270, y = plot_y0 = 20. Row 0 ("A")'s
    # 14x14 swatch sits at (270,20); row 1 ("B")'s at (270, 20 +
    # (14+8)) = (270,42) -- both solved directly from _draw_legend's
    # own layout constants, not read off the code's output. Checked at
    # each swatch's own center (270+7, row_y+7) so a boundary/rounding
    # difference of a pixel or two wouldn't produce a false failure.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var palette = default_categorical_palette()
    _assert_color(c, 277, 27, palette[0], "legend row 0 swatch -- category A")
    _assert_color(c, 277, 49, palette[1], "legend row 1 swatch -- category B")


def test_render_legend_disabled_restores_the_full_plot_width() raises:
    # theme.show_legend=False -- confirms legend_reserve actually goes
    # back to 0, not just that no legend pixels are drawn: the point
    # positions themselves must return to exactly the same pixel
    # centers (75,135)/(365,135) the *continuous* color test (with no
    # legend at all) uses, since the plot area regains its full
    # original width x:[60,380].
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var t = Theme(show_legend=False)
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var palette = default_categorical_palette()
    _assert_color(c, 75, 135, palette[0], "category A, full-width layout")
    _assert_color(c, 365, 135, palette[1], "category B, full-width layout")
    # Where the legend *would* have been drawn is plain background now.
    _assert_color(c, 277, 27, BG, "no legend drawn when show_legend=False")


def test_render_svg_continuous_color_legend_matches_hand_derived_strips() raises:
    # x=[0,10], y=[0,10], color=[0.0,10.0] (continuous, no size) --
    # canvas 400x300, default theme, show_gridlines=False. "10.0"/"0.0"
    # (26.0px/19.0px at the default 12pt font, confirmed by probe)
    # both stay well under the 130px default legend width, so
    # legend_reserve stays at that default, unchanged -- plot_x1=
    # 400-20-130=250, legend anchor (x=270, y=20).
    #
    # The gradient bar approximates ColorScale's own continuous
    # interpolation as 20 solid strips, each colored at its own
    # vertical *midpoint* value (not its edge) -- strip 0 (the very
    # top, height=100/20=5px exactly) sits at value 9.75 (very close to
    # the domain max, 10.0, so very close to color_scale_high); strip
    # 19 (the very bottom) sits at value 0.25 (very close to color_
    # scale_low). Both colors and every position independently re-
    # derived via python3 (ColorScale's own linear-interpolation
    # formula, not read off the code's output), then confirmed against
    # a real render_svg() run before trusting it here.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var color: List[Float64] = [0.0, 10.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true(
        '<rect x="270" y="20" width="14" height="5" fill="#d85b2c"/>' in s,
        "gradient bar's own top strip (value 9.75, close to color_scale_high)",
    )
    assert_true(
        '<rect x="270" y="115" width="14" height="5" fill="#406ec4"/>' in s,
        "gradient bar's own bottom strip (value 0.25, close to color_scale_low)",
    )
    assert_true(
        '<text x="288" y="24" font-size="12.000" fill="#282828" text-anchor="start">10.0</text>' in s,
        "domain max label, at the bar's own top",
    )
    assert_true(
        '<text x="288" y="124" font-size="12.000" fill="#282828" text-anchor="start">0.0</text>' in s,
        "domain min label, at the bar's own bottom",
    )


def test_render_svg_continuous_size_legend_matches_hand_derived_circles() raises:
    # x=[0,10], y=[0,10], size=[2.0,8.0] (continuous, no color) --
    # same plot_x1=250, legend anchor (270,20) as the color-legend test
    # above (size_range_min/max default to 3.0/15.0, and this data's
    # own three representative labels -- "8.0"/"5.0"/"2.0", all 19.0px
    # -- also stay under the 130px default). Three circles at max
    # (8.0 -> radius 15), midpoint (5.0 -> radius 9), and min (2.0 ->
    # radius 3) of the *data's* own size domain, left-aligned on
    # Theme's own configured largest radius (cx = 270 + 15 = 285) so
    # every label lines up regardless of which circle is biggest.
    # Every center/radius/label position independently re-derived via
    # python3 (LinearScale's own slope/intercept for the size scale),
    # then confirmed against a real render_svg() run before trusting it
    # here.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var size: List[Float64] = [2.0, 8.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=x, y=y, size=size).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true('<circle cx="285" cy="35" r="15" fill="#1e64b4"/>' in s, "max (8.0) -> radius 15")
    assert_true('<circle cx="285" cy="67" r="9" fill="#1e64b4"/>' in s, "midpoint (5.0) -> radius 9")
    assert_true('<circle cx="285" cy="87" r="3" fill="#1e64b4"/>' in s, "min (2.0) -> radius 3")
    assert_true(
        '<text x="304" y="39" font-size="12.000" fill="#282828" text-anchor="start">8.0</text>' in s,
        "max circle's own label",
    )
    assert_true(
        '<text x="298" y="71" font-size="12.000" fill="#282828" text-anchor="start">5.0</text>' in s,
        "midpoint circle's own label",
    )
    assert_true(
        '<text x="292" y="91" font-size="12.000" fill="#282828" text-anchor="start">2.0</text>' in s,
        "min circle's own label",
    )


def test_render_point_continuous_legends_are_off_by_default_theme_setting() raises:
    # Theme(show_legend=False) suppresses continuous color/size legends
    # the same way it already suppresses the categorical one -- the
    # plot area regains its full original width.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(show_legend=False)
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)
    _assert_color(c, 365, 135, t.color_scale_high, "point regains the full-width layout's own pixel center")
    _assert_color(c, 277, 27, BG, "no continuous color legend drawn when show_legend=False")


def test_render_point_legend_width_grows_to_fit_long_category_names() raises:
    # "Southeast Region Sales" measures 140.4px at the default 12pt
    # font (confirmed by probe against this environment's real "Sans"
    # font metrics, the same "locked in, confirmed by probe" convention
    # test_render_left_margin_grows_to_fit_wide_y_axis_labels's own
    # wide y-axis label test already uses -- re-probed after canvas_
    # mojo v0.1.0's FreeType-to-native-TTF-parser swap, which is
    # deliberately unhinted and so measures every glyph slightly
    # differently than the old FreeType-hinted values this test used
    # to lock in). _dynamic_legend_width = max(130, 14+4+140+8) =
    # max(130, 166) = 166, wider than Theme's own default 130px legend
    # column -- so plot_x1 becomes 400-20-166=214, not 400-20-130=250.
    # Legend swatch row 0 at x=plot_x1+margin_right=214+20=234, y=
    # plot_y0=20.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["Cat1", "Southeast Region Sales"]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="234" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "legend column shifted left to make room for the long label",
    )
    assert_true(
        '<rect x="234" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "the long label's own legend swatch",
    )


def test_render_grouped_bar_legend_width_grows_to_fit_long_series_names() raises:
    # Same 140.4px-wide "Southeast Region Sales" label, same math as
    # the Mark.POINT test just above -- dynamic_legend_width=166,
    # plot_x1=400-166-20=214, legend swatch row 0 at x=214+20=234.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "Southeast Region Sales"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="234" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "North's own legend swatch, shifted left to make room for the wider label",
    )
    assert_true(
        '<rect x="234" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "the long label's own legend swatch",
    )


def test_render_left_margin_grows_to_fit_wide_y_axis_labels() raises:
    # y=[1000000,2000000] gives nice ticks [1000000,1500000,2000000]
    # (_data_extent pads to domain [950000,2050000]; Heckbert's own
    # nice-step algorithm picks step=500000 for that span -- same
    # hand-verified math test_scale.mojo's own tests already lock in,
    # not re-derived here). Those three labels' rendered width at the
    # default 12pt font -- confirmed by probe against this
    # environment's real "Sans" font metrics, the same "locked in,
    # confirmed by probe" convention canvas_mojo/tests/test_text.mojo's own
    # glyph-extent tests already use, re-probed after canvas_mojo
    # v0.1.0's FreeType-to-native-TTF-parser swap (deliberately
    # unhinted, so it measures every glyph slightly differently than
    # the old FreeType-hinted values this test used to lock in) -- max
    # out at 51.8px (the "2000000" label, down from the pre-repin
    # 55.0px). dynamic_left_margin = Int(51.8) + _TICK_LENGTH(5) +
    # _LABEL_GAP(4) + _MARGIN_BUFFER(8) = 68, wider than Theme's
    # default 60px margin, so plot_x0 becomes 68, not 60 -- checked
    # directly against where the y-axis line itself actually is (drawn
    # at exactly plot_x0), not an indirect proxy for it.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_point().encode(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 68, 135, t.axis_color, "y-axis line moved to the dynamic margin")

    # The wide label's own ink extends left of the *old* fixed 60px
    # margin (confirmed by probe: real, non-background pixels sit at
    # x=57, part of the "2000000" label's glyphs -- x=56 itself is a
    # gap between glyphs under the new, narrower metrics, unlike the
    # pre-repin render) -- exactly why it needed, and got, more room
    # than the old fixed margin would have given it; a plain "x=60 is
    # background" check would be wrong here, since covering that space
    # with real label ink is the entire point of this feature, not an
    # absence to assert on.
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's own ink reaches left of the old fixed margin",
    )


def test_render_left_margin_unchanged_for_short_y_axis_labels() raises:
    # Confirms the dynamic computation is purely additive: short
    # labels ("2","4","6","8","10", from the same data every other
    # point-mark test in this file uses) must leave plot_x0 at
    # exactly Theme's own default 60, byte-identical to every
    # pre-existing hand-derived test above -- not a coincidence, the
    # actual reason none of those needed updating when this feature
    # was added.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_point().encode(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 60, 135, t.axis_color, "y-axis line still at Theme's default margin")


def test_render_bar_left_margin_also_grows_to_fit_wide_y_axis_labels() raises:
    # Same dynamic-left-margin mechanism as the continuous-path tests
    # above, wired into _render_bar independently (see that function's
    # own comment) -- confirmed here rather than just assumed to carry
    # over, since it's a separate function, not shared code.
    # y=[1000000,2000000] through _zero_baseline_y_extent (BAR's own
    # always-include-zero y-domain, not _data_extent's) gives nice
    # ticks [0,500000,1000000,1500000,2000000] -- confirmed by probe
    # (re-probed after canvas_mojo v0.1.0's FreeType-to-native-TTF-
    # parser swap, see test_render_left_margin_grows_to_fit_wide_y_
    # axis_labels's own comment) this lands on the identical dynamic_
    # left_margin=68 the continuous-path test above got (the widest
    # label's width happens to match closely enough that both round to
    # the same margin), so the same pixel checks apply: the y-axis
    # line at x=68, and real label ink reaching left of the old fixed
    # 60px margin (x=57 -- confirmed separately by probe, not assumed
    # identical, though it now happens to coincide with the continuous
    # test's own x=57 too, unlike before the repin).
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 68, 135, t.axis_color, "bar chart y-axis line moved to the dynamic margin")
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's own ink reaches left of the old fixed margin",
    )


def test_render_facets_lays_out_independent_plots_side_by_side() raises:
    # Two cells, 400x300 each, side by side on an 800x300 canvas (cols=2,
    # so rows=1) -- cell 0 is x:[0,400], y:[0,300], the *exact* same
    # dimensions test_render_point_mark_centers_on_the_hand_derived_pixel
    # already hand-solved for a single (5.0, 5.0) point with Theme's
    # default margins: plot area x:[60,380], y:[20,250], point pixel
    # (220, 135). Cell 1 is x:[400,800], y:[0,300] -- identical geometry,
    # just shifted +400 in x (`render()`'s own ox0 offsets everything,
    # including the margins, so the whole plot area shifts by the same
    # +400, not just its origin) -- plot area x:[460,780], point pixel
    # (620, 135) confirmed by the same offset, not re-solved from
    # scratch. Two different mark_colors (one per plot's own Theme)
    # confirm each cell actually rendered its own independent plot, not
    # one plot's output bleeding into or overwriting the other's cell.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=Color(255, 0, 0)))
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var c = Canvas(800, 300, BG)
    render_facets(c, plots, cols=2)

    _assert_color(c, 220, 135, Theme.default().mark_color, "cell 0's own point, unshifted")
    _assert_color(c, 620, 135, Color(255, 0, 0), "cell 1's own point, +400px shifted")


def test_render_facets_leaves_trailing_cells_blank_when_plots_dont_fill_the_grid() raises:
    # 3 plots, cols=2 -> rows=ceil(3/2)=2, a 2x2 grid of 400x300 cells
    # on an 800x600 canvas (800/2=400, 600/2=300 -- divides evenly, no
    # rounding to reason about here). Plots fill row-major: (0,0),
    # (0,1), (1,0); (1,1) has no 4th plot and is never touched.
    #
    # Each filled cell reuses the same hand-solved single-(5.0,5.0)-point
    # geometry as the side-by-side test above, offset by its own cell's
    # origin: (0,0) -> point at (220,135) [unshifted]; (0,1) -> (620,135)
    # [+400 in x]; (1,0) -> plot area y:[320,550] (cell_y0=300, so
    # +300 in y throughout), point at (220,435) [+300 in y].
    #
    # The canvas starts filled with a color no plot's own Theme ever
    # produces (10,20,30, not white) specifically so a genuinely
    # untouched cell is distinguishable from one that was rendered with
    # a background matching the canvas's own initial fill by
    # coincidence.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy)
    var plot2 = Plot().mark_point().encode(x=xy, y=xy)
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)
    plots.append(plot2^)

    var c = Canvas(800, 600, Color(10, 20, 30))
    render_facets(c, plots, cols=2)

    var mark_color = Theme.default().mark_color
    _assert_color(c, 220, 135, mark_color, "cell (0,0)'s own point")
    _assert_color(c, 620, 135, mark_color, "cell (0,1)'s own point")
    _assert_color(c, 220, 435, mark_color, "cell (1,0)'s own point")
    _assert_color(c, 700, 450, Color(10, 20, 30), "cell (1,1) has no 4th plot -- never touched")


def test_render_facets_raises_on_non_positive_cols() raises:
    var plots = List[Plot]()
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_facets(c, plots, cols=0)
    with assert_raises():
        render_facets(c, plots, cols=-1)


def test_render_facets_with_empty_list_is_a_noop() raises:
    var plots = List[Plot]()
    var c = Canvas(50, 40, Color(10, 20, 30))
    render_facets(c, plots, cols=2)
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, 10)
            assert_equal(p.g, 20)
            assert_equal(p.b, 30)


def test_render_theme_scale_uniformly_scales_the_whole_layout() raises:
    # Theme.scale=2.0, paired with a canvas twice the width/height, is
    # meant to reproduce the exact same chart at twice the pixel
    # density -- so this reuses (not re-derives) test_render_point_
    # mark_centers_on_the_hand_derived_pixel's own single-(5.0, 5.0)-
    # point setup, at 2x: canvas 800x600 (2x of 400x300), default
    # margins doubled by _Scaled (left=120, right=40, top=40,
    # bottom=100), giving a plot area of x:[120,760], y:[40,500] --
    # exactly 2x test_render_point_mark_centers_on_the_hand_derived_
    # pixel's own x:[60,380], y:[20,250]. The point's own pixel
    # (440, 270) is exactly double (220, 135) for the same reason:
    # LinearScale.to_pixel() of a domain's own midpoint always lands
    # on the range's own midpoint, and doubling a range's endpoints
    # doubles its midpoint too (confirmed directly via the formula,
    # not assumed to "just carry over" from the 1x case).
    var xy: List[Float64] = [5.0]
    var t = Theme(scale=2.0)
    var plot = Plot().mark_point().encode(x=xy, y=xy).theme(t)
    var c = Canvas(800, 600, BG)
    render(c, plot)

    _assert_color(c, 440, 270, t.mark_color, "scale=2.0's point, exactly 2x the scale=1.0 pixel")
    # The y-axis line itself, confirming the *margin* scaled (not just
    # incidentally landing on the right point pixel) -- plot_x0=120
    # spans the axis line from plot_y0=40 to plot_y1=500, and 270 is
    # well inside that span.
    _assert_color(c, 120, 270, t.axis_color, "scale=2.0's y-axis line, at the doubled margin")


def test_render_theme_scale_default_matches_unscaled_output_exactly() raises:
    # scale's own default (1.0) must reproduce the exact pre-existing
    # unscaled render byte-for-byte -- not just "close", since every
    # pre-existing hand-derived pixel test in this file already
    # depends on that. Cross-checked directly here too: the identical
    # single-point setup, compared pixel-for-pixel between an explicit
    # Theme(scale=1.0) and Theme's own bare default.
    var xy: List[Float64] = [5.0]
    var c_default = Canvas(400, 300, BG)
    render(c_default, Plot().mark_point().encode(x=xy, y=xy))
    var c_explicit = Canvas(400, 300, BG)
    render(c_explicit, Plot().mark_point().encode(x=xy, y=xy).theme(Theme(scale=1.0)))

    for y in range(c_default.height):
        for x in range(c_default.width):
            var p_default = c_default.get_pixel(x, y)
            var p_explicit = c_explicit.get_pixel(x, y)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_svg_point_mark_matches_hand_derived_coordinates() raises:
    # The exact same single-(5.0, 5.0)-point setup test_render_point_
    # mark_centers_on_the_hand_derived_pixel already hand-solved for
    # the raster path -- (220, 135), radius 4 -- confirming render_svg()
    # produces the identical circle through the shared _render_generic
    # core, not re-derived from scratch. Integer pixel coordinates
    # (from _round_to_int, not raw Path floats) can't drift between
    # languages/float implementations the way a raw float coordinate
    # could, so no cross-check-by-probe was needed here (see the LINE/
    # BAR/ARC tests below, whose raw-float or angle-derived coordinates
    # were each confirmed against a real render_svg() run first).
    var xy: List[Float64] = [5.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=xy, y=xy)
    render_svg(svg, plot)
    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in svg.to_string(),
        "encode()'s point, same pixel render() already hand-derives",
    )


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


def test_render_svg_labels_matches_hand_derived_title_and_axis_titles() raises:
    # Same x=[0,10]/y=[5,5] data as the plain-LINE SVG test just above,
    # now with all three of Plot.labels()'s own strings set -- default
    # Theme (title_font_size=18.0, axis_title_font_size=14.0,
    # label_gap=4), canvas 400x300, show_gridlines=False.
    #
    # _apply_labels reserves extra_top=Int(18.0)+4=22, extra_bottom=
    # Int(14.0)+4=18, extra_left=Int(14.0)+4=18 from the *outer* 400x300
    # bounds before _render_generic ever runs, so the inner rect handed
    # to it is (18, 22, 400, 282), not (0, 0, 400, 300) -- shifting
    # every plot-area/tick/line-endpoint coordinate the original LINE
    # SVG test hand-solved for the unshrunk canvas. Every position below
    # (titles' own anchors, and the line's own re-solved endpoints)
    # independently re-derived via python3 from that shrunk rect, then
    # confirmed against a real render_svg() run before trusting it here
    # -- the same cross-check discipline every hand-derived test in this
    # file follows, doubly so here since this is the first test to
    # exercise _apply_labels' own shrunk-rect math at all.
    #
    # Title/x_title/y_title all center on the *inner* plot rect
    # (_RenderResult's own px0/py0/px1/py1 -- see dataviz_mojo/ROADMAP.md's
    # own "Plot.labels() precise centering" Done entry), not the full
    # outer bounds -- confirmed here via the LINE mark's own already-
    # hand-solved endpoints just below: plot_x0=78 (frame.ox0=18 +
    # margin_left=60, no dynamic left-margin growth -- short y=5 tick
    # labels), plot_x1=380 (frame.ox1=400 - margin_right=20, no legend
    # on Mark.LINE), matching the line path's own re-solved
    # to_pixel(0)=91.727/to_pixel(10)=366.273 (slope solved from those
    # two points) below. plot_y0=42 (frame.oy0=22 + margin_top=20),
    # plot_y1=232 (frame.oy1=282 - margin_bottom=50) -- matching the
    # line's own flat y=137.000 (the exact vertical midpoint, y=[5,5]
    # constant data).
    #
    # Title: center=((78+380)//2, 14)=(229,14) -- horizontal center is
    # the inner rect's, but the *vertical* position (14) still comes
    # from the *original* outer oy0=0 (Int(18.0*0.8)=14), unaffected --
    # only the cross-axis coordinate moved, not the along-axis one (see
    # _label_text_requests' own docstring). No rotation (0.0, so no
    # transform attr).
    # x_title: center=(229,297) -- same horizontal center as title,
    # vertical position still from the original outer oy1=300
    # (300-Int(14.0*0.25)=297), unaffected.
    # y_title: (11,(42+232)//2)=(11,137) -- horizontal position still
    # from the original outer ox0=0 (Int(14.0*0.8)=11), unaffected; the
    # *vertical* center is now the inner rect's own (137, not the old
    # 150=outer-bounds-based value) -- rotation=-pi/2 -> exactly -90.000
    # degrees, confirmed correct (bottom-to-top reading, the standard
    # y-axis-title convention) via a real rendered raster probe before
    # trusting the sign in this SVG assertion.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_line()
        .encode(x=x, y=y)
        .labels(title="My Title", x_title="X Axis", y_title="Y Axis")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true(
        '<text x="229" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">My Title</text>' in s,
        "chart title -- centered over the inner plot rect, no rotation",
    )
    assert_true(
        '<text x="229" y="297" font-size="14.000" fill="#282828"'
        ' text-anchor="middle">X Axis</text>' in s,
        "x_title -- centered over the inner plot rect, near the bottom edge",
    )
    assert_true(
        '<text x="11" y="137" font-size="14.000" fill="#282828"'
        ' text-anchor="middle" transform="rotate(-90.000 11 137)">Y Axis</text>' in s,
        "y_title -- rotated -90 degrees (reads bottom-to-top), vertically centered on the inner rect",
    )
    assert_true(
        '<path d="M91.727,137.000 L366.273,137.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in s,
        "the LINE mark itself, re-solved against the shrunk inner rect",
    )


def test_render_svg_title_centers_on_inner_plot_rect_not_outer_bounds() raises:
    # Direct regression test for the "Plot.labels() precise centering"
    # fix: same long-category-name legend setup as test_render_point_
    # legend_width_grows_to_fit_long_category_names above (_dynamic_
    # legend_width=166, plot_x1=400-20-166=214; plot_x0 stays the
    # default margin_left=60 -- y=[0.0,0.0] pads to a short-labeled
    # domain, no dynamic-left-margin growth here), now with a chart
    # title too. Before this fix, the title centered on the full outer
    # canvas width ((0+400)//2=200, what test_render_svg_labels_matches_
    # hand_derived_title_and_axis_titles's own "My Title" case would
    # have used pre-fix); after it, the title centers on the *inner*
    # plot rect instead -- (60+214)//2=137 -- correctly shifted left of
    # the legend-narrowed data area's own true center, not the
    # legend-oblivious canvas center.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["Cat1", "Southeast Region Sales"]
    var svg = SvgCanvas(400, 300)
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y, color_categories=cats)
        .labels(title="Sales by Region")
        .theme(Theme(show_gridlines=False))
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<text x="137" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">Sales by Region</text>' in s,
        "title centers on the legend-narrowed inner plot rect (137), not the full outer width (200)",
    )


def test_render_labels_default_matches_unlabeled_output_exactly() raises:
    # Plot.labels()'s own defaults (all three strings "") must reproduce
    # the exact pre-existing no-labels render byte-for-byte -- the same
    # "purely additive" bar every optional feature added to this file
    # has had to clear (see e.g. Theme.line_smoothing's own equivalent
    # test). Compared pixel-for-pixel across the whole canvas between a
    # plot that never calls .labels() at all and one that calls it with
    # every argument left at its own default.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var c_unlabeled = Canvas(400, 300, BG)
    render(c_unlabeled, Plot().mark_line().encode(x=x, y=y))
    var c_explicit = Canvas(400, 300, BG)
    render(c_explicit, Plot().mark_line().encode(x=x, y=y).labels())

    for yy in range(c_unlabeled.height):
        for xx in range(c_unlabeled.width):
            var p_unlabeled = c_unlabeled.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_unlabeled.r, p_explicit.r)
            assert_equal(p_unlabeled.g, p_explicit.g)
            assert_equal(p_unlabeled.b, p_explicit.b)


def test_render_title_draws_ink_in_its_own_reserved_top_band() raises:
    # A simpler, raster-side companion to the SVG string test above --
    # confirms canvas_mojo.text.draw_text actually got called with a
    # real, matching title (not just that the SVG backend's own
    # _TextRequest plumbing is correct): a fresh Canvas has no ink
    # anywhere at all before render(), so any non-background pixel
    # inside the reserved top band (y in [0, extra_top)) after
    # render() must be the title's own ink.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var c = Canvas(400, 300, BG)
    render(c, Plot().mark_line().encode(x=x, y=y).labels(title="My Title"))

    var found_ink = False
    for yy in range(22):  # extra_top, hand-derived above
        for xx in range(400):
            var p = c.get_pixel(xx, yy)
            if p.r != BG.r or p.g != BG.g or p.b != BG.b:
                found_ink = True
    assert_true(found_ink, "the title's own ink, somewhere in its reserved top band")


def test_render_labels_raises_x_title_or_y_title_on_arc() raises:
    # _apply_labels' own explicit "no sensible axis to caption" check
    # -- Mark.ARC has no x/y axes at all (_render_arc's own docstring),
    # so setting x_title/y_title on one raises rather than silently
    # dropping a caller's own request, the same "raise on a setting
    # that can't apply" rule Plot.encode's own color/size-on-a-non-
    # POINT-mark check already follows. title alone (no axis titles)
    # is fine for Mark.ARC -- checked separately, not raised here.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, Plot().mark_arc().encode_categorical(x=cats, y=vals).labels(x_title="X"))
    with assert_raises():
        render(c, Plot().mark_arc().encode_categorical(x=cats, y=vals).labels(y_title="Y"))
    # title alone must NOT raise for Mark.ARC.
    render(c, Plot().mark_arc().encode_categorical(x=cats, y=vals).labels(title="Share"))


def test_render_svg_bar_mark_matches_confirmed_rect() raises:
    # Same 3-category/[10,20,15] data test_render_bar_mark_matches_
    # hand_derived_bar_rectangles already hand-solved (bar 1's own
    # rect: x=177, y=31, width=85, height=219) -- confirmed here via a
    # real render_svg() run first, the same cross-check discipline the
    # LINE test above used, before trusting it in this assertion.
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [10.0, 20.0, 15.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    assert_true(
        '<rect x="177" y="31" width="85" height="219" fill="#1e64b4"/>' in svg.to_string(),
        "BAR mark's own middle bar, same rectangle render()'s own hand-derived test finds",
    )


def test_render_svg_arc_mark_matches_confirmed_wedge_paths() raises:
    # 2 categories, values [1, 3] (total 4) -- wedge 0 spans pi/2 (a
    # small arc, large-arc-flag 0), wedge 1 spans 3*pi/2 (large-arc-
    # flag 1) -- deliberately not a 50/50 split, whose each-wedge span
    # would land exactly on the pi boundary the large-arc-flag itself
    # switches on, an ambiguous case not worth testing. Endpoint
    # coordinates confirmed via a real render_svg() run first (same
    # discipline as the LINE/BAR tests above), formatted through
    # `_format_svg_float`'s own 3-decimal rounding (see the LINE
    # test's own comment) -- which also resolves what would otherwise
    # print as 219.99999999999997 (pi's own finite representation
    # leaking through) down to a clean 220.000, the expected value on
    # both ends of the full circle these two wedges split.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,135.000 L220.000,31.500 A103.500,103.500 0 0,1 323.500,135.000'
        ' Z" fill="#1f77b4"/>' in s,
        "wedge 0 (value 1, span pi/2): small arc, large-arc-flag 0, palette[0]",
    )
    assert_true(
        '<path d="M220.000,135.000 L323.500,135.000 A103.500,103.500 0 1,1 220.000,31.500'
        ' Z" fill="#ff7f0e"/>' in s,
        "wedge 1 (value 3, span 3pi/2): wide arc, large-arc-flag 1, palette[1]",
    )


def test_render_svg_raises_on_mismatched_x_y_lengths() raises:
    # render_svg()'s validation isn't a separate check -- it's the
    # exact same _render_generic core render() itself calls, so a
    # mismatched-length Plot raises through either entry point
    # identically. Confirms that sharing, not re-derives the check.
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    var svg = SvgCanvas(200, 150)
    var plot = Plot().encode(x=x, y=y)
    with assert_raises():
        render_svg(svg, plot)


def test_render_donut_leaves_the_center_unfilled_and_fills_the_ring() raises:
    # Same 2-category [1, 3] data (and the same hand-solved center/
    # radius: cx=220, cy=135, radius=103.5, no legend) test_render_
    # svg_arc_mark_matches_confirmed_wedge_paths already uses --
    # donut_inner_radius_fraction=0.5 makes inner_radius=51.75, so the
    # exact center (220, 135) must stay background (the donut hole),
    # while a point on wedge 0's own angular bisector (start=-pi/2,
    # end=0, bisector=-pi/4) at the ring's own midpoint radius
    # ((51.75+103.5)/2=77.625) -- (275, 80), confirmed via a real
    # render() run, not assumed from the formula alone -- lands deep
    # inside the filled ring, not near either edge where AA blending
    # would make an exact color match unreliable.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var c = Canvas(400, 300, BG)
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(
        Theme(show_legend=False, donut_inner_radius_fraction=0.5)
    )
    render(c, plot)

    _assert_color(c, 220, 135, BG, "donut hole: the exact center stays background")
    _assert_color(
        c, 275, 80, default_categorical_palette()[0], "wedge 0's own ring, well inside its bounds"
    )


def test_render_donut_svg_matches_confirmed_ring_sector_paths() raises:
    # Same data/theme as the raster donut test above, through
    # render_svg() instead -- endpoints confirmed via a real
    # render_svg() run first (the same discipline every raw-float SVG
    # assertion in this file uses), formatted through SvgCanvas's own
    # 3-decimal `_format_svg_float`.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(
        Theme(show_legend=False, donut_inner_radius_fraction=0.5)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,31.500 A103.500,103.500 0 0,1 323.500,135.000'
        ' L271.750,135.000 A51.750,51.750 0 0,0 220.000,83.250 Z" fill="#1f77b4"/>' in s,
        "wedge 0's own ring-sector path, outer arc forward then inner arc backward",
    )
    assert_true(
        '<path d="M323.500,135.000 A103.500,103.500 0 1,1 220.000,31.500'
        ' L220.000,83.250 A51.750,51.750 0 1,0 271.750,135.000 Z" fill="#ff7f0e"/>' in s,
        "wedge 1's own ring-sector path, wide arc (large-arc-flag 1) on both radii",
    )


def test_render_donut_raises_on_out_of_range_inner_radius_fraction() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 1.0]
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render(
            c,
            Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(
                Theme(donut_inner_radius_fraction=1.0)
            ),
        )
    with assert_raises():
        render(
            c,
            Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(
                Theme(donut_inner_radius_fraction=-0.1)
            ),
        )


def test_encode_histogram_bins_match_hand_derived_counts() raises:
    # 10 values, 5 bins -- bin_width=(9.0-1.0)/5=1.6, counts hand-
    # solved via python3: [3, 3, 2, 0, 2] (bin 3, [5.8,7.4), empty --
    # confirms encode_histogram doesn't skip empty bins, they're a
    # real 0-count category like any other). 9.0 (data's own max)
    # lands in the last bin (would otherwise compute an out-of-range
    # index bins itself) -- see this method's own docstring for why.
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
    # A smoke test confirming the wiring end to end, not re-deriving
    # Mark.BAR's own rendering math (already exhaustively covered by
    # test_render_bar_mark_matches_hand_derived_bar_rectangles and
    # friends -- encode_histogram() feeds the identical render path,
    # just with computed rather than given categories/counts).
    var data: List[Float64] = [1.0, 1.0, 1.0, 5.0, 9.0]
    var c = Canvas(400, 300, BG)
    var plot = Plot().mark_bar().encode_histogram(data, bins=3).theme(Theme(show_gridlines=False))
    render(c, plot)
    # Bin 0 ([1.0, 3.667)) holds 3 of the 5 values -- its own bar
    # should be the tallest, definitely not still just background at
    # the vertical center of the plot area.
    var mid_of_plot_area = c.get_pixel(113, 135)
    assert_true(
        mid_of_plot_area.r != 255 or mid_of_plot_area.g != 255 or mid_of_plot_area.b != 255,
        "bin 0's own bar (3 of 5 values) reaches well above the plot area's own midpoint",
    )


def test_render_bar_color_by_sign_colors_negative_bars_differently() raises:
    # The exact single-negative-bar setup test_render_bar_negative_
    # values_extend_below_the_baseline already hand-solved (canvas
    # 400x300, no gridlines, single category "a" at value -10 -- the
    # baseline sits at the plot area's own top, pixel y=20, so (220,25)
    # is just inside the bar). Theme.color_by_sign=True switches that
    # exact pixel from mark_color to mark_color_negative -- confirming
    # the flag is actually read, not just accepted and ignored.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)
    _assert_color(c, 220, 25, t.mark_color_negative, "negative bar uses mark_color_negative")


def test_render_bar_color_by_sign_leaves_positive_bars_at_mark_color() raises:
    # Same setup, value flipped positive (+10, not -10) -- baseline
    # now sits at the plot area's own *bottom* (see the sibling
    # positive-values test this data shape matches), so the well-
    # inside-the-bar pixel is (220, 245), just above the baseline
    # (250) instead of just below the top (20).
    var x: List[String] = ["a"]
    var y: List[Float64] = [10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)
    _assert_color(c, 220, 245, t.mark_color, "positive bar stays mark_color even with color_by_sign on")


def test_render_bar_color_by_sign_defaults_off() raises:
    # color_by_sign's own default (False) must reproduce the exact
    # pre-existing single-negative-bar test's own assertion -- a
    # negative bar still just mark_color, not mark_color_negative,
    # when the flag is never set. Purely additive, confirmed the same
    # way every other Theme addition in this file has been.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)
    _assert_color(c, 220, 25, t.mark_color, "color_by_sign defaults off: still mark_color")


def test_render_facets_svg_lays_out_independent_plots_side_by_side() raises:
    # The exact same setup test_render_facets_lays_out_independent_
    # plots_side_by_side already hand-solved for the raster path: two
    # 400x300 cells side by side on an 800x300 canvas (cols=2, rows=1),
    # each a single (5.0, 5.0) point -- cell 0's own point at (220,
    # 135) [unshifted], cell 1's at (620, 135) [+400 in x, the same
    # cell-origin-offset reasoning that test's own comment explains].
    # Two different mark_colors confirm each cell rendered its own
    # independent plot into the shared SvgCanvas, not one overwriting
    # the other.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy)
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=Color(255, 0, 0)))
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = SvgCanvas(800, 300)
    render_facets_svg(svg, plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s,
        "cell 0's own point, same coordinates render_facets()'s own test finds",
    )
    assert_true(
        '<circle cx="620" cy="135" r="4" fill="#ff0000"/>' in s,
        "cell 1's own point, +400px shifted, same as render_facets()'s own test",
    )


def test_render_facets_svg_each_cell_gets_its_own_independent_title() raises:
    # Same two-cell 800x300 layout (cols=2) as the test just above, but
    # cell 0's own Plot sets a title (via .labels()) and cell 1's
    # doesn't -- confirming render_facets()'s own per-cell Plot.labels()
    # support (dataviz_mojo/ROADMAP.md's own "Plot.labels() reaches
    # render_facets/render_layers" Done entry): the title reserves space
    # *only* in cell 0 -- its own point shifts from (220,135), the
    # no-title baseline the test above already established, down to
    # (220,146) (extra_top=Int(18.0)+4=22 pushes plot_y0 from 20 to 42,
    # moving the y=[4,6]-padded-domain midpoint pixel from
    # (20+250)/2=135 to (42+250)/2=146) -- while cell 1's own point
    # stays exactly where it was (620,135), no title there to reserve
    # room for. The title itself centers at
    # ((60+380)//2, Int(18.0*0.8))=(220,14), cell 0's own inner rect,
    # unaffected by cell 1's own layout.
    var xy: List[Float64] = [5.0]
    var plot0 = Plot().mark_point().encode(x=xy, y=xy).labels(title="Left")
    var plot1 = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(mark_color=Color(255, 0, 0)))
    var plots = List[Plot]()
    plots.append(plot0^)
    plots.append(plot1^)

    var svg = SvgCanvas(800, 300)
    render_facets_svg(svg, plots, cols=2)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">Left</text>' in s,
        "cell 0's own title, centered on its own inner plot rect",
    )
    assert_true(
        '<circle cx="220" cy="146" r="4" fill="#1e64b4"/>' in s,
        "cell 0's own point, shifted down to make room for its own title",
    )
    assert_true(
        '<circle cx="620" cy="135" r="4" fill="#ff0000"/>' in s,
        "cell 1's own point, unaffected -- it never set a title",
    )


def test_render_facets_svg_raises_on_non_positive_cols() raises:
    var plots = List[Plot]()
    var svg = SvgCanvas(400, 300)
    with assert_raises():
        render_facets_svg(svg, plots, cols=0)


def test_render_layers_shares_one_domain_across_a_line_and_a_point() raises:
    # A LINE plot (x=[0,10], y=[0,10], default theme) layered with a
    # POINT plot (a single (5,5) point, custom red color + radius 5)
    # -- every coordinate below confirmed via a real render_layers()
    # run first (the same cross-check discipline every raw-float
    # assertion in this file uses), not derived from a hand-rolled
    # formula alone: the combined domain (both plots' x/y data
    # together) pads to [-0.5, 10.5] on both axes, landing the shared
    # point (5,5) -- coincidentally, since 5.0 is that domain's own
    # midpoint -- on the same (220, 135) pixel many other single-plot
    # tests in this file already use, and the line's own two endpoints
    # at (74.545, 239.545) and (365.455, 30.455).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var plot_a = Plot().mark_line().encode(x=line_x, y=line_y).theme(Theme(show_gridlines=False))
    var plot_b = Plot().mark_point().encode(x=point_x, y=point_y).theme(
        Theme(mark_color=Color(255, 0, 0), point_radius=5.0)
    )
    var plots = List[Plot]()
    plots.append(plot_a^)
    plots.append(plot_b^)

    var c = Canvas(400, 300, BG)
    render_layers(c, plots)
    _assert_color(c, 220, 135, Color(255, 0, 0), "the layered point, at the shared domain's own pixel")

    var svg = SvgCanvas(400, 300)
    var svg_plots = List[Plot]()
    svg_plots.append(Plot().mark_line().encode(x=line_x, y=line_y).theme(Theme(show_gridlines=False)))
    svg_plots.append(
        Plot().mark_point().encode(x=point_x, y=point_y).theme(
            Theme(mark_color=Color(255, 0, 0), point_radius=5.0)
        )
    )
    render_layers_svg(svg, svg_plots)
    var s = svg.to_string()
    assert_true(
        '<path d="M74.545,239.545 L365.455,30.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the layered line, endpoints confirmed via a real render_layers_svg() run",
    )
    assert_true('<circle cx="220" cy="135" r="5" fill="#ff0000"/>' in s, "the layered point, same shared domain")


def test_render_layers_svg_title_from_plots0_centers_on_shared_inner_rect() raises:
    # Same LINE+POINT layered setup as the test just above, now with
    # plots[0] (the LINE plot) setting a chart title via .labels() --
    # confirming render_layers()'s own Plot.labels() support
    # (dataviz_mojo/ROADMAP.md's own "Plot.labels() reaches
    # render_facets/render_layers" Done entry): the title comes from
    # plots[0] only (the same "shared chrome from plots[0]" convention
    # Theme already follows here -- see render_layers()'s own
    # docstring), and its own extra_top=Int(18.0)+4=22 reservation
    # shifts the *shared* plot_y0 from 20 to 42 -- affecting every
    # layer's own geometry together, not just plots[0]'s own, since
    # every layer draws into the identical shared inner rect (the
    # point's own cy moves from 135 to 146; the line's own endpoints
    # re-solved below via the same to_pixel formula the un-titled test
    # above already confirmed, just against range_max=42 instead of 20).
    # Title itself centers at ((60+380)//2, Int(18.0*0.8))=(220,14).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var point_x: List[Float64] = [5.0]
    var point_y: List[Float64] = [5.0]
    var svg = SvgCanvas(400, 300)
    var plots = List[Plot]()
    plots.append(
        Plot().mark_line().encode(x=line_x, y=line_y).labels(title="Combined").theme(
            Theme(show_gridlines=False)
        )
    )
    plots.append(
        Plot().mark_point().encode(x=point_x, y=point_y).theme(
            Theme(mark_color=Color(255, 0, 0), point_radius=5.0)
        )
    )
    render_layers_svg(svg, plots)
    var s = svg.to_string()

    assert_true(
        '<text x="220" y="14" font-size="18.000" fill="#282828"'
        ' text-anchor="middle">Combined</text>' in s,
        "layered chart title, from plots[0], centered on the shared inner rect",
    )
    assert_true(
        '<path d="M74.545,240.545 L365.455,51.455" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "the layered line, re-solved against the title-shrunk shared inner rect",
    )
    assert_true(
        '<circle cx="220" cy="146" r="5" fill="#ff0000"/>' in s,
        "the layered point, same shared domain, shifted down by the shared title reservation",
    )


def test_render_layers_svg_point_layer_color_categories_matches_hand_derived_legend() raises:
    # A single Mark.POINT layer (no other layers) with color_categories
    # encoding -- confirming render_layers()'s own per-point encoding +
    # legend support (dataviz_mojo/ROADMAP.md's own "render_layers
    # per-point encoding and legends" Done entry). x=[0,10], y=[0.0,0.0]
    # (constant -- zero-span domain, padded to [-1,1], the same pattern
    # test_render_color_encoding_matches_hand_derived_colors above
    # already establishes), color_categories=["A","B"] -- short labels,
    # so the default 130px Theme.legend_width governs (not grown), and
    # plot_x1 becomes 400-20-130=250 (not 380, the no-legend value other
    # single-layer tests in this file use).
    #
    # x-domain pads [0,10] to [-0.5,10.5]; with plot_x0=60 (unaffected,
    # no dynamic left-margin growth -- short y=[-1,1] tick labels) and
    # this narrowed plot_x1=250, to_pixel(0)=68.636->69,
    # to_pixel(10)=241.364->241 (re-solved via the same LinearScale
    # slope/intercept formula every hand-derived pixel test in this file
    # uses, cross-checked in Python, not read off the code's own
    # output). y=[−1,1] domain's own midpoint (value 0.0) lands at the
    # exact vertical center of [plot_y0=20, plot_y1=250] -> 135, for
    # both points (constant y). Point 0 ("A") gets the default palette's
    # own first color (#1f77b4), point 1 ("B") the second (#ff7f0e) --
    # the identical two colors/ordering the single-plot categorical-
    # color tests in this file already confirm, reused unchanged since
    # render_layers's own per-layer encoding is exactly Mark.POINT's own
    # single-plot logic, not a reimplementation.
    #
    # Legend column at legend_x=plot_x1+margin_right=250+20=270, row 0
    # (swatch "A") at y=plot_y0=20, row 1 ("B") at y=20+(14+8)=42 -- the
    # identical swatch_size=14/row_gap=8 spacing test_render_point_
    # legend_width_grows_to_fit_long_category_names above already
    # establishes.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var svg = SvgCanvas(400, 300)
    var plots = List[Plot]()
    plots.append(
        Plot().mark_point().encode(x=x, y=y, color_categories=cats).theme(Theme(show_gridlines=False))
    )
    render_layers_svg(svg, plots)
    var s = svg.to_string()

    assert_true('<circle cx="69" cy="135" r="4" fill="#1f77b4"/>' in s, "layered point 0, category A's own color")
    assert_true('<circle cx="241" cy="135" r="4" fill="#ff7f0e"/>' in s, "layered point 1, category B's own color")
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s,
        "legend row 0 -- narrowed plot area makes room for the legend column",
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s,
        "legend row 1",
    )


def test_render_layers_raises_when_a_line_layer_uses_color_categories() raises:
    # The identical "only Mark.POINT" restriction Plot.encode's own
    # single-plot path already enforces (see _render_generic's own
    # validation) -- render_layers() raises the same way rather than
    # silently ignoring a LINE/AREA layer's own color/color_categories/
    # size, which the pre-per-point-encoding version of this function
    # used to do (see render_layers()'s own docstring).
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var line_cats: List[String] = ["a", "b"]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y, color_categories=line_cats))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_with_empty_list_and_a_title_is_still_a_noop() raises:
    # test_render_layers_with_empty_list_is_a_noop's own case, but
    # confirming the new Plot.labels() support doesn't break it: an
    # empty plots list has no plots[0] to source a title from, so
    # render_layers() must skip label handling entirely rather than
    # indexing an empty list -- still a genuine no-op, canvas untouched.
    var plots = List[Plot]()
    var c = Canvas(50, 40, Color(10, 20, 30))
    render_layers(c, plots)
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, 10)
            assert_equal(p.g, 20)
            assert_equal(p.b, 30)


def test_render_layers_raises_when_a_bar_plot_is_included() raises:
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var bar_x: List[String] = ["a", "b"]
    var bar_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_bar().encode_categorical(x=bar_x, y=bar_y))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_layers_with_empty_list_is_a_noop() raises:
    var plots = List[Plot]()
    var c = Canvas(50, 40, Color(10, 20, 30))
    render_layers(c, plots)
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, 10)
            assert_equal(p.g, 20)
            assert_equal(p.b, 30)


def test_render_lollipop_matches_hand_derived_stem_and_point() raises:
    # Exactly test_render_bar_mark_matches_hand_derived_bar_rectangles'
    # own data/canvas/theme (3 categories, y=[10,20,15], 400x300,
    # default margins, gridlines off) -- Mark.LOLLIPOP shares Mark.BAR's
    # own encode_categorical() data shape and _zero_baseline_y_extent
    # domain, so category "b"'s own band center (220.0, an exact value
    # -- band_start(1)=177.333 + bandwidth/2=42.667) and value-20 pixel
    # (30.952, rounds to 31 -- the same "tops at y=31" the bar test
    # already confirmed) carry over unchanged; only the *shape* drawn
    # at those coordinates differs. Confirmed via a real render() run
    # first, not derived from the formula alone.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 220, 31, t.mark_color, "circle center, category b's own value pixel")
    _assert_color(c, 220, 150, t.mark_color, "stem midpoint, well within the 2px-wide stroke")
    _assert_color(c, 210, 150, BG, "off the stem entirely -- background")
    _assert_color(c, 220, 10, BG, "above the point -- nothing drawn there")


def test_render_lollipop_svg_matches_confirmed_stem_and_point() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,250.000 L220.000,30.952" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "category b's own stem, confirmed via a real render_svg() run",
    )
    assert_true('<circle cx="220" cy="31" r="4" fill="#1e64b4"/>' in s, "category b's own point")


def test_render_lollipop_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_waterfall_colors_by_sign_and_matches_hand_derived_bars() raises:
    # 3 categories, deltas=[10, -4, 6] -- running totals y0/y1 = [0,10,
    # 10,6, 6,12]. Combined domain [0, 12.6] (_zero_baseline_y_extent
    # over y0 union y1) lands each category's own band at the *same*
    # x positions test_render_bar_mark_matches_hand_derived_bar_
    # rectangles already confirmed (113/220/327 centers) since both use
    # the identical 3-category OrdinalScale over the same [60,380]
    # range -- only the y-domain and per-bar y0/y1 differ. Every pixel
    # below confirmed via a real render() run first, not the formula
    # alone: bar 0 (delta +10) mark_color, bar 1 (delta -4) mark_color_
    # negative -- unconditional sign coloring, no Theme.color_by_sign
    # flag needed, unlike Mark.BAR -- bar 2 (delta +6) mark_color again,
    # and the two connector lines (gridline_color) at the pixel height
    # where consecutive bars' own running totals hand off.
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 113, 150, t.mark_color, "bar 0 (delta +10), well inside its own rect")
    _assert_color(c, 220, 100, t.mark_color_negative, "bar 1 (delta -4), colored by sign")
    _assert_color(c, 327, 80, t.mark_color, "bar 2 (delta +6), back to mark_color")
    _assert_color(c, 165, 67, t.axis_color, "connector between bar 0 and bar 1")
    _assert_color(c, 273, 140, t.axis_color, "connector between bar 1 and bar 2")
    _assert_color(c, 350, 10, BG, "far from every bar -- background")


def test_render_waterfall_svg_matches_confirmed_rects_and_connectors() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="71" y="67" width="85" height="183" fill="#1e64b4"/>' in s, "bar 0 (delta +10): y0=0 to y1=10"
    )
    assert_true(
        '<rect x="177" y="67" width="85" height="73" fill="#c83c3c"/>' in s,
        "bar 1 (delta -4): y0=10 down to y1=6, colored by sign",
    )
    assert_true(
        '<rect x="284" y="31" width="85" height="109" fill="#1e64b4"/>' in s, "bar 2 (delta +6): y0=6 to y1=12"
    )
    assert_true(
        '<line x1="156" y1="67" x2="177" y2="67" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector between bar 0 and bar 1, at the shared y1=10/y0=10 pixel height",
    )
    assert_true(
        '<line x1="263" y1="140" x2="284" y2="140" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector between bar 1 and bar 2, at the shared y1=6/y0=6 pixel height",
    )


def test_render_waterfall_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_waterfall_total_rows_matches_hand_derived_bars() raises:
    # 4 categories: "Start" (total, delta=50 -- a starting-balance total
    # still *adds* its own delta to the running sum, just displays 0 ->
    # the result instead of floating -- see encode_waterfall()'s own
    # docstring), "A" (delta +20, plain), "B" (delta -10, plain), "End"
    # (total, delta=0 -- contributes nothing further, displays 0 -> the
    # final running sum). Running sum: Start 0+50=50 (y0=0,y1=50), A
    # 50+20=70 (y0=50,y1=70), B 70-10=60 (y0=70,y1=60), End 60+0=60
    # (y0=0,y1=60). Canvas 400x300, default margins, show_gridlines=
    # False. _zero_baseline_y_extent over the combined y0/y1 set
    # {0,50,70,60} -> domain [0, 73.5] (70's own +5% pad).
    #
    # OrdinalScale over [60,380], 4 categories, step=80, bandwidth=64 ->
    # band_start: Start=68, A=148, B=228, End=308. Total bars draw full
    # band width (64px); delta bars draw _WATERFALL_DELTA_WIDTH_FRACTION
    # (0.6) of it, centered -- narrow=38.4, inset=12.8, so A/B's own
    # bars are inset ~13px from their own band's edges on both sides.
    #
    # Every position independently re-derived via python3 (LinearScale's
    # own slope/intercept for y, OrdinalScale's own band formula for x),
    # then confirmed against a real render() run before trusting it.
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas, is_total).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    # Start (total): x:[68,132), y:[94,250) -- full band width.
    _assert_color(c, 100, 200, t.waterfall_total_color, "Start (total), well inside")
    # A (delta +20, narrower): x:[161,199), y:[31,94).
    _assert_color(c, 180, 60, t.mark_color, "A (delta +20), well inside its own narrower rect")
    # A's own band still has real background on either side of the
    # narrow bar -- confirming it actually IS narrower, not just a
    # differently-colored full-width bar.
    _assert_color(c, 150, 60, BG, "A's own band, left of its narrow bar -- background")
    # B (delta -10, narrower): x:[241,279), y:[31,62).
    _assert_color(c, 260, 45, t.mark_color_negative, "B (delta -10), colored by sign")
    # End (total): x:[308,372), y:[62,250) -- full band width again.
    _assert_color(c, 340, 150, t.waterfall_total_color, "End (total), well inside")


def test_render_svg_waterfall_total_rows_matches_confirmed_rects() raises:
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas, is_total).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<rect x="68" y="94" width="64" height="156" fill="#646464"/>' in s, "Start (total): 0 -> 50"
    )
    assert_true('<rect x="161" y="31" width="38" height="63" fill="#1e64b4"/>' in s, "A: 50 -> 70")
    assert_true('<rect x="241" y="31" width="38" height="31" fill="#c83c3c"/>' in s, "B: 70 -> 60")
    assert_true(
        '<rect x="308" y="62" width="64" height="188" fill="#646464"/>' in s, "End (total): 0 -> 60"
    )
    # Connectors reference each bar's own *actual* drawn edge (`bar_x_
    # list[i-1] + bar_width_list[i-1]`, not a formula re-derived from
    # the band directly) once total rows are in play -- exercises the
    # exact logic this feature's own hand-derivation bug (a 1px
    # mismatch between a full-width bar's independently-rounded width
    # and a boundary-rounded connector position, caught by this test
    # failing against real output before the fix, not assumed correct)
    # was found and fixed in. Start's own right edge (68+64=132) ->
    # A's own left edge (161); A's own right edge (161+38=199) -> B's
    # own left edge (241); B's own right edge (241+38=279) -> End's own
    # left edge (308).
    assert_true(
        '<line x1="132" y1="94" x2="161" y2="94" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: Start's own actual right edge -> A's own left edge",
    )
    assert_true(
        '<line x1="199" y1="31" x2="241" y2="31" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: A's own actual right edge -> B's own left edge",
    )
    assert_true(
        '<line x1="279" y1="62" x2="308" y2="62" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: B's own actual right edge -> End's own left edge",
    )


def test_render_waterfall_raises_on_mismatched_is_total_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var is_total: List[Bool] = [True, False]
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas, is_total)
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render(c, plot)


def test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier() raises:
    # 2 categories: "A" = [2,4,4,4,5,5,7,9,20] (q1=4, median=5, q3=7,
    # low_whisker=2, high_whisker=9, one outlier at 20 -- 1.5*IQR fence
    # is [4-4.5, 7+4.5]=[-0.5, 11.5], so 20 is the only value beyond
    # it), "B" = [10,12,14,15,18] (q1=12, median=14, q3=15, low=10,
    # high=18, no outliers -- fence [7.5, 19.5] contains every value).
    # Both hand-derived via the same linear-interpolation percentile
    # `_box_stats` itself uses (independently reimplemented in Python,
    # not just re-run through the Mojo code, before trusting these).
    # Domain = _data_extent over every low/high/outlier value
    # ([2,9,10,18,20]) = [1.1, 20.9], 2 categories over [60,380] (band
    # centers 140/300, bandwidth 128, half-width 64, cap half-width 32)
    # -- every pixel below confirmed via a real render() run first.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_box().encode_boxplot(cats, values).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 140, 200, t.mark_color, "A: inside the box (between q1 and q3)")
    _assert_color(c, 140, 205, t.axis_color, "A: the median line, drawn over the box fill")
    _assert_color(c, 140, 170, t.axis_color, "A: the upper whisker, between q3 and high")
    _assert_color(c, 120, 158, t.axis_color, "A: the high-whisker cap")
    _assert_color(c, 140, 30, t.mark_color, "A: the one outlier point, at value 20")
    _assert_color(c, 300, 105, t.mark_color, "B: inside the box")
    _assert_color(c, 300, 100, t.axis_color, "B: the median line")
    _assert_color(c, 300, 70, t.axis_color, "B: the lower whisker, between q1 and low")
    _assert_color(c, 190, 150, BG, "the gap between A's and B's own bands -- background")


def test_render_boxplot_svg_matches_confirmed_rects_and_outlier() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_box().encode_boxplot(cats, values).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="76" y="181" width="128" height="35" fill="#1e64b4"/>' in s, "A's own box (q1 to q3)")
    assert_true('<rect x="236" y="89" width="128" height="35" fill="#1e64b4"/>' in s, "B's own box (q1 to q3)")
    assert_true('<circle cx="140" cy="30" r="4" fill="#1e64b4"/>' in s, "A's own single outlier, at value 20")


def test_encode_boxplot_raises_on_mismatched_length() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = Plot().mark_box().encode_boxplot(cats, values)


def test_encode_boxplot_raises_on_empty_category_values() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0], List[Float64]()]
    with assert_raises():
        _ = Plot().mark_box().encode_boxplot(cats, values)


def test_render_layers_raises_when_a_lollipop_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only restriction test_render_
    # layers_raises_when_a_bar_plot_is_included already confirms for
    # Mark.BAR -- checked again for one of "Phase 2a"'s new categorical
    # marks specifically, since the raise's own check is a positive
    # allow-list (only POINT/LINE/AREA), not a deny-list that would
    # need updating per new mark -- this test exists to confirm that
    # holds in practice, not just by reading the condition.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var lolli_x: List[String] = ["a", "b"]
    var lolli_y: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_lollipop().encode_categorical(x=lolli_x, y=lolli_y))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_candlestick_matches_hand_derived_wicks_and_bodies() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = O10/H15/L8/C13
    # (closed up, close >= open); "B" = O20/H22/L16/C17 (closed down).
    # Domain = _data_extent over every O/H/L/C value ([8,22]; no zero
    # baseline, matching Mark.BOX's own reasoning) padded 5% of the
    # 14-span = [7.3, 22.7]. Same 2-category OrdinalScale over [60,380]
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier
    # already worked out (bands at x=76/236, width 128, centers 140/300)
    # -- only the y-domain and per-category shape differ here. Every
    # pixel below independently computed via python3 from LinearScale's
    # own slope/intercept formula, then confirmed against a real
    # render() run before trusting it.
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 140, 200, t.mark_color, "A: inside the body (open=210 to close=165), closed up")
    _assert_color(c, 140, 150, t.axis_color, "A: the wick, above the body (between high=135 and the body top)")
    _assert_color(c, 140, 225, t.axis_color, "A: the wick, below the body (between the body bottom and low=240)")
    _assert_color(c, 300, 80, t.mark_color_negative, "B: inside the body (open=60 to close=105), closed down")
    _assert_color(c, 300, 45, t.axis_color, "B: the wick, above the body (between high=30 and the body top)")
    _assert_color(c, 300, 115, t.axis_color, "B: the wick, below the body (between the body bottom and low=120)")
    _assert_color(c, 190, 150, BG, "no ink here -- off the wick's own x, above A's own body")


def test_render_candlestick_svg_matches_confirmed_wicks_and_bodies() raises:
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="140" y1="135" x2="140" y2="240" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "A's own wick, from high=135 to low=240",
    )
    assert_true('<rect x="76" y="165" width="128" height="45" fill="#1e64b4"/>' in s, "A's own body, closed up")
    assert_true(
        '<line x1="300" y1="30" x2="300" y2="120" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "B's own wick, from high=30 to low=120",
    )
    assert_true(
        '<rect x="236" y="60" width="128" height="45" fill="#c83c3c"/>' in s, "B's own body, closed down"
    )


def test_render_candlestick_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_candlestick_raises_on_mismatched_ohlc_length() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0]
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_layers_raises_when_a_candlestick_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list test_render_layers_
    # raises_when_a_lollipop_plot_is_included already confirms holds for
    # a second "Phase 2a" mark, checked again for "Phase 2b"'s own first
    # mark -- see that test's own docstring for why this needs no change
    # to render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_candlestick().encode_candlestick(cats, one, one, one, one))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_bullet_matches_hand_derived_bands_measure_and_target() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = ranges=[40,70,100],
    # measure=55, target=65; "B" = ranges=[30,60,90], measure=75,
    # target=50. Domain data = {0, range-top, measure, target} per
    # category = [0,100,55,65, 0,90,75,50] -> _zero_baseline_y_extent
    # gives lo=min(0,0)=0 (unpadded, already at zero), hi=max(0,100)=100
    # padded 5% of the 100-span to 105 -- domain [0, 105]. Same
    # 2-category OrdinalScale over [60,380] every other categorical test
    # already established (bands at x=76/236, width 128, centers
    # 140/300). Every pixel below independently computed via python3
    # from LinearScale's own slope/intercept formula (scale=(20-250)/
    # 105=-2.190476.., translate=250), then confirmed against a real
    # render() run before trusting it.
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_bullet().encode_bullet(cats, measures, targets, ranges).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 90, 200, Color(224, 224, 224), "A: lightest range band [0,40], off the measure bar")
    _assert_color(c, 90, 130, Color(172, 172, 172), "A: middle range band [40,70], off the measure bar")
    _assert_color(c, 90, 60, Color(120, 120, 120), "A: darkest range band [70,100], off the measure bar")
    _assert_color(c, 140, 200, t.mark_color, "A: inside the measure bar (0 to 55), over the bands")
    _assert_color(c, 90, 108, t.axis_color, "A: the target tick (65), off the measure bar")
    _assert_color(c, 140, 10, BG, "A: above every band -- background")
    _assert_color(c, 300, 150, t.mark_color, "B: inside the measure bar (0 to 75)")
    _assert_color(c, 250, 140, t.axis_color, "B: the target tick (50), off the measure bar")
    _assert_color(c, 220, 150, BG, "the gap between A's and B's own bands -- background")


def test_render_bullet_svg_matches_confirmed_bands_measure_and_target() raises:
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_bullet().encode_bullet(cats, measures, targets, ranges).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="76" y="162" width="128" height="88" fill="#e0e0e0"/>' in s, "A's lightest band [0,40]")
    assert_true('<rect x="76" y="97" width="128" height="65" fill="#acacac"/>' in s, "A's middle band [40,70]")
    assert_true('<rect x="76" y="31" width="128" height="66" fill="#787878"/>' in s, "A's darkest band [70,100]")
    assert_true('<rect x="118" y="130" width="45" height="120" fill="#1e64b4"/>' in s, "A's own measure bar")
    assert_true(
        '<line x1="76" y1="108" x2="204" y2="108" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "A's own target tick, full band width",
    )


def test_render_bullet_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], [1.0]]
    var plot = Plot().mark_bullet().encode_bullet(cats, one, one, ranges)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_bullet_raises_on_empty_range_thresholds() raises:
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], List[Float64]()]
    var plot = Plot().mark_bullet().encode_bullet(cats, one, one, ranges)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_bullet_raises_on_non_ascending_range_thresholds() raises:
    var cats: List[String] = ["a"]
    var one: List[Float64] = [1.0]
    var ranges: List[List[Float64]] = [[50.0, 30.0, 100.0]]
    var plot = Plot().mark_bullet().encode_bullet(cats, one, one, ranges)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_layers_raises_when_a_bullet_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # "Phase 2b"'s second mark -- see test_render_layers_raises_when_a_
    # lollipop_plot_is_included's own docstring for why this needs no
    # change to render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], [1.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_bullet().encode_bullet(cats, one, one, ranges))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_gantt_matches_hand_derived_bars() raises:
    # 2 categories ("A", "B" -- short labels, so the dynamic left margin
    # stays at Theme's default 60, the same "A"/short-label convention
    # test_render_left_margin_unchanged_for_short_y_axis_labels already
    # established, sidestepping real font-metric dependence). Canvas
    # 400x300, plot area x:[60,380], y:[20,250], show_gridlines=False.
    # "A" spans [10,40], "B" spans [50,90]. Domain data = every start/end
    # value = [10,40,50,90] -> _data_extent pads 5% of the 80-span (4.0)
    # -> x-domain [6, 94]. y is now the *categorical* axis: OrdinalScale
    # over [20,250] (2 categories, step=115, padding 0.2 -> bandwidth
    # 92), category 0 ("A") landing nearer the *top* (smaller pixel y)
    # than category 1 ("B") -- confirmed directly below, not assumed.
    # Every pixel independently computed via python3 from LinearScale's/
    # OrdinalScale's own formulas, then confirmed against a real
    # render() run before trusting it.
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    _assert_color(c, 100, 60, t.mark_color, "A's own bar (x:[75,184), y:[32,124)), well inside")
    _assert_color(c, 250, 180, t.mark_color, "B's own bar (x:[220,365), y:[147,239)), well inside")
    _assert_color(c, 100, 140, BG, "the gap between A's and B's own rows -- background")
    _assert_color(c, 200, 60, BG, "A's own row, but past its bar's own right edge -- background")
    _assert_color(c, 10, 60, BG, "left of the plot area entirely -- background")


def test_render_gantt_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var start: List[Float64] = [10.0, 50.0]
    var end: List[Float64] = [40.0, 90.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<rect x="75" y="32" width="109" height="92" fill="#1e64b4"/>' in s, "A's own bar")
    assert_true('<rect x="220" y="147" width="145" height="92" fill="#1e64b4"/>' in s, "B's own bar")


def test_render_gantt_zero_length_span_floors_to_one_pixel() raises:
    # A milestone: start == end. _render_gantt's own docstring is
    # explicit this is real, informative data (a deadline marker), not
    # an absent value the way Mark.BULLET's own zero-measure case is --
    # floored to 1px rather than drawn as a genuinely zero-width
    # (invisible) rect the way a naive fill_rect call would.
    var cats: List[String] = ["Launch"]
    var start: List[Float64] = [50.0]
    var end: List[Float64] = [50.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_gantt().encode_gantt(cats, start, end).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('width="1"' in s, "the milestone's own bar, floored to a visible 1px width")


def test_render_gantt_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_gantt().encode_gantt(cats, one, one)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_gantt_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var empty = List[Float64]()
    var plot = Plot().mark_gantt().encode_gantt(cats, empty, empty)
    var c = Canvas(200, 150, BG)
    render(c, plot)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


def test_render_layers_raises_when_a_gantt_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # "Phase 2b"'s third and final mark -- see test_render_layers_raises_
    # when_a_lollipop_plot_is_included's own docstring for why this
    # needs no change to render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_gantt().encode_gantt(cats, one, one))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_grouped_bar_matches_hand_derived_rectangles() raises:
    # 2 categories ("A"/"B", short labels -- dynamic left margin stays
    # at Theme's own default 60, the same short-label convention every
    # other hand-derived test in this file already relies on), 2 series
    # -- `values[0]` (North) = [10, 20] (North's own value for A, then
    # B), `values[1]` (South) = [5, 15] (South's own value for A, then
    # B): North_A=10, North_B=20, South_A=5, South_B=15 -- easy to
    # mis-cross with North_A/South_A both "the first number," which is
    # exactly what a first pass at this test's own hand-derivation got
    # wrong before a real render() run caught it; the values below are
    # the corrected, confirmed ones. Canvas 400x300, default margins,
    # show_gridlines=False, show_legend left at its own default (True)
    # -- grouped bar always reserves a legend column, unlike plain
    # Mark.BAR, so the OrdinalScale's own range is [60, 250], not
    # [60, 380] (270 = 400 - Theme's own default 130px legend_width,
    # minus margin_right=20).
    #
    # y-domain: _zero_baseline_y_extent over every value (10, 20, 5, 15)
    # -> [0, 21] (zero already exact, so unpadded; 20's own +5% pad ->
    # 21). OrdinalScale over [60, 250], 2 categories, step=95,
    # bandwidth=76 (0.2 padding) -> band_start(A)=69.5, band_start(B)=
    # 164.5. sub_width = bandwidth/2 = 38. Every sub-bar's own left/
    # right edge computed as a *rounded boundary*, not an independently
    # rounded width -- see _render_grouped_bar's own docstring for why.
    #
    # Every position independently re-derived via python3 (LinearScale's
    # own slope/intercept for the y-axis, OrdinalScale's own band
    # formula for x, both re-solved for this shrunk-by-the-legend
    # range), then confirmed against a real render() run before trusting
    # it here.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var palette = default_categorical_palette()
    # A, North (series 0, value 10): x:[70,108), y:[140,250)
    _assert_color(c, 89, 200, palette[0], "A/North bar, well inside")
    # A, South (series 1, value 5): x:[108,146), y:[195,250)
    _assert_color(c, 127, 220, palette[1], "A/South bar, well inside")
    # B, North (series 0, value 20): x:[165,203), y:[31,250)
    _assert_color(c, 184, 100, palette[0], "B/North bar, well inside")
    # B, South (series 1, value 15): x:[203,241), y:[86,250)
    _assert_color(c, 222, 150, palette[1], "B/South bar, well inside")
    # The gap between A's own two sub-bars and B's own two sub-bars is
    # zero (consecutive-boundary rounding, no gap within a category) --
    # but there IS a real gap *between* categories A and B (OrdinalScale's
    # own 0.2 padding, band_start(B)=164.5 vs A's own band ending at
    # 69.5+76=145.5): x=155 sits in that inter-category gap at any y.
    _assert_color(c, 155, 150, BG, "the inter-category gap between A and B -- background")


def test_render_svg_grouped_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="140" width="38" height="110" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="108" y="195" width="38" height="55" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="165" y="31" width="38" height="219" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="203" y="86" width="38" height="164" fill="#ff7f0e"/>' in s, "B/South")

    # Legend: _draw_legend's own row layout (legend_swatch_size=14,
    # legend_row_gap=8) is already covered by Mark.POINT's/Mark.ARC's
    # own hand-derived legend tests -- this only confirms _render_
    # grouped_bar actually calls it with the right labels/palette/
    # starting position: x=plot_x1+margin_right=250+20=270, y=plot_y0=
    # 20 (row 0), row 1 at y=20+(14+8)=42.
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's own legend swatch"
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's own legend swatch"
    )


def test_render_grouped_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values)
    var c = Canvas(200, 150, BG)
    render(c, plot)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


def test_render_grouped_bar_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_grouped_bar_raises_on_mismatched_value_series_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_layers_raises_when_a_grouped_bar_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # the newest mark -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's own docstring for why this needs no change to
    # render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def test_render_stacked_bar_matches_hand_derived_rectangles() raises:
    # Same 2-category/2-series data test_render_grouped_bar_matches_
    # hand_derived_rectangles already hand-solved the axis frame for
    # (canvas 400x300, default margins, show_gridlines=False, legend
    # reserved -> OrdinalScale range [60,250], band_start(A)=69.5 ->70,
    # band_start(B)=164.5->165, bandwidth=76) -- all positive values
    # here, so only the *positive* running total ever moves. Per
    # category: North stacks first (bottom=0), South stacks on top of
    # it (bottom=North's own value). y-domain: _zero_baseline_y_extent
    # over each category's own *final* running total (A: 10+5=15, B:
    # 20+15=35) plus the always-included zero -> padded [0, 36.75].
    #
    # Every position independently re-derived via python3 (LinearScale's
    # own slope/intercept for the y-axis against this stacked-total
    # domain, OrdinalScale's own band formula for x, unchanged from
    # Mark.GROUPED_BAR's own -- full band width per segment here, not
    # divided sub-bars), then confirmed against a real render() run.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(t)
    var c = Canvas(400, 300, BG)
    render(c, plot)

    var palette = default_categorical_palette()
    # A, North (bottom segment, value 10): x:[70,146), y:[187,250)
    _assert_color(c, 100, 220, palette[0], "A/North segment, well inside")
    # A, South (top segment, value 5, stacked on North): x:[70,146), y:[156,187)
    _assert_color(c, 100, 170, palette[1], "A/South segment, stacked on top of North")
    # B, North (bottom segment, value 20): x:[165,241), y:[125,250)
    _assert_color(c, 195, 200, palette[0], "B/North segment, well inside")
    # B, South (top segment, value 15, stacked on North): x:[165,241), y:[31,125)
    _assert_color(c, 195, 80, palette[1], "B/South segment, stacked on top of North")
    # Unlike Mark.GROUPED_BAR, a stacked bar's own segments share the
    # *full* band width, so there's no gap between series within a
    # category -- but the inter-category gap (OrdinalScale's own 0.2
    # padding) is still there: x=155 sits in it at any y.
    _assert_color(c, 155, 150, BG, "the inter-category gap between A and B -- background")


def test_render_svg_stacked_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="187" width="76" height="63" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="70" y="156" width="76" height="31" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="165" y="125" width="76" height="125" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="165" y="31" width="76" height="94" fill="#ff7f0e"/>' in s, "B/South")
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's own legend swatch"
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's own legend swatch"
    )


def test_render_svg_stacked_bar_mixed_sign_stacks_independently_each_direction() raises:
    # One category ("A"), two series: North=10 (positive), South=-5
    # (negative) -- the one case test_render_stacked_bar_matches_hand_
    # derived_rectangles' own all-positive data can't exercise: a
    # negative value must stack *downward* from its own running
    # negative total (independent of North's own positive stack), not
    # slide North's own segment down by 5. y-domain: _zero_baseline_y_
    # extent over [pos_total=10, neg_total=-5] -> padded [-5.75, 10.75]
    # (span 15, 5% pad 0.75 each end, zero always included/kept exact).
    # band_start(0)=79 (1 category spans the whole OrdinalScale range,
    # no inter-category gap to speak of), bandwidth=152.
    #
    # Every position independently re-derived via python3, confirmed
    # against a real render_svg() run before trusting it here.
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    # North: data range [0,10] (positive stack, starts at zero).
    assert_true('<rect x="79" y="30" width="152" height="140" fill="#1f77b4"/>' in s, "North, above zero")
    # South: data range [-5,0] (negative stack, starts at zero, extends down).
    assert_true('<rect x="79" y="170" width="152" height="70" fill="#ff7f0e"/>' in s, "South, below zero")


def test_render_stacked_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values)
    var c = Canvas(200, 150, BG)
    render(c, plot)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


def test_render_stacked_bar_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_stacked_bar_raises_on_mismatched_value_series_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values)
    var c = Canvas(200, 150, BG)
    with assert_raises():
        render(c, plot)


def test_render_layers_raises_when_a_stacked_bar_plot_is_included() raises:
    # The same Mark.POINT/LINE/AREA-only allow-list checked again for
    # the newest mark -- see test_render_layers_raises_when_a_lollipop_
    # plot_is_included's own docstring for why this needs no change to
    # render_layers()'s own check.
    var line_x: List[Float64] = [0.0, 10.0]
    var line_y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    var plots = List[Plot]()
    plots.append(Plot().mark_line().encode(x=line_x, y=line_y))
    plots.append(Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values))
    var c = Canvas(400, 300, BG)
    with assert_raises():
        render_layers(c, plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
