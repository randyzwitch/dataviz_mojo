"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_scale.mojo`: Tests for scale.mojo: LinearScale.to_pixel/scale/translate, and the
  nice-tick algorithm -- every expected value here was independently
  computed by hand (see scale.mojo's module docstring) before
  trusting the Mojo implementation.

- `test_ordinal_scale.mojo`: Tests for ordinal_scale.mojo: OrdinalScale's band math, hand-
  computed independently.

- `test_color_scale.mojo`: Tests for color_scale.mojo: ColorScale.color_at -- shares its
  interpolation math with canvas.gradient's LinearGradient/
  RadialGradient (already exhaustively tested there), so these focus on
  what's specific to ColorScale: projecting a data domain (not a pixel
  position) onto [0, 1], and the zero-span-domain degenerate case.
  Expected values independently computed by hand (same
  white-on-black-gives-the-coverage-fraction-directly technique
  canvas_mojo/tests/test_gradient.mojo's tests use).

- `test_colors.mojo`: Tests for colors.mojo -- spot checks against the actual CSS Color
  Module Level 3 spec (<https://www.w3.org/TR/css-color-3/#svg-color>),
  not just re-reading colors.mojo's values back at itself: the three
  additive primaries, a representative multi-word name, that both
  spellings CSS itself standardizes for six names resolve to the
  identical color, and that a named constant works exactly like any
  other `Color` literal through a real render (see the "why comptime,
  not a lookup" paragraph in colors.mojo's docstring -- this is what
  that buys: no separate integration path to test, just Theme.mark_color
  fed a different value).

- `test_array_like.mojo`: Tests for `Float64Sequence`/`StringSequence` (array_like.mojo) and
  `Plot.encode()`'s array-like `x`/`y` overload: `_materialize_floats`/
  `_materialize_strings` copy a conforming custom type into a real
  `List[Float64]`/`List[String]` correctly, a custom `Float64Sequence`
  struct renders byte-for-byte identically to the equivalent plain
  `List[Float64]` through `Plot.encode()`, the plain-`List` path itself
  is unaffected, and the array-like overload still enforces the same
  length validation the concrete one does (since it delegates to it).
  
  Also covers the independent `DType`-generic axis (`_materialize_
  scalar_list`, `encode()`/`encode_categorical()`'s numeric-element-type
  overloads): `List[Int]`/`List[Float32]` render byte-for-byte
  identically to the equivalent `List[Float64]`, integer values convert
  losslessly up to the real `Int`-to-`Float64` exact-precision boundary
  (2^53 -- confirmed empirically while building this, not assumed), and
  a chart built from `List[Int]` still displays whole-number labels as
  `"10"`, never `"10.0"` (`_label_decimals` decides digit count from the
  value itself, not from whatever type it started out as).
  
  Also covers `StringSequence`'s own container axis on the categorical
  side -- `encode_categorical()`'s `x` and `encode_grouped_bar()`'s
  `categories`, not just `encode()`'s `x`/`y` -- rendering byte-for-byte
  identically to the equivalent `List[String]`.

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


# ---------------------------------------------------------------
# from tests/test_scale.mojo
# ---------------------------------------------------------------

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
    # A constant-valued color column -- span is 0, so t is always 0.0
    # regardless of the actual data value, landing on the lowest-
    # offset stop's color (blue here), not a crash from dividing by
    # the zero span.
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
    _assert_rgb(GREEN, 0, 128, 0, "GREEN")  # CSS "green", not the brighter "lime" (0,255,0)
    _assert_rgb(BLUE, 0, 0, 255, "BLUE")
    _assert_rgb(BLACK, 0, 0, 0, "BLACK")
    _assert_rgb(WHITE, 255, 255, 255, "WHITE")


def test_multiword_name_matches_the_css_spec() raises:
    _assert_rgb(CORNFLOWERBLUE, 100, 149, 237, "CORNFLOWERBLUE")


def test_gray_grey_spelling_pairs_are_identical_colors() raises:
    # CSS standardizes both spellings for these six names -- picking
    # one and dropping the other would just be a different, equally
    # arbitrary standard (see colors.mojo's docstring), so both
    # are provided, and must actually agree with each other.
    _assert_rgb(GREY, Int(GRAY.r), Int(GRAY.g), Int(GRAY.b), "GREY matches GRAY")
    _assert_rgb(DARKGREY, Int(DARKGRAY.r), Int(DARKGRAY.g), Int(DARKGRAY.b), "DARKGREY matches DARKGRAY")
    _assert_rgb(DIMGREY, Int(DIMGRAY.r), Int(DIMGRAY.g), Int(DIMGRAY.b), "DIMGREY matches DIMGRAY")
    _assert_rgb(LIGHTGREY, Int(LIGHTGRAY.r), Int(LIGHTGRAY.g), Int(LIGHTGRAY.b), "LIGHTGREY matches LIGHTGRAY")
    _assert_rgb(
        LIGHTSLATEGREY,
        Int(LIGHTSLATEGRAY.r),
        Int(LIGHTSLATEGRAY.g),
        Int(LIGHTSLATEGRAY.b),
        "LIGHTSLATEGREY matches LIGHTSLATEGRAY",
    )
    _assert_rgb(SLATEGREY, Int(SLATEGRAY.r), Int(SLATEGRAY.g), Int(SLATEGRAY.b), "SLATEGREY matches SLATEGRAY")


def test_named_color_works_as_a_theme_mark_color_through_a_real_render() raises:
    # A real render, not just reading the constant back -- confirms a
    # named color reaches the renderer exactly like any other Color
    # literal, with no separate integration path (see
    # colors.mojo's "why comptime, not a lookup" paragraph). A
    # plain non-zero count, not a specific hand-derived pixel -- bar()
    # layout itself is already exhaustively covered in test_bar.mojo;
    # all this needs to prove is that the fill color a caller asked
    # for is the fill color that actually landed on the canvas.
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [3.0, 5.0]
    var _hoisted1 = bar(cats, values, theme=Theme(mark_color=CORNFLOWERBLUE))
    var c = render(_hoisted1)

    assert_equal(_count_color(c, CORNFLOWERBLUE) > 0, True, "bar filled with a named color renders that exact color")

# ---------------------------------------------------------------
# from tests/test_array_like.mojo
# ---------------------------------------------------------------

struct _FloatBuffer(Float64Sequence, Copyable, Movable):
    """A minimal `Float64Sequence`-conforming struct, standing in for
    a future dataframe column type or a custom buffer wrapper -- see
    array_like.mojo's own docstring for why this can't just be
    `List[Float64]` itself (nominal trait conformance, confirmed
    empirically while building this: `List` has the same `__len__`/
    `__getitem__` shape but doesn't conform without being declared to).
    """

    var data: List[Float64]

    def __init__(out self, var data: List[Float64]):
        self.data = data^

    def __len__(self) -> Int:
        return len(self.data)

    def __getitem__(self, idx: Int) -> Float64:
        return self.data[idx]


struct _StringBuffer(StringSequence, Copyable, Movable):
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
    # The point of this feature: a Float64Sequence-conforming struct
    # renders identically to the plain List[Float64] it wraps --
    # Plot.encode()'s array-like overload materializes it into a real
    # List once, then delegates entirely to the concrete overload (see
    # that method's own docstring), so there should be no observable
    # difference in the rendered SVG at all.
    var x_buf = _FloatBuffer([1.0, 2.0, 3.0])
    var y_buf = _FloatBuffer([10.0, 20.0, 30.0])
    var plot_from_buffer = Plot().mark_point().encode(x=x_buf, y=y_buf).size(400, 300)
    var svg_from_buffer = render_svg(plot_from_buffer).to_string()

    var x_list: List[Float64] = [1.0, 2.0, 3.0]
    var y_list: List[Float64] = [10.0, 20.0, 30.0]
    var plot_from_list = Plot().mark_point().encode(x=x_list, y=y_list).size(400, 300)
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_buffer, svg_from_list)


def test_encode_plain_list_path_is_unaffected() raises:
    # A plain List[Float64] doesn't conform to Float64Sequence (see
    # array_like.mojo's own docstring) -- this proves the original
    # concrete overload still resolves and renders correctly with the
    # new generic overload sitting alongside it.
    var x: List[Float64] = [1.0, 2.0]
    var y: List[Float64] = [5.0, 15.0]
    var plot = Plot().mark_point().encode(x=x, y=y).size(400, 300)
    var svg = render_svg(plot).to_string()
    assert_equal(svg.count("<circle"), 2)


def test_encode_array_like_overload_still_enforces_length_validation() raises:
    # Delegates to the concrete encode()/render() pipeline unchanged,
    # so a length mismatch is still caught the same way -- proving
    # this overload didn't silently bypass any of encode()'s existing
    # validation.
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
    # (9007199254740992); 2^53+1 is the first value that doesn't --
    # confirmed empirically (python3-cross-checked IEEE 754 double
    # precision), not assumed from a general "floats can be
    # imprecise" impression. This is the one real, documented limit
    # of accepting List[Int] directly -- shared with every other
    # Float64-based charting library, not introduced by this
    # conversion.
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
    var plot_from_int = Plot().mark_bar().encode_categorical(x=cats, y=yi).size(400, 300)
    var svg_from_int = render_svg(plot_from_int).to_string()

    var yf: List[Float64] = [10.0, 20.0, -5.0]
    var plot_from_float = Plot().mark_bar().encode_categorical(x=cats, y=yf).size(400, 300)
    var svg_from_float = render_svg(plot_from_float).to_string()

    assert_equal(svg_from_int, svg_from_float)


def test_encode_categorical_list_int_labels_display_as_whole_numbers() raises:
    # The label-display concern this feature has to get right: a
    # chart built from List[Int] still shows "10"/"-5", never
    # "10.0"/"-5.0" -- _label_decimals decides digit count from the
    # value itself (post-conversion Float64), not from whatever type
    # it started out as, so this was already true before this feature
    # and stays true now; verified directly rather than assumed.
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Int] = [10, 20, -5]
    var plot = Plot().mark_bar().encode_categorical(x=cats, y=vals).theme(
        Theme(show_gridlines=False, show_data_labels=True)
    ).size(400, 300)
    var svg = render_svg(plot).to_string()
    assert_equal("10</text>" in svg, True)
    assert_equal("-5</text>" in svg, True)
    assert_equal("10.0</text>" in svg, False)
    assert_equal("-5.0</text>" in svg, False)


def test_encode_categorical_accepts_a_custom_stringsequence_matching_the_list_path() raises:
    # The container axis's counterpart on the categorical side --
    # encode_categorical()'s x, not just encode()'s x/y, can be
    # anything conforming to StringSequence.
    var x_buf = _StringBuffer(["A", "B", "C"])
    var vals: List[Float64] = [10.0, 20.0, -5.0]
    var plot_from_buffer = Plot().mark_bar().encode_categorical(x=x_buf, y=vals).size(400, 300)
    var svg_from_buffer = render_svg(plot_from_buffer).to_string()

    var x_list: List[String] = ["A", "B", "C"]
    var plot_from_list = Plot().mark_bar().encode_categorical(x=x_list, y=vals).size(400, 300)
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_buffer, svg_from_list)


def test_encode_grouped_bar_accepts_a_custom_stringsequence_matching_the_list_path() raises:
    var cats_buf = _StringBuffer(["Q1", "Q2"])
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var plot_from_buffer = Plot().mark_grouped_bar().encode_grouped_bar(
        categories=cats_buf, series_names=names, values=values
    ).size(400, 300)
    var svg_from_buffer = render_svg(plot_from_buffer).to_string()

    var cats_list: List[String] = ["Q1", "Q2"]
    var plot_from_list = Plot().mark_grouped_bar().encode_grouped_bar(
        categories=cats_list, series_names=names, values=values
    ).size(400, 300)
    var svg_from_list = render_svg(plot_from_list).to_string()

    assert_equal(svg_from_buffer, svg_from_list)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
