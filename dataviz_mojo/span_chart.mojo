from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _rendered,
)
from dataviz_mojo.theme import Theme


def _render_span_chart[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.SPAN_CHART` plot: `Mark.GANTT`'s mirror
    image -- one floating bar per category from `plot._gantt.start[i]`
    (the low end) to `plot._gantt.end[i]` (the high end), but *vertical*
    on the normal `_draw_categorical_axis_frame` (categories along `x`,
    a continuous `y` for the value domain) instead of `Mark.GANTT`'s horizontal frame -- ECharts.jl's `spanchart`, "an invisible
    spacer bar extends from 0 to lows[i], and the visible span bar
    extends from lows[i] to highs[i]," the same "a range with no
    anchor to zero" reading `Mark.CANDLESTICK`'s high-low wick
    gives, generalized to a filled bar instead of a thin line.

    Reuses `encode_gantt()`'s data shape completely unchanged
    (`Plot.mark_span_chart().encode_gantt(categories=..., start=lows,
    end=highs)`) rather than a new `encode_*` method -- identical
    data, purely an orientation/rendering difference. `_gantt`'s `start`/
    `end` don't need `start[i] <= end[i]` -- same as `Mark.GANTT`'s lack of that requirement, this draws from `min`/`max` of the two,
    not literally `start` to `end` in that order.

    Bar width comes from `frame.x_scale.bandwidth()` (the ordinal
    x-axis's per-category band, full width -- `Mark.BAR`'s convention, not narrowed the way `Mark.WATERFALL`'s delta bars
    are), bar height floored to at least 1 pixel (`max(1, ...)`, the
    same "a zero-length span is real, visible data, not nothing to
    show" reasoning `Mark.GANTT`'s docstring gives for its zero-width case).
    """
    if len(plot.x_categories) != len(plot._gantt.start) or len(plot._gantt.end) != len(plot._gantt.start):
        raise Error(
            "Plot.encode_gantt(): categories, start, and end must all have"
            " the same length (got "
            + String(len(plot.x_categories))
            + " categories, "
            + String(len(plot._gantt.start))
            + " start values, "
            + String(len(plot._gantt.end))
            + " end values)"
        )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var domain_data = List[Float64]()
    for v in plot._gantt.start:
        domain_data.append(v)
    for v in plot._gantt.end:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var bandwidth = frame.x_scale.bandwidth()
    for i in range(len(plot.x_categories)):
        var band_start = frame.x_scale.band_start(i)
        var bar_x = _round_to_int(band_start)
        var bar_width = _round_to_int(bandwidth)
        var low_py = _axis_pixel(frame.y_scale, plot._gantt.start[i])
        var high_py = _axis_pixel(frame.y_scale, plot._gantt.end[i])
        var bar_y = min(low_py, high_py)
        var bar_height = max(1, max(low_py, high_py) - min(low_py, high_py))
        target.fill_rect(bar_x, bar_y, bar_width, bar_height, theme.mark_color)

    return frame.result()


def span_chart(
    categories: List[String],
    low: List[Float64],
    high: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A span chart -- `Mark.SPAN_CHART`, one floating vertical bar per
    category from `low[i]` to `high[i]` (`Mark.GANTT`'s mirror
    image; ECharts.jl's `spanchart`, useful for confidence
    intervals, error bounds, or a range like a daily temperature
    high/low that isn't anchored to zero the way `bar()` assumes).

    Args:
        categories: One floating vertical bar per entry, in the
            given order.
        low: Each bar's lower value.
        high: Each bar's upper value.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Canvas`.
        height: Pixel height of the returned `Canvas`.
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The rendered chart -- call `.write_png(path)`/`.write_bmp(path)` (both `canvas_mojo.io`) to save it.
    """
    var plot = Plot().mark_span_chart().encode_gantt(categories=categories, start=low, end=high)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
