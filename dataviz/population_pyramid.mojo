from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _draw_legend,
    _dynamic_legend_width,
    _finished,
    _require_non_empty,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


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



def _symmetric_zero_baseline_x_extent(left: List[Float64], right: List[Float64]) raises -> LinearScale:
    """The x-domain for `Mark.POPULATION_PYRAMID`: always `[-bound, bound]`,
    with `bound` the largest magnitude across both sides plus a 5% pad
    (the same fraction `_data_extent`/`_zero_baseline_y_extent` use).
    Forced symmetric so both sides share one scale. Every value is read
    as a magnitude (`max(v, -v)`) regardless of sign; see
    `encode_population_pyramid()`.
    """
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
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.POPULATION_PYRAMID` plot:
    `_draw_horizontal_categorical_axis_frame` (the frame `Mark.GANTT`
    uses) with `_symmetric_zero_baseline_x_extent`'s centered domain, and
    two mirrored bars per row: `left_values[i]` fills from the center
    leftward and `right_values[i]` rightward, in
    `default_categorical_palette()` indices 0 and 1.

    A zero-magnitude side draws no bar (not floored to 1px the way
    `Mark.GANTT`'s zero-length span is): nothing on that side means
    nothing to mark.

    Draws a two-entry legend (`left_name`/`right_name`, defaulting to
    "Left"/"Right") via `_draw_legend`/`_dynamic_legend_width`, reserved
    from the outer `ox1`, whenever `Theme.show_legend` is on.
    """
    if len(plot.x_categories) != len(plot._pyramid.left) or len(plot._pyramid.right) != len(plot._pyramid.left):
        raise Error(
            "Plot.encode_population_pyramid(): categories, left_values, and"
            " right_values must all have the same length (got "
            + String(len(plot.x_categories))
            + " categories, "
            + String(len(plot._pyramid.left))
            + " left_values, "
            + String(len(plot._pyramid.right))
            + " right_values)"
        )

    var theme = plot._theme
    _require_non_empty(
        len(plot.x_categories), "Plot.encode_population_pyramid()"
    )
    var sc = _Scaled(theme)
    var legend_names = List[String]()
    if theme.show_legend:
        legend_names.append(plot._pyramid.left_name if plot._pyramid.left_name.byte_length() > 0 else "Left")
        legend_names.append(plot._pyramid.right_name if plot._pyramid.right_name.byte_length() > 0 else "Right")
    var legend_reserve = _dynamic_legend_width(legend_names, sc.legend_swatch_size, sc) if theme.show_legend else 0

    var x_scale = _symmetric_zero_baseline_x_extent(plot._pyramid.left, plot._pyramid.right)
    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()
    var center_px = _axis_pixel(frame.x_scale, 0.0)
    var row_height = _round_to_int(frame.y_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var row_y = _round_to_int(frame.y_scale.band_start(i))

        var left_edge_px = _axis_pixel(frame.x_scale, -max(plot._pyramid.left[i], -plot._pyramid.left[i]))
        var left_x = min(left_edge_px, center_px)
        var left_w = max(left_edge_px, center_px) - min(left_edge_px, center_px)
        if left_w > 0:
            target.fill_rect(left_x, row_y, left_w, row_height, palette[0])

        var right_edge_px = _axis_pixel(frame.x_scale, max(plot._pyramid.right[i], -plot._pyramid.right[i]))
        var right_x = min(center_px, right_edge_px)
        var right_w = max(center_px, right_edge_px) - min(center_px, right_edge_px)
        if right_w > 0:
            target.fill_rect(right_x, row_y, right_w, row_height, palette[1])

    if theme.show_legend:
        _draw_legend(
            target,
            frame.text_requests,
            legend_names,
            palette,
            _round_to_int(frame.x_scale.range_max) + sc.margin_right,
            _round_to_int(frame.y_scale.range_max),
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
    """A population pyramid.

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
        from dataviz.plot import save

        def main() raises:
            var age_bands: List[String] = ["0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70+"]
            var male: List[Float64] = [12.0, 13.0, 14.0, 12.5, 10.0, 8.5, 6.0, 4.0]
            var female: List[Float64] = [11.5, 12.5, 13.5, 12.0, 10.5, 9.0, 7.0, 5.5]

            var c = population_pyramid(age_bands, male, female, left_name="Male", right_name="Female")
            save(c, "docs/src/examples/out_population_pyramid.svg")
        ```
    """
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=categories,
        left_values=left_values,
        right_values=right_values,
        left_name=left_name,
        right_name=right_name,
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


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
    `scatter()`'s `DType` overload (plot.mojo). `left_values`/
    `right_values` share one dtype. Delegates to the concrete overload
    above.
    """
    return population_pyramid(
        categories, _materialize_scalar_list(left_values), _materialize_scalar_list(right_values),
        left_name=left_name, right_name=right_name, theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
