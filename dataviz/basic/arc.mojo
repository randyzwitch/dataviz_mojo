from std.math import cos, pi, sin

from canvas.geometry import round_to_int
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.mark import Mark
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.tooltip_labels import _tooltip_label
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.legend import _LegendLayout, _draw_legend_at, _legend_layout
from dataviz.core.validate import (
    _validate_categorical_encoding,
    _require_non_negative,
)
from dataviz.core.scale import _format_fixed, _label_decimals
from dataviz.core.theme import Theme


def _arc_share_label(
    cx: Float64,
    cy: Float64,
    angle: Float64,
    radius: Float64,
    share: Float64,
    theme: Theme,
    sc: _Scaled,
    mut text_requests: List[_TextRequest],
):
    """One wedge's share of the whole, as a percentage, at the angle
    that bisects it and halfway from the center to the outer edge
    (#684). Inside, not beyond the edge like the radial marks'
    `_radial_value_label`: a full circle's wedges are edge-to-edge with
    no gap to place a label in, unlike a partial ring.
    """
    var x = cx + radius * cos(angle)
    var y = cy + radius * sin(angle)
    text_requests.append(
        _TextRequest(
            round_to_int(x),
            round_to_int(y + sc.font_size * 0.35),
            _format_fixed(share, _label_decimals(share)) + "%",
            # A wedge is filled from the categorical palette, so the
            # label needs to read against any of them -- the same
            # reason SUNBURST's separator line uses theme.background.
            theme.background,
            sc.font_size,
            TextAlign.CENTER,
            theme.font_family,
        )
    )


def _arc_total(plot: Plot) raises -> Float64:
    """Validate an arc layer and return its positive total."""
    _validate_categorical_encoding(
        plot._categorical, plot._continuous, plot._y_err, plot._mark
    )

    _require_non_negative(plot._continuous.y, "Mark.ARC")
    var total = 0.0
    for v in plot._continuous.y:
        total += v
    if total <= 0.0:
        raise Error(
            "Plot: Mark.ARC requires at least one positive value"
            " (all values summed to "
            + String(total)
            + ")"
        )
    return total


def _draw_arc_wedges[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    cx: Float64,
    cy: Float64,
    inner_radius: Float64,
    radius: Float64,
    total: Float64,
    mut text_requests: List[_TextRequest],
) raises:
    """The same wedge geometry for standalone arcs and concentric layers."""
    var theme = plot._settings.theme
    var sc = _Scaled(theme)
    var palette = categorical_palette_for(theme)
    var start = -pi / 2.0
    var tooltips_on = plot._settings.tooltips_on(len(plot._categorical.x))
    for i in range(len(plot._categorical.x)):
        var span = (plot._continuous.y[i] / total) * 2.0 * pi
        var end = start + span
        var color = palette[i % len(palette)]
        if tooltips_on:
            target.begin_annotated_group(
                _tooltip_label(plot._categorical.x[i], plot._continuous.y[i])
            )
        if inner_radius > 0.0:
            target.fill_ring_sector_aa(
                cx, cy, inner_radius, radius, start, end, color
            )
        else:
            target.fill_arc_aa(cx, cy, radius, start, end, color)
        if tooltips_on:
            target.end_annotated_group()
        if theme.show_data_labels:
            _arc_share_label(
                cx,
                cy,
                (start + end) / 2.0,
                (inner_radius + radius) / 2.0,
                (plot._continuous.y[i] / total) * 100.0,
                theme,
                sc,
                text_requests,
            )
        start = end


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
    var total = _arc_total(plot)
    var theme = plot._settings.theme
    var text_requests = List[_TextRequest]()
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
        plot._categorical.x,
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
    var inner_radius = radius * plot._mark_style.donut_inner_radius_fraction
    _draw_arc_wedges(
        target, plot, cx, cy, inner_radius, radius, total, text_requests
    )
    var palette = categorical_palette_for(theme)

    if show_legend:
        _draw_legend_at(
            target,
            text_requests,
            plot._categorical.x,
            palette,
            legend,
            plot_x0,
            plot_y0,
            plot_x1,
            plot_y1,
            theme,
            cache=cache,
        )

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def pie(
    df: DataFrame,
    categories: String,
    values: String,
    inner_radius_fraction: Float64 = 0.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`pie()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: The string column for this channel.
        values: The numeric column for this channel.
        inner_radius_fraction: See the list overload.
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
        df, categories, "pie()", theme.missing, theme.missing_category_label
    )
    var values_values = _frame_floats(df, values, "pie()", theme.missing)
    return pie(
        categories=categories_values,
        values=values_values,
        inner_radius_fraction=inner_radius_fraction,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
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
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_arc(inner_radius_fraction=inner_radius_fraction)
        .encode_categorical(x=categories, y=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
