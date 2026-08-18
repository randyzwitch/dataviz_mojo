"""Mark.GROUPED_BAR's own rendering -- see Plot.mark_grouped_bar()'s
own docstring (plot.mojo) for what the mark means; `_render_grouped_
bar` is what `_render_generic` (plot.mojo) dispatches to.
"""

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _draw_legend,
    _dynamic_legend_width,
    _empty_result,
    _zero_baseline_y_extent,
)
from dataviz_mojo.theme import Theme


def _validate_grouped_bar_series(plot: Plot) raises:
    """`Plot.encode_grouped_bar()`'s own deferred length checks --
    `series_names`/`values` the same length, and every `values[j]` the
    same length as `categories` (see that method's own docstring in
    plot.mojo for why they're deferred to render() time rather than
    raised there).

    Lives here, next to `Mark.GROUPED_BAR`'s own rendering, and is
    imported by stacked_bar.mojo rather than duplicated into it: both
    marks are drawn from the exact same `encode_grouped_bar()` data
    (only the drawing differs -- see `_render_stacked_bar`'s own
    docstring), so they necessarily have the identical thing to check,
    and had carried verbatim copies of it. `Mark.STACKED_BAR` already
    depends on `Mark.GROUPED_BAR` conceptually for its whole data
    shape; making that a real import keeps the two from drifting the
    way the continuous render paths did.
    """
    if len(plot._grouped_bar_series_names) != len(plot._grouped_bar_values):
        raise Error(
            "Plot.encode_grouped_bar(): series_names and values must have"
            " the same length (got "
            + String(len(plot._grouped_bar_series_names))
            + " and "
            + String(len(plot._grouped_bar_values))
            + ")"
        )
    for j in range(len(plot._grouped_bar_values)):
        if len(plot._grouped_bar_values[j]) != len(plot.x_categories):
            raise Error(
                "Plot.encode_grouped_bar(): every series' own values must"
                " have the same length as categories (series "
                + String(j)
                + " has "
                + String(len(plot._grouped_bar_values[j]))
                + ", categories has "
                + String(len(plot.x_categories))
                + ")"
            )


def _series_legend_reserve(plot: Plot, sc: _Scaled) raises -> Int:
    """How much width the series-name legend `Mark.GROUPED_BAR`/
    `STACKED_BAR` both draw needs, or `0` when `Theme.show_legend` is
    off -- the other thing those two carried identical copies of.
    Subtracted from the *outer* `ox1` before
    `_draw_categorical_axis_frame` is called, the same "shrink the rect
    from outside, don't thread a flag through the shared core" pattern
    `_apply_labels` established (see `_render_grouped_bar`'s own
    docstring).
    """
    if not plot._theme.show_legend:
        return 0
    return _dynamic_legend_width(plot._grouped_bar_series_names, sc.legend_swatch_size, sc)


def _render_grouped_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.GROUPED_BAR` plot: `_render_bar`'s own categorical
    x-axis / zero-baseline y-axis (`_draw_categorical_axis_frame`,
    shared -- see its own docstring), but each category's own band is
    subdivided into `len(series_names)` equal-width sub-bars, one per
    series, side by side, instead of one bar spanning the whole band.
    `default_categorical_palette()` colors each series (cycled `j %
    len(palette)`, the same convention `Mark.POINT`'s own categorical
    color encoding and `Mark.ARC`'s own wedge coloring already use) --
    unlike `Mark.BAR`'s own `Theme.color_by_sign`, there's no sign here
    to color by; the whole point of a *grouped* bar chart is telling
    series apart by color, not telling positive from negative.

    Sub-bar boundaries are computed as `_round_to_int(band_start + j *
    sub_width)` for each `j` from `0` to `len(series_names)` (`len(
    series_names) + 1` boundary points, not `len(series_names)`
    independently-rounded widths) -- rounding each *boundary* once and
    taking consecutive boundaries as a sub-bar's own left/right edges
    guarantees adjacent sub-bars share an exact pixel edge (no 1px gap,
    no 1px overlap), the standard fencepost-safe way to subdivide a
    span into rounded pixel segments; independently rounding each
    sub-bar's own width instead can accumulate exactly that kind of
    off-by-one drift across a whole band.

    The one other new thing no other categorical-x-axis mark needs: a
    legend (series name -> color), reserved via the same `Theme.
    show_legend` flag and `sc.legend_width` column `Mark.POINT`'s own
    categorical color legend uses (see `_render_generic`'s own `show_
    legend`/`legend_reserve` logic) -- but subtracted from the *outer*
    `ox1` passed into `_draw_categorical_axis_frame` rather than
    threaded through that shared function as a new parameter, the same
    "shrink the rect from outside, don't touch the shared core" pattern
    `_apply_labels` already established for `Plot.labels()`'s own
    title/axis-title margins.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var domain_data = List[Float64]()
    for j in range(len(plot._grouped_bar_values)):
        for i in range(len(plot._grouped_bar_values[j])):
            domain_data.append(plot._grouped_bar_values[j][i])
    var y_scale = _zero_baseline_y_extent(domain_data)

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = _series_legend_reserve(plot, sc)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    var palette = default_categorical_palette()
    var n_series = len(plot._grouped_bar_series_names)
    var baseline_py = _axis_pixel(frame.y_scale, 0.0)

    for i in range(len(plot.x_categories)):
        var band_start = frame.x_scale.band_start(i)
        var bandwidth = frame.x_scale.bandwidth()
        var sub_width = bandwidth / Float64(n_series)
        for j in range(n_series):
            var left = _round_to_int(band_start + Float64(j) * sub_width)
            var right = _round_to_int(band_start + Float64(j + 1) * sub_width)
            var top_py = _axis_pixel(frame.y_scale, plot._grouped_bar_values[j][i])
            var bar_y = min(baseline_py, top_py)
            var bar_height = max(baseline_py, top_py) - min(baseline_py, top_py)
            target.fill_rect(left, bar_y, right - left, bar_height, palette[j % len(palette)])

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
