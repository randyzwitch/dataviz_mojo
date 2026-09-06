from std.math import sqrt

from canvas.text.font_cache import FontCache
from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.plot import (
    Plot,
    _RenderResult,
    _axis_pixel_f,
    _data_extent,
    _min_max,
    _finished,
)
from dataviz.theme import Theme
from dataviz.violin import _KDE_SAMPLES, _kde_bandwidth, _kde_density


def _render_ridgeline[
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
    """Render a `Mark.RIDGELINE` plot: the same per-category kernel-density
    estimate `Mark.VIOLIN` computes (`_kde_bandwidth`/`_kde_density`/
    `_KDE_SAMPLES`, from violin.mojo), drawn as one row per category on
    `_draw_horizontal_categorical_axis_frame` (categories along `y`, top
    to bottom; continuous `x` along the bottom), each curve rising upward
    from its row's bottom edge. The frame is built with `padding=0.0` so
    rows sit edge-to-edge; any gap would show as a notch between rows.

    Each row's curve may rise up to `plot._mark_style.ridgeline_overlap`
    times the row height, so a tall peak overlaps into the row above. Rows
    are drawn top to bottom in `x_categories`' order, so where two
    overlap, the lower row is on top.

    Each category's density is scaled to its own peak (ggplot2's
    `scale = "width"`), or by `sqrt(n_i / max(n))` on top of that when
    `mark_ridgeline(scale_by_count=True)` (`scale = "area"`), the same as
    `mark_violin()`. `mark_ridgeline()`'s `bandwidth`, when positive,
    replaces every category's Silverman's-rule `_kde_bandwidth(values)`
    with one shared value.
    """
    var theme = plot._theme
    if plot._distribution.kde_bandwidth_override < 0.0:
        raise Error(
            "Plot.mark_ridgeline(): bandwidth must be positive (got "
            + String(plot._distribution.kde_bandwidth_override)
            + ")"
        )

    var all_values = List[Float64]()
    var max_n = 0
    for series in plot._distribution.values:
        if len(series) > max_n:
            max_n = len(series)
        for v in series:
            all_values.append(v)
    var x_scale = _data_extent(all_values)

    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot.x_categories,
        x_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        padding=0.0,
        cache=cache,
    )

    var row_height = frame.y_scale.bandwidth()
    var max_rise = row_height * plot._mark_style.ridgeline_overlap

    for i in range(len(plot.x_categories)):
        var values = plot._distribution.values[i].copy()
        var baseline_y = frame.y_scale.band_start(i) + row_height
        # The bottom-most row's baseline lands exactly on the drawn bottom axis
        # line (padding=0.0 tiles rows edge to edge). Pulled 1px up so the
        # curve's flat closing edge doesn't paint over the line's antialiasing,
        # the same `_pull_off_axis_line` reasoning (frame.mojo).
        if abs(baseline_y - Float64(frame.py1)) < 0.5:
            baseline_y -= 1.0
        var count_factor = sqrt(Float64(len(values)) / Float64(max_n)) if (
            plot._distribution.kde_scale_by_count and max_n > 0
        ) else 1.0
        var bandwidth = (
            plot._distribution.kde_bandwidth_override if plot._distribution.kde_bandwidth_override
            > 0.0 else _kde_bandwidth(values)
        )
        var mm = _min_max(values)

        var xs = List[Float64](capacity=_KDE_SAMPLES)
        var densities = List[Float64](capacity=_KDE_SAMPLES)
        var max_density = 0.0
        var span = mm.max - mm.min
        for s in range(_KDE_SAMPLES):
            var value = mm.min if span == 0.0 else mm.min + span * Float64(
                s
            ) / Float64(_KDE_SAMPLES - 1)
            var d = _kde_density(values, bandwidth, value)
            xs.append(_axis_pixel_f(frame.x_scale, value))
            densities.append(d)
            max_density = max(max_density, d)

        var scale = (
            max_rise * count_factor
        ) / max_density if max_density > 0.0 else 0.0
        var path = Path()
        path.move_to(xs[0], baseline_y)
        for s in range(_KDE_SAMPLES):
            path.line_to(xs[s], baseline_y - densities[s] * scale)
        path.line_to(xs[_KDE_SAMPLES - 1], baseline_y)
        path.close()
        target.fill_path_aa(path, theme.mark_color, fill_rule=FillRule.NONZERO)

    return frame.result()


def ridgeline(
    categories: List[String],
    values: List[List[Float64]],
    bandwidth: Float64 = 0.0,
    scale_by_count: Bool = False,
    overlap: Float64 = 1.3,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A ridgeline plot, popularized as the "joyplot" after the cover of
    Joy Division's Unknown Pleasures album: one density-estimate curve
    per category, stacked with a slight vertical overlap, for comparing
    many distributions' shapes at once without a box plot's information
    loss.

    `Mark.RIDGELINE`: one overlapping density-estimate row per category,
    top to bottom. `bandwidth` (when positive) overrides every category's
    Silverman's-rule bandwidth with one shared value; `scale_by_count=True`
    switches from ggplot2's `scale = "width"` to `scale = "area"` (see
    `Plot.mark_violin()`). See `Plot.encode_distribution()` (plot.mojo)
    for the data shape, shared with `beeswarm()`/`violin()`.

    Args:
        categories: One overlapping density row per entry, top to
            bottom.
        values: Each category's raw values (`values[i]`) -- the
            density estimate is computed from these, not passed in
            directly.
        bandwidth: Overrides every category's Silverman's-rule
            kernel-density bandwidth with one shared value; must be
            positive if given. Left at its default `0.0`, each
            category gets its own Silverman's-rule bandwidth.
        scale_by_count: `False` (the default, ggplot2's `scale =
            "width"`) gives every category's peak the same maximum
            width; `True` (`scale = "area"`) additionally scales a
            category's maximum width by `sqrt(n_i / max(n))`, so one
            built from fewer raw values draws visibly narrower.
        overlap: How far each row rises into the rows above, as a multiple
            of row height; defaults to `1.3`.
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

    Example:
        ```mojo
        from dataviz import ridgeline
        from dataviz.plot import save

        def main() raises:
            var months: List[String] = ["June", "July", "August", "September"]
            var temps: List[List[Int]] = [
                [68, 70, 72, 74, 71, 69, 75, 73],
                [78, 80, 82, 85, 79, 81, 83, 84],
                [80, 82, 84, 86, 81, 83, 85, 87],
                [70, 72, 74, 76, 71, 73, 75, 69],
            ]

            var c = ridgeline(months, temps)
            save(c, "docs/src/examples/out_ridgeline.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_ridgeline(
            bandwidth=bandwidth, scale_by_count=scale_by_count, overlap=overlap
        )
        .encode_distribution(categories=categories, values=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def ridgeline[
    dtype: DType
](
    categories: List[String],
    values: List[List[Scalar[dtype]]],
    bandwidth: Float64 = 0.0,
    scale_by_count: Bool = False,
    overlap: Float64 = 1.3,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`ridgeline()` generalized over numeric element type for `values`; see
    `beeswarm()`'s `DType` overload. Delegates to the concrete overload
    above.
    """
    return ridgeline(
        categories,
        _materialize_nested_scalar_list(values),
        bandwidth=bandwidth,
        scale_by_count=scale_by_count,
        overlap=overlap,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
