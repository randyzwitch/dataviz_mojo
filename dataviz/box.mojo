from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import (
    Plot,
    _BaselineRect,
    _Orientation,
    _RenderResult,
    _tooltip_label,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _finished,
)
from dataviz.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.theme import Theme


struct _BoxData(Copyable, Movable):
    """The five-number summary `encode_boxplot()` computes per category, plus
    every outlier tagged with its category index, for `Mark.BOX`. See
    that method for the quartile/whisker/outlier math. Stored on
    `Plot._box`.
    """

    var q1: List[Float64]
    var median: List[Float64]
    var q3: List[Float64]
    var low: List[Float64]
    var high: List[Float64]
    var outlier_cat: List[Int]
    var outlier_value: List[Float64]

    def __init__(out self):
        self.q1 = List[Float64]()
        self.median = List[Float64]()
        self.q3 = List[Float64]()
        self.low = List[Float64]()
        self.high = List[Float64]()
        self.outlier_cat = List[Int]()
        self.outlier_value = List[Float64]()


def _percentile(sorted_values: List[Float64], p: Float64) -> Float64:
    """The `p`-th percentile (`p` in `[0, 1]`) of `sorted_values` (already
    sorted ascending by the caller) via linear interpolation between the
    two nearest ranks, `numpy.percentile`'s default method.
    `sorted_values` must be non-empty; `Plot.encode_boxplot()` raises
    before that can happen.
    """
    var n = len(sorted_values)
    var idx = p * Float64(n - 1)
    var lo = Int(idx)
    var hi = lo + 1 if lo + 1 < n else lo
    var frac = idx - Float64(lo)
    return sorted_values[lo] + frac * (sorted_values[hi] - sorted_values[lo])


struct _BoxStats(Movable):
    """`_box_stats()`'s result: the five-number summary (`q1`/`median`/`q3`/
    `low`/`high`, with `low`/`high` the whisker ends rather than the raw
    min/max) plus every value beyond the whiskers, drawn as individual
    points.
    """

    var q1: Float64
    var median: Float64
    var q3: Float64
    var low: Float64
    var high: Float64
    var outliers: List[Float64]

    def __init__(
        out self,
        q1: Float64,
        median: Float64,
        q3: Float64,
        low: Float64,
        high: Float64,
        var outliers: List[Float64],
    ):
        self.q1 = q1
        self.median = median
        self.q3 = q3
        self.low = low
        self.high = high
        self.outliers = outliers^


def _box_stats(values: List[Float64]) -> _BoxStats:
    """Tukey's five-number summary plus outliers: quartiles via
    `_percentile`, then the low/high whisker as the most extreme value
    still within 1.5*IQR of the box, and every value beyond that fence as
    an outlier. `values` must be non-empty; `Plot.encode_boxplot()` raises
    before that can happen.

    The whisker scan relies on the sorted order: the first value
    `>= low_fence` is the low whisker, and the last value `<= high_fence`
    before the first that exceeds it is the high whisker.
    """
    var sorted_values = values.copy()
    sort(sorted_values)
    var n = len(sorted_values)

    var q1 = _percentile(sorted_values, 0.25)
    var median = _percentile(sorted_values, 0.5)
    var q3 = _percentile(sorted_values, 0.75)
    var iqr = q3 - q1
    var low_fence = q1 - 1.5 * iqr
    var high_fence = q3 + 1.5 * iqr

    var low_whisker = sorted_values[n - 1]
    for v in sorted_values:
        if v >= low_fence:
            low_whisker = v
            break

    var high_whisker = sorted_values[0]
    for v in sorted_values:
        if v <= high_fence:
            high_whisker = v
        else:
            break

    var outliers = List[Float64]()
    for v in sorted_values:
        if v < low_fence or v > high_fence:
            outliers.append(v)

    return _BoxStats(q1, median, q3, low_whisker, high_whisker, outliers^)


def _draw_box_glyphs[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    band_scale: OrdinalScale,
    value_scale: LinearScale,
    orient: _Orientation,
    point_radius: Int,
) raises:
    """Every category's box, whiskers, caps, median line and outliers,
    written once for both orientations; `_Orientation` carries the four
    places band/value become x/y pixels (rect, line along the value axis,
    line across the band, point).

    Whisker caps are half the band's width, the box the full band, and
    the median line spans the box, all expressed against
    `band_scale.bandwidth()`.

    `to_pixel` (not `_axis_pixel`) for the five box statistics, since
    these are already-computed positions; outliers use `_axis_pixel`.
    """
    var theme = plot._theme
    var band_size = band_scale.bandwidth()
    var half = band_size / 2.0
    var cap_half = band_size / 4.0

    for i in range(len(plot.x_categories)):
        var center = band_scale.center(i)
        var center_i = _round_to_int(center)
        var q1 = value_scale.to_pixel(plot._box.q1[i])
        var q3 = value_scale.to_pixel(plot._box.q3[i])
        var median = value_scale.to_pixel(plot._box.median[i])
        var low = value_scale.to_pixel(plot._box.low[i])
        var high = value_scale.to_pixel(plot._box.high[i])

        if theme.svg_tooltips:
            # The five-number summary is what the shape encodes, so that's the
            # hover text. One per category, so the longer label is cheap.
            target.begin_annotated_group(
                plot.x_categories[i]
                + ": median "
                + _format_fixed(
                    plot._box.median[i], _label_decimals(plot._box.median[i])
                )
                + ", Q1 "
                + _format_fixed(
                    plot._box.q1[i], _label_decimals(plot._box.q1[i])
                )
                + ", Q3 "
                + _format_fixed(
                    plot._box.q3[i], _label_decimals(plot._box.q3[i])
                )
                + ", range "
                + _format_fixed(
                    plot._box.low[i], _label_decimals(plot._box.low[i])
                )
                + "-"
                + _format_fixed(
                    plot._box.high[i], _label_decimals(plot._box.high[i])
                )
            )
        # Whiskers: high -> q3 and q1 -> low, along the value axis.
        orient.value_line(
            target,
            _round_to_int(high),
            _round_to_int(q3),
            center_i,
            theme.axis_color,
            theme.scale,
        )
        orient.value_line(
            target,
            _round_to_int(q1),
            _round_to_int(low),
            center_i,
            theme.axis_color,
            theme.scale,
        )
        # Caps across each whisker's end.
        orient.band_line(
            target,
            _round_to_int(high),
            _round_to_int(center - cap_half),
            _round_to_int(center + cap_half),
            theme.axis_color,
            theme.scale,
        )
        orient.band_line(
            target,
            _round_to_int(low),
            _round_to_int(center - cap_half),
            _round_to_int(center + cap_half),
            theme.axis_color,
            theme.scale,
        )
        # The interquartile box, then the median line across it.
        var box_near = _round_to_int(min(q1, q3))
        var box_span = _round_to_int(max(q1, q3) - min(q1, q3))
        orient.fill_band_rect(
            target,
            _BaselineRect(box_near, box_span),
            _round_to_int(center - half),
            _round_to_int(band_size),
            theme.mark_color,
        )
        orient.band_line(
            target,
            _round_to_int(median),
            _round_to_int(center - half),
            _round_to_int(center + half),
            theme.axis_color,
            theme.scale,
        )
        if theme.svg_tooltips:
            target.end_annotated_group()

    # Outliers sit outside the per-category groups: each is its own datum
    # with its own title.
    for j in range(len(plot._box.outlier_value)):
        if theme.svg_tooltips:
            target.begin_annotated_group(
                _tooltip_label(
                    plot.x_categories[plot._box.outlier_cat[j]],
                    plot._box.outlier_value[j],
                )
                + " (outlier)"
            )
        orient.band_point(
            target,
            _axis_pixel(value_scale, plot._box.outlier_value[j]),
            _round_to_int(band_scale.center(plot._box.outlier_cat[j])),
            point_radius,
            theme.mark_color,
        )
        if theme.svg_tooltips:
            target.end_annotated_group()


def _render_box[
    T: DrawTarget
](
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """Render a `Mark.BOX` plot: `_draw_categorical_axis_frame`'s
    categorical x-axis, with a y-domain (`_data_extent`, padded but not
    forced to include zero) over each category's whiskers and outliers
    (`_box`'s `low`/`high`/`outlier_value`, exactly the values drawn).

    Per category, back to front: the two whiskers (`Q3` to `high`, `Q1`
    to `low`) with a cap at each end, then the box (`Q1` to `Q3`,
    `theme.mark_color`), then the median line (`theme.axis_color`).
    Outliers are drawn in one final pass after every category's box so no
    outlier is occluded by a neighboring box.
    """
    if len(plot.x_categories) != len(plot._box.q1):
        raise Error(
            "Plot.encode_boxplot(): categories and values must have the"
            " same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot._box.q1))
            + ")"
        )

    var theme = plot._theme
    var domain_data = List[Float64]()
    for v in plot._box.low:
        domain_data.append(v)
    for v in plot._box.high:
        domain_data.append(v)
    for v in plot._box.outlier_value:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1
    )

    _draw_box_glyphs(
        target,
        plot,
        frame.x_scale,
        frame.y_scale,
        _Orientation(False),
        _round_to_int(frame.sc.point_radius),
    )

    return frame.result()


def _render_horizontal_box[
    T: DrawTarget
](
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """`_render_box`'s mirror image for `Plot.mark_box(horizontal=True)`
    (#121): `_render_horizontal_bar`'s categorical y-axis
    (`_draw_horizontal_categorical_axis_frame`, gantt.mojo) with the
    continuous axis (`_data_extent`, not zero-forced) along the bottom.
    Whiskers become horizontal lines with vertical caps, the box spans
    the category's band height, the median line runs vertically, and
    outliers plot at `(value's x, category's y-center)`. Its own function
    rather than an orientation flag, for the reasons in
    `_render_horizontal_bar`'s docstring (bar.mojo).
    """
    if len(plot.x_categories) != len(plot._box.q1):
        raise Error(
            "Plot.encode_boxplot(): categories and values must have the"
            " same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot._box.q1))
            + ")"
        )

    var theme = plot._theme
    var domain_data = List[Float64]()
    for v in plot._box.low:
        domain_data.append(v)
    for v in plot._box.high:
        domain_data.append(v)
    for v in plot._box.outlier_value:
        domain_data.append(v)
    var x_scale = _data_extent(domain_data)

    var frame = _draw_horizontal_categorical_axis_frame(
        target, plot.x_categories, x_scale, theme, ox0, oy0, ox1, oy1
    )

    _draw_box_glyphs(
        target,
        plot,
        frame.y_scale,
        frame.x_scale,
        _Orientation(True),
        _round_to_int(frame.sc.point_radius),
    )

    return frame.result()


def box(
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
    """A box plot, John Tukey's five-number summary: a box spanning the
    interquartile range with a median line and whiskers to the
    non-outlier extremes, for comparing a distribution's spread and skew
    across categories at a glance rather than every individual value.

    `Mark.BOX`: one box-and-whiskers per category summarizing a
    distribution of raw values (`values[i]`). See `Plot.encode_boxplot()`
    (plot.mojo) for the quartile/whisker/outlier computation.

    Args:
        categories: One box per entry, in the given order.
        values: Each category's raw values (`values[i]`) -- quartiles,
            whiskers, and outliers are computed from these, not
            passed in directly.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.
        horizontal: Draw categories running top-to-bottom with each
            box-and-whiskers left-to-right instead of the default
            vertical layout -- see `Plot.mark_box()`'s own docstring
            (#121).

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import box
        from dataviz.plot import save
        from dataviz.colors import ROYALBLUE
        from dataviz.theme import Theme

        def main() raises:
            var groups: List[String] = ["Group A", "Group B", "Group C", "Group D"]
            var scores: List[List[Int]] = [
                [72, 75, 78, 80, 81, 83, 85, 88, 90],
                [60, 65, 68, 70, 72, 74, 77, 79],
                [55, 70, 73, 75, 76, 78, 80, 82, 20],
                [82, 84, 85, 86, 87, 88, 89, 91, 93],
            ]

            var c = box(groups, scores, theme=Theme(mark_color=ROYALBLUE))
            save(c, "docs/src/examples/out_box.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_box(horizontal=horizontal)
        .encode_boxplot(categories=categories, values=values)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def box[
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
    """`box()` generalized over numeric element type for `values`; see
    `beeswarm()`'s `DType` overload. Delegates to the concrete overload
    above.
    """
    return box(
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
