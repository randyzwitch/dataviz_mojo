from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.color_scale import categorical_palette_for
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.plot import (
    Plot,
    _BaselineRectF,
    _Orientation,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _axis_pixel_f,
    _snap_pixel_edge,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
    _require_non_empty,
    _series_tooltip_label,
)
from dataviz.core.scale import LinearScale, _format_tick, _label_decimals
from dataviz.core.theme import Theme


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
    plot: Plot,
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
    if len(plot._categorical.x) != len(plot._pyramid.left) or len(
        plot._pyramid.right
    ) != len(plot._pyramid.left):
        raise Error(
            "Plot.encode_population_pyramid(): categories, left_values, and"
            " right_values must all have the same length (got "
            + String(len(plot._categorical.x))
            + " categories, "
            + String(len(plot._pyramid.left))
            + " left_values, "
            + String(len(plot._pyramid.right))
            + " right_values)"
        )

    var theme = plot._theme
    _require_non_empty(
        len(plot._categorical.x), "Plot.encode_population_pyramid()"
    )
    var sc = _Scaled(theme)
    # Tooltips need side names even when the legend is hidden.
    var left_name = (
        plot._pyramid.left_name if plot._pyramid.left_name.byte_length()
        > 0 else "Left"
    )
    var right_name = (
        plot._pyramid.right_name if plot._pyramid.right_name.byte_length()
        > 0 else "Right"
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

    var x_scale = _symmetric_zero_baseline_x_extent(
        plot._pyramid.left, plot._pyramid.right
    )
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
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
    for i in range(len(plot._categorical.x)):
        var row_y = frame.y_scale.band_start(i)

        var left_edge_px = _axis_pixel_f(
            frame.x_scale, -max(plot._pyramid.left[i], -plot._pyramid.left[i])
        )
        var left_x = min(left_edge_px, center_px)
        var left_w = max(left_edge_px, center_px) - min(left_edge_px, center_px)
        if left_w > 0.0:
            if theme.svg_tooltips:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        plot._categorical.x[i],
                        left_name,
                        plot._pyramid.left[i],
                    )
                )
            var lx0 = _snap_pixel_edge(left_x)
            var lx1 = _snap_pixel_edge(left_x + left_w)
            var ly0 = _snap_pixel_edge(row_y)
            var ly1 = _snap_pixel_edge(row_y + row_height)
            target.fill_rect(lx0, ly0, lx1 - lx0, ly1 - ly0, palette[0])
            if theme.svg_tooltips:
                target.end_annotated_group()
            if theme.show_data_labels:
                var left_value = plot._pyramid.left[i]
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
            frame.x_scale, max(plot._pyramid.right[i], -plot._pyramid.right[i])
        )
        var right_x = min(center_px, right_edge_px)
        var right_w = max(center_px, right_edge_px) - min(
            center_px, right_edge_px
        )
        if right_w > 0.0:
            if theme.svg_tooltips:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        plot._categorical.x[i],
                        right_name,
                        plot._pyramid.right[i],
                    )
                )
            var rx0 = _snap_pixel_edge(right_x)
            var rx1 = _snap_pixel_edge(right_x + right_w)
            var ry0 = _snap_pixel_edge(row_y)
            var ry1 = _snap_pixel_edge(row_y + row_height)
            target.fill_rect(rx0, ry0, rx1 - rx0, ry1 - ry0, palette[1])
            if theme.svg_tooltips:
                target.end_annotated_group()
            if theme.show_data_labels:
                var right_value = plot._pyramid.right[i]
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
        )

    return frame.result()


def population_pyramid(
    categories: List[String],
    left_values: List[Float64],
    right_values: List[Float64],
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
    var plot = (
        Plot()
        .mark_population_pyramid()
        .encode_population_pyramid(
            categories=categories,
            left_values=left_values,
            right_values=right_values,
            left_name=left_name,
            right_name=right_name,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
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
    """`population_pyramid()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (continuous.mojo). `left_values`/
    `right_values` share one dtype. Delegates to the concrete overload
    above.
    """
    return population_pyramid(
        categories,
        _materialize_scalar_list(left_values),
        _materialize_scalar_list(right_values),
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
