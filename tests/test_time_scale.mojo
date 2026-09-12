"""Tests for the temporal axis (#195): where the ticks land and what
they read, across nine orders of magnitude of span.

Every expectation here is a calendar fact -- a month start, a local
midnight, a Monday -- rather than a number that came out of a previous
run, because the bug this replaces was ticks on arithmetically tidy but
calendrically meaningless boundaries.
"""

from morrow import Morrow, TimeZone
from std.testing import TestSuite, assert_equal, assert_true

from _test_helpers import _count_tag
from dataviz import line, save
from dataviz.plot import Plot, render_layers_svg, render_svg
from dataviz.scale import LinearScale
from dataviz.theme import Theme


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
