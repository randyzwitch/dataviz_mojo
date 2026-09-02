"""Tests for `Plot.mark_stacked_bar(horizontal=True)`/`stacked_bar(...,
horizontal=True)` (#121): `_render_horizontal_stacked_bar`'s segment
rectangles and legend placement, `percent=True` combined with
`horizontal=True` (a fixed `[0, 100]` x-axis), the quickplot
`stacked_bar()` function matching the fluent `Plot.mark_stacked_bar(
horizontal=True)` builder exactly (both the concrete and `DType`-
generic overload), and the empty-data case.
"""

from std.testing import assert_equal, assert_raises, assert_true, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from dataviz import stacked_bar


def test_render_svg_horizontal_stacked_bar_matches_hand_derived_rectangles_and_legend() raises:
    # Same values[0]/values[1] = North=[10,20]/South=[5,15] as the
    # sibling horizontal grouped-bar test, but stacked: category A's
    # total is 15 (10+5), category B's is 35 (20+15) -- domain over
    # [pos_total, neg_total] per category = [15, 0, 35, 0] ->
    # _zero_baseline_y_extent -> [0, 36.75] (zero exact, so only the
    # high end padded 5%). Canvas 400x300, show_gridlines=False,
    # show_legend default (True), same [60,250]x[20,250] frame the
    # sibling grouped-bar test derives.
    #
    # Each category's row is the *full* band height (92, not split
    # into sub-rows) -- band_y(A)=32 (round(31.5)), band_y(B)=147
    # (round(146.5)), matching the sibling test's own band-start math.
    # North's segment always starts at the baseline (pulled 1px to 61,
    # non-negative-only domain -- see _pull_off_axis_line's docstring);
    # South's segment picks up exactly where North's left off (the
    # running-total property `_render_stacked_bar`'s own docstring
    # explains -- no extra rounding trick needed for that shared
    # edge). Every position independently re-derived via python3 and
    # cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_stacked_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="61" y="32" width="51" height="92" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="112" y="32" width="26" height="92" fill="#ff7f0e"/>' in s, "A/South, picks up where North left off")
    assert_true('<rect x="61" y="147" width="102" height="92" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="163" y="147" width="78" height="92" fill="#ff7f0e"/>' in s, "B/South")

    assert_true('<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch")
    assert_true('<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch")


def test_render_svg_horizontal_stacked_bar_percent_fixes_x_axis_to_0_100() raises:
    # values[0] (North) = [10, 30], values[1] (South) = [20, 10] --
    # category A: North=10/South=20, total 30, scale_factor=100/30;
    # North -> 33.33% -> [0,33.33], South -> 66.67% -> [33.33,100].
    # Category B: North=30/South=10, total 40, scale_factor=100/40=2.5;
    # North -> 75% -> [0,75], South -> 25% -> [75,100]. The x-axis
    # itself is fixed to exactly [0,100] regardless of the raw data
    # (Plot.mark_stacked_bar()'s own docstring) -- confirmed here by
    # the "100" tick landing at the frame's own right edge (250), not
    # some data-dependent padded value. Every position independently
    # re-derived via python3 and cross-checked against the actual
    # rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 30.0], [20.0, 10.0]]
    var plot = Plot().mark_stacked_bar(percent=True, horizontal=True).encode_grouped_bar(
        cats, names, values
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<text x="250" y="271"' in s and ">100</text>" in s, "the x-axis is fixed to end at exactly 100")
    assert_true('<rect x="61" y="32" width="62" height="92" fill="#1f77b4"/>' in s, "A/North, 33.3% of A's total")
    assert_true('<rect x="123" y="32" width="127" height="92" fill="#ff7f0e"/>' in s, "A/South, the remaining 66.7%")
    assert_true('<rect x="61" y="147" width="142" height="92" fill="#1f77b4"/>' in s, "B/North, 75% of B's total")
    assert_true('<rect x="203" y="147" width="47" height="92" fill="#ff7f0e"/>' in s, "B/South, the remaining 25%")


def test_render_horizontal_stacked_bar_percent_raises_on_a_negative_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    with assert_raises():
        var plot = Plot().mark_stacked_bar(percent=True, horizontal=True).encode_grouped_bar(cats, names, values)
        _ = render_svg(plot)


def test_stacked_bar_horizontal_matches_plot_mark_stacked_bar_horizontal() raises:
    # The quickplot stacked_bar(horizontal=True) convenience function
    # must render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var int_values: List[List[Int]] = [[10, 20], [5, 15]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = stacked_bar(cats, names, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_stacked_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(t)
    var from_dtype = stacked_bar(cats, names, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_stacked_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var plot = Plot().mark_stacked_bar(horizontal=True).encode_grouped_bar(cats, names, values).size(200, 150)
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
