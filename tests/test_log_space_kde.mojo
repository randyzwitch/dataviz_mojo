"""KDE under a log x axis is estimated in log space (#718).

Estimating in linear x and drawing on a log axis stretches a fixed-width
kernel unevenly across decades, so the curve's shape is an artifact of
the axis rather than a property of the data. The fix estimates the
density of `log10(x)`.

The discriminating test is the one #718 names. A log-normal sample is
symmetric in log x, so its log-space density must be symmetric about the
median on a log axis. The linear estimate drawn on that same axis is
not, which the control asserts, so the first test is proving something.
"""

from std.math import cos, exp, log, log10, pi, sqrt
from std.testing import TestSuite, assert_raises, assert_true

from dataviz.distributions.kde import _kde_curve, _kde_curve_for_axis, kdeplot
from dataviz.plot import Plot
from dataviz import render


def _lognormal(n: Int) -> List[Float64]:
    """exp(N(0, 1)) by Box-Muller from a fixed LCG, so the test is
    deterministic."""
    var out = List[Float64]()
    var seed = 20260918
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) % 2147483648
        var u1 = (Float64(seed) + 1.0) / 2147483649.0
        seed = (seed * 1103515245 + 12345) % 2147483648
        var u2 = Float64(seed) / 2147483648.0
        var z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2)
        out.append(exp(z))
    return out^


def _asymmetry(
    xs: List[Float64], ys: List[Float64], center: Float64
) -> Float64:
    """How lopsided the curve is about `center` in log10 space: the worst
    relative gap between the density at `center - d` and `center + d`,
    over offsets out to one decade."""
    var worst = 0.0
    var peak = 0.0
    for v in ys:
        if v > peak:
            peak = v
    for k in range(1, 9):
        var d = Float64(k) * 0.1
        var left = _at(xs, ys, 10.0 ** (center - d))
        var right = _at(xs, ys, 10.0 ** (center + d))
        var gap = abs(left - right) / peak
        if gap > worst:
            worst = gap
    return worst


def _at(xs: List[Float64], ys: List[Float64], x: Float64) -> Float64:
    """The curve's value at `x`, linearly between samples."""
    for i in range(1, len(xs)):
        if xs[i] >= x:
            var t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
    return ys[len(ys) - 1]


def test_a_lognormal_sample_is_symmetric_on_a_log_axis() raises:
    var v = _lognormal(2000)
    var log_axis = Plot().mark_kde().scale_x_log()
    var curve = _kde_curve_for_axis(
        log_axis.mark.distribution, log_axis.settings, v
    )
    var lopsided = _asymmetry(curve[0], curve[1], 0.0)
    assert_true(
        lopsided < 0.1,
        (
            "the log-space estimate of a log-normal sample is lopsided by "
            + String(lopsided)
            + " of its peak about the median"
        ),
    )


def test_the_linear_estimate_is_what_this_fixes() raises:
    # The same sample, estimated in linear x and read off at the same
    # log-spaced offsets. It crowds to the left and is badly lopsided.
    var v = _lognormal(2000)
    var linear = _kde_curve(v, 0.0)
    var lopsided = _asymmetry(linear[0], linear[1], 0.0)
    assert_true(
        lopsided > 0.3,
        (
            "the linear estimate is already symmetric on a log axis ("
            + String(lopsided)
            + "), so there is nothing for log-space estimation to fix"
        ),
    )


def test_a_linear_axis_is_unchanged() raises:
    var v = _lognormal(200)
    var direct = _kde_curve(v, 0.0)
    var linear = Plot().mark_kde()
    var routed = _kde_curve_for_axis(
        linear.mark.distribution, linear.settings, v
    )
    for i in range(len(direct[0])):
        assert_true(
            direct[0][i] == routed[0][i] and direct[1][i] == routed[1][i],
            "the linear path moved",
        )


def test_kde_renders_on_a_log_axis() raises:
    _ = render(kdeplot(_lognormal(300)).scale_x_log())


def test_a_non_positive_value_raises_under_log() raises:
    var v: List[Float64] = [1.0, 0.0, 3.0]
    with assert_raises(contains="must be > 0"):
        _ = render(kdeplot(v).scale_x_log())


def test_symlog_raises() raises:
    with assert_raises(contains="takes scale_x_log() only"):
        _ = render(kdeplot(_lognormal(50)).scale_x_symlog())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
