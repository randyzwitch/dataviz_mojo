"""The kernel density estimate `Mark.VIOLIN`, `Mark.RIDGELINE` and
`Mark.KDE` share.

Lived in `violin.mojo` until `Mark.KDE` needed it too --
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
from dataviz.text import _Scaled
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
    var values = _kde_observations(plot)

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

    _draw_kde_layer(
        target,
        plot,
        curve[0],
        curve[1],
        values,
        frame.x_scale,
        frame.y_scale,
        frame.sc,
        Float64(frame.py1),
    )
    return frame.result()


def _kde_observations(plot: Plot) raises -> List[Float64]:
    """The observations behind a `Mark.KDE`/`Mark.RUG` plot, checked
    non-empty.

    A free function rather than three copies of the same two lines
    because `_render_layers_generic` needs it too, and needs it *before*
    the shared frame is drawn: a layer's domain contribution is computed
    in a first pass over every layer, so the check that a layer has any
    data at all has to be reachable from there. Raising with
    `Plot.encode_kde()`'s own message keeps a bad layer's error the same
    one the standalone render gives.
    """
    # The outer list is checked before it is indexed. Reaching
    # for `values[0]` first turns "you forgot encode_kde()" from a
    # catchable error into an out-of-bounds assert that aborts the
    # process -- no traceback into user code, and nothing a caller can
    # recover from. The guard has to come before the subscript, not
    # after it.
    _require_non_empty(len(plot._distribution.values), "Plot.encode_kde()")
    var values = plot._distribution.values[0].copy()
    _require_non_empty(len(values), "Plot.encode_kde()")
    return values^


def _draw_kde_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    curve_x: List[Float64],
    curve_y: List[Float64],
    values: List[Float64],
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
    baseline_py: Float64,
) raises:
    """Draw one `Mark.KDE` plot's curve (and its `rug=True` ticks) into an
    already-laid-out continuous axis frame, the counterpart to
    `_draw_line_layer`/`_draw_area_layer` in continuous.mojo.

    Shared by standalone and layered rendering so both draw the same geometry
    rather than a layered path reimplementing it -- which is how
    `_render_bar_combo_layers`' inline copy of the line geometry came to
    silently drop `step=` and then `dashes=`.

    `curve_x`/`curve_y` are `_kde_curve`'s output, passed in rather than
    recomputed: the layered caller has already evaluated the curve to
    contribute it to the combined x/y domain, so passing it through is
    what makes the drawn geometry provably the geometry that domain was
    sized for.

    `sc` is the *layer's* own `_Scaled`, not the frame's. They are the
    same object for a standalone render; in a stack the shared frame
    belongs to `plots[0]` while `line_width` and `tick_length` here have
    to follow this layer's `Theme.scale`, as `render_layers()` documents.

    Args:
        target: Where to draw.
        plot: The chart, for its `_distribution` flags and `Theme`.
        curve_x: The curve's evaluation points.
        curve_y: The density at each.
        values: The raw observations, for the `rug=True` ticks.
        x_scale: The frame's x-scale, already ranged onto the plot rect.
        y_scale: The y-scale this layer draws against.
        sc: This layer's scaled theme metrics.
        baseline_py: The plot rect's bottom edge, where rug ticks sit.
    """
    var theme = plot._theme
    var path = Path()
    path.move_to(x_scale.to_pixel(curve_x[0]), y_scale.to_pixel(curve_y[0]))
    for i in range(1, len(curve_x)):
        path.line_to(x_scale.to_pixel(curve_x[i]), y_scale.to_pixel(curve_y[i]))
    if plot._distribution.kde_fill:
        # Its own path rather than a copy of the stroke's: the fill needs
        # the two closing segments down to density zero, and the stroke
        # must not have them -- a stroked baseline would read as an axis.
        var filled = Path()
        filled.move_to(
            x_scale.to_pixel(curve_x[0]), y_scale.to_pixel(curve_y[0])
        )
        for i in range(1, len(curve_x)):
            filled.line_to(
                x_scale.to_pixel(curve_x[i]), y_scale.to_pixel(curve_y[i])
            )
        filled.line_to(
            x_scale.to_pixel(curve_x[len(curve_x) - 1]), y_scale.to_pixel(0.0)
        )
        filled.line_to(x_scale.to_pixel(curve_x[0]), y_scale.to_pixel(0.0))
        filled.close()
        target.fill_path_aa(
            filled, theme.mark_color, fill_rule=FillRule.NONZERO
        )
    target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)

    if plot._distribution.kde_rug:
        # Over a filled curve the ticks would be mark_color on
        # mark_color and invisible, so they are cut in the background
        # color instead -- notches out of the fill rather than marks on
        # top of it. Unfilled, they are the mark's own color, because a
        # rug is data.
        var tick_color = (
            theme.background if plot._distribution.kde_fill else theme.mark_color
        )
        _draw_rug_ticks(target, values, x_scale, baseline_py, sc, tick_color)


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
    underneath. Two ways to draw that: `render_layers([kdeplot(v),
    rugplot(v)])` composes the two marks, and `kdeplot(rug=True)`
    draws both from the one mark. They produce byte-identical output --
    both reach `_draw_rug_ticks` below against the curve's own x-scale --
    so the choice is about how the code reads, not the chart.

    In a layer stack the rug is a passenger on whatever it sits under:
    the y-axis belongs to the host layer, and the ticks still sit on the
    plot rect's bottom edge. That is why the `y_axis_visible=False` below
    is on *this* function's frame call rather than hung off `Mark.RUG`
    itself -- suppressing a co-layer's axis would delete the thing the
    stack is measured against.

    Each tick is a hairline, so its fixed coordinate snaps to a pixel
    center and it stays crisp; the whole chart is thin vertical lines and
    a blurred one reads as a fainter observation.

    The y-axis is suppressed (`y_axis_visible=False`). A rug has no
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
    var values = _kde_observations(plot)
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

    _draw_rug_ticks(
        target,
        values,
        frame.x_scale,
        Float64(frame.py1),
        frame.sc,
        theme.mark_color,
    )
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
    axes.

    Comparing them on one frame is what seaborn does by calling
    `kdeplot()` twice onto the same axes, and
    `render_layers([kdeplot(a), kdeplot(b)])` is how to say that here
    : the curves share one density axis, so their peak heights are
    comparable, which is the whole point. `render_facets()` puts them
    side by side instead, a weaker reading but useful when the
    distributions barely overlap.

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
        from dataviz import save

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
    draws under its curve, as a chart of their own -- or as a layer, via
    `render_layers([kdeplot(v), rugplot(v)])`, which draws exactly what
    `kdeplot(rug=True)` does.

    Drawn with no y-axis: a rug's ticks are all the same length
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
        from dataviz import save

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


def _draw_snapped_ticks[
    T: DrawTarget
](
    mut target: T,
    values: List[Float64],
    x_scale: LinearScale,
    y_top: Float64,
    y_bottom: Float64,
    color: Color,
    width: Float64,
) raises:
    """Draw one pixel-centered vertical tick per value.

    Only x is snapped; y endpoints retain their layout positions.
    """
    for v in values:
        var px = _snap_pixel_center(x_scale.to_pixel(v))
        target.draw_line_aa(px, y_bottom, px, y_top, color, width=width)


def _draw_rug_ticks[
    T: DrawTarget
](
    mut target: T,
    values: List[Float64],
    x_scale: LinearScale,
    baseline_py: Float64,
    sc: _Scaled,
    color: Color,
) raises:
    """One short tick per observation along the frame's baseline.

    Shared by `Mark.RUG`, by `mark_kde(rug=True)`, and by a `Mark.RUG`
    layer inside `render_layers()`, so the ticks are identical
    whether they stand alone, sit under a curve, or ride a shared frame.

    Takes the three pieces it needs rather than a whole
    `_ContinuousFrame`: the layered caller has the shared frame but must
    pass *this layer's* `sc`, since `tick_length` and `scale` follow the
    layer's own `Theme.scale` while the frame's belong to `plots[0]`.

    What is left here is only what is specific to a rug -- standing on
    the baseline, two tick-lengths tall, one device pixel wide. The tick
    itself, snap included, is `_draw_snapped_ticks` above, which
    `Mark.EVENTPLOT` draws through as well.

    Args:
        target: Where to draw.
        values: The observations.
        x_scale: The frame's x-scale, already ranged onto the plot rect.
        baseline_py: The plot rect's bottom edge, where the ticks sit.
        sc: The drawing layer's scaled theme metrics.
        color: The tick color -- the mark's, or the background where
            the ticks sit on a filled curve.
    """
    _draw_snapped_ticks(
        target,
        values,
        x_scale,
        baseline_py - Float64(sc.tick_length) * 2.0,
        baseline_py,
        color,
        sc.scale,
    )
