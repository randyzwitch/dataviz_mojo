"""`barplot()` and `countplot()`: bars of an estimate with its interval,
and bars of a count (#350)."""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from dataviz.barplot import barplot, countplot
from dataviz.plot import render_svg
from dataviz.stats import ErrorBar, Estimator


def _groups() -> List[String]:
    var g: List[String] = ["x", "y", "x", "y", "x", "y"]
    return g^


def _values() -> List[Float64]:
    var v: List[Float64] = [1.0, 10.0, 2.0, 20.0, 3.0, 30.0]
    return v^


def test_barplot_bars_are_the_group_means_with_whiskers() raises:
    var p = barplot(_groups(), _values(), errorbar=ErrorBar.se())
    assert_equal(len(p._categorical.x), 2)
    assert_equal(p._categorical.x[0], "x")
    assert_equal(p._categorical.x[1], "y")
    assert_equal(p._continuous.y[0], 2.0)
    assert_equal(p._continuous.y[1], 20.0)
    # se of [1,2,3] is 1/sqrt(3); of [10,20,30] is 10/sqrt(3).
    assert_almost_equal(p._y_err.lower[0], 0.5773502691896258, atol=1e-12)
    assert_almost_equal(p._y_err.upper[1], 5.773502691896258, atol=1e-12)


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


def test_barplot_with_no_errorbar_has_no_whiskers() raises:
    var p = barplot(_groups(), _values(), errorbar=ErrorBar.none())
    assert_equal(len(p._y_err.lower), 0)
    assert_equal(len(p._y_err.symmetric), 0)


def test_barplot_dtype_overload_matches_the_float64_path() raises:
    var vi: List[Int64] = [1, 10, 2, 20, 3, 30]
    assert_equal(
        render_svg(barplot(_groups(), vi)).to_string(),
        render_svg(barplot(_groups(), _values())).to_string(),
    )


def test_countplot_counts_in_first_seen_order() raises:
    var c: List[String] = ["chat", "email", "chat", "chat", "phone", "email"]
    var p = countplot(c)
    assert_equal(p._categorical.x[0], "chat")
    assert_equal(p._categorical.x[1], "email")
    assert_equal(p._categorical.x[2], "phone")
    assert_equal(p._continuous.y[0], 3.0)
    assert_equal(p._continuous.y[1], 2.0)
    assert_equal(p._continuous.y[2], 1.0)
    assert_equal(len(p._y_err.lower), 0)
    assert_true(">Count<" in render_svg(p).to_string())


def test_barplot_raises_on_mismatched_or_empty_input() raises:
    var g: List[String] = ["a"]
    var two: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = barplot(g, two)
    var none = List[String]()
    with assert_raises():
        _ = countplot(none)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
