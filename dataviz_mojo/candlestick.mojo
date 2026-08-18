"""Mark.CANDLESTICK's own rendering -- see Plot.mark_candlestick()'s
own docstring (plot.mojo) for what the mark means; `_render_
candlestick` is what `_render_generic` (plot.mojo) dispatches to.
"""

from canvas_mojo.geometry import _round_to_int
from canvas_mojo.vector.draw_target import DrawTarget

from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _TextRequest,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
)
from dataviz_mojo.theme import Theme


def _render_candlestick[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.CANDLESTICK` plot: `_draw_categorical_axis_frame`'s
    shared categorical x-axis, with a y-domain spanning every open/high/
    low/close value actually drawn (`_data_extent`, padded but *not*
    forced through zero -- the same reasoning `Mark.BOX` already
    established: a candlestick chart's whole point is showing fine
    detail in a price range that's typically nowhere near zero, so
    forcing zero into view would flatten exactly the detail the chart
    exists to show).

    Draws, per category, back to front (the same "whisker under the
    box" order `_render_box` already established, so a wick with a
    short body still reads as one shape, not two disconnected pieces):
    a thin wick (`draw_line_aa`, `theme.axis_color` -- matching `Mark.
    BOX`'s own whisker color, both being "the part of the shape that
    isn't the headline value") from `high` to `low`, then the body
    itself (`fill_rect`, full band width -- the same "use the whole
    band, no extra narrowing" choice `Mark.BAR`/`BOX` already make) from
    `open` to `close`, colored by `close >= open`: `theme.mark_color`
    (closed up) or `theme.mark_color_negative` (closed down). These are
    the *same* two fields `Mark.WATERFALL` already reuses for its own
    unconditional sign coloring, not new dedicated bullish/bearish
    fields -- a candlestick's whole reason for being colored by sign
    *is* the chart, the same "not gated behind an opt-in flag" reasoning
    `encode_waterfall()`'s own docstring gives (contrast `Mark.BAR`'s
    `Theme.color_by_sign`, which stays a real opt-in there since a plain
    bar chart is still a complete, correct chart without it).

    A doji (`open == close` exactly) would otherwise draw a zero-height
    rect -- `fill_rect` treats that as a no-op (see its own tests), which
    would make the body invisible against its own wick, when a real
    candlestick chart shows a doji as a thin flat body -- so body height
    is floored at 1px, not left to `fill_rect`'s own zero-size handling.
    """
    if len(plot.x_categories) != len(plot._candle_open):
        raise Error(
            "Plot.encode_candlestick(): categories and open/high/low/close"
            " must all have the same length (got "
            + String(len(plot.x_categories))
            + " categories and "
            + String(len(plot._candle_open))
            + " open values)"
        )
    if (
        len(plot._candle_high) != len(plot._candle_open)
        or len(plot._candle_low) != len(plot._candle_open)
        or len(plot._candle_close) != len(plot._candle_open)
    ):
        raise Error(
            "Plot.encode_candlestick(): open, high, low, and close must"
            " all have the same length (got "
            + String(len(plot._candle_open))
            + ", "
            + String(len(plot._candle_high))
            + ", "
            + String(len(plot._candle_low))
            + ", "
            + String(len(plot._candle_close))
            + ")"
        )

    var theme = plot._theme
    target.fill_rect(ox0, oy0, ox1 - ox0, oy1 - oy0, theme.background)

    var text_requests = List[_TextRequest]()
    if len(plot.x_categories) == 0:
        return _RenderResult(text_requests^, ox0, oy0, ox1, oy1)

    var domain_data = List[Float64]()
    for v in plot._candle_open:
        domain_data.append(v)
    for v in plot._candle_high:
        domain_data.append(v)
    for v in plot._candle_low:
        domain_data.append(v)
    for v in plot._candle_close:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1)

    for i in range(len(plot.x_categories)):
        var center_px = _round_to_int(frame.x_scale.center(i))
        var high_py = _axis_pixel(frame.y_scale, plot._candle_high[i])
        var low_py = _axis_pixel(frame.y_scale, plot._candle_low[i])
        target.draw_line_aa(center_px, high_py, center_px, low_py, theme.axis_color)

        var open_py = _axis_pixel(frame.y_scale, plot._candle_open[i])
        var close_py = _axis_pixel(frame.y_scale, plot._candle_close[i])
        var body_x = _round_to_int(frame.x_scale.band_start(i))
        var body_width = _round_to_int(frame.x_scale.bandwidth())
        var body_y = min(open_py, close_py)
        var body_height = max(1, max(open_py, close_py) - min(open_py, close_py))
        var body_color = (
            theme.mark_color if plot._candle_close[i] >= plot._candle_open[i] else theme.mark_color_negative
        )
        target.fill_rect(body_x, body_y, body_width, body_height, body_color)

    return _RenderResult(frame.text_requests.copy(), frame.px0, frame.py0, frame.px1, frame.py1)
