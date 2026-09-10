"""`barplot()` and `countplot()`: bars of an estimate per category with
its uncertainty, and bars of a count -- seaborn's pair, and the first
charts here that compute an aggregate rather than draw one (#350)."""

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.stats import ErrorBar, Estimator, _Aggregate, _aggregate
from dataviz.theme import Theme


def barplot(
    categories: List[String],
    values: List[Float64],
    estimator: Estimator = Estimator.MEAN,
    errorbar: ErrorBar = ErrorBar.ci(0.95),
    seed: Int = 12345,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """One bar per distinct category holding an *estimate* of that
    category's values -- the mean by default -- with a whisker for its
    uncertainty: seaborn's `barplot()`. Unlike `bar()`, which draws the
    numbers it is given, this takes raw observations, several per
    category, and reduces them.

    `Mark.BAR` over `_aggregate()`'s per-category estimate, with
    `y_err_lower`/`y_err_upper` set from the interval. Categories keep
    the order they are first seen in.

    A bar of an estimate hides its sample size: a mean of three points
    and a mean of three thousand look the same apart from the whisker.
    So the estimator is named on the y-axis by default (`y_title` empty
    draws "Mean", "Median", "Count" or "Sum"), and the whisker is on by
    default rather than opt-in.

    Args:
        categories: The group each observation belongs to, one per
            observation; repeated as observations repeat.
        values: One observation per entry of `categories`.
        estimator: `Estimator.MEAN` (the default), `MEDIAN`, `COUNT` or
            `SUM`.
        errorbar: `ErrorBar.ci(0.95)` (the default): a bootstrap 95%
            confidence interval of the estimate. `ErrorBar.se()`,
            `.sd()`, `.pi()` or `.none()` for the others; see `ErrorBar`.
        seed: The bootstrap's seed. Fixed by default so a chart renders
            the same every time; change it to see how much the interval
            moves under resampling.
        theme: Full styling knobs beyond this function's own arguments.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; empty for none.
        y_title: Y-axis title; empty (the default) names the estimator.
        horizontal: Draw categories top-to-bottom with bars running
            left-to-right.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: `categories` and `values` differ in length or are empty,
            or an interval level is outside `(0, 1)`.

    Example:
        ```mojo
        from dataviz import barplot, save

        def main() raises:
            # Illustrative response times (ms) from repeated trials on
            # three servers: several observations per server, reduced to
            # a mean with its bootstrap 95% confidence interval.
            var servers = List[String]()
            var latency = List[Float64]()
            var a: List[Float64] = [118.0, 124.0, 131.0, 122.0, 127.0, 119.0]
            var b: List[Float64] = [142.0, 165.0, 139.0, 171.0, 150.0, 158.0]
            var c: List[Float64] = [101.0, 104.0, 99.0, 103.0, 100.0, 102.0]
            for v in a:
                servers.append("east")
                latency.append(v)
            for v in b:
                servers.append("west")
                latency.append(v)
            for v in c:
                servers.append("edge")
                latency.append(v)
            var chart = barplot(
                servers,
                latency,
                title="Illustrative Mean Response Time by Server",
                y_title="Mean latency (ms), 95% CI",
            )
            save(chart, "docs/src/examples/out_barplot.svg")
        ```
    """
    var agg: _Aggregate
    try:
        agg = _aggregate(categories, values, estimator, errorbar, UInt64(seed))
    except e:
        raise Error("barplot(): " + String(e))
    var plot = Plot().mark_bar(horizontal=horizontal)
    if errorbar.is_none() or estimator == Estimator.COUNT:
        plot = plot^.encode_categorical(x=agg.categories, y=agg.estimates)
    else:
        var lower = List[Float64](capacity=len(agg.estimates))
        var upper = List[Float64](capacity=len(agg.estimates))
        for i in range(len(agg.estimates)):
            lower.append(agg.estimates[i] - agg.lows[i])
            upper.append(agg.highs[i] - agg.estimates[i])
        plot = plot^.encode_categorical(
            x=agg.categories,
            y=agg.estimates,
            y_err_lower=lower,
            y_err_upper=upper,
        )
    var resolved_y = y_title if y_title.byte_length() > 0 else estimator.label()
    return _finished(
        plot^,
        theme,
        width,
        height,
        title,
        x_title,
        resolved_y,
        subtitle=subtitle,
    )


def barplot[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    estimator: Estimator = Estimator.MEAN,
    errorbar: ErrorBar = ErrorBar.ci(0.95),
    seed: Int = 12345,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`barplot()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.
    """
    return barplot(
        categories,
        _materialize_scalar_list(values),
        estimator=estimator,
        errorbar=errorbar,
        seed=seed,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
        horizontal=horizontal,
    )


def countplot(
    categories: List[String],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "Count",
    horizontal: Bool = False,
) raises -> Plot:
    """One bar per distinct category holding how many times it appears:
    seaborn's `countplot()`, the degenerate `barplot()` whose estimator
    is a count and which therefore has no interval.

    Args:
        categories: One entry per observation; repeated as observations
            repeat. Bars keep first-seen order.
        theme: Full styling knobs beyond this function's own arguments.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; empty for none.
        y_title: Y-axis title; "Count" by default.
        horizontal: Draw categories top-to-bottom with bars running
            left-to-right.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: `categories` is empty.

    Example:
        ```mojo
        from dataviz import countplot, save

        def main() raises:
            # Illustrative support tickets by channel over a week: one
            # entry per ticket, counted into a bar per channel.
            var channel = List[String]()
            var n: List[Int] = [23, 41, 9, 17]
            var names: List[String] = ["email", "chat", "phone", "form"]
            for i in range(len(names)):
                for _ in range(n[i]):
                    channel.append(names[i])
            var chart = countplot(
                channel, title="Illustrative Support Tickets by Channel"
            )
            save(chart, "docs/src/examples/out_countplot.svg")
        ```
    """
    var ones = List[Float64](capacity=len(categories))
    for _ in range(len(categories)):
        ones.append(1.0)
    var agg: _Aggregate
    try:
        agg = _aggregate(
            categories, ones, Estimator.COUNT, ErrorBar.none(), UInt64(0)
        )
    except e:
        raise Error("countplot(): " + String(e))
    var plot = (
        Plot()
        .mark_bar(horizontal=horizontal)
        .encode_categorical(x=agg.categories, y=agg.estimates)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
