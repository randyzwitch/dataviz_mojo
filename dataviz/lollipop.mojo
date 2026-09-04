from canvas.geometry import _round_to_int
from canvas.path import Path
from dataviz.plot import _LazyFontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _BaselineRect,
    _Orientation,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _tooltip_label,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _finished,
    _pull_off_axis_line,
    _zero_baseline_y_extent,
    _validate_categorical_encoding,
)
from dataviz.scale import LinearScale, _format_tick, _label_decimals
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
    mut text_requests: List[_TextRequest],
) raises:
    """Every category's stem and head, written once for both orientations;
    `_Orientation` supplies the stem path, the head circle, and the
    direction to nudge off the axis line.

    The stem is pulled 1px clear of the categorical axis line so it
    doesn't paint over that line's antialiasing, but only when the
    baseline sits on that line (every value non-negative, so
    `_zero_baseline_y_extent` puts 0 at the drawn edge). A zero-value stem
    is left alone so it doesn't grow a stem out of nothing.

    `Theme.show_data_labels` (#213) places each label past the head
    circle via the same `orient.outside_band_label()` `Mark.BAR` uses,
    fed a `_BaselineRect` padded `radius` past both ends (rather than
    `_pull_off_axis_line`'s bare stem extent) so the label clears the
    dot regardless of which end is the "far" one for a negative value.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var baseline = value_scale.to_pixel(0.0)
    var baseline_on_axis_line = _round_to_int(baseline) == baseline_edge
    var band_size = _round_to_int(band_scale.bandwidth())

    for i in range(len(plot.x_categories)):
        var band_pos = _round_to_int(band_scale.band_start(i))
        var center = band_scale.center(i)
        var value = value_scale.to_pixel(plot.y_data[i])
        var stem_from = (
            baseline
            + orient.baseline_pull() if (
                baseline_on_axis_line and value != baseline
            ) else baseline
        )
        if theme.svg_tooltips:
            target.begin_annotated_group(
                _tooltip_label(plot.x_categories[i], plot.y_data[i])
            )
        target.stroke_path_aa(
            orient.value_stem_path(stem_from, value, center),
            theme.mark_color,
            width=line_width,
        )
        orient.band_point(
            target,
            _round_to_int(value),
            _round_to_int(center),
            radius,
            theme.mark_color,
        )
        if theme.svg_tooltips:
            target.end_annotated_group()
        if theme.show_data_labels:
            var extent = _pull_off_axis_line(
                _axis_pixel(value_scale, 0.0),
                _axis_pixel(value_scale, plot.y_data[i]),
                baseline_edge,
            )
            var padded_extent = _BaselineRect(
                extent.y - radius, extent.height + 2 * radius
            )
            var label_value = plot.y_data[i]
            var at = orient.outside_band_label(
                padded_extent,
                band_pos,
                band_size,
                label_value < 0.0,
                sc.label_gap,
                sc.font_size,
            )
            text_requests.append(
                _TextRequest(
                    at.x,
                    at.y,
                    _format_tick(
                        label_value,
                        _label_decimals(label_value),
                        theme.x_tick_format if orient.horizontal else theme.y_tick_format,
                    ),
                    theme.text_color,
                    sc.font_size,
                    at.align,
                    theme.font_family,
                )
            )


def _render_lollipop[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """Render a `Mark.LOLLIPOP` plot: `_render_bar`'s categorical x-axis /
    zero-baseline y-axis (`_draw_categorical_axis_frame`), with each
    category drawn as a thin stem (`stroke_path_aa`, `Theme.line_width`)
    from the zero baseline to its value, capped with a point
    (`fill_circle_aa`, `Theme.point_radius`).

    Stem positions use unrounded pixel floats for the `Path`, as
    `Mark.LINE`/`AREA` do; only the point's center, passed to the
    `Int`-coordinate `fill_circle_aa`, is rounded.
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var y_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_categorical_axis_frame(
        target,
        plot.x_categories,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_lollipop_stems(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        frame.sc.line_width,
        _round_to_int(frame.sc.point_radius),
        frame.text_requests,
    )

    return frame.result()


def _render_horizontal_lollipop[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: _LazyFontCache,
) raises -> _RenderResult:
    """`_render_lollipop`'s mirror image for
    `Plot.mark_lollipop(horizontal=True)` (#121): `_render_horizontal_bar`'s
    categorical y-axis / zero-baseline x-axis
    (`_draw_horizontal_categorical_axis_frame`, gantt.mojo), with each
    stem running from the zero baseline out to its value along `x_scale`.
    Its own function rather than an orientation flag on
    `_render_lollipop`, for the reasons in `_render_horizontal_bar`'s
    docstring (bar.mojo).
    """
    _validate_categorical_encoding(plot)

    var theme = plot._theme
    var x_scale = _zero_baseline_y_extent(plot.y_data)
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot.x_categories,
        x_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    _draw_lollipop_stems(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        frame.px0,
        _Orientation(True),
        frame.sc.line_width,
        _round_to_int(frame.sc.point_radius),
        frame.text_requests,
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
    """A lollipop chart: the same category/value shape as `bar()`, drawn
    as a thin stem and dot instead of a filled rectangle, reducing
    visual weight when a chart has many categories or the comparison is
    really about position, not area.

    `Mark.LOLLIPOP`: the same `(categories, values)` shape `bar()` takes,
    drawn as a thin stem plus a point per category instead of a filled
    rect.

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
    var plot = (
        Plot()
        .mark_lollipop(horizontal=horizontal)
        .encode_categorical(x=categories, y=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


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
    """`lollipop()` generalized over numeric element type; see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return lollipop(
        categories,
        _materialize_scalar_list(values),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
        horizontal=horizontal,
    )
