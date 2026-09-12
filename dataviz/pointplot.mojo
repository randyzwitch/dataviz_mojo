"""`Mark.POINTPLOT` and `pointplot()`: the estimate per category as a
point with its interval as a whisker, joined across categories --
seaborn's `pointplot()`, `barplot()`'s estimate with a lighter glyph."""

from canvas.geometry import round_to_int
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.bar import _bar_y_domain_data
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel_f,
    _data_extent,
    _draw_categorical_axis_frame,
    _finished,
    _validate_categorical_encoding,
)
from dataviz.core.stats import ErrorBar, Estimator, _Aggregate, _aggregate
from dataviz.core.theme import Theme


def _render_pointplot[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.POINTPLOT` plot: `_render_bar`'s categorical x-axis
    (`_draw_categorical_axis_frame`) with, at each category's band
    center, a whisker from `y_err_lower` to `y_err_upper` when
    `Plot.encode_categorical()` set them, a line joining consecutive
    values, and a point on the value -- drawn in that order so the
    point sits on top of everything at its own position.

    The y-domain is `_data_extent` over the values and whisker ends,
    not a zero baseline: an estimate's position is what the chart
    encodes, and forcing zero onto the axis would compress a set of
    means that all sit far from it -- the same reason `Mark.POINT`
    does not baseline.
    """
    _validate_categorical_encoding(plot)
    var theme = plot._theme
    var y_scale = _data_extent(_bar_y_domain_data(plot))
    var frame = _draw_categorical_axis_frame(
        target,
        plot._categorical.x,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    var sc = _Scaled(theme)
    var n = len(plot._categorical.x)
    var has_err = len(plot._y_err.symmetric) > 0 or len(plot._y_err.lower) > 0
    var cap_half = sc.error_bar_cap_width

    var cxs = List[Float64](capacity=n)
    var pys = List[Float64](capacity=n)
    for i in range(n):
        cxs.append(frame.x_scale.center(i))
        pys.append(_axis_pixel_f(frame.y_scale, plot._continuous.y[i]))

    if has_err:
        for i in range(n):
            var value = plot._continuous.y[i]
            var lo: Float64
            var hi: Float64
            if len(plot._y_err.symmetric) > 0:
                lo = value - plot._y_err.symmetric[i]
                hi = value + plot._y_err.symmetric[i]
            else:
                lo = value - plot._y_err.lower[i]
                hi = value + plot._y_err.upper[i]
            var py_lo = _axis_pixel_f(frame.y_scale, lo)
            var py_hi = _axis_pixel_f(frame.y_scale, hi)
            target.draw_line_aa(
                cxs[i], py_hi, cxs[i], py_lo, theme.mark_color, width=sc.scale
            )
            target.draw_line_aa(
                cxs[i] - cap_half,
                py_hi,
                cxs[i] + cap_half,
                py_hi,
                theme.mark_color,
                width=sc.scale,
            )
            target.draw_line_aa(
                cxs[i] - cap_half,
                py_lo,
                cxs[i] + cap_half,
                py_lo,
                theme.mark_color,
                width=sc.scale,
            )

    for i in range(1, n):
        target.draw_line_aa(
            cxs[i - 1],
            pys[i - 1],
            cxs[i],
            pys[i],
            theme.mark_color,
            width=sc.line_width,
        )

    var radius = Float64(round_to_int(sc.point_radius))
    for i in range(n):
        target.fill_circle_aa(cxs[i], pys[i], radius, theme.mark_color)

    return frame.result()


def pointplot(
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
) raises -> Plot:
    """One point per distinct category at an *estimate* of that category's
    values -- the mean by default -- with a whisker for its uncertainty
    and a line joining the points: seaborn's `pointplot()`. The same
    reduction as `barplot()`, drawn as a position rather than a length,
    which is the better glyph when the estimates sit far from zero or
    when the shape across categories is the point.

    `Mark.POINTPLOT` over `_aggregate()`'s per-category estimate, with
    `y_err_lower`/`y_err_upper` from the interval. Categories keep the
    order they are first seen in.

    An estimate hides its sample size, so the estimator is named on
    the y-axis by default (`y_title` empty draws "Mean", "Median",
    "Count" or "Sum") and the whisker is on by default.

    Args:
        categories: The group each observation belongs to, one per
            observation; repeated as observations repeat.
        values: One observation per entry of `categories`.
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
        Error: `categories` and `values` differ in length or are empty,
            or an interval level is outside `(0, 1)`.

    Example:
        ```mojo
        from dataviz import pointplot, save

        def main() raises:
            # Illustrative customer-satisfaction scores (1-10) from
            # repeated surveys across four quarters: several responses per
            # quarter, reduced to a mean with its bootstrap 95% confidence
            # interval, joined to show the trend.
            var quarter = List[String]()
            var score = List[Float64]()
            var q: List[List[Float64]] = [
                [7.1, 6.8, 7.4, 7.0, 6.9, 7.3, 7.2],
                [7.4, 7.6, 7.2, 7.8, 7.5, 7.3, 7.7],
                [7.9, 8.2, 7.7, 8.0, 8.3, 7.8, 8.1],
                [8.4, 8.1, 8.6, 8.3, 8.7, 8.2, 8.5],
            ]
            var names: List[String] = ["Q1", "Q2", "Q3", "Q4"]
            for i in range(len(names)):
                for v in q[i]:
                    quarter.append(names[i])
                    score.append(v)
            var chart = pointplot(
                quarter,
                score,
                title="Illustrative Satisfaction by Quarter",
                y_title="Mean score (1-10), 95% CI",
            )
            save(chart, "docs/src/examples/out_pointplot.svg")
        ```
    """
    var agg: _Aggregate
    try:
        agg = _aggregate(categories, values, estimator, errorbar, UInt64(seed))
    except e:
        raise Error("pointplot(): " + String(e))
    var plot = Plot().mark_pointplot()
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


def pointplot[
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
) raises -> Plot:
    """`pointplot()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (continuous.mojo). Delegates to the
    concrete overload above.
    """
    return pointplot(
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
    )
