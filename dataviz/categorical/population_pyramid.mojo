from dataviz.core.plot_fields import _CategoricalData
from dataviz.core.chart_settings import _ChartSettings
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats, _frame_strings
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.categorical.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.plot import Plot, _finished
from dataviz.core.frame import _BaselineRectF, _Orientation, _axis_pixel_f
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from canvas.geometry import snap_to_pixel_edge
from dataviz.core.legend import _LegendLayout, _draw_legend_at, _legend_layout
from dataviz.core.validate import _require_non_empty
from dataviz.core.tooltip_labels import _series_tooltip_label
from dataviz.core.scale import LinearScale, _format_tick, _label_decimals
from dataviz.core.theme import Theme
from dataviz.core.mark import Mark, _require_mark


struct _PyramidData(Copyable, Movable):
    """One magnitude per side per category, plus each side's legend name,
    for `Mark.POPULATION_PYRAMID`. See `encode_population_pyramid()`.
    Stored on `Plot._pyramid`.
    """

    var left: List[Float64]
    var right: List[Float64]
    var left_name: String
    var right_name: String

    def __init__(out self):
        self.left = List[Float64]()
        self.right = List[Float64]()
        self.left_name = ""
        self.right_name = ""


def _symmetric_zero_baseline_x_extent(
    left: List[Float64], right: List[Float64]
) raises -> LinearScale:
    """Return a padded, symmetric domain covering both value lists."""
    var max_abs = 0.0
    for v in left:
        max_abs = max(max_abs, max(v, -v))
    for v in right:
        max_abs = max(max_abs, max(v, -v))
    var pad = max_abs * 0.05 if max_abs > 0.0 else 1.0
    var bound = max_abs + pad
    return LinearScale(-bound, bound, 0.0, 1.0)


def _render_population_pyramid[
    T: DrawTarget
](
    mut target: T,
    pyramid: _PyramidData,
    categorical: _CategoricalData,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render paired values as bars mirrored around a centered zero axis.

    Both sides share a symmetric domain. Zero values draw no bar, and the
    optional legend names the two sides.
    """
    if len(categorical.x) != len(pyramid.left) or len(pyramid.right) != len(
        pyramid.left
    ):
        raise Error(
            "Plot.encode_population_pyramid(): categories, left_values, and"
            " right_values must all have the same length (got "
            + String(len(categorical.x))
            + " categories, "
            + String(len(pyramid.left))
            + " left_values, "
            + String(len(pyramid.right))
            + " right_values)"
        )

    var theme = settings.theme
    _require_non_empty(len(categorical.x), "Plot.encode_population_pyramid()")
    var sc = _Scaled(theme)
    # Tooltips need side names even when the legend is hidden.
    var left_name = (
        pyramid.left_name if pyramid.left_name.byte_length() > 0 else "Left"
    )
    var right_name = (
        pyramid.right_name if pyramid.right_name.byte_length() > 0 else "Right"
    )
    var legend_names = List[String]()
    if theme.show_legend:
        legend_names.append(left_name)
        legend_names.append(right_name)
    var legend = _legend_layout(
        legend_names,
        sc.legend_swatch_size,
        sc,
        theme,
        ox1 - ox0,
        cache=cache,
    ) if theme.show_legend else _LegendLayout()

    var x_scale = _symmetric_zero_baseline_x_extent(pyramid.left, pyramid.right)
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        categorical.x,
        x_scale,
        theme,
        ox0 + legend.left,
        oy0 + legend.top,
        ox1 - legend.right,
        oy1 - legend.bottom,
        cache=cache,
    )

    var palette = categorical_palette_for(theme)
    var center_px = _axis_pixel_f(frame.x_scale, 0.0)
    var row_height = frame.y_scale.bandwidth()
    var orient = _Orientation(True)  # bars grow horizontally from center
    var tooltips_on = settings.tooltips_on(2 * len(categorical.x))
    for i in range(len(categorical.x)):
        var row_y = frame.y_scale.band_start(i)

        var left_edge_px = _axis_pixel_f(
            frame.x_scale, -max(pyramid.left[i], -pyramid.left[i])
        )
        var left_x = min(left_edge_px, center_px)
        var left_w = max(left_edge_px, center_px) - min(left_edge_px, center_px)
        if left_w > 0.0:
            if tooltips_on:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        categorical.x[i],
                        left_name,
                        pyramid.left[i],
                    )
                )
            var lx0 = snap_to_pixel_edge(left_x)
            var lx1 = snap_to_pixel_edge(left_x + left_w)
            var ly0 = snap_to_pixel_edge(row_y)
            var ly1 = snap_to_pixel_edge(row_y + row_height)
            target.fill_rect(lx0, ly0, lx1 - lx0, ly1 - ly0, palette[0])
            if tooltips_on:
                target.end_annotated_group()
            if theme.show_data_labels:
                var left_value = pyramid.left[i]
                var at = orient.outside_band_label(
                    _BaselineRectF(left_x, left_w),
                    row_y,
                    row_height,
                    True,
                    sc.label_gap,
                    sc.font_size,
                )
                frame.text_requests.append(
                    _TextRequest(
                        at.x,
                        at.y,
                        _format_tick(
                            left_value,
                            _label_decimals(left_value),
                            theme.x_tick_format,
                        ),
                        theme.text_color,
                        sc.font_size,
                        at.align,
                        theme.font_family,
                    )
                )

        var right_edge_px = _axis_pixel_f(
            frame.x_scale, max(pyramid.right[i], -pyramid.right[i])
        )
        var right_x = min(center_px, right_edge_px)
        var right_w = max(center_px, right_edge_px) - min(
            center_px, right_edge_px
        )
        if right_w > 0.0:
            if tooltips_on:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        categorical.x[i],
                        right_name,
                        pyramid.right[i],
                    )
                )
            var rx0 = snap_to_pixel_edge(right_x)
            var rx1 = snap_to_pixel_edge(right_x + right_w)
            var ry0 = snap_to_pixel_edge(row_y)
            var ry1 = snap_to_pixel_edge(row_y + row_height)
            target.fill_rect(rx0, ry0, rx1 - rx0, ry1 - ry0, palette[1])
            if tooltips_on:
                target.end_annotated_group()
            if theme.show_data_labels:
                var right_value = pyramid.right[i]
                var at2 = orient.outside_band_label(
                    _BaselineRectF(right_x, right_w),
                    row_y,
                    row_height,
                    False,
                    sc.label_gap,
                    sc.font_size,
                )
                frame.text_requests.append(
                    _TextRequest(
                        at2.x,
                        at2.y,
                        _format_tick(
                            right_value,
                            _label_decimals(right_value),
                            theme.x_tick_format,
                        ),
                        theme.text_color,
                        sc.font_size,
                        at2.align,
                        theme.font_family,
                    )
                )

    if theme.show_legend:
        _draw_legend_at(
            target,
            frame.text_requests,
            legend_names,
            palette,
            legend,
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            theme,
            cache=cache,
        )

    return frame.result()


def _render_population_pyramid_plot[
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
    """`_render_population_pyramid` on `plot`'s own columns and settings: the callback
    its `mark_*()` setter binds. This is the one place the mark's
    renderer meets a `Plot` (#826)."""
    return _render_population_pyramid(
        target,
        plot._pyramid,
        plot._categorical,
        plot._settings,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )


def population_pyramid(
    df: DataFrame,
    categories: String,
    left_values: String,
    right_values: String,
    left_name: String = "",
    right_name: String = "",
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`population_pyramid()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: The string column for this channel.
        left_values: The numeric column for this channel.
        right_values: The numeric column for this channel.
        left_name: See the list overload.
        right_name: See the list overload.
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
        df, categories, "population_pyramid()"
    )
    var left_values_values = _frame_floats(
        df, left_values, "population_pyramid()"
    )
    var right_values_values = _frame_floats(
        df, right_values, "population_pyramid()"
    )
    return population_pyramid(
        categories=categories_values,
        left_values=left_values_values,
        right_values=right_values_values,
        left_name=left_name,
        right_name=right_name,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )


def population_pyramid[
    dtype: DType
](
    categories: List[String],
    left_values: List[Scalar[dtype]],
    right_values: List[Scalar[dtype]],
    left_name: String = "",
    right_name: String = "",
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A population pyramid, the standard demographic chart for an
    age/sex distribution: two mirrored horizontal bars per category (an
    age band), one extending left and one right, so the two groups'
    shapes can be compared directly.

    `Mark.POPULATION_PYRAMID`: two mirrored horizontal bars per category
    growing outward from a shared, always-centered zero baseline.

    Args:
        categories: One row of two mirrored bars per entry, top to
            bottom.
        left_values: Each row's left-side magnitude, non-negative.
        right_values: Each row's right-side magnitude, non-negative.
        left_name: Legend label for the left side; left empty (the
            default), falls back to "Left" at render time.
        right_name: Legend label for the right side; left empty (the
            default), falls back to "Right" at render time.
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
        from dataviz import population_pyramid
        from dataviz import save

        def main() raises:
            var age_bands: List[String] = ["0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70+"]
            var male: List[Float64] = [12.0, 13.0, 14.0, 12.5, 10.0, 8.5, 6.0, 4.0]
            var female: List[Float64] = [11.5, 12.5, 13.5, 12.0, 10.5, 9.0, 7.0, 5.5]

            # Illustrative resident counts in millions.
            var c = population_pyramid(
                age_bands,
                male,
                female,
                left_name="Male",
                right_name="Female",
                title="Illustrative Population by Age and Sex",
                x_title="Population (millions)",
                y_title="Age group",
            )
            save(c, "docs/src/examples/out_population_pyramid.svg")
        ```
    """
    var left_values_f = _materialize_scalar_list(left_values)
    var right_values_f = _materialize_scalar_list(right_values)
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(
            categories=categories,
            left_values=left_values_f,
            right_values=right_values_f,
            left_name=left_name,
            right_name=right_name,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def _encode_population_pyramid(
    mut plot: Plot,
    categories: List[String],
    left_values: List[Float64],
    right_values: List[Float64],
    left_name: String,
    right_name: String,
) raises:
    """`Plot.encode_population_pyramid()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark,
        "encode_population_pyramid",
        "mark_population_pyramid()",
        Mark.POPULATION_PYRAMID,
    )
    plot._categorical.x = categories.copy()
    plot._continuous.x = List[Float64]()
    plot._continuous.y = List[Float64]()
    plot._pyramid.left = left_values.copy()
    plot._pyramid.right = right_values.copy()
    plot._pyramid.left_name = left_name
    plot._pyramid.right_name = right_name
