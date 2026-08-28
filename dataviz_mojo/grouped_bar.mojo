from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

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
    _pull_off_axis_line,
    _finished,
    _zero_baseline_y_extent,
)
from dataviz_mojo.theme import Theme


def _validate_grouped_bar_series(plot: Plot) raises:
    """`Plot.encode_grouped_bar()`'s deferred length checks --
    `series_names`/`values` the same length, and every `values[j]` the
    same length as `categories` (see that method's docstring in
    plot.mojo for why they're deferred to render() time rather than
    raised there).

    Lives here, next to `Mark.GROUPED_BAR`'s rendering, and is
    imported by stacked_bar.mojo rather than duplicated into it: both
    marks are drawn from the exact same `encode_grouped_bar()` data
    (only the drawing differs -- see `_render_stacked_bar`'s docstring), so they necessarily have the identical thing to
    check. `Mark.STACKED_BAR` already depends on `Mark.GROUPED_BAR`
    conceptually for its whole data shape; a real import keeps the two
    from drifting apart.
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


def _series_legend_reserve(plot: Plot, sc: _Scaled) raises -> Int:
    """How much width the series-name legend `Mark.GROUPED_BAR`/
    `STACKED_BAR` both draw needs, or `0` when `Theme.show_legend` is
    off -- shared here for the same reason `_validate_grouped_bar_
    series` is (see that function's docstring). Subtracted from the
    *outer* `ox1` before
    `_draw_categorical_axis_frame` is called, the same "shrink the rect
    from outside, don't thread a flag through the shared core" pattern
    `_apply_labels` established (see `_render_grouped_bar`'s docstring).
    """
    if not plot._theme.show_legend:
        return 0
    return _dynamic_legend_width(plot._grouped_bar.series_names, sc.legend_swatch_size, sc)


def _render_grouped_bar[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.GROUPED_BAR` plot: `_render_bar`'s categorical
    x-axis / zero-baseline y-axis (`_draw_categorical_axis_frame`,
    shared -- see its docstring), but each category's band is
    subdivided into `len(series_names)` equal-width sub-bars, one per
    series, side by side, instead of one bar spanning the whole band.
    `default_categorical_palette()` colors each series (cycled `j %
    len(palette)`, the same convention `Mark.POINT`'s categorical
    color encoding and `Mark.ARC`'s wedge coloring already use) --
    unlike `Mark.BAR`'s `Theme.color_by_sign`, there's no sign here
    to color by; the whole point of a *grouped* bar chart is telling
    series apart by color, not telling positive from negative.

    Sub-bar boundaries round each *boundary* pixel once (`len(
    series_names) + 1` boundary points, not `len(series_names)`
    independently-rounded widths) and take consecutive boundaries as a
    sub-bar's left/right edges, guaranteeing adjacent sub-bars share an
    exact pixel edge (no 1px gap, no 1px overlap) -- the standard
    fencepost-safe way to subdivide a span into rounded pixel segments;
    independently rounding each sub-bar's width instead can accumulate
    exactly that kind of off-by-one drift across a whole band.

    The one other new thing no other categorical-x-axis mark needs: a
    legend (series name -> color), reserved via the same `Theme.
    show_legend` flag and `sc.legend_width` column `Mark.POINT`'s categorical color legend uses (see `_render_generic`'s `show_
    legend`/`legend_reserve` logic) -- but subtracted from the *outer*
    `ox1` passed into `_draw_categorical_axis_frame` rather than
    threaded through that shared function as a new parameter -- the
    same "shrink the rect from outside, don't touch the shared core"
    pattern `_apply_labels` uses for `Plot.labels()`'s title/axis-title
    margins.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

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
    var n_series = len(plot._grouped_bar.series_names)
    var baseline_py = _axis_pixel(frame.y_scale, 0.0)

    var sub_width = frame.x_scale.bandwidth() / Float64(n_series)
    for i in range(len(plot.x_categories)):
        var band_start = frame.x_scale.band_start(i)
        for j in range(n_series):
            var left = _round_to_int(band_start + Float64(j) * sub_width)
            var right = _round_to_int(band_start + Float64(j + 1) * sub_width)
            var top_py = _axis_pixel(frame.y_scale, plot._grouped_bar.values[j][i])
            var rect = _pull_off_axis_line(baseline_py, top_py, frame.py1)
            target.fill_rect(left, rect.y, right - left, rect.height, palette[j % len(palette)])

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
) raises -> Plot:
    """A grouped bar chart -- `Mark.GROUPED_BAR`, several bars side
    by side per category, one per series (`values[j]` is series
    `series_names[j]`'s value per category). See `Plot.
    encode_grouped_bar()`'s docstring (plot.mojo) for the exact
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

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.
    """
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(
        categories=categories, series_names=series_names, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
