"""`Mark.BOXENPLOT` and `boxenplot()`: the letter-value plot (#356)."""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from _test_helpers import _count_tag
from dataviz.boxen import _letter_value_depth, _letter_values, boxenplot
from dataviz.plot import render_svg


def _box_rects(svg: String) -> Int:
    """`<rect>` elements that are not the SVG backend's white background."""
    var white = 0
    var at = svg.find('fill="#ffffff"')
    while at >= 0:
        white += 1
        at = svg.find('fill="#ffffff"', at + 1)
    return _count_tag(svg, "rect") - white


def test_letter_value_depth_follows_tukeys_rule() raises:
    # floor(log2(n)) - 3, never below one: 8 -> 1, 16 -> 1, 32 -> 2,
    # 64 -> 3, 1000 -> 6 (2^9 = 512 <= 1000 < 1024).
    assert_equal(_letter_value_depth(8), 1)
    assert_equal(_letter_value_depth(15), 1)
    assert_equal(_letter_value_depth(16), 1)
    assert_equal(_letter_value_depth(32), 2)
    assert_equal(_letter_value_depth(64), 3)
    assert_equal(_letter_value_depth(1000), 6)


def test_letter_values_match_hand_derived_quantiles() raises:
    # 1..32: two levels. numpy-linear quantiles: q(.25) at rank 7.75 ->
    # 8.75, q(.75) at 23.25 -> 24.25; q(.125) at 3.875 -> 4.875,
    # q(.875) at 27.125 -> 28.125; median 16.5. Beyond the deepest pair
    # lie 1-4 and 29-32: eight outliers.
    var v = List[Float64]()
    for i in range(1, 33):
        v.append(Float64(i))
    var lv = _letter_values(v)
    assert_equal(lv.median, 16.5)
    assert_equal(len(lv.lower), 2)
    assert_almost_equal(lv.lower[0], 8.75, atol=1e-12)
    assert_almost_equal(lv.upper[0], 24.25, atol=1e-12)
    assert_almost_equal(lv.lower[1], 4.875, atol=1e-12)
    assert_almost_equal(lv.upper[1], 28.125, atol=1e-12)
    assert_equal(len(lv.outliers), 8)
    assert_equal(lv.outliers[0], 1.0)
    assert_equal(lv.outliers[7], 32.0)


def test_letter_values_nest_outward() raises:
    var v = List[Float64]()
    for i in range(200):
        v.append(Float64(i * i) / 40.0)
    var lv = _letter_values(v)
    assert_equal(len(lv.lower), 4)
    for k in range(1, 4):
        assert_true(lv.lower[k] <= lv.lower[k - 1], "deeper is lower")
        assert_true(lv.upper[k] >= lv.upper[k - 1], "deeper is higher")


def test_boxenplot_draws_one_rect_per_level_and_a_median_per_category() raises:
    var cats: List[String] = ["a", "b"]
    var a = List[Float64]()
    var b = List[Float64]()
    for i in range(1, 33):
        a.append(Float64(i))
        b.append(Float64(i) * 2.0)
    var vals: List[List[Float64]] = [a^, b^]
    var p = boxenplot(cats, vals, width=400, height=300)
    assert_equal(len(p._boxen.lower[0]), 2)
    var s = render_svg(p).to_string()
    # Two levels per category, so four boxes (the background rect
    # excluded); eight outliers per category, so sixteen points.
    assert_equal(_box_rects(s), 4)
    assert_equal(_count_tag(s, "circle"), 16)


def test_boxenplot_horizontal_renders_the_same_counts() raises:
    var cats: List[String] = ["a"]
    var a = List[Float64]()
    for i in range(1, 33):
        a.append(Float64(i))
    var vals: List[List[Float64]] = [a^]
    var s = render_svg(
        boxenplot(cats, vals, horizontal=True, width=400, height=300)
    ).to_string()
    assert_equal(_box_rects(s), 2)
    assert_equal(_count_tag(s, "circle"), 8)


def test_boxenplot_dtype_overload_matches_the_float64_path() raises:
    var cats: List[String] = ["a"]
    var vi = List[Int64]()
    var vf = List[Float64]()
    for i in range(1, 33):
        vi.append(Int64(i))
        vf.append(Float64(i))
    var li: List[List[Int64]] = [vi^]
    var lf: List[List[Float64]] = [vf^]
    assert_equal(
        render_svg(boxenplot(cats, li)).to_string(),
        render_svg(boxenplot(cats, lf)).to_string(),
    )


def test_boxenplot_raises_on_bad_input() raises:
    var cats: List[String] = ["a", "b"]
    var one: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = boxenplot(cats, one)
    var c1: List[String] = ["a"]
    var empty: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        _ = boxenplot(c1, empty)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
