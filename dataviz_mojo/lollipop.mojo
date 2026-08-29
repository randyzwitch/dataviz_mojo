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
    _finished,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz_mojo.theme import Theme


def _render_lollipop[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.LOLLIPOP` plot: exactly `_render_bar`'s categorical x-axis / zero-baseline y-axis (`_draw_categorical_axis_
    frame`, shared -- see its docstring), but each category draws a
    thin stem (`stroke_path_aa`, `Theme.line_width`, matching `Mark.
    LINE`'s stroke-width convention) from the zero baseline up to
    its value, capped with a point (`fill_circle_aa`, `Theme.
    point_radius`, matching `Mark.POINT`'s own) at the value itself --
    the same "magnitude from a baseline" meaning a bar's height
    encodes, just drawn as a stem+point instead of a filled rect.

    Stem/point positions use raw (unrounded) pixel floats from
    `x_scale.center(i)`/`y_scale.to_pixel(...)` for the `Path` the stem
    strokes through, the same sub-pixel-precision convention `Mark.
    LINE`/`AREA` already use for their `Path`s -- only the point's
    *center*, passed to `fill_circle_aa` (an `Int`-coordinate primitive,
    see canvas_mojo/draw_target.mojo), gets rounded, matching `Mark.POINT`'s `_axis_pixel` convention.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var y_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var baseline_py = frame.y_scale.to_pixel(0.0)
    # True only when every value here is non-negative (the only case
    # _zero_baseline_y_extent's domain puts 0 exactly at the drawn
    # bottom axis line) -- see _pull_off_axis_line's docstring
    # (plot.mojo) for the same reasoning, applied to a stroked stem
    # here instead of a filled rect.
    var baseline_on_axis_line = _round_to_int(baseline_py) == frame.py1
    for i in range(len(plot.x_categories)):
        var center = frame.x_scale.center(i)
        var value_py = frame.y_scale.to_pixel(plot.y_data[i])
        # Pulled 1px off the axis line so a nonzero stem doesn't paint
        # over the row the line's own antialiasing occupies -- left
        # alone for a zero-value stem (value_py == baseline_py) so it
        # doesn't grow a real stem out of nothing.
        var stem_start_py = baseline_py - 1.0 if (baseline_on_axis_line and value_py != baseline_py) else baseline_py

        var stem = Path()
        stem.move_to(center, stem_start_py)
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
) raises -> Plot:
    """A lollipop chart -- `Mark.LOLLIPOP`, the same `(categories,
    values)` shape `bar()` takes (a thin stem plus a point instead of
    a filled rect per category).

    Args:
        categories: One stem-and-point per entry, in the given order.
        values: Each entry's value; negative values extend below the
            zero baseline automatically, the same as `bar()`.
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
        from dataviz_mojo import lollipop
        from dataviz_mojo.plot import save
        from dataviz_mojo.theme import Theme
        from dataviz_mojo.colors import TEAL

        def main() raises:
            var countries: List[String] = [
                "USA", "China", "Japan", "Germany", "India",
                "UK", "France", "Italy", "Brazil", "Canada",
            ]
            var gdp: List[Float64] = [27.4, 17.8, 4.2, 4.1, 3.7, 3.3, 3.0, 2.2, 2.1, 2.1]

            var c = lollipop(countries, gdp, theme=Theme(mark_color=TEAL))
            save(c, "docs/src/examples/out_lollipop.svg")
        ```
    """
    var plot = Plot().mark_lollipop().encode_categorical(x=categories, y=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
