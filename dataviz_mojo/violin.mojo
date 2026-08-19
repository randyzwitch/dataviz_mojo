from std.math import exp, pi, pow, sqrt

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.path import Path
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _min_max,
    _rendered,
)
from dataviz_mojo.theme import Theme

comptime _KDE_SAMPLES = 30

# Each violin's own max half-width, as a fraction of its category's own
# band width -- fixed, not a Theme field, the same "no concrete need
# for a knob yet" reasoning every other fixed layout constant here
# already follows (_LEGEND_WIDTH, _CHORD_RING_FRACTION, ...).
comptime _VIOLIN_WIDTH_FRACTION = 0.4


def _kde_bandwidth(values: List[Float64]) -> Float64:
    """Silverman's rule of thumb, the standard default kernel-density-
    estimate bandwidth: `0.9 * std * n^(-1/5)` -- the plain std-only
    version, not the fuller IQR-adjusted variant real stats packages
    default to (`0.9 * min(std, IQR/1.34) * n^(-1/5)`, more robust to
    outliers but needs a second, percentile-based computation on top of
    this one). A deliberate v1 simplification, not an oversight: the
    plain version is exactly as easy to get wrong and much easier to
    hand-verify (mean/variance only, no percentile-interpolation
    formula alongside it) -- revisit if a real skewed-distribution case
    ever needs the more robust one.

    Falls back to a fixed `1.0` when `std` comes out `<= 0.0` (a single
    value, or every value identical) -- the formula would otherwise
    collapse the whole kernel to a single infinitely-narrow spike
    (equivalent to dividing by zero in `_kde_density`'s own formula),
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
    every one of `values`' own points, of a standard normal curve
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
    """Render a `Mark.VIOLIN` plot: `encode_distribution()`'s own raw
    per-category values (the same data `Mark.BEESWARM` takes), each
    category drawn as a symmetric density-estimate silhouette instead
    of individual jittered points -- a smoothed, continuous view of the
    same distribution `Mark.BOX`'s five-number summary and `Mark.
    BEESWARM`'s own raw points each show a different, coarser or more
    literal way.

    Each violin is sampled at `_KDE_SAMPLES` evenly spaced points across
    its own category's own `[min(values), max(values)]` -- not the full
    shared y-axis domain -- so the visible shape spans exactly the
    observed data range, the same convention most from-scratch violin
    implementations use (a KDE's own tails technically extend forever,
    but drawing them out to the shared axis's own padding would just be
    a long, visually meaningless near-zero-width sliver).

    Each violin's own width is scaled *independently* -- its own peak
    density maps to `_VIOLIN_WIDTH_FRACTION` of its own category's band
    width, not a shared cross-category maximum -- matching ggplot2's
    own default `scale = "width"` behavior (every violin the same
    maximum width, regardless of how many points went into it) rather
    than `scale = "area"` (equal area, proportional peak width). Picked
    for being the simpler of the two, not because area-scaling is
    wrong -- revisit if a real use ever wants relative sample-size to
    read visually.

    Reuses `_draw_categorical_axis_frame` (the same vertical-
    categorical-x/continuous-y core `Mark.BAR`/`BOX`/`BEESWARM` share),
    with `_data_extent` over every value across every category for the
    shared axis domain -- the same domain reasoning `Mark.BOX`/
    `BEESWARM` already established for this data shape.
    """
    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var all_values = List[Float64]()
    for series in plot._distribution_values:
        for v in series:
            all_values.append(v)
    var y_scale = _data_extent(all_values)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var half_width = frame.x_scale.bandwidth() * _VIOLIN_WIDTH_FRACTION

    for i in range(len(plot.x_categories)):
        var values = plot._distribution_values[i].copy()
        var center_x = frame.x_scale.center(i)
        var bandwidth = _kde_bandwidth(values)
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
        var scale = half_width / max_density if max_density > 0.0 else 0.0
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
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A violin plot -- `Mark.VIOLIN`, a symmetric kernel-density-
    estimate silhouette per category. See `Plot.encode_distribution()`'s
    own docstring (plot.mojo) for the exact shape (the same one
    `beeswarm()`/`ridgeline()` take)."""
    var plot = Plot().mark_violin().encode_distribution(categories=categories, values=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
