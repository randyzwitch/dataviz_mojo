from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _RenderResult,
    _axis_pixel_f,
    _snap_pixel_edge,
    _data_extent,
    _draw_categorical_axis_frame,
    _finished,
    _require_non_empty,
    _span_tooltip_label,
)
from dataviz.core.theme import Theme


def _render_span_chart[
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
    """Render one floating vertical bar per category using Gantt-shaped data.

    Endpoint order does not matter. Bars use the full category bandwidth, and
    zero-length spans remain visible as one-pixel bars.
    """
    if len(plot._categorical.x) != len(plot._gantt.start) or len(
        plot._gantt.end
    ) != len(plot._gantt.start):
        raise Error(
            "Plot.encode_gantt(): categories, start, and end must all have"
            " the same length (got "
            + String(len(plot._categorical.x))
            + " categories, "
            + String(len(plot._gantt.start))
            + " start values, "
            + String(len(plot._gantt.end))
            + " end values)"
        )

    var theme = plot._theme
    _require_non_empty(len(plot._categorical.x), "Plot.encode_gantt()")
    var domain_data = List[Float64]()
    for v in plot._gantt.start:
        domain_data.append(v)
    for v in plot._gantt.end:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

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

    var bandwidth = frame.x_scale.bandwidth()
    for i in range(len(plot._categorical.x)):
        var band_start = frame.x_scale.band_start(i)
        var low_py = _axis_pixel_f(frame.y_scale, plot._gantt.start[i])
        var high_py = _axis_pixel_f(frame.y_scale, plot._gantt.end[i])
        # Snap all edges, then preserve a one-pixel minimum height.
        var bx0 = _snap_pixel_edge(band_start)
        var bx1 = _snap_pixel_edge(band_start + bandwidth)
        var by0 = _snap_pixel_edge(min(low_py, high_py))
        var by1 = _snap_pixel_edge(max(low_py, high_py))
        if by1 - by0 < 1.0:
            by1 = by0 + 1.0
        if theme.svg_tooltips:
            target.begin_annotated_group(
                _span_tooltip_label(
                    plot._categorical.x[i],
                    plot._gantt.start[i],
                    plot._gantt.end[i],
                )
            )
        target.fill_rect(bx0, by0, bx1 - bx0, by1 - by0, theme.mark_color)
        if theme.svg_tooltips:
            target.end_annotated_group()

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
    """A span chart: one floating vertical bar per category from a start
    value to an end value, for visualizing ranges (temperature
    highs/lows, price ranges, durations) rather than a single
    measurement per category.

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
        from dataviz import save

        def main() raises:
            var months: List[String] = [
                "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
            ]
            # Illustrative monthly daily-low and daily-high normals for a
            # continental climate, kept in one unit on the shared axis.
            var temp_low: List[Int] = [-6, -4, 1, 7, 12, 18, 20, 19, 15, 8, 2, -3]
            var temp_high: List[Int] = [0, 2, 9, 15, 21, 27, 29, 28, 24, 17, 9, 2]

            var c = span_chart(
                months,
                temp_low,
                temp_high,
                title="Illustrative Chicago Monthly Temperature Range",
                x_title="Month",
                y_title="Temperature (°C)",
            )
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
    `scatter()`'s `DType` overload (continuous.mojo). `low`/`high` share one
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
