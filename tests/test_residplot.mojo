"""`residplot()`: residuals of the OLS fit against fitted values (#352)."""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from dataviz.plot import render_svg
from dataviz.residplot import residplot


def test_residplot_points_are_hand_derived_fitted_values_and_residuals() raises:
    # x=[1..5], y=[1,3,2,5,4]: the fit is y = 0.8x + 0.6, so fitted values
    # are 1.4/2.2/3.0/3.8/4.6 and residuals -0.4/0.8/-1.0/1.2/-0.6 -- the
    # exact distances from the line annotate_best_fit() draws.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var p = residplot(x, y)
    var fitted: List[Float64] = [1.4, 2.2, 3.0, 3.8, 4.6]
    var resid: List[Float64] = [-0.4, 0.8, -1.0, 1.2, -0.6]
    assert_equal(len(p.x_data), 5)
    var total = 0.0
    for i in range(5):
        assert_almost_equal(p.x_data[i], fitted[i], atol=1e-12)
        assert_almost_equal(p.y_data[i], resid[i], atol=1e-12)
        total += p.y_data[i]
    # OLS residuals always sum to zero.
    assert_almost_equal(total, 0.0, atol=1e-12)
    assert_equal(p._annotations.line_values[0], 0.0)


def test_residplot_perfect_fit_has_all_zero_residuals() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [2.0, 4.0, 6.0, 8.0]
    var p = residplot(x, y)
    for v in p.y_data:
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
