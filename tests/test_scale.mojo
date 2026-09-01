"""Tests for scale.mojo: LinearScale.to_pixel/scale/translate, and the
nice-tick algorithm -- every expected value here was independently
computed by hand (see scale.mojo's module docstring) before
trusting the Mojo implementation.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from dataviz.scale import LinearScale, Ticks, _format_fixed, _label_decimals, _log_ticks, _min_max, _nice_step


def _assert_ticks_equal(actual: List[Float64], expected: List[Float64], label: String) raises:
    assert_equal(len(actual), len(expected), label)
    for i in range(len(expected)):
        assert_true(
            actual[i] > expected[i] - 1e-9 and actual[i] < expected[i] + 1e-9, label
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
    # 0.0 + 3*0.1 is 0.30000000000000004 as a raw Float64 -- see
    # _format_fixed's docstring for why raw String(Float64) is unsafe
    # for tick labels. String(Float64) alone would print that garbage
    # directly; _format_fixed must not.
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
    # The same 0.30000000000000004-class drift test_format_fixed_
    # avoids_binary_floating_point_drift already covers -- a value
    # that's "really" 0.3 (to any human reading it) must not need 15+
    # decimals just because its raw Float64 bits aren't exact.
    var drifted = 0.0 + 3.0 * 0.1
    assert_equal(_label_decimals(drifted), 1)


def test_ticks_labels_uses_format_fixed_per_tick() raises:
    var s = LinearScale(0.0, 0.01, 0.0, 600.0)
    var t = s.ticks(5)
    var labels = t.labels()
    assert_equal(labels[0], "0.000")
    assert_equal(labels[1], "0.002")
    assert_equal(labels[len(labels) - 1], "0.010")


def test_log_scale_to_pixel_matches_hand_derived_positions() raises:
    # domain [0, 3] (log10-space, i.e. real [1, 1000]) -> range
    # [400, 0]: scale() = (0-400)/(3-0) = -133.333..., translate() =
    # 400 - 0*scale() = 400. to_pixel(v) = log10(v)*scale() +
    # translate() -- every value below independently computed by hand.
    var s = LinearScale(0.0, 3.0, 400.0, 0.0, is_log=True)
    assert_equal(s.to_pixel(1.0), 400.0)
    assert_equal(s.to_pixel(10.0), 266.66666666666663)
    assert_equal(s.to_pixel(100.0), 133.33333333333331)
    assert_equal(s.to_pixel(1000.0), 0.0)


def test_log_ticks_wide_domain_returns_major_ticks_only() raises:
    # > 2 decades (domain [0, 3], real [1, 1000]) -> 1*10^k only, no
    # 2*10^k/5*10^k sub-ticks (the standard log-axis convention for a
    # wide range -- see _log_ticks's own docstring).
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
    # domain [-2, 0] (real [0.01, 1]) -- every 1/2/5*10^k tick needs a
    # *different* decimal count (0.01 needs 2 places, 1 needs 0),
    # exactly what Ticks.override_labels exists for (one shared
    # `decimals` can't express this).
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
    # No caller can currently reach an empty column (every render path
    # returns early on empty data first), so this
    # raises rather than inventing a fallback: a silent MinMax(0, 0)
    # would hand back a degenerate domain that still renders as a real
    # axis, which is the "silently misrepresent the data" failure this
    # package's encode/render checks exist to prevent.
    with assert_raises():
        _ = _min_max(List[Float64]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
