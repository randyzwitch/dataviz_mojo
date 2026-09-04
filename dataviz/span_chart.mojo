from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


def _render_span_chart[
    T: DrawTarget
](
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """Render a `Mark.SPAN_CHART` plot: one floating vertical bar per
    category from `plot._gantt.start[i]` to `plot._gantt.end[i]`, on the
    normal `_draw_categorical_axis_frame` (categories along `x`,
    continuous `y`). `Mark.GANTT`'s vertical mirror image, and ECharts.jl's
    `spanchart`.

    Reuses `encode_gantt()`'s data shape unchanged
    (`Plot.mark_span_chart().encode_gantt(categories=..., start=lows,
    end=highs)`). `start[i] <= end[i]` is not required: bars draw from
    `min` to `max` of the two.

    Bar width is the ordinal x-axis's full `bandwidth()`; bar height is
    floored to 1 pixel so a zero-length span stays visible.
    """
    if len(plot.x_categories) != len(plot._gantt.start) or len(
        plot._gantt.end
    ) != len(plot._gantt.start):
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
    _require_non_empty(len(plot.x_categories), "Plot.encode_gantt()")
    var domain_data = List[Float64]()
    for v in plot._gantt.start:
        domain_data.append(v)
    for v in plot._gantt.end:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1
    )

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
) raises -> Plot:
    """A span chart.

    `Mark.SPAN_CHART`: one floating vertical bar per category from
    `low[i]` to `high[i]`, for confidence intervals, error bounds, or a
    range like a daily temperature high/low that isn't anchored to zero
    the way `bar()` is.

    Args:
        categories: One floating vertical bar per entry, in the
            given order.
        low: Each bar's lower value.
        high: Each bar's upper value.
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
        from dataviz import span_chart
        from dataviz.plot import save

        def main() raises:
            var months: List[String] = [
                "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
            ]
            var temp_low: List[Int] = [-3, -2, 3, 10, 15, 19, 21, 20, 15, 8, 2, -1]
            var temp_high: List[Int] = [5, 7, 12, 20, 25, 29, 31, 30, 26, 18, 10, 5]

            var c = span_chart(months, temp_low, temp_high)
            save(c, "docs/src/examples/out_span_chart.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_span_chart()
        .encode_gantt(categories=categories, start=low, end=high)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def span_chart[
    dtype: DType
](
    categories: List[String],
    low: List[Scalar[dtype]],
    high: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`span_chart()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (plot.mojo). `low`/`high` share one
    dtype. Delegates to the concrete overload above.
    """
    return span_chart(
        categories,
        _materialize_scalar_list(low),
        _materialize_scalar_list(high),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
