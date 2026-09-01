from std.math import exp, pi, pow, sqrt

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.mark import Mark
from dataviz.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _min_max,
    _finished,
)
from dataviz.theme import Theme

comptime _KDE_SAMPLES = 30


def _kde_bandwidth(values: List[Float64]) -> Float64:
    """Silverman's rule of thumb, the standard default kernel-density-
    estimate bandwidth: `0.9 * std * n^(-1/5)` -- the plain std-only
    version, not the fuller IQR-adjusted variant real stats packages
    default to (`0.9 * min(std, IQR/1.34) * n^(-1/5)`, more robust to
    outliers but needs a second, percentile-based computation on top of
    this one). A deliberate simplification, not an oversight: the
    plain version is exactly as easy to get wrong and much easier to
    hand-verify (mean/variance only, no percentile-interpolation
    formula alongside it) -- revisit if a real skewed-distribution case
    ever needs the more robust one.

    Falls back to a fixed `1.0` when `std` comes out `<= 0.0` (a single
    value, or every value identical) -- the formula would otherwise
    collapse the whole kernel to a single infinitely-narrow spike
    (equivalent to dividing by zero in `_kde_density`'s formula),
    not a meaningful "no spread" answer to draw.
    """
    var n = len(values)
    var mean = 0.0
    for v in values:
        mean += v
    mean /= Float64(n)
    var variance = 0.0
    for v in values:
        variance += (v - mean) * (v - mean)
    variance /= Float64(n)
    var std = sqrt(variance)
    if std <= 0.0:
        return 1.0
    return 0.9 * std * Float64(n) ** (-1.0 / 5.0)


def _kde_density(values: List[Float64], bandwidth: Float64, y: Float64) -> Float64:
    """The Gaussian-kernel density estimate at `y`: the average, over
    every one of `values`' points, of a standard normal curve
    centered on that point and scaled by `bandwidth` -- the textbook
    KDE formula, `(1 / (n*h)) * sum(gaussian((y - v_i) / h))`.
    """
    var n = len(values)
    var sum_density = 0.0
    for v in values:
        var u = (y - v) / bandwidth
        sum_density += exp(-0.5 * u * u) / sqrt(2.0 * pi)
    return sum_density / (Float64(n) * bandwidth)


def _render_violin[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.VIOLIN` plot: `encode_distribution()`'s raw
    per-category values (the same data `Mark.BEESWARM` takes), each
    category drawn as a symmetric density-estimate silhouette instead
    of individual jittered points -- a smoothed, continuous view of the
    same distribution `Mark.BOX`'s five-number summary and `Mark.
    BEESWARM`'s raw points each show a different, coarser or more
    literal way.

    Each violin is sampled at `_KDE_SAMPLES` evenly spaced points across
    its category's `[min(values), max(values)]` -- not the full
    shared y-axis domain -- so the visible shape spans exactly the
    observed data range, the same convention most from-scratch violin
    implementations use (a KDE's tails technically extend forever,
    but drawing them out to the shared axis's padding would just be
    a long, visually meaningless near-zero-width sliver).

    Each violin's width is scaled *independently* -- its peak
    density maps to `theme.violin_width_fraction` of its category's band
    width, not a shared cross-category maximum -- matching ggplot2's default `scale = "width"` behavior (every violin the same
    maximum width, regardless of how many points went into it) rather
    than `scale = "area"` (equal area, proportional peak width). The
    default; `mark_violin()`'s `scale_by_count=True` switches to
    the `scale = "area"` behavior instead, multiplying each category's maximum width by `sqrt(n_i / max(n))` -- see that method's docstring for why.

    Reuses `_draw_categorical_axis_frame` (the same vertical-
    categorical-x/continuous-y core `Mark.BAR`/`BOX`/`BEESWARM` share),
    with `_data_extent` over every value across every category for the
    shared axis domain, the same choice `Mark.BOX`/`BEESWARM` make for
    this data shape.

    `mark_violin()`'s `bandwidth`, when given (checked positive at
    render() time), replaces every category's Silverman's-rule
    `_kde_bandwidth(values)` with one shared value instead -- see that
    method's docstring for why.
    """
    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    if plot._distribution.kde_bandwidth_override < 0.0:
        raise Error(
            "Plot.mark_violin(): bandwidth must be positive (got "
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
    var y_scale = _data_extent(all_values)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var half_width = frame.x_scale.bandwidth() * theme.violin_width_fraction

    for i in range(len(plot.x_categories)):
        var values = plot._distribution.values[i].copy()
        var center_x = frame.x_scale.center(i)
        var count_factor = sqrt(Float64(len(values)) / Float64(max_n)) if (
            plot._distribution.kde_scale_by_count and max_n > 0
        ) else 1.0
        var bandwidth = plot._distribution.kde_bandwidth_override if plot._distribution.kde_bandwidth_override > 0.0 else _kde_bandwidth(
            values
        )
        var mm = _min_max(values)

        var densities = List[Float64](capacity=_KDE_SAMPLES)
        var y_values = List[Float64](capacity=_KDE_SAMPLES)
        var max_density = 0.0
        var span = mm.max - mm.min
        for s in range(_KDE_SAMPLES):
            var y_value = mm.min if span == 0.0 else mm.min + span * Float64(s) / Float64(_KDE_SAMPLES - 1)
            var d = _kde_density(values, bandwidth, y_value)
            y_values.append(y_value)
            densities.append(d)
            max_density = max(max_density, d)

        var path = Path()
        var scale = (half_width * count_factor) / max_density if max_density > 0.0 else 0.0
        path.move_to(center_x + densities[0] * scale, Float64(_axis_pixel(frame.y_scale, y_values[0])))
        for s in range(1, _KDE_SAMPLES):
            path.line_to(
                center_x + densities[s] * scale, Float64(_axis_pixel(frame.y_scale, y_values[s]))
            )
        for s in range(_KDE_SAMPLES - 1, -1, -1):
            path.line_to(
                center_x - densities[s] * scale, Float64(_axis_pixel(frame.y_scale, y_values[s]))
            )
        path.close()
        target.fill_path_aa(path, theme.mark_color)

    return frame.result()


def violin(
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
    """A violin plot -- `Mark.VIOLIN`, a symmetric kernel-density-
    estimate silhouette per category (`bandwidth`, left at its default
    `0.0`, overrides every category's Silverman's-rule bandwidth
    with one shared value; `scale_by_count`, left at its default
    `False`, switches from ggplot2's `scale = "width"` to `scale =
    "area"` -- see `Plot.mark_violin()`'s docstring for both). See
    `Plot.encode_distribution()`'s docstring (plot.mojo) for the
    exact shape (the same one `beeswarm()`/`ridgeline()` take).

    Args:
        categories: One silhouette per entry, in the given order.
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

    Example:
        ```mojo
        from dataviz import violin
        from dataviz.plot import save

        def main() raises:
            var classes: List[String] = ["Section A", "Section B", "Section C"]
            var scores: List[List[Int]] = [
                [72, 75, 78, 80, 74, 76, 91],
                [65, 70, 72, 88, 90, 92, 95],
                [80, 82, 83, 84, 81, 79, 85],
            ]

            var c = violin(classes, scores)
            save(c, "docs/src/examples/out_violin.svg")
        ```
    """
    var plot = Plot().mark_violin(bandwidth=bandwidth, scale_by_count=scale_by_count).encode_distribution(
        categories=categories, values=values
    )
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def violin[
    dtype: DType
](
    categories: List[String],
    values: List[List[Scalar[dtype]]],
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
    """`violin()`, generalized over numeric element type for
    `values` -- see `beeswarm()`'s own `DType`-generic overload for
    the full reasoning. Delegates to the concrete `violin()` above.
    """
    return violin(
        categories, _materialize_nested_scalar_list(values), bandwidth=bandwidth,
        scale_by_count=scale_by_count, theme=theme, width=width, height=height, title=title,
        subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
