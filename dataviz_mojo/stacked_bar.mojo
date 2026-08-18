"""Mark.STACKED_BAR's own rendering -- see Plot.mark_stacked_bar()'s
own docstring (plot.mojo) for what the mark means; `_render_stacked_
bar` is what `_render_generic` (plot.mojo) dispatches to. Shares
`Plot.encode_grouped_bar()`'s own data shape with Mark.GROUPED_BAR
(see grouped_bar.mojo) -- only the drawing differs.
"""

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.grouped_bar import _series_legend_reserve, _validate_grouped_bar_series
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _draw_legend,
    _empty_result,
    _zero_baseline_y_extent,
)


def _render_stacked_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.STACKED_BAR` plot: the exact same `encode_grouped_
    bar()` data `Mark.GROUPED_BAR` uses (see `_render_grouped_bar`'s own
    docstring for the length-checking this function shares unchanged),
    but each category's own series stack as segments on top of each
    other instead of sitting in divided sub-bars side by side -- full
    band width per segment (`_round_to_int(frame.x_scale.band_start(i))`/
    `.bandwidth()`, `Mark.BAR`'s own convention), not `GROUPED_BAR`'s
    own `bandwidth / len(series_names)`.

    Mixed-sign values stack in two independent running totals per
    category, not one -- a non-negative value's own segment sits on top
    of that category's own running *positive* total (then extends it);
    a negative value's own segment sits below the running *negative*
    total (then extends that instead), the same convention most
    charting libraries use for a mixed-sign stack: positive segments
    build upward from zero, negative segments build downward from zero,
    independently, rather than one single running sum where a negative
    value part-way through the stack would slide every segment above it
    back down (visually nonsensical for a composition chart, whose
    whole point is showing how positive parts sum to a positive whole
    and negative parts to a negative one). The y-domain (`_zero_
    baseline_y_extent`, computed over every category's own *final*
    positive/negative running total, not the raw per-segment values
    directly -- those final totals are always the most extreme point
    each direction reaches) is computed in a first pass over the data;
    the second, drawing pass recomputes the same running totals again
    (cheap -- at most a handful of series) rather than storing them,
    since the first pass only needed each category's own *final* total,
    not the intermediate per-segment values along the way.

    No extra pixel-boundary-rounding trick is needed the way `Mark.
    GROUPED_BAR`'s own sub-bar division needed one: a segment's own top
    and the segment above it's own bottom are always the *identical*
    Float64 running-total value (the running total carries over exactly
    from one segment to the next), so `_axis_pixel` -- a pure,
    deterministic function of its input -- rounds both to the identical
    pixel automatically. `GROUPED_BAR`'s own sub-bar edges don't have
    that property (each is a genuinely different band-relative offset
    computed independently), which is exactly why *that* function needs
    the "round the boundary once, reuse it" technique and this one
    doesn't.

    Same legend as `Mark.GROUPED_BAR` (series name -> color, reserved
    by shrinking the outer `ox1` before calling `_draw_categorical_
    axis_frame`) -- and now literally the same code: `_series_legend_
    reserve`, imported from grouped_bar.mojo alongside `_validate_
    grouped_bar_series`, rather than the verbatim copies of both these
    two used to carry. See `_validate_grouped_bar_series`'s own
    docstring for why sharing beat duplicating here. No sign-coloring
    -- like `GROUPED_BAR`, a stacked bar chart's whole point is telling
    series apart by color, not sign.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var n_series = len(plot._grouped_bar_series_names)
    var domain_data = List[Float64]()
    for i in range(len(plot.x_categories)):
        var pos_total = 0.0
        var neg_total = 0.0
        for j in range(n_series):
            var v = plot._grouped_bar_values[j][i]
            if v >= 0.0:
                pos_total += v
            else:
                neg_total += v
        domain_data.append(pos_total)
        domain_data.append(neg_total)
    var y_scale = _zero_baseline_y_extent(domain_data)

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _series_legend_reserve(plot, sc)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()

    for i in range(len(plot.x_categories)):
        var band_x = _round_to_int(frame.x_scale.band_start(i))
        var band_width = _round_to_int(frame.x_scale.bandwidth())
        var pos_running = 0.0
        var neg_running = 0.0
        for j in range(n_series):
            var v = plot._grouped_bar_values[j][i]
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
            var seg_y = min(top_py, bottom_py)
            var seg_height = max(top_py, bottom_py) - min(top_py, bottom_py)
            target.fill_rect(band_x, seg_y, band_width, seg_height, palette[j % len(palette)])

    if show_legend:
        _draw_legend(
            target,
            frame.text_requests,
            plot._grouped_bar_series_names,
            palette,
            _round_to_int(frame.x_scale.range_max) + sc.margin_right,
            _round_to_int(frame.y_scale.range_max),
            theme,
        )

    return frame.result()
