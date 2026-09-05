from canvas.fill_rule import FillRule
from canvas.geometry import _round_to_int
from canvas.path import Path
from dataviz.plot import _LazyFontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.color_scale import default_categorical_palette
from dataviz.grouped_bar import _validate_grouped_bar_series
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _axis_pixel,
    _check_line_smoothing,
    _draw_categorical_axis_frame,
    _LegendLayout,
    _draw_legend_at,
    _legend_layout,
    _finished,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


def _symmetric_zero_baseline_y_extent(
    values: List[List[Float64]], n_categories: Int
) raises -> LinearScale:
    """The y-domain for `Mark.STREAMGRAPH`: symmetric around 0, wide enough
    for the tallest category's full stack (`max_total`, the largest
    per-category sum across every series). `_render_streamgraph`'s
    per-category baseline is `-total_i / 2`, so shorter categories don't
    use the full vertical span. Same forced-symmetric idea as
    `Mark.POPULATION_PYRAMID`'s `_symmetric_zero_baseline_x_extent`.
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


def _append_smoothed_edge(
    mut path: Path, px: List[Float64], py: List[Float64], smoothing: Float64
) raises:
    """Append `line_to`/`cubic_curve_to` segments for `px[0]->...->px[n-1]`
    onto `path`, continuing from its current point (no `move_to`). Same
    Catmull-Rom math as `_build_line_path` (plot.mojo), duplicated because
    a streamgraph band runs it twice on one continuous `Path` (top edge,
    then bottom edge) and `_build_line_path` always starts a fresh
    subpath.
    """
    if len(px) <= 1:
        return
    if smoothing <= 0.0:
        for i in range(1, len(px)):
            path.line_to(px[i], py[i])
        return

    var n = len(px)
    for i in range(n - 1):
        var prev = i - 1 if i > 0 else i
        var next2 = i + 2 if i + 2 < n else i + 1
        var t1x = (px[i + 1] - px[prev]) / 6.0 * smoothing
        var t1y = (py[i + 1] - py[prev]) / 6.0 * smoothing
        var t2x = (px[next2] - px[i]) / 6.0 * smoothing
        var t2y = (py[next2] - py[i]) / 6.0 * smoothing
        path.cubic_curve_to(
            px[i] + t1x,
            py[i] + t1y,
            px[i + 1] - t2x,
            py[i + 1] - t2y,
            px[i + 1],
            py[i + 1],
        )


def _render_streamgraph[
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
    """Render a `Mark.STREAMGRAPH` plot: `encode_grouped_bar()`'s data
    stacked the same running-total way as `Mark.STACKED_BAR`, with two
    differences. Each category's stack starts from `-total_i / 2` rather
    than a shared zero, so the whole stack floats centered around zero.
    And each series is drawn as one flowing band connecting every
    category's top/bottom edge in turn, filled via `fill_path_aa`, rather
    than one rect per category.

    `Theme.line_smoothing` curves both the top and bottom edges
    (`_append_smoothed_edge`; `0.0` gives straight segments). The two cap
    edges at the first/last category always stay straight.

    Every value must be non-negative. Reuses `_draw_categorical_axis_frame`
    fed `_symmetric_zero_baseline_y_extent`'s domain.
    """
    _validate_grouped_bar_series(plot)

    var theme = plot._theme
    _check_line_smoothing(theme)
    var n_series = len(plot._grouped_bar.series_names)
    var n_categories = len(plot.x_categories)

    for series in plot._grouped_bar.values:
        for v in series:
            if v < 0.0:
                raise Error(
                    "Plot: Mark.STREAMGRAPH values must be non-negative (got "
                    + String(v)
                    + ")"
                )

    var sc = _Scaled(theme)
    var show_legend = theme.show_legend
    var legend = _legend_layout(
        plot._grouped_bar.series_names,
        sc.legend_swatch_size,
        sc,
        theme,
        ox1 - ox0,
        cache=cache,
    ) if show_legend else _LegendLayout()

    var y_scale = _symmetric_zero_baseline_y_extent(
        plot._grouped_bar.values, n_categories
    )
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

    # running[i]: each category's stack cursor, starting at its centered
    # baseline (-total_i / 2) and advancing upward series by series.
    var running = List[Float64]()
    for i in range(n_categories):
        var total = 0.0
        for series in plot._grouped_bar.values:
            total += series[i]
        running.append(-total / 2.0)

    var palette = default_categorical_palette()
    for j in range(n_series):
        var top = List[Float64](capacity=n_categories)
        var bottom = List[Float64](capacity=n_categories)
        for i in range(n_categories):
            bottom.append(running[i])
            running[i] += plot._grouped_bar.values[j][i]
            top.append(running[i])

        # Top edge in category order, then bottom edge in reverse, so the path
        # traces one closed outline (Catmull-Rom is symmetric, so the reversed
        # bottom edge smooths identically).
        var top_px = List[Float64](capacity=n_categories)
        var top_py = List[Float64](capacity=n_categories)
        for i in range(n_categories):
            top_px.append(frame.x_scale.center(i))
            top_py.append(Float64(_axis_pixel(frame.y_scale, top[i])))
        var bottom_px = List[Float64](capacity=n_categories)
        var bottom_py = List[Float64](capacity=n_categories)
        for i in range(n_categories - 1, -1, -1):
            bottom_px.append(frame.x_scale.center(i))
            bottom_py.append(Float64(_axis_pixel(frame.y_scale, bottom[i])))

        var path = Path()
        path.move_to(top_px[0], top_py[0])
        _append_smoothed_edge(path, top_px, top_py, theme.line_smoothing)
        path.line_to(
            bottom_px[0], bottom_py[0]
        )  # the straight "cap" at the last category
        _append_smoothed_edge(path, bottom_px, bottom_py, theme.line_smoothing)
        path.close()  # the straight "cap" at the first category
        target.fill_path_aa(
            path, palette[j % len(palette)], fill_rule=FillRule.NONZERO
        )

    if show_legend:
        _draw_legend_at(
            target,
            frame.text_requests,
            plot._grouped_bar.series_names,
            palette,
            legend,
            frame.px0,
            frame.py0,
            frame.px1,
            frame.py1,
            theme,
        )

    return frame.result()


def streamgraph(
    categories: List[String],
    series_names: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    smoothing: Float64 = 0.6,
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
) raises -> Plot:
    """A streamgraph: `stacked_bar()`'s running total turned into smooth
    layers and floated around a central axis instead of a fixed zero
    baseline. Popularized by Lee Byron and Martin Wattenberg's 2008 work
    (notably the New York Times' movie box-office chart), for showing how
    several series' magnitudes ebb and flow over time.

    `Mark.STREAMGRAPH`: `Mark.STACKED_BAR`'s running-total stack, floated
    centered around zero and drawn as flowing bands instead of discrete
    rects. Same data shape `grouped_bar()`/`stacked_bar()`/`bump()` take.

    Args:
        categories: One position along the x-axis per entry, in the
            given order.
        series_names: One flowing band per name, used as the legend
            key.
        values: `values[j]` is `series_names[j]`'s value per
            category.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        smoothing: Sets `theme.line_smoothing` -- how much each band's
            edges curve, `[0.0, 1.0]`. Defaults to `0.6`, not `Theme`'s
            own `0.0`: a streamgraph is meant to look like flowing
            water, so unlike `Mark.LINE`/`AREA` (straight by default),
            this one curves unless told not to. Pass `0.0` for the old
            straight-segment bands.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import streamgraph
        from dataviz.plot import save

        def main() raises:
            var years: List[String] = ["2020", "2021", "2022", "2023", "2024"]
            var genres: List[String] = ["Pop", "Rock", "Jazz"]
            var listens: List[List[Int]] = [
                [30, 40, 55, 60, 50],
                [45, 35, 30, 25, 20],
                [10, 15, 12, 18, 25],
            ]

            var c = streamgraph(years, genres, listens)
            save(c, "docs/src/examples/out_streamgraph.svg")
        ```
    """
    var t = theme
    t.line_smoothing = smoothing
    var plot = (
        Plot()
        .mark_streamgraph()
        .encode_grouped_bar(
            categories=categories, series_names=series_names, values=values
        )
    )
    return _finished(
        plot^, t, width, height, title, x_title, "", subtitle=subtitle
    )


def streamgraph[
    dtype: DType
](
    categories: List[String],
    series_names: List[String],
    values: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    smoothing: Float64 = 0.6,
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
) raises -> Plot:
    """`streamgraph()` generalized over numeric element type for `values`;
    see `grouped_bar()`'s `DType` overload. Delegates to the concrete
    overload above.
    """
    return streamgraph(
        categories,
        series_names,
        _materialize_nested_scalar_list(values),
        theme=theme,
        smoothing=smoothing,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
    )
