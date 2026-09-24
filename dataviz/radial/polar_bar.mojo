from std.math import pi

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.core.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _tooltip_label,
    _Scaled,
    _TextRequest,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
    _validate_categorical_encoding,
    _require_non_negative,
    _require_some_positive,
)
from dataviz.core.scale import _format_tick, _label_decimals
from dataviz.radial.polar import _radial_value_label
from dataviz.core.theme import Theme


def _render_polar_bar[
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
    """Render non-negative values as padded radial bars.

    Categories receive equal angular slots, and radius scales linearly against
    the largest value.
    """
    _validate_categorical_encoding(
        plot._categorical, plot._continuous, plot._y_err, plot._mark
    )

    var theme = plot._theme
    var text_requests = List[_TextRequest]()

    _require_non_negative(plot._continuous.y, "Mark.POLAR_BAR")
    var max_v = _require_some_positive(plot._continuous.y, "Mark.POLAR_BAR")

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
    var max_radius = (
        Float64(min(plot_x1 - plot_x0, plot_y1 - plot_y0)) / 2.0 * 0.9
    )

    var palette = categorical_palette_for(theme)
    var n = len(plot._categorical.x)
    var slot = 2.0 * pi / Float64(n)
    var gap = slot * plot._mark_style.polar_bar_padding
    var slot_start = -pi / 2.0
    var tooltips_on = plot._tooltips_on(n)
    for i in range(n):
        var start = slot_start + gap / 2.0
        var end = slot_start + slot - gap / 2.0
        var radius = max_radius * (plot._continuous.y[i] / max_v)
        var color = palette[i % len(palette)]
        if tooltips_on:
            target.begin_annotated_group(
                _tooltip_label(plot._categorical.x[i], plot._continuous.y[i])
            )
        target.fill_arc_aa(cx, cy, radius, start, end, color)
        if tooltips_on:
            target.end_annotated_group()
        if theme.show_data_labels:
            _radial_value_label(
                cx,
                cy,
                (start + end) / 2.0,
                radius,
                plot._continuous.y[i],
                theme,
                sc,
                text_requests,
            )
        slot_start += slot

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


def polarbar(
    df: DataFrame,
    categories: String,
    values: String,
    padding: Float64 = 0.2,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`polarbar()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values. The axis titles default to the `categories` and `values` column names.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: The string column for this channel.
        values: The numeric column for this channel.
        padding: See the list overload.
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
        "polarbar()",
        theme.missing,
        theme.missing_category_label,
    )
    var values_values = _frame_floats(df, values, "polarbar()", theme.missing)
    return polarbar(
        categories=categories_values,
        values=values_values,
        padding=padding,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else categories,
        y_title=y_title if y_title.byte_length() > 0 else values,
    )


def polarbar[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    padding: Float64 = 0.2,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A circular column chart: `bar()`'s categorical bars bent around a
    circle instead of a straight baseline, trading precise length
    comparison for a compact, radial layout.

    `Mark.POLAR_BAR` over a categorical `x` and continuous `y` (the same
    shape `bar()`/`pie()` take; values must be non-negative, with at least
    one positive). Bars radiate from the center, one equal-width angular
    slot per category, length proportional to `value / max(values)`. See
    `_render_polar_bar` for how this differs from `nightingale()`.

    Args:
        categories: One equal-width angular slot per entry, in the
            given order.
        values: Each bar's length, proportional to `value /
            max(values)`; every value must be non-negative, and at
            least one positive.
        padding: Gap taken out of each bar's angular slot; defaults to
            `0.2`.
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
        from dataviz import polarbar
        from dataviz import save

        def main() raises:
            var direction: List[String] = [
                "N", "NE", "E", "SE", "S", "SW", "W", "NW",
            ]
            # Illustrative share of observations from each direction; sums to 100%.
            var frequency: List[Int] = [18, 12, 9, 7, 11, 14, 16, 13]

            var c = polarbar(
                direction,
                frequency,
                title="Illustrative Wind Direction Frequency (%)",
            )
            save(c, "docs/src/examples/out_polarbar.svg")
        ```
    """
    var values_f = _materialize_scalar_list(values)
    var plot = (
        Plot()
        .mark_polar_bar(padding=padding)
        .encode_categorical(x=categories, y=values_f)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
