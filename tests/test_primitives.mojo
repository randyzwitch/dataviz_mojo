"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers scale.mojo (LinearScale, the
nice-tick algorithm, _format_fixed, _label_decimals, log ticks),
ordinal_scale.mojo, color_scale.mojo (domain projection and the
zero-span case; interpolation itself is tested in canvas.gradient),
colors.mojo (spot checks against the CSS spec, the gray/grey pairs, a
named color through a real render), and array_like.mojo
(Float64Sequence/StringSequence, the DType-generic overloads, exact
Int conversion up to 2^53, whole-number labels from List[Int]).
"""

from _test_helpers import _count_color
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
from dataviz.color_scale import ColorScale
from dataviz.colors import BLACK, BLUE, RED, WHITE
from dataviz.ordinal_scale import OrdinalScale
from dataviz.plot import Plot, render, render_svg
from dataviz.scale import (
    LinearScale,
    Ticks,
    _format_fixed,
    _label_decimals,
    _log_ticks,
    _min_max,
    _nice_step,
)
from dataviz.theme import Theme
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


def test_named_color_works_as_a_theme_mark_color_through_a_real_render() raises:
    # A named color reaches the renderer like any other Color literal. A
    # non-zero count rather than a hand-derived pixel; bar() layout is
    # covered in its own tests.
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [3.0, 5.0]
    var _hoisted1 = bar(cats, values, theme=Theme(mark_color=CORNFLOWERBLUE))
    var c = render(_hoisted1)

    assert_equal(
        _count_color(c, CORNFLOWERBLUE) > 0,
        True,
        "bar filled with a named color renders that exact color",
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
