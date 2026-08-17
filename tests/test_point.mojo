"""Tests for Mark.POINT (scatter): centering, custom theme colors,
color/size encoding, categorical color, SVG coordinates -- split out of
what used to be one big test_plot.mojo.
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
