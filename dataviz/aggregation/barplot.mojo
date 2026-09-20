"""`barplot()`: bars of an estimate per category with its uncertainty,
the first chart here that computes an aggregate rather than draws one
(#350)."""

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.core.stats import ErrorBar, Estimator, _Aggregate, _aggregate
from dataviz.core.theme import Theme


def barplot(
    df: DataFrame,
    categories: String,
    values: String,
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
    """`barplot()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values. The axis titles default to the `categories` and `values` column names.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: The string column for this channel.
        values: The numeric column for this channel.
        estimator: See the list overload.
        errorbar: See the list overload.
        seed: See the list overload.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.
        y_title: See the list overload.
        horizontal: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var categories_values = _frame_strings(df, categories, "barplot()")
    var values_values = _frame_floats(df, values, "barplot()")
    return barplot(
        categories=categories_values,
        values=values_values,
        estimator=estimator,
        errorbar=errorbar,
        seed=seed,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else categories,
        y_title=y_title if y_title.byte_length() > 0 else values,
        horizontal=horizontal,
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
    """One bar per distinct category holding an *estimate* of that
    category's values -- the mean by default -- with a whisker for its
    uncertainty. Unlike `bar()`, which draws the
    numbers it is given, this takes raw observations, several per
    category, and reduces them.

    `Mark.BAR` over `_aggregate()`'s per-category estimate, with
    `y_err_lower`/`y_err_upper` set from the interval. Categories keep
    the order they are first seen in.

    A bar of an estimate hides its sample size: a mean of three points
    and a mean of three thousand look the same apart from the whisker.
    So the estimator is named on the value axis by default -- the y-axis,
    or the x-axis with `horizontal=True` (an empty `y_title`, or
    `x_title`, draws "Mean", "Median", "Count" or "Sum") -- and the
    whisker is on by default rather than opt-in.

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
        x_title: X-axis title; empty for none, or for the estimator's
            name with `horizontal=True`.
        y_title: Y-axis title; empty (the default) names the estimator,
            or none with `horizontal=True`.
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
    var values_f = _materialize_scalar_list(values)
    var agg: _Aggregate
    try:
        agg = _aggregate(
            categories, values_f, estimator, errorbar, UInt64(seed)
        )
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
    # The estimator names the value axis, which is x when horizontal.
    var resolved_x = x_title
    var resolved_y = y_title
    if horizontal:
        if resolved_x.byte_length() == 0:
            resolved_x = estimator.label()
    elif resolved_y.byte_length() == 0:
        resolved_y = estimator.label()
    return _finished(
        plot^,
        theme,
        width,
        height,
        title,
        resolved_x,
        resolved_y,
        subtitle=subtitle,
    )
