from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.gantt import _draw_horizontal_categorical_axis_frame
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _rendered,
)
from dataviz_mojo.scale import LinearScale
from dataviz_mojo.theme import Theme


def _symmetric_zero_baseline_x_extent(left: List[Float64], right: List[Float64]) raises -> LinearScale:
    """The x-domain for `Mark.POPULATION_PYRAMID`: always `[-bound,
    bound]`, `bound` the largest magnitude across *both* sides (plus a
    5% pad, the same padding fraction `_data_extent`/`_zero_baseline_y_
    extent` use elsewhere) -- unlike `_zero_baseline_y_extent`'s
    independent low/high padding, this is forced symmetric on purpose:
    a pyramid's whole point is comparing left vs. right at a glance, so
    both sides have to share one scale, or a longer bar could just mean
    "this side's own axis happens to be stretched less," not "this
    category is actually bigger." Every value is read as a magnitude
    (`max(v, -v)`) regardless of sign -- see `encode_population_
    pyramid()`'s own docstring for why."""
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
    """Render a `Mark.POPULATION_PYRAMID` plot: `_draw_horizontal_
    categorical_axis_frame`'s own horizontal categorical axis (the
    exact frame `Mark.GANTT` uses, reused unchanged -- categories along
    `y`, top-to-bottom, a continuous `x`-domain along the bottom), but
    with `_symmetric_zero_baseline_x_extent`'s own always-centered
    domain instead of `Gantt`'s data-extent one, and two mirrored bars
    per row instead of one floating span: `left_values[i]` fills from
    the center leftward, `right_values[i]` from the center rightward,
    each in its own color from `default_categorical_palette()` (index
    0/1 -- the same two-color convention `Mark.GROUPED_BAR`'s own
    per-series coloring establishes, just fixed at two series instead
    of `n_series`).

    A zero-magnitude side draws no bar at all (width 0, skipped) --
    deliberately *not* `Mark.GANTT`'s own zero-length-span-floors-to-
    1px rule: a gantt milestone is real, informative data at a single
    point; a population-pyramid category with nothing on one side (no
    data for that side, or a genuine zero count) has nothing to mark
    there, so drawing a 1px sliver would misrepresent it as data.

    Draws a two-entry legend (`left_name`/`right_name`, defaulting to
    "Left"/"Right") via the same `_draw_legend`/`_dynamic_legend_width`
    pair `Mark.GROUPED_BAR`/`STACKED_BAR` use, reserved from the outer
    `ox1` the same "shrink the rect from outside" way -- shown whenever
    `Theme.show_legend` is on, unconditionally (unlike `Mark.GROUPED_
    BAR`, whose legend already has a real series name per entry from
    `encode_grouped_bar()`, a population pyramid's two sides are
    meaningful even with no name given at all, so the legend still
    draws with its "Left"/"Right" fallback rather than being suppressed
    for lack of one).
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
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

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
) raises -> Canvas:
    """A population pyramid -- `Mark.POPULATION_PYRAMID`, two mirrored
    horizontal bars per category growing outward from a shared, always-
    centered zero baseline."""
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=categories,
        left_values=left_values,
        right_values=right_values,
        left_name=left_name,
        right_name=right_name,
    )
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
