"""The kernel density estimate `Mark.VIOLIN`, `Mark.RIDGELINE` and
`Mark.KDE` share.

Lived in `violin.mojo` until `Mark.KDE` needed it too (#351) --
`ridgeline.mojo` was already importing it from there, which made violin
the de-facto shared home without anything saying so. Moved here
unchanged; the estimator is the same one violins have always drawn.
"""

from std.math import exp, pi, sqrt

from canvas.color import Color
from canvas.fill_rule import FillRule
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import (
    _ContinuousFrame,
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
    _min_max,
    _require_non_empty,
)
from dataviz.pixel_snap import _snap_pixel_center
from dataviz.scale import LinearScale
from dataviz.theme import Theme


comptime _KDE_SAMPLES = 30


def _kde_bandwidth(values: List[Float64]) -> Float64:
    """Silverman's rule of thumb for kernel-density bandwidth,
    `0.9 * std * n^(-1/5)`: the std-only version, not the IQR-adjusted
    variant (`0.9 * min(std, IQR/1.34) * n^(-1/5)`), which is more robust
    to outliers but needs a percentile computation on top. Falls back to
    `1.0` when `std <= 0.0` (a single value, or all identical), where the
    formula would collapse the kernel to a spike.
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


def _kde_density(
    values: List[Float64], bandwidth: Float64, y: Float64
) -> Float64:
    """The Gaussian-kernel density estimate at `y`:
    `(1 / (n*h)) * sum(gaussian((y - v_i) / h))` over every point in
    `values`.
    """
    var n = len(values)
    var sum_density = 0.0
    for v in values:
        var u = (y - v) / bandwidth
        sum_density += exp(-0.5 * u * u) / sqrt(2.0 * pi)
    return sum_density / (Float64(n) * bandwidth)


def _kde_curve(
    values: List[Float64], bandwidth: Float64
) raises -> Tuple[List[Float64], List[Float64]]:
    """The density curve over `values`' own range, as x and y columns.

    Evaluated at `_KDE_SAMPLES` points spanning the data padded by three
    bandwidths on each side, which is where a Gaussian kernel has
    effectively decayed to nothing -- stopping at the data's own extremes
    would cut the curve off mid-slope and imply the distribution ends
    there.

    Args:
        values: The observations.
        bandwidth: Kernel bandwidth; Silverman's rule when not positive.

    Returns:
        The evaluation points and the density at each.
    """
    var h = bandwidth if bandwidth > 0.0 else _kde_bandwidth(values)
    var mm = _min_max(values)
    var lo = mm.min - 3.0 * h
    var hi = mm.max + 3.0 * h
    var xs = List[Float64](capacity=_KDE_SAMPLES)
    var ys = List[Float64](capacity=_KDE_SAMPLES)
    for s in range(_KDE_SAMPLES):
        var x = lo + (hi - lo) * Float64(s) / Float64(_KDE_SAMPLES - 1)
        xs.append(x)
        ys.append(_kde_density(values, h, x))
    return (xs^, ys^)


def _render_kde[
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
    """Render a `Mark.KDE` plot: one smooth density curve over raw
    observations, the shape seaborn's `kdeplot()` draws.

    The same estimate `Mark.VIOLIN` computes, drawn on a continuous
    frame -- value across, density up -- rather than mirrored inside a
    category band. That is the form for comparing two or three
    distributions on shared axes, which a violin cannot do without a
    category for each.

    A density curve says nothing about how many observations produced
    it, which is what `Mark.RUG` is for underneath it.

    Args:
        target: Where to draw.
        plot: The chart, whose `_distribution` values this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: No values were given.
    """
    var values = plot._distribution.values[0].copy()
    _require_non_empty(len(values), "Plot.encode_kde()")

    var curve = _kde_curve(values, plot._distribution.kde_bandwidth_override)
    var theme = plot._theme

    var y_max = 0.0
    for d in curve[1]:
        if d > y_max:
            y_max = d
    var y_scale = LinearScale(
        0.0, y_max * 1.05 if y_max > 0.0 else 1.0, 0.0, 1.0
    )

    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(curve[0]),
        y_scale,
        theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )

    var path = Path()
    path.move_to(
        frame.x_scale.to_pixel(curve[0][0]),
        frame.y_scale.to_pixel(curve[1][0]),
    )
    for i in range(1, len(curve[0])):
        path.line_to(
            frame.x_scale.to_pixel(curve[0][i]),
            frame.y_scale.to_pixel(curve[1][i]),
        )
    if plot._distribution.kde_fill:
        # Its own path rather than a copy of the stroke's: the fill needs
        # the two closing segments down to density zero, and the stroke
        # must not have them -- a stroked baseline would read as an axis.
        var filled = Path()
        filled.move_to(
            frame.x_scale.to_pixel(curve[0][0]),
            frame.y_scale.to_pixel(curve[1][0]),
        )
        for i in range(1, len(curve[0])):
            filled.line_to(
                frame.x_scale.to_pixel(curve[0][i]),
                frame.y_scale.to_pixel(curve[1][i]),
            )
        filled.line_to(
            frame.x_scale.to_pixel(curve[0][len(curve[0]) - 1]),
            frame.y_scale.to_pixel(0.0),
        )
        filled.line_to(
            frame.x_scale.to_pixel(curve[0][0]), frame.y_scale.to_pixel(0.0)
        )
        filled.close()
        target.fill_path_aa(
            filled, theme.mark_color, fill_rule=FillRule.NONZERO
        )
    target.stroke_path_aa(path, theme.mark_color, width=frame.sc.line_width)

    if plot._distribution.kde_rug:
        # Over a filled curve the ticks would be mark_color on
        # mark_color and invisible, so they are cut in the background
        # colour instead -- notches out of the fill rather than marks on
        # top of it. Unfilled, they are the mark's own colour, because a
        # rug is data.
        _draw_rug_ticks(
            target,
            values,
            frame,
            theme.background if plot._distribution.kde_fill else theme.mark_color,
        )
    return frame.result()


def _render_rug[
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
    """Render a `Mark.RUG` plot: one short tick per observation along the
    x axis, the shape seaborn's `rugplot()` draws.

    A density curve is smooth everywhere and says nothing about how many
    observations are behind it, or where they actually fall. A rug is the
    honesty check on one, which is why it is conventionally drawn
    underneath -- layer the two with `render_layers()`.

    Each tick is a hairline, so its fixed coordinate snaps to a pixel
    centre and it stays crisp; the whole chart is thin vertical lines and
    a blurred one reads as a fainter observation.

    The y-axis is suppressed (`y_axis_visible=False`, #378). A rug has no
    y dimension: the `LinearScale(0.0, 1.0, ...)` below exists only
    because `_draw_continuous_axis_frame` requires a y-domain, and drawn
    out it would caption the chart `0.0 0.2 ... 1.0` -- a density a
    reader can reasonably believe and that is not there. The x-axis and
    the vertical gridlines stay: the observation's value is the one thing
    a rug does encode.

    Args:
        target: Where to draw.
        plot: The chart, whose `_distribution` values this reads.
        ox0: Left edge of the outer bounds.
        oy0: Top edge.
        ox1: Right edge.
        oy1: Bottom edge.
        cache: The render's font cache.

    Returns:
        The frame the axes were drawn into.

    Raises:
        Error: No values were given.
    """
    var values = plot._distribution.values[0].copy()
    _require_non_empty(len(values), "Plot.encode_kde()")
    var theme = plot._theme

    var frame = _draw_continuous_axis_frame(
        target,
        _data_extent(values),
        LinearScale(0.0, 1.0, 0.0, 1.0),
        theme,
        _LegendLayout(),
        ox0,
        oy0,
        ox1,
        oy1,
        y_axis_visible=False,
        cache=cache,
    )

    _draw_rug_ticks(target, values, frame, theme.mark_color)
    return frame.result()


def kdeplot(
    values: List[Float64],
    bandwidth: Float64 = 0.0,
    fill: Bool = False,
    rug: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A kernel-density curve over raw observations: the smooth estimate
    of a distribution's shape, without a histogram's bin-width choice.

    `Mark.KDE`: seaborn's `kdeplot()`. The same estimate `Mark.VIOLIN`
    computes, drawn on a continuous frame -- value across, density up --
    which is the form for comparing two or three distributions on shared
    axes. Layer them with `render_layers()`.

    A KDE is smooth everywhere, including where there are no
    observations at all, so it can imply detail the sample does not
    support. `rug=True` marks where the data actually are, and
    `bandwidth` is worth setting deliberately -- the same sample can show
    one mode or three depending on it.

    Args:
        values: The observations.
        bandwidth: Kernel bandwidth; not positive uses Silverman's rule.
        fill: Shade the curve down to zero as well as stroking it.
        rug: Draw each observation as a tick along the baseline.
        theme: Colors, sizes and spacing.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Smaller line under the title.
        x_title: X-axis label.
        y_title: Y-axis label.

    Returns:
        The finished `Plot`.

    Raises:
        Error: `values` is empty.

    Example:
        ```mojo
        from dataviz import kdeplot
        from dataviz.plot import save

        def main() raises:
            var samples: List[Float64] = [
                12.0, 14.0, 15.0, 15.0, 16.0, 16.0, 17.0, 18.0,
                24.0, 25.0, 26.0, 26.0, 27.0, 28.0,
            ]
            var c = kdeplot(samples, fill=True, rug=True, title="Response time")
            save(c, "docs/src/examples/out_kdeplot.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_kde(bandwidth=bandwidth, fill=fill, rug=rug)
        .encode_kde(values=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def rugplot(
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """One short tick per observation along the x axis.

    `Mark.RUG`: seaborn's `rugplot()`. The same ticks `kdeplot(rug=True)`
    draws under its curve, as a chart of their own -- `render_layers()`
    cannot yet combine the two marks (#376).

    Drawn with no y-axis (#378): a rug's ticks are all the same length
    and all sit on the baseline, so the only thing the chart says is
    *where the observations are*. Passing `y_title` still captions the
    left edge, which is worth avoiding here for the same reason.

    Args:
        values: The observations.
        theme: Colors, sizes and spacing.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title.
        subtitle: Smaller line under the title.
        x_title: X-axis label.
        y_title: Y-axis label.

    Returns:
        The finished `Plot`.

    Raises:
        Error: `values` is empty.

    Example:
        ```mojo
        from dataviz import rugplot
        from dataviz.plot import save

        def main() raises:
            var samples: List[Float64] = [
                12.0, 14.0, 15.0, 15.0, 16.0, 17.0, 24.0, 25.0, 26.0, 28.0,
            ]
            var c = rugplot(samples, title="Observations")
            save(c, "docs/src/examples/out_rugplot.svg")
        ```
    """
    var plot = Plot().mark_rug().encode_kde(values=values)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def _draw_rug_ticks[
    T: DrawTarget
](
    mut target: T,
    values: List[Float64],
    frame: _ContinuousFrame,
    color: Color,
) raises:
    """One short tick per observation along the frame's baseline.

    Shared by `Mark.RUG` and by `mark_kde(rug=True)`, so the ticks are
    identical whether they stand alone or sit under a curve.

    Each tick is a hairline, so its fixed coordinate snaps to a pixel
    centre and stays crisp -- the whole point is a row of thin vertical
    lines, and a blurred one reads as a fainter observation.

    Args:
        target: Where to draw.
        values: The observations.
        frame: The frame to draw against.
        color: The tick colour -- the mark's, or the background where
            the ticks sit on a filled curve.
    """
    var height = Float64(frame.sc.tick_length) * 2.0
    var baseline = Float64(frame.py1)
    for v in values:
        var px = _snap_pixel_center(frame.x_scale.to_pixel(v))
        target.draw_line_aa(
            px,
            baseline,
            px,
            baseline - height,
            color,
            width=frame.sc.scale,
        )
