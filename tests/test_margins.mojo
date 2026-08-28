"""Tests for the dynamic left-margin computation (wide y-axis tick labels
growing plot_x0 on both the continuous and Mark.BAR render paths).

The axis-line-position checks use `_assert_near_color()`, not
`_assert_color()` -- `render()`'s supersample-then-downsample
(`_RASTER_SUPERSAMPLE`, plot.mojo) has no single output pixel that
lands fully opaque for a 1px-wide stroke, so an exact color match at
the line's own nominal column isn't guaranteed the way a filled mark's
solid interior pixel still is (see `_assert_near_color`'s own
docstring, tests/_test_helpers.mojo). What's still checked exactly:
*which* column the line's ink concentrates around (the margin
actually moved), not the precise color at it.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
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

from _test_helpers import _count_color, _assert_color, _assert_near_color


def test_render_left_margin_grows_to_fit_wide_y_axis_labels() raises:
    # y=[1000000,2000000] gives nice ticks [1000000,1500000,2000000]
    # (_data_extent pads to domain [950000,2050000]; Heckbert's
    # nice-step algorithm picks step=500000 for that span -- same
    # hand-verified math test_scale.mojo's tests lock in, not
    # re-derived here). Those three labels' rendered width at the
    # default 12pt font, against this environment's real "Sans" font
    # metrics (unhinted, so glyph widths depend on the installed font
    # file), maxes out at 51.8px (the "2000000" label).
    # dynamic_left_margin = Int(51.8) + theme.tick_length(5) +
    # theme.label_gap(4) + theme.margin_buffer(8) = 68, wider than
    # Theme's default 60px margin, so plot_x0 becomes 68, not 60 -- checked
    # directly against where the y-axis line itself actually is (drawn
    # at exactly plot_x0), not an indirect proxy for it.
    # Built via Plot/Canvas/render() directly, not scatter() -- these
    # margin/axis-line pixel positions are exact by construction (see
    # this function's comment above); this test predates quickplot
    # returning a plain, un-rendered `Plot` (dataviz_mojo.plot.
    # _finished's docstring), render() being the exact same path
    # scatter()'s own output would go through now too.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_point().encode(x=x, y=y).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_near_color(c, 68, 135, t.axis_color, 70, "y-axis line moved to the dynamic margin")

    # The wide label's ink extends left of a plain fixed 60px margin:
    # real, non-background pixels sit at x=57, part of the
    # "2000000" label's glyphs (x=56 itself is a gap between glyphs).
    # A plain "x=60 is
    # background" check would be wrong here, since covering that space
    # with real label ink is the entire point of this feature, not an
    # absence to assert on.
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's ink reaches left of the plain fixed margin",
    )


def test_render_left_margin_unchanged_for_short_y_axis_labels() raises:
    # Confirms the dynamic computation is purely additive: short
    # labels ("2","4","6","8","10", from the same data every other
    # point-mark test in this file uses) must leave plot_x0 at
    # exactly Theme's default 60, byte-identical to every other
    # hand-derived test above -- the same margin every one of those
    # depends on for its hand-derived pixel math to hold.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]
    var t = Theme(show_gridlines=False)
    var _hoisted2 = Plot().mark_point().encode(x=x, y=y).theme(t).size(400, 300)
    var c = render(_hoisted2)

    _assert_near_color(c, 60, 135, t.axis_color, 70, "y-axis line still at Theme's default margin")


def test_render_bar_left_margin_also_grows_to_fit_wide_y_axis_labels() raises:
    # Same dynamic-left-margin mechanism as the continuous-path tests
    # above, wired into _render_bar independently (see that
    # function's comment) -- a separate function, not shared code.
    # y=[1000000,2000000] through _zero_baseline_y_extent (BAR's
    # always-include-zero y-domain, not _data_extent's) gives nice
    # ticks [0,500000,1000000,1500000,2000000], which lands on the
    # identical dynamic_left_margin=68 the continuous-path test above
    # got (the widest
    # label's width happens to match closely enough that both round to
    # the same margin), so the same pixel checks apply: the y-axis
    # line at x=68, and real label ink reaching left of a plain fixed
    # 60px margin (x=57, coinciding with the continuous test's x=57
    # too).
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = Plot().mark_bar().encode_categorical(x=x, y=y).theme(t).size(400, 300)
    var c = render(_hoisted3)

    _assert_near_color(c, 68, 135, t.axis_color, 70, "bar chart y-axis line moved to the dynamic margin")
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's ink reaches left of the plain fixed margin",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
