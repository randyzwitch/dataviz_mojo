"""`lineplot()`: the estimate per x of repeated measurements, drawn as a
line with a band for its uncertainty, and the reason that chart can take
a dataset where a plain `line()` cannot."""

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.core.stats import (
    ErrorBar,
    Estimator,
    _NumericAggregate,
    _aggregate_by_x,
)
from dataviz.core.theme import Theme


def lineplot(
    df: DataFrame,
    x: String,
    y: String,
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
) raises -> Plot:
    """`lineplot()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values. The axis titles default to the `x` and `y` column names.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        y: The numeric column for this channel.
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

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var x_values = _frame_floats(df, x, "lineplot()", theme.missing)
    var y_values = _frame_floats(df, y, "lineplot()", theme.missing)
    return lineplot(
        x=x_values,
        y=y_values,
        estimator=estimator,
        errorbar=errorbar,
        seed=seed,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else x,
        y_title=y_title if y_title.byte_length() > 0 else y,
    )


def lineplot[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
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
) raises -> Plot:
    """A line through the *estimate* of `y` at each distinct `x` -- the
    mean by default -- with a shaded band for its uncertainty. Where
    `line()` connects the points it is given,
    this takes repeated measurements, several `y` per `x`, reduces each
    `x` to one estimate and draws the interval around it.

    `Mark.LINE` over `_aggregate_by_x()`'s per-x estimate, sorted by
    `x`, plus `annotate_band()` between the interval's edges. Exact
    `x` equality defines a group; two readings at nearly the same `x`
    are two positions, since merging them would be binning.

    A line of estimates hides how many readings stand behind each
    point, so the estimator is named on the y-axis by default
    (`y_title` empty draws "Mean", "Median", "Count" or "Sum") and the
    band is on by default rather than opt-in.

    Args:
        x: The position of each observation; repeated as measurements
            repeat at the same x.
        y: One observation per entry of `x`.
        estimator: `Estimator.MEAN` (the default), `MEDIAN`, `COUNT` or
            `SUM`.
        errorbar: `ErrorBar.ci(0.95)` (the default): a bootstrap 95%
            confidence interval of the estimate. `ErrorBar.se()`,
            `.sd()`, `.pi()` or `.none()` for the others; see `ErrorBar`.
        seed: The bootstrap's seed, fixed by default so a chart renders
            the same every time.
        theme: Full styling knobs beyond this function's own arguments.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; empty for none.
        y_title: Y-axis title; empty (the default) names the estimator.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: `x` and `y` differ in length or are empty, or an interval
            level is outside `(0, 1)`.

    Example:
        ```mojo
        from dataviz import lineplot, save

        def main() raises:
            # Illustrative reaction time (ms) across five sessions, three
            # trials per session per participant. Each session's readings
            # collapse to a mean with its bootstrap 95% confidence band.
            var session = List[Float64]()
            var reaction = List[Float64]()
            var trials: List[List[Float64]] = [
                [412.0, 398.0, 431.0, 405.0, 420.0, 415.0],
                [388.0, 371.0, 402.0, 379.0, 395.0, 384.0],
                [362.0, 349.0, 377.0, 358.0, 366.0, 355.0],
                [351.0, 338.0, 360.0, 344.0, 357.0, 349.0],
                [340.0, 333.0, 352.0, 339.0, 347.0, 336.0],
            ]
            for s in range(len(trials)):
                for v in trials[s]:
                    session.append(Float64(s + 1))
                    reaction.append(v)
            var chart = lineplot(
                session,
                reaction,
                title="Illustrative Reaction Time by Session",
                x_title="Session",
                y_title="Mean reaction time (ms), 95% CI",
            )
            save(chart, "docs/src/examples/out_lineplot.svg")
        ```
    """
    var x_f = _materialize_scalar_list(x)
    var y_f = _materialize_scalar_list(y)
    var agg: _NumericAggregate
    try:
        agg = _aggregate_by_x(x_f, y_f, estimator, errorbar, UInt64(seed))
    except e:
        raise Error("lineplot(): " + String(e))
    var plot = Plot().mark_line().encode(x=agg.xs, y=agg.estimates)
    if not (errorbar.is_none() or estimator == Estimator.COUNT):
        plot = plot^.annotate_band(agg.xs, agg.lows, agg.highs)
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
