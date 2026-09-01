"""Tests for `Float64Sequence`/`StringSequence` (array_like.mojo) and
`Plot.encode()`'s array-like `x`/`y` overload: `_materialize_floats`/
`_materialize_strings` copy a conforming custom type into a real
`List[Float64]`/`List[String]` correctly, a custom `Float64Sequence`
struct renders byte-for-byte identically to the equivalent plain
`List[Float64]` through `Plot.encode()`, the plain-`List` path itself
is unaffected, and the array-like overload still enforces the same
length validation the concrete one does (since it delegates to it).
"""

from std.testing import assert_equal, assert_raises, TestSuite

from dataviz_mojo.array_like import Float64Sequence, StringSequence, _materialize_floats, _materialize_strings
from dataviz_mojo.plot import Plot, render_svg


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
