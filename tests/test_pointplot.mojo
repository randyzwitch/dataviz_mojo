"""`Mark.POINTPLOT` and `pointplot()`: an estimate per category as a
point with its whisker, joined across categories (#350)."""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from _test_helpers import _count_tag
from dataviz.plot import Plot, render_svg
from dataviz.pointplot import pointplot
from dataviz.core.stats import ErrorBar, Estimator


def _groups() -> List[String]:
    var g: List[String] = ["x", "y", "x", "y"]
    return g^


def _values() -> List[Float64]:
    var v: List[Float64] = [1.0, 10.0, 3.0, 20.0]
    return v^


def test_pointplot_points_are_the_group_means_with_se_whiskers() raises:
    # x: [1, 3] -> mean 2, sd sqrt(2), se 1.0. y: [10, 20] -> mean 15,
    # sd sqrt(50), se 5.0.
    var p = pointplot(_groups(), _values(), errorbar=ErrorBar.se())
    assert_equal(len(p._categorical.x), 2)
    assert_equal(p._continuous.y[0], 2.0)
    assert_equal(p._continuous.y[1], 15.0)
    assert_almost_equal(p._y_err.lower[0], 1.0, atol=1e-12)
    assert_almost_equal(p._y_err.upper[1], 5.0, atol=1e-12)


def test_pointplot_renders_points_a_joining_line_and_whiskers() raises:
    var s = render_svg(
        pointplot(
            _groups(), _values(), errorbar=ErrorBar.se(), width=400, height=300
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
            _groups(),
            _values(),
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
        render_svg(pointplot(_groups(), vi)).to_string(),
        render_svg(pointplot(_groups(), _values())).to_string(),
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
    assert_equal(p._mark.name(), "Mark.POINTPLOT")
    assert_equal(_count_tag(render_svg(p).to_string(), "circle"), 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
