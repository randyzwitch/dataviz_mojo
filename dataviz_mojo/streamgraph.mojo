from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.grouped_bar import _validate_grouped_bar_series
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
    _rendered,
)
from dataviz_mojo.scale import LinearScale
from dataviz_mojo.theme import Theme


def _symmetric_zero_baseline_y_extent(values: List[List[Float64]], n_categories: Int) raises -> LinearScale:
    """The y-domain for `Mark.STREAMGRAPH`: symmetric around 0, wide
    enough for the *tallest* category's full stack -- `max_total`,
    the largest per-category sum across every series (`_render_
    streamgraph`'s per-category baseline is `-total_i / 2`, so a
    shorter category's band just doesn't use the full vertical
    span, the "wavy river narrowing" look a streamgraph is for). The
    same "forced symmetric, not independently padded" reasoning `Mark.
    POPULATION_PYRAMID`'s `_symmetric_zero_baseline_x_extent`
    already gives, just for a stacked total instead of two independent
    magnitudes -- both exist so unrelated rows/categories still read on
    one shared, honest scale.
    """
    var max_total = 0.0
    for i in range(n_categories):
        var total = 0.0
        for series in values:
            total += series[i]
        max_total = max(max_total, total)
    var pad = max_total * 0.05 if max_total > 0.0 else 1.0
    var bound = max_total / 2.0 + pad
    return LinearScale(-bound, bound, 0.0, 1.0)


def _render_streamgraph[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.STREAMGRAPH` plot: `encode_grouped_bar()`'s data (categories, one name and one value per series) stacked the
    same running-total way `Mark.STACKED_BAR` already does, but two
    things differ. First, each category's stack starts from `-total_
    i / 2` (`_symmetric_zero_baseline_y_extent`'s per-category
    baseline), not a shared zero, so the whole stack floats centered
    around zero instead of sitting on a fixed baseline -- the
    "silhouette" look. Second, each series is drawn as one *flowing
    band* connecting every category's top/bottom edge in turn
    (straight `line_to` segments between category centers, not curved
    -- deliberately not reusing `Mark.LINE`'s `Theme.line_
    smoothing`-aware path builder, to keep the polygon-closing logic
    here simple; a smoothed variant is a real, separate enhancement,
    not part of what this mark needs to exist at
    all), filled via `DrawTarget.fill_path_aa` -- not `Mark.STACKED_
    BAR`'s one-rect-per-category-per-series.

    Every value must be non-negative -- same reasoning `Mark.ARC`/
    `FUNNEL` already give: a negative flow has no meaning as a stacked
    band's height.

    Reuses `_draw_categorical_axis_frame` (the vertical-categorical-x/
    continuous-y core `Mark.BAR`/`GROUPED_BAR`/`STACKED_BAR` already
    share) unchanged, just fed `_symmetric_zero_baseline_y_extent`'s domain instead of `_zero_baseline_y_extent`'s fixed-at-zero one.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var n_series = len(plot._grouped_bar.series_names)
    var n_categories = len(plot.x_categories)

    for series in plot._grouped_bar.values:
        for v in series:
            if v < 0.0:
                raise Error("Plot: Mark.STREAMGRAPH values must be non-negative (got " + String(v) + ")")

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend_reserve = (
        _dynamic_legend_width(plot._grouped_bar.series_names, sc.legend_swatch_size, sc) if show_legend else 0
    )

    var y_scale = _symmetric_zero_baseline_y_extent(plot._grouped_bar.values, n_categories)
    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1 - legend_reserve, oy1
    )

    # running[i]: each category's stack cursor, starting at its centered baseline (-total_i / 2) and advancing upward series by
    # series -- the same running-total bookkeeping style Mark.WATERFALL/
    # STACKED_BAR already use, just per-category here instead of a
    # single shared one.
    var running = List[Float64]()
    for i in range(n_categories):
        var total = 0.0
        for series in plot._grouped_bar.values:
            total += series[i]
        running.append(-total / 2.0)

    var palette = default_categorical_palette()
    for j in range(n_series):
        var path = Path()
        var top = List[Float64](capacity=n_categories)
        var bottom = List[Float64](capacity=n_categories)
        for i in range(n_categories):
            bottom.append(running[i])
            running[i] += plot._grouped_bar.values[j][i]
            top.append(running[i])

        path.move_to(frame.x_scale.center(0), Float64(_axis_pixel(frame.y_scale, top[0])))
        for i in range(1, n_categories):
            path.line_to(frame.x_scale.center(i), Float64(_axis_pixel(frame.y_scale, top[i])))
        for i in range(n_categories - 1, -1, -1):
            path.line_to(frame.x_scale.center(i), Float64(_axis_pixel(frame.y_scale, bottom[i])))
        path.close()
        target.fill_path_aa(path, palette[j % len(palette)])

    if show_legend:
        _draw_legend(
            target, frame.text_requests, plot._grouped_bar.series_names, palette,
            _round_to_int(frame.x_scale.range_max) + sc.margin_right, _round_to_int(frame.y_scale.range_max), theme,
        )

    return frame.result()


def streamgraph(
    categories: List[String],
    series_names: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
) raises -> Canvas:
    """A streamgraph -- `Mark.STREAMGRAPH`, `Mark.STACKED_BAR`'s running-total stack, floated centered around zero instead of
    sitting on a fixed baseline, and drawn as flowing bands instead of
    discrete rects. Same data shape `grouped_bar()`/`stacked_bar()`/
    `bump()` all take."""
    var plot = Plot().mark_streamgraph().encode_grouped_bar(
        categories=categories, series_names=series_names, values=values
    )
    return _rendered(plot^, theme, width, height, title, x_title, "", subtitle=subtitle)
