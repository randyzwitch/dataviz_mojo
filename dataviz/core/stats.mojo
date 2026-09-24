"""Statistical estimation shared by the marks that draw an estimate with
its uncertainty -- the start of the family #350 and #352 describe.

Everything here is a pure function over lists, tested against
hand-computed values away from any rendering, so a chart only has to
show that the numbers reached the glyph.
"""

from std.utils.numerics import isfinite, isnan
from std.math import sqrt

from dataviz.distributions.box import _percentile


def _pearson_correlation(x: List[Float64], y: List[Float64]) raises -> Float64:
    """Pearson correlation over paired, present observations.

    Missing values are excluded pairwise. A constant column or fewer than
    two complete pairs has no correlation and raises.
    """
    if len(x) != len(y):
        raise Error("correlation columns must have the same length")
    var n = 0
    var sum_x = 0.0
    var sum_y = 0.0
    for i in range(len(x)):
        if isnan(x[i]) or isnan(y[i]):
            continue
        if not isfinite(x[i]) or not isfinite(y[i]):
            raise Error("correlation values must be finite")
        n += 1
        sum_x += x[i]
        sum_y += y[i]
    if n < 2:
        raise Error("correlation needs at least two complete rows")
    var mean_x = sum_x / Float64(n)
    var mean_y = sum_y / Float64(n)
    var sxx = 0.0
    var syy = 0.0
    var sxy = 0.0
    for i in range(len(x)):
        if isnan(x[i]) or isnan(y[i]):
            continue
        var dx = x[i] - mean_x
        var dy = y[i] - mean_y
        sxx += dx * dx
        syy += dy * dy
        sxy += dx * dy
    if sxx == 0.0 or syy == 0.0:
        raise Error("correlation is undefined for a constant column")
    var value = sxy / sqrt(sxx * syy)
    return max(-1.0, min(1.0, value))


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


def _present_pairs(
    x: List[Float64], y: List[Float64]
) raises -> Tuple[List[Float64], List[Float64]]:
    """The `(x, y)` pairs where both coordinates are there (#367).

    A fit needs both halves of a point: a row missing either one says
    nothing about the relationship between them, so it is left out
    rather than fitted through.

    Args:
        x: The x column.
        y: The y column, the same length.

    Returns:
        The surviving pairs, in order.

    Raises:
        Error: The columns differ in length.
    """
    if len(x) != len(y):
        raise Error(
            "x and y must have the same length (got "
            + String(len(x))
            + " and "
            + String(len(y))
            + ")"
        )
    var kept_x = List[Float64](capacity=len(x))
    var kept_y = List[Float64](capacity=len(y))
    for i in range(len(x)):
        if not isnan(x[i]) and not isnan(y[i]):
            kept_x.append(x[i])
            kept_y.append(y[i])
    return (kept_x^, kept_y^)


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
    var pairs = _present_pairs(x, y)
    ref px = pairs[0]
    ref py = pairs[1]
    var n_points = len(px)
    if n_points < 2:
        raise Error(
            "needs at least 2 points to fit a line through (got "
            + String(n_points)
            + " with both coordinates present)"
        )
    var n = Float64(n_points)
    var sum_x = 0.0
    var sum_y = 0.0
    var sum_xy = 0.0
    var sum_xx = 0.0
    for i in range(n_points):
        sum_x += px[i]
        sum_y += py[i]
        sum_xy += px[i] * py[i]
        sum_xx += px[i] * px[i]
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
        var r = py[i] - (slope * px[i] + intercept)
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
    """What a group of observations is reduced to. Pass one to
    `barplot()`.

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
    """How the uncertainty around an estimate is sized.

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
"""Resamples per bootstrap interval; enough that the
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


def _present(values: List[Float64]) -> List[Float64]:
    """The values that are there, dropping the missing ones (#367).

    Every statistic in this package starts here, so "the mean of what
    was measured" is the same rule everywhere: a missing observation is
    left out rather than counted as a zero or poisoning the result into
    `NaN`. The count that remains is the effective sample size, which is
    what `Estimator.COUNT` then reports.

    Args:
        values: A column, possibly with missing entries.

    Returns:
        A list of the present values, in order.
    """
    var out = List[Float64](capacity=len(values))
    for v in values:
        if not isnan(v):
            out.append(v)
    return out^


def _estimate(values: List[Float64], estimator: Estimator) raises -> Float64:
    """Reduce `values` by `estimator`, over the observations that are
    there. Raises when none is.

    `Estimator.COUNT` therefore reports the effective sample size: how
    many observations the estimate rests on, not how many rows the
    column had (#367).
    """
    var present = _present(values)
    var n = len(present)
    if n == 0:
        raise Error(
            "an estimate needs at least one observation, and every value"
            " in this group is missing"
        )
    if estimator == Estimator.COUNT:
        return Float64(n)
    var total = 0.0
    for v in present:
        total += v
    if estimator == Estimator.SUM:
        return total
    if estimator == Estimator.MEAN:
        return total / Float64(n)
    var sorted = present^
    _sort_ascending(sorted)
    return _percentile(sorted, 0.5)


def _sample_sd(values: List[Float64]) -> Float64:
    """The sample standard deviation (n - 1 in the denominator) over the
    observations that are there; `0.0` below two of them, where it is
    undefined (#367)."""
    var present = _present(values)
    var n = len(present)
    if n < 2:
        return 0.0
    var mean = 0.0
    for v in present:
        mean += v
    mean /= Float64(n)
    var ss = 0.0
    for v in present:
        ss += (v - mean) * (v - mean)
    return sqrt(ss / Float64(n - 1))


def _interval(
    values: List[Float64],
    estimator: Estimator,
    errorbar: ErrorBar,
    seed: UInt64,
) raises -> Tuple[Float64, Float64]:
    """The `(low, high)` interval around `_estimate(values, estimator)`
    that `errorbar` asks for, over the observations that are there.
    `COUNT` and `ErrorBar.none()` both give the estimate twice -- an
    empty interval, drawn as no whisker.
    """
    var est = _estimate(values, estimator)
    if errorbar.is_none() or estimator == Estimator.COUNT:
        return (est, est)
    # Every part below counts, resamples or sorts observations, so it
    # works from the ones that are there: `n` is the effective sample
    # size, and a bootstrap that could draw a missing value would put a
    # `NaN` into an interval (#367).
    var present = _present(values)
    var n = len(present)
    if errorbar._kind == 1:
        var half = errorbar.scale * _sample_sd(present)
        return (est - half, est + half)
    if errorbar._kind == 2:
        var half = errorbar.scale * _sample_sd(present) / sqrt(Float64(n))
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
        var sorted = present.copy()
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
            draw.append(present[Int(rng.next_bits() % UInt64(n))])
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
    var kept = List[String](capacity=len(categories))
    var estimates = List[Float64](capacity=len(categories))
    var lows = List[Float64](capacity=len(categories))
    var highs = List[Float64](capacity=len(categories))
    for j in range(len(categories)):
        # A group whose observations are all missing has no estimate to
        # draw, so it leaves the axis rather than becoming a bar of no
        # height, which would read as a measured zero (#367).
        if len(_present(members[j])) == 0:
            continue
        kept.append(categories[j])
        estimates.append(_estimate(members[j], estimator))
        var iv = _interval(members[j], estimator, errorbar, seed)
        lows.append(iv[0])
        highs.append(iv[1])
    if len(kept) == 0:
        raise Error(
            "nothing to estimate: every observation in every group is missing"
        )
    return _Aggregate(kept^, estimates^, lows^, highs^)


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
    per-x estimation `lineplot()` performs on repeated
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
        # A row with no x has no position on the axis to be estimated
        # at, so it takes no part (#367). A row with an x but no y is
        # kept here and dropped by the estimate below, which is what
        # makes the effective sample size right.
        if isnan(x[i]):
            continue
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
        # An x whose observations are all missing has no estimate; it
        # leaves the line rather than dropping it to a measured-looking
        # zero (#367).
        if len(_present(members[j])) == 0:
            continue
        xs.append(keys[j])
        estimates.append(_estimate(members[j], estimator))
        var iv = _interval(members[j], estimator, errorbar, seed)
        lows.append(iv[0])
        highs.append(iv[1])
    if len(xs) == 0:
        raise Error(
            "nothing to estimate: every observation at every x is missing"
        )
    return _NumericAggregate(xs^, estimates^, lows^, highs^)


struct SmoothMethod(Copyable, ImplicitlyCopyable, Movable):
    """Which curve `Plot.annotate_smooth()` fits (#147).

    - `SmoothMethod.LOESS` -- locally weighted regression: at each point
      along x, a polynomial fitted to the nearest `span` share of the
      data, weighted so the nearest count most. It follows whatever
      shape the data has, which is what makes it the default trend line
      for exploring data.
    - `SmoothMethod.POLYNOMIAL` -- one least-squares polynomial of a
      given degree over all the data: a single formula, for when the
      shape is known to be, say, quadratic.
    """

    var _value: Int

    comptime LOESS = Self(0)
    comptime POLYNOMIAL = Self(1)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


def _solve_linear(
    var a: List[List[Float64]], var b: List[Float64]
) raises -> List[Float64]:
    """Solve `a * x = b` for a small square system by Gaussian
    elimination with partial pivoting (#147).

    Only ever handed a normal-equations system of a few rows -- a
    polynomial fit's or a LOESS window's -- so there is no call for a
    general linear-algebra dependency. A pivot that vanishes relative to
    the matrix's largest entry means the data cannot determine the fit
    (too few distinct x values for the degree), and raises.

    Args:
        a: The coefficient matrix, `n` rows of `n`.
        b: The right-hand side, `n` long.

    Returns:
        The solution, `n` long.

    Raises:
        Error: The system is singular to working precision.
    """
    var n = len(b)
    var scale = 0.0
    for row in a:
        for v in row:
            scale = max(scale, abs(v))
    if scale == 0.0:
        raise Error("the fit's system is singular")
    for col in range(n):
        var pivot = col
        for r in range(col + 1, n):
            if abs(a[r][col]) > abs(a[pivot][col]):
                pivot = r
        if abs(a[pivot][col]) <= 1e-12 * scale:
            raise Error(
                "the fit's system is singular -- too few distinct x values"
                " for the degree"
            )
        if pivot != col:
            var tmp_row = a[col].copy()
            a[col] = a[pivot].copy()
            a[pivot] = tmp_row^
            var tmp_b = b[col]
            b[col] = b[pivot]
            b[pivot] = tmp_b
        for r in range(col + 1, n):
            var f = a[r][col] / a[col][col]
            if f == 0.0:
                continue
            for c in range(col, n):
                a[r][c] -= f * a[col][c]
            b[r] -= f * b[col]
    var x = List[Float64](capacity=n)
    for _ in range(n):
        x.append(0.0)
    for r in range(n - 1, -1, -1):
        var acc = b[r]
        for c in range(r + 1, n):
            acc -= a[r][c] * x[c]
        x[r] = acc / a[r][r]
    return x^


def _weighted_poly_intercept(
    t: List[Float64], y: List[Float64], w: List[Float64], degree: Int
) raises -> Float64:
    """The constant term of the weighted least-squares polynomial of
    `degree` in `t`: the fitted value at `t = 0`.

    Builds the normal equations `sum w t^(j+k) * c_k = sum w t^j y`
    and solves them with `_solve_linear`.
    """
    var size = degree + 1
    var a = List[List[Float64]](capacity=size)
    var b = List[Float64](capacity=size)
    for _ in range(size):
        var row = List[Float64](capacity=size)
        for _ in range(size):
            row.append(0.0)
        a.append(row^)
        b.append(0.0)
    for i in range(len(t)):
        if w[i] == 0.0:
            continue
        var powers = List[Float64](capacity=2 * size)
        var p = 1.0
        for _ in range(2 * size - 1):
            powers.append(p)
            p *= t[i]
        for j in range(size):
            b[j] += w[i] * powers[j] * y[i]
            for k in range(size):
                a[j][k] += w[i] * powers[j + k]
    return _solve_linear(a^, b^)[0]


struct _PolyFit(Copyable, Movable):
    """A least-squares polynomial in the centered, scaled variable
    `(x - center) / spread`, which keeps the normal equations well
    conditioned when x is large or the degree is high."""

    var center: Float64
    var spread: Float64
    var coefficients: List[Float64]
    """Lowest power first, in the scaled variable."""

    def __init__(
        out self,
        center: Float64,
        spread: Float64,
        var coefficients: List[Float64],
    ):
        self.center = center
        self.spread = spread
        self.coefficients = coefficients^

    def predict(self, x: Float64) -> Float64:
        var t = (x - self.center) / self.spread
        var acc = 0.0
        for k in range(len(self.coefficients) - 1, -1, -1):
            acc = acc * t + self.coefficients[k]
        return acc


def _poly_fit(
    x: List[Float64], y: List[Float64], degree: Int
) raises -> _PolyFit:
    """The least-squares polynomial of `degree` through `(x, y)` (#147).

    Fitted in `(x - mean) / max|x - mean|` rather than in x itself: the
    normal equations raise x to the power `2 * degree`, and for years or
    timestamps that loses every significant digit. The same fit, better
    conditioned; `_PolyFit.predict` undoes the transform.

    Raises:
        Error: `degree` is below 1, the columns differ in length, or
            there are not more distinct x values than `degree`.
    """
    if degree < 1:
        raise Error("degree must be at least 1 (got " + String(degree) + ")")
    if len(x) != len(y):
        raise Error("x and y must be the same length")
    if len(x) <= degree:
        raise Error(
            "a degree-"
            + String(degree)
            + " polynomial needs more than "
            + String(degree)
            + " points (got "
            + String(len(x))
            + ")"
        )
    var center = 0.0
    for v in x:
        center += v
    center /= Float64(len(x))
    var spread = 0.0
    for v in x:
        spread = max(spread, abs(v - center))
    if spread == 0.0:
        raise Error("every x value is the same, so no curve fits")
    var t = List[Float64](capacity=len(x))
    var w = List[Float64](capacity=len(x))
    for v in x:
        t.append((v - center) / spread)
        w.append(1.0)
    # The full coefficient vector, not just the intercept: solve the
    # same normal equations _weighted_poly_intercept builds.
    var size = degree + 1
    var a = List[List[Float64]](capacity=size)
    var b = List[Float64](capacity=size)
    for _ in range(size):
        var row = List[Float64](capacity=size)
        for _ in range(size):
            row.append(0.0)
        a.append(row^)
        b.append(0.0)
    for i in range(len(t)):
        var p = 1.0
        var powers = List[Float64](capacity=2 * size)
        for _ in range(2 * size - 1):
            powers.append(p)
            p *= t[i]
        for j in range(size):
            b[j] += powers[j] * y[i]
            for k in range(size):
                a[j][k] += powers[j + k]
    return _PolyFit(center, spread, _solve_linear(a^, b^))


def _loess_at(
    x: List[Float64],
    y: List[Float64],
    x0: Float64,
    span: Float64,
    degree: Int,
) raises -> Float64:
    """The LOESS estimate at `x0` (#147): a weighted least-squares
    polynomial of `degree` fitted to the `floor(span * n)` points
    nearest `x0`, evaluated at `x0`.

    Each point in the window is weighted by the tricube kernel of its
    distance over the window's radius `h` -- the distance to the
    `q`-th nearest point -- so `(1 - (d/h)^3)^3`, one at `x0` and
    falling to zero at the window's edge. This is Cleveland's local
    regression, without the robustness iterations that down-weight
    outliers.

    Raises:
        Error: `span` is outside `(0, 1]`, `degree` is not 1 or 2, or
            the window holds too few distinct x values for the degree.
    """
    if span <= 0.0 or span > 1.0:
        raise Error("span must be in (0, 1] (got " + String(span) + ")")
    if degree != 1 and degree != 2:
        raise Error(
            "a LOESS degree must be 1 or 2 (got " + String(degree) + ")"
        )
    var n = len(x)
    var q = Int(span * Float64(n))
    if q < degree + 2:
        raise Error(
            "span "
            + String(span)
            + " of "
            + String(n)
            + " points leaves "
            + String(q)
            + " in each window, too few for a degree-"
            + String(degree)
            + " fit"
        )
    var d = List[Float64](capacity=n)
    for v in x:
        d.append(abs(v - x0))
    var sorted_d = d.copy()
    sort(sorted_d)
    var h = sorted_d[q - 1]
    if h == 0.0:
        raise Error(
            "the nearest "
            + String(q)
            + " points all sit at one x value, so no local curve fits"
        )
    var t = List[Float64](capacity=n)
    var w = List[Float64](capacity=n)
    for i in range(n):
        var u = d[i] / h
        var wt = 0.0
        if u < 1.0:
            var c = 1.0 - u * u * u
            wt = c * c * c
        w.append(wt)
        t.append((x[i] - x0) / h)
    return _weighted_poly_intercept(t, y, w, degree)
