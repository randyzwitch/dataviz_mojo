"""Tests for `Plot.mark_box(horizontal=True)`/`box(..., horizontal=True)`
(#121): `_render_horizontal_box`'s box/whisker rectangles and outlier
placement, the quickplot `box()` function matching the fluent `Plot.
mark_box(horizontal=True)` builder exactly (both the concrete and
`DType`-generic overload), and the same length-mismatch raise
`_render_box`'s own validation gives.
"""

from std.testing import assert_equal, assert_raises, assert_true, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from dataviz import box


def test_render_svg_horizontal_box_matches_hand_derived_rects_and_outlier() raises:
    # Same data as test_box.mojo's own hand-derived test: "A" =
    # [2,4,4,4,5,5,7,9,20] (q1=4, median=5, q3=7, low=2, high=9, one
    # outlier at 20), "B" = [10,12,14,15,18] (q1=12, median=14, q3=15,
    # low=10, high=18, no outliers). Canvas 400x300, show_gridlines=
    # False -- the horizontal mirror of that test's own [60,380]x
    # [20,250]y frame, both axes swapped: domain [1.1, 20.9] now runs
    # left-to-right, 2 categories run top-to-bottom (band centers
    # 78/193, bandwidth 92). Every position independently re-derived
    # via python3 and cross-checked against the actual rendered SVG.
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [
        [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0, 20.0],
        [10.0, 12.0, 14.0, 15.0, 18.0],
    ]
    var plot = Plot().mark_box(horizontal=True).encode_boxplot(cats, values).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<rect x="107" y="32" width="48" height="92" fill="#1e64b4"/>' in s, "A's box (q1 to q3)")
    assert_true('<line x1="123" y1="32" x2="123" y2="124"' in s, "A's median line (value 5), vertical across the box")
    assert_true('<rect x="236" y="147" width="48" height="92" fill="#1e64b4"/>' in s, "B's box (q1 to q3)")
    assert_true('<circle cx="365" cy="78" r="4" fill="#1e64b4"/>' in s, "A's single outlier, at value 20")


def test_box_horizontal_matches_plot_mark_box_horizontal() raises:
    # The quickplot box(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[2.0, 4.0, 7.0, 9.0], [10.0, 12.0, 15.0, 18.0]]
    var int_values: List[List[Int]] = [[2, 4, 7, 9], [10, 12, 15, 18]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = box(cats, values, theme=t, horizontal=True)
    var from_builder = Plot().mark_box(horizontal=True).encode_boxplot(cats, values).theme(t)
    var from_dtype = box(cats, int_values, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_box_raises_on_mismatched_length() raises:
    var cats: List[String] = ["A", "B"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var plot = box(cats, values, horizontal=True)
        _ = render_svg(plot)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
