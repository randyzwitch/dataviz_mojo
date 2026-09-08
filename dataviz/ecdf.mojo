"""`Mark.ECDF`: the empirical cumulative distribution function (#338).

The whole computation is a sort. `_ecdf_points` below turns raw
observations into the staircase's vertices in data units; `_render_ecdf`
projects those onto a continuous frame and hands them to `_step_points`
(continuous.mojo), the same expansion `mark_line(step=...)` uses, so
this file owns no staircase geometry of its own.

Why this chart earns a mark of its own, next to `Mark.HISTOGRAM`'s bars
and `Mark.KDE`'s curve: an ECDF makes no binning or bandwidth choice, so
there is no parameter that can change the conclusion. A histogram of the
same sample can show one mode or three depending on bin width, and a KDE
the same depending on bandwidth. An ECDF has one shape.
"""

from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.continuous import (
    _build_line_path,
    _decimate_to_pixel_columns,
    _step_points,
)
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _finished,
    _require_non_empty,
)
from dataviz.scale import LinearScale
from dataviz.step_style import StepStyle
from dataviz.theme import Theme


struct _EcdfCurve(Movable):
    """`_ecdf_points`' result: the staircase's vertices in data units, as
    the parallel `x`/`y` columns the rest of the render path already
    speaks. Its own struct for the same reason `_Stepped` (continuous.mojo)
    has one -- a function returns one value and the two lists have to
    travel together.
    """

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

    ## Ties get one step of `k/n`, not `k` steps of `1/n`

    `values` is sorted, then walked in runs of equal values: one vertex
    per *distinct* value, carrying that value's cumulative count. `[1, 1,
    2]` becomes `F(1) = 2/3, F(2) = 1` -- two steps, not three.

    matplotlib's `Axes.ecdf` emits one vertex per observation instead
    (`cum_weights = (1 + arange(n)) / n`, every value kept), which draws
    the same picture: the extra vertices sit at the same x, so the
    plateaus between them have zero length and put no ink down. Both are
    correct; this form is the smaller one, and it is the one whose
    vertices a reader can check against the definition.

    matplotlib's own `compress=True` -- documented as grouping equal
    entries "with a summed weight", i.e. exactly this -- is **not** the
    oracle here, because on matplotlib 3.11.1 it keeps each run's
    *first* cumulative weight rather than its last:

        ecdf([1, 1, 2], compress=True)     -> y = [0, 1/3, 1]
        ecdf([1, 1, 1, 2, 5, 5], compress=True)
                                           -> y = [0, 1/6, 2/3, 5/6]

    The first understates `F(1)` (2/3, not 1/3); the second never
    reaches 1 at all. Its default (uncompressed) path is right, and that
    is what this function was checked against value by value.

    ## The curve runs the data range, and no further

    The first vertex repeats the smallest observation at `y = 0`, so the
    curve rises from 0 at `min(values)` and ends at exactly 1 at
    `max(values)`. It is not extended to the axis edges: doing that
    would draw a flat run at 0 below the minimum and at 1 above the
    maximum, which asserts the distribution is bounded there -- a claim
    the sample does not make. matplotlib draws to the data range for the
    same reason, and `_data_extent`'s 5% padding leaves the visible gap
    at each end unpainted rather than filled in.

    `1` is reached exactly, not to within rounding: the last cumulative
    count is `n`, and `Float64(n) / Float64(n)` is exactly `1.0`.

    ## Which `StepStyle` an ECDF is

    `POST`: the riser sits at the later sample's x, so the plateau over
    `[x[i], x[i + 1])` is drawn at `y[i]`. That is the definition --
    `F` holds its value from one observation until the next one is
    reached, then jumps. `PRE` would draw `F` as left-continuous
    (jumping *before* the observation) and `MID` would put the jump
    halfway between two observations, at an x where nothing happened.
    Only `POST` is the function; the other two are pictures of a
    different one. matplotlib passes `drawstyle="steps-post"` here too.

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
    the main reason to draw one -- is not available yet:
    `render_layers()` takes only `Mark.POINT`/`LINE`/`AREA` (#376).
    `render_facets()` puts them side by side today, a weaker reading but
    an honest one.

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

    var px = List[Float64](capacity=len(curve.x))
    var py = List[Float64](capacity=len(curve.x))
    for i in range(len(curve.x)):
        px.append(frame.x_scale.to_pixel(curve.x[i]))
        py.append(frame.y_scale.to_pixel(curve.y[i]))

    # Step first, decimate second -- `_draw_line_layer`'s order and its
    # reasoning: what gets thinned should be the geometry actually drawn,
    # so the two-points-per-column cap applies to the staircase itself.
    # A big sample is exactly where this matters, since an ECDF draws
    # every observation by construction (one vertex per distinct value,
    # doubled by the expansion) and never bins any of them away.
    var stepped = _step_points(px, py, _ecdf_step_style(complementary))
    var thinned = _decimate_to_pixel_columns(stepped.px, stepped.py)
    var path = _build_line_path(thinned.px, thinned.py, 0.0)
    target.stroke_path_aa(path, theme.mark_color, width=frame.sc.line_width)
    return frame.result()


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
    makes this the better chart for comparing distributions (that
    comparison needs `render_layers()`, which does not take this mark
    yet -- #376; `render_facets()` is today's side-by-side answer).

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
        from dataviz.plot import save

        def main() raises:
            var response_ms: List[Float64] = [
                12.0, 14.0, 15.0, 15.0, 16.0, 16.0, 17.0, 18.0, 19.0,
                21.0, 24.0, 25.0, 26.0, 26.0, 27.0, 28.0, 31.0, 44.0,
            ]
            var c = ecdf(
                response_ms,
                title="Response time",
                x_title="ms",
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
