"""Tests for Mark.BAR: rectangles, negative values, dynamic left margin,
color-by-sign.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import (
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
from dataviz.theme import Theme
from dataviz import bar

from _test_helpers import BG, _count_color, _assert_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
