from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.grouped_bar import _series_legend_reserve, _validate_grouped_bar_series
from dataviz_mojo.mark import Mark
from dataviz_mojo.scale import LinearScale
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _draw_legend,
    _empty_result,
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
)
from dataviz_mojo.theme import Theme


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
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var n_series = len(plot._grouped_bar.series_names)

    if plot._stacked_bar_percent:
        for j in range(n_series):
            for v in plot._grouped_bar.values[j]:
                if v < 0.0:
                    raise Error(
                        "Plot.mark_stacked_bar(percent=True): every value must be >= 0 (a negative"
                        " share has no meaning) -- got " + String(v)
                    )

    var y_scale: LinearScale
    if plot._stacked_bar_percent:
        # Fixed to exactly [0, 100] -- there's no "padding" a
        # percentage the way _zero_baseline_y_extent pads a real-valued
        # domain; every column is definitionally exactly 100% tall, so
        # a padded [0, 105]-ish axis would misrepresent that.
        y_scale = LinearScale(0.0, 100.0, 0.0, 1.0)
    else:
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
        y_scale = _zero_baseline_y_extent(domain_data)

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _series_legend_reserve(plot, sc)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()

    var band_width = _round_to_int(frame.x_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var band_x = _round_to_int(frame.x_scale.band_start(i))
        # percent=True: each category's own total (validated non-
        # negative above, so a plain sum is also that category's own
        # magnitude) rescales its own series values to sum to 100 --
        # every other category's own total is unrelated, so this is
        # recomputed per category, not once for the whole chart. A
        # category whose values are all zero divides by nothing;
        # `scale_factor` of 0.0 in that case just draws every segment
        # at zero height instead (an empty column), not a NaN.
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
            var seg_bottom: Float64
            var seg_top: Float64
            if v >= 0.0:
                seg_bottom = pos_running
                seg_top = pos_running + v
                pos_running = seg_top
            else:
                seg_top = neg_running
                seg_bottom = neg_running + v
                neg_running = seg_bottom
            var top_py = _axis_pixel(frame.y_scale, seg_top)
            var bottom_py = _axis_pixel(frame.y_scale, seg_bottom)
            var rect = _pull_off_axis_line(top_py, bottom_py, frame.py1)
            target.fill_rect(band_x, rect.y, band_width, rect.height, palette[j % len(palette)])

    if show_legend:
        _draw_legend(
            target,
            frame.text_requests,
            plot._grouped_bar.series_names,
            palette,
            _round_to_int(frame.x_scale.range_max) + sc.margin_right,
            _round_to_int(frame.y_scale.range_max),
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

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz_mojo import stacked_bar
        from dataviz_mojo.plot import save

        def main() raises:
            var quarters: List[String] = ["Q1", "Q2", "Q3", "Q4"]
            var series_names: List[String] = ["North", "South", "East"]
            var values: List[List[Float64]] = [
                [42.0, 48.0, 45.0, 61.0],
                [30.0, 35.0, 33.0, 40.0],
                [55.0, 50.0, 58.0, 66.0],
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
    var plot = Plot().mark_stacked_bar(percent=percent).encode_grouped_bar(
        categories=categories, series_names=series_names, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
