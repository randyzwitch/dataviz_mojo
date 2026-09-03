from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_nested_scalar_list
from dataviz.gantt import _draw_horizontal_categorical_axis_frame
from dataviz.plot import (
    Plot,
    _BaselineRect,
    _Orientation,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _empty_result,
    _finished,
)
from dataviz.theme import Theme


struct _BoxData(Movable):
    """
    Mark.BOX only -- the five-number summary encode_boxplot() computes per
    category up front, plus every outlier tagged with which category (by
    index into x_categories) it belongs to. See that method's docstring for
    the quartile/whisker/outlier math.

    Grouped onto `Plot._box` -- see `Plot`'s docstring.
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
    """The `p`-th percentile (`p` in `[0, 1]`) of `sorted_values`
    (already sorted ascending -- callers, not this function, own that,
    since `_box_stats` already needs a sorted copy for its whisker
    scan and there's no reason to sort twice) via linear interpolation
    between the two nearest ranks -- the same method `numpy.percentile`'s default (`"linear"`) uses. `sorted_values` must be non-empty;
    `_box_stats`'s caller (`Plot.encode_boxplot()`) raises before
    this could ever run on an empty list.
    """
    var n = len(sorted_values)
    var idx = p * Float64(n - 1)
    var lo = Int(idx)
    var hi = lo + 1 if lo + 1 < n else lo
    var frac = idx - Float64(lo)
    return sorted_values[lo] + frac * (sorted_values[hi] - sorted_values[lo])


struct _BoxStats(Movable):
    """`_box_stats()`'s result -- a box plot's conventional five-
    number summary (`q1`/`median`/`q3`/`low`/`high`, `low`/`high` being
    the whisker ends, not the raw min/max) plus every value beyond the
    whiskers, kept separately since a box plot draws those as
    individual points, not folded into the whisker range."""

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
    """Tukey's five-number summary plus outliers, the conventional box-
    plot algorithm: quartiles via `_percentile`'s linear interpolation,
    then the low/high whisker as the most extreme value still *within*
    1.5*IQR of the box (not simply `values`' min/max -- a whisker
    stops at the last real data point inside the fence, the entire
    point of separating "whisker" from "outlier"), and every value
    beyond that fence as its outlier. `values` must be non-empty --
    `Plot.encode_boxplot()`, this function's only caller, raises before
    this could ever run on an empty list.

    The whisker scan relies on `sorted_values` already being sorted
    ascending: the first value `>= low_fence` is the smallest one still
    inside the fence (so `low_whisker`), and the last value `<=
    high_fence` scanned before the first one that isn't is the largest
    one still inside it (so `high_whisker`, found by breaking out of
    the loop the moment a value exceeds the fence -- correct precisely
    because the list is sorted, every later value would too).
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
    written once for both orientations -- `_Orientation` carries the
    four places band/value have to become concrete x/y pixels (rect,
    line along the value axis, line across the band, point).

    Whisker caps are half the band's width, the box the full band, and
    the median line spans the box -- the conventional Tukey proportions
    each expressed against `band_scale.bandwidth()` rather than fixed
    pixels, so they hold at any canvas size.

    `to_pixel` (not `_axis_pixel`) for the five box statistics, since
    these are already-computed positions rather than data values
    needing the axis's own rounding -- the outliers use `_axis_pixel`
    for the same reason `_render_box` always did.
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

        # Whiskers: high -> q3 and q1 -> low, along the value axis.
        orient.value_line(
            target, _round_to_int(high), _round_to_int(q3), center_i, theme.axis_color, theme.scale
        )
        orient.value_line(
            target, _round_to_int(q1), _round_to_int(low), center_i, theme.axis_color, theme.scale
        )
        # Caps across each whisker's end.
        orient.band_line(
            target, _round_to_int(high), _round_to_int(center - cap_half),
            _round_to_int(center + cap_half), theme.axis_color, theme.scale,
        )
        orient.band_line(
            target, _round_to_int(low), _round_to_int(center - cap_half),
            _round_to_int(center + cap_half), theme.axis_color, theme.scale,
        )
        # The interquartile box, then the median line across it.
        var box_near = _round_to_int(min(q1, q3))
        var box_span = _round_to_int(max(q1, q3) - min(q1, q3))
        orient.fill_band_rect(
            target, _BaselineRect(box_near, box_span), _round_to_int(center - half),
            _round_to_int(band_size), theme.mark_color,
        )
        orient.band_line(
            target, _round_to_int(median), _round_to_int(center - half),
            _round_to_int(center + half), theme.axis_color, theme.scale,
        )

    for j in range(len(plot._box.outlier_value)):
        orient.band_point(
            target,
            _axis_pixel(value_scale, plot._box.outlier_value[j]),
            _round_to_int(band_scale.center(plot._box.outlier_cat[j])),
            point_radius,
            theme.mark_color,
        )


def _render_box[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.BOX` plot: `_draw_categorical_axis_frame`'s
    shared categorical x-axis, but a y-domain spanning every point that
    will actually be drawn (`_data_extent` -- padded, but *not* forced
    to include zero the way `Mark.BAR`/`LOLLIPOP`/`WATERFALL`'s domains
    are; a box plot shows a distribution's spread, which has no
    inherent reason to include zero) over each category's whiskers
    and outliers (`_box`'s `low`/`high`/`outlier_value` --
    exactly the values this function goes on to draw, so the domain is
    guaranteed to fit every one of them with no separate pass over the
    original raw data `encode_boxplot()` already reduced away).

    Draws, per category, back to front: the two whiskers (`Q3` up to
    `high`, `Q1` down to `low`) with a small horizontal cap at each end,
    then the box itself (`Q1` to `Q3`, `theme.mark_color`) over the
    whiskers' center so the box visually "contains" them, then the
    median line (`theme.axis_color`) on top of the box fill. Outliers
    are drawn in one final pass *after* every category's box/
    whiskers, not interleaved per category -- so one category's outlier point is never occluded by a neighboring category's box.
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
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var domain_data = List[Float64]()
    for v in plot._box.low:
        domain_data.append(v)
    for v in plot._box.high:
        domain_data.append(v)
    for v in plot._box.outlier_value:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    _draw_box_glyphs(
        target, plot, frame.x_scale, frame.y_scale, _Orientation(False), _round_to_int(frame.sc.point_radius)
    )

    return frame.result()


def _render_horizontal_box[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """`_render_box`'s mirror image for `Plot.mark_box(horizontal=
    True)` (#121) -- exactly `_render_horizontal_bar`'s own categorical
    y-axis (`_draw_horizontal_categorical_axis_frame`, gantt.mojo,
    shared -- see that function's docstring) instead of a categorical
    x-axis, with the continuous axis (`_data_extent`, not zero-forced --
    see `_render_box`'s own docstring for why) carried along the
    bottom instead of up the left side.

    Every role `_render_box` gives `x_scale`/`y_scale` swaps here:
    the two whiskers become horizontal lines (`Q3` out to `high`, `Q1`
    out to `low`) with a small *vertical* cap at each end instead of a
    horizontal one, the box itself becomes a horizontal rect (`Q1` to
    `Q3`) spanning the category's own band *height*, and the median
    line is drawn vertically across the box's own height instead of
    horizontally across its width. Outliers plot at `(value's x pixel,
    category's y-center)` instead of the reverse. Otherwise the exact
    same per-category five-number-summary drawing `_render_box`'s own
    docstring explains, just rotated.

    Deliberately its own function, not an orientation flag threaded
    through `_render_box` -- see `_render_horizontal_bar`'s own
    docstring (bar.mojo) for the full reasoning, identical here.
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
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

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
        target, plot, frame.y_scale, frame.x_scale, _Orientation(True), _round_to_int(frame.sc.point_radius)
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
    """A box plot -- `Mark.BOX`, one box-and-whiskers per category
    summarizing a whole distribution of raw values (`values[i]`, not
    a single number). See `Plot.encode_boxplot()`'s docstring
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
    var plot = Plot().mark_box(horizontal=horizontal).encode_boxplot(categories=categories, values=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


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
    """`box()`, generalized over numeric element type for `values`
    -- see `beeswarm()`'s own `DType`-generic overload for the full
    reasoning. Delegates to the concrete `box()` above.
    """
    return box(
        categories, _materialize_nested_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title, horizontal=horizontal,
    )
