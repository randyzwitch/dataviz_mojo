"""Tests for `Plot.mark_stacked_bar(percent=True)`: each category's
segments rescaled to sum to exactly 100, fixed [0, 100] y-axis, the
non-negative-value requirement, and the all-zero-category edge case.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import stacked_bar


def test_render_svg_percent_stacked_bar_matches_hand_derived_rectangles() raises:
    # Same axis frame as test_stacked_bar.mojo's tests (canvas 400x300,
    # default margins, show_gridlines=False, legend reserved ->
    # x_scale range [60,250], band_start(A)=70, band_start(B)=165,
    # bandwidth=76) -- percent=True fixes the y-domain to exactly
    # [0, 100] regardless of the data, so frame.y_scale maps 0 -> py1
    # (250, the drawn axis line) and 100 -> py0 (20, the top margin),
    # a plain 230px span with no 5%-padding the way a real-valued
    # domain gets from _zero_baseline_y_extent.
    #
    # A: North=30, South=10 -> total 40 -> North 75%, South 25%.
    # B: North=20, South=30 -> total 50 -> North 40%, South 60%.
    # Every position independently re-derived via python3 (percent = value / category_total * 100 for the segment span, then 0..100 -> 250..20 linearly) and cross-checked against the rendered SVG.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 20.0], [10.0, 30.0]]
    var plot = Plot().mark_stacked_bar(percent=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    # A/North: bottom segment, 0..75 -> py 250..78 (230*0.75=172.5), height 171.
    assert_true('<rect x="70" y="78" width="76" height="171" fill="#1f77b4"/>' in s, "A/North (75%)")
    # A/South: stacked on top, 75..100 -> py 78..20, height 58.
    assert_true('<rect x="70" y="20" width="76" height="58" fill="#ff7f0e"/>' in s, "A/South (25%)")
    # B/North: bottom segment, 0..40 -> py 250..158 (230*0.40=92), height 91.
    assert_true('<rect x="165" y="158" width="76" height="91" fill="#1f77b4"/>' in s, "B/North (40%)")
    # B/South: stacked on top, 40..100 -> py 158..20, height 138.
    assert_true('<rect x="165" y="20" width="76" height="138" fill="#ff7f0e"/>' in s, "B/South (60%)")


def test_render_svg_percent_stacked_bar_all_zero_category_is_an_empty_column() raises:
    # Category B's values are all zero -- category_total is 0.0, so
    # scale_factor falls to the 0.0 branch (not a divide-by-zero) and
    # every segment in that column draws at zero height, sitting right
    # on the axis line. Category A (North=30, South=20, unaffected)
    # still renders normally.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 0.0], [20.0, 0.0]]
    var plot = Plot().mark_stacked_bar(percent=True).encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="112" width="76" height="137" fill="#1f77b4"/>' in s, "A/North (60%), unaffected")
    assert_true('<rect x="70" y="20" width="76" height="92" fill="#ff7f0e"/>' in s, "A/South (40%), unaffected")
    assert_true('<rect x="165" y="250" width="76" height="0" fill="#1f77b4"/>' in s, "B/North, zero-height")
    assert_true('<rect x="165" y="250" width="76" height="0" fill="#ff7f0e"/>' in s, "B/South, zero-height")


def test_render_raises_on_percent_stacked_bar_with_a_negative_value() raises:
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[-5.0], [20.0]]
    with assert_raises():
        var plot = Plot().mark_stacked_bar(percent=True).encode_grouped_bar(cats, names, values)
        _ = render_svg(plot)


def test_render_svg_non_percent_stacked_bar_is_unaffected_by_percent_flag() raises:
    # percent=False (the default) must keep behaving exactly as
    # test_stacked_bar.mojo already confirms -- raw values, no
    # rescaling. Regression check against sharing the drawing loop.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="187" width="76" height="62" fill="#1f77b4"/>' in s, "A/North, raw")
    assert_true('<rect x="70" y="156" width="76" height="31" fill="#ff7f0e"/>' in s, "A/South, raw")


def test_stacked_bar_quickplot_accepts_percent_kwarg() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[30.0, 20.0], [10.0, 30.0]]
    var c = stacked_bar(cats, names, values, width=400, height=300, percent=True)
    var svg = render_svg(c)
    var s = svg.to_string()
    assert_true('<rect x="70" y="78" width="76" height="171" fill="#1f77b4"/>' in s, "quickplot percent=True")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
