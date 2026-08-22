"""Tests for categorical/continuous legends: swatch positions, continuous
color/size legends, dynamic legend-column width -- split out of what
used to be one big test_plot.mojo.
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


def test_render_svg_continuous_color_legend_matches_hand_derived_gradient() raises:
    # x=[0,10], y=[0,10], color=[0.0,10.0] (continuous, no size) --
    # canvas 400x300, default theme, show_gridlines=False. "10.0"/"0.0"
    # (26.0px/19.0px at the default 12pt font, confirmed by probe)
    # both stay well under the 130px default legend width, so
    # legend_reserve stays at that default, unchanged -- plot_x1=
    # 400-20-130=250, legend anchor (x=270, y=20), bar 14 wide, 100
    # tall (x:[270,284], y:[20,120]).
    #
    # A real DrawTarget.fill_rect_gradient bar now (canvas_mojo
    # >=0.3.0), not the many-thin-strip approximation an earlier
    # version of this test covered -- built from ColorScale's own
    # three stops (ColorScale.from_theme: color_scale_low/mid/high at
    # 0.0/0.5/1.0, see that method's own docstring for why a middle
    # stop exists at all -- Theme.color_scale_mid's own docstring has
    # the real, rendering-caught readability bug it fixes), each one's
    # own gradient offset flipped (1.0 - stop.offset, see _draw_
    # continuous_color_legend's own docstring for why: the bar's top
    # has to be the *high* value, but ColorScale's own offset 1.0
    # already means high) -- so the emitted gradient axis (270, 20) ->
    # (270, 120) carries stop offset 1.0 = color_scale_low (#3c6ec8,
    # Color(60,110,200)), stop offset 0.5 = color_scale_mid (#ebebeb,
    # Color(235,235,235)) unchanged by the flip (0.5 maps to itself),
    # and stop offset 0.0 = color_scale_high (#dc5a28, Color(220,90,
    # 40)), in that order (ColorScale's own stops list is built low-
    # then-mid-then-high, and this loop doesn't reorder them, just
    # flips each one's own offset in place). Confirmed against a real
    # render_svg() run before trusting it here, not just derived from
    # the three Theme color fields by hand.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var color: List[Float64] = [0.0, 10.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=x, y=y, color=color).theme(Theme(show_gridlines=False))
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true(
        '<linearGradient id="grad1" gradientUnits="userSpaceOnUse" x1="270.000" y1="20.000"'
        ' x2="270.000" y2="120.000"><stop offset="1.000" stop-color="#3c6ec8" stop-opacity="1.000"/>'
        '<stop offset="0.500" stop-color="#ebebeb" stop-opacity="1.000"/>'
        '<stop offset="0.000" stop-color="#dc5a28" stop-opacity="1.000"/></linearGradient>' in s,
        "the gradient definition: low color at the bottom (offset 1.0), mid at the middle (offset"
        " 0.5), high color at the top (offset 0.0)",
    )
    assert_true(
        '<rect x="270" y="20" width="14" height="100" fill="url(#grad1)"/>' in s,
        "the gradient bar itself, filled by reference to that gradient",
    )
    assert_true(
        '<text x="288" y="24" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">10.0</text>' in s,
        "domain max label, at the bar's own top",
    )
    assert_true(
        '<text x="288" y="124" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">0.0</text>' in s,
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
        '<text x="304" y="39" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">8.0</text>' in s,
        "max circle's own label",
    )
    assert_true(
        '<text x="298" y="71" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">5.0</text>' in s,
        "midpoint circle's own label",
    )
    assert_true(
        '<text x="292" y="91" font-size="12.000" font-family="sans-serif" fill="#282828" text-anchor="start">2.0</text>' in s,
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
