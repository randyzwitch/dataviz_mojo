from canvas_mojo.geometry import _round_to_int
from canvas_mojo.text.render import TextAlign
from canvas_mojo.vector.draw_target import DrawTarget
from canvas_mojo.buffer import Canvas

from dataviz_mojo.color_scale import ColorScale
from dataviz_mojo.mark import Mark
from dataviz_mojo.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _draw_continuous_color_legend,
    _dynamic_legend_width,
    _empty_result,
    _max_label_width,
    _min_max,
    _rendered,
)
from dataviz_mojo.scale import _format_fixed
from dataviz_mojo.theme import Theme

def _calendar_day_labels() -> List[String]:
    """The 7 row labels, Sunday first -- the same top-to-bottom order
    every GitHub-style contribution calendar (and ECharts' own
    calendar component) uses. Fixed, not derived from the data: unlike
    every other categorical axis in this package, a calendar's own 7
    rows exist whether or not a given day of the week appears in the
    data. A plain function, not a `Theme` field or a `comptime`
    constant -- `List` isn't `comptime`-constructible, the same reason
    `default_categorical_palette()`'s own docstring gives for a fixed
    default list living as a function instead."""
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


def _calendar_month_labels() -> List[String]:
    """See `_calendar_day_labels()`'s own docstring for why this is a
    plain function."""
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


struct _Date(Copyable, Movable):
    """A plain year/month/day triple -- not a general-purpose Date
    type (this package deliberately has none, the same stance `Mark.
    GANTT`'s own `encode_gantt` docstring already takes for its own
    start/end values), just enough structure for `_days_from_civil`/
    `_day_of_week` below to place one calendar cell. A named struct,
    not a raw tuple -- this file's own established "always a named
    struct for a multi-value return" convention."""

    var year: Int
    var month: Int
    var day: Int

    def __init__(out self, year: Int, month: Int, day: Int):
        self.year = year
        self.month = month
        self.day = day


def _parse_date(s: String) raises -> _Date:
    """Parse a plain `"YYYY-MM-DD"` string -- the one date format this
    mark accepts (ISO 8601's own calendar-date form), split on `"-"`
    and converted with `Int()`. Raises naturally (Mojo's own `Int()`
    conversion, or an out-of-bounds `List` index if the string doesn't
    split into exactly 3 parts) on anything else -- no separate
    validation layer on top of that, the same "let the obvious failure
    surface" stance this package takes elsewhere for malformed input
    with no principled recovery.
    """
    var parts = s.split("-")
    return _Date(Int(parts[0]), Int(parts[1]), Int(parts[2]))


def _days_from_civil(date: _Date) -> Int:
    """Days since 1970-01-01 (the Unix epoch), proleptic Gregorian --
    Howard Hinnant's well-known `days_from_civil` algorithm (public
    domain, widely used exactly because it's easy to independently
    verify against known reference dates rather than trust blindly:
    confirmed here against 2024-01-01, a real-world Monday -- see
    `_day_of_week`'s own docstring). Exact for any real Gregorian
    calendar date; this mark only ever calls it with dates already
    parsed from a caller's own data, never a negative/pre-Gregorian
    year.
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
    """0 (Sunday) through 6 (Saturday) for a `_days_from_civil` day
    count -- 1970-01-01 (`days_since_epoch == 0`) was a real-world
    Thursday, so `(days_since_epoch + 4) % 7` lands on 4. Every date
    this mark ever calls this with comes from `_days_from_civil` on a
    caller-given, real modern-era date, so `days_since_epoch` is
    always non-negative here -- no need for the negative-input branch
    a fully general version of this formula would have.
    """
    return (days_since_epoch + 4) % 7


def _render_calendar_heatmap[
    T: DrawTarget
](mut target: T, plot: Plot, ox0: Int, oy0: Int, ox1: Int, oy1: Int) raises -> _RenderResult:
    """Render a `Mark.CALENDAR_HEATMAP` plot: `encode_calendar()`'s
    own `dates`/`values` laid out in a GitHub-contributions-style
    calendar grid -- one column per week, one row per day of the week
    (`_calendar_day_labels()`, Sunday at the top), colored through a
    continuous `ColorScale` spanning `values`' own [min, max] --
    exactly `Mark.HEATMAP`'s own gradient vocabulary (`Theme.color_
    scale_low`/`color_scale_high`), reused here rather than
    reinvented.

    Every date must fall in the same calendar year (inferred from the
    first date, not a separate caller-supplied `year` parameter the
    way ECharts.jl's own `calendarheatmap()` takes -- a real,
    deliberate simplification: this package raises on a genuinely
    inconsistent input rather than silently filtering it the way that
    library's own `year` argument does, the same "raise on
    inconsistent input" stance `Mark.RADAR`'s own `encode_radar`
    already takes for its own length-mismatched lists). The first
    week's own column always starts on the Sunday on/before January
    1st (so January 1st never lands outside the grid even when it
    isn't itself a Sunday) -- `column = (days_since_jan1 + jan1s_own_
    weekday) // 7`, `row = day_of_week`.

    Own bespoke grid layout, not `Mark.HEATMAP`'s own `_draw_grid_
    axis_frame` -- that function's two axes are both string-labeled
    `OrdinalScale`s over a caller-given domain; this one's row domain
    is a fixed 7-day week and its column domain is a *computed* week
    index with no natural string label of its own (month names label
    the *columns where each month starts*, not one label per column
    the way `_draw_grid_axis_frame` would draw), different enough to
    need its own layout rather than a forced fit -- the same "own
    frame when the layout genuinely differs" reasoning `Mark.HEATMAP`'s
    own docstring already gives against reusing either existing
    categorical-axis core.
    """
    if len(plot._calendar_dates) != len(plot._calendar_values):
        raise Error(
            "Plot.encode_calendar(): dates and values must have the same length"
            " (got "
            + String(len(plot._calendar_dates))
            + " and "
            + String(len(plot._calendar_values))
            + ")"
        )

    var theme = plot._theme
    if len(plot._calendar_dates) == 0:
        return _empty_result(ox0, oy0, ox1, oy1)

    var parsed = List[_Date]()
    for d in plot._calendar_dates:
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
    var dynamic_left_margin = (
        Int(_max_label_width(day_labels, sc.font_size)) + sc.tick_length + sc.label_gap + sc.margin_buffer
    )

    var value_mm = _min_max(plot._calendar_values)
    var color_scale = ColorScale(value_mm.min, value_mm.max)
    color_scale.add_stop(0.0, theme.color_scale_low)
    color_scale.add_stop(1.0, theme.color_scale_high)

    var legend_reserve = 0
    if theme.show_legend:
        var legend_labels = List[String]()
        legend_labels.append(_format_fixed(color_scale.domain_max, 1))
        legend_labels.append(_format_fixed(color_scale.domain_min, 1))
        legend_reserve = _dynamic_legend_width(legend_labels, sc.continuous_legend_bar_width, sc)

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
            )
        )

    for month in range(1, 13):
        var days = _days_from_civil(_Date(year, month, 1)) - jan1_days
        var col = (days + jan1_dow) // 7
        var cx = _round_to_int(Float64(plot_x0) + Float64(col) * cell_width)
        text_requests.append(
            _TextRequest(
                cx, plot_y0 - sc.label_gap, month_labels[month - 1], theme.text_color, sc.font_size,
                TextAlign.LEFT,
            )
        )

    for i in range(len(parsed)):
        var days = _days_from_civil(parsed[i]) - jan1_days
        var col = (days + jan1_dow) // 7
        var row = _day_of_week(days + jan1_days)
        var cell_x = _round_to_int(Float64(plot_x0) + Float64(col) * cell_width)
        var cell_y = _round_to_int(Float64(plot_y0) + Float64(row) * cell_height)
        var color = color_scale.color_at(plot._calendar_values[i])
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
    x_title: String = "",
    y_title: String = "",
) raises -> Canvas:
    """A calendar heatmap -- `Mark.CALENDAR_HEATMAP`, daily `values`
    laid out in a GitHub-contributions-style calendar grid, colored
    through a continuous gradient. `dates` are plain `"YYYY-MM-DD"`
    strings, all in the same year (inferred from the first one -- see
    `_render_calendar_heatmap`'s own docstring)."""
    var plot = Plot().mark_calendar_heatmap().encode_calendar(dates=dates, values=values)
    return _rendered(plot^, theme, width, height, title, x_title, y_title)
