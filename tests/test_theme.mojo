"""Tests for Theme.scale (uniform layout scaling and its purely-additive
default) and Theme.font_family (threaded into every _TextRequest at
construction time, both backends) -- split out of what used to be one
big test_plot.mojo.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
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
from dataviz_mojo import scatter

from _test_helpers import _count_color, _assert_color


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
    var c = scatter(xy, xy, theme=t, width=800, height=600)

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
    var c_default = scatter(xy, xy, width=400, height=300)
    var c_explicit = scatter(xy, xy, theme=Theme(scale=1.0), width=400, height=300)

    for y in range(c_default.height):
        for x in range(c_default.width):
            var p_default = c_default.get_pixel(x, y)
            var p_explicit = c_explicit.get_pixel(x, y)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_theme_font_family_reaches_svg_output() raises:
    # A custom font_family ("Georgia") shows up as a literal
    # font-family="Georgia" attribute on every <text> element SVG
    # emits -- confirmed via a real render_svg() run first (not
    # assumed from the plumbing alone). Single point, canvas 400x300,
    # default theme otherwise: the same setup test_render_theme_scale_
    # uniformly_scales_the_whole_layout's own 1x case reuses, so the
    # first tick label ("4.0" on the y-axis) lands at the same (60,
    # 271) that case's own math already establishes.
    var xy: List[Float64] = [5.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(font_family="Georgia"))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<text x="60" y="271" font-size="12.000" font-family="Georgia" fill="#282828"'
        ' text-anchor="middle">4.0</text>' in s,
        "a y-axis tick label, carrying the custom font_family",
    )


def test_render_theme_font_family_default_matches_sans_serif_explicit() raises:
    # font_family's own bare default ("sans-serif") must reproduce the
    # exact same output as passing that same value explicitly -- the
    # same explicit-default-value guarantee test_render_theme_scale_
    # default_matches_unscaled_output_exactly proves for scale,
    # exercised through the actual construction-time-baked-in code
    # path rather than just trusting the parameter's own default.
    var xy: List[Float64] = [5.0]
    var c_default = scatter(xy, xy, width=400, height=300)
    var c_explicit = scatter(xy, xy, theme=Theme(font_family="sans-serif"), width=400, height=300)

    for y in range(c_default.height):
        for x in range(c_default.width):
            var p_default = c_default.get_pixel(x, y)
            var p_explicit = c_explicit.get_pixel(x, y)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_theme_font_family_actually_changes_raster_glyphs() raises:
    # A genuinely different family (monospace, vs. the default sans-
    # serif) must change the actual rendered raster glyphs, not just
    # the SVG markup -- proof `family` reaches canvas_mojo.text.
    # draw_text's own raster path too, not only SvgCanvas.draw_text.
    # Sampling a small box around the first y-axis tick label ("4.0"
    # at pixel (60, 271), see the SVG test above) rather than a single
    # pixel: a font-shape difference shows up as *some* pixel in the
    # glyph's own footprint changing, not necessarily every pixel or
    # any one specific one, so this counts differing pixels in a
    # small region around the label instead of asserting an exact
    # value -- confirmed via a real render() run first that a real,
    # nonzero difference exists there before trusting this test.
    var xy: List[Float64] = [5.0]
    var c_sans = scatter(xy, xy, theme=Theme(font_family="sans-serif"), width=400, height=300)
    var c_mono = scatter(xy, xy, theme=Theme(font_family="monospace"), width=400, height=300)

    var diff_count = 0
    for y in range(260, 280):
        for x in range(45, 75):
            var p1 = c_sans.get_pixel(x, y)
            var p2 = c_mono.get_pixel(x, y)
            if p1.r != p2.r or p1.g != p2.g or p1.b != p2.b:
                diff_count += 1
    assert_true(diff_count > 0, "monospace vs sans-serif must render visibly different glyphs")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
