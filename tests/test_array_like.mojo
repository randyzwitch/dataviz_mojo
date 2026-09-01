"""Tests for `Float64Sequence`/`StringSequence` (array_like.mojo) and
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
"""

from std.testing import assert_equal, assert_raises, TestSuite

from dataviz_mojo.array_like import (
    Float64Sequence,
    StringSequence,
    _materialize_floats,
    _materialize_scalar_list,
    _materialize_strings,
)
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
