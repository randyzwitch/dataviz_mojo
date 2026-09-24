from canvas.geometry import round_to_int
from canvas.text.font_cache import FontCache
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame
from morrow import Morrow

from dataviz.core.frame_input import (
    _frame_column,
    _frame_floats,
    _frame_morrow,
    _frame_strings,
)
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.plot import (
    Plot,
    _RenderResult,
    _TextRequest,
    _axis_pixel_f,
    snap_to_pixel_center,
    snap_to_pixel_edge,
    _data_extent,
    _draw_categorical_axis_frame,
    _draw_continuous_axis_frame,
    _LegendLayout,
    _Scaled,
    _finished,
    _require_non_empty,
)
from dataviz.core.scale import LinearScale, _format_fixed, _label_decimals
from dataviz.core.theme import Theme


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


def _candle_tooltip_label(
    category: String,
    open_price: Float64,
    high: Float64,
    low: Float64,
    close_price: Float64,
) -> String:
    """One candle's hover text: `"Mon: O 10, H 14, L 9, C 13"`. All four
    prices, since that quadruple is exactly what the wick and body
    encode -- the same reasoning as `Mark.BOX`'s five-number tooltip.
    """
    return (
        category
        + ": O "
        + _format_fixed(open_price, _label_decimals(open_price))
        + ", H "
        + _format_fixed(high, _label_decimals(high))
        + ", L "
        + _format_fixed(low, _label_decimals(low))
        + ", C "
        + _format_fixed(close_price, _label_decimals(close_price))
    )


def _candle_y_domain(plot: Plot) raises -> LinearScale:
    var values = List[Float64]()
    for v in plot._candle.open_price:
        values.append(v)
    for v in plot._candle.high:
        values.append(v)
    for v in plot._candle.low:
        values.append(v)
    for v in plot._candle.close_price:
        values.append(v)
    return _data_extent(values)


def _draw_candles[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    centers: List[Float64],
    starts: List[Float64],
    ends: List[Float64],
    y_scale: LinearScale,
    sc: _Scaled,
    mut text_requests: List[_TextRequest],
) raises:
    """Wicks and bodies, shared by categorical and time x axes."""
    var theme = plot._theme
    var tooltips_on = plot._tooltips_on(len(centers))
    for i in range(len(centers)):
        var center_px = snap_to_pixel_center(centers[i])
        var high_py = _axis_pixel_f(y_scale, plot._candle.high[i])
        var low_py = _axis_pixel_f(y_scale, plot._candle.low[i])
        if tooltips_on:
            target.begin_annotated_group(
                _candle_tooltip_label(
                    plot._categorical.x[i],
                    plot._candle.open_price[i],
                    plot._candle.high[i],
                    plot._candle.low[i],
                    plot._candle.close_price[i],
                )
            )
        target.draw_line_aa(
            center_px,
            high_py,
            center_px,
            low_py,
            theme.axis_color,
            width=theme.scale,
        )

        var open_py = _axis_pixel_f(y_scale, plot._candle.open_price[i])
        var close_py = _axis_pixel_f(y_scale, plot._candle.close_price[i])
        var bx0 = snap_to_pixel_edge(starts[i])
        var bx1 = snap_to_pixel_edge(ends[i])
        var by0 = snap_to_pixel_edge(min(open_py, close_py))
        var by1 = snap_to_pixel_edge(max(open_py, close_py))
        if by1 - by0 < 1.0:
            by1 = by0 + 1.0
        var body_color = (
            theme.mark_color if plot._candle.close_price[i]
            >= plot._candle.open_price[i] else theme.mark_color_negative
        )
        target.fill_rect(bx0, by0, bx1 - bx0, by1 - by0, body_color)
        if tooltips_on:
            target.end_annotated_group()
        if theme.show_data_labels:
            var close = plot._candle.close_price[i]
            text_requests.append(
                _TextRequest(
                    round_to_int(center_px),
                    round_to_int(high_py) - sc.label_gap,
                    _format_fixed(close, _label_decimals(close)),
                    theme.text_color,
                    sc.font_size,
                    TextAlign.CENTER,
                    theme.font_family,
                )
            )


def _time_candle_width(seconds: List[Float64]) raises -> Float64:
    """Seventy percent of median spacing, capped by the shortest gap.

    The cap keeps sparse weekends from making two adjacent trading days'
    bodies overlap. A lone candle gets a one-day reference interval.
    """
    if len(seconds) == 1:
        return 86400.0 * 0.7
    var sorted = seconds.copy()
    sort(sorted)
    var gaps = List[Float64](capacity=len(sorted) - 1)
    for i in range(1, len(sorted)):
        var gap = sorted[i] - sorted[i - 1]
        if gap <= 0.0:
            raise Error(
                "Plot.encode_candlestick_time(): timestamps must be distinct"
            )
        gaps.append(gap)
    sort(gaps)
    var mid = len(gaps) // 2
    var median = gaps[mid] if len(gaps) % 2 == 1 else (
        (gaps[mid - 1] + gaps[mid]) / 2.0
    )
    return min(0.7 * median, 0.8 * gaps[0])


def _render_candlestick[
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
    """Render OHLC candles on categorical bands or real timestamps."""
    var n = len(plot._candle.open_price)
    if len(plot._categorical.x) != n:
        raise Error(
            "Plot.encode_candlestick(): categories and open/high/low/close"
            " must all have the same length (got "
            + String(len(plot._categorical.x))
            + " categories and "
            + String(n)
            + " open values)"
        )
    if (
        len(plot._candle.high) != n
        or len(plot._candle.low) != n
        or len(plot._candle.close_price) != n
    ):
        raise Error(
            "Plot.encode_candlestick(): open, high, low, and close must"
            " all have the same length (got "
            + String(n)
            + ", "
            + String(len(plot._candle.high))
            + ", "
            + String(len(plot._candle.low))
            + ", "
            + String(len(plot._candle.close_price))
            + ")"
        )
    _require_non_empty(n, "Plot.encode_candlestick()")
    var theme = plot._theme
    var y_scale = _candle_y_domain(plot)
    var centers = List[Float64](capacity=n)
    var starts = List[Float64](capacity=n)
    var ends = List[Float64](capacity=n)

    if plot._x_time:
        if len(plot._continuous.x) != n:
            raise Error(
                "Plot.encode_candlestick_time(): dates and open/high/low/close"
                " must have the same length"
            )
        var width_seconds = _time_candle_width(plot._continuous.x)
        var earliest = plot._continuous.x[0]
        var latest = earliest
        for seconds in plot._continuous.x:
            earliest = min(earliest, seconds)
            latest = max(latest, seconds)
        var x_scale = LinearScale(
            earliest - width_seconds, latest + width_seconds, 0.0, 1.0
        )
        x_scale.is_time = True
        x_scale.tz_offset = plot._x_tz_offset
        var time_frame = _draw_continuous_axis_frame(
            target,
            x_scale,
            y_scale,
            theme,
            _LegendLayout(),
            ox0,
            oy0,
            ox1,
            oy1,
            cache=cache,
        )
        for seconds in plot._continuous.x:
            centers.append(_axis_pixel_f(time_frame.x_scale, seconds))
            starts.append(
                _axis_pixel_f(time_frame.x_scale, seconds - width_seconds / 2.0)
            )
            ends.append(
                _axis_pixel_f(time_frame.x_scale, seconds + width_seconds / 2.0)
            )
        _draw_candles(
            target,
            plot,
            centers,
            starts,
            ends,
            time_frame.y_scale,
            time_frame.sc,
            time_frame.text_requests,
        )
        return time_frame.result()

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
    for i in range(n):
        centers.append(frame.x_scale.center(i))
        starts.append(frame.x_scale.band_start(i))
        ends.append(frame.x_scale.band_start(i) + frame.x_scale.bandwidth())
    _draw_candles(
        target,
        plot,
        centers,
        starts,
        ends,
        frame.y_scale,
        frame.sc,
        frame.text_requests,
    )
    return frame.result()


def candlestick(
    df: DataFrame,
    categories: String,
    open: String,
    high: String,
    low: String,
    close: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`candlestick()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        categories: A string category or date/datetime time column.
        open: The numeric column for this channel.
        high: The numeric column for this channel.
        low: The numeric column for this channel.
        close: The numeric column for this channel.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.
        x_title: See the list overload.
        y_title: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var category_dtype = _frame_column(df, categories, "candlestick()").dtype()
    var open_values = _frame_floats(df, open, "candlestick()", theme.missing)
    var high_values = _frame_floats(df, high, "candlestick()", theme.missing)
    var low_values = _frame_floats(df, low, "candlestick()", theme.missing)
    var close_values = _frame_floats(df, close, "candlestick()", theme.missing)
    if category_dtype.is_date() or category_dtype.is_datetime():
        return candlestick(
            dates=_frame_morrow(df, categories, "candlestick()"),
            open=open_values,
            high=high_values,
            low=low_values,
            close=close_values,
            theme=theme,
            width=width,
            height=height,
            title=title,
            subtitle=subtitle,
            x_title=x_title if x_title.byte_length() > 0 else categories,
            y_title=y_title,
        )
    var categories_values = _frame_strings(
        df,
        categories,
        "candlestick()",
        theme.missing,
        theme.missing_category_label,
    )
    return candlestick(
        categories=categories_values,
        open=open_values,
        high=high_values,
        low=low_values,
        close=close_values,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title,
        y_title=y_title,
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
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Illustrative daily OHLC prices across twelve trading sessions.
            var days: List[String] = [
                "Sep 1", "Sep 2", "Sep 3", "Sep 4", "Sep 5", "Sep 8",
                "Sep 9", "Sep 10", "Sep 11", "Sep 12", "Sep 15", "Sep 16",
            ]
            var open: List[Int] = [100, 104, 101, 97, 107, 110, 103, 108, 105, 111, 116, 113]
            var high: List[Int] = [106, 105, 103, 108, 112, 111, 109, 110, 113, 118, 119, 117]
            var low: List[Int] = [98, 99, 95, 96, 105, 102, 101, 104, 103, 109, 112, 108]
            var close: List[Int] = [104, 101, 97, 107, 110, 103, 108, 105, 111, 116, 113, 110]

            var c = candlestick(
                days,
                open,
                high,
                low,
                close,
                title="Illustrative Daily OHLC Prices",
                x_title="Trading session",
                y_title="Share price ($)",
            )
            save(c, "docs/src/examples/out_candlestick.svg")
        ```
    """
    var open_f = _materialize_scalar_list(open)
    var high_f = _materialize_scalar_list(high)
    var low_f = _materialize_scalar_list(low)
    var close_f = _materialize_scalar_list(close)
    var plot = (
        Plot()
        .mark_candlestick()
        .encode_candlestick(
            categories=categories,
            open=open_f,
            high=high_f,
            low=low_f,
            close=close_f,
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def candlestick[
    dtype: DType
](
    dates: List[Morrow],
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
    """Candlesticks at real timestamps, with gaps for weekends and holidays.

    The time axis uses the first date's time zone. Candle bodies are 70%
    of the median interval between dates, capped at 80% of the shortest
    interval so adjacent bodies cannot overlap. Dates must be distinct.

    Args:
        dates: One timestamp per OHLC observation.
        open: Opening prices.
        high: High prices.
        low: Low prices.
        close: Closing prices.
        theme: Chart styling.
        width: Chart width in pixels.
        height: Chart height in pixels.
        title: Chart title.
        subtitle: Chart subtitle.
        x_title: Time-axis title.
        y_title: Price-axis title.

    Returns:
        The unrendered plot.
    """
    var plot = (
        Plot()
        .mark_candlestick()
        .encode_candlestick_time(
            dates,
            _materialize_scalar_list(open),
            _materialize_scalar_list(high),
            _materialize_scalar_list(low),
            _materialize_scalar_list(close),
        )
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
