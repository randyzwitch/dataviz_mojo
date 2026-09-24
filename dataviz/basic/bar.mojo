from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame
from morrow import Morrow

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.frame_input import _frame_column, _frame_floats, _frame_morrow

from canvas.text.render import TextAlign
from dataviz.core.ordinal_scale import OrdinalScale
from dataviz.core.scale import LinearScale, _format_tick, _label_decimals
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Orientation,
    _Scaled,
    _tooltip_label,
    _TextRequest,
    _axis_pixel_f,
    _draw_categorical_axis_frame,
    _draw_continuous_axis_frame,
    _LegendLayout,
    _data_extent,
    _pull_off_axis_line_f,
    _finished,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz.categorical.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.core.theme import Theme
from std.collections import Dict
from dataviz.core.mark import Mark, _require_mark
from dataviz.binned.histogram import BinRule, _bin_histogram


def _bar_fill_color(theme: Theme, value: Float64) -> Color:
    """The fill color `_draw_bar_rects` picks per bar:
    `Theme.mark_color_negative` when `Theme.color_by_sign` is on and the
    value is negative, `Theme.mark_color` otherwise.
    """
    return theme.mark_color_negative if (
        theme.color_by_sign and value < 0.0
    ) else theme.mark_color


def _bar_y_domain_data(plot: Plot) -> List[Float64]:
    """`plot._continuous.y`, or every error-bar whisker endpoint when `y_err`
    (or `y_err_lower`/`y_err_upper`) is set, so the y-domain spans
    everything `_draw_bar_rects` actually draws -- the same
    `y_domain_data` pattern `_render_generic` uses for `POINT`/`LINE`/
    `EFFECT_SCATTER`.
    """
    var domain_data = List[Float64]()
    if len(plot._y_err.symmetric) > 0:
        for i in range(len(plot._continuous.y)):
            domain_data.append(plot._continuous.y[i] - plot._y_err.symmetric[i])
            domain_data.append(plot._continuous.y[i] + plot._y_err.symmetric[i])
    elif len(plot._y_err.lower) > 0:
        for i in range(len(plot._continuous.y)):
            domain_data.append(plot._continuous.y[i] - plot._y_err.lower[i])
            domain_data.append(plot._continuous.y[i] + plot._y_err.upper[i])
    else:
        for v in plot._continuous.y:
            domain_data.append(v)
    return domain_data^


def _draw_bar_rects_at_positions[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_starts: List[Float64],
    band_widths: List[Float64],
    band_centers: List[Float64],
    value_scale: LinearScale,
    baseline_edge: Int,
    orient: _Orientation,
    mut text_requests: List[_TextRequest],
) raises:
    """Draw bar values at pixel positions supplied by either x-axis.

    This keeps colors, error bars, tooltips, and data labels identical
    for categorical bands and timestamp intervals.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var baseline = _axis_pixel_f(value_scale, 0.0)
    var has_y_err = len(plot._y_err.symmetric) > 0 or len(plot._y_err.lower) > 0
    var cap_half = sc.error_bar_cap_width
    var tooltips_on = plot._tooltips_on(len(plot._categorical.x))
    for i in range(len(plot._categorical.x)):
        var band_pos = band_starts[i]
        var band_size = band_widths[i]
        var value = plot._continuous.y[i]
        var extent = _pull_off_axis_line_f(
            baseline, _axis_pixel_f(value_scale, value), Float64(baseline_edge)
        )
        var color = _bar_fill_color(theme, value)
        if tooltips_on:
            target.begin_annotated_group(
                _tooltip_label(plot._categorical.x[i], value)
            )
        if has_y_err:
            var lo: Float64
            var hi: Float64
            if len(plot._y_err.symmetric) > 0:
                var err = plot._y_err.symmetric[i]
                lo = value - err
                hi = value + err
            else:
                lo = value - plot._y_err.lower[i]
                hi = value + plot._y_err.upper[i]
            var center_i = band_centers[i]
            var py_hi = _axis_pixel_f(value_scale, hi)
            var py_lo = _axis_pixel_f(value_scale, lo)
            orient.value_line(target, py_hi, py_lo, center_i, color, sc.scale)
            orient.band_line(
                target,
                py_hi,
                center_i - cap_half,
                center_i + cap_half,
                color,
                sc.scale,
            )
            orient.band_line(
                target,
                py_lo,
                center_i - cap_half,
                center_i + cap_half,
                color,
                sc.scale,
            )
        orient.fill_band_rect(target, extent, band_pos, band_size, color)
        if tooltips_on:
            target.end_annotated_group()
        if theme.show_data_labels:
            var at = orient.outside_band_label(
                extent,
                band_pos,
                band_size,
                value < 0.0,
                sc.label_gap,
                sc.font_size,
            )
            text_requests.append(
                _TextRequest(
                    at.x,
                    at.y,
                    _format_tick(
                        value,
                        _label_decimals(value),
                        theme.x_tick_format if orient.horizontal else theme.y_tick_format,
                    ),
                    theme.text_color,
                    sc.font_size,
                    at.align,
                    theme.font_family,
                )
            )


def _draw_bar_rects[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    baseline_edge: Int,
    orient: _Orientation,
    mut text_requests: List[_TextRequest],
    group_index: Int = 0,
    group_count: Int = 1,
) raises:
    """Draw categorical bars with the same glyph path as time bars."""
    var starts = List[Float64](capacity=len(plot._categorical.x))
    var widths = List[Float64](capacity=len(plot._categorical.x))
    var centers = List[Float64](capacity=len(plot._categorical.x))
    var width = band_scale.bandwidth() / Float64(group_count)
    for i in range(len(plot._categorical.x)):
        var start = band_scale.band_start(i) + Float64(group_index) * width
        starts.append(start)
        widths.append(width)
        centers.append(start + width / 2.0)
    _draw_bar_rects_at_positions(
        target,
        plot,
        starts,
        widths,
        centers,
        value_scale,
        baseline_edge,
        orient,
        text_requests,
    )


def _time_bar_interval(seconds: List[Float64]) raises -> Float64:
    """Shortest observed interval, so time bars cannot overlap."""
    if len(seconds) == 1:
        return 86400.0
    var sorted = seconds.copy()
    sort(sorted)
    var shortest = sorted[1] - sorted[0]
    if shortest <= 0.0:
        raise Error("Plot.encode_time_bars(): timestamps must be distinct")
    for i in range(2, len(sorted)):
        var gap = sorted[i] - sorted[i - 1]
        if gap <= 0.0:
            raise Error("Plot.encode_time_bars(): timestamps must be distinct")
        shortest = min(shortest, gap)
    return shortest


def _render_time_bar[
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
    """Vertical bars on a dated linear x-axis with one interval per bar."""
    _validate_categorical_encoding(plot)
    if len(plot._continuous.x) != len(plot._continuous.y):
        raise Error(
            "Plot.encode_time_bars(): dates and values must have the same"
            " length (got "
            + String(len(plot._continuous.x))
            + " and "
            + String(len(plot._continuous.y))
            + ")"
        )
    var interval = _time_bar_interval(plot._continuous.x)
    var earliest = plot._continuous.x[0]
    var latest = earliest
    for seconds in plot._continuous.x:
        earliest = min(earliest, seconds)
        latest = max(latest, seconds)
    var bounds: List[Float64] = [
        earliest - interval / 2.0,
        latest + interval / 2.0,
    ]
    var x_scale = _data_extent(bounds)
    x_scale.is_time = True
    x_scale.tz_offset = plot._x_tz_offset
    var y_scale = _zero_baseline_y_extent(_bar_y_domain_data(plot))
    var frame = _draw_continuous_axis_frame(
        target,
        x_scale,
        y_scale,
        plot._theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    var starts = List[Float64](capacity=len(plot._continuous.x))
    var widths = List[Float64](capacity=len(plot._continuous.x))
    var centers = List[Float64](capacity=len(plot._continuous.x))
    for seconds in plot._continuous.x:
        var left = _axis_pixel_f(frame.x_scale, seconds - interval / 2.0)
        var right = _axis_pixel_f(frame.x_scale, seconds + interval / 2.0)
        starts.append(left)
        widths.append(right - left)
        centers.append(_axis_pixel_f(frame.x_scale, seconds))
    _draw_bar_rects_at_positions(
        target,
        plot,
        starts,
        widths,
        centers,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        frame.text_requests,
    )
    return frame.result()


def _render_bar[
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
    """Render a `Mark.BAR` plot on categorical bands or real timestamps.

    `_x_time` dispatches to `_render_time_bar`. The categorical path uses
    an `OrdinalScale` with one evenly spaced band per category and a
    continuous y-axis whose domain
    always includes a zero baseline (`_zero_baseline_y_extent`, not the
    continuous marks' `_data_extent`). Generic over `T: DrawTarget`,
    returning axis/tick labels as `_TextRequest`s rather than drawing
    them (see `_render_generic`).

    `ox0`/`oy0`/`ox1`/`oy1` are `render()`'s already-resolved outer
    bounds (never the -1 sentinel); this function lays out relative to
    that rectangle, whether the whole target or one facet cell.

    The axis frame is `_draw_categorical_axis_frame`'s job, shared with
    `Mark.LOLLIPOP`/`WATERFALL`/`BOX`; the rects are `_draw_bar_rects`,
    shared with `render_layers()`'s bar-combo path.
    `Theme.show_data_labels` draws each bar's value above it (below it
    for a negative value). No x-gridlines: the bars already separate
    categories.
    """
    if plot._x_time:
        return _render_time_bar(target, plot, ox0, oy0, ox1, oy1, cache=cache)
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    # y-domain computed before the frame's dynamic left margin is
    # finalized; see _draw_categorical_axis_frame for why it takes y_scale
    # as an input.
    var y_scale = _zero_baseline_y_extent(_bar_y_domain_data(plot))
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

    _draw_bar_rects(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        frame.text_requests,
    )

    # `frame.result()` copies `text_requests` rather than moving it: Mojo
    # rejects moving a single field out of `frame` ("field destroyed out of
    # the middle of a value").
    return frame.result()


def _render_horizontal_bar[
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
    """`_render_bar`'s mirror image for `Plot.mark_bar(horizontal=True)`
    : a categorical y-axis (`OrdinalScale`, top to bottom) and a
        continuous x-axis whose domain includes a zero baseline
        (`_zero_baseline_y_extent`, axis-agnostic despite the name).

        A separate function rather than an orientation flag on `_render_bar`,
        for the same reason `_draw_horizontal_categorical_axis_frame`
        (gantt.mojo) stays separate from `_draw_categorical_axis_frame`: a
        bidirectional frame would need a branch on nearly every line (which
        scale is which type, which axis reverses, which margin grows). The
        rect drawing itself is shared through `_draw_bar_rects` and
        `_Orientation(True)`. No y-gridlines, mirroring `_render_bar`'s no
        x-gridlines.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var x_scale = _zero_baseline_y_extent(_bar_y_domain_data(plot))
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
        x_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_bar_rects(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        frame.px0,
        _Orientation(True),
        frame.text_requests,
    )

    return frame.result()


def bar(
    df: DataFrame,
    x: String,
    y: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`bar()` over named columns of a `dataframe_mojo` `DataFrame`
    (#364): a string `x` column is categorical, while a date or datetime
    `x` column uses a real time axis. The numeric `y` column gives bar
    heights, and axis titles default to both column names.

    Args:
        df: The frame to read.
        x: A string category or date/datetime time column.
        y: The numeric column giving each bar's height.
        theme: Full styling knobs beyond this function's own parameters.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A line under the title.
        x_title: The x-axis caption; defaults to `x`.
        y_title: The y-axis caption; defaults to `y`.
        horizontal: Draw the bars left-to-right instead of upward.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for its
            channel, or has missing values.
    """
    var x_dtype = _frame_column(df, x, "bar()").dtype()
    if x_dtype.is_date() or x_dtype.is_datetime():
        return bar(
            _frame_morrow(df, x, "bar()"),
            _frame_floats(df, y, "bar()", theme.missing),
            theme=theme,
            width=width,
            height=height,
            title=title,
            subtitle=subtitle,
            x_title=x_title if x_title.byte_length() > 0 else x,
            y_title=y_title if y_title.byte_length() > 0 else y,
            horizontal=horizontal,
        )
    # The theme goes on first: `encode_frame` reads `Theme.missing` and
    # `Theme.missing_category_label` as it reads the columns (#367).
    var plot = (
        Plot()
        .mark_bar(horizontal=horizontal)
        .theme(theme)
        .encode_frame(df, x=x, y=y)
    )
    return _finished(
        plot^,
        theme,
        width,
        height,
        title,
        x_title if x_title.byte_length() > 0 else x,
        y_title if y_title.byte_length() > 0 else y,
        subtitle=subtitle,
    )


def bar[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """A bar chart, the standard choice for comparing a value across
    discrete categories: one rectangle per category, its length
    proportional to the value, with negative values extending below the
    zero baseline.

    `Mark.BAR` over a categorical `x` and continuous `y` (see
    `Plot.encode_categorical()`); one bar per entry, with negative values
    extending below the zero baseline.

    Args:
        categories: One bar per entry, in the given order.
        values: Each bar's height; negative values extend below the
            zero baseline automatically.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.
        horizontal: Draw categories running top-to-bottom with each
            bar extending left-to-right instead of the default
            vertical layout -- see `Plot.mark_bar()`'s own docstring.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import bar
        from dataviz import save
        from dataviz.core.colors import SEAGREEN
        from dataviz import Theme

        def main() raises:
            var categories: List[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            var values: List[Int] = [118, 146, 131, 159, 172, 94, 76]

            var c = bar(
                categories,
                values,
                title="Orders Shipped by Day",
                x_title="Day",
                y_title="Orders shipped",
                theme=Theme(mark_color=SEAGREEN),
            )
            save(c, "docs/src/examples/out_bar.svg")
        ```

    Example (Diverging bars (color_by_sign)):
        ```mojo
        from dataviz import bar
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            var months: List[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
            var net_change: List[Float64] = [15.0, -8.0, 22.0, -3.0, 10.0, -12.0]

            var c_diverging = bar(
                months,
                net_change,
                title="Monthly Budget Variance",
                x_title="Month",
                y_title="Variance ($k)",
                theme=Theme(color_by_sign=True),
            )
            save(c_diverging, "docs/src/examples/out_bar_diverging.svg")
        ```
    """
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_bar(horizontal=horizontal)
        .encode_categorical(x=categories, y=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def bar[
    dtype: DType
](
    dates: List[Morrow],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """Vertical bars one observed interval wide on a real time axis.

    A bar is centered on each timestamp. Its width is the shortest gap
    between dates, so missing days leave blank space and bars never
    overlap. A single date receives a one-day width. Dates must be
    distinct; `horizontal=True` is not supported on a time x-axis.

    Args:
        dates: One timestamp per bar.
        values: Bar heights.
        theme: Chart styling.
        width: Chart width in pixels.
        height: Chart height in pixels.
        title: Chart title.
        subtitle: Chart subtitle.
        x_title: Time-axis title.
        y_title: Value-axis title.
        horizontal: Must be false for time bars.

    Returns:
        The unrendered plot.
    """
    var plot = (
        Plot()
        .mark_bar(horizontal=horizontal)
        .encode_time_bars(dates, _materialize_scalar_list(values))
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def _encode_categorical(
    mut plot: Plot,
    x: List[String],
    y: List[Float64],
    y_err: List[Float64],
    y_err_lower: List[Float64],
    y_err_upper: List[Float64],
) raises:
    """`Plot.encode_categorical()`'s body, which forwards here with
    every argument; see that method for the contract."""
    var _ok_encode_categorical = List[Mark]()
    _ok_encode_categorical.append(Mark.BAR)
    _ok_encode_categorical.append(Mark.LOLLIPOP)
    _ok_encode_categorical.append(Mark.POINTPLOT)
    _ok_encode_categorical.append(Mark.ARC)
    _ok_encode_categorical.append(Mark.FUNNEL)
    _ok_encode_categorical.append(Mark.NIGHTINGALE)
    _ok_encode_categorical.append(Mark.POLAR_BAR)
    _ok_encode_categorical.append(Mark.RADIALBAR)
    _require_mark(
        plot._mark,
        "encode_categorical",
        "mark_bar()",
        _ok_encode_categorical^,
    )
    var first_position = Dict[String, Int]()
    for i in range(len(x)):
        var category = x[i]
        if category in first_position:
            raise Error(
                'Plot.encode_categorical(): duplicate category "'
                + category
                + '" at positions '
                + String(first_position[category])
                + " and "
                + String(i)
            )
        first_position[category] = i
    plot._categorical.x = x.copy()
    plot._continuous.x = List[Float64]()
    plot._continuous.y = y.copy()
    plot._y_err.symmetric = y_err.copy()
    plot._y_err.lower = y_err_lower.copy()
    plot._y_err.upper = y_err_upper.copy()
    plot._x_time = False


def _encode_time_bars(
    mut plot: Plot,
    dates: List[Morrow],
    values: List[Float64],
    y_err: List[Float64],
    y_err_lower: List[Float64],
    y_err_upper: List[Float64],
) raises:
    """`Plot.encode_time_bars()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(plot._mark, "encode_time_bars", "mark_bar()", Mark.BAR)
    if plot._horizontal:
        raise Error(
            "Plot.encode_time_bars(): horizontal bars cannot use a time x-axis"
        )
    var seconds = List[Float64](capacity=len(dates))
    var labels = List[String](capacity=len(dates))
    for date in dates:
        seconds.append(date.timestamp())
        labels.append(date.format("YYYY-MM-DD HH:mm:ss"))
    plot._categorical.x = labels^
    plot._continuous.x = seconds^
    plot._continuous.y = values.copy()
    plot._y_err.symmetric = y_err.copy()
    plot._y_err.lower = y_err_lower.copy()
    plot._y_err.upper = y_err_upper.copy()
    plot._x_time = True
    if len(dates) > 0:
        plot._x_tz_offset = dates[0].tz.offset


def _encode_binned_categories(
    mut plot: Plot,
    data: List[Float64],
    bins: Int,
) raises:
    """`Plot.encode_binned_categories()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark, "encode_binned_categories", "mark_bar()", Mark.BAR
    )
    var binned = _bin_histogram(data, bins)
    plot._categorical.x = binned.labels.copy()
    plot._continuous.x = List[Float64]()
    plot._continuous.y = binned.counts.copy()


def _encode_binned_categories(
    mut plot: Plot,
    data: List[Float64],
    rule: BinRule,
) raises:
    """`Plot.encode_binned_categories()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark, "encode_binned_categories", "mark_bar()", Mark.BAR
    )
    var binned = _bin_histogram(data, rule)
    plot._categorical.x = binned.labels.copy()
    plot._continuous.x = List[Float64]()
    plot._continuous.y = binned.counts.copy()
