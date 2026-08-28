from std.math import sqrt

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.gantt import _draw_horizontal_categorical_axis_frame
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _empty_result,
    _min_max,
    _finished,
)
from dataviz_mojo.theme import Theme
from dataviz_mojo.violin import _KDE_SAMPLES, _kde_bandwidth, _kde_density


def _render_ridgeline[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.RIDGELINE` plot: the exact same per-category
    kernel-density estimate `Mark.VIOLIN` computes (`_kde_bandwidth`/
    `_kde_density`, reused unchanged from violin.mojo), but drawn as
    one row per category on a *horizontal* categorical frame instead
    of a vertical one -- `_draw_horizontal_categorical_axis_frame`
    (`Mark.GANTT`'s core: categories along `y`, top to bottom; a
    continuous `x` for the value domain along the bottom), each
    category's curve rising *upward* from its row's bottom
    edge (the baseline) instead of `Mark.VIOLIN`'s left-right-symmetric
    silhouette. Called with `padding=0.0`, *not* that function's 0.2
    default: a ridgeline plot needs rows to sit edge-to-edge (any
    nonzero gap leaves a sliver of background between rows, only
    inconsistently covered by `theme.ridgeline_overlap`'s rise, which
    reads as a spurious notch).

    Each row's curve may rise up to `theme.ridgeline_overlap` times the
    row's height above its baseline -- deliberately more than
    one row tall, so a tall category's peak overlaps into the row
    above it. Categories are drawn top to bottom, in `x_categories`' given order (not reordered by value the way `Mark.FUNNEL`
    sorts) -- since a later (lower) row is drawn *after* an earlier
    (higher) one, a lower row's curve is what's on top wherever
    two overlap, the same "later in the list, closer to the viewer"
    reading real ridgeline/joyplot charts conventionally use.

    Each category's density is still independently scaled to its peak (not a shared cross-category maximum) -- the same
    `scale = "width"`-style reasoning `Mark.VIOLIN`'s docstring
    gives, applied to height instead of width here. `mark_ridgeline()`'s `scale_by_count=True` switches to `scale = "area"` the same way
    `mark_violin()`'s does -- see that method's docstring.

    Reuses `Mark.VIOLIN`'s `_kde_bandwidth`/`_kde_density` and
    `_KDE_SAMPLES` sample count completely unchanged -- only the axis
    orientation and the curve's baseline/direction differ.

    `mark_ridgeline()`'s `bandwidth`, when given (checked positive
    at render() time), replaces every category's Silverman's-rule
    `_kde_bandwidth(values)` with one shared value instead -- the same
    override `Mark.VIOLIN` shares, see `mark_violin()`'s docstring.
    """
    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

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
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1, oy1, padding=0.0
    )

    var row_height = frame.y_scale.bandwidth()
    var max_rise = row_height * theme.ridgeline_overlap

    for i in range(len(plot.x_categories)):
        var values = plot._distribution.values[i].copy()
        var baseline_y = frame.y_scale.band_start(i) + row_height
        # The bottom-most row's baseline lands exactly on the drawn
        # bottom axis line (padding=0.0 above tiles every row edge to
        # edge, and this is the last one) -- pulled 1px up so a tall
        # enough curve's flat closing edge doesn't paint over the
        # line's own antialiasing, the same `_pull_off_axis_line`
        # reasoning (plot.mojo) applied to this fill's flat lower
        # boundary instead of a rect edge.
        if _round_to_int(baseline_y) == frame.py1:
            baseline_y -= 1.0
        var count_factor = sqrt(Float64(len(values)) / Float64(max_n)) if (
            plot._distribution.kde_scale_by_count and max_n > 0
        ) else 1.0
        var bandwidth = plot._distribution.kde_bandwidth_override if plot._distribution.kde_bandwidth_override > 0.0 else _kde_bandwidth(
            values
        )
        var mm = _min_max(values)

        var xs = List[Int](capacity=_KDE_SAMPLES)
        var densities = List[Float64](capacity=_KDE_SAMPLES)
        var max_density = 0.0
        var span = mm.max - mm.min
        for s in range(_KDE_SAMPLES):
            var value = mm.min if span == 0.0 else mm.min + span * Float64(s) / Float64(_KDE_SAMPLES - 1)
            var d = _kde_density(values, bandwidth, value)
            xs.append(_axis_pixel(frame.x_scale, value))
            densities.append(d)
            max_density = max(max_density, d)

        var scale = (max_rise * count_factor) / max_density if max_density > 0.0 else 0.0
        var path = Path()
        path.move_to(Float64(xs[0]), baseline_y)
        for s in range(_KDE_SAMPLES):
            path.line_to(Float64(xs[s]), baseline_y - densities[s] * scale)
        path.line_to(Float64(xs[_KDE_SAMPLES - 1]), baseline_y)
        path.close()
        target.fill_path_aa(path, theme.mark_color)

    return frame.result()


def ridgeline(
    categories: List[String],
    values: List[List[Float64]],
    bandwidth: Float64 = 0.0,
    scale_by_count: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A ridgeline plot -- `Mark.RIDGELINE`, one overlapping density-
    estimate row per category, top to bottom (`bandwidth`, left at its
    default `0.0`, overrides every category's Silverman's-rule
    bandwidth with one shared value; `scale_by_count`, left at its
    default `False`, switches from ggplot2's `scale = "width"` to
    `scale = "area"` -- see `Plot.mark_violin()`'s docstring for
    both). See `Plot.encode_distribution()`'s docstring (plot.mojo)
    for the exact shape (the same one `beeswarm()`/`violin()` take).

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
    var plot = Plot().mark_ridgeline(bandwidth=bandwidth, scale_by_count=scale_by_count).encode_distribution(
        categories=categories, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
