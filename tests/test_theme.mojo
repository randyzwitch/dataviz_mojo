"""Tests for Theme.scale (uniform layout scaling and its purely-additive
default), Theme.font_family (threaded into every _TextRequest at
construction time, both backends), and Theme.title_bold (the one
Theme default that isn't backward-compatible).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import (
    Plot,
    _Scaled,
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
from dataviz_mojo.colors import RED
from dataviz_mojo.theme import Theme
from dataviz_mojo import scatter, waterfall, bullet, treemap, radialbar

from _test_helpers import BG, _count_color, _assert_color


def test_render_theme_scale_uniformly_scales_the_whole_layout() raises:
    # Theme.scale=2.0, paired with a canvas twice the width/height, is
    # meant to reproduce the exact same chart at twice the pixel
    # density -- so this reuses (not re-derives) test_render_point_
    # mark_centers_on_the_hand_derived_pixel's single-(5.0, 5.0)-
    # point setup, at 2x: canvas 800x600 (2x of 400x300), default
    # margins doubled by _Scaled (left=120, right=40, top=40,
    # bottom=100), giving a plot area of x:[120,760], y:[40,500] --
    # exactly 2x test_render_point_mark_centers_on_the_hand_derived_
    # pixel's x:[60,380], y:[20,250]. The point's pixel
    # (440, 270) is exactly double (220, 135) for the same reason:
    # LinearScale.to_pixel() of a domain's midpoint always lands
    # on the range's midpoint, and doubling a range's endpoints
    # doubles its midpoint too.
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
    # scale's default (1.0) must reproduce the exact pre-existing
    # unscaled render byte-for-byte -- not just "close", since every
    # pre-existing hand-derived pixel test in this file already
    # depends on that. Cross-checked directly here too: the identical
    # single-point setup, compared pixel-for-pixel between an explicit
    # Theme(scale=1.0) and Theme's bare default.
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
    # emits. Single point, canvas 400x300,
    # default theme otherwise: the same setup test_render_theme_scale_
    # uniformly_scales_the_whole_layout's 1x case reuses, so the
    # first tick label ("4.0" on the y-axis) lands at the same (60,
    # 271) that case's math establishes.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).theme(Theme(font_family="Georgia")).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="60" y="271" font-size="12.000" font-family="Georgia" fill="#282828"'
        ' text-anchor="middle">4.0</text>' in s,
        "a y-axis tick label, carrying the custom font_family",
    )


def test_render_theme_font_family_default_matches_sans_serif_explicit() raises:
    # font_family's bare default ("sans-serif") must reproduce the
    # exact same output as passing that same value explicitly -- the
    # same explicit-default-value guarantee test_render_theme_scale_
    # default_matches_unscaled_output_exactly proves for scale,
    # exercised through the actual construction-time-baked-in code
    # path rather than just trusting the parameter's default.
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
    # draw_text's raster path too, not only SvgCanvas.draw_text.
    # Sampling a small box around the first y-axis tick label ("4.0"
    # at pixel (60, 271), see the SVG test above) rather than a single
    # pixel: a font-shape difference shows up as *some* pixel in the
    # glyph's footprint changing, not necessarily every pixel or
    # any one specific one, so this counts differing pixels in a
    # small region around the label instead of asserting an exact
    # value -- a real, nonzero difference exists in that region.
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


def test_render_theme_title_bold_default_emits_font_weight_bold() raises:
    # title_bold's default (True) emits a literal font-weight="bold"
    # attribute on the title's <text> element. Single point, canvas 400x300,
    # title "Hi" -- the same no-legend geometry test_render_theme_
    # scale_uniformly_scales_the_whole_layout's 1x case
    # establishes, so the title lands at the same (220, 14) that
    # case's math implies for this canvas size.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).labels(title="Hi").size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" font-weight="bold"'
        ' fill="#282828" text-anchor="middle">Hi</text>' in s,
        "the title, bold by default",
    )


def test_render_theme_title_bold_false_reproduces_the_old_no_bold_output() raises:
    # title_bold=False must reproduce the plain title output -- no
    # font-weight attribute at all, not font-weight="normal". Same
    # setup as the default-bold test above.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).labels(title="Hi").theme(Theme(title_bold=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<text x="220" y="14" font-size="18.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="middle">Hi</text>' in s,
        "the title, title_bold=False reproduces the old un-bolded output",
    )


def test_render_theme_title_bold_only_affects_the_title() raises:
    # Bold is scoped to the chart title alone -- x_title/y_title (and
    # every other _TextRequest) stay normal weight regardless of
    # title_bold, matching Theme.title_bold's docstring ("one
    # deliberate exception, not a general knob"): with both an x_title
    # and a title present, exactly one font-weight="bold" attribute
    # appears in the whole document.
    var xy: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=xy, y=xy).labels(title="Hi", x_title="X").size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    var count = 0
    var search_from = 0
    while True:
        var idx = s.find('font-weight="bold"', search_from)
        if idx == -1:
            break
        count += 1
        search_from = idx + 1
    assert_equal(count, 1, "exactly one bold text element -- the title, not x_title")


def test_theme_mark_style_fields_actually_change_output() raises:
    # A default-vs-overridden render must differ somewhere, or the
    # field is wired to nothing. A total row is required: the
    # narrow-delta width only applies when the chart actually has
    # totals to contrast against (see _render_waterfall -- with no
    # totals every bar spans its full band, and this fraction is
    # correctly ignored) -- without one, this test would pass even
    # against a field wired to nothing.
    var cats: List[String] = ["a", "b", "total"]
    var vals: List[Float64] = [3.0, -2.0, 1.0]
    var totals: List[Bool] = [False, False, True]

    var base = waterfall(cats, vals, totals, theme=Theme(), width=200, height=150)
    var wide = waterfall(
        cats, vals, totals,
        theme=Theme(waterfall_delta_width_fraction=0.95), width=200, height=150,
    )
    assert_true(
        _count_color(base, Theme().mark_color) != _count_color(wide, Theme().mark_color),
        "waterfall_delta_width_fraction changes how much band a delta bar covers",
    )

    var measure: List[Float64] = [7.0]
    var target: List[Float64] = [8.0]
    var ranges: List[List[Float64]] = [[4.0, 6.0, 10.0]]
    var b_thin = bullet(cats0(), measure, target, ranges, theme=Theme(), width=200, height=150)
    var b_fat = bullet(
        cats0(), measure, target, ranges,
        theme=Theme(bullet_measure_width_fraction=0.9), width=200, height=150,
    )
    assert_true(
        _count_color(b_thin, Theme().mark_color) != _count_color(b_fat, Theme().mark_color),
        "bullet_measure_width_fraction changes the measure bar's thickness",
    )


def cats0() -> List[String]:
    return ["only"]


def test_theme_mark_colors_are_actually_used() raises:
    # treemap_label_color and radialbar_track_color are pure color
    # swaps -- assert the overridden color appears at all, which the
    # default palette would never produce on its own.
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var values: List[Float64] = [0.0, 5.0, 3.0]
    # Counted as "reddish" rather than exactly RED: quickplot renders
    # supersampled and downsamples, so an antialiased glyph keeps no
    # pixel at the pure source color. The label is unmistakably red
    # either way, which is what this asserts.
    var t = treemap(ids, parents, values, theme=Theme(treemap_label_color=RED), width=300, height=200)
    var reddish = 0
    for y in range(t.height):
        for x in range(t.width):
            var px = t.get_pixel(x, y)
            if px.r > 180 and px.g < 90 and px.b < 90:
                reddish += 1
    assert_true(reddish > 0, "treemap_label_color reaches the label")

    # Values must sit well below the maximum, or every ring sweeps a
    # full turn and there is no unfilled track left to color at all.
    var rb_cats: List[String] = ["x", "y"]
    var rb_vals: List[Float64] = [1.0, 8.0]
    var r = radialbar(
        rb_cats, rb_vals, theme=Theme(radialbar_track_color=RED), width=300, height=220
    )
    assert_true(_count_color(r, RED) > 0, "radialbar_track_color reaches the unfilled track")


def test_theme_layout_fields_reach_scaled() raises:
    # Layout fields differ from the mark-style fields above: these are
    # pixel quantities that must keep flowing through _Scaled, so a bare
    # "does the output change" check is not enough -- it must also
    # still multiply by Theme.scale for HiDPI.
    var t1 = Theme(tick_length=5)
    var t2 = Theme(tick_length=20)
    assert_equal(_Scaled(t1).tick_length, 5, "default tick_length reaches _Scaled")
    assert_equal(_Scaled(t2).tick_length, 20, "overridden tick_length reaches _Scaled")

    # .and still scales. 20 at scale 2.0 is 40, not 20.
    assert_equal(
        _Scaled(Theme(tick_length=20, scale=2.0)).tick_length, 40,
        "a themed tick_length is still multiplied by Theme.scale",
    )
    assert_equal(
        _Scaled(Theme(legend_width=200, scale=3.0)).legend_width, 600,
        "legend_width scales too",
    )

    # legend_swatch_size and continuous_legend_bar_width are
    # independent fields, not one defined in terms of the other --
    # changing the swatch must never silently move the gradient bar.
    var decoupled = _Scaled(Theme(legend_swatch_size=40))
    assert_equal(decoupled.legend_swatch_size, 40, "swatch size changed")
    assert_equal(
        decoupled.continuous_legend_bar_width, 14,
        "the gradient bar doesn't follow the swatch size",
    )


def test_theme_legend_width_actually_changes_layout() raises:
    # The end-to-end half: a wider legend column must take real space
    # away from the plot area, not just sit in _Scaled.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var cats: List[String] = ["alpha", "beta"]
    var narrow = render(Plot().mark_point().encode(x=x, y=y, color_categories=cats)
           .theme(Theme(legend_width=80, show_gridlines=False)).size(400, 300))
    var wide = render(Plot().mark_point().encode(x=x, y=y, color_categories=cats)
           .theme(Theme(legend_width=260, show_gridlines=False)).size(400, 300))
    assert_true(
        _count_color(narrow, BG) != _count_color(wide, BG),
        "legend_width changes how much canvas the plot area gets",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
