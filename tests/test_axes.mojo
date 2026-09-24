"""Axes: which spines draw and where, and the temporal scale's ticks and labels.

One module rather than 2: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from canvas.text.font_cache import FontCache
from dataviz import (
    AxisPosition,
    Theme,
    bar,
    candlestick,
    line,
    pairplot,
    rugplot,
    save,
    scatter,
)
from dataviz.core.frame import _fitting_ticks, _ticks_fit
from dataviz.core.scale import TickFormat
from dataviz.core.text import _Scaled, _max_label_width
from dataviz.core.scale import (
    LinearScale,
    _symlog_forward,
    _symlog_inverse,
)
from dataviz.core.theme import Theme
from dataviz.plot import (
    Plot,
    _symlog_data_extent,
    render,
    render_layers_svg,
    render_svg,
)
from _test_helpers import _attr_values, _count_tag
from morrow import Morrow, TimeZone


# ==== from test_axis_spines.mojo ====
# Tests for the axis spines (#346): the four `Theme.show_axis_*` flags
# and `AxisPosition.ZERO`, asserted on exact SVG line endpoints.


# Every chart here is 400x300 with gridlines off, so the plot rect is
# x:[60,380], y:[20,250] -- the rect every other pinned-pixel test in
# this suite uses.
comptime _X0 = 60
comptime _Y0 = 20
comptime _X1 = 380
comptime _Y1 = 250


def _theme(
    left: Bool = True,
    right: Bool = False,
    top: Bool = False,
    bottom: Bool = True,
    x_at: AxisPosition = AxisPosition.EDGE,
    y_at: AxisPosition = AxisPosition.EDGE,
) -> Theme:
    return Theme(
        show_gridlines=False,
        show_axis_left=left,
        show_axis_right=right,
        show_axis_top=top,
        show_axis_bottom=bottom,
        x_axis_position=x_at,
        y_axis_position=y_at,
    )


struct _Seg(Copyable, ImplicitlyCopyable, Movable):
    var x1: Int
    var y1: Int
    var x2: Int
    var y2: Int

    def __init__(out self, x1: Int, y1: Int, x2: Int, y2: Int):
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2


def _segments(svg: String) raises -> List[_Seg]:
    """Every `<line>` as integer endpoints, in document order."""
    var x1 = _attr_values(svg, "line", "x1")
    var y1 = _attr_values(svg, "line", "y1")
    var x2 = _attr_values(svg, "line", "x2")
    var y2 = _attr_values(svg, "line", "y2")
    var out = List[_Seg]()
    for i in range(len(x1)):
        out.append(
            _Seg(
                Int(Float64(x1[i])),
                Int(Float64(y1[i])),
                Int(Float64(x2[i])),
                Int(Float64(y2[i])),
            )
        )
    return out^


def _has(segs: List[_Seg], x1: Int, y1: Int, x2: Int, y2: Int) -> Bool:
    for s in segs:
        if s.x1 == x1 and s.y1 == y1 and s.x2 == x2 and s.y2 == y2:
            return True
    return False


def _spans_plot_width(s: _Seg) -> Bool:
    return s.y1 == s.y2 and s.x1 == _X0 and s.x2 == _X1


def _spans_plot_height(s: _Seg) -> Bool:
    return s.x1 == s.x2 and s.y1 == _Y0 and s.y2 == _Y1


def _full_span_count(segs: List[_Seg]) -> Int:
    """Lines that bound or cross the whole plot rect: the spines, since
    a tick is five pixels long and this chart has no gridlines."""
    var n = 0
    for s in segs:
        if _spans_plot_width(s) or _spans_plot_height(s):
            n += 1
    return n


def _plot(theme: Theme) raises -> Plot:
    # Symmetric about zero on both axes, so `_data_extent`'s 5% padding
    # keeps zero at the exact center of the plot rect: x = 220, y = 135.
    var xs: List[Float64] = [-4.0, 0.0, 4.0]
    var ys: List[Float64] = [-4.0, 1.0, 4.0]
    return scatter(xs, ys, theme=theme, width=400, height=300)


def test_the_default_frame_is_left_and_bottom_only() raises:
    var segs = _segments(render_svg(_plot(_theme())).to_string())
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")
    assert_true(not _has(segs, _X0, _Y0, _X1, _Y0), "no top line")
    assert_true(not _has(segs, _X1, _Y0, _X1, _Y1), "no right line")
    assert_equal(_full_span_count(segs), 2)


def test_all_four_flags_draw_a_full_box() raises:
    var segs = _segments(
        render_svg(_plot(_theme(right=True, top=True))).to_string()
    )
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom")
    assert_true(_has(segs, _X0, _Y0, _X1, _Y0), "top")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left")
    assert_true(_has(segs, _X1, _Y0, _X1, _Y1), "right")
    assert_equal(_full_span_count(segs), 4)


def test_a_frameless_chart_drops_the_lines_and_the_ticks_but_keeps_labels() raises:
    var s = render_svg(_plot(_theme(left=False, bottom=False))).to_string()
    var segs = _segments(s)
    assert_equal(_full_span_count(segs), 0, "no axis lines")
    assert_equal(len(segs), 0, "and no tick marks either")
    # The numbers stay: a frameless chart has less furniture, not less
    # information.
    assert_true(s.find(">0<") >= 0, "the tick labels are still drawn")


def test_hiding_one_axis_leaves_the_others_ticks_alone() raises:
    var segs = _segments(render_svg(_plot(_theme(bottom=False))).to_string())
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "the left line stays")
    for s in segs:
        assert_true(
            not (s.y1 == _Y1 and s.y2 > _Y1),
            "no x tick hangs off the hidden bottom axis",
        )
    var y_ticks = 0
    for s in segs:
        if s.x1 == _X0 - 5 and s.x2 == _X0:
            y_ticks += 1
    assert_true(y_ticks > 0, "the y ticks are untouched")


def test_axes_at_zero_cross_the_data_and_take_their_ticks_along() raises:
    # Zero is the exact center of both padded domains (see `_plot`).
    var zero_x = (_X0 + _X1) // 2
    var zero_y = (_Y0 + _Y1) // 2
    var segs = _segments(
        render_svg(
            _plot(_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO))
        ).to_string()
    )
    assert_true(_has(segs, _X0, zero_y, _X1, zero_y), "x axis at y = 0")
    assert_true(_has(segs, zero_x, _Y0, zero_x, _Y1), "y axis at x = 0")
    assert_true(not _has(segs, _X0, _Y1, _X1, _Y1), "not at the bottom too")
    assert_true(not _has(segs, _X0, _Y0, _X0, _Y1), "nor at the left")
    # Ticks moved with their lines: an x tick now hangs off row 135, and
    # a y tick reaches leftward from column 220.
    var moved_x = 0
    var moved_y = 0
    for s in segs:
        if s.y1 == zero_y and s.y2 == zero_y + 5:
            moved_x += 1
        if s.x1 == zero_x - 5 and s.x2 == zero_x:
            moved_y += 1
    assert_true(moved_x > 0, "x ticks follow the x axis to zero")
    assert_true(moved_y > 0, "y ticks follow the y axis to zero")


def test_zero_falls_back_to_the_edge_when_the_domain_misses_zero() raises:
    # All-positive data: an axis at zero would be outside the plot rect,
    # so the documented fallback puts both lines back on the edges.
    var xs: List[Float64] = [10.0, 20.0, 30.0]
    var ys: List[Float64] = [5.0, 6.0, 9.0]
    var segs = _segments(
        render_svg(
            scatter(
                xs,
                ys,
                theme=_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO),
                width=400,
                height=300,
            )
        ).to_string()
    )
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")
    assert_equal(_full_span_count(segs), 2)


def test_zero_falls_back_on_a_log_axis() raises:
    # log10(0) is undefined, so a log axis can never carry the line.
    var xs: List[Float64] = [1.0, 10.0, 100.0]
    var ys: List[Float64] = [1.0, 10.0, 100.0]
    var p = scatter(
        xs,
        ys,
        theme=_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO),
        width=400,
        height=300,
    )
    var segs = _segments(render_svg(p^.scale_y_log().scale_x_log()).to_string())
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")


def test_the_flags_reach_a_categorical_frame_too() raises:
    # One helper draws every frame's spines, so a bar chart gets the
    # same box -- its plot rect is the same, since the y labels here are
    # no wider than the default margin.
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var segs = _segments(
        render_svg(
            bar(
                cats,
                vals,
                theme=_theme(right=True, top=True),
                width=400,
                height=300,
            )
        ).to_string()
    )
    assert_equal(_full_span_count(segs), 4, "a bar chart takes the full box")


def test_zero_is_ignored_where_an_axis_is_not_continuous() raises:
    # A bar chart's x-axis is ordinal: x = 0 has no position, so the
    # vertical line stays at the edge rather than guessing.
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [3.0, 1.0, 2.0]
    var segs = _segments(
        render_svg(
            bar(
                cats,
                vals,
                theme=_theme(x_at=AxisPosition.ZERO, y_at=AxisPosition.ZERO),
                width=400,
                height=300,
            )
        ).to_string()
    )
    assert_true(_has(segs, _X0, _Y1, _X1, _Y1), "bottom axis line")
    assert_true(_has(segs, _X0, _Y0, _X0, _Y1), "left axis line")
    assert_equal(_full_span_count(segs), 2)


def test_a_mark_with_no_y_axis_draws_no_vertical_line_whatever_the_flags_say() raises:
    # `Mark.RUG` suppresses the y-axis: a left or right line there would
    # claim a scale the chart does not have.
    var values: List[Float64] = [1.0, 2.0, 3.0, 5.0]
    var segs = _segments(
        render_svg(
            rugplot(
                values,
                theme=_theme(right=True, top=True),
                width=400,
                height=300,
            )
        ).to_string()
    )
    for s in segs:
        assert_true(
            not _spans_plot_height(s),
            "no vertical spine on a mark with no y-axis",
        )
    var horizontals = 0
    for s in segs:
        if _spans_plot_width(s):
            horizontals += 1
    assert_equal(horizontals, 2, "the top and bottom lines still draw")


# ==== from test_time_scale.mojo ====
# Tests for the temporal axis (#195): where the ticks land and what
# they read, across nine orders of magnitude of span.
#
# Every expectation here is a calendar fact -- a month start, a local
# midnight, a Monday -- rather than a number that came out of a previous
# run, because the bug this replaces was ticks on arithmetically tidy but
# calendrically meaningless boundaries.


def _labels(lo: Morrow, hi: Morrow, tz_offset: Int = 0) raises -> List[String]:
    var s = LinearScale(
        lo.timestamp(),
        hi.timestamp(),
        0.0,
        1.0,
        is_time=True,
        tz_offset=tz_offset,
    )
    return s.ticks().override_labels.copy()


def _values(lo: Morrow, hi: Morrow, tz_offset: Int = 0) raises -> List[Float64]:
    var s = LinearScale(
        lo.timestamp(),
        hi.timestamp(),
        0.0,
        1.0,
        is_time=True,
        tz_offset=tz_offset,
    )
    return s.ticks().values.copy()


def _joined(items: List[String]) -> String:
    var out = String("")
    for i in range(len(items)):
        if i > 0:
            out += "|"
        out += items[i]
    return out


def test_a_six_month_daily_series_gets_month_starts() raises:
    # #195's own case: the axis used to read 20450 / 20500 / 20550,
    # epoch day counts on 50-day boundaries. A reader of six months
    # wants months.
    var start = Morrow.get(2026, 1, 1)
    var labels = _labels(start, start.shift(days=180))
    # Jan 1 plus 180 days is Jun 30, so Jul 1 is past the end: six
    # ticks, and the last one inside the domain rather than beyond it.
    # The year rides on the first tick only -- see `_time_tick_label`,
    # which appends it where the year changes so an axis inside one year
    # does not repeat it six times.
    assert_equal(_joined(labels), "Jan 2026|Feb|Mar|Apr|May|Jun")
    # And they are month starts, not 30-day multiples: check each tick
    # round-trips to the first of a month at midnight.
    for v in _values(start, start.shift(days=180)):
        var at = Morrow.utcfromtimestamp(v)
        assert_equal(at.day, 1, "every tick is the first of a month")
        assert_equal(at.hour, 0)
        assert_equal(at.minute, 0)


def test_a_single_year_gets_quarters_not_twelve_months() raises:
    # The closest-ratio rule earns its keep here: twelve monthly labels
    # would not fit, and a rule taking the first step under the target
    # would pick them.
    var start = Morrow.get(2026, 3, 17, 9, 41, 12, 0)
    # And the year appears twice: on the first tick, and again on the
    # January that crosses into 2027.
    assert_equal(
        _joined(_labels(start, start.shift(years=1))),
        "Apr 2026|Jul|Oct|Jan 2027",
    )


def test_a_decade_snaps_to_round_years() raises:
    # 2030/2040/2050, not 2033/2043/2053: the year is floored to a
    # multiple of the step before stepping.
    var start = Morrow.get(2026, 3, 17)
    assert_equal(
        _joined(_labels(start, start.shift(years=40))),
        "2030|2040|2050|2060",
    )


def test_a_day_gets_hours_and_a_couple_of_minutes_gets_seconds() raises:
    var start = Morrow.get(2026, 3, 17, 9, 41, 12, 0)
    assert_equal(
        _joined(_labels(start, start.shift(days=1))),
        "12:00|18:00|00:00|06:00",
    )
    assert_equal(
        _joined(_labels(start, start.shift(minutes=2))),
        "09:41:30|09:42:00|09:42:30|09:43:00",
    )
    assert_equal(
        _joined(_labels(start, start.shift(minutes=90))),
        "09:45|10:00|10:15|10:30|10:45|11:00",
    )


def test_fortnightly_ticks_land_on_mondays() raises:
    # Seven-day steps count from the epoch, which was a Thursday, so
    # they are snapped to Monday instead. 2026-03-30 is a Monday.
    var start = Morrow.get(2026, 3, 17)
    var values = _values(start, start.shift(months=2))
    assert_true(len(values) > 2, "a two-month span gets several ticks")
    for v in values:
        var at = Morrow.utcfromtimestamp(v)
        var days = Int(v / 86400.0)
        assert_equal((days + 3) % 7, 0, "each tick is a Monday")
        assert_equal(at.hour, 0, "at midnight")


def test_ticks_land_on_local_midnight_not_utc_midnight() raises:
    # A day tick for data recorded in New York (UTC-5) must be local
    # midnight, which is 05:00 UTC. An axis whose day ticks landed at
    # 19:00 local would be wrong in a way that still looks plausible.
    var west = TimeZone(-5 * 3600)
    var start = Morrow.get(2026, 3, 17, 0, 0, 0, 0, west)
    var values = _values(start, start.shift(days=4), tz_offset=-5 * 3600)
    assert_true(len(values) > 2, "a four-day span gets daily ticks")
    for v in values:
        assert_equal(
            Morrow.utcfromtimestamp(v).hour, 5, "local midnight is 05:00 UTC"
        )


def test_labels_read_in_the_data_s_zone_not_in_utc() raises:
    # Tokyo (UTC+9), where the two answers differ: local midnight on
    # Mar 18 is 15:00 UTC on Mar 17, so a label rendered in UTC reads
    # the *previous* day. New York could not catch this -- its local
    # midnight is 05:00 UTC on the same date -- which is why this test
    # exists separately.
    var east = TimeZone(9 * 3600)
    var start = Morrow.get(2026, 3, 17, 0, 0, 0, 0, east)
    var offset = 9 * 3600
    var values = _values(start, start.shift(days=4), tz_offset=offset)
    var labels = _labels(start, start.shift(days=4), tz_offset=offset)
    assert_true(len(values) > 2, "a four-day span gets daily ticks")
    for i in range(len(values)):
        var utc = Morrow.utcfromtimestamp(values[i])
        assert_equal(utc.hour, 15, "local midnight in Tokyo is 15:00 UTC")
        # The label is the local date, a day ahead of the UTC one. Only
        # the first tick carries the year (`_time_tick_label`), so
        # compare against the same format the label would have used.
        var local = Morrow.fromtimestamp(values[i], east)
        var fmt = String("MMM DD YYYY") if i == 0 else String("MMM DD")
        assert_equal(labels[i], local.format(fmt))
        assert_true(
            labels[i] != utc.format(fmt),
            "the local label differs from the UTC one -- got "
            + labels[i]
            + " for a UTC instant on "
            + utc.format(fmt),
        )


def test_a_zero_span_domain_gets_one_dated_tick() raises:
    var at = Morrow.get(2026, 7, 4)
    assert_equal(_joined(_labels(at, at)), "2026-07-04")


def test_encode_time_puts_posix_seconds_on_the_axis() raises:
    var days = List[Morrow]()
    var vals = List[Float64]()
    for i in range(5):
        days.append(Morrow.get(2026, 1, 1).shift(days=i))
        vals.append(Float64(i))
    var p = Plot().mark_line().encode_time(days, vals)
    assert_true(p._x_time, "the axis is marked temporal")
    assert_equal(len(p._continuous.x), 5)
    assert_equal(p._continuous.x[0], Morrow.get(2026, 1, 1).timestamp())
    assert_equal(
        p._continuous.x[1] - p._continuous.x[0],
        86400.0,
        "one day apart in seconds",
    )
    assert_equal(len(p._continuous.y), 5)


def test_time_bars_leave_a_weekend_gap() raises:
    var dates: List[Morrow] = [
        Morrow.get(2024, 3, 1),
        Morrow.get(2024, 3, 4),
        Morrow.get(2024, 3, 5),
    ]
    var values: List[Float64] = [10.0, 20.0, 15.0]
    var plot = bar(
        dates,
        values,
        theme=Theme(show_gridlines=False),
        width=400,
        height=300,
    )
    assert_true(plot._x_time, "bars use a time axis")
    assert_equal(plot._continuous.x[1] - plot._continuous.x[0], 3.0 * 86400.0)
    var s = render_svg(plot).to_string()
    assert_true(">Mar" in s, "x ticks show dates")
    assert_true("2024-03-04 00:00:00: 20" in s, "tooltip names its date")
    assert_true('x="75"' in s, "Friday bar starts at its real date")
    assert_true('x="250"' in s, "Monday bar leaves a weekend gap")
    assert_true('x="308"' in s, "Tuesday bar follows one day later")


def test_time_bars_reject_duplicate_dates_and_horizontal_orientation() raises:
    var dates: List[Morrow] = [Morrow.get(2024, 3, 1), Morrow.get(2024, 3, 1)]
    var values: List[Float64] = [10.0, 12.0]
    with assert_raises(contains="timestamps must be distinct"):
        _ = render_svg(bar(dates, values))
    with assert_raises(contains="horizontal bars cannot use a time x-axis"):
        _ = bar(dates, values, horizontal=True)


def test_one_time_bar_and_error_whisker_render() raises:
    var dates: List[Morrow] = [Morrow.get(2024, 3, 1)]
    var values: List[Float64] = [10.0]
    var errors: List[Float64] = [2.0]
    var plot = (
        Plot()
        .mark_bar()
        .encode_time_bars(dates, values, y_err=errors)
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true("2024-03-01 00:00:00: 10" in s, "single dated tooltip")
    assert_true("<rect " in s, "single date uses the one-day interval")
    assert_true("<line " in s, "error whisker renders on the dated bar")


def test_a_lone_time_bar_layer_keeps_its_time_geometry() raises:
    var dates: List[Morrow] = [Morrow.get(2024, 3, 1), Morrow.get(2024, 3, 4)]
    var values: List[Float64] = [10.0, 12.0]
    var plot = bar(dates, values, width=400, height=300)
    var standalone = render_svg(plot).to_string()
    var plots: List[Plot] = [plot^]
    assert_equal(
        render_layers_svg(plots).to_string(),
        standalone,
        "one time bar layer uses the same dated frame",
    )
    var idx: List[Float64] = [0.0, 1.0]
    var line_y: List[Float64] = [9.0, 11.0]
    plots.append(line(idx, line_y, width=400, height=300))
    with assert_raises(contains="time-axis Mark.BAR"):
        _ = render_layers_svg(plots)


def test_time_candles_leave_a_weekend_gap() raises:
    var dates: List[Morrow] = [
        Morrow.get(2024, 3, 1),
        Morrow.get(2024, 3, 4),
        Morrow.get(2024, 3, 5),
    ]
    var open: List[Float64] = [10.0, 12.0, 14.0]
    var high: List[Float64] = [15.0, 16.0, 17.0]
    var low: List[Float64] = [8.0, 9.0, 11.0]
    var close: List[Float64] = [13.0, 14.0, 12.0]
    var plot = candlestick(
        dates,
        open,
        high,
        low,
        close,
        theme=Theme(show_gridlines=False),
        width=400,
        height=300,
    )
    assert_true(plot._x_time, "candlestick uses a temporal axis")
    assert_equal(
        plot._continuous.x[1] - plot._continuous.x[0],
        3.0 * 86400.0,
        "weekend remains three real days",
    )
    var s = render_svg(plot).to_string()
    assert_true('x1="106.000"' in s, "Friday wick on its timestamp")
    assert_true('x1="277.000"' in s, "Monday wick after the weekend")
    assert_true('x1="334.000"' in s, "Tuesday wick one day later")
    assert_true("2024-03-04" in s, "dated candle tooltip")


def test_time_candles_reject_duplicate_dates() raises:
    var dates: List[Morrow] = [Morrow.get(2024, 3, 1), Morrow.get(2024, 3, 1)]
    var open: List[Float64] = [10.0, 12.0]
    var high: List[Float64] = [15.0, 16.0]
    var low: List[Float64] = [8.0, 9.0]
    var close: List[Float64] = [13.0, 14.0]
    with assert_raises(contains="timestamps must be distinct"):
        _ = render_svg(candlestick(dates, open, high, low, close))


def test_the_one_call_time_overloads_label_dates() raises:
    var days = List[Morrow]()
    var vals = List[Float64]()
    for i in range(120):
        days.append(Morrow.get(2026, 1, 1).shift(days=i))
        vals.append(Float64(i % 7))
    var s = render_svg(
        line(
            days, vals, theme=Theme(show_gridlines=False), width=400, height=300
        )
    ).to_string()
    # The year rides on the first tick; later months are bare.
    assert_true(s.find(">Jan 2026<") >= 0, "the first tick names the year")
    assert_true(s.find(">Feb<") >= 0, "and later months do not repeat it")
    assert_true(s.find(">20454<") < 0, "and not as epoch day counts")


def test_a_layered_time_series_keeps_the_dated_axis() raises:
    var days = List[Morrow]()
    var a = List[Float64]()
    var b = List[Float64]()
    for i in range(120):
        days.append(Morrow.get(2026, 1, 1).shift(days=i))
        a.append(Float64(i % 7))
        b.append(Float64(i % 5) + 2.0)
    var plots: List[Plot] = [
        line(days, a, width=400, height=300),
        line(days, b, width=400, height=300),
    ]
    var s = render_layers_svg(plots).to_string()
    assert_true(s.find(">Jan 2026<") >= 0, "an overlay keeps the dates")
    assert_true(s.find(">Feb<") >= 0, "with the year only where it changes")
    assert_true(_count_tag(s, "path") >= 2, "both series draw")


def test_the_year_is_repeated_only_where_it_changes() raises:
    # Ported from the module this change deletes (#523), which had the
    # better rule: an axis inside one year names it once, and a monthly
    # axis crossing into a new one names it again at that January.
    var start = Morrow.get(2026, 3, 17)
    assert_equal(
        _joined(_labels(start, start.shift(years=3))),
        "Jul 2026|Jan 2027|Jul|Jan 2028|Jul|Jan 2029",
    )
    # Day rungs follow the same rule. This start is midnight, so the
    # first day boundary is the domain's own left end.
    assert_equal(
        _joined(_labels(start, start.shift(days=5))),
        "Mar 17 2026|Mar 18|Mar 19|Mar 20|Mar 21|Mar 22",
    )


# ==== axis controls (#368) ====
# Explicit ticks, reversed axes and equal aspect, asserted on the SVG's
# own numbers: circle centers for where the data landed, the two axis
# spines for where the plot rect is, and the short segments hanging off
# the rect for where the ticks are.


def _controls_theme() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def _diagonal() -> List[Float64]:
    """Five points up the diagonal, used for both axes, so a tick at a
    data value can be compared against that point's own pixel.
    """
    var v: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    return v^


def _rect(svg: String) raises -> Tuple[Int, Int, Int, Int]:
    """The plot rect as `(x0, y0, x1, y1)`, from the two axis spines: the
    longest vertical line is the left one and the longest horizontal the
    bottom one, and each spans the rect exactly.
    """
    var segs = _segments(svg)
    var vi = -1
    var hi = -1
    var best_v = -1
    var best_h = -1
    for i in range(len(segs)):
        var s = segs[i]
        if s.x1 == s.x2:
            var length = abs(s.y2 - s.y1)
            if length > best_v:
                best_v = length
                vi = i
        elif s.y1 == s.y2:
            var length = abs(s.x2 - s.x1)
            if length > best_h:
                best_h = length
                hi = i
    if vi < 0 or hi < 0:
        raise Error("no axis spines in the document")
    var v = segs[vi]
    var h = segs[hi]
    return (v.x1, min(v.y1, v.y2), max(h.x1, h.x2), h.y1)


def _center_xs(svg: String) raises -> List[Float64]:
    """Every scatter marker's center x, in document order."""
    var out = List[Float64]()
    for v in _attr_values(svg, "circle", "cx"):
        out.append(Float64(v))
    return out^


def _center_ys(svg: String) raises -> List[Float64]:
    """Every scatter marker's center y, in document order."""
    var out = List[Float64]()
    for v in _attr_values(svg, "circle", "cy"):
        out.append(Float64(v))
    return out^


def _x_tick_pixels(svg: String) raises -> List[Int]:
    """Each x tick mark's column: the short vertical segments hanging
    below the plot rect's bottom edge.
    """
    var r = _rect(svg)
    var out = List[Int]()
    for s in _segments(svg):
        if s.x1 == s.x2 and min(s.y1, s.y2) == r[3] and max(s.y1, s.y2) > r[3]:
            out.append(s.x1)
    return out^


def test_an_explicit_x_tick_lands_on_its_own_data_value() raises:
    # The decisive check, and one that needs no pixel arithmetic in the
    # test: a tick asked for at x=1 must print in the same column as the
    # marker at x=1, because they go through the same scale.
    var pos: List[Float64] = [1.0, 3.0]
    var names: List[String] = ["one", "three"]
    var svg = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        ).scale_x_ticks(pos, names)
    ).to_string()
    var ticks = _x_tick_pixels(svg)
    assert_equal(len(ticks), 2, "two ticks asked for, two drawn")
    # A tick mark is rounded to a pixel column; a marker center keeps
    # its fraction. Same column is the most the two can agree on.
    var cx = _center_xs(svg)
    assert_equal(
        ticks[0], Int(cx[1] + 0.5), "the tick at x=1 is on that marker"
    )
    assert_equal(
        ticks[1], Int(cx[3] + 0.5), "the tick at x=3 is on that marker"
    )
    assert_true(svg.find(">one<") != -1, "and carries its label")
    assert_true(svg.find(">three<") != -1)


def test_explicit_ticks_replace_the_computed_ones_entirely() raises:
    var plain = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        )
    ).to_string()
    var pos: List[Float64] = [1.0, 3.0]
    var pinned = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        ).scale_x_ticks(pos)
    ).to_string()
    assert_true(
        len(_x_tick_pixels(plain)) > 2, "the computed axis has more ticks"
    )
    assert_equal(len(_x_tick_pixels(pinned)), 2, "the explicit set is all")
    # With no labels given the positions are formatted like any others.
    assert_true(pinned.find(">1<") != -1, "an unlabeled tick is formatted")


def test_a_tick_outside_the_domain_is_dropped() raises:
    var pos: List[Float64] = [1.0, 99.0]
    var svg = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        ).scale_x_ticks(pos)
    ).to_string()
    assert_equal(
        len(_x_tick_pixels(svg)), 1, "only the one inside the domain draws"
    )
    assert_true(svg.find(">99<") == -1, "and the other prints nothing")


def test_explicit_y_labels_set_the_left_margin() raises:
    # The y labels are what the margin is measured from, so a long one
    # has to move the plot rect right or it would print over the axis.
    var pos: List[Float64] = [1.0, 3.0]
    var short: List[String] = ["a", "b"]
    var long: List[String] = [
        "a very long tick label",
        "another long one",
    ]
    var narrow = _rect(
        render_svg(
            scatter(
                _diagonal(),
                _diagonal(),
                theme=_controls_theme(),
                width=400,
                height=300,
            ).scale_y_ticks(pos, short)
        ).to_string()
    )
    var wide = _rect(
        render_svg(
            scatter(
                _diagonal(),
                _diagonal(),
                theme=_controls_theme(),
                width=400,
                height=300,
            ).scale_y_ticks(pos, long)
        ).to_string()
    )
    assert_true(
        wide[0] > narrow[0],
        "the long labels push the rect right: "
        + String(wide[0])
        + " vs "
        + String(narrow[0]),
    )


def test_a_reversed_x_axis_mirrors_every_marker() raises:
    var plain = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        )
    ).to_string()
    var flipped = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        ).scale_x_reverse()
    ).to_string()
    var r = _rect(plain)
    assert_equal(_rect(flipped)[0], r[0], "the rect itself does not move")
    assert_equal(_rect(flipped)[2], r[2])
    var a = _center_xs(plain)
    var b = _center_xs(flipped)
    assert_equal(len(a), len(b))
    var edges = Float64(r[0] + r[2])
    for i in range(len(a)):
        assert_true(
            abs(a[i] + b[i] - edges) < 0.01,
            "marker "
            + String(i)
            + " mirrors about the rect: "
            + String(a[i])
            + " and "
            + String(b[i]),
        )
    # Ascending before, descending after: the order really reversed.
    assert_true(a[0] < a[4] and b[0] > b[4])


def test_a_reversed_y_axis_mirrors_every_marker() raises:
    var plain = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        )
    ).to_string()
    var flipped = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        ).scale_y_reverse()
    ).to_string()
    var r = _rect(plain)
    var a = _center_ys(plain)
    var b = _center_ys(flipped)
    var edges = Float64(r[1] + r[3])
    for i in range(len(a)):
        assert_true(abs(a[i] + b[i] - edges) < 0.01, "marker " + String(i))
    assert_true(a[0] > a[4] and b[0] < b[4], "y ran up, now it runs down")


def test_reversing_keeps_the_ticks_and_their_labels() raises:
    # Only the pixels swap: the domain still walks low to high, so the
    # same tick values are drawn and only their columns move.
    var pos: List[Float64] = [1.0, 3.0]
    var names: List[String] = ["one", "three"]
    var svg = render_svg(
        scatter(
            _diagonal(),
            _diagonal(),
            theme=_controls_theme(),
            width=400,
            height=300,
        )
        .scale_x_ticks(pos, names)
        .scale_x_reverse()
    ).to_string()
    var ticks = _x_tick_pixels(svg)
    assert_equal(len(ticks), 2)
    assert_true(svg.find(">one<") != -1 and svg.find(">three<") != -1)
    var cx = _center_xs(svg)
    assert_equal(ticks[0], Int(cx[1] + 0.5), "still on the marker it names")
    assert_equal(ticks[1], Int(cx[3] + 0.5))


def test_equal_aspect_gives_equal_distances_equal_pixel_lengths() raises:
    # One unit right and one unit up, from the same corner.
    var xs: List[Float64] = [0.0, 1.0, 0.0]
    var ys: List[Float64] = [0.0, 0.0, 1.0]
    var free = render_svg(
        scatter(xs, ys, theme=_controls_theme(), width=400, height=300)
    ).to_string()
    var equal = render_svg(
        scatter(
            xs, ys, theme=_controls_theme(), width=400, height=300
        ).equal_aspect()
    ).to_string()
    var fx = _center_xs(free)
    var fy = _center_ys(free)
    var free_x = abs(fx[1] - fx[0])
    var free_y = abs(fy[2] - fy[0])
    assert_true(
        abs(free_x - free_y) > 10.0,
        "without it the same distance is drawn at two lengths",
    )
    var ex = _center_xs(equal)
    var ey = _center_ys(equal)
    var eq_x = abs(ex[1] - ex[0])
    var eq_y = abs(ey[2] - ey[0])
    assert_true(
        abs(eq_x - eq_y) <= 1.0,
        "with it they match: " + String(eq_x) + " and " + String(eq_y),
    )


def test_equal_aspect_shrinks_the_rect_and_centers_it() raises:
    var xs: List[Float64] = [0.0, 1.0, 0.0]
    var ys: List[Float64] = [0.0, 0.0, 1.0]
    var free = _rect(
        render_svg(
            scatter(xs, ys, theme=_controls_theme(), width=400, height=300)
        ).to_string()
    )
    var equal = _rect(
        render_svg(
            scatter(
                xs, ys, theme=_controls_theme(), width=400, height=300
            ).equal_aspect()
        ).to_string()
    )
    assert_true(
        equal[2] - equal[0] <= free[2] - free[0], "no wider than it had"
    )
    assert_true(
        equal[3] - equal[1] <= free[3] - free[1], "no taller than it had"
    )
    # Equal domain spans on both axes, so the rect comes out square.
    assert_true(
        abs((equal[2] - equal[0]) - (equal[3] - equal[1])) <= 1,
        "square for equal spans: "
        + String(equal[2] - equal[0])
        + " by "
        + String(equal[3] - equal[1]),
    )
    # Centered in the room it gave up, to within the odd pixel.
    var left_gap = equal[0] - free[0]
    var right_gap = free[2] - equal[2]
    assert_true(
        abs(left_gap - right_gap) <= 1,
        "centered: gaps " + String(left_gap) + " and " + String(right_gap),
    )


def test_axis_control_inputs_are_checked() raises:
    var none: List[Float64] = []
    with assert_raises(contains="at least one tick position"):
        _ = render_svg(scatter(_diagonal(), _diagonal()).scale_x_ticks(none))
    var two: List[Float64] = [1.0, 2.0]
    var one: List[String] = ["only one"]
    with assert_raises(contains="one label per position"):
        _ = render_svg(
            scatter(_diagonal(), _diagonal()).scale_y_ticks(two, one)
        )
    var neg: List[Float64] = [-1.0, 1.0]
    with assert_raises(contains="must be > 0 on a log-scaled axis"):
        _ = render_svg(
            scatter(_diagonal(), _diagonal()).scale_x_log().scale_x_ticks(neg)
        )


def test_equal_aspect_refuses_an_axis_with_no_constant_unit() raises:
    with assert_raises(contains="not supported on a log-scaled axis"):
        _ = render_svg(
            scatter(_diagonal(), _diagonal()).scale_y_log().equal_aspect()
        )


def test_the_axis_controls_raise_on_a_mark_that_ignores_them() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [1.0, 2.0, 3.0]
    var pos: List[Float64] = [1.0]
    with assert_raises(contains="only apply to"):
        _ = render_svg(bar(cats, vals).scale_x_ticks(pos))
    with assert_raises(contains="only apply to"):
        _ = render_svg(bar(cats, vals).equal_aspect())


# ==== symlog: a log axis that can show zero and negatives (#368) ====
# `scale_y_log()` needs strictly positive values, so a series crossing
# zero cannot go on one at all, and a linear axis collapses everything
# small against the largest value. Symlog is linear within
# `[-linthresh, linthresh]` and logarithmic beyond it.
#
# The transform is pinned by its definition rather than by a previous
# run: the two halves must agree at the threshold, the inverse must
# undo the forward everywhere, and zero must stay zero.


def test_symlog_is_continuous_where_the_two_halves_meet() raises:
    # The whole difficulty of a piecewise transform is the seam. At
    # |v| = linthresh both branches must give the same answer, or the
    # axis has a step in it exactly where the data is densest.
    var t = 10.0
    assert_equal(_symlog_forward(t, t), 1.0, "the positive seam")
    assert_equal(_symlog_forward(-t, t), -1.0, "the negative seam")
    # Approaching from the logarithmic side.
    var just_above = _symlog_forward(t * 1.0000001, t)
    assert_true(
        just_above > 1.0 and just_above < 1.000001,
        "the log side does not start at 1 -- got " + String(just_above),
    )


def test_symlog_keeps_zero_at_zero_and_keeps_the_sign() raises:
    var t = 2.5
    assert_equal(_symlog_forward(0.0, t), 0.0, "zero moved")
    assert_true(_symlog_forward(-100.0, t) < 0.0, "a negative went positive")
    assert_true(_symlog_forward(100.0, t) > 0.0, "a positive went negative")
    # Symmetric about zero, which is what the name promises.
    assert_equal(
        _symlog_forward(-100.0, t),
        -_symlog_forward(100.0, t),
        "the two sides are not mirror images",
    )


def test_symlog_inverse_undoes_forward_on_both_sides() raises:
    # Round-trip over values inside the linear region, at the seam, and
    # several decades out on each side.
    var t = 1.0
    var probes: List[Float64] = [
        0.0,
        0.25,
        -0.25,
        1.0,
        -1.0,
        9.5,
        -9.5,
        1000.0,
        -1000.0,
    ]
    for v in probes:
        var back = _symlog_inverse(_symlog_forward(v, t), t)
        # Relative, not absolute. The logarithmic branch round-trips
        # through log10 and pow, which preserve relative precision:
        # 9.5 comes back as 9.499999997584657, wrong by 2.4e-9 in
        # absolute terms and by 2.5e-10 in relative ones. An absolute
        # bound would tighten as the values grow, which is backwards
        # for a transform whose whole purpose is spanning decades.
        var scale = abs(v) if abs(v) > 1.0 else 1.0
        assert_true(
            abs(back - v) <= 1e-9 * scale,
            "round trip lost " + String(v) + " -- got " + String(back),
        )


def test_a_decade_is_a_decade_on_the_log_side() raises:
    # Equal ratios take equal space once past the threshold, which is
    # the property a log axis is chosen for and the one symlog has to
    # keep outside the linear region.
    var t = 1.0
    var a = _symlog_forward(10.0, t) - _symlog_forward(1.0, t)
    var b = _symlog_forward(100.0, t) - _symlog_forward(10.0, t)
    assert_true(
        abs(a - b) < 1e-12,
        "two decades took different space: "
        + String(a)
        + " against "
        + String(b),
    )


def test_the_linear_region_is_one_decade_wide() raises:
    # The ratio that makes the two halves comparable without a second
    # knob, and the thing a reader has to be able to rely on when
    # judging distance near zero against distance far from it.
    var t = 3.0
    var linear_half = _symlog_forward(t, t) - _symlog_forward(0.0, t)
    var one_decade = _symlog_forward(t * 10.0, t) - _symlog_forward(t, t)
    assert_true(
        abs(linear_half - one_decade) < 1e-12,
        "the linear half is not one decade wide",
    )


def test_a_symlog_domain_accepts_zero_and_negatives() raises:
    # `_log_data_extent` raises on these; that is the gap.
    var data: List[Float64] = [-500.0, -1.0, 0.0, 1.0, 500.0]
    var scale = _symlog_data_extent(data, 1.0)
    assert_true(scale.is_symlog, "the scale is not marked symlog")
    assert_equal(scale.symlog_linthresh, 1.0, "the threshold was lost")
    # Zero sits at the middle of a domain symmetric about it.
    var mid = (scale.to_pixel(0.0) - scale.to_pixel(-500.0)) / (
        scale.to_pixel(500.0) - scale.to_pixel(-500.0)
    )
    assert_true(
        abs(mid - 0.5) < 1e-9,
        "zero is not centered on symmetric data -- at " + String(mid),
    )


def test_a_symlog_domain_rejects_a_non_positive_threshold() raises:
    var data: List[Float64] = [-1.0, 0.0, 1.0]
    with assert_raises(contains="linthresh must be positive"):
        _ = _symlog_data_extent(data, 0.0)
    with assert_raises(contains="linthresh must be positive"):
        _ = _symlog_data_extent(data, -2.0)


def test_symlog_ticks_include_zero_and_the_threshold() raises:
    var data: List[Float64] = [-1000.0, 0.0, 1000.0]
    var scale = _symlog_data_extent(data, 1.0)
    var ticks = scale.ticks()
    var has_zero = False
    var has_thresh = False
    var has_neg_decade = False
    for v in ticks.values:
        if v == 0.0:
            has_zero = True
        if v == 1.0:
            has_thresh = True
        if abs(v + 100.0) < 1e-6:
            has_neg_decade = True
    assert_true(has_zero, "a symlog axis did not label zero")
    assert_true(has_thresh, "the threshold is not a tick")
    assert_true(has_neg_decade, "the negative decades are missing")


def test_an_axis_cannot_be_both_log_and_symlog() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises(contains="an axis cannot be both"):
        _ = render(scatter(x, y).scale_y_log().scale_y_symlog())
    with assert_raises(contains="an axis cannot be both"):
        _ = render(scatter(x, y).scale_x_log().scale_x_symlog())


def test_a_symlog_chart_renders_data_that_crosses_zero() raises:
    # The end-to-end case: a series a log axis could not take at all.
    var x: List[Float64] = [1.0, 2.0, 3.0, 4.0, 5.0]
    var y: List[Float64] = [-1000.0, -10.0, 0.0, 10.0, 1000.0]
    var c = render(
        scatter(x, y, width=400, height=300).scale_y_symlog(linthresh=1.0)
    )
    assert_equal(c.width, 400, "the chart did not render")


def test_auto_tick_labels_abbreviate_large_and_small_magnitudes() raises:
    var millions = LinearScale(0.0, 6000000.0, 0.0, 600.0).ticks()
    var million_labels = millions.labels()
    assert_true("2M" in million_labels, "millions should have an SI suffix")
    assert_true("6M" in million_labels, "the upper tick should be short")

    var billions = LinearScale(-2000000000.0, 2000000000.0, 0.0, 600.0).ticks()
    var billion_labels = billions.labels()
    assert_true("-2G" in billion_labels, "negative billions need a suffix")
    assert_true("0" in billion_labels, "zero needs no suffix")
    assert_true("2G" in billion_labels, "positive billions need a suffix")

    var microns = LinearScale(0.0, 0.00006, 0.0, 600.0).ticks()
    var micron_labels = microns.labels()
    assert_true("20µ" in micron_labels, "small values need a prefix")
    assert_true("60µ" in micron_labels, "the upper small tick should be short")


# ---------------------------------------------------------------
# Tick counts that fit the axis (#727)


def test_a_full_size_axis_keeps_the_default_ticks() raises:
    # The fitting only ever removes ticks when they would collide, so a
    # normal chart's axis gets exactly what ticks() gives it.
    var scale = LinearScale(0.0, 100.0, 0.0, 1.0)
    var cache = FontCache()
    var sc = _Scaled(Theme())
    var fitted = _fitting_ticks(
        scale, 560.0, True, TickFormat.AUTO, sc, "sans-serif", cache
    )
    assert_equal(fitted.values, scale.ticks().values)
    var tall = _fitting_ticks(
        scale, 350.0, False, TickFormat.AUTO, sc, "sans-serif", cache
    )
    assert_equal(tall.values, scale.ticks().values)


def test_a_narrow_axis_gets_ticks_that_fit_and_keeps_two_when_two_fit() raises:
    var cache = FontCache()
    var sc = _Scaled(Theme())
    # 0..1000 across 70 px: the default 0, 200, ... 1000 collide -- the
    # precondition, checked, so this case really exercises the thinning
    # -- and the fitted set is coarser, fits, and still has two ticks.
    var narrow = LinearScale(0.0, 1000.0, 0.0, 1.0)
    var default = narrow.ticks()
    assert_true(
        not _ticks_fit(
            narrow,
            default,
            70.0,
            True,
            TickFormat.AUTO,
            sc,
            "sans-serif",
            cache,
        ),
        "precondition: the default ticks collide at this width",
    )
    var t = _fitting_ticks(
        narrow, 70.0, True, TickFormat.AUTO, sc, "sans-serif", cache
    )
    assert_true(
        _ticks_fit(
            narrow, t, 70.0, True, TickFormat.AUTO, sc, "sans-serif", cache
        )
    )
    assert_true(len(t.values) >= 2, "two ticks still fit, so two are kept")
    assert_true(len(t.values) < len(default.values))
    # 0..2.2 over 12 px: 0 and 2 would sit 11 px apart, closer than the
    # 15 px two 12 px labels need, so one label, not two on top of each
    # other.
    var short = LinearScale(0.0, 2.2, 0.0, 1.0)
    var one = _fitting_ticks(
        short, 12.0, False, TickFormat.AUTO, sc, "sans-serif", cache
    )
    assert_equal(
        len(one.values),
        1,
        "one clean label rather than two on top of each other",
    )


def test_no_tick_labels_overlap_in_a_small_pairplot() raises:
    # The case #727 was found in: 140 x 120 cells. Every bottom-axis
    # label row -- middle-anchored text sharing one y -- is read back
    # from the SVG and each neighbor pair checked for a gap, with the
    # same text metrics the renderer uses.
    var a: List[Float64] = [
        1.2,
        2.5,
        3.1,
        4.8,
        5.0,
        6.7,
        7.3,
        8.1,
        9.9,
        10.4,
        11.8,
        12.2,
    ]
    var b: List[Float64] = [
        110,
        150,
        180,
        175,
        240,
        260,
        290,
        300,
        340,
        360,
        380,
        420,
    ]
    var c: List[Float64] = [
        0.31,
        0.29,
        0.27,
        0.25,
        0.22,
        0.2,
        0.19,
        0.17,
        0.14,
        0.13,
        0.11,
        0.08,
    ]
    var cols: List[List[Float64]] = [a^, b^, c^]
    var names: List[String] = ["Engine (L)", "Horsepower", "Efficiency"]
    var svg = render_svg(
        pairplot(cols, names, cell_width=140, cell_height=120)
    ).to_string()
    var xs = _attr_values(svg, "text", "x")
    var ys = _attr_values(svg, "text", "y")
    var anchors = _attr_values(svg, "text", "text-anchor")
    var texts = List[String]()
    var at = 0
    while True:
        var open = svg.find("<text", at)
        if open < 0:
            break
        var start = svg.find(">", open) + 1
        var close = svg.find("</text>", start)
        texts.append(String(svg[byte=start:close]))
        at = close
    var cache = FontCache()
    var font = Theme().font_size
    var checked = 0
    for i in range(len(xs)):
        if anchors[i] != "middle":
            continue
        for j in range(i + 1, len(xs)):
            if anchors[j] != "middle" or ys[j] != ys[i]:
                continue
            var gap = abs(Float64(xs[j]) - Float64(xs[i]))
            var one: List[String] = [texts[i]]
            var two: List[String] = [texts[j]]
            var half = (
                _max_label_width(one, font, family="sans-serif", cache=cache)
                + _max_label_width(two, font, family="sans-serif", cache=cache)
            ) / 2.0
            # Only neighbors within one cell's width can collide.
            if gap < 100.0:
                checked += 1
                assert_true(
                    gap >= half,
                    "labels " + texts[i] + " and " + texts[j] + " overlap",
                )
    assert_true(checked > 0, "the test read some neighboring labels")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
