"""Tests for the dynamic left-margin computation (wide y-axis tick labels
growing plot_x0 on both the continuous and Mark.BAR render paths).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.buffer import Canvas
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

from _test_helpers import BG, _count_color, _assert_color


def test_render_left_margin_grows_to_fit_wide_y_axis_labels() raises:
    # y=[1000000,2000000] gives nice ticks [1000000,1500000,2000000]
    # (_data_extent pads to domain [950000,2050000]; Heckbert's nice-step algorithm picks step=500000 for that span -- same
    # hand-verified math test_scale.mojo's tests already lock in,
    # not re-derived here). Those three labels' rendered width at the
    # default 12pt font -- confirmed by probe against this
    # environment's real "Sans" font metrics, the same "locked in,
    # confirmed by probe" convention canvas_mojo/tests/test_text.mojo's glyph-extent tests already use, re-probed after canvas_mojo
    # v0.1.0's FreeType-to-native-TTF-parser swap (deliberately
    # unhinted, so it measures every glyph slightly differently than
    # the old FreeType-hinted values this test used to lock in) -- max
    # out at 51.8px (the "2000000" label, down from the pre-repin
    # 55.0px). dynamic_left_margin = Int(51.8) + _TICK_LENGTH(5) +
    # _LABEL_GAP(4) + _MARGIN_BUFFER(8) = 68, wider than Theme's
    # default 60px margin, so plot_x0 becomes 68, not 60 -- checked
    # directly against where the y-axis line itself actually is (drawn
    # at exactly plot_x0), not an indirect proxy for it.
    # Built via Plot/Canvas/render() directly, not scatter() -- these
    # margin/axis-line pixel positions are exact by construction (see
    # this function's comment above), and scatter()'s output
    # is supersampled-then-downsampled internally now (see dataviz_
    # mojo.plot._rendered's docstring), whose real font metrics at
    # 3x scale don't divide back down to the identical pixel column
    # this hand-derived math assumes. render() itself stays
    # unsupersampled -- see its docstring -- so this exact check
    # still holds there.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var c = Canvas(400, 300, BG)
    render(c, Plot().mark_point().encode(x=x, y=y).theme(t))

    _assert_color(c, 68, 135, t.axis_color, "y-axis line moved to the dynamic margin")

    # The wide label's ink extends left of the *old* fixed 60px
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
        "wide tick label's ink reaches left of the old fixed margin",
    )


def test_render_left_margin_unchanged_for_short_y_axis_labels() raises:
    # Confirms the dynamic computation is purely additive: short
    # labels ("2","4","6","8","10", from the same data every other
    # point-mark test in this file uses) must leave plot_x0 at
    # exactly Theme's default 60, byte-identical to every
    # pre-existing hand-derived test above -- not a coincidence, the
    # actual reason none of those needed updating when this feature
    # was added.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    var y: List[Float64] = [2.3, 4.1, 3.6, 5.8, 5.1, 7.4, 6.9, 8.2, 9.0, 8.6]
    var t = Theme(show_gridlines=False)
    var c = Canvas(400, 300, BG)
    render(c, Plot().mark_point().encode(x=x, y=y).theme(t))

    _assert_color(c, 60, 135, t.axis_color, "y-axis line still at Theme's default margin")


def test_render_bar_left_margin_also_grows_to_fit_wide_y_axis_labels() raises:
    # Same dynamic-left-margin mechanism as the continuous-path tests
    # above, wired into _render_bar independently (see that function's
    # own comment) -- confirmed here rather than just assumed to carry
    # over, since it's a separate function, not shared code.
    # y=[1000000,2000000] through _zero_baseline_y_extent (BAR's always-include-zero y-domain, not _data_extent's) gives nice
    # ticks [0,500000,1000000,1500000,2000000] -- confirmed by probe
    # (re-probed after canvas_mojo v0.1.0's FreeType-to-native-TTF-
    # parser swap, see test_render_left_margin_grows_to_fit_wide_y_
    # axis_labels's comment) this lands on the identical dynamic_
    # left_margin=68 the continuous-path test above got (the widest
    # label's width happens to match closely enough that both round to
    # the same margin), so the same pixel checks apply: the y-axis
    # line at x=68, and real label ink reaching left of the old fixed
    # 60px margin (x=57 -- confirmed separately by probe, not assumed
    # identical, though it now happens to coincide with the continuous
    # test's x=57 too, unlike before the repin).
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1000000.0, 2000000.0]
    var t = Theme(show_gridlines=False)
    var c = Canvas(400, 300, BG)
    render(c, Plot().mark_bar().encode_categorical(x=x, y=y).theme(t))

    _assert_color(c, 68, 135, t.axis_color, "bar chart y-axis line moved to the dynamic margin")
    var left_of_old_margin = c.get_pixel(57, 135)
    assert_true(
        left_of_old_margin.r != 255 or left_of_old_margin.g != 255 or left_of_old_margin.b != 255,
        "wide tick label's ink reaches left of the old fixed margin",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
