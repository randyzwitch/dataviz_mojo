from canvas.geometry import _round_to_int
from canvas.text.render import TextAlign
from canvas.vector.draw_target import DrawTarget

from dataviz.array_like import _materialize_scalar_list
from dataviz.color_scale import ColorScale
from canvas.text.font_cache import FontCache
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _max_label_width,
    _min_max,
    _finished,
    _require_non_empty,
)
from dataviz.scale import _format_fixed
from dataviz.theme import Theme


struct _CalendarData(Movable):
    """One (`"YYYY-MM-DD"` date, value) row per day, for
    `Mark.CALENDAR_HEATMAP`. See `encode_calendar()`. Stored on
    `Plot._calendar`.
    """

    var dates: List[String]
    var values: List[Float64]

    def __init__(out self):
        self.dates = List[String]()
        self.values = List[Float64]()


def _calendar_day_labels() -> List[String]:
    """The 7 row labels, Sunday first (GitHub's contribution calendar order).
    Fixed rather than derived from the data: all 7 rows exist whether or
    not a weekday appears. A plain function because `List` isn't
    `comptime`-constructible.
    """
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


def _calendar_month_labels() -> List[String]:
    """The 12 month labels; a plain function for the reason in
    `_calendar_day_labels()`.
    """
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


struct _Date(Copyable, Movable):
    """A plain year/month/day triple, just enough for `_days_from_civil`/
    `_day_of_week` to place one calendar cell. Not a general-purpose Date
    type.
    """

    var year: Int
    var month: Int
    var day: Int

    def __init__(out self, year: Int, month: Int, day: Int):
        self.year = year
        self.month = month
        self.day = day


def _parse_date(s: String) raises -> _Date:
    """Parse a `"YYYY-MM-DD"` string (ISO 8601 calendar date), split on `"-"`
    and converted with `Int()`. Anything else raises from `Int()` or from
    indexing fewer than 3 parts.
    """
    var parts = s.split("-")
    return _Date(Int(parts[0]), Int(parts[1]), Int(parts[2]))


def _days_from_civil(date: _Date) -> Int:
    """Days since 1970-01-01, proleptic Gregorian: Howard Hinnant's
    `days_from_civil` algorithm (public domain).
    """
    var y = date.year
    if date.month <= 2:
        y -= 1
    var era = (y if y >= 0 else y - 399) // 400
    var yoe = y - era * 400
    var mp = date.month + (-3 if date.month > 2 else 9)
    var doy = (153 * mp + 2) // 5 + date.day - 1
    var doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


def _day_of_week(days_since_epoch: Int) -> Int:
    """0 (Sunday) through 6 (Saturday) for a `_days_from_civil` day count.
    1970-01-01 was a Thursday, so `(days + 4) % 7`. Inputs here are always
    non-negative, so there is no negative-input branch.
    """
    return (days_since_epoch + 4) % 7


def _render_calendar_heatmap[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.CALENDAR_HEATMAP` plot: `encode_calendar()`'s `dates`/
    `values` in a GitHub-contributions-style grid, one column per week
    and one row per day of the week (`_calendar_day_labels()`, Sunday at
    the top), colored through `ColorScale.from_theme` over `values`'
    [min, max] as `Mark.HEATMAP` is.

    Every date must fall in the same calendar year, inferred from the
    first date; a mismatch raises. The first column starts on the Sunday
    on or before January 1st: `column = (days_since_jan1 + jan1_dow) // 7`,
    `row = day_of_week`. Month names label the columns where each month
    starts.

    Its own grid layout rather than `_draw_grid_axis_frame`: the row
    domain is a fixed 7-day week and the column domain is a computed week
    index with no per-column label.
    """
    if len(plot._calendar.dates) != len(plot._calendar.values):
        raise Error(
            "Plot.encode_calendar(): dates and values must have the same length"
            " (got "
            + String(len(plot._calendar.dates))
            + " and "
            + String(len(plot._calendar.values))
            + ")"
        )

    var theme = plot._theme
    _require_non_empty(len(plot._calendar.dates), "Plot.encode_calendar()")

    var parsed = List[_Date]()
    for d in plot._calendar.dates:
        parsed.append(_parse_date(d))
    var year = parsed[0].year
    for date in parsed:
        if date.year != year:
            raise Error(
                "Plot.encode_calendar(): every date must fall in the same"
                " year (got "
                + String(year)
                + " and "
                + String(date.year)
                + ")"
            )

    var jan1_days = _days_from_civil(_Date(year, 1, 1))
    var jan1_dow = _day_of_week(jan1_days)
    var dec31_days = _days_from_civil(_Date(year, 12, 31))
    var n_cols = (dec31_days - jan1_days + jan1_dow) // 7 + 1

    var sc = _Scaled(theme)
    var day_labels = _calendar_day_labels()
    var month_labels = _calendar_month_labels()
    # One FontCache for both measurements: the y-axis day labels here and
    # the legend's labels below.
    var measure_cache = FontCache()
    var dynamic_left_margin = (
        Int(_max_label_width(day_labels, sc.font_size, cache=measure_cache)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var value_mm = _min_max(plot._calendar.values)
    var color_scale = ColorScale.from_theme(theme, value_mm.min, value_mm.max)

    var legend_reserve = 0
    if theme.show_legend:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend_reserve = _dynamic_legend_width(legend_labels, sc.continuous_legend_bar_width, sc, cache=measure_cache)

    var plot_x0 = ox0 + max(sc.margin_left, dynamic_left_margin)
    var plot_y0 = oy0 + sc.margin_top + Int(sc.font_size) + sc.label_gap
    var plot_x1 = ox1 - sc.margin_right - legend_reserve
    var plot_y1 = oy1 - sc.margin_bottom

    var cell_width = Float64(plot_x1 - plot_x0) / Float64(n_cols)
    var cell_height = Float64(plot_y1 - plot_y0) / 7.0

    var text_requests = List[_TextRequest]()

    var y_label_baseline_offset = Int(sc.font_size * 0.35)
    for row in range(7):
        var cy = _round_to_int(Float64(plot_y0) + (Float64(row) + 0.5) * cell_height)
        text_requests.append(
            _TextRequest(
                plot_x0 - sc.tick_length - sc.label_gap,
                cy + y_label_baseline_offset,
                day_labels[row],
                theme.text_color,
                sc.font_size,
                TextAlign.RIGHT,
                theme.font_family,
            )
        )

    for month in range(1, 13):
        var days = _days_from_civil(_Date(year, month, 1)) - jan1_days
        var col = (days + jan1_dow) // 7
        var cx = _round_to_int(Float64(plot_x0) + Float64(col) * cell_width)
        text_requests.append(
            _TextRequest(
                cx, plot_y0 - sc.label_gap, month_labels[month - 1], theme.text_color, sc.font_size,
                TextAlign.LEFT, theme.font_family,
            )
        )

    for i in range(len(parsed)):
        var days = _days_from_civil(parsed[i]) - jan1_days
        var col = (days + jan1_dow) // 7
        var row = _day_of_week(days + jan1_days)
        var cell_x = _round_to_int(Float64(plot_x0) + Float64(col) * cell_width)
        var cell_y = _round_to_int(Float64(plot_y0) + Float64(row) * cell_height)
        var color = color_scale.color_at(plot._calendar.values[i])
        target.fill_rect(cell_x, cell_y, _round_to_int(cell_width), _round_to_int(cell_height), color)

    if theme.show_legend:
        _ = _draw_continuous_color_legend(target, text_requests, color_scale, plot_x1 + sc.margin_right, plot_y0, theme)

    return _RenderResult(text_requests^, plot_x0, plot_y0, plot_x1, plot_y1)


def calendar_heatmap(
    dates: List[String],
    values: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A calendar heatmap.

    `Mark.CALENDAR_HEATMAP`: daily `values` laid out in a
    GitHub-contributions-style calendar grid, colored through a
    continuous gradient. `dates` are `"YYYY-MM-DD"` strings, all in the
    same year (inferred from the first one; see
    `_render_calendar_heatmap`).

    Args:
        dates: Plain `"YYYY-MM-DD"` strings, one per entry, all in
            the same year (inferred from `dates[0]`).
        values: Each date's value, mapped through a continuous color
            gradient.
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
        from dataviz import calendar_heatmap
        from dataviz.plot import save

        def main() raises:
            var dates = List[String]()
            var values = List[Int]()
            var days_in_month: List[Int] = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            for month in range(1, 13):
                var month_str = "0" + String(month) if month < 10 else String(month)
                for day in range(1, days_in_month[month - 1] + 1):
                    var day_str = "0" + String(day) if day < 10 else String(day)
                    dates.append(String(2024) + "-" + month_str + "-" + day_str)
                    values.append((day * 7 + month) % 10)

            var c = calendar_heatmap(dates, values, width=900, height=250)
            save(c, "docs/src/examples/out_calendar_heatmap.svg")
        ```
    """
    var plot = Plot().mark_calendar_heatmap().encode_calendar(dates=dates, values=values)
    return _finished(plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle)


def calendar_heatmap[
    dtype: DType
](
    dates: List[String],
    values: List[Scalar[dtype]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`calendar_heatmap()` generalized over numeric element type; see
    `scatter()`'s `DType` overload (plot.mojo). Delegates to the concrete
    overload above.
    """
    return calendar_heatmap(
        dates, _materialize_scalar_list(values), theme=theme, width=width, height=height,
        title=title, subtitle=subtitle, x_title=x_title, y_title=y_title,
    )
