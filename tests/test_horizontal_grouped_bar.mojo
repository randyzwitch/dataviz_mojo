"""Tests for `Plot.mark_grouped_bar(horizontal=True)`/`grouped_bar(...,
horizontal=True)` (#121): `_render_horizontal_grouped_bar`'s
sub-bar rectangles and legend placement, `Theme.show_data_labels`
support with mixed-sign values, the quickplot `grouped_bar()` function
matching the fluent `Plot.mark_grouped_bar(horizontal=True)` builder
exactly (both the concrete and `DType`-generic overload), and the
empty-data case.
"""

from std.testing import assert_equal, assert_true, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from dataviz import grouped_bar


def test_render_svg_horizontal_grouped_bar_matches_hand_derived_rectangles_and_legend() raises:
    # 2 categories ("A"/"B"), 2 series -- values[0] (North) = [10, 20]
    # (North's value for A, then B), values[1] (South) = [5, 15]
    # (South's value for A, then B) -- the same data/mapping test_
    # grouped_bar.mojo's own hand-derived-rectangles test uses, so its
    # domain math ([0, 21], zero exact so unpadded) carries over
    # unchanged. Canvas 400x300, show_gridlines=False, show_legend at
    # its default (True) -- legend reserves 130px, so the frame's own
    # plot area is x:[60,250] y:[20,250] (the horizontal mirror of that
    # test's own [60,250]x-range/[20,250]y-range, both axes swapped).
    #
    # Every value here is non-negative, so the baseline (0) lands
    # exactly on the frame's left axis line (px0=60) -- every sub-bar's
    # left edge is pulled 1px to 61 (see _pull_off_axis_line's
    # docstring, plot.mojo). Category A's band starts at y=31.5,
    # bandwidth 92, sub_height 46 (2 series) -> North's row y:[32,78),
    # South's row y:[78,124). Category B's band starts at y=146.5 ->
    # North's row y:[147,193), South's row y:[193,239). Every position
    # independently re-derived via python3 and cross-checked against
    # the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="61" y="32" width="89" height="46" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="61" y="78" width="44" height="46" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="61" y="147" width="180" height="46" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="61" y="193" width="135" height="46" fill="#ff7f0e"/>' in s, "B/South")

    # Legend: same starting corner _render_horizontal_grouped_bar's own
    # docstring explains (frame.x_scale.range_max + margin_right,
    # frame.py0) -- x=230+20=250? actually resolves to 270 (see the
    # vertical Mark.GROUPED_BAR test's own identical 270,20 -- the
    # same legend width/margins on this same 400x300 canvas produce
    # the same corner regardless of orientation).
    assert_true('<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch")
    assert_true('<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch")


def test_render_svg_horizontal_grouped_bar_supports_show_data_labels_with_mixed_signs() raises:
    # values[0] (North) = [10, -5], values[1] (South) = [20, 15] --
    # mixed signs this time, so the baseline no longer lands on the
    # frame's own left axis line (unlike the sibling test above) and
    # no pull-off applies. Every position independently re-derived via
    # python3 and cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, -5.0], [20.0, 15.0]]
    var plot = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="103" y="32" width="69" height="46" fill="#1f77b4"/>' in s, "A/North (10)")
    assert_true(
        '<text x="176" y="59" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="start">10</text>' in s,
        "A/North's label, right of its own bar, left-aligned",
    )
    assert_true('<rect x="69" y="147" width="34" height="46" fill="#1f77b4"/>' in s, "B/North (-5)")
    assert_true(
        '<text x="65" y="174" font-size="12.000" font-family="sans-serif" fill="#282828"'
        ' text-anchor="end">-5</text>' in s,
        "B/North's label, left of its own bar (negative), right-aligned",
    )


def test_grouped_bar_horizontal_matches_plot_mark_grouped_bar_horizontal() raises:
    # The quickplot grouped_bar(horizontal=True) convenience function
    # must render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see lollipop's
    # own equivalent test -- a forwarding bug there was caught this
    # exact way).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var int_values: List[List[Int]] = [[10, 20], [5, 15]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = grouped_bar(cats, names, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).theme(t)
    var from_dtype = grouped_bar(cats, names, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_grouped_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var plot = Plot().mark_grouped_bar(horizontal=True).encode_grouped_bar(cats, names, values).size(200, 150)
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
