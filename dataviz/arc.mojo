from std.math import pi

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
    _validate_categorical_encoding,
    _require_non_negative,
)
from dataviz.theme import Theme


def _render_arc[
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
    """Render pie or donut wedges clockwise from 12 o'clock.

    Wedge angles are proportional to non-negative values, colors follow the
    categorical palette, and a positive inner-radius fraction selects donut
    sectors. Values must have a positive total.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    _require_non_negative(plot.y_data, "Mark.ARC")
    var total = 0.0
    for v in plot.y_data:
        total += v
    if total <= 0.0:
        raise Error(
            "Plot: Mark.ARC requires at least one positive value"
            " (all values summed to "
            + String(total)
            + ")"
        )
    if (
        plot._mark_style.donut_inner_radius_fraction < 0.0
        or plot._mark_style.donut_inner_radius_fraction >= 1.0
    ):
        raise Error(
            "mark_arc(inner_radius_fraction=...) must be in [0.0, 1.0) (got "
            + String(plot._mark_style.donut_inner_radius_fraction)
            + ")"
        )

    # Scale pixel-sized theme values once.
    var sc = _Scaled(theme)

    var show_legend = theme.show_legend
    var legend = _legend_layout(
        plot.x_categories,
        sc.legend_swatch_size,
        sc,
        theme,
        ox1 - ox0,
        cache=cache,
    ) if show_legend else _LegendLayout()

    var plot_x0 = ox0 + sc.margin_left + legend.left
    var plot_y0 = oy0 + sc.margin_top + legend.top
    var plot_x1 = ox1 - sc.margin_right - legend.right
    var plot_y1 = oy1 - sc.margin_bottom - legend.bottom
    var cx = Float64(plot_x0 + plot_x1) / 2.0
    var cy = Float64(plot_y0 + plot_y1) / 2.0
    var radius = Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    var is_donut = plot._mark_style.donut_inner_radius_fraction > 0.0
    var inner_radius = radius * plot._mark_style.donut_inner_radius_fraction

    var palette = default_categorical_palette()
    var start = -pi / 2.0
    for i in range(len(plot.x_categories)):
        var span = (plot.y_data[i] / total) * 2.0 * pi
        var end = start + span
        var color = palette[i % len(palette)]
        if is_donut:
            target.fill_ring_sector_aa(
                cx, cy, inner_radius, radius, start, end, color
            )
        else:
            target.fill_arc_aa(cx, cy, radius, start, end, color)
        start = end

    if show_legend:
        _draw_legend_at(
            target,
            text_requests,
            plot.x_categories,
            palette,
            legend,
            plot_x0,
            plot_y0,
            plot_x1,
            plot_y1,
            theme,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def pie(
    categories: List[String],
    values: List[Float64],
    inner_radius_fraction: Float64 = 0.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A pie chart, showing each category's share of a whole as a wedge's
    angle. Best for a small number of categories (roughly two to six)
    that sum to a meaningful total; more than that becomes hard to
    compare by angle alone, where a bar chart usually reads faster.

    `Mark.ARC` over a categorical `x` and continuous `y` (the same shape
    `bar()` takes; values must be non-negative, with at least one
    positive). Pass `inner_radius_fraction=0.55` (any value in
    `[0.0, 1.0)`) for a donut; see `Plot.mark_arc()`.

    Args:
        categories: One wedge per entry, in the given order.
        values: Each category's share; every value must be
            non-negative, and at least one positive.
        inner_radius_fraction: Hole radius as a fraction of the pie radius -- above
            `0.0` makes a donut; defaults to `0.0`.
        theme: Full styling knobs beyond this function's own
            parameters -- see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: Unused -- a pie chart has no x-axis to label.
        y_title: Unused -- a pie chart has no y-axis to label.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import pie
        from dataviz import save

        def main() raises:
            # Illustrative share of 10,000 support requests by intake channel.
            var channels: List[String] = [
                "Email", "Live chat", "Phone", "Web form", "Other",
            ]
            var tickets: List[Int] = [4200, 2800, 1700, 900, 400]

            var c = pie(
                channels,
                tickets,
                title="Illustrative Support Mix",
                width=400,
                height=300,
            )
            save(c, "docs/src/examples/out_pie.svg")
        ```

    Example (Donut (donut_inner_radius_fraction)):
        ```mojo
        from dataviz import pie
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # The same illustrative support mix as the pie example.
            var channels: List[String] = [
                "Email", "Live chat", "Phone", "Web form", "Other",
            ]
            var tickets: List[Int] = [4200, 2800, 1700, 900, 400]

            var c_donut = pie(
                channels,
                tickets,
                title="Illustrative Support Mix",
                inner_radius_fraction=0.55,
                width=400,
                height=300,
            )
            save(c_donut, "docs/src/examples/out_pie_donut.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_arc(inner_radius_fraction=inner_radius_fraction)
        .encode_categorical(x=categories, y=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def pie[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    inner_radius_fraction: Float64 = 0.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`pie()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (continuous.mojo). Delegates to the concrete overload
    above.
    """
    return pie(
        categories,
        _materialize_scalar_list(values),
        inner_radius_fraction=inner_radius_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
