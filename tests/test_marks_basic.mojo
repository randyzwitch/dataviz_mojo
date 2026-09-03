"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_point.mojo`: Tests for Mark.POINT (scatter): centering, custom theme colors,
  color/size encoding, categorical color, SVG coordinates.

- `test_line.mojo`: Tests for Mark.LINE: drawing, line_smoothing (raster + SVG), and the
  _build_line_path Catmull-Rom-to-Bezier helper it's built on.

- `test_area.mojo`: Tests for Mark.AREA: fill region and area_smoothing (raster + SVG).

- `test_bar.mojo`: Tests for Mark.BAR: rectangles, negative values, dynamic left margin,
  color-by-sign.

- `test_histogram.mojo`: Tests for Plot.encode_histogram()'s binning and its render as an
  ordinary Mark.BAR chart.

- `test_lollipop.mojo`: Tests for Mark.LOLLIPOP: stem-and-point rendering (raster + SVG).

- `test_box.mojo`: Tests for Mark.BOX (boxplot): box/whiskers/outlier rendering (raster +
  SVG) and encode_boxplot() validation.

- `test_candlestick.mojo`: Tests for Mark.CANDLESTICK: wicks and bodies (raster + SVG).

- `test_waterfall.mojo`: Tests for Mark.WATERFALL: sign-colored bars, running total rows,
  connectors (raster + SVG).

- `test_bullet.mojo`: Tests for Mark.BULLET: qualitative range bands, measure, and target
  (raster + SVG).

"""

from _test_helpers import BG, _assert_color, _assert_near_color, _count_color
from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz import area, bar, box, bullet, candlestick, line, lollipop, scatter, waterfall
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
    # Single data point (5.0, 5.0) -- zero domain span, so
    # _data_extent pads +/-1.0 on each side, giving domain [4.0, 6.0]
    # for both axes. Canvas is 400x300 with Theme's default margins
    # (left=60, right=20, top=20, bottom=50), so the plot area is
    # x:[60,380], y:[20,250] -- exact integers throughout, hand-solved
    # from LinearScale's slope/intercept formula (not read off the
    # code's output): x_scale.to_pixel(5.0) = 220, y_scale.to_pixel
    # (5.0) = 135 (both land exactly on an integer, no rounding
    # ambiguity to worry about). Default point_radius=3.5 rounds
    # (round-half-away-from-zero) to a 4px radius, so (220,135) is
    # deep in the disk's fully-covered interior -- exact color match,
    # not just "some ink present". Built via scatter() (matches Plot().
    # mark_point().encode(x=x, y=y) + Canvas(400,300,BG) + render()
    # exactly -- see test_quickplot.mojo's test_scatter_matches_
    # manual_plot) rather than the fluent builder spelled out by hand.
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
    # Two points at x=[0,10], y=[0,0] (constant y -> zero-span domain,
    # padded to [-1,1], so y=0.0 maps to the plot area's exact
    # vertical midpoint, y=135 -- same hand-derivation as the size
    # test below). x-domain [0,10] pads to [-0.5,10.5], landing the
    # two points at pixel x=75 and x=365 (solved directly from
    # LinearScale's slope/intercept formula, cross-checked in Python,
    # not read off the code's output).
    #
    # color_data=[0.0,10.0] over a theme whose color_scale_low/high
    # are pure black/white -- the exact same domain and stops
    # test_color_scale.mojo's hand-verified test uses, so the two
    # points must land on exactly black and exactly white.
    # show_legend=False: this test is about the color-scale math, not
    # legend layout -- has_color now draws a continuous legend by
    # default (see the "Continuous color/size legends" wiki entry),
    # which would reserve horizontal space and shift these hand-derived
    # pixel positions. Legend layout itself is covered separately by
    # test_render_svg_continuous_color_legend_matches_hand_derived_gradient.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(
        color_scale_low=BLACK, color_scale_high=WHITE, show_legend=False
    )
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(t).size(400, 300)
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
    # Same two point positions (75,135)/(365,135) as the color test
    # above. size_data=[0.0,100.0] over a theme with a clean
    # size_range [2.0,10.0] -- point 0 gets radius 2, point 1 gets
    # radius 10 (both round-half-away-from-zero exact, no rounding
    # ambiguity). Checked by coverage at increasing distance from each
    # center, not by re-deriving fill_circle_aa's coverage math
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
    var plot = Plot().mark_point().encode(x=x, y=y, size=size).theme(t).size(400, 300)
    var c = render(plot)

    var mark_color = t.mark_color
    _assert_color(c, 75, 135, mark_color, "small point center")
    _assert_color(c, 78, 135, BG, "3px from small (radius 2) point -- outside")

    _assert_color(c, 365, 135, mark_color, "large point center")
    _assert_color(c, 368, 135, mark_color, "3px from large (radius 10) point -- still inside")
    _assert_color(c, 376, 135, BG, "11px from large (radius 10) point -- outside")


def test_render_categorical_color_matches_hand_derived_palette_entries() raises:
    # Different pixel centers than the continuous color test above --
    # color_categories automatically reserves a 130px legend column on
    # the right (see render()'s show_legend/legend_reserve), so
    # the plot area is narrower here (x range [60,250], not [60,380]):
    # the same x domain [-0.5,10.5] now lands the two points at pixel
    # x=69/241, not 75/365 -- solved directly from LinearScale's formula against the *narrowed* range, cross-checked in Python,
    # not read off the code's output. color_categories = ["A","B"]
    # -- two distinct categories in first-seen order, so point 0 gets
    # default_categorical_palette()[0], point 1 gets [1], not the
    # theme's continuous color_scale_low/high at all.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var cats: List[String] = ["A", "B"]
    var plot = Plot().mark_point().encode(x=x, y=y, color_categories=cats).size(400, 300)
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 69, 135, palette[0], "category A -> palette[0]")
    _assert_color(c, 241, 135, palette[1], "category B -> palette[1]")


def test_render_svg_point_mark_matches_hand_derived_coordinates() raises:
    # The exact same single-(5.0, 5.0)-point setup test_render_point_
    # mark_centers_on_the_hand_derived_pixel already hand-solved for
    # the raster path -- (220, 135), radius 4 -- confirming render_svg()
    # produces the identical circle through the shared _render_generic
    # core, not re-derived from scratch. Integer pixel coordinates
    # (from _round_to_int, not raw Path floats) can't drift between
    # languages/float implementations the way a raw float coordinate
    # could.
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
    # A horizontal line from (0,0) to (10,0) -- constant y means the
    # y-domain has zero span, padded to [-1.0, 1.0], so y=0.0 maps to
    # the exact vertical midpoint of the plot area. The line's midpoint in x similarly lands at the plot area's horizontal
    # midpoint. Checked as "not background" (real ink is present),
    # not an exact color match -- stroke_path_aa's coverage math
    # is already exhaustively tested in canvas itself; this only needs
    # to confirm Plot actually calls it, with a path that passes
    # through the expected point. Built via line() (matches Plot().
    # mark_line().encode(x=x, y=y) + Canvas(400,300,BG) + render()
    # exactly -- see test_quickplot.mojo's test_line_matches_
    # manual_plot) rather than the fluent builder spelled out by hand.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 0.0]
    var _hoisted1 = line(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var mid = c.get_pixel(220, 135)  # plot area's horizontal/vertical midpoint
    assert_true(mid.r != 255 or mid.g != 255 or mid.b != 255)


def test_build_line_path_zero_smoothing_is_a_plain_polyline() raises:
    # smoothing=0.0 must take the early "no curve math at all" branch,
    # not a degenerate curve formula: every command after the initial
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
    # line_smoothing's default (0.0) must reproduce the exact
    # pre-existing straight-segment render byte-for-byte -- not just
    # "close", the same "purely additive" bar every other Theme field
    # added to this package has had to clear (see e.g. Theme.scale's
    # equivalent test). A real 3-point line (a peak shape, not the
    # 2-point flat line the very first LINE test uses), compared
    # pixel-for-pixel across the whole canvas between Theme's bare
    # default and an explicit Theme(line_smoothing=0.0).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var _hoisted2 = line(x, y, width=400, height=300)
    var c_default = render(_hoisted2)
    var _hoisted3 = line(x, y, theme=Theme(line_smoothing=0.0), width=400, height=300)
    var c_explicit = render(_hoisted3)

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
    # show_gridlines=False. The straight-line path's first segment
    # runs from (74.545,239.545) to (220,30.455) -- its exact midpoint
    # is (147.27,135.0). A fully (1.0) smoothed Catmull-Rom curve
    # through the same three points bows well away from that point at
    # the same parameter: hand-derived via python3, the cubic Bezier's
    # own t=0.5 point lands at (138.18,121.93), about 13px away -- far
    # more than line_width=2.0 plus any AA fringe could reach. So
    # (147,135) is real ink under the straight line but background
    # under the fully smoothed one.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var _hoisted4 = line(
        x, y, theme=Theme(line_smoothing=0.0, show_gridlines=False), width=400, height=300
    )
    var c_straight = render(_hoisted4)
    var _hoisted5 = line(
        x, y, theme=Theme(line_smoothing=1.0, show_gridlines=False), width=400, height=300
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
    # Same x=[0,10,20], y=[0,10,0] peak as the raster test above --
    # every control-point coordinate independently derived via python3
    # from LinearScale's slope/intercept formula composed with the
    # Catmull-Rom tangent formula.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [0.0, 10.0, 0.0]
    var plot = Plot().mark_line().encode(x=x, y=y).theme(Theme(line_smoothing=1.0, show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,239.545 C98.788,204.697 171.515,30.455 220.000,30.455'
        ' C268.485,30.455 341.212,204.697 365.455,239.545" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in svg.to_string(),
        "the fully-smoothed LINE mark's two cubic segments",
    )


def test_render_line_raises_on_out_of_range_smoothing() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    with assert_raises():
        var _hoisted6 = line(x, y, theme=Theme(line_smoothing=-0.1), width=200, height=150)
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = line(x, y, theme=Theme(line_smoothing=1.1), width=200, height=150)
        _ = render(_hoisted7)


def test_render_raises_when_color_encoding_used_with_line_mark() raises:
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [1.0, 2.0]
    var color: List[Float64] = [1.0, 2.0]
    var plot = Plot().mark_line().encode(x=x, y=y, color=color).size(200, 150)
    with assert_raises():
        var c = render(plot)


def test_render_svg_line_mark_matches_confirmed_path_coordinates() raises:
    # x=[0,10], y=[5,5] (horizontal, zero-span y padded to [4,6] the
    # same way test_render_line_mark_draws_ink_between_the_two_
    # endpoints' data is) -- Path stores raw (unrounded) Float64
    # pixel coordinates, formatted through SvgCanvas's
    # `_format_svg_float` (3 decimal places -- see that function's
    # docstring for why raw `String(Float64)` isn't safe to assert
    # against here).
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [5.0, 5.0]
    var plot = Plot().mark_line().encode(x=x, y=y).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,135.000 L365.455,135.000" fill="none"'
        ' stroke="#1e64b4" stroke-width="2.000" stroke-linecap="round"'
        ' stroke-linejoin="round"/>' in svg.to_string(),
        "LINE mark's stroked path",
    )

# ---------------------------------------------------------------
# from tests/test_area.mojo
# ---------------------------------------------------------------

def test_render_area_mark_matches_hand_derived_fill_region() raises:
    # x=[0,10], y=[0,10] on a 400x300 canvas, default margins (plot
    # area x:[60,380], y:[20,250]). x lands at pixel 75/365 (same
    # domain math as every other continuous-x test above).
    # _zero_baseline_y_extent([0,10]) pads only the non-zero end,
    # giving domain [0,10.5], baseline pixel y=250, top-right point
    # pixel y=31 -- so the filled region is a right-triangle-ish area
    # from (75,250) up to (365,31) then back down to the baseline
    # (both solved directly from LinearScale's formula, cross-
    # checked in Python). Interpolating that top edge at pixel x=220
    # (the plot's horizontal midpoint) puts it at y=140.5 -- a
    # point comfortably below that (y=200) must be filled, a point
    # comfortably above it (y=50) must still be background.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = area(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 200, t.mark_color, "inside the filled area")
    _assert_color(c, 220, 50, BG, "above the area's top edge -- background")


def test_render_svg_area_smoothing_matches_hand_derived_curve() raises:
    # x=[0,10,20], y=[2,10,4] (a peak, deliberately not touching zero at
    # either end -- unlike this data's y=0 endpoints would, which
    # would make the closing line_to()s down to baseline degenerate,
    # zero-length segments landing exactly on the curve's last
    # point; not wrong, just a less illustrative hand-derivation).
    # Canvas 400x300, default margins, show_gridlines=False.
    # _zero_baseline_y_extent([2,10,4]) -> domain [0, 10.5] (zero
    # already exact; 10's +5% pad -> 10.5) -- the *top* edge only
    # (px/py, the same LinearScale math Mark.LINE's equivalent test
    # established the technique for) is smoothed; the two
    # line_to()s down to/along baseline (pixel y=250, to_pixel(0.0))
    # stay straight, but that baseline sits exactly on the drawn
    # bottom axis line, so it's pulled 1px up to y=249 before either
    # line_to() -- see _pull_off_axis_line's docstring (plot.mojo).
    # Every control-point coordinate independently re-derived via
    # python3.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var plot = Plot().mark_area().encode(x=x, y=y).theme(
        Theme(line_smoothing=1.0, show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    assert_true(
        '<path d="M74.545,206.190 C98.788,176.984 171.515,38.254 220.000,30.952'
        ' C268.485,23.651 341.212,140.476 365.455,162.381 L365.455,249.000'
        ' L74.545,249.000 Z" fill="#1e64b4"/>' in svg.to_string(),
        "the smoothed top edge, then two straight line_to()s down to baseline, closed",
    )


def test_render_area_smoothing_default_matches_straight_output_exactly() raises:
    # line_smoothing's default (0.0) must reproduce the exact pre-
    # existing straight-edged Mark.AREA render byte-for-byte -- the same
    # "purely additive" bar every optional Theme field has had to clear
    # (see e.g. Mark.LINE's equivalent test). Compared pixel-for-
    # pixel across the whole canvas between Theme's bare default and
    # an explicit Theme(line_smoothing=0.0).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var _hoisted2 = area(x, y, width=400, height=300)
    var c_default = render(_hoisted2)
    var _hoisted3 = area(x, y, theme=Theme(line_smoothing=0.0), width=400, height=300)
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
        var _hoisted4 = area(x, y, theme=Theme(line_smoothing=-0.1), width=200, height=150)
        _ = render(_hoisted4)
    with assert_raises():
        var _hoisted5 = area(x, y, theme=Theme(line_smoothing=1.1), width=200, height=150)
        _ = render(_hoisted5)

# ---------------------------------------------------------------
# from tests/test_bar.mojo
# ---------------------------------------------------------------

def test_render_bar_mark_matches_hand_derived_bar_rectangles() raises:
    # 3 categories, y=[10,20,15], canvas 400x300 with default margins
    # (plot area x:[60,380], y:[20,250]). _zero_baseline_y_extent pads
    # [0,20] up to [0,21.0] (5% of the 20-span, only on the non-zero end -- see
    # that function's docstring), giving baseline pixel y=250 and
    # tops at y=140/31/86 for values 10/20/15 respectively.
    # OrdinalScale's default 0.2 padding over range [60,380] (step
    # 106.667, bandwidth 85.333) puts each band's left edge at
    # x=71/177/284, all solved directly from LinearScale/OrdinalScale's
    # formulas (cross-checked in Python), not read off the code's
    # output. Gridlines off to keep the checked pixels unambiguous.
    # Built via bar() (matches Plot().mark_bar().encode_categorical(x=x,
    # y=y).theme(t) + Canvas(400,300,t.background) + render() exactly --
    # see test_quickplot.mojo's test_bar_matches_manual_plot) rather
    # than the fluent builder spelled out by hand, so this test tracks
    # the render path a real caller actually uses.
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


def test_render_bar_empty_data_only_fills_background() raises:
    var plot = Plot().mark_bar().size(50, 40)  # no encode_categorical() call
    var c = render(plot)
    var expected = Theme.default().background
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            assert_equal(p.r, expected.r)
            assert_equal(p.g, expected.g)
            assert_equal(p.b, expected.b)


def test_render_bar_negative_values_extend_below_the_baseline() raises:
    # A single negative bar -- _zero_baseline_y_extent's domain is
    # [lo-pad, 0] (hi stays exactly 0, unpadded, since no value is above zero --
    # see that function's docstring), so the baseline sits at the
    # *top* of the bar's drawn rectangle, not its bottom the way
    # every positive-only bar in the test above has it.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted3)

    # Baseline (value 0) is the domain's unpadded top edge, so it
    # lands exactly at the plot area's top, pixel y=20 -- a
    # pixel just below that, well inside the bar's single wide band,
    # must already be the mark color.
    _assert_color(c, 220, 25, t.mark_color, "just below the zero baseline, inside the bar")
    # Well above the plot area entirely -- background regardless.
    _assert_color(c, 220, 5, BG, "above the plot area")


def test_render_svg_bar_mark_matches_confirmed_rect() raises:
    # Same 3-category/[10,20,15] data test_render_bar_mark_matches_
    # hand_derived_bar_rectangles already hand-solved (bar 1's rect:
    # x=177, y=31, width=85, baseline_py=250, so height would be 219 --
    # but the bar's bottom edge sits exactly on the drawn axis line
    # (250), so _pull_off_axis_line shrinks it 1px to 218, leaving a
    # hairline of background between the bar and the axis line (see
    # that function's docstring, plot.mojo).
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [10.0, 20.0, 15.0]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    assert_true(
        '<rect x="177" y="31" width="85" height="218" fill="#1e64b4"/>' in svg.to_string(),
        "BAR mark's middle bar, same rectangle render()'s hand-derived test finds",
    )


def test_render_bar_color_by_sign_colors_negative_bars_differently() raises:
    # The exact single-negative-bar setup test_render_bar_negative_
    # values_extend_below_the_baseline already hand-solved (canvas
    # 400x300, no gridlines, single category "a" at value -10 -- the
    # baseline sits at the plot area's top, pixel y=20, so (220,25)
    # is just inside the bar). Theme.color_by_sign=True switches that
    # exact pixel from mark_color to mark_color_negative -- confirming
    # the flag is actually read, not just accepted and ignored.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var _hoisted4 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted4)
    _assert_color(c, 220, 25, t.mark_color_negative, "negative bar uses mark_color_negative")


def test_render_bar_color_by_sign_leaves_positive_bars_at_mark_color() raises:
    # Same setup, value flipped positive (+10, not -10) -- baseline
    # now sits at the plot area's *bottom* (see the sibling
    # positive-values test this data shape matches), so the well-
    # inside-the-bar pixel is (220, 245), just above the baseline
    # (250) instead of just below the top (20).
    var x: List[String] = ["a"]
    var y: List[Float64] = [10.0]
    var t = Theme(show_gridlines=False, color_by_sign=True)
    var _hoisted5 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted5)
    _assert_color(c, 220, 245, t.mark_color, "positive bar stays mark_color even with color_by_sign on")


def test_render_bar_color_by_sign_defaults_off() raises:
    # color_by_sign's default (False) must reproduce the exact
    # pre-existing single-negative-bar test's assertion -- a
    # negative bar still just mark_color, not mark_color_negative,
    # when the flag is never set. Purely additive, confirmed the same
    # way every other Theme addition in this file has been.
    var x: List[String] = ["a"]
    var y: List[Float64] = [-10.0]
    var t = Theme(show_gridlines=False)
    var _hoisted6 = bar(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted6)
    _assert_color(c, 220, 25, t.mark_color, "color_by_sign defaults off: still mark_color")

# ---------------------------------------------------------------
# from tests/test_histogram.mojo
# ---------------------------------------------------------------

def test_encode_histogram_bins_match_hand_derived_counts() raises:
    # 10 values, 5 bins -- bin_width=(9.0-1.0)/5=1.6, counts hand-
    # solved via python3: [3, 3, 2, 0, 2] (bin 3, [5.8,7.4), empty --
    # confirms encode_histogram doesn't skip empty bins, they're a
    # real 0-count category like any other). 9.0 (data's max)
    # lands in the last bin (would otherwise compute an out-of-range
    # index bins itself) -- see this method's docstring for why.
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
    # Mark.BAR's rendering math (already exhaustively covered by
    # test_render_bar_mark_matches_hand_derived_bar_rectangles and
    # friends -- encode_histogram() feeds the identical render path,
    # just with computed rather than given categories/counts).
    var data: List[Float64] = [1.0, 1.0, 1.0, 5.0, 9.0]
    var plot = Plot().mark_bar().encode_histogram(data, bins=3).theme(Theme(show_gridlines=False)).size(400, 300)
    var c = render(plot)
    # Bin 0 ([1.0, 3.667)) holds 3 of the 5 values -- its bar
    # should be the tallest, definitely not still just background at
    # the vertical center of the plot area.
    var mid_of_plot_area = c.get_pixel(113, 135)
    assert_true(
        mid_of_plot_area.r != 255 or mid_of_plot_area.g != 255 or mid_of_plot_area.b != 255,
        "bin 0's bar (3 of 5 values) reaches well above the plot area's midpoint",
    )

# ---------------------------------------------------------------
# from tests/test_lollipop.mojo
# ---------------------------------------------------------------

def test_render_lollipop_matches_hand_derived_stem_and_point() raises:
    # Exactly test_render_bar_mark_matches_hand_derived_bar_rectangles'
    # data/canvas/theme (3 categories, y=[10,20,15], 400x300,
    # default margins, gridlines off) -- Mark.LOLLIPOP shares Mark.BAR's
    # encode_categorical() data shape and _zero_baseline_y_extent
    # domain, so category "b"'s band center (220.0, an exact value
    # -- band_start(1)=177.333 + bandwidth/2=42.667) and value-20 pixel
    # (30.952, rounds to 31 -- the same "tops at y=31" the bar test
    # confirmed) carry over unchanged; only the *shape* drawn
    # at those coordinates differs.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = lollipop(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 31, t.mark_color, "circle center, category b's value pixel")
    _assert_color(c, 220, 150, t.mark_color, "stem midpoint, well within the 2px-wide stroke")
    _assert_color(c, 210, 150, BG, "off the stem entirely -- background")
    _assert_color(c, 220, 10, BG, "above the point -- nothing drawn there")


def test_render_lollipop_svg_matches_confirmed_stem_and_point() raises:
    # Baseline (250.000) sits exactly on the drawn bottom axis line, so
    # the stem's start point is pulled 1px up to 249.000 -- see
    # _pull_off_axis_line's docstring (plot.mojo).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [10.0, 20.0, 15.0]
    var plot = Plot().mark_lollipop().encode_categorical(x=x, y=y).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,249.000 L220.000,30.952" fill="none" stroke="#1e64b4"'
        ' stroke-width="2.000" stroke-linecap="round" stroke-linejoin="round"/>' in s,
        "category b's stem",
    )
    assert_true('<circle cx="220" cy="31" r="4" fill="#1e64b4"/>' in s, "category b's point")


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
    # low_whisker=2, high_whisker=9, one outlier at 20 -- 1.5*IQR fence
    # is [4-4.5, 7+4.5]=[-0.5, 11.5], so 20 is the only value beyond
    # it), "B" = [10,12,14,15,18] (q1=12, median=14, q3=15, low=10,
    # high=18, no outliers -- fence [7.5, 19.5] contains every value).
    # Both hand-derived via the same linear-interpolation percentile
    # `_box_stats` itself uses (independently reimplemented in
    # Python, not just re-run through the Mojo code).
    # Domain = _data_extent over every low/high/outlier value
    # ([2,9,10,18,20]) = [1.1, 20.9], 2 categories over [60,380] (band
    # centers 140/300, bandwidth 128, half-width 64, cap half-width 32).
    # Built via Plot/Canvas/render() directly, not box() -- these are
    # exact hand-derived pixel positions (see this function's comment
    # above); this test predates quickplot returning a plain,
    # un-rendered `Plot` (dataviz.plot._finished's docstring),
    # render() being the exact same path box()'s own output would go
    # through now too.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_box().encode_boxplot(cats, values).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 200, t.mark_color, "A: inside the box (between q1 and q3)")
    # The median line and whisker checks below use `_assert_near_color()`
    # -- both are 1px-wide strokes, the same reason every other mark's
    # axis-line/gridline checks already need the tolerant helper (see
    # its docstring, tests/_test_helpers.mojo). The high-whisker cap
    # still lands exact at its own sampled position, so it keeps
    # `_assert_color()`.
    _assert_near_color(c, 140, 205, t.axis_color, 70, "A: the median line, drawn over the box fill")
    _assert_near_color(c, 140, 170, t.axis_color, 60, "A: the upper whisker, between q3 and high")
    _assert_color(c, 120, 158, t.axis_color, "A: the high-whisker cap")
    _assert_color(c, 140, 30, t.mark_color, "A: the one outlier point, at value 20")
    _assert_color(c, 300, 105, t.mark_color, "B: inside the box")
    _assert_near_color(c, 300, 100, t.axis_color, 40, "B: the median line")
    _assert_near_color(c, 300, 70, t.axis_color, 60, "B: the lower whisker, between q1 and low")
    _assert_color(c, 190, 150, BG, "the gap between A's and B's bands -- background")


def test_render_boxplot_svg_matches_confirmed_rects_and_outlier() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var plot = Plot().mark_box().encode_boxplot(cats, values).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="76" y="181" width="128" height="35" fill="#1e64b4"/>' in s, "A's box (q1 to q3)")
    assert_true('<rect x="236" y="89" width="128" height="35" fill="#1e64b4"/>' in s, "B's box (q1 to q3)")
    assert_true('<circle cx="140" cy="30" r="4" fill="#1e64b4"/>' in s, "A's single outlier, at value 20")


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
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = O10/H15/L8/C13
    # (closed up, close >= open); "B" = O20/H22/L16/C17 (closed down).
    # Domain = _data_extent over every O/H/L/C value ([8,22]; no zero
    # baseline, matching Mark.BOX's reasoning) padded 5% of the
    # 14-span = [7.3, 22.7]. Same 2-category OrdinalScale over [60,380]
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_outlier
    # already worked out (bands at x=76/236, width 128, centers 140/300)
    # -- only the y-domain and per-category shape differ here. Every
    # pixel below independently computed via python3 from
    # LinearScale's slope/intercept formula.
    # Built via Plot/Canvas/render() directly, not candlestick() -- see
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_
    # outlier's comment for why an exact hand-derived pixel check
    # uses render() itself rather than the (now internally
    # supersampled) quickplot wrapper.
    #
    # The 4 wick checks use `_assert_near_color()`, not `_assert_
    # color()` -- a wick is a 1px-wide stroke, the same reason every
    # other mark's axis-line/gridline checks already need the
    # tolerant helper (see its docstring, tests/_test_helpers.mojo).
    # The 2 body checks (solid interior) and the background check (a
    # wide-open empty area) stay exact -- both robust by construction.
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_color(c, 140, 200, t.mark_color, "A: inside the body (open=210 to close=165), closed up")
    _assert_near_color(c, 140, 150, t.axis_color, 60, "A: the wick, above the body (between high=135 and the body top)")
    _assert_near_color(c, 140, 225, t.axis_color, 60, "A: the wick, below the body (between the body bottom and low=240)")
    _assert_color(c, 300, 80, t.mark_color_negative, "B: inside the body (open=60 to close=105), closed down")
    _assert_near_color(c, 300, 45, t.axis_color, 60, "B: the wick, above the body (between high=30 and the body top)")
    _assert_near_color(c, 300, 115, t.axis_color, 60, "B: the wick, below the body (between the body bottom and low=120)")
    _assert_color(c, 190, 150, BG, "no ink here -- off the wick's x, above A's body")


def test_render_candlestick_svg_matches_confirmed_wicks_and_bodies() raises:
    var cats: List[String] = ["A", "B"]
    var open: List[Float64] = [10.0, 20.0]
    var high: List[Float64] = [15.0, 22.0]
    var low: List[Float64] = [8.0, 16.0]
    var close: List[Float64] = [13.0, 17.0]
    var plot = Plot().mark_candlestick().encode_candlestick(cats, open, high, low, close).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<line x1="140" y1="135" x2="140" y2="240" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "A's wick, from high=135 to low=240",
    )
    assert_true('<rect x="76" y="165" width="128" height="45" fill="#1e64b4"/>' in s, "A's body, closed up")
    assert_true(
        '<line x1="300" y1="30" x2="300" y2="120" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "B's wick, from high=30 to low=120",
    )
    assert_true(
        '<rect x="236" y="60" width="128" height="45" fill="#c83c3c"/>' in s, "B's body, closed down"
    )


def test_render_candlestick_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = candlestick(cats, open, high, low, close, width=200, height=150)
        _ = render(_hoisted2)


def test_render_candlestick_raises_on_mismatched_ohlc_length() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [1.0, 2.0]
    var high: List[Float64] = [1.0, 2.0]
    var low: List[Float64] = [1.0, 2.0]
    var close: List[Float64] = [1.0]
    with assert_raises():
        var _hoisted3 = candlestick(cats, open, high, low, close, width=200, height=150)
        _ = render(_hoisted3)

# ---------------------------------------------------------------
# from tests/test_waterfall.mojo
# ---------------------------------------------------------------

def test_render_waterfall_colors_by_sign_and_matches_hand_derived_bars() raises:
    # 3 categories, deltas=[10, -4, 6] -- running totals y0/y1 = [0,10,
    # 10,6, 6,12]. Combined domain [0, 12.6] (_zero_baseline_y_extent
    # over y0 union y1) lands each category's band at the *same*
    # x positions test_render_bar_mark_matches_hand_derived_bar_
    # rectangles confirmed (113/220/327 centers) since both use
    # the identical 3-category OrdinalScale over the same [60,380]
    # range -- only the y-domain and per-bar y0/y1 differ. Per bar:
    # bar 0 (delta +10) mark_color, bar 1 (delta -4) mark_color_
    # negative -- unconditional sign coloring, no Theme.color_by_sign
    # flag needed, unlike Mark.BAR -- bar 2 (delta +6) mark_color again,
    # and the two connector lines (gridline_color) at the pixel height
    # where consecutive bars' running totals hand off.
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = waterfall(cats, deltas, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 113, 150, t.mark_color, "bar 0 (delta +10), well inside its rect")
    _assert_color(c, 220, 100, t.mark_color_negative, "bar 1 (delta -4), colored by sign")
    _assert_color(c, 327, 80, t.mark_color, "bar 2 (delta +6), back to mark_color")
    _assert_color(c, 165, 67, t.axis_color, "connector between bar 0 and bar 1")
    _assert_color(c, 273, 140, t.axis_color, "connector between bar 1 and bar 2")
    _assert_color(c, 350, 10, BG, "far from every bar -- background")


def test_render_waterfall_svg_matches_confirmed_rects_and_connectors() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        # y0=0 is the baseline, and it lands exactly on the drawn bottom
        # axis line here (unlike bars 1/2's y0/y1, neither of which is
        # 0) -- height shrinks 183 -> 182, pulled 1px off that line --
        # see _pull_off_axis_line's docstring (plot.mojo).
        '<rect x="71" y="67" width="85" height="182" fill="#1e64b4"/>' in s, "bar 0 (delta +10): y0=0 to y1=10"
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
    with assert_raises():
        var _hoisted2 = waterfall(cats, deltas, width=200, height=150)
        _ = render(_hoisted2)


def test_render_waterfall_total_rows_matches_hand_derived_bars() raises:
    # 4 categories: "Start" (total, delta=50 -- a starting-balance total
    # still *adds* its delta to the running sum, just displays 0 ->
    # the result instead of floating -- see encode_waterfall()'s docstring), "A" (delta +20, plain), "B" (delta -10, plain), "End"
    # (total, delta=0 -- contributes nothing further, displays 0 -> the
    # final running sum). Running sum: Start 0+50=50 (y0=0,y1=50), A
    # 50+20=70 (y0=50,y1=70), B 70-10=60 (y0=70,y1=60), End 60+0=60
    # (y0=0,y1=60). Canvas 400x300, default margins, show_gridlines=
    # False. _zero_baseline_y_extent over the combined y0/y1 set
    # {0,50,70,60} -> domain [0, 73.5] (70's +5% pad).
    #
    # OrdinalScale over [60,380], 4 categories, step=80, bandwidth=64 ->
    # band_start: Start=68, A=148, B=228, End=308. Total bars draw full
    # band width (64px); delta bars draw theme.waterfall_delta_width_fraction
    # (0.6) of it, centered -- narrow=38.4, inset=12.8, so A/B's bars are inset ~13px from their band's edges on both sides.
    #
    # Every position independently re-derived via python3 (LinearScale's
    # slope/intercept for y, OrdinalScale's band formula for x).
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = waterfall(cats, deltas, is_total=is_total, theme=t, width=400, height=300)
    var c = render(_hoisted3)

    # Start (total): x:[68,132), y:[94,250) -- full band width.
    _assert_color(c, 100, 200, t.waterfall_total_color, "Start (total), well inside")
    # A (delta +20, narrower): x:[161,199), y:[31,94).
    _assert_color(c, 180, 60, t.mark_color, "A (delta +20), well inside its narrower rect")
    # A's band still has real background on either side of the
    # narrow bar -- confirming it actually IS narrower, not just a
    # differently-colored full-width bar.
    _assert_color(c, 150, 60, BG, "A's band, left of its narrow bar -- background")
    # B (delta -10, narrower): x:[241,279), y:[31,62).
    _assert_color(c, 260, 45, t.mark_color_negative, "B (delta -10), colored by sign")
    # End (total): x:[308,372), y:[62,250) -- full band width again.
    _assert_color(c, 340, 150, t.waterfall_total_color, "End (total), well inside")


def test_render_svg_waterfall_total_rows_matches_confirmed_rects() raises:
    var cats: List[String] = ["Start", "A", "B", "End"]
    var deltas: List[Float64] = [50.0, 20.0, -10.0, 0.0]
    var is_total: List[Bool] = [True, False, False, True]
    var plot = Plot().mark_waterfall().encode_waterfall(cats, deltas, is_total).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        # Both total rows' y0=0 is the baseline, and it lands exactly on
        # the drawn bottom axis line -- each height pulled 1px off that
        # line (156->155, 188->187 below); A/B's y0/y1 are never 0, so
        # neither of theirs moves. See _pull_off_axis_line's docstring
        # (plot.mojo).
        '<rect x="68" y="94" width="64" height="155" fill="#646464"/>' in s, "Start (total): 0 -> 50"
    )
    assert_true('<rect x="161" y="31" width="38" height="63" fill="#1e64b4"/>' in s, "A: 50 -> 70")
    assert_true('<rect x="241" y="31" width="38" height="31" fill="#c83c3c"/>' in s, "B: 70 -> 60")
    assert_true(
        '<rect x="308" y="62" width="64" height="187" fill="#646464"/>' in s, "End (total): 0 -> 60"
    )
    # Connectors reference each bar's *actual* drawn edge (`bar_x_
    # list[i-1] + bar_width_list[i-1]`, not a formula re-derived from
    # the band directly) once total rows are in play -- guards
    # against a 1px mismatch between a full-width bar's
    # independently-rounded width and a boundary-rounded connector
    # position. Start's right edge (68+64=132) ->
    # A's left edge (161); A's right edge (161+38=199) -> B's
    # left edge (241); B's right edge (241+38=279) -> End's left edge (308).
    assert_true(
        '<line x1="132" y1="94" x2="161" y2="94" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: Start's actual right edge -> A's left edge",
    )
    assert_true(
        '<line x1="199" y1="31" x2="241" y2="31" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: A's actual right edge -> B's left edge",
    )
    assert_true(
        '<line x1="279" y1="62" x2="308" y2="62" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "connector: B's actual right edge -> End's left edge",
    )


def test_render_waterfall_raises_on_mismatched_is_total_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var deltas: List[Float64] = [10.0, -4.0, 6.0]
    var is_total: List[Bool] = [True, False]
    with assert_raises():
        var _hoisted4 = waterfall(cats, deltas, is_total=is_total, width=400, height=300)
        _ = render(_hoisted4)

# ---------------------------------------------------------------
# from tests/test_bullet.mojo
# ---------------------------------------------------------------

def test_render_bullet_matches_hand_derived_bands_measure_and_target() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = ranges=[40,70,100],
    # measure=55, target=65; "B" = ranges=[30,60,90], measure=75,
    # target=50. Domain data = {0, range-top, measure, target} per
    # category = [0,100,55,65, 0,90,75,50] -> _zero_baseline_y_extent
    # gives lo=min(0,0)=0 (unpadded, already at zero), hi=max(0,100)=100
    # padded 5% of the 100-span to 105 -- domain [0, 105]. Same
    # 2-category OrdinalScale over [60,380] every other categorical test
    # establishes (bands at x=76/236, width 128, centers
    # 140/300). Every pixel below independently computed via python3
    # from LinearScale's slope/intercept formula (scale=(20-250)/
    # 105=-2.190476., translate=250).
    # Built via Plot/Canvas/render() directly, not bullet() -- see
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_
    # outlier's comment for why an exact hand-derived pixel check
    # uses render() itself rather than the (now internally
    # supersampled) quickplot wrapper.
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_bullet().encode_bullet(cats, measures, targets, ranges).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_color(c, 90, 200, Color(224, 224, 224), "A: lightest range band [0,40], off the measure bar")
    _assert_color(c, 90, 130, Color(172, 172, 172), "A: middle range band [40,70], off the measure bar")
    _assert_color(c, 90, 60, Color(120, 120, 120), "A: darkest range band [70,100], off the measure bar")
    _assert_color(c, 140, 200, t.mark_color, "A: inside the measure bar (0 to 55), over the bands")
    # A's target tick, not B's: `render()`'s supersample-then-downsample
    # (`_RASTER_SUPERSAMPLE`, plot.mojo) doesn't land this particular
    # 1px-wide stroke fully opaque at this column -- B's target tick
    # below, at a different pixel position, still does (see
    # `_assert_near_color`'s docstring, tests/_test_helpers.mojo).
    _assert_near_color(c, 90, 108, t.axis_color, 65, "A: the target tick (65), off the measure bar")
    _assert_color(c, 140, 10, BG, "A: above every band -- background")
    _assert_color(c, 300, 150, t.mark_color, "B: inside the measure bar (0 to 75)")
    _assert_color(c, 250, 140, t.axis_color, "B: the target tick (50), off the measure bar")
    _assert_color(c, 220, 150, BG, "the gap between A's and B's bands -- background")


def test_render_bullet_svg_matches_confirmed_bands_measure_and_target() raises:
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var plot = Plot().mark_bullet().encode_bullet(cats, measures, targets, ranges).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    # The lightest band's bottom (prev_threshold=0) and the measure
    # bar's bottom (baseline=0) both land exactly on the drawn bottom
    # axis line, so both heights are pulled 1px off it (88->87,
    # 120->119) -- the middle/darkest bands and the target tick never
    # touch 0, so theirs are unaffected. See _pull_off_axis_line's
    # docstring (plot.mojo).
    assert_true('<rect x="76" y="162" width="128" height="87" fill="#e0e0e0"/>' in s, "A's lightest band [0,40]")
    assert_true('<rect x="76" y="97" width="128" height="65" fill="#acacac"/>' in s, "A's middle band [40,70]")
    assert_true('<rect x="76" y="31" width="128" height="66" fill="#787878"/>' in s, "A's darkest band [70,100]")
    assert_true('<rect x="118" y="130" width="45" height="119" fill="#1e64b4"/>' in s, "A's measure bar")
    assert_true(
        '<line x1="76" y1="108" x2="204" y2="108" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
