"""Statistical estimation shared by the marks that draw an estimate with
its uncertainty -- the start of the family #350 and #352 describe.

Everything here is a pure function over lists, tested against
hand-computed values away from any rendering, so a chart only has to
show that the numbers reached the glyph.
"""

from std.math import sqrt

from dataviz.box import _percentile


struct _OlsFit(Copyable, Movable):
    """An ordinary-least-squares line through `(x, y)` pairs, with the
    pieces a confidence band around it needs."""

    var n: Int
    var slope: Float64
    var intercept: Float64
    var mean_x: Float64
    var mean_y: Float64
    var sxx: Float64
    """`sum((x - mean_x)^2)`, the spread of the predictors."""
    var residual_se: Float64
    """`sqrt(SS_res / (n - 2))`; `0.0` when `n < 3`, where it is undefined."""

    def __init__(
        out self,
        n: Int,
        slope: Float64,
        intercept: Float64,
        mean_x: Float64,
        mean_y: Float64,
        sxx: Float64,
        residual_se: Float64,
    ):
        self.n = n
        self.slope = slope
        self.intercept = intercept
        self.mean_x = mean_x
        self.mean_y = mean_y
        self.sxx = sxx
        self.residual_se = residual_se

    def predict(self, x: Float64) -> Float64:
        """The fitted line's value at `x`."""
        return self.slope * x + self.intercept

    def band_half_width(self, x: Float64, level: Float64) raises -> Float64:
        """Half the width of the confidence band for the fitted *mean*
        at `x`, at two-sided confidence `level`:

            t(level, n - 2) * s * sqrt(1/n + (x - mean_x)^2 / Sxx)

        Narrowest at `mean_x` and flaring toward the ends -- the
        hourglass that is the visual point of the band.

        Raises:
            Error: `n < 3` (no residual degrees of freedom) or a
                `level` `_t_quantile` does not carry.
        """
        if self.n < 3:
            raise Error(
                "a confidence band needs at least 3 points (got "
                + String(self.n)
                + "): with two, the line passes through both and the"
                " residual error has no degrees of freedom"
            )
        var d = x - self.mean_x
        return (
            _t_quantile(level, self.n - 2)
            * self.residual_se
            * sqrt(1.0 / Float64(self.n) + d * d / self.sxx)
        )


def _ols_fit(x: List[Float64], y: List[Float64]) raises -> _OlsFit:
    """Fit `y = slope * x + intercept` by ordinary least squares.

    The slope and intercept use exactly the closed forms
    `annotate_best_fit()` has always used -- `(n*sum_xy - sum_x*sum_y)
    / (n*sum_xx - sum_x^2)` and `mean_y - slope*mean_x` -- so moving the
    arithmetic here changed no fitted line.

    Raises:
        Error: Fewer than 2 points, or every `x` identical (the
            denominator is zero and no non-vertical line fits).
    """
    var n_points = len(x)
    if n_points < 2:
        raise Error(
            "needs at least 2 points to fit a line through (got "
            + String(n_points)
            + ")"
        )
    var n = Float64(n_points)
    var sum_x = 0.0
    var sum_y = 0.0
    var sum_xy = 0.0
    var sum_xx = 0.0
    for i in range(n_points):
        sum_x += x[i]
        sum_y += y[i]
        sum_xy += x[i] * y[i]
        sum_xx += x[i] * x[i]
    var denom = n * sum_xx - sum_x * sum_x
    if denom == 0.0:
        raise Error(
            "every x value is identical -- there is no honest non-vertical"
            " line to fit through a vertical scatter"
        )
    var slope = (n * sum_xy - sum_x * sum_y) / denom
    var mean_x = sum_x / n
    var mean_y = sum_y / n
    var intercept = mean_y - slope * mean_x
    var sxx = sum_xx - n * mean_x * mean_x
    var ss_res = 0.0
    for i in range(n_points):
        var r = y[i] - (slope * x[i] + intercept)
        ss_res += r * r
    var residual_se = sqrt(ss_res / (n - 2.0)) if n_points > 2 else 0.0
    return _OlsFit(n_points, slope, intercept, mean_x, mean_y, sxx, residual_se)


def _t_quantile(level: Float64, df: Int) raises -> Float64:
    """The two-sided Student-t critical value: the `t` with
    `P(|T_df| <= t) == level`.

    Carried as tables at the three levels a confidence band is drawn at
    in practice -- 0.90, 0.95 and 0.99 -- for `df` 1 through 30, then
    the normal quantile beyond, where the two are within a percent. A
    table is exact where it applies and cannot silently be a little
    wrong the way a series approximation can; an unsupported `level`
    raises rather than rounding to the nearest one it has.

    Raises:
        Error: `df < 1`, or a `level` other than 0.90/0.95/0.99.
    """
    if df < 1:
        raise Error("t quantile needs at least 1 degree of freedom")
    var t90: List[Float64] = [
        6.314,
        2.920,
        2.353,
        2.132,
        2.015,
        1.943,
        1.895,
        1.860,
        1.833,
        1.812,
        1.796,
        1.782,
        1.771,
        1.761,
        1.753,
        1.746,
        1.740,
        1.734,
        1.729,
        1.725,
        1.721,
        1.717,
        1.714,
        1.711,
        1.708,
        1.706,
        1.703,
        1.701,
        1.699,
        1.697,
    ]
    var t95: List[Float64] = [
        12.706,
        4.303,
        3.182,
        2.776,
        2.571,
        2.447,
        2.365,
        2.306,
        2.262,
        2.228,
        2.201,
        2.179,
        2.160,
        2.145,
        2.131,
        2.120,
        2.110,
        2.101,
        2.093,
        2.086,
        2.080,
        2.074,
        2.069,
        2.064,
        2.060,
        2.056,
        2.052,
        2.048,
        2.045,
        2.042,
    ]
    var t99: List[Float64] = [
        63.657,
        9.925,
        5.841,
        4.604,
        4.032,
        3.707,
        3.499,
        3.355,
        3.250,
        3.169,
        3.106,
        3.055,
        3.012,
        2.977,
        2.947,
        2.921,
        2.898,
        2.878,
        2.861,
        2.845,
        2.831,
        2.819,
        2.807,
        2.797,
        2.787,
        2.779,
        2.771,
        2.763,
        2.756,
        2.750,
    ]
    var i = min(df, 30) - 1
    if level == 0.95:
        return t95[i] if df <= 30 else 1.960
    if level == 0.90:
        return t90[i] if df <= 30 else 1.645
    if level == 0.99:
        return t99[i] if df <= 30 else 2.576
    raise Error(
        "confidence level must be 0.90, 0.95 or 0.99 (got "
        + String(level)
        + ")"
    )


# ---------------------------------------------------------------------
# Estimation with uncertainty (#350): one estimator, one interval spec,
# one aggregation, used by every mark that draws an estimate.
# ---------------------------------------------------------------------


struct _Lcg(Movable):
    """A small linear congruential generator for the bootstrap.

    Its own generator rather than a dependency, and seeded rather than
    clocked: a chart is a document, and a confidence interval that came
    out differently on every render would make the chart unreproducible
    and every test of it unstable. Knuth's MMIX constants; the low bits
    of an LCG are poor, so every draw comes from the high 32.
    """

    var _state: UInt64

    def __init__(out self, seed: UInt64):
        self._state = seed

    def next_bits(mut self) -> UInt64:
        """The next 32-bit draw."""
        self._state = self._state * 6364136223846793005 + 1442695040888963407
        return self._state >> 32


struct Estimator(Copyable, ImplicitlyCopyable, Movable):
    """What a group of observations is reduced to: seaborn's
    `estimator=` vocabulary. Pass one to `barplot()`.

    `COUNT` ignores the values and reports how many there were, so its
    interval is always empty -- a count has no sampling error to
    estimate from the sample itself.
    """

    var _value: Int
    comptime MEAN = Self(0)
    comptime MEDIAN = Self(1)
    comptime COUNT = Self(2)
    comptime SUM = Self(3)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    def label(self) -> String:
        """A title-cased name for an axis label, so a chart of an
        estimate says which estimate it is."""
        if self._value == 0:
            return "Mean"
        if self._value == 1:
            return "Median"
        if self._value == 2:
            return "Count"
        return "Sum"


struct ErrorBar(Copyable, ImplicitlyCopyable, Movable):
    """How the uncertainty around an estimate is sized: seaborn's
    `errorbar=` vocabulary.

    - `ErrorBar.none()` -- no interval.
    - `ErrorBar.sd(k)` -- `k` sample standard deviations, the spread of
      the observations themselves.
    - `ErrorBar.se(k)` -- `k` standard errors of the mean, the spread of
      the estimate.
    - `ErrorBar.pi(level)` -- a percentile interval of the observations,
      e.g. 0.95 for the 2.5th to 97.5th percentile.
    - `ErrorBar.ci(level)` -- a bootstrap confidence interval of the
      estimate: resample the group with replacement, re-estimate, take
      the percentile interval of those estimates. Needs a seed, which
      `barplot()` carries with a fixed default.

    `sd` and `se` are symmetric about the estimate and closed-form;
    `pi` and `ci` are asymmetric and follow the data's shape.
    """

    var _kind: Int
    var scale: Float64
    """`k` for `sd`/`se`, the confidence level in `(0, 1)` for `pi`/`ci`."""

    def __init__(out self, kind: Int, scale: Float64):
        self._kind = kind
        self.scale = scale

    @staticmethod
    def none() -> Self:
        return Self(0, 0.0)

    @staticmethod
    def sd(k: Float64 = 1.0) -> Self:
        return Self(1, k)

    @staticmethod
    def se(k: Float64 = 1.0) -> Self:
        return Self(2, k)

    @staticmethod
    def pi(level: Float64 = 0.95) -> Self:
        return Self(3, level)

    @staticmethod
    def ci(level: Float64 = 0.95) -> Self:
        return Self(4, level)

    def is_none(self) -> Bool:
        return self._kind == 0

    def is_bootstrap(self) -> Bool:
        return self._kind == 4

    def label(self) -> String:
        """How the interval was made, for a caption."""
        if self._kind == 0:
            return "none"
        if self._kind == 1:
            return String(self.scale) + " sd"
        if self._kind == 2:
            return String(self.scale) + " se"
        if self._kind == 3:
            return String(Int(round(self.scale * 100.0))) + "% pi"
        return String(Int(round(self.scale * 100.0))) + "% ci"


comptime _BOOTSTRAP_RESAMPLES = 1000
"""Resamples per bootstrap interval. seaborn's default; enough that the
percentile ends are stable to the second figure."""


def _sort_ascending(mut values: List[Float64]):
    """In-place insertion sort. The lists here are a group's
    observations or a bootstrap's resampled estimates -- small enough
    that a dependency-free O(n^2) is the simpler honest choice."""
    for i in range(1, len(values)):
        var k = i
        while k > 0 and values[k] < values[k - 1]:
            var t = values[k]
            values[k] = values[k - 1]
            values[k - 1] = t
            k -= 1


def _estimate(values: List[Float64], estimator: Estimator) raises -> Float64:
    """Reduce `values` by `estimator`. Raises on an empty list."""
    var n = len(values)
    if n == 0:
        raise Error("an estimate needs at least one observation")
    if estimator == Estimator.COUNT:
        return Float64(n)
    var total = 0.0
    for v in values:
        total += v
    if estimator == Estimator.SUM:
        return total
    if estimator == Estimator.MEAN:
        return total / Float64(n)
    var sorted = values.copy()
    _sort_ascending(sorted)
    return _percentile(sorted, 0.5)


def _sample_sd(values: List[Float64]) -> Float64:
    """The sample standard deviation (n - 1 in the denominator); `0.0`
    below two observations, where it is undefined."""
    var n = len(values)
    if n < 2:
        return 0.0
    var mean = 0.0
    for v in values:
        mean += v
    mean /= Float64(n)
    var ss = 0.0
    for v in values:
        ss += (v - mean) * (v - mean)
    return sqrt(ss / Float64(n - 1))


def _interval(
    values: List[Float64],
    estimator: Estimator,
    errorbar: ErrorBar,
    seed: UInt64,
) raises -> Tuple[Float64, Float64]:
    """The `(low, high)` interval around `_estimate(values, estimator)`
    that `errorbar` asks for. `COUNT` and `ErrorBar.none()` both give
    the estimate twice -- an empty interval, drawn as no whisker.
    """
    var est = _estimate(values, estimator)
    if errorbar.is_none() or estimator == Estimator.COUNT:
        return (est, est)
    var n = len(values)
    if errorbar._kind == 1:
        var half = errorbar.scale * _sample_sd(values)
        return (est - half, est + half)
    if errorbar._kind == 2:
        var half = errorbar.scale * _sample_sd(values) / sqrt(Float64(n))
        return (est - half, est + half)
    var level = errorbar.scale
    if level <= 0.0 or level >= 1.0:
        raise Error(
            "an interval's confidence level must be in (0, 1) (got "
            + String(level)
            + ")"
        )
    var lo_p = (1.0 - level) / 2.0
    var hi_p = (1.0 + level) / 2.0
    if errorbar._kind == 3:
        var sorted = values.copy()
        _sort_ascending(sorted)
        return (_percentile(sorted, lo_p), _percentile(sorted, hi_p))
    # Bootstrap: resample with replacement, re-estimate, take the
    # percentile interval of the resampled estimates.
    var rng = _Lcg(seed)
    var estimates = List[Float64](capacity=_BOOTSTRAP_RESAMPLES)
    var draw = List[Float64](capacity=n)
    for _ in range(_BOOTSTRAP_RESAMPLES):
        draw.clear()
        for _ in range(n):
            draw.append(values[Int(rng.next_bits() % UInt64(n))])
        estimates.append(_estimate(draw, estimator))
    _sort_ascending(estimates)
    return (_percentile(estimates, lo_p), _percentile(estimates, hi_p))


struct _Aggregate(Movable):
    """`_aggregate()`'s result: one row per group, in first-seen order."""

    var categories: List[String]
    var estimates: List[Float64]
    var lows: List[Float64]
    var highs: List[Float64]

    def __init__(
        out self,
        var categories: List[String],
        var estimates: List[Float64],
        var lows: List[Float64],
        var highs: List[Float64],
    ):
        self.categories = categories^
        self.estimates = estimates^
        self.lows = lows^
        self.highs = highs^


def _aggregate(
    groups: List[String],
    values: List[Float64],
    estimator: Estimator,
    errorbar: ErrorBar,
    seed: UInt64,
) raises -> _Aggregate:
    """Reduce `values` to one estimate and interval per distinct entry of
    `groups`, groups ordered as first seen -- the categorical axis a
    `barplot()` draws. Each group is bootstrapped from the same seed,
    so a group's interval does not depend on which other groups are
    present.

    Raises:
        Error: `groups` and `values` differ in length, or are empty.
    """
    if len(groups) != len(values):
        raise Error(
            "groups and values must have the same length (got "
            + String(len(groups))
            + " and "
            + String(len(values))
            + ")"
        )
    if len(groups) == 0:
        raise Error("nothing to estimate: groups is empty")
    var categories = List[String]()
    var members = List[List[Float64]]()
    for i in range(len(groups)):
        var found = -1
        for j in range(len(categories)):
            if categories[j] == groups[i]:
                found = j
        if found < 0:
            categories.append(groups[i])
            members.append(List[Float64]())
            found = len(categories) - 1
        members[found].append(values[i])
    var estimates = List[Float64](capacity=len(categories))
    var lows = List[Float64](capacity=len(categories))
    var highs = List[Float64](capacity=len(categories))
    for j in range(len(categories)):
        estimates.append(_estimate(members[j], estimator))
        var iv = _interval(members[j], estimator, errorbar, seed)
        lows.append(iv[0])
        highs.append(iv[1])
    return _Aggregate(categories^, estimates^, lows^, highs^)


struct _NumericAggregate(Movable):
    """`_aggregate_by_x()`'s result: one row per distinct x, ascending."""

    var xs: List[Float64]
    var estimates: List[Float64]
    var lows: List[Float64]
    var highs: List[Float64]

    def __init__(
        out self,
        var xs: List[Float64],
        var estimates: List[Float64],
        var lows: List[Float64],
        var highs: List[Float64],
    ):
        self.xs = xs^
        self.estimates = estimates^
        self.lows = lows^
        self.highs = highs^


def _aggregate_by_x(
    x: List[Float64],
    y: List[Float64],
    estimator: Estimator,
    errorbar: ErrorBar,
    seed: UInt64,
) raises -> _NumericAggregate:
    """`_aggregate()` for a continuous key: every observation whose `x`
    is exactly equal is one group, and the groups come back sorted by
    `x` so a line can be drawn through the estimates in order -- the
    per-x estimation seaborn's `lineplot()` performs on repeated
    measurements.

    Exact equality is deliberate. Two readings at 1.0 and 1.0000001 are
    two x positions, and deciding they are the same would be binning,
    which is a different chart (`histogram()`).

    Raises:
        Error: `x` and `y` differ in length, or are empty.
    """
    if len(x) != len(y):
        raise Error(
            "x and y must have the same length (got "
            + String(len(x))
            + " and "
            + String(len(y))
            + ")"
        )
    if len(x) == 0:
        raise Error("nothing to estimate: x is empty")
    var keys = List[Float64]()
    var members = List[List[Float64]]()
    for i in range(len(x)):
        var found = -1
        for j in range(len(keys)):
            if keys[j] == x[i]:
                found = j
        if found < 0:
            keys.append(x[i])
            members.append(List[Float64]())
            found = len(keys) - 1
        members[found].append(y[i])
    # Sort the groups by key; the member lists ride along.
    var order = List[Int](capacity=len(keys))
    for j in range(len(keys)):
        order.append(j)
    for i in range(1, len(order)):
        var k = i
        while k > 0 and keys[order[k]] < keys[order[k - 1]]:
            var t = order[k]
            order[k] = order[k - 1]
            order[k - 1] = t
            k -= 1
    var xs = List[Float64](capacity=len(keys))
    var estimates = List[Float64](capacity=len(keys))
    var lows = List[Float64](capacity=len(keys))
    var highs = List[Float64](capacity=len(keys))
    for j in order:
        xs.append(keys[j])
        estimates.append(_estimate(members[j], estimator))
        var iv = _interval(members[j], estimator, errorbar, seed)
        lows.append(iv[0])
        highs.append(iv[1])
    return _NumericAggregate(xs^, estimates^, lows^, highs^)
