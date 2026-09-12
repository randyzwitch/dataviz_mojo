"""`Mark.BOXENPLOT` and `boxenplot()`: the letter-value plot -- a box plot
whose single box and whiskers become nested boxes at successively finer
quantiles, so a large sample's tail is drawn rather than discarded."""

from canvas.text.font_cache import FontCache
from canvas.geometry import round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.box import _percentile
from dataviz.color_scale import ColorScale
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _BaselineRectF,
    _Orientation,
    _RenderResult,
    _axis_pixel_f,
    _data_extent,
    _draw_categorical_axis_frame,
    _finished,
)
from dataviz.scale import LinearScale
from dataviz.theme import Theme


struct _BoxenData(Copyable, Movable):
    """The letter values `encode_boxenplot()` computes per category, for
    `Mark.BOXENPLOT`. Level `k` of category `i` spans `lower[i][k]` to
    `upper[i][k]`; level 0 is the quartile box and each deeper level
    halves the tail probability. Stored on `Plot._boxen`."""

    var median: List[Float64]
    var lower: List[List[Float64]]
    var upper: List[List[Float64]]
    var outlier_cat: List[Int]
    var outlier_value: List[Float64]

    def __init__(out self):
        self.median = List[Float64]()
        self.lower = List[List[Float64]]()
        self.upper = List[List[Float64]]()
        self.outlier_cat = List[Int]()
        self.outlier_value = List[Float64]()


struct _LetterValues(Movable):
    """`_letter_values()`'s result for one sample."""

    var median: Float64
    var lower: List[Float64]
    var upper: List[Float64]
    var outliers: List[Float64]

    def __init__(
        out self,
        median: Float64,
        var lower: List[Float64],
        var upper: List[Float64],
        var outliers: List[Float64],
    ):
        self.median = median
        self.lower = lower^
        self.upper = upper^
        self.outliers = outliers^


def _letter_value_depth(n: Int) -> Int:
    """How many nested boxes a sample of `n` supports: Tukey's rule,
    `floor(log2(n)) - 3`, the largest `k` with `2^(k + 3) <= n`, so the
    outermost box still rests on several observations. At least one --
    the quartile box -- however small the sample, where a letter-value
    plot degrades gracefully into a box plot whose whiskers are the
    quartiles."""
    var k = 0
    while (1 << (k + 4)) <= n:
        k += 1
    return max(1, k)


def _letter_values(values: List[Float64]) raises -> _LetterValues:
    """The median, then `_letter_value_depth(n)` nested quantile pairs
    -- level `k` at `2^-(k + 2)` and `1 - 2^-(k + 2)`, so level 0 is the
    quartiles, level 1 the eighths, and so on -- plus every observation
    beyond the deepest pair as an outlier. Quantiles via `_percentile`,
    numpy's linear interpolation, the rule `Mark.BOX` uses.

    Raises:
        Error: `values` is empty.
    """
    if len(values) == 0:
        raise Error("a letter-value plot needs at least one observation")
    var sorted_values = values.copy()
    sort(sorted_values)
    var n = len(sorted_values)
    var depth = _letter_value_depth(n)
    var lower = List[Float64](capacity=depth)
    var upper = List[Float64](capacity=depth)
    var p = 0.25
    for _ in range(depth):
        lower.append(_percentile(sorted_values, p))
        upper.append(_percentile(sorted_values, 1.0 - p))
        p /= 2.0
    var outliers = List[Float64]()
    for v in sorted_values:
        if v < lower[depth - 1] or v > upper[depth - 1]:
            outliers.append(v)
    return _LetterValues(
        _percentile(sorted_values, 0.5), lower^, upper^, outliers^
    )


def _draw_boxen_glyphs[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    orient: _Orientation,
    point_radius: Int,
) raises:
    """Every category's nested boxes, median line and outliers, written
    once for both orientations through `_Orientation` as `Mark.BOX`'s
    glyphs are.

    Boxes are drawn deepest first: the deepest level spans the most and
    is the narrowest, and each shallower level is wider and sits on top
    of it, so the nest reads as a stack narrowing into the tails. The
    quartile box takes the full band and each level beyond it half the
    width of the last. Levels are colored by depth through the theme's
    `ColorScale`, which is how the nesting is read when the widths
    alone are close.
    """
    var theme = plot._theme
    var band_size = band_scale.bandwidth()
    var half = band_size / 2.0
    for i in range(len(plot._categorical.x)):
        var center = band_scale.center(i)
        var depth = len(plot._boxen.lower[i])
        var scale = ColorScale.from_theme(
            theme, 0.0, Float64(max(depth - 1, 1))
        )
        var k = depth - 1
        while k >= 0:
            var near_v = value_scale.to_pixel(plot._boxen.lower[i][k])
            var far_v = value_scale.to_pixel(plot._boxen.upper[i][k])
            var near = min(near_v, far_v)
            var span = max(near_v, far_v) - near
            var width = band_size
            for _ in range(k):
                width /= 2.0
            orient.fill_band_rect(
                target,
                _BaselineRectF(near, span),
                center - width / 2.0,
                width,
                scale.color_at(Float64(k)),
            )
            k -= 1
        orient.band_line(
            target,
            value_scale.to_pixel(plot._boxen.median[i]),
            center - half,
            center + half,
            theme.axis_color,
            theme.scale,
        )
    for j in range(len(plot._boxen.outlier_value)):
        orient.band_point(
            target,
            _axis_pixel_f(value_scale, plot._boxen.outlier_value[j]),
            band_scale.center(plot._boxen.outlier_cat[j]),
            Float64(point_radius),
            theme.mark_color,
        )


def _boxen_domain_data(plot: Plot) raises -> List[Float64]:
    """The deepest level's ends and every outlier -- exactly the values
    drawn -- for `_data_extent`."""
    if len(plot._categorical.x) != len(plot._boxen.median):
        raise Error(
            "Plot.encode_boxenplot(): categories and values must have the"
            " same length (got "
            + String(len(plot._categorical.x))
            + " and "
            + String(len(plot._boxen.median))
            + ")"
        )
    var domain_data = List[Float64]()
    for i in range(len(plot._boxen.lower)):
        var d = len(plot._boxen.lower[i]) - 1
        domain_data.append(plot._boxen.lower[i][d])
        domain_data.append(plot._boxen.upper[i][d])
    for v in plot._boxen.outlier_value:
        domain_data.append(v)
    return domain_data^


def _render_boxenplot[
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
    """Render a `Mark.BOXENPLOT` plot: `Mark.BOX`'s categorical x-axis and
    `_data_extent` y-domain over what is drawn, then `_draw_boxen_glyphs`."""
    var theme = plot._theme
    var y_scale = _data_extent(_boxen_domain_data(plot))
    var frame = _draw_categorical_axis_frame(
        target,
        plot._categorical.x,
        y_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_boxen_glyphs(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        _Orientation(False),
        round_to_int(frame.sc.point_radius),
    )
    return frame.result()


def _render_horizontal_boxenplot[
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
    """`_render_boxenplot`'s mirror image for
    `Plot.mark_boxenplot(horizontal=True)`, as `_render_horizontal_box`
    is for `Mark.BOX`."""
    var theme = plot._theme
    var x_scale = _data_extent(_boxen_domain_data(plot))
    var frame = _draw_horizontal_categorical_axis_frame(
        target,
        plot._categorical.x,
        x_scale,
        theme,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_boxen_glyphs(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        _Orientation(True),
        round_to_int(frame.sc.point_radius),
    )
    return frame.result()


def boxenplot(
    categories: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """A letter-value plot, seaborn's `boxenplot()`: like `box()`, but the
    single box and two whiskers become nested boxes at successively
    finer quantiles -- the quartiles, then the eighths, the sixteenths
    and on -- each half as wide as the last, with only the observations
    beyond the deepest box drawn as points.

    A box plot is the right summary for a small sample and a poor one
    for a large one: with thousands of observations "outlier" under the
    1.5 IQR rule stops meaning anything, and the whiskers plus a cloud
    of points say nothing about the shape of the tail. This draws the
    tail instead of discarding it. How deep the nest goes follows the
    sample size (Tukey's rule, `floor(log2(n)) - 3` levels), so a small
    sample gets a plain quartile box and a large one several levels.

    `Mark.BOXENPLOT` over `encode_boxenplot()`.

    Args:
        categories: One label per group.
        values: `values[i]` is every raw observation in `categories[i]`.
        theme: Full styling knobs beyond this function's own arguments.
        width: Canvas width in pixels.
        height: Canvas height in pixels.
        title: Chart title; empty for none.
        subtitle: Chart subtitle; empty for none.
        x_title: X-axis title; empty for none.
        y_title: Y-axis title; empty for none.
        horizontal: Draw categories top-to-bottom with values running
            left-to-right.

    Returns:
        The finished `Plot`, ready to `render()` or `save()`.

    Raises:
        Error: `categories` and `values` differ in length, or a group is
            empty.

    Example:
        ```mojo
        from dataviz import boxenplot, save

        def main() raises:
            # Illustrative page-load times (ms) for three deployments, 256
            # samples each with a long right tail -- the case a box plot's
            # outlier cloud says nothing useful about.
            var names: List[String] = ["v1", "v2", "v3"]
            var samples = List[List[Float64]]()
            for d in range(3):
                var s = List[Float64]()
                var seed = 7 + d
                for _ in range(256):
                    seed = (seed * 1103515245 + 12345) % 2147483648
                    var u = Float64(seed % 10000) / 10000.0
                    # Skewed: most loads are quick, a few are very slow.
                    s.append(120.0 + 40.0 * Float64(d) + 900.0 * u * u * u)
                samples.append(s^)
            var chart = boxenplot(
                names,
                samples,
                title="Illustrative Page-Load Time by Deployment",
                y_title="Load time (ms)",
            )
            save(chart, "docs/src/examples/out_boxenplot.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_boxenplot(horizontal=horizontal)
        .encode_boxenplot(categories, values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def boxenplot[
    dtype: DType
](
    categories: List[String],
    values: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
    horizontal: Bool = False,
) raises -> Plot:
    """`boxenplot()` generalized over numeric element type; see `box()`'s
    `DType` overload. Delegates to the concrete overload above.
    """
    return boxenplot(
        categories,
        _materialize_nested_scalar_list(values),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
        horizontal=horizontal,
    )
