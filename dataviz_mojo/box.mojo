from canvas_mojo.geometry import _round_to_int
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
    _rendered,
)
from dataviz_mojo.theme import Theme


def _percentile(sorted_values: List[Float64], p: Float64) -> Float64:
    """The `p`-th percentile (`p` in `[0, 1]`) of `sorted_values`
    (already sorted ascending -- callers, not this function, own that,
    since `_box_stats` already needs a sorted copy for its own whisker
    scan and there's no reason to sort twice) via linear interpolation
    between the two nearest ranks -- the same method `numpy.percentile`'s
    own default (`"linear"`) uses. `sorted_values` must be non-empty;
    `_box_stats`'s own caller (`Plot.encode_boxplot()`) raises before
    this could ever run on an empty list.
    """
    var n = len(sorted_values)
    var idx = p * Float64(n - 1)
    var lo = Int(idx)
    var hi = lo + 1 if lo + 1 < n else lo
    var frac = idx - Float64(lo)
    return sorted_values[lo] + frac * (sorted_values[hi] - sorted_values[lo])


struct _BoxStats(Movable):
    """`_box_stats()`'s own result -- a box plot's conventional five-
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
    1.5*IQR of the box (not simply `values`' own min/max -- a whisker
    stops at the last real data point inside the fence, the entire
    point of separating "whisker" from "outlier"), and every value
    beyond that fence as its own outlier. `values` must be non-empty --
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


def _render_box[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.BOX` plot: `_draw_categorical_axis_frame`'s
    shared categorical x-axis, but a y-domain spanning every point that
    will actually be drawn (`_data_extent` -- padded, but *not* forced
    to include zero the way `Mark.BAR`/`LOLLIPOP`/`WATERFALL`'s domains
    are; a box plot shows a distribution's own spread, which has no
    inherent reason to include zero) over each category's own whiskers
    and outliers (`_box_low`/`_box_high`/`_box_outlier_value` --
    exactly the values this function goes on to draw, so the domain is
    guaranteed to fit every one of them with no separate pass over the
    original raw data `encode_boxplot()` already reduced away).

    Draws, per category, back to front: the two whiskers (`Q3` up to
    `high`, `Q1` down to `low`) with a small horizontal cap at each end,
    then the box itself (`Q1` to `Q3`, `theme.mark_color`) over the
    whiskers' own center so the box visually "contains" them, then the
    median line (`theme.axis_color`) on top of the box fill. Outliers
    are drawn in one final pass *after* every category's own box/
    whiskers, not interleaved per category -- so one category's own
    outlier point is never occluded by a neighboring category's box.
    """
    if len(plot.x_categories) != len(plot._box_q1):
        raise Error(
            "Plot.encode_boxplot(): categories and values must have the"
            " same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot._box_q1))
            + ")"
        )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var domain_data = List[Float64]()
    for v in plot._box_low:
        domain_data.append(v)
    for v in plot._box_high:
        domain_data.append(v)
    for v in plot._box_outlier_value:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    var band_w = frame.x_scale.bandwidth()
    for i in range(len(plot.x_categories)):
        var center = frame.x_scale.center(i)
        var half_w = band_w / 2.0
        var cap_half_w = band_w / 4.0

        var q1_py = frame.y_scale.to_pixel(plot._box_q1[i])
        var q3_py = frame.y_scale.to_pixel(plot._box_q3[i])
        var median_py = frame.y_scale.to_pixel(plot._box_median[i])
        var low_py = frame.y_scale.to_pixel(plot._box_low[i])
        var high_py = frame.y_scale.to_pixel(plot._box_high[i])

        var center_i = _round_to_int(center)
        target.draw_line_aa(center_i, _round_to_int(high_py), center_i, _round_to_int(q3_py), theme.axis_color)
        target.draw_line_aa(center_i, _round_to_int(q1_py), center_i, _round_to_int(low_py), theme.axis_color)
        target.draw_line_aa(
            _round_to_int(center - cap_half_w),
            _round_to_int(high_py),
            _round_to_int(center + cap_half_w),
            _round_to_int(high_py),
            theme.axis_color,
        )
        target.draw_line_aa(
            _round_to_int(center - cap_half_w),
            _round_to_int(low_py),
            _round_to_int(center + cap_half_w),
            _round_to_int(low_py),
            theme.axis_color,
        )

        var box_x = _round_to_int(center - half_w)
        var box_y = _round_to_int(min(q1_py, q3_py))
        var box_h = _round_to_int(max(q1_py, q3_py) - min(q1_py, q3_py))
        target.fill_rect(box_x, box_y, _round_to_int(band_w), box_h, theme.mark_color)

        target.draw_line_aa(
            _round_to_int(center - half_w), _round_to_int(median_py), _round_to_int(center + half_w),
            _round_to_int(median_py), theme.axis_color,
        )

    for j in range(len(plot._box_outlier_value)):
        var cat_i = plot._box_outlier_cat[j]
        var center_px = _round_to_int(frame.x_scale.center(cat_i))
        var value_py = _axis_pixel(frame.y_scale, plot._box_outlier_value[j])
        target.fill_circle_aa(center_px, value_py, _round_to_int(frame.sc.point_radius), theme.mark_color)

    return frame.result()


def box(
    categories: List[String],
    values: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A box plot -- `Mark.BOX`, one box-and-whiskers per category
    summarizing a whole distribution of raw values (`values[i]`, not
    a single number). See `Plot.encode_boxplot()`'s own docstring
    (plot.mojo) for the quartile/whisker/outlier computation, and
    plot.mojo's own module docstring for the shared parameters every
    function here takes."""
    var plot = Plot().mark_box().encode_boxplot(categories=categories, values=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
