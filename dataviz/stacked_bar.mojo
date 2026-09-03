from canvas.color import Color
from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from canvas.text.render import TextAlign
from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.grouped_bar import _draw_series_legend, _series_legend_reserve, _validate_grouped_bar_series
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
    _empty_result,
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
)
from dataviz.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.theme import Theme


def _stacked_bar_domain(plot: Plot, n_series: Int) raises -> LinearScale:
    """The value-axis domain a `Mark.STACKED_BAR` needs, orientation-
    independent: fixed `[0, 100]` for `percent=True` (every column is
    definitionally exactly 100% long, so a padded [0, 105]-ish axis
    would misrepresent that), otherwise `_zero_baseline_y_extent` over
    each category's *final* positive and negative running totals --
    always the most extreme point each direction reaches, so the raw
    per-segment values never need to enter the domain."""
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
                    "Plot.mark_stacked_bar(percent=True): every value must be >= 0 (a negative"
                    " share has no meaning) -- got " + String(v)
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
    orientations -- `_Orientation` carries the only two differences
    (which way a rect is emitted, where its label sits). `band_scale`/
    `value_scale` come from whichever frame the caller built, and
    `baseline_edge` is that frame's own axis line (`py1` vertically,
    `px0` horizontally) for `_pull_off_axis_line`'s
    don't-paint-over-the-axis check.

    Mixed-sign values stack in two independent running totals per
    category, not one: a non-negative value's segment sits on the
    running *positive* total and extends it, a negative value's on the
    running *negative* total. That is the convention most charting
    libraries use for a mixed-sign stack -- positive parts build away
    from zero one way, negative parts the other, independently --
    rather than one running sum where a negative value part-way up
    would slide every segment above it back down, which is visually
    nonsensical for a composition chart.

    No pixel-boundary-rounding trick is needed the way `Mark.GROUPED_
    BAR`'s sub-bar division needs one: a segment's far edge and the
    next segment's near edge are the *identical* `Float64` running
    total, so `_axis_pixel` rounds both to the same pixel on its own.

    `Theme.show_data_labels` centers each segment's own value *inside*
    it, not outside the way `Mark.BAR`/`GROUPED_BAR` place theirs -- a
    stacked segment usually has neighbors on both sides, so there is no
    clear outside edge to anchor to.
    """
    var theme = plot._theme
    var sc = _Scaled(theme)
    var n_series = len(plot._grouped_bar.series_names)
    var band_size = _round_to_int(band_scale.bandwidth())

    for i in range(len(plot.x_categories)):
        var band_pos = _round_to_int(band_scale.band_start(i))
        # percent=True rescales each category against its own total --
        # every other category's total is unrelated, so this is per
        # category, not once for the chart. An all-zero category
        # divides by nothing; a 0.0 factor just draws an empty column
        # rather than a NaN.
        var scale_factor = 1.0
        if plot._stacked_bar_percent:
            var category_total = 0.0
            for j in range(n_series):
                category_total += plot._grouped_bar.values[j][i]
            scale_factor = 100.0 / category_total if category_total > 0.0 else 0.0

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
                _axis_pixel(value_scale, seg_far), _axis_pixel(value_scale, seg_near), baseline_edge
            )
            if theme.svg_tooltips:
                target.begin_annotated_group(
                    _series_tooltip_label(
                        plot.x_categories[i], plot._grouped_bar.series_names[j], v
                    )
                )
            orient.fill_band_rect(target, extent, band_pos, band_size, palette[j % len(palette)])
            if theme.svg_tooltips:
                target.end_annotated_group()
            if theme.show_data_labels:
                var at = orient.band_label_point(extent, band_pos, band_size, sc.font_size)
                text_requests.append(
                    _TextRequest(
                        at.x,
                        at.y,
                        _format_fixed(v, _label_decimals(v)),
                        theme.text_color,
                        sc.font_size,
                        TextAlign.CENTER,
                        theme.font_family,
                    )
                )


def _render_stacked_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.STACKED_BAR` plot: the exact same `encode_grouped_
    bar()` data `Mark.GROUPED_BAR` uses (see `_render_grouped_bar`'s docstring for the length-checking this function shares unchanged),
    but each category's series stack as segments on top of each
    other instead of sitting in divided sub-bars side by side -- full
    band width per segment (`_round_to_int(frame.x_scale.band_start(i))`/
    `.bandwidth()`, `Mark.BAR`'s convention), not `GROUPED_BAR`'s `bandwidth / len(series_names)`.

    Mixed-sign values stack in two independent running totals per
    category, not one -- a non-negative value's segment sits on top
    of that category's running *positive* total (then extends it);
    a negative value's segment sits below the running *negative*
    total (then extends that instead), the same convention most
    charting libraries use for a mixed-sign stack: positive segments
    build upward from zero, negative segments build downward from zero,
    independently, rather than one single running sum where a negative
    value part-way through the stack would slide every segment above it
    back down (visually nonsensical for a composition chart, whose
    whole point is showing how positive parts sum to a positive whole
    and negative parts to a negative one). The y-domain (`_zero_
    baseline_y_extent`, computed over every category's *final*
    positive/negative running total, not the raw per-segment values
    directly -- those final totals are always the most extreme point
    each direction reaches) is computed in a first pass over the data;
    the second, drawing pass recomputes the same running totals again
    (cheap -- at most a handful of series) rather than storing them,
    since the first pass only needed each category's *final* total,
    not the intermediate per-segment values along the way.

    No extra pixel-boundary-rounding trick is needed the way `Mark.
    GROUPED_BAR`'s sub-bar division needed one: a segment's top
    and the segment above it's bottom are always the *identical*
    Float64 running-total value (the running total carries over exactly
    from one segment to the next), so `_axis_pixel` -- a pure,
    deterministic function of its input -- rounds both to the identical
    pixel automatically. `GROUPED_BAR`'s sub-bar edges don't have
    that property (each is a genuinely different band-relative offset
    computed independently), which is exactly why *that* function needs
    the "round the boundary once, reuse it" technique and this one
    doesn't.

    Same legend as `Mark.GROUPED_BAR` (series name -> color, reserved
    by shrinking the outer `ox1` before calling `_draw_categorical_
    axis_frame`) -- and literally the same code: `_series_legend_
    reserve`, imported from grouped_bar.mojo alongside `_validate_
    grouped_bar_series` -- see that function's docstring for why
    sharing beats duplicating here. No sign-coloring
    -- like `GROUPED_BAR`, a stacked bar chart's whole point is telling
    series apart by color, not sign.

    `Theme.show_data_labels` draws each segment's own value centered
    *inside* it (not above/below the way `Mark.BAR`/`GROUPED_BAR`'s
    labels sit -- a stacked segment usually has neighbors directly
    above/below it, so there's no clear outside edge) -- see `Theme.
    show_data_labels`'s own docstring.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var n_series = len(plot._grouped_bar.series_names)
    _validate_stacked_bar_percent(plot, n_series)
    var y_scale = _stacked_bar_domain(plot, n_series)

    var sc = _Scaled(theme)
    var legend_reserve = _series_legend_reserve(plot, sc)
    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()
    _draw_stacked_segments(
        target, plot, frame.x_scale, frame.y_scale, frame.py1, _Orientation(False), palette,
        frame.text_requests,
    )

    if theme.show_legend:
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


def _render_horizontal_stacked_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """`_render_stacked_bar`'s mirror image for `Plot.mark_stacked_bar(
    horizontal=True)` (#121) -- exactly `_render_horizontal_bar`'s own
    categorical y-axis / zero-baseline (or fixed `[0, 100]` for
    `percent=True`) x-axis (`_draw_horizontal_categorical_axis_frame`,
    gantt.mojo, shared -- see that function's docstring), but each
    category's row stacks its series' segments left-to-right instead
    of bottom-to-top -- full band *height* per segment (`frame.y_scale.
    band_start(i)`/`.bandwidth()`) instead of `_render_stacked_bar`'s
    full band *width*, otherwise the identical two-independent-running-
    totals-per-category logic that function's own docstring explains
    (mixed-sign values, `percent=True`'s per-category rescale, the
    "running totals share an exact Float64 boundary so no extra
    pixel-rounding trick is needed" property) -- unchanged here since
    none of it depends on which axis is which.

    Deliberately its own function, not an orientation flag threaded
    through `_render_stacked_bar` -- see `_render_horizontal_bar`'s own
    docstring (bar.mojo) for the full reasoning, identical here.

    Same legend placement as `_render_horizontal_grouped_bar`'s own
    (`frame.px1 + margin_right`, `frame.py0`) -- see that function's
    docstring for why `frame.py0` replaces `_render_stacked_bar`'s own
    `frame.y_scale.range_max` here.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var n_series = len(plot._grouped_bar.series_names)
    _validate_stacked_bar_percent(plot, n_series)
    var x_scale = _stacked_bar_domain(plot, n_series)

    var sc = _Scaled(theme)
    var legend_reserve = _series_legend_reserve(plot, sc)
    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()
    _draw_stacked_segments(
        target, plot, frame.y_scale, frame.x_scale, frame.px0, _Orientation(True), palette,
        frame.text_requests,
    )

    if theme.show_legend:
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
    """A stacked bar chart -- `Mark.STACKED_BAR`, the exact same
    `(categories, series_names, values)` shape `grouped_bar()` takes,
    each series drawn as a stacked segment instead of a side-by-side
    sub-bar. See `Plot.mark_stacked_bar()`'s own docstring for what
    `percent=True` does.

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
    var plot = Plot().mark_stacked_bar(percent=percent, horizontal=horizontal).encode_grouped_bar(
        categories=categories, series_names=series_names, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


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
    """`stacked_bar()`, generalized over numeric element type for
    `values` -- see `grouped_bar()`'s own `DType`-generic overload for
    the full reasoning. Delegates to the concrete `stacked_bar()`
    above.
    """
    return stacked_bar(
        categories, series_names, _materialize_nested_scalar_list(values), theme=theme, width=width,
        height=height, title=title, subtitle=subtitle, x_title=x_title, y_title=y_title, percent=percent,
        horizontal=horizontal,
    )
