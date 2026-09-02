"""Tests for `Plot.mark_beeswarm(horizontal=True)`/`beeswarm(...,
horizontal=True)` (#121): `_render_horizontal_beeswarm`'s jittered
point positions, the quickplot `beeswarm()` function matching the
fluent `Plot.mark_beeswarm(horizontal=True)` builder exactly (both the
concrete and `DType`-generic overload), and the same raise paths
`_render_beeswarm`'s own validation gives.
"""

from std.testing import assert_equal, assert_raises, assert_true, TestSuite

from dataviz.plot import Plot, render_svg
from dataviz.theme import Theme
from dataviz import beeswarm


def test_render_svg_horizontal_beeswarm_matches_hand_derived_offsets() raises:
    # Same data as test_beeswarm.mojo's own hand-derived test: 1
    # category ("A"), values [10, 11, 50] -- 10 and 11 land close
    # enough in pixel space to collide, 50 stays alone. Canvas
    # 400x300, show_gridlines=False -- the horizontal mirror of that
    # test's own [60,380]x[20,250]y frame, both axes swapped: x-domain
    # = _data_extent([10,11,50]) = [8,52] now runs left-to-right
    # (pixel x's 75 (v=10), 82 (v=11), 365 (v=50)), 1 category spans
    # the whole y-band (center=135). Unlike the vertical case (where
    # the y-axis is flipped, so 11 sorts before 10 in pixel space), the
    # x-axis here runs the same direction as the values, so 10 (pixel
    # 75) sorts before 11 (pixel 82): 10 gets offset 0 (first in its
    # row), 11 gets offset +8 (second). Every position independently
    # re-derived via python3 and cross-checked against the actual
    # rendered SVG.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var plot = Plot().mark_beeswarm(horizontal=True).encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var s = render_svg(plot).to_string()

    assert_true('<circle cx="75" cy="135" r="4" fill="#1e64b4"/>' in s, "value 10 -- offset 0 (first in its row)")
    assert_true('<circle cx="82" cy="143" r="4" fill="#1e64b4"/>' in s, "value 11 -- offset +8 (second in its row)")
    assert_true('<circle cx="365" cy="135" r="4" fill="#1e64b4"/>' in s, "value 50 -- offset 0 (alone in its row)")


def test_beeswarm_horizontal_matches_plot_mark_beeswarm_horizontal() raises:
    # The quickplot beeswarm(horizontal=True) convenience function must
    # render identically to the fluent builder it wraps, and the
    # DType-generic overload must forward horizontal too (see
    # lollipop's own equivalent test -- a forwarding bug there was
    # caught this exact way).
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var int_vals: List[List[Int]] = [[10, 11, 50]]
    var t = Theme(show_gridlines=False)
    var from_quickplot = beeswarm(cats, vals, theme=t, horizontal=True)
    var from_builder = Plot().mark_beeswarm(horizontal=True).encode_distribution(categories=cats, values=vals).theme(t)
    var from_dtype = beeswarm(cats, int_vals, theme=t, horizontal=True)
    assert_equal(render_svg(from_quickplot).to_string(), render_svg(from_builder).to_string())
    assert_equal(render_svg(from_dtype).to_string(), render_svg(from_builder).to_string())


def test_render_horizontal_beeswarm_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var plot = beeswarm(cats, vals, width=200, height=150, horizontal=True)
        _ = render_svg(plot)


def test_render_horizontal_beeswarm_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var plot = beeswarm(cats, vals, width=200, height=150, horizontal=True)
    var s = render_svg(plot).to_string()
    assert_true("<rect" in s, "still fills the background")
    assert_true("<line" not in s, "no axis lines drawn for zero categories")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
