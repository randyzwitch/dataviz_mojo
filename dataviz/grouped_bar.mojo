from canvas.color import Color
from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from canvas.text.render import TextAlign
from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Orientation,
    _Scaled,
    _series_tooltip_label,
    _TextRequest,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _draw_legend,
    _dynamic_legend_width,
    _pull_off_axis_line,
    _finished,
    _require_non_empty,
    _zero_baseline_y_extent,
)
from dataviz.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.theme import Theme


def _validate_grouped_bar_series(plot: Plot) raises:
    """`Plot.encode_grouped_bar()`'s deferred length checks:
    `series_names`/`values` the same length, and every `values[j]` the
    same length as `categories` (deferred to render() time; see that
    method), plus an empty-data check (`_require_non_empty`, #206) on
    both `categories` and `series_names`. Lives here next to
    `Mark.GROUPED_BAR`'s rendering and is imported by stacked_bar.mojo,
    bump.mojo, and streamgraph.mojo, which
    draw from the same data.
    """
    if len(plot._grouped_bar.series_names) != len(plot._grouped_bar.values):
        raise Error(
            "Plot.encode_grouped_bar(): series_names and values must have"
            " the same length (got "
            + String(len(plot._grouped_bar.series_names))
            + " and "
            + String(len(plot._grouped_bar.values))
            + ")"
        )
    for j in range(len(plot._grouped_bar.values)):
        if len(plot._grouped_bar.values[j]) != len(plot.x_categories):
            raise Error(
                "Plot.encode_grouped_bar(): every series' values must"
                " have the same length as categories (series "
                + String(j)
                + " has "
                + String(len(plot._grouped_bar.values[j]))
                + ", categories has "
                + String(len(plot.x_categories))
                + ")"
            )
    _require_non_empty(len(plot.x_categories), "Plot.encode_grouped_bar()")
    _require_non_empty(
        len(plot._grouped_bar.series_names), "Plot.encode_grouped_bar()"
    )


def _series_legend_reserve(plot: Plot, sc: _Scaled) raises -> Int:
    """The width the series-name legend needs, or `0` when
    `Theme.show_legend` is off. Subtracted from the outer `ox1` before the
    axis frame is built, the same shrink-the-rect-from-outside pattern
    `_apply_labels` uses.
    """
    if not plot._theme.show_legend:
        return 0
    return _dynamic_legend_width(plot._grouped_bar.series_names, sc.legend_swatch_size, sc)


def _draw_series_legend[
    T: DrawTarget
](
    mut target: T,
    mut text_requests: List[_TextRequest],
    plot: Plot,
    sc: _Scaled,
    palette: List[Color],
    legend_range_max: Int,
    legend_y: Int,
    theme: Theme,
) raises:
    """The one `_draw_legend` call `Mark.GROUPED_BAR`/`STACKED_BAR` make in
    both orientations. `legend_range_max + sc.margin_right` is the x
    position (the frame's continuous scale's `range_max`, already rounded
    by the caller); `legend_y` is the vertical frame's
    `y_scale.range_max` or the horizontal frame's `py0`, both the plot's
    top pixel.
    """
    _draw_legend(
        target,
        text_requests,
        plot._grouped_bar.series_names,
        palette,
        legend_range_max + sc.margin_right,
        legend_y,
        theme,
    )


def _draw_grouped_bars[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    baseline_edge: Int,
    orient: _Orientation,
    palette: List[Color],
    mut text_requests: List[_TextRequest],
) raises:
    """Every sub-bar of every category, written once for both orientations;
    `_Orientation` carries the two differences (which way a rect is
    emitted, where its label sits).

    Each category's band is divided into `n_series` equal sub-bands, and
    each sub-band's two edges are rounded to pixels independently from
    the same unrounded origin (`band_start + j * sub` and
    `band_start + (j+1) * sub`) rather than rounding a width once and
    stepping it, so sub-bar `j`'s far edge and `j+1`'s near edge are the
    identical integer with no seam or overlap.

    `band_scale`/`value_scale` come from the caller's frame, and
    `baseline_edge` is that frame's axis line (`py1` vertically, `px0`
    horizontally).
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var n_series = len(plot._grouped_bar.series_names)
    var baseline = _axis_pixel(value_scale, 0.0)
    var sub_size = band_scale.bandwidth() / Float64(n_series)

    for i in range(len(plot.x_categories)):
        var band_start = band_scale.band_start(i)
        for j in range(n_series):
            var near = _round_to_int(band_start + Float64(j) * sub_size)
            var far = _round_to_int(band_start + Float64(j + 1) * sub_size)
            var value = plot._grouped_bar.values[j][i]
            var extent = _pull_off_axis_line(
                baseline, _axis_pixel(value_scale, value), baseline_edge
            )
            if theme.svg_tooltips:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        plot.x_categories[i], plot._grouped_bar.series_names[j], value
                    )
                )
            orient.fill_band_rect(target, extent, near, far - near, palette[j % len(palette)])
            if theme.svg_tooltips:
                target.end_annotated_group()
            if theme.show_data_labels:
                var at = orient.outside_band_label(
                    extent, near, far - near, value < 0.0, sc.label_gap, sc.font_size
                )
                text_requests.append(
                    _TextRequest(
                        at.x,
                        at.y,
                        _format_fixed(value, _label_decimals(value)),
                        theme.text_color,
                        sc.font_size,
                        at.align,
                        theme.font_family,
                    )
                )


def _render_grouped_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.GROUPED_BAR` plot: `_render_bar`'s categorical x-axis /
    zero-baseline y-axis (`_draw_categorical_axis_frame`), with each
    category's band subdivided into `len(series_names)` equal-width
    sub-bars, one per series, colored by `default_categorical_palette()`
    (`j % len(palette)`). No sign coloring: series are told apart by
    color.

    The series-name legend is reserved via `Theme.show_legend` by
    subtracting its width from the outer `ox1` passed to
    `_draw_categorical_axis_frame`, the same pattern `_apply_labels` uses
    for title/axis-title margins.

    `Theme.show_data_labels` draws each sub-bar's value above (or below,
    for a negative value) it, centered on the sub-bar's width.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    var domain_data = List[Float64]()
    for j in range(len(plot._grouped_bar.values)):
        for i in range(len(plot._grouped_bar.values[j])):
            domain_data.append(plot._grouped_bar.values[j][i])
    var y_scale = _zero_baseline_y_extent(domain_data)

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _series_legend_reserve(plot, sc)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()
    _draw_grouped_bars(
        target, plot, frame.x_scale, frame.y_scale, frame.py1, _Orientation(False), palette,
        frame.text_requests,
    )

    if show_legend:
        _draw_series_legend(
            target,
            frame.text_requests,
            plot,
            sc,
            palette,
            _round_to_int(frame.x_scale.range_max),
            _round_to_int(frame.y_scale.range_max),
            theme,
        )

    return frame.result()


def _render_horizontal_grouped_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """`_render_grouped_bar`'s mirror image for
    `Plot.mark_grouped_bar(horizontal=True)` (#121):
    `_render_horizontal_bar`'s categorical y-axis / zero-baseline x-axis
    (`_draw_horizontal_categorical_axis_frame`, gantt.mojo), with each
    category's row subdivided into equal-height sub-bars stacked within
    it. Its own function rather than an orientation flag, for the reasons
    in `_render_horizontal_bar`'s docstring (bar.mojo).

    The legend still reserves space from the outer `ox1`;
    `frame.x_scale.range_max` lands at that reduced boundary in both
    orientations. It is positioned at the frame's top-left corner
    (`frame.px1 + margin_right`, `frame.py0`); the vertical version uses
    `frame.y_scale.range_max` for the same corner because there `y_scale`
    is the continuous scale.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    var domain_data = List[Float64]()
    for j in range(len(plot._grouped_bar.values)):
        for i in range(len(plot._grouped_bar.values[j])):
            domain_data.append(plot._grouped_bar.values[j][i])
    var x_scale = _zero_baseline_y_extent(domain_data)

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _series_legend_reserve(plot, sc)

    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()
    _draw_grouped_bars(
        target, plot, frame.y_scale, frame.x_scale, frame.px0, _Orientation(True), palette,
        frame.text_requests,
    )

    if show_legend:
        _draw_series_legend(
            target,
            frame.text_requests,
            plot,
            sc,
            palette,
            _round_to_int(frame.x_scale.range_max),
            frame.py0,
            theme,
        )

    return frame.result()


def grouped_bar(
    categories: List[String],
    series_names: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """A grouped bar chart.

    `Mark.GROUPED_BAR`: several bars side by side per category, one per
    series (`values[j]` is series `series_names[j]`'s value per
    category). See `Plot.encode_grouped_bar()` (plot.mojo) for the data
    shape.

    Args:
        categories: One group of side-by-side bars per entry, in the
            given order.
        series_names: One sub-bar per name, used as the legend key.
        values: `values[j]` is `series_names[j]`'s value per
            category.
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
            category's sub-bars stacked left-to-right instead of the
            default vertical layout -- see `Plot.mark_grouped_bar()`'s
            own docstring (#121).

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import grouped_bar
        from dataviz.plot import save

        def main() raises:
            var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
            var series_names: List[String] = ["North", "South", "East"]
            var values: List[List[Int]] = [
                [42, 48, 45, 61],
                [30, 35, 33, 40],
                [55, 50, 58, 66],
            ]

            var c = grouped_bar(
                quarters,
                series_names,
                values,
                title="Quarterly Revenue by Region",
                x_title="Quarter",
                y_title="Revenue ($M)",
            )
            save(c, "docs/src/examples/out_grouped_bar.svg")
        ```
    """
    var plot = Plot().mark_grouped_bar(horizontal=horizontal).encode_grouped_bar(
        categories=categories, series_names=series_names, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def grouped_bar[
    dtype: DType
](
    categories: List[String],
    series_names: List[String],
    values: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`grouped_bar()` generalized over numeric element type for `values`
    (`List[List[Int]]`, `List[List[Float32]]`, ...), via
    `_materialize_nested_scalar_list` (array_like.mojo); see `scatter()`'s
    `DType` overload (plot.mojo). Delegates to the concrete overload
    above.
    """
    return grouped_bar(
        categories, series_names, _materialize_nested_scalar_list(values), theme=theme, width=width,
        height=height, title=title, subtitle=subtitle, x_title=x_title, y_title=y_title, horizontal=horizontal,
    )
