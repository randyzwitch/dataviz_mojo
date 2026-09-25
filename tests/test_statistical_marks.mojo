"""The seaborn-style statistical marks: lineplot(), barplot() and pointplot() aggregate
observations per x or per category with an estimator and an error bar, residplot()
fits and subtracts a line, and boxenplot() draws letter values.

One module rather than 5: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from dataviz.core.tooltips import Tooltips
from dataviz.aggregation.barplot import barplot
from dataviz.aggregation.lineplot import lineplot
from dataviz.aggregation.pointplot import pointplot
from dataviz.aggregation.residplot import residplot
from dataviz.core.stats import ErrorBar, Estimator
from dataviz.distributions.boxen import (
    _letter_value_depth,
    _letter_values,
    boxenplot,
)
from dataviz.core.theme import Theme
from dataviz.plot import Plot
from dataviz import render_svg
from _test_helpers import _count_tag


# ==== from test_lineplot.mojo ====
# `lineplot()`: the per-x estimate of repeated measurements as a line
# with its interval as a band (#350).


def _x() -> List[Float64]:
    var v: List[Float64] = [1.0, 2.0, 1.0, 2.0, 3.0, 3.0]
    return v^


def _y() -> List[Float64]:
    var v: List[Float64] = [10.0, 20.0, 12.0, 22.0, 30.0, 34.0]
    return v^


def test_lineplot_line_is_the_per_x_mean_with_a_band_of_the_interval() raises:
    var p = lineplot(_x(), _y(), errorbar=ErrorBar.se())
    assert_equal(len(p.mark.continuous.x), 3)
    assert_equal(p.mark.continuous.x[0], 1.0)
    assert_equal(p.mark.continuous.y[0], 11.0)
    assert_equal(p.mark.continuous.y[1], 21.0)
    assert_equal(p.mark.continuous.y[2], 32.0)
    # One band: its edges are the estimate minus and plus one se, which
    # for each pair here is half the gap -- so the band runs exactly
    # through the raw readings.
    assert_equal(len(p.annotations.band_x), 1)
    var lower = p.annotations.band_y_lower[0].copy()
    var upper = p.annotations.band_y_upper[0].copy()
    assert_almost_equal(lower[0], 10.0, atol=1e-12)
    assert_almost_equal(upper[0], 12.0, atol=1e-12)
    assert_almost_equal(lower[2], 30.0, atol=1e-12)
    assert_almost_equal(upper[2], 34.0, atol=1e-12)


def test_lineplot_with_no_errorbar_has_no_band() raises:
    var p = lineplot(_x(), _y(), errorbar=ErrorBar.none())
    assert_equal(len(p.annotations.band_x), 0)


def test_lineplot_names_the_estimator_on_the_y_axis_by_default() raises:
    var s = render_svg(lineplot(_x(), _y())).to_string()
    assert_true(">Mean<" in s)
    var m = render_svg(
        lineplot(_x(), _y(), estimator=Estimator.MEDIAN)
    ).to_string()
    assert_true(">Median<" in m)


def test_lineplot_dtype_overload_matches_the_float64_path() raises:
    var xi: List[Int64] = [1, 2, 1, 2, 3, 3]
    var yi: List[Int64] = [10, 20, 12, 22, 30, 34]
    assert_equal(
        render_svg(lineplot(xi, yi)).to_string(),
        render_svg(lineplot(_x(), _y())).to_string(),
    )


def test_lineplot_raises_on_mismatched_or_empty_input() raises:
    var one: List[Float64] = [1.0]
    with assert_raises():
        _ = lineplot(one, _y())
    var none = List[Float64]()
    with assert_raises():
        _ = lineplot(none, none)


# ==== from test_residplot.mojo ====
# `residplot()`: residuals of the OLS fit against fitted values (#352).


def test_residplot_points_are_hand_derived_fitted_values_and_residuals() raises:
    # x=[1..5], y=[1,3,2,5,4]: the fit is y = 0.8x + 0.6, so fitted values
    # are 1.4/2.2/3.0/3.8/4.6 and residuals -0.4/0.8/-1.0/1.2/-0.6 -- the
    # exact distances from the line annotate_best_fit() draws.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var p = residplot(x, y)
    var fitted: List[Float64] = [1.4, 2.2, 3.0, 3.8, 4.6]
    var resid: List[Float64] = [-0.4, 0.8, -1.0, 1.2, -0.6]
    assert_equal(len(p.mark.continuous.x), 5)
    var total = 0.0
    for i in range(5):
        assert_almost_equal(p.mark.continuous.x[i], fitted[i], atol=1e-12)
        assert_almost_equal(p.mark.continuous.y[i], resid[i], atol=1e-12)
        total += p.mark.continuous.y[i]
    # OLS residuals always sum to zero.
    assert_almost_equal(total, 0.0, atol=1e-12)
    assert_equal(p.annotations.line_values[0], 0.0)


def test_residplot_perfect_fit_has_all_zero_residuals() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [2.0, 4.0, 6.0, 8.0]
    var p = residplot(x, y)
    for v in p.mark.continuous.y:
        assert_equal(v, 0.0)


def test_residplot_renders_with_the_zero_reference_line() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var s = render_svg(residplot(x, y, width=400, height=300)).to_string()
    assert_true("<circle" in s, "the residuals are drawn as points")
    assert_true(
        "Fitted value" in s and "Residual" in s,
        "the default axis titles name what the axes are",
    )


def test_residplot_dtype_overload_matches_the_float64_path() raises:
    var xi: List[Int64] = [1, 2, 3, 4, 5]
    var yi: List[Int64] = [1, 3, 2, 5, 4]
    var xf: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var yf: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    assert_equal(
        render_svg(residplot(xi, yi)).to_string(),
        render_svg(residplot(xf, yf)).to_string(),
    )


def test_residplot_raises_where_no_line_fits() raises:
    var one: List[Float64] = [1.0]
    with assert_raises():
        _ = residplot(one, one)
    var xv: List[Float64] = [2.0, 2.0, 2.0]
    var yv: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        _ = residplot(xv, yv)
    var x3: List[Float64] = [1.0, 2.0, 3.0]
    var y2: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = residplot(x3, y2)


# ==== from test_barplot.mojo ====
# `barplot()`: bars of an estimate with its interval (#350).


def _groups() -> List[String]:
    var g: List[String] = ["x", "y", "x", "y", "x", "y"]
    return g^


def _values() -> List[Float64]:
    var v: List[Float64] = [1.0, 10.0, 2.0, 20.0, 3.0, 30.0]
    return v^


def test_barplot_bars_are_the_group_means_with_whiskers() raises:
    var p = barplot(_groups(), _values(), errorbar=ErrorBar.se())
    assert_equal(len(p.mark.categorical.x), 2)
    assert_equal(p.mark.categorical.x[0], "x")
    assert_equal(p.mark.categorical.x[1], "y")
    assert_equal(p.mark.continuous.y[0], 2.0)
    assert_equal(p.mark.continuous.y[1], 20.0)
    # se of [1,2,3] is 1/sqrt(3); of [10,20,30] is 10/sqrt(3).
    assert_almost_equal(p.mark.y_err.lower[0], 0.5773502691896258, atol=1e-12)
    assert_almost_equal(p.mark.y_err.upper[1], 5.773502691896258, atol=1e-12)


def test_barplot_names_the_estimator_on_the_y_axis_by_default() raises:
    var s = render_svg(barplot(_groups(), _values())).to_string()
    assert_true(">Mean<" in s, "the y-axis title says which estimate it is")
    var m = render_svg(
        barplot(_groups(), _values(), estimator=Estimator.MEDIAN)
    ).to_string()
    assert_true(">Median<" in m)
    var named = render_svg(
        barplot(_groups(), _values(), y_title="Latency (ms)")
    ).to_string()
    assert_true(">Latency (ms)<" in named and ">Mean<" not in named)


def test_a_horizontal_barplot_names_the_estimator_on_the_value_axis() raises:
    # #709: horizontal, the value axis is x, so "Mean" is the unrotated
    # bottom title; before, it was drawn rotated on the left, labeling
    # the category axis, and the value axis had no title at all.
    var s = render_svg(
        barplot(_groups(), _values(), horizontal=True, width=300, height=200)
    ).to_string()
    var at = s.find(">Mean</text>")
    assert_true(at >= 0, "the estimator is still named")
    var before = String(s[byte=0:at])
    var element = String(before[byte = before.rfind("<text") :])
    assert_true("rotate(" not in element, "Mean is the unrotated bottom title")
    var named = render_svg(
        barplot(
            _groups(),
            _values(),
            horizontal=True,
            x_title="Latency (ms)",
            width=300,
            height=200,
        )
    ).to_string()
    assert_true(
        ">Latency (ms)<" in named and ">Mean<" not in named,
        "an explicit x_title replaces the default",
    )


def test_barplot_with_no_errorbar_has_no_whiskers() raises:
    var p = barplot(_groups(), _values(), errorbar=ErrorBar.none())
    assert_equal(len(p.mark.y_err.lower), 0)
    assert_equal(len(p.mark.y_err.symmetric), 0)


def test_barplot_dtype_overload_matches_the_float64_path() raises:
    var vi: List[Int64] = [1, 10, 2, 20, 3, 30]
    assert_equal(
        render_svg(barplot(_groups(), vi)).to_string(),
        render_svg(barplot(_groups(), _values())).to_string(),
    )


def test_barplot_raises_on_mismatched_or_empty_input() raises:
    var g: List[String] = ["a"]
    var two: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = barplot(g, two)


# ==== from test_pointplot.mojo ====
# `Mark.POINTPLOT` and `pointplot()`: an estimate per category as a
# point with its whisker, joined across categories (#350).


def _groups_pointplot() -> List[String]:
    var g: List[String] = ["x", "y", "x", "y"]
    return g^


def _values_pointplot() -> List[Float64]:
    var v: List[Float64] = [1.0, 10.0, 3.0, 20.0]
    return v^


def test_pointplot_points_are_the_group_means_with_se_whiskers() raises:
    # x: [1, 3] -> mean 2, sd sqrt(2), se 1.0. y: [10, 20] -> mean 15,
    # sd sqrt(50), se 5.0.
    var p = pointplot(
        _groups_pointplot(), _values_pointplot(), errorbar=ErrorBar.se()
    )
    assert_equal(len(p.mark.categorical.x), 2)
    assert_equal(p.mark.continuous.y[0], 2.0)
    assert_equal(p.mark.continuous.y[1], 15.0)
    assert_almost_equal(p.mark.y_err.lower[0], 1.0, atol=1e-12)
    assert_almost_equal(p.mark.y_err.upper[1], 5.0, atol=1e-12)


def test_pointplot_renders_points_a_joining_line_and_whiskers() raises:
    var s = render_svg(
        pointplot(
            _groups_pointplot(),
            _values_pointplot(),
            errorbar=ErrorBar.se(),
            width=400,
            height=300,
        )
    ).to_string()
    assert_equal(_count_tag(s, "circle"), 2)
    # One joining segment plus three whisker segments per category, all
    # in the mark color; the axis lines are in axis_color.
    var mark_lines = 0
    var at = s.find('stroke="#1e64b4"')
    while at >= 0:
        mark_lines += 1
        at = s.find('stroke="#1e64b4"', at + 1)
    assert_equal(mark_lines, 7)
    assert_true(">Mean<" in s, "the y-axis names the estimator")


def test_pointplot_axis_follows_the_data_rather_than_zero() raises:
    # Means of 2 and 15 with no whiskers: the y-domain is _data_extent
    # over [2, 15], padded 5% -> [1.35, 15.65]; a zero-baselined axis
    # would label 0. No "0" tick, and no tick above 16.
    var s = render_svg(
        pointplot(
            _groups_pointplot(),
            _values_pointplot(),
            errorbar=ErrorBar.none(),
            width=400,
            height=300,
        )
    ).to_string()
    assert_true(
        'text-anchor="end">0<' not in s and 'text-anchor="end">0.0<' not in s
    )
    assert_true('text-anchor="end">20<' not in s)


def test_pointplot_dtype_overload_matches_the_float64_path() raises:
    var vi: List[Int64] = [1, 10, 3, 20]
    assert_equal(
        render_svg(pointplot(_groups_pointplot(), vi)).to_string(),
        render_svg(
            pointplot(_groups_pointplot(), _values_pointplot())
        ).to_string(),
    )


def test_pointplot_raises_on_mismatched_input() raises:
    var g: List[String] = ["a"]
    var two: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = pointplot(g, two)


def test_mark_pointplot_builder_sets_the_mark() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 2.0]
    var p = Plot().mark_pointplot().encode_categorical(x=cats, y=vals)
    assert_equal(p.id().name(), "Mark.POINTPLOT")
    assert_equal(_count_tag(render_svg(p).to_string(), "circle"), 2)


# ==== from test_boxen.mojo ====
# `Mark.BOXENPLOT` and `boxenplot()`: the letter-value plot (#356).


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
    assert_equal(len(p.mark.boxen.lower[0]), 2)
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


# ---------------------------------------------------------------
# Tooltips on pointplot and boxenplot (#678)


def _titles_in(svg: String) -> List[String]:
    var out = List[String]()
    var at = 0
    while True:
        var open_at = svg.find("<title>", at)
        if open_at < 0:
            return out^
        var start = open_at + 7
        var close_at = svg.find("</title>", start)
        out.append(String(svg[byte=start:close_at]))
        at = close_at


def test_a_boxenplot_glyph_is_titled_by_its_median_and_widest_box() raises:
    # n=9, depth 1: Q1/median/Q3 via numpy-style linear interpolation
    # are the values at sorted index 2/4/6 -- 3, 5, 7.
    var cats: List[String] = ["a", "b"]
    var av: List[Float64] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
    var bv: List[Float64] = [10, 20, 30, 40, 50, 60, 70, 80, 90]
    var values: List[List[Float64]] = [av^, bv^]
    var titles = _titles_in(
        render_svg(boxenplot(cats, values, width=400, height=300)).to_string()
    )
    assert_equal(len(titles), 2, "one title per category's glyph")
    assert_equal(titles[0], "a: median 5, box 3-7")
    assert_equal(titles[1], "b: median 50, box 30-70")


def test_a_pointplot_point_and_whisker_are_titled_by_category_and_value() raises:
    # Two identical observations per category give sd=0, so the
    # closed-form whisker's lo/hi collapse onto the mean exactly --
    # no bootstrap or percentile formula to reproduce by hand.
    var cats: List[String] = ["a", "a", "b", "b"]
    var vals: List[Float64] = [5.0, 5.0, 10.0, 10.0]
    var titles = _titles_in(
        render_svg(
            pointplot(
                cats, vals, errorbar=ErrorBar.sd(1.0), width=400, height=300
            )
        ).to_string()
    )
    assert_equal(
        len(titles), 4, "one whisker title and one point title per category"
    )
    assert_equal(titles[0], "a: 5-5")
    assert_equal(titles[1], "b: 10-10")
    assert_equal(titles[2], "a: 5")
    assert_equal(titles[3], "b: 10")


def test_pointplot_and_boxenplot_tooltips_follow_the_theme_flag() raises:
    var cats: List[String] = ["a", "a"]
    var vals: List[Float64] = [5.0, 5.0]
    var off = render_svg(
        pointplot(cats, vals, theme=Theme(tooltips=Tooltips.OFF))
    ).to_string()
    assert_true("<title>" not in off, "Tooltips.OFF removes them")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
