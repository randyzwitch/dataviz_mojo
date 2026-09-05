"""Calendar-aware tick positions and labels for a day-resolution
temporal axis (#195, first slice).

`_nice_step` picks 1/2/5 x 10^n, which is right for a quantity and wrong
for time: a reader wants month starts, quarters or years, and those are
irregular -- 28 to 31 days, 365 or 366 -- in a way no multiplicative
step can express. So ticks here are *walked* along the calendar rather
than computed, and each carries its own label.

This is the half of #195 that no encoding decision changes. The issue
leaves open how a caller supplies dates (ISO strings, epoch numbers, or
a real Date type) and whether a temporal axis is requested or inferred;
all three still need the same answer to "given a span of days, where do
the ticks go and what do they read". Nothing here is wired into `Plot`,
and no public API is added, precisely so that decision stays open.

Day resolution only. Sub-day steps (hours, minutes) need an epoch unit
finer than days, which is design question 2 on the issue and not settled
here; `_TimeUnit`'s ladder is arranged so those slot in below `DAY`
without disturbing what is above it.
"""

from dataviz.calendar_heatmap import _Date, _days_from_civil
from dataviz.scale import Ticks


def _month_name(month: Int) -> String:
    """The three-letter abbreviation for a 1-12 month number.

    Args:
        month: 1 (January) through 12.

    Returns:
        `"Jan"` through `"Dec"`.
    """
    var names: List[String] = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
    ]
    return names[month - 1]


struct _TimeUnit(Copyable, ImplicitlyCopyable, Movable):
    """Which calendar interval a temporal axis steps by.

    Ordered coarsest-last so the ladder `_pick_step` ranks is ascending
    by interval length. Sub-day units would extend it below `DAY`
    without changing the rungs above.
    """

    var _value: Int

    comptime DAY = Self(0)
    comptime WEEK = Self(1)
    comptime MONTH = Self(2)
    comptime YEAR = Self(3)

    def __init__(out self, value: Int):
        self._value = value

    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value


struct _TimeStep(Copyable, ImplicitlyCopyable, Movable):
    """One rung of the ladder: a unit and how many of it to advance by.

    `MONTH` with `count` 3 is a quarterly axis, `YEAR` with 10 a decade
    axis. Kept as a pair rather than an enum per interval so the rungs
    stay data rather than code.
    """

    var unit: _TimeUnit
    var count: Int

    def __init__(out self, unit: _TimeUnit, count: Int):
        self.unit = unit
        self.count = count


def _is_leap(year: Int) -> Bool:
    """Proleptic Gregorian leap year.

    Args:
        year: The year.

    Returns:
        True when February has 29 days.
    """
    if year % 4 != 0:
        return False
    if year % 100 != 0:
        return True
    return year % 400 == 0


def _days_in_month(year: Int, month: Int) -> Int:
    """How many days that month has.

    Args:
        year: The year, for February.
        month: 1-12.

    Returns:
        28-31.
    """
    if month == 2:
        return 29 if _is_leap(year) else 28
    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30
    return 31


def _civil_from_days(days: Int) raises -> _Date:
    """The inverse of `_days_from_civil`: a day count back to a calendar
    date. Howard Hinnant's `civil_from_days` (public domain), the exact
    counterpart of the algorithm `calendar_heatmap.mojo` already uses in
    the forward direction.

    Walking the calendar needs this: a tick at "the first of the next
    month" is only expressible as a date, and only a date can be
    formatted as `Mar 2026`.

    Args:
        days: Days since 1970-01-01, negative for earlier dates.

    Returns:
        The calendar date.
    """
    var z = days + 719468
    var era = (z if z >= 0 else z - 146096) // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var y = yoe + era * 400
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var d = doy - (153 * mp + 2) // 5 + 1
    var m = mp + (3 if mp < 10 else -9)
    if m <= 2:
        y += 1
    return _Date(y, m, d)


def _ladder() -> List[_TimeStep]:
    """The rungs a temporal axis may step by, coarsest last.

    Chosen so consecutive rungs differ by roughly 2-3x, which keeps the
    tick count near the target whatever the span: a domain landing
    between two rungs gets the coarser one rather than an axis crowded
    to twice the requested density.

    Returns:
        The ladder, ascending by interval length.
    """
    var out = List[_TimeStep]()
    out.append(_TimeStep(_TimeUnit.DAY, 1))
    out.append(_TimeStep(_TimeUnit.DAY, 2))
    out.append(_TimeStep(_TimeUnit.WEEK, 1))
    out.append(_TimeStep(_TimeUnit.WEEK, 2))
    out.append(_TimeStep(_TimeUnit.MONTH, 1))
    out.append(_TimeStep(_TimeUnit.MONTH, 3))
    out.append(_TimeStep(_TimeUnit.MONTH, 6))
    out.append(_TimeStep(_TimeUnit.YEAR, 1))
    out.append(_TimeStep(_TimeUnit.YEAR, 2))
    out.append(_TimeStep(_TimeUnit.YEAR, 5))
    out.append(_TimeStep(_TimeUnit.YEAR, 10))
    out.append(_TimeStep(_TimeUnit.YEAR, 25))
    out.append(_TimeStep(_TimeUnit.YEAR, 50))
    out.append(_TimeStep(_TimeUnit.YEAR, 100))
    return out^


def _approx_days(step: _TimeStep) -> Float64:
    """Roughly how many days one `step` spans, for choosing a rung.

    Approximate on purpose: months and years vary, and this only ranks
    the rungs. The tick positions themselves are walked exactly.

    Args:
        step: The rung.

    Returns:
        An average length in days.
    """
    if step.unit == _TimeUnit.DAY:
        return Float64(step.count)
    if step.unit == _TimeUnit.WEEK:
        return Float64(step.count) * 7.0
    if step.unit == _TimeUnit.MONTH:
        return Float64(step.count) * 30.436875
    return Float64(step.count) * 365.2425


def _pick_step(span_days: Float64, target_count: Int) -> _TimeStep:
    """The rung whose interval comes closest to the one `target_count`
    ticks would need.

    Closest *ratio*, not closest difference: a rung twice too long and
    one half too long are equally wrong to a reader, and the ladder spans
    four orders of magnitude, so comparing `approx / ideal` against its
    reciprocal is the only scale-free way to rank rungs. Comparing
    absolute days would make every fine rung look identical next to a
    century.

    Taking the *nearest* rung rather than the coarsest one clearing the
    target matters at the boundaries: a five-month domain is 4.96 months,
    just under a target of 5, and "at least 5 ticks" would drop it all
    the way to fortnightly -- eleven ticks reading `15 Jan`, `29 Jan`,
    where the month rung it just missed reads `Jan`, `Feb`.

    Args:
        span_days: The domain's length in days.
        target_count: Roughly how many ticks to aim for.

    Returns:
        The rung to walk by.
    """
    var rungs = _ladder()
    var want = Float64(target_count if target_count > 1 else 2)
    var ideal = span_days / want
    var chosen = rungs[0]
    var best = 0.0
    for i in range(len(rungs)):
        var ratio = _approx_days(rungs[i]) / ideal
        var score = ratio if ratio >= 1.0 else 1.0 / ratio
        if i == 0 or score < best:
            best = score
            chosen = rungs[i]
    return chosen.copy()


def _first_tick_on_or_after(days: Int, step: _TimeStep) raises -> Int:
    """The first tick position at or after `days` for this rung.

    Day and week rungs anchor on the epoch, so their ticks fall on a
    fixed lattice; month and year rungs snap to a calendar boundary
    divisible by the count, so a quarterly axis lands on Jan/Apr/Jul/Oct
    rather than wherever the data happens to start.

    Args:
        days: Domain start, in days since the epoch.
        step: The rung.

    Returns:
        The first tick's day count.
    """
    if step.unit == _TimeUnit.DAY or step.unit == _TimeUnit.WEEK:
        var stride = step.count * (7 if step.unit == _TimeUnit.WEEK else 1)
        var rem = days % stride
        if rem < 0:
            rem += stride
        return days if rem == 0 else days + (stride - rem)

    var d = _civil_from_days(days)
    if step.unit == _TimeUnit.MONTH:
        var month0 = d.month - 1
        var snapped = (month0 // step.count) * step.count
        var year = d.year
        if snapped < month0 or d.day > 1:
            snapped += step.count
            if snapped >= 12:
                snapped -= 12
                year += 1
        return _days_from_civil(_Date(year, snapped + 1, 1))

    var year_snapped = (d.year // step.count) * step.count
    if year_snapped < d.year or d.month > 1 or d.day > 1:
        year_snapped += step.count
    return _days_from_civil(_Date(year_snapped, 1, 1))


def _advance(days: Int, step: _TimeStep) raises -> Int:
    """One rung forward from `days`.

    Months and years advance on the calendar rather than by a fixed
    number of days, which is the whole reason ticks are walked: adding
    "one month" to 31 January is 1 March if done in days and 1 February
    if done on the calendar.

    Args:
        days: Current tick, in days since the epoch.
        step: The rung.

    Returns:
        The next tick's day count.
    """
    if step.unit == _TimeUnit.DAY:
        return days + step.count
    if step.unit == _TimeUnit.WEEK:
        return days + step.count * 7

    var d = _civil_from_days(days)
    if step.unit == _TimeUnit.MONTH:
        var m = d.month - 1 + step.count
        var y = d.year + m // 12
        m = m % 12
        var day = d.day
        var limit = _days_in_month(y, m + 1)
        if day > limit:
            day = limit
        return _days_from_civil(_Date(y, m + 1, day))

    var year = d.year + step.count
    var day2 = d.day
    var limit2 = _days_in_month(year, d.month)
    if day2 > limit2:
        day2 = limit2
    return _days_from_civil(_Date(year, d.month, day2))


def _label_for(date: _Date, step: _TimeStep, show_year: Bool) -> String:
    """One tick's label, at the resolution its rung implies.

    A year rung reads `2026`; a month or quarter rung reads `Mar`, with
    the year appended only when it differs from the previous tick's, so a
    multi-year monthly axis marks each January without repeating "2026"
    twelve times. Day and week rungs read `3 Mar`, with the same
    year rule.

    Args:
        date: The tick's calendar date.
        step: The rung being walked.
        show_year: Whether this tick starts a new year.

    Returns:
        The label.
    """
    if step.unit == _TimeUnit.YEAR:
        return String(date.year)

    var month = _month_name(date.month)
    if step.unit == _TimeUnit.MONTH:
        return month + " " + String(date.year) if show_year else month

    var day_part = String(date.day) + " " + month
    return day_part + " " + String(date.year) if show_year else day_part


def _time_ticks(
    domain_min_days: Float64, domain_max_days: Float64, target_count: Int = 5
) raises -> Ticks:
    """Calendar-aware ticks over a domain measured in days since the
    epoch, with a pre-formatted label per tick.

    Returns them through `Ticks`' `override_labels`, the same seam
    `_log_ticks` uses: an axis whose labels are not a shared decimal
    count hands back its own strings and bypasses `_format_fixed`
    entirely. That is what lets a temporal axis drop into
    `_draw_continuous_axis_frame` unchanged -- it measures `.labels()`
    for the dynamic margin, so wider labels like `Mar 2026` size the
    margin correctly for free.

    A zero-span or inverted domain returns the single day it names, so a
    degenerate axis still draws one meaningful label.

    Args:
        domain_min_days: Domain start, days since 1970-01-01.
        domain_max_days: Domain end, days since 1970-01-01.
        target_count: Roughly how many ticks to aim for; the rung
            chosen decides the actual count. Defaults to `5`.

    Returns:
        Tick positions in days, with one label each.
    """
    var lo = Int(domain_min_days)
    var hi = Int(domain_max_days)
    if hi <= lo:
        var one = List[Float64]()
        one.append(Float64(lo))
        var one_label = List[String]()
        var d0 = _civil_from_days(lo)
        one_label.append(_label_for(d0, _TimeStep(_TimeUnit.DAY, 1), True))
        return Ticks(one^, 0, one_label^)

    var step = _pick_step(Float64(hi - lo), target_count)
    var values = List[Float64]()
    var labels = List[String]()

    var at = _first_tick_on_or_after(lo, step)
    var previous_year = 0
    var first = True
    while at <= hi:
        var d = _civil_from_days(at)
        var show_year = first or d.year != previous_year
        values.append(Float64(at))
        labels.append(_label_for(d, step, show_year))
        previous_year = d.year
        first = False
        at = _advance(at, step)

    return Ticks(values^, 0, labels^)
