from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _empty_result,
    _rendered,
    _zero_baseline_y_extent,
)
from dataviz_mojo.theme import Theme


def _render_lollipop[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.LOLLIPOP` plot: exactly `_render_bar`'s own
    categorical x-axis / zero-baseline y-axis (`_draw_categorical_axis_
    frame`, shared -- see its own docstring), but each category draws a
    thin stem (`stroke_path_aa`, `Theme.line_width`, matching `Mark.
    LINE`'s own stroke-width convention) from the zero baseline up to
    its value, capped with a point (`fill_circle_aa`, `Theme.
    point_radius`, matching `Mark.POINT`'s own) at the value itself --
    the same "magnitude from a baseline" meaning a bar's height
    encodes, just drawn as a stem+point instead of a filled rect.

    Stem/point positions use raw (unrounded) pixel floats from
    `x_scale.center(i)`/`y_scale.to_pixel(...)` for the `Path` the stem
    strokes through, the same sub-pixel-precision convention `Mark.
    LINE`/`AREA` already use for their own `Path`s -- only the point's
    *center*, passed to `fill_circle_aa` (an `Int`-coordinate primitive,
    see canvas_mojo/draw_target.mojo), gets rounded, matching `Mark.POINT`'s
    own `_axis_pixel` convention.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_categorical(): x and y must have the same length"
            " (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var y_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var baseline_py = frame.y_scale.to_pixel(0.0)
    for i in range(len(plot.x_categories)):
        var center = frame.x_scale.center(i)
        var value_py = frame.y_scale.to_pixel(plot.y_data[i])

        var stem = Path()
        stem.move_to(center, baseline_py)
        stem.line_to(center, value_py)
        target.stroke_path_aa(stem, theme.mark_color, width=frame.sc.line_width)

        target.fill_circle_aa(
            _round_to_int(center), _round_to_int(value_py), _round_to_int(frame.sc.point_radius), theme.mark_color
        )

    return frame.result()


def lollipop(
    categories: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A lollipop chart -- `Mark.LOLLIPOP`, the same `(categories,
    values)` shape `bar()` takes (a thin stem plus a point instead of
    a filled rect per category)."""
    var plot = Plot().mark_lollipop().encode_categorical(x=categories, y=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
