"""`Mark.POINTPLOT` and `pointplot()`: the estimate per category as a
point with its interval as a whisker, joined across categories:
`barplot()`'s estimate with a lighter glyph."""

from canvas.geometry import round_to_int
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.basic.bar import _bar_y_domain_data
from dataviz.plot import Plot, _finished
from dataviz.core.frame import (
    _Orientation,
    _axis_pixel_f,
    _draw_categorical_axis_frame,
)
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled
from dataviz.core.extent import _data_extent
from dataviz.core.validate import _validate_categorical_encoding
from dataviz.core.stats import ErrorBar, Estimator, _Aggregate, _aggregate
from dataviz.core.theme import Theme
from dataviz.core.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.categorical.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.core.ordinal_scale import OrdinalScale


def _pointplot_value_label(plot: Plot, i: Int) -> String:
    """One category's estimate (#678): `"category: value"`, the same
    shape `_boxen_tooltip_label` uses for its median line."""
    var value = plot._continuous.y[i]
    return (
        plot._categorical.x[i]
        + ": "
        + _format_fixed(value, _label_decimals(value))
    )


def _pointplot_interval_label(
    plot: Plot, i: Int, lo: Float64, hi: Float64
) -> String:
    """One category's whisker (#678): `"category: LO-HI"`, mirroring
    `_boxen_tooltip_label`'s `"box LO-HI"` for the same kind of
    interval glyph."""
    return (
        plot._categorical.x[i]
        + ": "
        + _format_fixed(lo, _label_decimals(lo))
        + "-"
        + _format_fixed(hi, _label_decimals(hi))
    )


def _pointplot_value_extent(plot: Plot) raises -> LinearScale:
    """The value axis's domain: `_data_extent` over the values and
    whisker ends, not a zero baseline -- an estimate's position is what
    the chart encodes, and forcing zero onto the axis would compress a
    set of means that all sit far from it, the same reason `Mark.POINT`
    does not baseline. Shared by both orientations."""
    return _data_extent(_bar_y_domain_data(plot))


def _draw_pointplot_marks[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    value_scale: LinearScale,
    band_scale: OrdinalScale,
    orient: _Orientation,
) raises:
    """At each category's band center: a whisker from `y_err_lower` to
    `y_err_upper` when `Plot.encode_categorical()` set them, a line
    joining consecutive values, and a point on the value -- drawn in
    that order so the point sits on top of everything at its own
    position -- in whichever orientation `orient` names (#686).

    Its own function, as `_draw_bullet_rows` is, so the vertical and
    horizontal renders share the geometry. Everything goes through
    `_Orientation`: the points through `band_point`, and the whisker,
    its caps and the joining line through `point_line`, which does not
    snap -- the vertical render is byte-identical to the one before
    this split.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var n = len(plot._categorical.x)
    var has_err = len(plot._y_err.symmetric) > 0 or len(plot._y_err.lower) > 0
    # Each point is titled, and so is each error bar.
    var tooltips_on = plot._tooltips_on(2 * n if has_err else n)
    var cap_half = sc.error_bar_cap_width

    var bands = List[Float64](capacity=n)
    var values = List[Float64](capacity=n)
    for i in range(n):
        bands.append(band_scale.center(i))
        values.append(_axis_pixel_f(value_scale, plot._continuous.y[i]))

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
            var at_lo = _axis_pixel_f(value_scale, lo)
            var at_hi = _axis_pixel_f(value_scale, hi)
            if tooltips_on:
                target.begin_annotated_group(
                    _pointplot_interval_label(plot, i, lo, hi)
                )
            orient.point_line(
                target,
                at_hi,
                bands[i],
                at_lo,
                bands[i],
                theme.mark_color,
                sc.scale,
            )
            orient.point_line(
                target,
                at_hi,
                bands[i] - cap_half,
                at_hi,
                bands[i] + cap_half,
                theme.mark_color,
                sc.scale,
            )
            orient.point_line(
                target,
                at_lo,
                bands[i] - cap_half,
                at_lo,
                bands[i] + cap_half,
                theme.mark_color,
                sc.scale,
            )
            if tooltips_on:
                target.end_annotated_group()

    for i in range(1, n):
        orient.point_line(
            target,
            values[i - 1],
            bands[i - 1],
            values[i],
            bands[i],
            theme.mark_color,
            sc.line_width,
        )

    var radius = Float64(round_to_int(sc.point_radius))
    for i in range(n):
        if tooltips_on:
            target.begin_annotated_group(_pointplot_value_label(plot, i))
        orient.band_point(target, values[i], bands[i], radius, theme.mark_color)
        if tooltips_on:
            target.end_annotated_group()


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
    """Render a `Mark.POINTPLOT` plot on `_render_bar`'s categorical
    x-axis (`_draw_categorical_axis_frame`), the values running up the
    page; `_draw_pointplot_marks` draws the whiskers, joining line and
    points, and `_pointplot_value_extent` says why the value axis does
    not start at zero.
    """
    _validate_categorical_encoding(
        plot._categorical, plot._continuous, plot._y_err, plot._mark
    )
    var frame = _draw_categorical_axis_frame(
        target,
        plot._categorical.x,
        _pointplot_value_extent(plot),
        plot._theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_pointplot_marks(
        target, plot, frame.y_scale, frame.x_scale, _Orientation(False)
    )
    return frame.result()


def _render_horizontal_pointplot[
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
    """`_render_pointplot`'s mirror image for
    `Plot.mark_pointplot(horizontal=True)` (#686): the categories run
    down the page and the estimates rightward, on
    `_draw_horizontal_categorical_axis_frame` (gantt.mojo) -- the
    orientation for long category names, which a vertical categorical
    axis crowds.
    """
    _validate_categorical_encoding(
        plot._categorical, plot._continuous, plot._y_err, plot._mark
    )
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
        _pointplot_value_extent(plot),
        plot._theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_pointplot_marks(
        target, plot, frame.x_scale, frame.y_scale, _Orientation(True)
    )
    return frame.result()


def pointplot(
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
    """`pointplot()` over named columns of a `dataframe_mojo`
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
    var categories_values = _frame_strings(
        df,
        categories,
        "pointplot()",
        theme.missing,
        theme.missing_category_label,
    )
    var values_values = _frame_floats(df, values, "pointplot()", theme.missing)
    return pointplot(
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
    horizontal: Bool = False,
) raises -> Plot:
    """One point per distinct category at an *estimate* of that category's
    values -- the mean by default -- with a whisker for its uncertainty
    and a line joining the points. The same
    reduction as `barplot()`, drawn as a position rather than a length,
    which is the better glyph when the estimates sit far from zero or
    when the shape across categories is the point.

    `Mark.POINTPLOT` over `_aggregate()`'s per-category estimate, with
    `y_err_lower`/`y_err_upper` from the interval. Categories keep the
    order they are first seen in.

    An estimate hides its sample size, so the estimator is named on
    the value axis by default -- the y-axis, or the x-axis with
    `horizontal=True` (an empty `y_title`, or `x_title`, draws "Mean",
    "Median", "Count" or "Sum") -- and the whisker is on by default.

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
        x_title: X-axis title; empty for none, or for the estimator's
            name with `horizontal=True`.
        y_title: Y-axis title; empty (the default) names the estimator,
            or none with `horizontal=True`.
        horizontal: Run the categories down the page and the estimates
            rightward, for long category names.

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
    var values_f = _materialize_scalar_list(values)
    var agg: _Aggregate
    try:
        agg = _aggregate(
            categories, values_f, estimator, errorbar, UInt64(seed)
        )
    except e:
        raise Error("pointplot(): " + String(e))
    var plot = Plot().mark_pointplot(horizontal=horizontal)
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
    # The estimator names the value axis, which is x when horizontal
    # (#709 is the same rule for barplot()).
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


def _render_pointplot_oriented[
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
    """`Mark.POINTPLOT`'s renderer, the one its setter binds: `_render_horizontal_pointplot`
    when the plot is horizontal, `_render_pointplot` otherwise."""
    if plot._horizontal:
        return _render_horizontal_pointplot(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    return _render_pointplot(target, plot, ox0, oy0, ox1, oy1, cache=cache)
