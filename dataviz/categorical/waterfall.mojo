from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_bools, _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _Orientation,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel_f,
    _draw_categorical_axis_frame,
    _pull_off_axis_line_f,
    snap_to_pixel_center,
    snap_to_pixel_edge,
    _finished,
    _require_non_empty,
    _tooltip_label,
    _zero_baseline_y_extent,
)
from dataviz.categorical.gantt import (
    _draw_horizontal_categorical_axis_frame,
)
from dataviz.core.ordinal_scale import OrdinalScale
from dataviz.core.scale import (
    LinearScale,
    _format_tick,
    _label_decimals,
)
from dataviz.core.theme import Theme
from dataviz.core.mark import Mark, _require_mark


struct _WaterfallData(Copyable, Movable):
    """The running-total bounds `encode_waterfall()` computes from each
    category's signed delta (`_continuous.y`), for `Mark.WATERFALL`. See that
    method. Stored on `Plot._waterfall`.
    """

    var y0: List[Float64]
    var y1: List[Float64]
    var is_total: List[Bool]

    def __init__(out self):
        self.y0 = List[Float64]()
        self.y1 = List[Float64]()
        self.is_total = List[Bool]()


struct _WaterfallBars(Movable):
    """The two running-total bounds `_render_waterfall` draws each bar
    between: `y0[i]`/`y1[i]` are the running total immediately before/
    after category `i`'s delta (or `0`/the new running total for a
    checkpoint row; see `_waterfall_running_totals()`).
    """

    var y0: List[Float64]
    var y1: List[Float64]

    def __init__(out self, var y0: List[Float64], var y1: List[Float64]):
        self.y0 = y0^
        self.y1 = y1^


def _waterfall_running_totals(
    deltas: List[Float64], is_total: List[Bool]
) -> _WaterfallBars:
    """Return each waterfall bar's bounds from cumulative deltas.

    Delta bars begin at the prior total. Checkpoint bars begin at zero, but
    their deltas still update the running total.
    """
    var y0 = List[Float64]()
    var y1 = List[Float64]()
    var running = 0.0
    for i in range(len(deltas)):
        var row_is_total = is_total[i] if i < len(is_total) else False
        var before = running
        running += deltas[i]
        if row_is_total:
            y0.append(0.0)
            y1.append(running)
        else:
            y0.append(before)
            y1.append(running)
    return _WaterfallBars(y0^, y1^)


def _render_waterfall[
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
    """Render cumulative deltas as floating bars joined by connectors.

    Delta color follows sign; checkpoint bars use the total color. The y-domain
    covers all running-total bounds and includes zero.
    """
    _validate_waterfall_encoding(plot)
    var theme = plot._theme
    var combined = List[Float64]()
    for v in plot._waterfall.y0:
        combined.append(v)
    for v in plot._waterfall.y1:
        combined.append(v)
    var y_scale = _zero_baseline_y_extent(combined)

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

    # Delta bars only narrow when is_total is in use; otherwise every bar
    # stays full band width.
    _draw_waterfall_bars(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        Float64(frame.py1),
        _Orientation(False),
        frame.text_requests,
    )
    return frame.result()


def _validate_waterfall_encoding(plot: Plot) raises:
    """The length checks both waterfall renders make before laying
    anything out: categories against deltas, and is_total against
    categories when it is given (#686 split this out so the horizontal
    render makes the same checks rather than a copy of them)."""
    if len(plot._categorical.x) != len(plot._continuous.y):
        raise Error(
            "Plot.encode_waterfall(): categories and deltas must have the"
            " same length (got "
            + String(len(plot._categorical.x))
            + " and "
            + String(len(plot._continuous.y))
            + ")"
        )
    if len(plot._waterfall.is_total) > 0 and len(
        plot._waterfall.is_total
    ) != len(plot._categorical.x):
        raise Error(
            "Plot.encode_waterfall(): is_total, if given, must have the"
            " same length as categories (got "
            + String(len(plot._waterfall.is_total))
            + " and "
            + String(len(plot._categorical.x))
            + ")"
        )
    _require_non_empty(len(plot._categorical.x), "Plot.encode_waterfall()")


def _draw_waterfall_bars[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    value_scale: LinearScale,
    band_scale: OrdinalScale,
    baseline: Float64,
    orient: _Orientation,
    mut text_requests: List[_TextRequest],
) raises:
    """Draw one floating bar per category plus the connectors between
    them, in whichever orientation `orient` names (#686).

    Its own function, as `_draw_lollipop_stems` is, so the vertical and
    horizontal renders share the geometry rather than keeping two copies
    of the delta-width inset, the totals rule and the connector.

    `value_scale` maps a running total to the value axis and
    `band_scale` a category to its band, whichever way round the frame
    puts them; `baseline` is the pixel of the zero line the bars are
    pulled off.

    Args:
        target: Where to draw.
        plot: The chart.
        value_scale: The continuous scale for running totals.
        band_scale: The ordinal scale for categories.
        baseline: The zero line's pixel on the value axis.
        orient: Which way the bands run.
        text_requests: Collects the data labels.

    Raises:
        Error: Whatever the target's draw calls raise.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var using_totals = len(plot._waterfall.is_total) > 0

    # Only recorded when is_total is in use: that's the only case the
    # connector pass reads them back (a delta bar can be narrower than its
    # band then). Otherwise the connector derives the edge from the band
    # directly.
    var bar_x_list = List[Float64]()
    var bar_x1_list = List[Float64]()
    var bandwidth = band_scale.bandwidth()
    var tooltips_on = plot._tooltips_on(len(plot._categorical.x))
    for i in range(len(plot._categorical.x)):
        var band_start = band_scale.band_start(i)
        var row_is_total = (
            plot._waterfall.is_total[i] if i
            < len(plot._waterfall.is_total) else False
        )
        # The bar's two geometric edges. `fill_rect` below snaps each to
        # a whole pixel and takes the width from the pair, rather than
        # rounding a position and a width apart from each other.
        var bar_x: Float64
        var bar_x1: Float64
        if row_is_total or not using_totals:
            bar_x = band_start
            bar_x1 = band_start + bandwidth
        else:
            var narrow_width = (
                bandwidth * plot._mark_style.waterfall_delta_width_fraction
            )
            var inset = (bandwidth - narrow_width) / 2.0
            bar_x = band_start + inset
            bar_x1 = bar_x + narrow_width
        if using_totals:
            bar_x_list.append(bar_x)
            bar_x1_list.append(bar_x1)

        var y0_py = _axis_pixel_f(value_scale, plot._waterfall.y0[i])
        var y1_py = _axis_pixel_f(value_scale, plot._waterfall.y1[i])
        var rect = _pull_off_axis_line_f(y0_py, y1_py, baseline)
        var bar_color = theme.waterfall_total_color if row_is_total else (
            theme.mark_color_negative if plot._continuous.y[i]
            < 0.0 else theme.mark_color
        )
        if tooltips_on:
            # Whichever number this bar's height actually encodes: a delta
            # row is drawn from the running total before it to the total
            # after, so its height is the delta; a checkpoint row is drawn
            # from zero, so its height is the running total itself.
            target.begin_annotated_group(
                _tooltip_label(
                    plot._categorical.x[i],
                    plot._waterfall.y1[
                        i
                    ] if row_is_total else plot._continuous.y[i],
                )
            )
        orient.fill_band_rect(target, rect, bar_x, bar_x1 - bar_x, bar_color)
        if tooltips_on:
            target.end_annotated_group()
        if theme.show_data_labels:
            var delta = plot._continuous.y[i]
            var at = orient.outside_band_label(
                rect,
                bar_x,
                bar_x1 - bar_x,
                delta < 0.0,
                sc.label_gap,
                sc.font_size,
            )
            text_requests.append(
                _TextRequest(
                    at.x,
                    at.y,
                    _format_tick(
                        delta, _label_decimals(delta), theme.y_tick_format
                    ),
                    theme.text_color,
                    sc.font_size,
                    at.align,
                    theme.font_family,
                )
            )

        if i > 0:
            var prev_end_py = snap_to_pixel_center(
                _axis_pixel_f(value_scale, plot._waterfall.y1[i - 1])
            )
            # With no totals, the edge comes from the band geometry (band_start +
            # bandwidth, summed then rounded once) since every bar is full band
            # width. With totals, ask the previous bar what it actually drew, since
            # a delta bar can be narrower than its band.
            var prev_x1 = (
                bar_x1_list[i - 1] if using_totals else band_scale.band_start(
                    i - 1
                )
                + band_scale.bandwidth()
            )
            orient.band_line(
                target,
                prev_end_py,
                prev_x1,
                bar_x,
                theme.axis_color,
                theme.scale,
            )


def _render_horizontal_waterfall[
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
    """`_render_waterfall`'s mirror image for
    `Plot.mark_waterfall(horizontal=True)` (#686): the categorical axis
    runs down the page and the running totals run rightward, on
    `_draw_horizontal_categorical_axis_frame` (gantt.mojo).

    A waterfall is the chart most likely to carry long stage names --
    "returns and refunds", "channel partner discount" -- and those are
    what a vertical categorical axis crowds. Its own function rather
    than a flag inside `_render_waterfall`, for the reason
    `_render_horizontal_bar` gives (bar.mojo): the two frames report
    their scales under different names and types.
    """
    _validate_waterfall_encoding(plot)
    var theme = plot._theme
    var combined = List[Float64]()
    for v in plot._waterfall.y0:
        combined.append(v)
    for v in plot._waterfall.y1:
        combined.append(v)
    var value_scale = _zero_baseline_y_extent(combined)
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
        value_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_waterfall_bars(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        Float64(frame.px0),
        _Orientation(True),
        frame.text_requests,
    )
    return frame.result()


def waterfall(
    df: DataFrame,
    categories: String,
    deltas: String,
    is_total: String = "",
    delta_width_fraction: Float64 = 0.6,
    horizontal: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`waterfall()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: The string column for this channel.
        deltas: The numeric column for this channel.
        is_total: The boolean column for this channel; left empty, the channel is unused.
        delta_width_fraction: See the list overload.
        horizontal: See the list overload.
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
    var categories_values = _frame_strings(
        df,
        categories,
        "waterfall()",
        theme.missing,
        theme.missing_category_label,
    )
    var deltas_values = _frame_floats(df, deltas, "waterfall()", theme.missing)
    var is_total_values = List[Bool]()
    if is_total.byte_length() > 0:
        is_total_values = _frame_bools(
            df, is_total, "waterfall()", theme.missing
        )
    return waterfall(
        categories=categories_values,
        deltas=deltas_values,
        is_total=is_total_values,
        delta_width_fraction=delta_width_fraction,
        horizontal=horizontal,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def waterfall[
    dtype: DType
](
    categories: List[String],
    deltas: List[Scalar[dtype]],
    is_total: List[Bool] = List[Bool](),
    delta_width_fraction: Float64 = 0.6,
    horizontal: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A waterfall chart: floating bars from a running total, each one
    showing how a positive or negative change moves the total from its
    previous value, for visualizing a sequence of additions and
    subtractions such as a profit bridge or an account balance over
    time.

    `Mark.WATERFALL`: floating bars from a running total. See
    `Plot.encode_waterfall()` (plot.mojo) for what `deltas`/`is_total`
    mean.

    Args:
        categories: One floating bar per entry, in the given order.
        deltas: How much the running total changes at each category
            -- not the bar's absolute height; each bar is drawn from
            the running total before it to the running total after
            it, starting the cumulative sum from `0.0`.
        is_total: Marks specific rows as running-total checkpoints
            (drawn full band width in `mark_waterfall(total_color=...)`)
            instead of a plain rising/falling delta. Left empty (the
            default), every row is a plain delta -- unchanged
            original behavior.
        delta_width_fraction: A delta bar's width as a fraction of the band width;
            defaults to `0.6`.
        horizontal: Whether the categories run down the page and the
            running totals rightward; defaults to `False`. The form to
            reach for when the stage names are long, as a bar chart's
            are.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import waterfall
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            var stages: List[String] = ["Starting", "Revenue", "COGS", "Opex", "Tax", "One-off", "Ending"]
            var deltas: List[Int] = [50, 32, -18, -12, -6, 4, 0]
            var is_total: List[Bool] = [True, False, False, False, False, False, True]

            var c = waterfall(
                stages,
                deltas,
                is_total=is_total,
                title="Operating Profit Bridge",
                x_title="Stage",
                y_title="Operating profit ($k)",
            )
            save(c, "docs/src/examples/out_waterfall.svg")
        ```
    """
    var deltas_f = _materialize_scalar_list(deltas)
    var plot = (
        Plot()
        .mark_waterfall(
            delta_width_fraction=delta_width_fraction, horizontal=horizontal
        )
        .encode_waterfall(
            categories=categories, deltas=deltas_f, is_total=is_total
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def _encode_waterfall(
    mut plot: Plot,
    categories: List[String],
    deltas: List[Float64],
    is_total: List[Bool],
) raises:
    """`Plot.encode_waterfall()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark, "encode_waterfall", "mark_waterfall()", Mark.WATERFALL
    )
    plot._categorical.x = categories.copy()
    plot._continuous.x = List[Float64]()
    plot._continuous.y = deltas.copy()
    plot._waterfall.is_total = is_total.copy()
    var bars = _waterfall_running_totals(deltas, is_total)
    plot._waterfall.y0 = bars.y0.copy()
    plot._waterfall.y1 = bars.y1.copy()


def _render_waterfall_oriented[
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
    """`Mark.WATERFALL`'s renderer, the one its setter binds: `_render_horizontal_waterfall`
    when the plot is horizontal, `_render_waterfall` otherwise."""
    if plot._horizontal:
        return _render_horizontal_waterfall(
            target, plot, ox0, oy0, ox1, oy1, cache=cache
        )
    return _render_waterfall(target, plot, ox0, oy0, ox1, oy1, cache=cache)
