"""`residplot()`: the residuals of a linear fit against its fitted values,
the standard check on whether a straight line was the right model."""

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import Plot, _finished
from dataviz.core.stats import _OlsFit, _ols_fit
from dataviz.core.theme import Theme


def residplot(
    df: DataFrame,
    x: String,
    y: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "Fitted value",
    y_title: String = "Residual",
) raises -> Plot:
    """`residplot()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values. The axis titles default to the `x` and `y` column names.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        y: The numeric column for this channel.
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
    var x_values = _frame_floats(df, x, "residplot()")
    var y_values = _frame_floats(df, y, "residplot()")
    return residplot(
        x=x_values,
        y=y_values,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else x,
        y_title=y_title if y_title.byte_length() > 0 else y,
    )


def residplot[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "Fitted value",
    y_title: String = "Residual",
) raises -> Plot:
    """Fit `y = m*x + b` by ordinary least squares and scatter each point's
    residual (`y - fitted`) against its fitted value, with a reference
    line at zero: the diagnostic for whether a
    linear fit was appropriate at all (#352).

    A fit that is right leaves residuals scattered evenly about zero
    with no pattern. Curvature -- a U or an arch -- says the
    relationship is not linear; a fan that widens to one side says the
    spread changes with the level. Neither is visible on the fitted
    line itself, which is why this chart exists.

    The same fit `annotate_best_fit()` draws (`_ols_fit`, stats.mojo),
    so the residuals here are exactly the distances from that line.
    `Mark.POINT` over the fitted values and residuals, plus
    `annotate_line(0.0)`.

    Args:
        x: The predictor, one entry per observation.
        y: The response, matching `x` in length.
        theme: Full styling knobs beyond this function's own arguments.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; "Fitted value" by default.
        y_title: Y-axis title; "Residual" by default.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: Fewer than 2 points, `x` and `y` of different lengths, or
            every `x` identical (no non-vertical line fits).

    Example:
        ```mojo
        from dataviz import residplot, save

        def main() raises:
            # Illustrative braking distance (m) against speed (km/h). The
            # true relationship is quadratic, so a straight-line fit
            # leaves a U of residuals: positive at both ends, negative in
            # the middle -- the shape that says "not linear".
            var speed = List[Float64]()
            var distance = List[Float64]()
            for i in range(12):
                var v = 20.0 + 10.0 * Float64(i)
                speed.append(v)
                distance.append(0.0065 * v * v + 0.2 * v)
            var c = residplot(
                speed,
                distance,
                title="Residuals of a Linear Fit to Braking Distance",
                x_title="Fitted distance (m)",
                y_title="Residual (m)",
            )
            save(c, "docs/src/examples/out_residplot.svg")
        ```
    """
    var x_f = _materialize_scalar_list(x)
    var y_f = _materialize_scalar_list(y)
    if len(x_f) != len(y_f):
        raise Error(
            "residplot(): x_f and y_f must have the same length (got "
            + String(len(x_f))
            + " and "
            + String(len(y_f))
            + ")"
        )
    var fit: _OlsFit
    try:
        fit = _ols_fit(x_f, y_f)
    except e:
        raise Error("residplot(): " + String(e))
    var fitted = List[Float64](capacity=len(x_f))
    var residuals = List[Float64](capacity=len(x_f))
    for i in range(len(x_f)):
        var f = fit.predict(x_f[i])
        fitted.append(f)
        residuals.append(y_f[i] - f)
    var plot = (
        Plot().mark_point().encode(x=fitted, y=residuals).annotate_line(0.0)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
