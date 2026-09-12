"""`lineplot()`: the per-x estimate of repeated measurements as a line
with its interval as a band (#350)."""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from dataviz.lineplot import lineplot
from dataviz.plot import render_svg
from dataviz.core.stats import ErrorBar, Estimator


def _x() -> List[Float64]:
    var v: List[Float64] = [1.0, 2.0, 1.0, 2.0, 3.0, 3.0]
    return v^


def _y() -> List[Float64]:
    var v: List[Float64] = [10.0, 20.0, 12.0, 22.0, 30.0, 34.0]
    return v^


def test_lineplot_line_is_the_per_x_mean_with_a_band_of_the_interval() raises:
    var p = lineplot(_x(), _y(), errorbar=ErrorBar.se())
    assert_equal(len(p._continuous.x), 3)
    assert_equal(p._continuous.x[0], 1.0)
    assert_equal(p._continuous.y[0], 11.0)
    assert_equal(p._continuous.y[1], 21.0)
    assert_equal(p._continuous.y[2], 32.0)
    # One band: its edges are the estimate minus and plus one se, which
    # for each pair here is half the gap -- so the band runs exactly
    # through the raw readings.
    assert_equal(len(p._annotations.band_x), 1)
    var lower = p._annotations.band_y_lower[0].copy()
    var upper = p._annotations.band_y_upper[0].copy()
    assert_almost_equal(lower[0], 10.0, atol=1e-12)
    assert_almost_equal(upper[0], 12.0, atol=1e-12)
    assert_almost_equal(lower[2], 30.0, atol=1e-12)
    assert_almost_equal(upper[2], 34.0, atol=1e-12)


def test_lineplot_with_no_errorbar_has_no_band() raises:
    var p = lineplot(_x(), _y(), errorbar=ErrorBar.none())
    assert_equal(len(p._annotations.band_x), 0)


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
