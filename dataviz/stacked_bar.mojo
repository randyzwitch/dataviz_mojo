from canvas.text.font_cache import FontCache
from canvas.color import Color
from canvas.geometry import round_to_int
from canvas.vector.draw_target import DrawTarget

from canvas.text.render import TextAlign
from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.grouped_bar import (
    _draw_series_legend,
    _series_legend_reserve,
    _validate_grouped_bar_series,
)
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
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
)
from dataviz.scale import LinearScale, _format_tick, _label_decimals
from dataviz.theme import Theme


def _stacked_bar_domain(plot: Plot, n_series: Int) raises -> LinearScale:
    """The value-axis domain for `Mark.STACKED_BAR`, orientation-independent:
    fixed `[0, 100]` for `percent=True` (every column is exactly 100%
    long), otherwise `_zero_baseline_y_extent` over each category's final
    positive and negative running totals, the most extreme point each
    direction reaches.
    """
    if plot._stacked_bar_percent:
        return LinearScale(0.0, 100.0, 0.0, 1.0)
    var domain_data = List[Float64]()
    for i in range(len(plot.x_categories)):
        var pos_total = 0.0
        var neg_total = 0.0
        for j in range(n_series):
            var v = plot._grouped_bar.values[j][i]
            if v >= 0.0:
                pos_total += v
            else:
                neg_total += v
        domain_data.append(pos_total)
        domain_data.append(neg_total)
    return _zero_baseline_y_extent(domain_data)


def _validate_stacked_bar_percent(plot: Plot, n_series: Int) raises:
    """`percent=True` needs every value non-negative -- a negative
    share has no meaning. Orientation-independent."""
    if not plot._stacked_bar_percent:
        return
    for j in range(n_series):
        for v in plot._grouped_bar.values[j]:
            if v < 0.0:
                raise Error(
                    "Plot.mark_stacked_bar(percent=True): every value must be"
                    " >= 0 (a negative share has no meaning) -- got "
                    + String(v)
                )


def _draw_stacked_segments[
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
    """Every segment of every category's stack, written once for both
    orientations; `_Orientation` carries the two differences (which way a
    rect is emitted, where its label sits). `band_scale`/`value_scale`
    come from the caller's frame, and `baseline_edge` is that frame's
    axis line (`py1` vertically, `px0` horizontally) for
    `_pull_off_axis_line`.

    Mixed-sign values stack in two independent running totals per
    category: a non-negative value's segment sits on the running positive
    total and extends it, a negative value's on the running negative
    total. Positive parts build away from zero one way and negative parts
    the other, the usual convention for a mixed-sign stack.

    No pixel-boundary-rounding trick is needed as in `Mark.GROUPED_BAR`'s
    sub-bar division: a segment's far edge and the next segment's near
    edge are the identical `Float64` running total, so `_axis_pixel`
    rounds both to the same pixel.

    `Theme.show_data_labels` centers each segment's value inside it,
    since a stacked segment has neighbors on both sides.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var n_series = len(plot._grouped_bar.series_names)
    var band_size = round_to_int(band_scale.bandwidth())

    for i in range(len(plot.x_categories)):
        var band_pos = round_to_int(band_scale.band_start(i))
        # percent=True rescales each category against its own total. An
        # all-zero category gets a 0.0 factor and draws an empty column rather
        # than NaN.
        var scale_factor = 1.0
        if plot._stacked_bar_percent:
            var category_total = 0.0
            for j in range(n_series):
                category_total += plot._grouped_bar.values[j][i]
            scale_factor = (
                100.0 / category_total if category_total > 0.0 else 0.0
            )

        var pos_running = 0.0
        var neg_running = 0.0
        for j in range(n_series):
            var v = plot._grouped_bar.values[j][i] * scale_factor
            var seg_near: Float64
            var seg_far: Float64
            if v >= 0.0:
                seg_near = pos_running
                seg_far = pos_running + v
                pos_running = seg_far
            else:
                seg_far = neg_running
                seg_near = neg_running + v
                neg_running = seg_near
            var extent = _pull_off_axis_line(
                _axis_pixel(value_scale, seg_far),
                _axis_pixel(value_scale, seg_near),
                baseline_edge,
            )
            if theme.svg_tooltips:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        plot.x_categories[i],
                        plot._grouped_bar.series_names[j],
                        v,
                    )
                )
            orient.fill_band_rect(
                target, extent, band_pos, band_size, palette[j % len(palette)]
            )
            if theme.svg_tooltips:
                target.end_annotated_group()
            if theme.show_data_labels:
                var at = orient.band_label_point(
                    extent, band_pos, band_size, sc.font_size
                )
                text_requests.append(
                    _TextRequest(
                        at.x,
                        at.y,
                        _format_tick(
                            v,
                            _label_decimals(v),
                            theme.x_tick_format if orient.horizontal else theme.y_tick_format,
                        ),
                        theme.text_color,
                        sc.font_size,
                        TextAlign.CENTER,
                        theme.font_family,
                    )
                )


def _render_stacked_bar[
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
    """Render a `Mark.STACKED_BAR` plot: the same `encode_grouped_bar()` data
    `Mark.GROUPED_BAR` uses, with each category's series stacked as
    full-band-width segments on top of each other instead of side-by-side
    sub-bars. The running-total stacking, mixed-sign handling, and label
    placement are described in `_draw_stacked_segments`; the domain comes
    from `_stacked_bar_domain` (a first pass over the data computing each
    category's final totals, which the drawing pass then recomputes).

    Same legend as `Mark.GROUPED_BAR` (`_series_legend_reserve`/
    `_draw_series_legend`, imported from grouped_bar.mojo alongside
    `_validate_grouped_bar_series`). No sign coloring.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    var n_series = len(plot._grouped_bar.series_names)
    _validate_stacked_bar_percent(plot, n_series)
    var y_scale = _stacked_bar_domain(plot, n_series)

    var sc = _Scaled(theme)
    var legend = _series_legend_reserve(plot, sc, ox1 - ox0, cache=cache)
    var frame = _draw_categorical_axis_frame(
        target,
        plot.x_categories,
        y_scale,
        theme,
        ox0 + legend.left,
        oy0 + legend.top,
        ox1 - legend.right,
        oy1 - legend.bottom,
        cache=cache,
    )

    var palette = default_categorical_palette()
    _draw_stacked_segments(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        frame.py1,
        _Orientation(False),
        palette,
        frame.text_requests,
    )

    if theme.show_legend:
        _draw_series_legend(
            target,
            frame.text_requests,
            plot,
            sc,
            palette,
            legend,
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            theme,
        )

    return frame.result()


def _render_horizontal_stacked_bar[
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
    """`_render_stacked_bar`'s mirror image for
    `Plot.mark_stacked_bar(horizontal=True)` (#121):
    `_render_horizontal_bar`'s categorical y-axis / zero-baseline (or
    fixed `[0, 100]` for `percent=True`) x-axis
    (`_draw_horizontal_categorical_axis_frame`, gantt.mojo), with each
    category's row stacking its segments left-to-right at full band
    height. The stacking logic is identical. Its own function rather than
    an orientation flag, for the reasons in `_render_horizontal_bar`'s
    docstring (bar.mojo). Legend placement matches
    `_render_horizontal_grouped_bar`.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    var n_series = len(plot._grouped_bar.series_names)
    _validate_stacked_bar_percent(plot, n_series)
    var x_scale = _stacked_bar_domain(plot, n_series)

    var sc = _Scaled(theme)
    var legend = _series_legend_reserve(plot, sc, ox1 - ox0, cache=cache)
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot.x_categories,
        x_scale,
        theme,
        ox0 + legend.left,
        oy0 + legend.top,
        ox1 - legend.right,
        oy1 - legend.bottom,
        cache=cache,
    )

    var palette = default_categorical_palette()
    _draw_stacked_segments(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        frame.px0,
        _Orientation(True),
        palette,
        frame.text_requests,
    )

    if theme.show_legend:
        _draw_series_legend(
            target,
            frame.text_requests,
            plot,
            sc,
            palette,
            legend,
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            theme,
        )

    return frame.result()


def stacked_bar(
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
    percent: Bool = False,
    horizontal: Bool = False,
) raises -> Plot:
    """A stacked bar chart: the same category/series/value shape as
    `grouped_bar()`, drawn as one bar per category with series stacked on
    top of each other, for comparing both each category's total and its
    composition at once.

    `Mark.STACKED_BAR`: the same `(categories, series_names, values)`
    shape `grouped_bar()` takes, each series drawn as a stacked segment
    instead of a side-by-side sub-bar. See `Plot.mark_stacked_bar()` for
    `percent=True`.

    Args:
        categories: One stacked bar per entry, in the given order.
        series_names: One stacked segment per name, used as the
            legend key.
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
        percent: `False` (the default) stacks raw values. `True`
            normalizes each category to 100% -- see `Plot.mark_
            stacked_bar()`'s own docstring.
        horizontal: Draw categories running top-to-bottom with each
            category's segments stacked left-to-right instead of the
            default vertical layout -- see `Plot.mark_stacked_bar()`'s
            own docstring (#121).

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import stacked_bar
        from dataviz.plot import save

        def main() raises:
            var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
            var series_names: List[String] = ["North", "South", "East"]
            var values: List[List[Int]] = [
                [42, 48, 45, 61],
                [30, 35, 33, 40],
                [55, 50, 58, 66],
            ]

            var c = stacked_bar(
                quarters,
                series_names,
                values,
                title="Quarterly Revenue by Region (stacked)",
                x_title="Quarter",
                y_title="Revenue ($M)",
            )
            save(c, "docs/src/examples/out_stacked_bar.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_stacked_bar(percent=percent, horizontal=horizontal)
        .encode_grouped_bar(
            categories=categories, series_names=series_names, values=values
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def stacked_bar[
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
    percent: Bool = False,
    horizontal: Bool = False,
) raises -> Plot:
    """`stacked_bar()` generalized over numeric element type for `values`;
    see `grouped_bar()`'s `DType` overload. Delegates to the concrete
    overload above.
    """
    return stacked_bar(
        categories,
        series_names,
        _materialize_nested_scalar_list(values),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
        percent=percent,
        horizontal=horizontal,
    )
