from canvas.color import Color
from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _Orientation,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _pull_off_axis_line,
    _finished,
    _require_non_empty,
    _zero_baseline_y_extent,
)
from dataviz.scale import _format_tick, _label_decimals
from dataviz.theme import Theme


struct _WaterfallData(Copyable, Movable):
    """The running-total bounds `encode_waterfall()` computes from each
    category's signed delta (`y_data`), for `Mark.WATERFALL`. See that
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
    """Compute each bar's `y0`/`y1` bounds from a running cumulative sum over
    `deltas`, starting at 0.0. Extracted from `Plot.encode_waterfall()`
    (plot.mojo) so the running-sum math sits next to `_render_waterfall`.

    `is_total[i]` (treated as `False` when `i` is past `is_total`'s
    length; the length check itself happens at `render()` time) changes
    only how row `i` draws: a plain delta row runs from the running total
    before its delta (`y0`) to the total after it (`y1`); a
    total/checkpoint row runs from `0` to the running total after its
    delta. `deltas[i]` is always added to the running sum either way.
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
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """Render a `Mark.WATERFALL` plot on `_draw_categorical_axis_frame`,
    with a y-domain spanning every bar's running-total bounds
    (`_waterfall`'s `y0`/`y1`, not the deltas) and forced to include
    zero.

    Each category draws a floating rect from `y0` to `y1`. A delta row is
    colored by its delta's sign unconditionally
    (`theme.mark_color_negative`/`mark_color`); a total row is
    `theme.waterfall_total_color` at full band width. Delta rows draw
    narrower (`plot._mark_style.waterfall_delta_width_fraction`) only
    when `is_total` is in use.

    Connector lines (`theme.axis_color`) run horizontally between
    consecutive bars at `y1[i-1]`, from one bar's actual right edge to
    the next's left edge. For consecutive delta rows that touches both
    bars exactly (`y1[i-1] == y0[i]`). A total row's `y0` is `0`, so the
    connector meets its top edge only when its own delta is `0`, the
    usual ending-balance case.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_waterfall(): categories and deltas must have the"
            " same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )
    if len(plot._waterfall.is_total) > 0 and len(
        plot._waterfall.is_total
    ) != len(plot.x_categories):
        raise Error(
            "Plot.encode_waterfall(): is_total, if given, must have the"
            " same length as categories (got "
            + String(len(plot._waterfall.is_total))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )

    var theme = plot._theme
    _require_non_empty(len(plot.x_categories), "Plot.encode_waterfall()")
    var combined = List[Float64]()
    for v in plot._waterfall.y0:
        combined.append(v)
    for v in plot._waterfall.y1:
        combined.append(v)
    var y_scale = _zero_baseline_y_extent(combined)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1
    )

    # Delta bars only narrow when is_total is in use; otherwise every bar
    # stays full band width.
    var using_totals = len(plot._waterfall.is_total) > 0
    var sc = _Scaled(theme)
    var orient = _Orientation(False)  # Mark.WATERFALL has no horizontal variant

    # Only recorded when is_total is in use: that's the only case the
    # connector pass reads them back (a delta bar can be narrower than its
    # band then). Otherwise the connector derives the edge from the band
    # directly.
    var bar_x_list = List[Int]()
    var bar_width_list = List[Int]()
    var bandwidth = frame.x_scale.bandwidth()
    for i in range(len(plot.x_categories)):
        var band_start = frame.x_scale.band_start(i)
        var row_is_total = (
            plot._waterfall.is_total[i] if i
            < len(plot._waterfall.is_total) else False
        )
        var bar_x: Int
        var bar_width: Int
        if row_is_total or not using_totals:
            bar_x = _round_to_int(band_start)
            bar_width = _round_to_int(bandwidth)
        else:
            var narrow_width = (
                bandwidth * plot._mark_style.waterfall_delta_width_fraction
            )
            var inset = (bandwidth - narrow_width) / 2.0
            bar_x = _round_to_int(band_start + inset)
            bar_width = _round_to_int(band_start + inset + narrow_width) - bar_x
        if using_totals:
            bar_x_list.append(bar_x)
            bar_width_list.append(bar_width)

        var y0_py = _axis_pixel(frame.y_scale, plot._waterfall.y0[i])
        var y1_py = _axis_pixel(frame.y_scale, plot._waterfall.y1[i])
        var rect = _pull_off_axis_line(y0_py, y1_py, frame.py1)
        var bar_color = theme.waterfall_total_color if row_is_total else (
            theme.mark_color_negative if plot.y_data[i]
            < 0.0 else theme.mark_color
        )
        target.fill_rect(bar_x, rect.y, bar_width, rect.height, bar_color)
        if theme.show_data_labels:
            var delta = plot.y_data[i]
            var at = orient.outside_band_label(
                rect, bar_x, bar_width, delta < 0.0, sc.label_gap, sc.font_size
            )
            frame.text_requests.append(
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
            var prev_end_py = _axis_pixel(
                frame.y_scale, plot._waterfall.y1[i - 1]
            )
            # With no totals, the edge comes from the band geometry (band_start +
            # bandwidth, summed then rounded once) since every bar is full band
            # width. With totals, ask the previous bar what it actually drew, since
            # a delta bar can be narrower than its band.
            var prev_x1 = bar_x_list[i - 1] + bar_width_list[
                i - 1
            ] if using_totals else _round_to_int(
                frame.x_scale.band_start(i - 1) + frame.x_scale.bandwidth()
            )
            target.draw_line_aa(
                prev_x1,
                prev_end_py,
                bar_x,
                prev_end_py,
                theme.axis_color,
                width=theme.scale,
            )

    return frame.result()


def waterfall(
    categories: List[String],
    deltas: List[Float64],
    is_total: List[Bool] = List[Bool](),
    delta_width_fraction: Float64 = 0.6,
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
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var stages: List[String] = ["Starting", "Revenue", "COGS", "Opex", "Tax", "One-off", "Ending"]
            var deltas: List[Int] = [50, 32, -18, -12, -6, 4, 0]
            var is_total: List[Bool] = [True, False, False, False, False, False, True]

            var c = waterfall(stages, deltas, is_total=is_total)
            save(c, "docs/src/examples/out_waterfall.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_waterfall(delta_width_fraction=delta_width_fraction)
        .encode_waterfall(
            categories=categories, deltas=deltas, is_total=is_total
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def waterfall[
    dtype: DType
](
    categories: List[String],
    deltas: List[Scalar[dtype]],
    is_total: List[Bool] = List[Bool](),
    delta_width_fraction: Float64 = 0.6,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`waterfall()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return waterfall(
        categories,
        _materialize_scalar_list(deltas),
        is_total=is_total,
        delta_width_fraction=delta_width_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
