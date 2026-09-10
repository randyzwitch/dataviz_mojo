"""`dataviz.stats`: the estimation shared by marks that draw an estimate
with its uncertainty (#350, #352). Every value here is worked out by
hand and pinned, away from any rendering.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)

from dataviz.stats import _ols_fit, _t_quantile


def test_ols_fit_matches_hand_derived_line_and_residual_error() raises:
    # x=[1..5], y=[1,3,2,5,4]: slope 0.8, intercept 0.6 (the values
    # annotate_best_fit has always drawn). Residuals -0.4/0.8/-1/1.2/-0.6
    # give SS_res 3.6 over n-2 = 3 -> s = sqrt(1.2). Sxx = 55 - 5*9 = 10.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var f = _ols_fit(x, y)
    assert_equal(f.n, 5)
    assert_almost_equal(f.slope, 0.8, atol=1e-12)
    assert_almost_equal(f.intercept, 0.6, atol=1e-12)
    assert_almost_equal(f.mean_x, 3.0, atol=1e-12)
    assert_almost_equal(f.sxx, 10.0, atol=1e-12)
    assert_almost_equal(f.residual_se, 1.0954451150103321, atol=1e-12)


def test_band_half_width_is_narrowest_at_mean_x_and_flares() raises:
    # Same fit; t(0.95, df=3) = 3.182.
    # at x = mean_x = 3: 3.182 * sqrt(1.2) * sqrt(1/5)       = 1.5588552
    # at x = 1:          3.182 * sqrt(1.2) * sqrt(1/5 + 4/10) = 2.7000164
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [1.0, 3.0, 2.0, 5.0, 4.0]
    var f = _ols_fit(x, y)
    var at_mean = f.band_half_width(3.0, 0.95)
    var at_end = f.band_half_width(1.0, 0.95)
    assert_almost_equal(at_mean, 1.5588552, atol=1e-6)
    assert_almost_equal(at_end, 2.7000164, atol=1e-6)
    assert_almost_equal(f.band_half_width(5.0, 0.95), at_end, atol=1e-12)


def test_perfect_fit_has_zero_residual_error_and_zero_width_band() raises:
    # y = 2x exactly: slope 2, intercept 0, every residual 0, so the
    # band collapses onto the line -- the degenerate case #352 names.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [2.0, 4.0, 6.0, 8.0, 10.0]
    var f = _ols_fit(x, y)
    assert_equal(f.slope, 2.0)
    assert_equal(f.intercept, 0.0)
    assert_equal(f.residual_se, 0.0)
    assert_equal(f.band_half_width(1.0, 0.95), 0.0)


def test_t_quantile_table_and_normal_tail() raises:
    assert_equal(_t_quantile(0.95, 1), 12.706)
    assert_equal(_t_quantile(0.95, 3), 3.182)
    assert_equal(_t_quantile(0.90, 10), 1.812)
    assert_equal(_t_quantile(0.99, 30), 2.750)
    assert_equal(_t_quantile(0.95, 31), 1.960)
    assert_equal(_t_quantile(0.95, 1000), 1.960)


def test_stats_raise_where_the_estimate_is_undefined() raises:
    var x2: List[Float64] = [1.0, 2.0]
    var y2: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = _ols_fit(x2, y2).band_half_width(1.5, 0.95)
    var xv: List[Float64] = [3.0, 3.0, 3.0]
    var yv: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        _ = _ols_fit(xv, yv)
    with assert_raises():
        _ = _t_quantile(0.8, 5)
    with assert_raises():
        _ = _t_quantile(0.95, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
