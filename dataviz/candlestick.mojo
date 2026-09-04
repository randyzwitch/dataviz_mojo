from canvas.geometry import _round_to_int
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _RenderResult,
    _axis_pixel,
    _data_extent,
    _draw_categorical_axis_frame,
    _finished,
    _require_non_empty,
)
from dataviz.theme import Theme


struct _CandleData(Copyable, Movable):
    """One open/high/low/close value per category, for `Mark.CANDLESTICK`.
    See `encode_candlestick()`. Stored on `Plot._candle`.
    """

    var open_price: List[Float64]
    var high: List[Float64]
    var low: List[Float64]
    var close_price: List[Float64]

    def __init__(out self):
        self.open_price = List[Float64]()
        self.high = List[Float64]()
        self.low = List[Float64]()
        self.close_price = List[Float64]()


def _render_candlestick[
    T: DrawTarget
](
    mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int
) raises -> _RenderResult:
    """Render a `Mark.CANDLESTICK` plot: `_draw_categorical_axis_frame`'s
    categorical x-axis, with a y-domain spanning every open/high/low/close
    value (`_data_extent`, padded but not forced through zero, since price
    ranges are typically nowhere near zero; the same choice `Mark.BOX`
    makes).

    Per category, back to front: a thin wick (`draw_line_aa`,
    `theme.axis_color`, matching `Mark.BOX`'s whisker color) from `high`
    to `low`, then the body (`fill_rect`, full band width) from `open` to
    `close`, colored `theme.mark_color` when `close >= open` and
    `theme.mark_color_negative` otherwise. These are the same two fields
    `Mark.WATERFALL` uses for its sign coloring; unlike `Mark.BAR`'s
    opt-in `Theme.color_by_sign`, a candlestick is always colored by sign.

    Body height is floored at 1px so a doji (`open == close`) draws as a
    thin flat body rather than `fill_rect`'s zero-height no-op.
    """
    if len(plot.x_categories) != len(plot._candle.open_price):
        raise Error(
            "Plot.encode_candlestick(): categories and open/high/low/close"
            " must all have the same length (got "
            + String(len(plot.x_categories))
            + " categories and "
            + String(len(plot._candle.open_price))
            + " open values)"
        )
    if (
        len(plot._candle.high) != len(plot._candle.open_price)
        or len(plot._candle.low) != len(plot._candle.open_price)
        or len(plot._candle.close_price) != len(plot._candle.open_price)
    ):
        raise Error(
            "Plot.encode_candlestick(): open, high, low, and close must"
            " all have the same length (got "
            + String(len(plot._candle.open_price))
            + ", "
            + String(len(plot._candle.high))
            + ", "
            + String(len(plot._candle.low))
            + ", "
            + String(len(plot._candle.close_price))
            + ")"
        )

    var theme = plot._theme
    _require_non_empty(len(plot.x_categories), "Plot.encode_candlestick()")
    var domain_data = List[Float64]()
    for v in plot._candle.open_price:
        domain_data.append(v)
    for v in plot._candle.high:
        domain_data.append(v)
    for v in plot._candle.low:
        domain_data.append(v)
    for v in plot._candle.close_price:
        domain_data.append(v)
    var y_scale = _data_extent(domain_data)

    var frame = _draw_categorical_axis_frame(
        target, plot.x_categories, y_scale, theme, ox0, oy0, ox1, oy1
    )

    var body_width = _round_to_int(frame.x_scale.bandwidth())
    for i in range(len(plot.x_categories)):
        var center_px = _round_to_int(frame.x_scale.center(i))
        var high_py = _axis_pixel(frame.y_scale, plot._candle.high[i])
        var low_py = _axis_pixel(frame.y_scale, plot._candle.low[i])
        target.draw_line_aa(
            center_px,
            high_py,
            center_px,
            low_py,
            theme.axis_color,
            width=theme.scale,
        )

        var open_py = _axis_pixel(frame.y_scale, plot._candle.open_price[i])
        var close_py = _axis_pixel(frame.y_scale, plot._candle.close_price[i])
        var body_x = _round_to_int(frame.x_scale.band_start(i))
        var body_y = min(open_py, close_py)
        var body_height = max(
            1, max(open_py, close_py) - min(open_py, close_py)
        )
        var body_color = (
            theme.mark_color if plot._candle.close_price[i]
            >= plot._candle.open_price[i] else theme.mark_color_negative
        )
        target.fill_rect(body_x, body_y, body_width, body_height, body_color)

    return frame.result()


def candlestick(
    categories: List[String],
    open: List[Float64],
    high: List[Float64],
    low: List[Float64],
    close: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A candlestick chart, the open/high/low/close convention that
    originated with 18th-century Japanese rice traders: each bar's body
    shows the open-to-close range and its wicks the period's full
    high/low, so a price's direction and volatility read at a glance.

    `Mark.CANDLESTICK`: one open/high/low/close bar per category.

    Args:
        categories: One bar per entry, in the given order.
        open: Each category's opening value.
        high: Each category's highest value -- the wick's top.
        low: Each category's lowest value -- the wick's bottom.
        close: Each category's closing value; the body is colored by
            whether it closed up (`mark_color`) or down
            (`mark_color_negative`) relative to `open`.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from dataviz import candlestick
        from dataviz.plot import save
        from dataviz.theme import Theme

        def main() raises:
            var days: List[String] = [
                "Day 1", "Day 2", "Day 3", "Day 4", "Day 5", "Day 6", "Day 7", "Day 8",
            ]
            var open: List[Int] = [100, 104, 101, 97, 107, 110, 103, 108]
            var high: List[Int] = [106, 105, 103, 108, 112, 111, 109, 110]
            var low: List[Int] = [98, 99, 95, 96, 105, 102, 101, 104]
            var close: List[Int] = [104, 101, 97, 107, 110, 103, 108, 105]

            var c = candlestick(days, open, high, low, close)
            save(c, "docs/src/examples/out_candlestick.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_candlestick()
        .encode_candlestick(
            categories=categories, open=open, high=high, low=low, close=close
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def candlestick[
    dtype: DType
](
    categories: List[String],
    open: List[Scalar[dtype]],
    high: List[Scalar[dtype]],
    low: List[Scalar[dtype]],
    close: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`candlestick()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (plot.mojo).
    `open`/`high`/`low`/`close` share one dtype. Delegates to the concrete
    overload above.
    """
    return candlestick(
        categories,
        _materialize_scalar_list(open),
        _materialize_scalar_list(high),
        _materialize_scalar_list(low),
        _materialize_scalar_list(close),
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
    )
