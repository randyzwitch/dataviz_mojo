from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _draw_categorical_axis_frame,
    _empty_result,
    _rendered,
    _zero_baseline_y_extent,
)
from dataviz_mojo.theme import Theme


struct _WaterfallData(Movable):
    """
    Mark.WATERFALL only -- the running-total bounds encode_waterfall()
    computes from each category's signed delta (y_data), see that
    method's docstring.

    Grouped onto `Plot._waterfall` -- see `Plot`'s docstring.
    """

    var y0: List[Float64]
    var y1: List[Float64]
    var is_total: List[Bool]

    def __init__(out self):
        self.y0 = List[Float64]()
        self.y1 = List[Float64]()
        self.is_total = List[Bool]()



struct _WaterfallBars(Movable):
    """The two running-total bounds `_render_waterfall` draws each bar
    between -- `y0[i]`/`y1[i]` are the running total immediately
    before/after category `i`'s delta is applied (or `0`/the new
    running total for a checkpoint row -- see `_waterfall_running_
    totals()`'s docstring for the exact rule)."""

    var y0: List[Float64]
    var y1: List[Float64]

    def __init__(out self, var y0: List[Float64], var y1: List[Float64]):
        self.y0 = y0^
        self.y1 = y1^


def _waterfall_running_totals(deltas: List[Float64], is_total: List[Bool]) -> _WaterfallBars:
    """Computes each bar's `y0`/`y1` bounds from a running
    cumulative sum over `deltas`, starting at 0.0 (the conventional
    waterfall starting point) -- extracted out of `Plot.encode_
    waterfall()`'s body (plot.mojo) so this running-sum math lives
    next to `_render_waterfall`, the only other place Mark.WATERFALL-
    specific logic lives.

    `is_total[i]` (checked defensively as `False` when `i` falls
    outside `is_total`'s length, so a short/empty list never
    indexes out of bounds -- the actual length-matches-`deltas` check
    happens at `render()` time, like every other length check `Plot`'s `encode_*` methods defer) changes only how row `i` draws: a
    plain delta row floats from the running total *before* its delta (`y0`) to the total *after* it (`y1`); a total/checkpoint row
    instead draws from `0` up to the running total *after* its delta is applied, regardless of what the running total was before.
    `deltas[i]` itself always means the same thing either way, still
    added to the running sum every time -- see `Plot.encode_waterfall(
    )`'s docstring (plot.mojo) for the full start-then-deltas-
    then-end story this enables.
    """
    var y0 = List[Float64]()
    var y1 = List[Float64]()
    var running = 0.0
    for i in range(len(deltas)):
        var row_is_total = is_total[i] if i < len(is_total) else False
        var before = running
        running += deltas[i]
        if row_is_total:
            y0.append(0.0)
            y1.append(running)
        else:
            y0.append(before)
            y1.append(running)
    return _WaterfallBars(y0^, y1^)


def _render_waterfall[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.WATERFALL` plot: `_draw_categorical_axis_frame`'s
    shared categorical x-axis, but a y-domain spanning every bar's running-total *bounds* (`_waterfall`'s `y0` union `y1`, not
    `plot.y_data` -- the deltas themselves, not the cumulative totals
    they add up to, would badly understate the actual pixel range a
    running total can reach), still forced to include zero
    (`_zero_baseline_y_extent`) since every waterfall's running
    total conventionally starts there.

    Each category draws a floating rect from its `y0` to `y1`
    (`encode_waterfall()`'s running-sum bookkeeping -- see that
    method's docstring). A plain delta row colors by its delta's
    sign unconditionally (`theme.mark_color_negative`/`mark_color`, not
    gated by `Theme.color_by_sign` the way `Mark.BAR`'s diverging
    coloring is -- see `encode_waterfall()`'s docstring for why). A
    total row colors `theme.waterfall_total_color` instead and always
    draws the *full* band width (`Mark.BAR`'s convention).

    A delta row draws narrower than the full band (`_WATERFALL_DELTA_
    WIDTH_FRACTION`, centered) *only when this plot actually uses total
    rows at all* (`plot._waterfall.is_total` non-empty) -- if `is_total`
    was never passed to `encode_waterfall()` (every existing call from
    before total rows existed), every bar stays full band width,
    unchanged, purely additive; only once a caller actually opts into
    at least one total row does the narrow-vs-full distinction have
    anything to distinguish, and only then does it apply. The two
    intentionally read as visually distinct at a glance in that case,
    not just by
    color (see `Theme.waterfall_total_color`'s docstring).

    Every bar's actual left/right pixel edges are computed once,
    per category, into `bar_x`/`bar_width` lists -- then reused for the
    connector-line pass below, rather than each connector re-deriving
    an edge from the *band's* own boundary directly: a narrower delta
    bar's edges don't coincide with its band's, so the connector has
    to ask each bar what it actually drew, not assume. The connector
    itself (`theme.axis_color`, not `gridline_color` -- visually
    indistinguishable from the y-axis's gridlines once rendered,
    defeating the point of a connector at all) still runs between
    consecutive bars at the pixel height
    `y1[i-1]` -- always exactly horizontal (a single Y value, drawn from
    one bar's actual right edge to the next's actual left edge).
    For two plain delta rows in a row, this touches both bars' shared edge exactly (`y1[i-1] == y0[i]` always, by construction).
    When row `i` is a total, its `y0` is fixed at `0`, not `y1
    [i-1]` -- so the connector still lands at the objectively correct
    height (where the running total stood *entering* this row), but
    only touches that total bar's top edge exactly when its delta is `0` (the common ending-balance case, and every case
    `examples/waterfall.mojo` demonstrates) -- a total row with a real
    nonzero delta of its would show the connector landing partway
    up the bar instead of at an edge, a deliberately accepted rough
    edge for a use case this package hasn't needed yet, not a bug in
    the common case.
    """
    if len(plot.x_categories) != len(plot.y_data):
        raise Error(
            "Plot.encode_waterfall(): categories and deltas must have the"
            " same length (got "
            + String(len(plot.x_categories))
            + " and "
            + String(len(plot.y_data))
            + ")"
        )
    if len(plot._waterfall.is_total) > 0 and len(plot._waterfall.is_total) != len(plot.x_categories):
        raise Error(
            "Plot.encode_waterfall(): is_total, if given, must have the"
            " same length as categories (got "
            + String(len(plot._waterfall.is_total))
            + " and "
            + String(len(plot.x_categories))
            + ")"
        )

    var theme = plot._theme
    if len(plot.x_categories) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var combined = List[Float64]()
    for v in plot._waterfall.y0:
        combined.append(v)
    for v in plot._waterfall.y1:
        combined.append(v)
    var y_scale = _zero_baseline_y_extent(combined)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    # Delta bars only narrow when is_total is actually in use somewhere
    # on this plot -- if it's empty (no caller ever opted into total
    # rows), every bar stays full band width, byte-for-byte the same as
    # every render from before total rows existed. Only once at least
    # one row is genuinely a total does the narrow-vs-full distinction
    # have anything to distinguish.
    var using_totals = len(plot._waterfall.is_total) > 0

    # Only recorded when is_total is actually in use -- that's the only
    # case the connector pass below reads them back (a delta bar can be
    # narrower than its band then, so a connector has to ask the
    # previous bar what it actually drew). With no total rows the
    # connector re-derives the edge from the band directly, for the
    # byte-compatibility reason its comment gives, and these two
    # lists would just be filled and never read.
    var bar_x_list = List[Int]()
    var bar_width_list = List[Int]()
    var bandwidth = frame.x_scale.bandwidth()
    for i in range(len(plot.x_categories)):
        var band_start = frame.x_scale.band_start(i)
        var row_is_total = plot._waterfall.is_total[i] if i < len(plot._waterfall.is_total) else False
        var bar_x: Int
        var bar_width: Int
        if row_is_total or not using_totals:
            bar_x = _round_to_int(band_start)
            bar_width = _round_to_int(bandwidth)
        else:
            var narrow_width = bandwidth * theme.waterfall_delta_width_fraction
            var inset = (bandwidth - narrow_width) / 2.0
            bar_x = _round_to_int(band_start + inset)
            bar_width = _round_to_int(band_start + inset + narrow_width) - bar_x
        if using_totals:
            bar_x_list.append(bar_x)
            bar_width_list.append(bar_width)

        var y0_py = _axis_pixel(frame.y_scale, plot._waterfall.y0[i])
        var y1_py = _axis_pixel(frame.y_scale, plot._waterfall.y1[i])
        var bar_y = min(y0_py, y1_py)
        var bar_height = max(y0_py, y1_py) - min(y0_py, y1_py)
        var bar_color = (
            theme.waterfall_total_color
            if row_is_total
            else (theme.mark_color_negative if plot.y_data[i] < 0.0 else theme.mark_color)
        )
        target.fill_rect(bar_x, bar_y, bar_width, bar_height, bar_color)

        if i > 0:
            var prev_end_py = _axis_pixel(frame.y_scale, plot._waterfall.y1[i - 1])
            # using_totals=False reproduces the exact original formula
            # here (band_start+bandwidth, summed then rounded once, not
            # `bar_x[i-1] + bar_width[i-1]`'s two independently-
            # rounded pieces) -- purely additive, byte-for-byte
            # unchanged from every render before total rows existed.
            # using_totals=True instead asks the previous bar what it
            # actually drew, needed once a delta bar can be narrower
            # than its band -- no backward-compatible formula to
            # preserve there, since that combination is new.
            var prev_x1 = (
                bar_x_list[i - 1] + bar_width_list[i - 1]
                if using_totals
                else _round_to_int(frame.x_scale.band_start(i - 1) + frame.x_scale.bandwidth())
            )
            target.draw_line_aa(prev_x1, prev_end_py, bar_x, prev_end_py, theme.axis_color, width=theme.scale)

    return frame.result()


def waterfall(
    categories: List[String],
    deltas: List[Float64],
    is_total: List[Bool] = List[Bool](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A waterfall chart -- `Mark.WATERFALL`, floating bars from a
    running total. See `Plot.encode_waterfall()`'s docstring
    (plot.mojo) for what `deltas`/`is_total` mean."""
    var plot = Plot().mark_waterfall().encode_waterfall(categories=categories, deltas=deltas, is_total=is_total)
    return _rendered(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)
