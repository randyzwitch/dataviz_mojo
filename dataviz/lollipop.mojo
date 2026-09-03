from canvas.geometry import _round_to_int
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _Orientation,
    _RenderResult,
    _draw_categorical_axis_frame,
    _empty_result,
    _finished,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


def _draw_lollipop_stems[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    baseline_edge: Int,
    orient: _Orientation,
    line_width: Float64,
    radius: Int,
) raises:
    """Every category's stem and head, written once for both
    orientations -- `_Orientation` carries the three places band and
    value become concrete pixels (the stem's path, the head's circle,
    and which way to nudge off the axis line).

    The stem is pulled 1px clear of the categorical axis line so it
    doesn't paint over the row that line's own antialiasing occupies --
    but only when the baseline actually sits *on* that line, which is
    exactly when every value is non-negative (the one case
    `_zero_baseline_y_extent`'s domain puts 0 at the drawn edge). A
    zero-value stem is left alone either way, so it doesn't grow a real
    stem out of nothing. `_Orientation.baseline_pull` supplies the
    direction, since "off the axis line" is upward vertically and
    rightward horizontally.
    """
    var theme = plot._theme
    var baseline = value_scale.to_pixel(0.0)
    var baseline_on_axis_line = _round_to_int(baseline) == baseline_edge

    for i in range(len(plot.x_categories)):
        var center = band_scale.center(i)
        var value = value_scale.to_pixel(plot.y_data[i])
        var stem_from = (
            baseline + orient.baseline_pull()
            if (baseline_on_axis_line and value != baseline)
            else baseline
        )
        target.stroke_path_aa(
            orient.value_stem_path(stem_from, value, center), theme.mark_color, width=line_width
        )
        orient.band_point(
            target, _round_to_int(value), _round_to_int(center), radius, theme.mark_color
        )


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
    see canvas/draw_target.mojo), gets rounded, matching `Mark.POINT`'s `_axis_pixel` convention.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var y_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    _draw_lollipop_stems(
        target, plot, frame.x_scale, frame.y_scale, frame.py1, _Orientation(False),
        frame.sc.line_width, _round_to_int(frame.sc.point_radius),
    )

    return frame.result()


def _render_horizontal_lollipop[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """`_render_lollipop`'s mirror image for `Plot.mark_lollipop(
    horizontal=True)` (#121) -- exactly `_render_horizontal_bar`'s own
    categorical y-axis / zero-baseline x-axis (`_draw_horizontal_
    categorical_axis_frame`, gantt.mojo, shared -- see that function's
    docstring), but each category draws a horizontal stem (`stroke_
    path_aa`) from the zero baseline out to its value along `x_scale`,
    capped with a point at the value itself -- the same stem+point
    shape `_render_lollipop` draws, just swapped onto the horizontal
    frame's `(LinearScale x_scale, OrdinalScale y_scale)` instead of
    the vertical one's `(OrdinalScale x_scale, LinearScale y_scale)`.

    Deliberately its own function, not an orientation flag threaded
    through `_render_lollipop` -- see `_render_horizontal_bar`'s own
    docstring (bar.mojo) for the full reasoning, identical here.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var x_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1, oy1
    )

    _draw_lollipop_stems(
        target, plot, frame.y_scale, frame.x_scale, frame.px0, _Orientation(True),
        frame.sc.line_width, _round_to_int(frame.sc.point_radius),
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
    horizontal: Bool = False,
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
        horizontal: Draw categories running top-to-bottom with each
            stem extending left-to-right instead of the default
            vertical layout -- see `Plot.mark_lollipop()`'s own
            docstring (#121).

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import lollipop
        from dataviz.plot import save
        from dataviz.theme import Theme
        from dataviz.colors import TEAL

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
    var plot = Plot().mark_lollipop(horizontal=horizontal).encode_categorical(x=categories, y=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def lollipop[
    dtype: DType
](
    categories: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`lollipop()`, generalized over numeric element type -- see
    `scatter()`'s own `DType`-generic overload (plot.mojo) for the
    full reasoning. Delegates to the concrete `lollipop()` above.
    """
    return lollipop(
        categories, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title, horizontal=horizontal,
    )
