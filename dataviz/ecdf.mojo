"""Empirical cumulative distribution rendering."""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.continuous import (
    _build_line_path,
    _decimate_to_pixel_columns,
    _step_points,
)
from dataviz.plot import (
    _Scaled,
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
    _require_non_empty,
)
from dataviz.core.scale import LinearScale
from dataviz.core.step_style import StepStyle
from dataviz.core.theme import Theme


struct _EcdfCurve(Movable):
    """ECDF staircase vertices in data units."""

    var x: List[Float64]
    var y: List[Float64]

    def __init__(out self, var x: List[Float64], var y: List[Float64]):
        self.x = x^
        self.y = y^


def _ecdf_points(
    values: List[Float64], complementary: Bool = False
) -> _EcdfCurve:
    """The vertices of the ECDF staircase over `values`, in data units --
    to be drawn with `StepStyle.POST` (or `PRE` when `complementary`).

    The definition: `F(x)` is the fraction of observations `<= x`, so it
    is a right-continuous step function that jumps by `k/n` at each
    distinct observed value, `k` being how many observations share it.

    `values` is sorted, then walked in runs of equal values: one vertex
    per *distinct* value, carrying that value's cumulative count. `[1, 1,
    2]` becomes `F(1) = 2/3, F(2) = 1` -- two steps, not three.

    The first vertex repeats the smallest observation at `y = 0`, so the
    curve rises from 0 at `min(values)` and ends at exactly 1 at
    `max(values)`. It is not extended to the axis edges: doing that
    would draw a flat run at 0 below the minimum and at 1 above the
    maximum. `_data_extent` padding therefore remains unpainted.

    `1` is reached exactly, not to within rounding: the last cumulative
    count is `n`, and `Float64(n) / Float64(n)` is exactly `1.0`.

    `POST`: the riser sits at the later sample's x, so the plateau over
    `[x[i], x[i + 1])` is drawn at `y[i]`. That is the definition --
    `F` holds its value from one observation until the next one is
    reached, then jumps. `PRE` would draw `F` as left-continuous
    (jumping *before* the observation) and `MID` would put the jump
    halfway between two observations, at an x where nothing happened.
    Only `POST` represents the right-continuous function.

    Complementary (`1 - F(x)`, the survival function reliability and
    survival analysis read) reverses that: the vertex list starts at 1,
    the last x is repeated instead of the first, and the risers land on
    the *earlier* sample, which is `PRE`. Same staircase, walked the
    other way -- again matching matplotlib's `complementary=True`.

    Args:
        values: The observations, in any order; not modified.
        complementary: Draw `1 - F(x)` (falling from 1 to 0) instead of
            `F(x)` (rising from 0 to 1).

    Returns:
        `m + 1` vertices for `m` distinct values, ready to project and
        step.
    """
    var sorted_values = values.copy()
    sort(sorted_values)
    var n = len(sorted_values)

    # One entry per distinct value, with the cumulative fraction of
    # observations at or below it -- the run-walk that makes a tie one
    # step of k/n.
    var distinct = List[Float64](capacity=n)
    var cumulative = List[Float64](capacity=n)
    var i = 0
    while i < n:
        var last = i
        while last + 1 < n and sorted_values[last + 1] == sorted_values[i]:
            last += 1
        distinct.append(sorted_values[i])
        cumulative.append(Float64(last + 1) / Float64(n))
        i = last + 1

    var m = len(distinct)
    var xs = List[Float64](capacity=m + 1)
    var ys = List[Float64](capacity=m + 1)
    if complementary:
        # (v0, 1), then (v1, 1 - f0), ..., with the last x repeated so
        # the final riser drops to zero at the largest observation.
        xs.append(distinct[0])
        ys.append(1.0)
        for k in range(m):
            xs.append(distinct[k + 1] if k + 1 < m else distinct[m - 1])
            ys.append(1.0 - cumulative[k])
    else:
        # (v0, 0), then (v0, f0), (v1, f1), ...: the first x is repeated
        # so the curve rises from zero at the smallest observation.
        xs.append(distinct[0])
        ys.append(0.0)
        for k in range(m):
            xs.append(distinct[k])
            ys.append(cumulative[k])
    return _EcdfCurve(xs^, ys^)


def _render_ecdf[
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
    """Render a `Mark.ECDF` plot: the empirical cumulative distribution
    as a staircase, the shape matplotlib's `ax.ecdf()` and seaborn's
    `ecdfplot()` draw.

    The y-domain is fixed at exactly `[0, 1]` rather than taken from the
    drawn values. It is a proportion, and its two ends mean "none of the
    sample" and "all of it" -- numbers that do not depend on this
    sample, so padding them would caption the axis with proportions
    outside `[0, 1]`, which do not exist. matplotlib pins the same two
    ends (`line.sticky_edges.y[:] = [0, 1]`). The x-domain is
    `_data_extent`'s usual padded data range.

    `Theme.line_smoothing` is ignored here rather than raising the way
    `mark_line(step=...)` does against it (`_check_step_smoothing`).
    That check exists because two *explicit* settings contradicted each
    other and silently picking a winner would make one of them do
    nothing. An ECDF's staircase is not a setting: it is what the mark
    is. A theme that smooths lines is a figure-wide default the caller
    may never have thought about, and refusing to draw a chart over it
    would make `Theme` and `Mark.ECDF` mutually exclusive.

    Layering two ECDFs on one frame -- comparing distributions, which is
    the main reason to draw one -- goes through `render_layers()`, which
    draws each layer with `_draw_ecdf_layer` below and pins the shared
    y-axis to `[0, 1]` when every layer is an ECDF.

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
    # An empty outer list means no `encode_ecdf()` call happened at all,
    # which is distinct from an empty column (`encode_ecdf()` rejects
    # that itself) and has to be checked before indexing into it.
    _require_non_empty(len(plot._distribution.values), "Plot.encode_ecdf()")
    var values = plot._distribution.values[0].copy()
    _require_non_empty(len(values), "Plot.encode_ecdf()")

    var theme = plot._theme
    var complementary = plot._distribution.ecdf_complementary
    var curve = _ecdf_points(values, complementary)

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
        cache=cache,
    )

    _draw_ecdf_layer(
        target, plot, curve.x, curve.y, frame.x_scale, frame.y_scale, frame.sc
    )
    return frame.result()


def _draw_ecdf_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    curve_x: List[Float64],
    curve_y: List[Float64],
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
) raises:
    """Stroke one `Mark.ECDF` staircase into an already-laid-out
    continuous axis frame -- the counterpart to `_draw_kde_layer`, and
    shared by `_render_ecdf` and `render_layers()` so both draw the same
    geometry rather than the layered path reimplementing it (#440).

    `curve_x`/`curve_y` are `_ecdf_points`' vertices in data units; the
    layered path hands back the columns its domain was sized from, so
    the curve drawn is provably the curve the axis was built for.

    Args:
        target: Where to draw.
        plot: The layer, for its theme and `ecdf_complementary` flag.
        curve_x: Staircase vertex x, in data units.
        curve_y: Staircase vertex y, a proportion in `[0, 1]`.
        x_scale: The frame's x-scale, already ranged to pixels.
        y_scale: The frame's y-scale, already ranged to pixels.
        sc: The frame's `_Scaled` theme quantities (line width).
    """
    var theme = plot._theme
    var px = List[Float64](capacity=len(curve_x))
    var py = List[Float64](capacity=len(curve_x))
    for i in range(len(curve_x)):
        px.append(x_scale.to_pixel(curve_x[i]))
        py.append(y_scale.to_pixel(curve_y[i]))

    # Step first, decimate second -- `_draw_line_layer`'s order and its
    # reasoning: what gets thinned should be the geometry actually drawn,
    # so the two-points-per-column cap applies to the staircase itself.
    # A big sample is exactly where this matters, since an ECDF draws
    # every observation by construction (one vertex per distinct value,
    # doubled by the expansion) and never bins any of them away.
    var stepped = _step_points(
        px, py, _ecdf_step_style(plot._distribution.ecdf_complementary)
    )
    var thinned = _decimate_to_pixel_columns(stepped.px, stepped.py)
    var path = _build_line_path(thinned.px, thinned.py, 0.0)
    target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)


def _ecdf_step_style(complementary: Bool) -> StepStyle:
    """`POST` for `F(x)`, `PRE` for `1 - F(x)`; see `_ecdf_points`'
    "Which `StepStyle` an ECDF is". Named rather than written inline at
    the one call site so the tests can assert the choice directly instead
    of inferring it from pixels.
    """
    return StepStyle.PRE if complementary else StepStyle.POST


def ecdf(
    values: List[Float64],
    complementary: Bool = False,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """The empirical cumulative distribution of `values`: the fraction of
    observations at or below each x, as a staircase rising from 0 to 1.

    `Mark.ECDF`: matplotlib's `ax.ecdf()`, seaborn's `ecdfplot()`.

    The honest alternative to a histogram. There is no bin width and no
    bandwidth, so there is no parameter that can change what the chart
    says -- the same sample always produces the same curve, and every
    observation is visible in it rather than summarized into a bucket.
    Two ECDFs also overplot legibly where two histograms do not, which
    makes this the better chart for comparing distributions: pass two
    of these to `render_layers()` and they share one frame, with the
    proportion axis pinned to `[0, 1]`.

    What it costs: a shape a reader has to be taught. A histogram's
    modes are obvious and an ECDF's are slopes, so a bimodal sample
    reads as two steep stretches with a flat one between them rather
    than as two humps.

    The curve runs from `min(values)` to `max(values)` and no further --
    extending it to the axis edges would claim the distribution is
    bounded there. Ties share one step of `k/n`. `complementary=True`
    draws `1 - F(x)` instead, falling from 1 to 0, which is what
    reliability and survival work reads: "what fraction lasted longer
    than this".

    Args:
        values: The observations, in any order.
        complementary: Draw the complementary (survival) curve
            `1 - F(x)`, falling from 1 to 0, instead of `F(x)`.
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
        from dataviz import ecdf
        from dataviz import save

        def main() raises:
            # The same illustrative right-skewed checkout latency sample used
            # by kdeplot(), rugplot(), and histogram().
            var latency_ms: List[Float64] = [
                84.0, 72.0, 91.0, 68.0, 75.0, 88.0, 79.0, 73.0,
                96.0, 82.0, 77.0, 69.0, 85.0, 74.0, 101.0, 80.0,
                71.0, 93.0, 76.0, 87.0, 83.0, 70.0, 78.0, 89.0,
                81.0, 95.0, 67.0, 86.0, 72.0, 90.0, 110.0, 124.0,
                138.0, 156.0, 205.0, 98.0, 105.0, 118.0, 74.0, 82.0,
            ]
            var c = ecdf(
                latency_ms,
                title="Illustrative Checkout API Latency",
                x_title="Latency (ms)",
                y_title="Proportion of requests",
            )
            save(c, "docs/src/examples/out_ecdf.svg")
        ```
    """
    var plot = (
        Plot().mark_ecdf(complementary=complementary).encode_ecdf(values=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
