"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers scale.mojo (LinearScale, the
nice-tick algorithm, _format_fixed, _label_decimals, log ticks),
ordinal_scale.mojo, color_scale.mojo (domain projection and the
zero-span case; interpolation itself is tested in canvas.gradient),
time_ticks.mojo (the calendar walk and its labels),
colors.mojo (spot checks against the CSS spec and the gray/grey
pairs; the one named-color-through-a-real-render check lives in
test_marks_basic.mojo, which rasterizes), and array_like.mojo
(Float64Sequence/StringSequence, the DType-generic overloads, exact
Int conversion up to 2^53, whole-number labels from List[Int]).
"""

from _test_helpers import Lcg, _count_color
from canvas.color import Color
from dataviz import (
    CORNFLOWERBLUE,
    DARKGRAY,
    DARKGREY,
    DIMGRAY,
    DIMGREY,
    GRAY,
    GREEN,
    GREY,
    LIGHTGRAY,
    LIGHTGREY,
    LIGHTSLATEGRAY,
    LIGHTSLATEGREY,
    SLATEGRAY,
    SLATEGREY,
    bar,
)
from dataviz.array_like import (
    Float64Sequence,
    StringSequence,
    _materialize_floats,
    _materialize_scalar_list,
    _materialize_strings,
)
from dataviz.calendar_heatmap import _Date, _days_from_civil
from dataviz.color_scale import ColorScale
from dataviz.colors import BLACK, BLUE, RED, WHITE
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import Plot, render, render_svg
from dataviz.scale import (
    LinearScale,
    Ticks,
    TickFormat,
    _format_fixed,
    _format_tick,
    _label_decimals,
    _log_ticks,
    _min_max,
    _nice_step,
)
from dataviz.theme import Theme
from dataviz.time_ticks import (
    _TimeStep,
    _TimeUnit,
    _advance,
    _civil_from_days,
    _days_in_month,
    _is_leap,
    _pick_step,
    _time_ticks,
)
from std.math import floor, log10, pow
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from std.utils.numerics import inf, nan


# ---------------------------------------------------------------
# from tests/test_scale.mojo
# ---------------------------------------------------------------


def _assert_ticks_equal(
    actual: List[Float64], expected: List[Float64], label: String
) raises:
    assert_equal(len(actual), len(expected), label)
    for i in range(len(expected)):
        assert_true(
            actual[i] > expected[i] - 1e-9 and actual[i] < expected[i] + 1e-9,
            label,
        )


def test_linear_scale_endpoints_map_to_range_exactly() raises:
    var s = LinearScale(0.0, 100.0, 20.0, 620.0)
    assert_equal(s.to_pixel(0.0), 20.0)
    assert_equal(s.to_pixel(100.0), 620.0)
    assert_equal(s.to_pixel(50.0), 320.0)


def test_linear_scale_handles_a_reversed_range_for_the_y_axis() raises:
    # A y-axis scale: domain_min (the smallest data value) maps to the
    # *bottom* of the plot area (a larger pixel y), domain_max to the
    # *top* (a smaller pixel y) -- pixel y increases downward. The
    # slope must come out negative with no separate flip flag.
    var s = LinearScale(0.0, 10.0, 380.0, 20.0)
    assert_equal(s.to_pixel(0.0), 380.0)
    assert_equal(s.to_pixel(10.0), 20.0)
    assert_true(s.scale() < 0.0)


def test_linear_scale_zero_domain_span_maps_everything_to_range_min() raises:
    var s = LinearScale(5.0, 5.0, 20.0, 620.0)
    assert_equal(s.scale(), 0.0)
    assert_equal(s.to_pixel(5.0), 20.0)
    assert_equal(s.to_pixel(999.0), 20.0)  # degenerate, but doesn't crash


def test_nice_step_matches_hand_computed_values() raises:
    # Independently computed by hand (Heckbert's nice-numbers
    # algorithm, see scale.mojo's docstring).
    var a = _nice_step(0.0, 100.0, 5)
    assert_equal(a.step, 20.0)
    assert_equal(a.exponent, 1)

    var b = _nice_step(3.0, 27.0, 5)
    assert_equal(b.step, 5.0)
    assert_equal(b.exponent, 0)

    var c = _nice_step(-50.0, 50.0, 5)
    assert_equal(c.step, 20.0)
    assert_equal(c.exponent, 1)

    var d = _nice_step(0.0, 0.01, 5)
    assert_equal(d.step, 0.002)
    assert_equal(d.exponent, -3)

    var e = _nice_step(0.0, 1.0, 5)
    assert_equal(e.step, 0.2)
    assert_equal(e.exponent, -1)


def test_ticks_matches_hand_computed_values_domain_0_100() raises:
    var s = LinearScale(0.0, 100.0, 0.0, 600.0)
    var t = s.ticks(5)
    var expected: List[Float64] = [0.0, 20.0, 40.0, 60.0, 80.0, 100.0]
    _assert_ticks_equal(t.values, expected, "domain [0,100]")
    assert_equal(t.decimals, 0)


def test_ticks_matches_hand_computed_values_domain_3_27() raises:
    var s = LinearScale(3.0, 27.0, 0.0, 600.0)
    var t = s.ticks(5)
    var expected: List[Float64] = [5.0, 10.0, 15.0, 20.0, 25.0]
    _assert_ticks_equal(t.values, expected, "domain [3,27]")
    assert_equal(t.decimals, 0)


def test_ticks_matches_hand_computed_values_domain_negative() raises:
    var s = LinearScale(-50.0, 50.0, 0.0, 600.0)
    var t = s.ticks(5)
    var expected: List[Float64] = [-40.0, -20.0, 0.0, 20.0, 40.0]
    _assert_ticks_equal(t.values, expected, "domain [-50,50]")


def test_ticks_matches_hand_computed_values_domain_fractional() raises:
    var s = LinearScale(0.0, 0.01, 0.0, 600.0)
    var t = s.ticks(5)
    var expected: List[Float64] = [0.0, 0.002, 0.004, 0.006, 0.008, 0.01]
    _assert_ticks_equal(t.values, expected, "domain [0,0.01]")
    assert_equal(t.decimals, 3)


def test_ticks_zero_domain_span_returns_a_single_tick() raises:
    var s = LinearScale(7.0, 7.0, 0.0, 600.0)
    var t = s.ticks(5)
    assert_equal(len(t.values), 1)
    assert_equal(t.values[0], 7.0)
    assert_equal(t.decimals, 0)


def test_format_fixed_matches_hand_computed_strings() raises:
    assert_equal(_format_fixed(20.0, 0), "20")
    assert_equal(_format_fixed(-40.0, 0), "-40")
    assert_equal(_format_fixed(0.002, 3), "0.002")
    assert_equal(_format_fixed(-0.002, 3), "-0.002")
    assert_equal(_format_fixed(0.2, 1), "0.2")
    assert_equal(_format_fixed(123.456, 2), "123.46")


def test_format_fixed_avoids_binary_floating_point_drift() raises:
    # 0.0 + 3*0.1 is 0.30000000000000004 as a raw Float64; _format_fixed
    # must not print that.
    var drifted = 0.0 + 3.0 * 0.1
    assert_equal(_format_fixed(drifted, 1), "0.3")


def test_label_decimals_matches_hand_computed_counts() raises:
    assert_equal(_label_decimals(12.0), 0)
    assert_equal(_label_decimals(-12.0), 0)
    assert_equal(_label_decimals(15.3), 1)
    assert_equal(_label_decimals(15.25), 2)
    assert_equal(_label_decimals(0.0), 0)
    # 1.0 / 3.0 needs far more than 2 decimals to represent exactly --
    # the default max_decimals=2 cap applies rather than searching
    # forever.
    assert_equal(_label_decimals(1.0 / 3.0), 2)
    # A caller-widened cap still finds the real value once it's within
    # reach.
    assert_equal(_label_decimals(15.25, max_decimals=3), 2)
    assert_equal(_label_decimals(15.125, max_decimals=3), 3)


def test_label_decimals_avoids_binary_floating_point_drift() raises:
    # The same drift: a value that reads as 0.3 must not need 15+ decimals.
    var drifted = 0.0 + 3.0 * 0.1
    assert_equal(_label_decimals(drifted), 1)


def test_format_fixed_falls_back_past_2_53_instead_of_overflowing() raises:
    # #205: _format_fixed rounds value*10^decimals through Int(Float64),
    # which silently wraps to garbage once that product exceeds what a
    # Float64 (or, sooner, Int) can represent exactly, rather than
    # raising. 1e19/1e17*100/-3e18*10 each used to produce wrong digits
    # (or, for -3e18, a doubled leading minus sign from an Int64-min
    # negation overflow) instead of failing loudly. Mojo's own
    # String(Float64) is the fallback and is used verbatim, so these
    # match its scientific-notation output exactly.
    assert_equal(_format_fixed(1e19, 0), "1e+19")
    assert_equal(_format_fixed(1e17, 2), "1e+17")
    assert_equal(_format_fixed(-3e18, 1), "-3e+18")
    assert_equal(_format_fixed(-3e18, 1), String(-3e18))


def test_format_fixed_exact_int_boundary_still_uses_the_precise_path() raises:
    # 2^53 is the largest magnitude every integer is still exactly
    # representable in a Float64 (see
    # test_materialize_scalar_list_converts_int_exactly_up_to_2_pow_53 in
    # this same file for array_like.mojo's own take on this boundary);
    # _format_fixed must keep using its precise digit-by-digit path here,
    # not the scientific-notation fallback, since nothing is lost yet.
    assert_equal(_format_fixed(9007199254740992.0, 0), "9007199254740992")
    assert_equal(_format_fixed(-9007199254740992.0, 0), "-9007199254740992")


def test_format_fixed_normal_range_values_are_unaffected_by_the_overflow_guard() raises:
    # The overflow guard must not change any ordinary value's output --
    # same assertions as test_format_fixed_matches_hand_computed_strings,
    # re-run to pin that the new early-return branches are true no-ops
    # below the threshold.
    assert_equal(_format_fixed(20.0, 0), "20")
    assert_equal(_format_fixed(-40.0, 0), "-40")
    assert_equal(_format_fixed(0.002, 3), "0.002")
    assert_equal(_format_fixed(123.456, 2), "123.46")


def test_label_decimals_returns_zero_past_2_53_instead_of_overflowing() raises:
    # #205's other call site: _label_decimals' own search loop rounds
    # through the same Int(Float64) cast per candidate decimal count, so
    # it must short-circuit before entering the loop rather than run it
    # (harmlessly, since Int overflow doesn't crash here, but pointlessly)
    # against an already-integral magnitude with no fractional part left
    # to discover.
    assert_equal(_label_decimals(1e19), 0)
    assert_equal(_label_decimals(-3e18), 0)
    assert_equal(_label_decimals(9007199254740992.0), 0)


def test_ticks_labels_on_a_huge_domain_uses_the_overflow_fallback_not_garbage() raises:
    # A domain far past 2^53 used to produce 19-digit labels built from
    # wrapped/garbage Int arithmetic once decimals happened to be
    # positive, or merely-unwieldy-but-correct all-digits labels at
    # decimals=0 (the case _nice_step actually produces here, since its
    # exponent is always >= 0 for a domain this large). This pins that
    # such a domain's ticks are readable and never garbage.
    var s = LinearScale(0.0, 5e18, 0.0, 1.0)
    var t = s.ticks()
    var labels = t.labels()
    assert_equal(labels[0], "0")
    assert_equal(labels[1], "1e+18")
    assert_equal(labels[len(labels) - 1], "5e+18")


def test_ticks_labels_uses_format_fixed_per_tick() raises:
    var s = LinearScale(0.0, 0.01, 0.0, 600.0)
    var t = s.ticks(5)
    var labels = t.labels()
    assert_equal(labels[0], "0.000")
    assert_equal(labels[1], "0.002")
    assert_equal(labels[len(labels) - 1], "0.010")


def test_format_tick_auto_matches_format_fixed() raises:
    # AUTO is _format_fixed unchanged, decimals as given.
    assert_equal(_format_tick(20.0, 0, TickFormat.AUTO), "20")
    assert_equal(_format_tick(0.25, 3, TickFormat.AUTO), "0.250")


def test_format_tick_percent_matches_hand_computed_strings() raises:
    # value*100, decimals-2 (a domain step needing 3 decimals in raw
    # units needs 1 once scaled to percent).
    assert_equal(_format_tick(0.25, 3, TickFormat.PERCENT), "25.0%")
    assert_equal(_format_tick(0.5, 2, TickFormat.PERCENT), "50%")
    assert_equal(_format_tick(1.0, 2, TickFormat.PERCENT), "100%")
    assert_equal(_format_tick(0.0, 2, TickFormat.PERCENT), "0%")


def test_format_tick_thousands_matches_hand_computed_strings() raises:
    assert_equal(_format_tick(1500000.0, 0, TickFormat.THOUSANDS), "1,500,000")
    assert_equal(
        _format_tick(-1500000.0, 0, TickFormat.THOUSANDS), "-1,500,000"
    )
    assert_equal(_format_tick(999.0, 0, TickFormat.THOUSANDS), "999")
    assert_equal(_format_tick(1234.5, 1, TickFormat.THOUSANDS), "1,234.5")


def test_format_tick_si_matches_hand_computed_strings() raises:
    assert_equal(_format_tick(1500000.0, 0, TickFormat.SI), "1.5M")
    assert_equal(_format_tick(2000000.0, 0, TickFormat.SI), "2M")
    assert_equal(_format_tick(2500.0, 0, TickFormat.SI), "2.5k")
    assert_equal(_format_tick(0.0025, 0, TickFormat.SI), "2.5m")
    assert_equal(_format_tick(0.0, 0, TickFormat.SI), "0")
    assert_equal(_format_tick(500.0, 0, TickFormat.SI), "500")


def test_format_tick_scientific_matches_hand_computed_strings() raises:
    assert_equal(_format_tick(1500000.0, 0, TickFormat.SCIENTIFIC), "1.5e+6")
    assert_equal(_format_tick(0.0025, 0, TickFormat.SCIENTIFIC), "2.5e-3")
    assert_equal(_format_tick(0.0, 0, TickFormat.SCIENTIFIC), "0e+0")
    assert_equal(_format_tick(-42.0, 0, TickFormat.SCIENTIFIC), "-4.2e+1")


def test_format_tick_fixed_always_uses_its_own_decimal_count() raises:
    # FIXED(n) ignores the passed-in decimals entirely.
    assert_equal(_format_tick(19.999, 5, TickFormat.FIXED(2)), "20.00")
    assert_equal(_format_tick(3.0, 5, TickFormat.FIXED(0)), "3")


def test_format_tick_with_affixes_wraps_every_kind() raises:
    assert_equal(
        _format_tick(19.99, 0, TickFormat.FIXED(2).with_affixes(prefix="$")),
        "$19.99",
    )
    assert_equal(
        _format_tick(0.5, 2, TickFormat.PERCENT.with_affixes(suffix=" off")),
        "50% off",
    )


def test_format_tick_falls_back_to_scientific_past_2_53_regardless_of_format() raises:
    # #205's overflow boundary applies to every kind here, not just AUTO,
    # since THOUSANDS/PERCENT/FIXED all still route through _format_fixed
    # internally.
    assert_equal(_format_tick(5e18, 0, TickFormat.THOUSANDS), "5e+18")
    assert_equal(_format_tick(5e18, 0, TickFormat.PERCENT), "5e+18")
    assert_equal(_format_tick(5e18, 2, TickFormat.FIXED(2)), "5e+18")


def test_ticks_labels_accepts_a_tick_format() raises:
    # Real ticks (not hand-built values) formatted as percent: domain
    # [0, 1] -> ticks [0, 0.2, 0.4, 0.6, 0.8, 1.0] at decimals=1, which
    # PERCENT renders at decimals-2 -> max(0, -1) -> 0 decimal places.
    var s = LinearScale(0.0, 1.0, 0.0, 600.0)
    var t = s.ticks(5)
    var labels = t.labels(TickFormat.PERCENT)
    assert_equal(labels[0], "0%")
    assert_equal(labels[1], "20%")
    assert_equal(labels[len(labels) - 1], "100%")


def test_render_svg_y_tick_format_reaches_the_axis_labels() raises:
    # #210: Theme.y_tick_format actually reaches the rendered SVG, not
    # just the isolated formatter.
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.1, 0.5, 0.9]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .theme(Theme(y_tick_format=TickFormat.PERCENT))
        .size(400, 300)
    )
    var s = render_svg(plot).to_string()
    assert_true(">40%<" in s, "a percent-formatted y tick draws")
    assert_true(">0.4<" not in s, "not also the plain AUTO-formatted label")


def test_log_scale_to_pixel_matches_hand_derived_positions() raises:
    # domain [0, 3] (log10-space, real [1, 1000]) -> range [400, 0]:
    # scale() = (0-400)/(3-0) = -133.333..., translate() = 400. to_pixel(v)
    # = log10(v)*scale() + translate().
    var s = LinearScale(0.0, 3.0, 400.0, 0.0, is_log=True)
    assert_equal(s.to_pixel(1.0), 400.0)
    assert_equal(s.to_pixel(10.0), 266.66666666666663)
    assert_equal(s.to_pixel(100.0), 133.33333333333331)
    assert_equal(s.to_pixel(1000.0), 0.0)


def test_log_ticks_wide_domain_returns_major_ticks_only() raises:
    # > 2 decades (domain [0, 3], real [1, 1000]) -> 1*10^k only.
    var t = _log_ticks(0.0, 3.0)
    var expected: List[Float64] = [1.0, 10.0, 100.0, 1000.0]
    _assert_ticks_equal(t.values, expected, "wide log domain [0,3]")
    var labels = t.labels()
    assert_equal(labels[0], "1")
    assert_equal(labels[1], "10")
    assert_equal(labels[2], "100")
    assert_equal(labels[3], "1000")


def test_log_ticks_narrow_domain_returns_the_full_1_2_5_set() raises:
    # <= 2 decades (domain [0, 1], real [1, 10]) -> the full 1/2/5*10^k
    # set within that one decade.
    var t = _log_ticks(0.0, 1.0)
    var expected: List[Float64] = [1.0, 2.0, 5.0, 10.0]
    _assert_ticks_equal(t.values, expected, "narrow log domain [0,1]")
    var labels = t.labels()
    assert_equal(labels[0], "1")
    assert_equal(labels[1], "2")
    assert_equal(labels[2], "5")
    assert_equal(labels[3], "10")


def test_log_ticks_sub_one_domain_formats_each_tick_with_its_own_decimals() raises:
    # domain [-2, 0] (real [0.01, 1]): every 1/2/5*10^k tick needs a
    # different decimal count (0.01 needs 2, 1 needs 0), which
    # Ticks.override_labels carries.
    var t = _log_ticks(-2.0, 0.0)
    var expected: List[Float64] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0]
    _assert_ticks_equal(t.values, expected, "sub-one log domain [-2,0]")
    var labels = t.labels()
    assert_equal(labels[0], "0.01")
    assert_equal(labels[1], "0.02")
    assert_equal(labels[2], "0.05")
    assert_equal(labels[3], "0.1")
    assert_equal(labels[4], "0.2")
    assert_equal(labels[5], "0.5")
    assert_equal(labels[6], "1")


def test_log_ticks_zero_span_domain_returns_a_single_real_unit_tick() raises:
    var t = _log_ticks(2.0, 2.0)
    assert_equal(len(t.values), 1)
    assert_equal(t.values[0], 100.0)
    assert_equal(t.labels()[0], "100")


def test_min_max_over_a_plain_column() raises:
    var data: List[Float64] = [3.0, -1.0, 7.5, 0.0]
    var mm = _min_max(data)
    assert_equal(mm.min, -1.0)
    assert_equal(mm.max, 7.5)


def test_min_max_raises_on_an_empty_column() raises:
    # No caller can currently reach an empty column, and a silent
    # MinMax(0, 0) would render as a degenerate axis, so this raises.
    with assert_raises():
        _ = _min_max(List[Float64]())


def test_min_max_raises_on_nan_anywhere_not_only_at_the_extremes() raises:
    # #190: NaN at index 0 used to poison lo/hi into (NaN, NaN) silently
    # (every comparison against NaN is false); NaN elsewhere used to be
    # skipped by those same comparisons and survive as a garbage
    # Int64::MIN pixel coordinate downstream. Both must now raise here,
    # the single chokepoint every domain computation passes through.
    with assert_raises():
        _ = _min_max([nan[DType.float64](), 2.0, 3.0])
    with assert_raises():
        _ = _min_max([1.0, nan[DType.float64](), 3.0])


def test_min_max_raises_on_inf() raises:
    # inf has a well-defined order, so it survives _min_max's
    # comparisons and used to produce a real-but-infinite domain no
    # tick generator could label.
    with assert_raises():
        _ = _min_max([1.0, inf[DType.float64](), 3.0])
    with assert_raises():
        _ = _min_max([1.0, 2.0, -inf[DType.float64]()])


def test_render_raises_on_nan_or_inf_in_encoded_data() raises:
    # End-to-end: a non-finite value reaching encode()/render() must
    # raise, not silently emit Int64::MIN as an SVG coordinate.
    var xs: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises():
        var plot = (
            Plot()
            .mark_point()
            .encode(x=xs, y=[1.0, nan[DType.float64](), 3.0])
            .size(200, 150)
        )
        _ = render(plot)
    with assert_raises():
        var plot = (
            Plot()
            .mark_point()
            .encode(x=xs, y=[1.0, inf[DType.float64](), 3.0])
            .size(200, 150)
        )
        _ = render(plot)


# ---------------------------------------------------------------
# from tests/test_ordinal_scale.mojo
# ---------------------------------------------------------------


def test_band_positions_match_hand_computed_values() raises:
    # domain of 3 categories, range [0, 300] (a clean multiple of 3),
    # padding 0.2 -- step = 100, bandwidth = 80 (100 * 0.8), each
    # band's left edge 10px in from its slot start (100 * 0.2/2).
    var domain: List[String] = ["a", "b", "c"]
    var s = OrdinalScale(domain^, 0.0, 300.0, padding=0.2)

    assert_equal(s.step(), 100.0)
    assert_equal(s.bandwidth(), 80.0)

    assert_equal(s.band_start(0), 10.0)
    assert_equal(s.center(0), 50.0)

    assert_equal(s.band_start(1), 110.0)
    assert_equal(s.center(1), 150.0)

    assert_equal(s.band_start(2), 210.0)
    assert_equal(s.center(2), 250.0)


def test_empty_domain_does_not_divide_by_zero() raises:
    var domain = List[String]()
    var s = OrdinalScale(domain^, 0.0, 300.0)
    assert_equal(s.step(), 0.0)
    assert_equal(s.bandwidth(), 0.0)


# ---------------------------------------------------------------
# from tests/test_color_scale.mojo
# ---------------------------------------------------------------


def test_color_scale_matches_hand_computed_values() raises:
    var s = ColorScale(0.0, 10.0)
    s.add_stop(0.0, BLACK)
    s.add_stop(1.0, WHITE)

    var lo = s.color_at(0.0)
    assert_equal(lo.r, 0)
    assert_equal(lo.g, 0)
    assert_equal(lo.b, 0)

    var hi = s.color_at(10.0)
    assert_equal(hi.r, 255)
    assert_equal(hi.g, 255)
    assert_equal(hi.b, 255)

    var mid = s.color_at(5.0)
    assert_equal(mid.r, 128)
    assert_equal(mid.g, 128)
    assert_equal(mid.b, 128)


def test_color_scale_clamps_beyond_the_domain() raises:
    var s = ColorScale(0.0, 10.0)
    s.add_stop(0.0, BLACK)
    s.add_stop(1.0, WHITE)

    var below = s.color_at(-50.0)
    assert_equal(below.r, 0)
    assert_equal(below.g, 0)
    assert_equal(below.b, 0)

    var above = s.color_at(500.0)
    assert_equal(above.r, 255)
    assert_equal(above.g, 255)
    assert_equal(above.b, 255)


def test_color_scale_zero_span_domain_returns_the_lowest_offset_stop() raises:
    # A constant-valued color column: span 0, so t is always 0.0, landing
    # on the lowest-offset stop (blue).
    var s = ColorScale(5.0, 5.0)
    s.add_stop(0.0, BLUE)
    s.add_stop(1.0, RED)

    var a = s.color_at(5.0)
    var b = s.color_at(999.0)
    assert_equal(a.r, 0)
    assert_equal(a.b, 255)
    assert_equal(b.r, 0)
    assert_equal(b.b, 255)


# ---------------------------------------------------------------
# from tests/test_colors.mojo
# ---------------------------------------------------------------


def _assert_rgb(c: Color, r: Int, g: Int, b: Int, label: String) raises:
    assert_equal(Int(c.r), r, label + ": r")
    assert_equal(Int(c.g), g, label + ": g")
    assert_equal(Int(c.b), b, label + ": b")
    assert_equal(Int(c.a), 255, label + ": a defaults fully opaque")


def test_primary_colors_match_the_css_spec() raises:
    _assert_rgb(RED, 255, 0, 0, "RED")
    _assert_rgb(
        GREEN, 0, 128, 0, "GREEN"
    )  # CSS "green", not the brighter "lime" (0,255,0)
    _assert_rgb(BLUE, 0, 0, 255, "BLUE")
    _assert_rgb(BLACK, 0, 0, 0, "BLACK")
    _assert_rgb(WHITE, 255, 255, 255, "WHITE")


def test_multiword_name_matches_the_css_spec() raises:
    _assert_rgb(CORNFLOWERBLUE, 100, 149, 237, "CORNFLOWERBLUE")


def test_gray_grey_spelling_pairs_are_identical_colors() raises:
    # CSS standardizes both spellings for these six names; both are
    # provided and must agree.
    _assert_rgb(
        GREY, Int(GRAY.r), Int(GRAY.g), Int(GRAY.b), "GREY matches GRAY"
    )
    _assert_rgb(
        DARKGREY,
        Int(DARKGRAY.r),
        Int(DARKGRAY.g),
        Int(DARKGRAY.b),
        "DARKGREY matches DARKGRAY",
    )
    _assert_rgb(
        DIMGREY,
        Int(DIMGRAY.r),
        Int(DIMGRAY.g),
        Int(DIMGRAY.b),
        "DIMGREY matches DIMGRAY",
    )
    _assert_rgb(
        LIGHTGREY,
        Int(LIGHTGRAY.r),
        Int(LIGHTGRAY.g),
        Int(LIGHTGRAY.b),
        "LIGHTGREY matches LIGHTGRAY",
    )
    _assert_rgb(
        LIGHTSLATEGREY,
        Int(LIGHTSLATEGRAY.r),
        Int(LIGHTSLATEGRAY.g),
        Int(LIGHTSLATEGRAY.b),
        "LIGHTSLATEGREY matches LIGHTSLATEGRAY",
    )
    _assert_rgb(
        SLATEGREY,
        Int(SLATEGRAY.r),
        Int(SLATEGRAY.g),
        Int(SLATEGRAY.b),
        "SLATEGREY matches SLATEGRAY",
    )


# ---------------------------------------------------------------
# from tests/test_array_like.mojo
# ---------------------------------------------------------------


struct _FloatBuffer(Copyable, Float64Sequence, Movable):
    """A minimal Float64Sequence-conforming struct standing in for a custom
    buffer wrapper or dataframe column; `List[Float64]` itself doesn't
    conform (see array_like.mojo).
    """

    var data: List[Float64]

    def __init__(out self, var data: List[Float64]):
        self.data = data^

    def __len__(self) -> Int:
        return len(self.data)

    def __getitem__(self, idx: Int) -> Float64:
        return self.data[idx]


struct _StringBuffer(Copyable, Movable, StringSequence):
    """`_FloatBuffer`'s exact counterpart for `StringSequence`."""

    var data: List[String]

    def __init__(out self, var data: List[String]):
        self.data = data^

    def __len__(self) -> Int:
        return len(self.data)

    def __getitem__(self, idx: Int) -> String:
        return self.data[idx]


def test_materialize_floats_matches_hand_derived_values() raises:
    var buf = _FloatBuffer([1.5, 2.5, 3.5])
    var out = _materialize_floats(buf)
    assert_equal(len(out), 3)
    assert_equal(out[0], 1.5)
    assert_equal(out[1], 2.5)
    assert_equal(out[2], 3.5)


def test_materialize_strings_matches_hand_derived_values() raises:
    var buf = _StringBuffer(["a", "b", "c"])
    var out = _materialize_strings(buf)
    assert_equal(len(out), 3)
    assert_equal(out[0], "a")
    assert_equal(out[1], "b")
    assert_equal(out[2], "c")


def test_encode_accepts_a_custom_float64sequence_matching_the_list_path() raises:
    # A Float64Sequence-conforming struct renders identically to the
    # List[Float64] it wraps, since encode()'s array-like overload
    # materializes it and delegates to the concrete one.
    var x_buf = _FloatBuffer([1.0, 2.0, 3.0])
    var y_buf = _FloatBuffer([10.0, 20.0, 30.0])
    var plot_from_buffer = (
        Plot().mark_point().encode(x=x_buf, y=y_buf).size(400, 300)
    )
    var svg_from_buffer = render_svg(plot_from_buffer).to_string()

    var x_list: List[Float64] = [1.0, 2.0, 3.0]
    var y_list: List[Float64] = [10.0, 20.0, 30.0]
    var plot_from_list = (
        Plot().mark_point().encode(x=x_list, y=y_list).size(400, 300)
    )
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_buffer, svg_from_list)


def test_encode_plain_list_path_is_unaffected() raises:
    # A plain List[Float64] doesn't conform to Float64Sequence, so the
    # concrete overload still resolves alongside the generic one.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [5.0, 15.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg = render_svg(plot).to_string()
    assert_equal(svg.count("<circle"), 2)


def test_encode_array_like_overload_still_enforces_length_validation() raises:
    # The array-like overload delegates to the concrete pipeline, so a
    # length mismatch is still caught.
    var x_buf = _FloatBuffer([1.0, 2.0, 3.0])
    var y_buf = _FloatBuffer([10.0, 20.0])
    with assert_raises():
        var plot = Plot().mark_point().encode(x=x_buf, y=y_buf).size(400, 300)
        _ = render_svg(plot)


def test_materialize_scalar_list_matches_hand_derived_values() raises:
    var xi: List[Int] = [1, 2, 3]
    var out_i = _materialize_scalar_list(xi)
    assert_equal(len(out_i), 3)
    assert_equal(out_i[0], 1.0)
    assert_equal(out_i[1], 2.0)
    assert_equal(out_i[2], 3.0)

    var xf32: List[Float32] = [1.5, 2.5]
    var out_f32 = _materialize_scalar_list(xf32)
    assert_equal(len(out_f32), 2)
    assert_equal(out_f32[0], 1.5)
    assert_equal(out_f32[1], 2.5)


def test_materialize_scalar_list_converts_int_exactly_up_to_2_pow_53() raises:
    # Float64 exactly represents every integer up to 2^53
    # (9007199254740992); 2^53+1 is the first that doesn't. The one limit
    # of accepting List[Int], shared with every Float64-based library.
    var exact: List[Int] = [9007199254740992]
    var out_exact = _materialize_scalar_list(exact)
    assert_equal(Int(out_exact[0]), 9007199254740992)

    var inexact: List[Int] = [9007199254740993]
    var out_inexact = _materialize_scalar_list(inexact)
    assert_equal(Int(out_inexact[0]) == 9007199254740993, False)


def test_encode_accepts_list_int_matching_the_list_float64_path() raises:
    var xi: List[Int] = [1, 2, 3]
    var yi: List[Int] = [10, 20, 30]
    var plot_from_int = Plot().mark_point().encode(x=xi, y=yi).size(400, 300)
    var svg_from_int = render_svg(plot_from_int).to_string()

    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [10.0, 20.0, 30.0]
    var plot_from_float = Plot().mark_point().encode(x=xf, y=yf).size(400, 300)
    var svg_from_float = render_svg(plot_from_float).to_string()

    assert_equal(svg_from_int, svg_from_float)


def test_encode_accepts_list_float32_matching_the_list_float64_path() raises:
    var x32: List[Float32] = [1.0, 2.0, 3.0]
    var y32: List[Float32] = [10.0, 20.0, 30.0]
    var plot_from_f32 = Plot().mark_point().encode(x=x32, y=y32).size(400, 300)
    var svg_from_f32 = render_svg(plot_from_f32).to_string()

    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [10.0, 20.0, 30.0]
    var plot_from_f64 = Plot().mark_point().encode(x=xf, y=yf).size(400, 300)
    var svg_from_f64 = render_svg(plot_from_f64).to_string()

    assert_equal(svg_from_f32, svg_from_f64)


def test_encode_categorical_accepts_list_int_y_matching_the_list_float64_path() raises:
    var cats: List[String] = ["A", "B", "C"]
    var yi: List[Int] = [10, 20, -5]
    var plot_from_int = (
        Plot().mark_bar().encode_categorical(x=cats, y=yi).size(400, 300)
    )
    var svg_from_int = render_svg(plot_from_int).to_string()

    var yf: List[Float64] = [10.0, 20.0, -5.0]
    var plot_from_float = (
        Plot().mark_bar().encode_categorical(x=cats, y=yf).size(400, 300)
    )
    var svg_from_float = render_svg(plot_from_float).to_string()

    assert_equal(svg_from_int, svg_from_float)


def test_encode_categorical_list_int_labels_display_as_whole_numbers() raises:
    # A chart built from List[Int] still shows "10"/"-5", never
    # "10.0"/"-5.0": _label_decimals decides from the value, not its
    # original type.
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Int] = [10, 20, -5]
    var plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_gridlines=False, show_data_labels=True))
        .size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    assert_equal("10</text>" in svg, True)
    assert_equal("-5</text>" in svg, True)
    assert_equal("10.0</text>" in svg, False)
    assert_equal("-5.0</text>" in svg, False)


def test_encode_categorical_accepts_a_custom_stringsequence_matching_the_list_path() raises:
    # encode_categorical()'s x can be anything conforming to
    # StringSequence, not just encode()'s x/y.
    var x_buf = _StringBuffer(["A", "B", "C"])
    var vals: List[Float64] = [10.0, 20.0, -5.0]
    var plot_from_buffer = (
        Plot().mark_bar().encode_categorical(x=x_buf, y=vals).size(400, 300)
    )
    var svg_from_buffer = render_svg(plot_from_buffer).to_string()

    var x_list: List[String] = ["A", "B", "C"]
    var plot_from_list = (
        Plot().mark_bar().encode_categorical(x=x_list, y=vals).size(400, 300)
    )
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_buffer, svg_from_list)


def test_encode_grouped_bar_accepts_a_custom_stringsequence_matching_the_list_path() raises:
    var cats_buf = _StringBuffer(["Q1", "Q2"])
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot_from_buffer = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(
            categories=cats_buf, series_names=names, values=values
        )
        .size(400, 300)
    )
    var svg_from_buffer = render_svg(plot_from_buffer).to_string()

    var cats_list: List[String] = ["Q1", "Q2"]
    var plot_from_list = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(
            categories=cats_list, series_names=names, values=values
        )
        .size(400, 300)
    )
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_buffer, svg_from_list)


# ---------------------------------------------------------------
# Property-style sweeps (#220)
#
# The scale math has crisp invariants that hold for every input, and
# the hand-picked domains elsewhere in this file only pin a handful of
# points on them. These sweep a few hundred generated domains per run
# through a fixed-seed `Lcg` (_test_helpers.mojo), so a failure repeats
# on the next run and prints the case that produced it -- which is what
# makes it liftable into a fixed regression test above.
#
# Each sweep asserts once, after the loop, rather than per case: a
# failure message naming the offending domain is worth more than
# knowing only that some case failed.
# ---------------------------------------------------------------


def _sweep_domain(mut rng: Lcg) -> Tuple[Float64, Float64]:
    """One random non-empty domain, spanning magnitudes from about
    1e-6 to 1e9 and straddling zero roughly a third of the time. The
    exponent is drawn uniformly rather than the value, so tiny and huge
    spans are sampled equally rather than the sweep spending nearly
    every case in the largest decade.
    """
    var exponent = rng.uniform(-6.0, 9.0)
    var span = pow(10.0, exponent)
    var lo = rng.uniform(-span, span) if rng.unit() < 0.33 else rng.uniform(
        0.0, span
    )
    return (lo, lo + span)


def test_sweep_linear_ticks_stay_inside_the_domain_and_are_evenly_spaced() raises:
    """`LinearScale.ticks(n)`: every tick lies inside the domain, ticks
    strictly increase, and consecutive gaps are equal.

    The gap check compares against the first gap with a relative
    tolerance: the positions are built by repeated addition, so the
    last gap can differ from the first in the low bits at large
    magnitudes without the sequence being anything but even.
    """
    var rng = Lcg(20240220)
    var failure = String("")
    var checked = 0
    for _ in range(300):
        var d = _sweep_domain(rng)
        var lo = d[0]
        var hi = d[1]
        var target = 2 + rng.below(9)
        var ticks = LinearScale(lo, hi, 0.0, 100.0).ticks(target)
        ref v = ticks.values
        checked += 1

        var span = hi - lo
        for i in range(len(v)):
            # A tolerance of one part in 1e9 of the span, not an exact
            # compare: start/stop come from ceil/floor of a division,
            # which lands a boundary tick a rounding step outside.
            if v[i] < lo - span * 1e-9 or v[i] > hi + span * 1e-9:
                failure = (
                    "tick "
                    + String(v[i])
                    + " outside domain ["
                    + String(lo)
                    + ", "
                    + String(hi)
                    + "]"
                )
                break
        if failure:
            break

        for i in range(1, len(v)):
            if v[i] <= v[i - 1]:
                failure = (
                    "ticks not strictly increasing at index "
                    + String(i)
                    + " for domain ["
                    + String(lo)
                    + ", "
                    + String(hi)
                    + "]"
                )
                break
        if failure:
            break

        if len(v) >= 3:
            var first_gap = v[1] - v[0]
            for i in range(2, len(v)):
                var gap = v[i] - v[i - 1]
                if abs(gap - first_gap) > abs(first_gap) * 1e-6:
                    failure = (
                        "uneven gap "
                        + String(gap)
                        + " vs "
                        + String(first_gap)
                        + " for domain ["
                        + String(lo)
                        + ", "
                        + String(hi)
                        + "]"
                    )
                    break
        if failure:
            break

    assert_equal(checked, 300, "every generated domain was checked")
    assert_true(failure == "", failure)


def test_sweep_linear_tick_labels_match_their_values_and_stay_distinct() raises:
    """`labels()` returns one label per tick, and no two repeat -- the
    decimal count comes from the step's exponent, so consecutive ticks
    always differ in a place the label actually shows.
    """
    var rng = Lcg(555)
    var failure = String("")
    for _ in range(200):
        var d = _sweep_domain(rng)
        var ticks = LinearScale(d[0], d[1], 0.0, 100.0).ticks(2 + rng.below(9))
        var labels = ticks.labels()
        if len(labels) != len(ticks.values):
            failure = (
                "label count "
                + String(len(labels))
                + " != tick count "
                + String(len(ticks.values))
                + " for domain ["
                + String(d[0])
                + ", "
                + String(d[1])
                + "]"
            )
            break
        for i in range(1, len(labels)):
            if labels[i] == labels[i - 1]:
                failure = (
                    "repeated label '"
                    + labels[i]
                    + "' for domain ["
                    + String(d[0])
                    + ", "
                    + String(d[1])
                    + "]"
                )
                break
        if failure:
            break
    assert_true(failure == "", failure)


def test_sweep_nice_step_is_a_1_2_or_5_times_a_power_of_ten() raises:
    """`_nice_step` returns `{1, 2, 5} * 10^k`, and its exponent is that
    `k` -- the exponent is reported separately precisely because it
    can't be recovered from the step by `log10` afterwards.
    """
    var rng = Lcg(99)
    var failure = String("")
    for _ in range(300):
        var d = _sweep_domain(rng)
        var target = 2 + rng.below(9)
        var nice = _nice_step(d[0], d[1], target)
        var mantissa = nice.step / pow(10.0, Float64(nice.exponent))
        var is_nice = (
            abs(mantissa - 1.0) < 1e-6
            or abs(mantissa - 2.0) < 1e-6
            or abs(mantissa - 5.0) < 1e-6
        )
        if not is_nice:
            failure = (
                "step "
                + String(nice.step)
                + " has mantissa "
                + String(mantissa)
                + " (exponent "
                + String(nice.exponent)
                + ") for domain ["
                + String(d[0])
                + ", "
                + String(d[1])
                + "]"
            )
            break
    assert_true(failure == "", failure)


def test_sweep_nice_step_lands_within_a_factor_of_the_requested_count() raises:
    """The step divides the span into roughly `target_count` pieces:
    rounding a raw step up to the next `{1, 2, 5}` can at most double
    it, so `span / step` stays inside [target/2.5, target*2.5].
    """
    var rng = Lcg(4242)
    var failure = String("")
    for _ in range(300):
        var d = _sweep_domain(rng)
        var target = 2 + rng.below(9)
        var nice = _nice_step(d[0], d[1], target)
        var pieces = (d[1] - d[0]) / nice.step
        if pieces < Float64(target) / 2.5 or pieces > Float64(target) * 2.5:
            failure = (
                "span/step = "
                + String(pieces)
                + " for target "
                + String(target)
                + ", domain ["
                + String(d[0])
                + ", "
                + String(d[1])
                + "]"
            )
            break
    assert_true(failure == "", failure)


def test_sweep_format_fixed_round_trips_within_half_an_ulp_of_its_last_digit() raises:
    """Parsing `_format_fixed(v, d)` back gives a value within
    `0.5 * 10^-d` of `v` -- the most the last shown digit can be off by
    if it rounded correctly -- with no doubled sign and no `-0`.
    """
    var rng = Lcg(31337)
    var failure = String("")
    for _ in range(400):
        var magnitude = pow(10.0, rng.uniform(-4.0, 8.0))
        var value = rng.uniform(-magnitude, magnitude)
        var decimals = rng.below(7)
        var text = _format_fixed(value, decimals)

        if text.startswith("--") or "-" in String(text[byte=1:]):
            failure = "doubled or misplaced sign in '" + text + "'"
            break
        if decimals == 0 and text == "-0":
            failure = (
                "negative zero from _format_fixed(" + String(value) + ", 0)"
            )
            break

        var tolerance = 0.5 * pow(10.0, -Float64(decimals))
        # The value itself carries relative error at these magnitudes,
        # so allow the greater of the digit tolerance and 1e-9 relative.
        var slack = max(tolerance, abs(value) * 1e-9)
        var parsed = Float64(text)
        if abs(parsed - value) > slack:
            failure = (
                "'"
                + text
                + "' parses to "
                + String(parsed)
                + ", off from "
                + String(value)
                + " by more than "
                + String(slack)
            )
            break
    assert_true(failure == "", failure)


def test_sweep_log_ticks_are_1_2_or_5_decade_positions_inside_the_domain() raises:
    """`_log_ticks` returns only `{1, 2, 5} * 10^k` positions, all inside
    the real-unit bounds.

    Its arguments are in log10-space (see its docstring), so the real
    bounds are `10^domain_min`/`10^domain_max` -- the sweep generates
    the exponents directly. The documented fallback for a domain too
    narrow to contain any 1/2/5 multiple returns the two real endpoints
    instead, which are not decade positions and are exempted here by the
    same test the function itself uses: exactly two values, equal to the
    bounds.
    """
    var rng = Lcg(1618)
    var failure = String("")
    for _ in range(200):
        var lo_exp = rng.uniform(-6.0, 4.0)
        var hi_exp = lo_exp + rng.uniform(0.05, 5.0)
        var lo = pow(10.0, lo_exp)
        var hi = pow(10.0, hi_exp)
        var ticks = _log_ticks(lo_exp, hi_exp)
        ref v = ticks.values

        var is_endpoint_fallback = (
            len(v) == 2
            and abs(v[0] - lo) <= abs(lo) * 1e-9
            and abs(v[1] - hi) <= abs(hi) * 1e-9
        )

        for i in range(len(v)):
            if v[i] < lo * (1.0 - 1e-9) or v[i] > hi * (1.0 + 1e-9):
                failure = (
                    "log tick "
                    + String(v[i])
                    + " outside real bounds ["
                    + String(lo)
                    + ", "
                    + String(hi)
                    + "] (exponents "
                    + String(lo_exp)
                    + ", "
                    + String(hi_exp)
                    + ")"
                )
                break
            if is_endpoint_fallback:
                continue
            var exponent = floor(log10(v[i]) + 1e-9)
            var mantissa = v[i] / pow(10.0, exponent)
            var is_nice = (
                abs(mantissa - 1.0) < 1e-6
                or abs(mantissa - 2.0) < 1e-6
                or abs(mantissa - 5.0) < 1e-6
            )
            if not is_nice:
                failure = (
                    "log tick "
                    + String(v[i])
                    + " has mantissa "
                    + String(mantissa)
                    + " (exponents "
                    + String(lo_exp)
                    + ", "
                    + String(hi_exp)
                    + ")"
                )
                break
        if failure:
            break
    assert_true(failure == "", failure)


# ---------------------------------------------------------------
# time_ticks.mojo -- calendar-aware ticks (#195)
# ---------------------------------------------------------------


def _days(year: Int, month: Int, day: Int) raises -> Float64:
    return Float64(_days_from_civil(_Date(year, month, day)))


def test_civil_from_days_round_trips_every_date_across_three_decades() raises:
    # _civil_from_days is the inverse of the _days_from_civil that
    # calendar_heatmap already ships, so the pair is checkable against
    # itself: every day from 2000 through 2031, leap days included, must
    # survive the trip out and back unchanged.
    var start = _days_from_civil(_Date(2000, 1, 1))
    var end = _days_from_civil(_Date(2031, 12, 31))
    var failure = String("")
    for d in range(start, end + 1):
        var date = _civil_from_days(d)
        if _days_from_civil(date) != d:
            failure = (
                "day "
                + String(d)
                + " -> "
                + String(date.year)
                + "-"
                + String(date.month)
                + "-"
                + String(date.day)
                + " -> "
                + String(_days_from_civil(date))
            )
            break
    assert_true(failure == "", failure)


def test_civil_from_days_round_trips_before_the_epoch() raises:
    # The era arithmetic branches on the sign of the shifted day count,
    # so dates before 1970 exercise a path 2000-2031 never reaches.
    var start = _days_from_civil(_Date(1899, 1, 1))
    var end = _days_from_civil(_Date(1905, 12, 31))
    for d in range(start, end + 1):
        assert_equal(_days_from_civil(_civil_from_days(d)), d)


def test_leap_years_follow_the_century_rule() raises:
    assert_true(_is_leap(2024), "2024 divisible by 4")
    assert_true(not _is_leap(2023), "2023 not divisible by 4")
    assert_true(not _is_leap(2100), "2100 divisible by 100, not by 400")
    assert_true(_is_leap(2000), "2000 divisible by 400")
    assert_equal(_days_in_month(2024, 2), 29)
    assert_equal(_days_in_month(2023, 2), 28)
    assert_equal(_days_in_month(2023, 4), 30)
    assert_equal(_days_in_month(2023, 12), 31)


def test_six_months_of_daily_data_reads_as_month_names() raises:
    # The motivating case on #195: a half-year domain should read
    # Jan/Feb/Mar, not a run of raw epoch day counts.
    var t = _time_ticks(_days(2026, 1, 1), _days(2026, 6, 1))
    var labels = t.labels()
    assert_equal(len(labels), 6)
    assert_equal(labels[0], "Jan 2026")
    assert_equal(labels[1], "Feb")
    assert_equal(labels[2], "Mar")
    assert_equal(labels[3], "Apr")
    assert_equal(labels[4], "May")
    assert_equal(labels[5], "Jun")


def test_the_year_is_repeated_only_where_it_changes() raises:
    # A monthly axis crossing New Year marks the new year once, on the
    # January tick, rather than appending "2027" to all twelve.
    var t = _time_ticks(_days(2026, 11, 1), _days(2027, 4, 1))
    var labels = t.labels()
    assert_equal(labels[0], "Nov 2026")
    assert_equal(labels[1], "Dec")
    assert_equal(labels[2], "Jan 2027")
    assert_equal(labels[3], "Feb")


def test_a_multi_year_span_reads_as_bare_years() raises:
    var t = _time_ticks(_days(1990, 1, 1), _days(2030, 1, 1))
    var labels = t.labels()
    assert_equal(len(labels), 5)
    assert_equal(labels[0], "1990")
    assert_equal(labels[4], "2030")


def test_quarterly_ticks_snap_to_calendar_quarters() raises:
    # The domain starts on 17 February; the ticks must still land on
    # Jan/Apr/Jul/Oct rather than inheriting the data's start day.
    var t = _time_ticks(_days(2024, 2, 17), _days(2025, 5, 20))
    var labels = t.labels()
    assert_equal(len(labels), 5)
    for i in range(len(t.values)):
        var d = _civil_from_days(Int(t.values[i]))
        assert_equal(d.day, 1)
        assert_true(
            d.month == 1 or d.month == 4 or d.month == 7 or d.month == 10,
            "quarter tick on month " + String(d.month) + ": " + labels[i],
        )
    assert_equal(labels[0], "Apr 2024")


def test_advancing_a_month_from_the_31st_lands_on_a_real_date() raises:
    # The reason ticks are walked rather than computed: 31 Jan + "one
    # month" is 28 Feb on the calendar and 3 March in fixed days.
    var jan31 = _days_from_civil(_Date(2023, 1, 31))
    var next = _civil_from_days(_advance(jan31, _TimeStep(_TimeUnit.MONTH, 1)))
    assert_equal(next.year, 2023)
    assert_equal(next.month, 2)
    assert_equal(next.day, 28)

    var leap = _civil_from_days(
        _advance(
            _days_from_civil(_Date(2024, 1, 31)), _TimeStep(_TimeUnit.MONTH, 1)
        )
    )
    assert_equal(leap.day, 29)

    # And a leap day advanced by a year clamps to 28 February.
    var feb29 = _civil_from_days(
        _advance(
            _days_from_civil(_Date(2024, 2, 29)), _TimeStep(_TimeUnit.YEAR, 1)
        )
    )
    assert_equal(feb29.year, 2025)
    assert_equal(feb29.month, 2)
    assert_equal(feb29.day, 28)


def test_a_five_month_span_picks_months_not_fortnights() raises:
    # 4.96 months: the nearest rung, not the coarsest rung clearing the
    # target. Picking "at least 5 ticks" would drop to fortnightly and
    # print eleven labels.
    var step = _pick_step(151.0, 5)
    assert_true(step.unit == _TimeUnit.MONTH, "unit")
    assert_equal(step.count, 1)


def test_zero_span_domain_returns_one_dated_tick() raises:
    var t = _time_ticks(_days(2026, 3, 4), _days(2026, 3, 4))
    assert_equal(len(t.values), 1)
    assert_equal(t.labels()[0], "4 Mar 2026")


def test_sweep_time_ticks_stay_inside_the_domain_and_ascend() raises:
    # Random domains from 3 days to ~80 years, against every rung: ticks
    # must be strictly increasing, lie within the domain, carry one label
    # each, and land near the requested count.
    var rng = Lcg(20260905)
    var failure = String("")
    for _ in range(400):
        var start = _days_from_civil(_Date(1975, 1, 1)) + Int(rng.below(20000))
        var span = 3 + Int(rng.below(29000))
        var target = 3 + Int(rng.below(8))
        var lo = Float64(start)
        var hi = Float64(start + span)
        var t = _time_ticks(lo, hi, target)
        var labels = t.labels()
        if len(labels) != len(t.values):
            failure = "label count differs from tick count"
            break
        if len(t.values) == 0:
            failure = "no ticks for span " + String(span)
            break
        for i in range(len(t.values)):
            if t.values[i] < lo or t.values[i] > hi:
                failure = (
                    "tick "
                    + String(t.values[i])
                    + " outside ["
                    + String(lo)
                    + ", "
                    + String(hi)
                    + "]"
                )
                break
            if i > 0 and t.values[i] <= t.values[i - 1]:
                failure = "ticks not strictly increasing at " + String(i)
                break
            if not labels[i]:
                failure = "empty label at " + String(i)
                break
        if failure:
            break
        # The ladder is spaced ~2-3x, so the worst a domain landing
        # between rungs can do is roughly double or halve the target.
        if len(t.values) > 3 * target or Float64(len(t.values)) < 0.4 * Float64(
            target
        ):
            failure = (
                "span "
                + String(span)
                + " days, target "
                + String(target)
                + " -> "
                + String(len(t.values))
                + " ticks"
            )
            break
    assert_true(failure == "", failure)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
