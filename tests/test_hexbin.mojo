"""Tests for `Mark.HEXBIN` / `hexbin()`: the lattice and its binning
rule derived by hand, empty cells as background, and the overloads."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

from _test_helpers import _assert_same_canvas, _count_color, _count_tag
from canvas.color import Color
from dataviz.hexbin import _HexBins, _hexbin_bins, hexbin
from dataviz.plot import render, render_svg
from dataviz.core.theme import Theme


comptime _LO = Color(0, 0, 255)
comptime _HI = Color(255, 0, 0)
comptime _BG = Color(0, 255, 0)


def _theme() -> Theme:
    var stops: List[Color] = [_LO, _HI]
    return Theme(
        background=_BG,
        color_ramp=stops,
        show_gridlines=False,
        show_legend=False,
    )


def _cell(b: _HexBins, cx: Float64, cy: Float64) -> Int:
    """The count at center `(cx, cy)`, or -1 when no such cell."""
    for i in range(len(b.count)):
        if b.cx[i] == cx and b.cy[i] == cy:
            return b.count[i]
    return -1


def test_lattice_and_binning_are_hand_derived() raises:
    # gridsize 2 over the box [0, 4] x [0, 4]: nx = 2, ny = floor(2 /
    # sqrt 3) = 1, so sx = 2 and sy = 4. Lattice 1 centers are x in
    # {0, 2, 4} by y in {0, 4}; the offset lattice's are (1, 2) and
    # (3, 2). Each point below is nearer one specific center.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 2.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0, 2.0, 2.0]
    var b = _hexbin_bins(x, y, 2)
    assert_equal(b.sx, 2.0)
    assert_equal(b.sy, 4.0)
    assert_equal(len(b.count), 5, "five cells are nonempty")
    assert_equal(_cell(b, 0.0, 0.0), 1, "(0, 0) is its own center")
    # (1, 0) is 0.5 lattice units from (2, 0) and, in the weighted
    # distance, 0.75 from the offset center (1, 2): it goes to (2, 0),
    # as does (2, 0) itself.
    assert_equal(_cell(b, 2.0, 0.0), 2)
    assert_equal(_cell(b, 4.0, 0.0), 1, "(3, 0) rounds to (4, 0)")
    assert_equal(_cell(b, 4.0, 4.0), 1, "the box corner is a center")
    # (2, 2) is half a row above (2, 0) -- weighted distance 0.75 --
    # and a quarter row from the offset center (3, 2) at 0.25: offset
    # lattice, both copies.
    assert_equal(_cell(b, 3.0, 2.0), 2)
    assert_equal(_cell(b, 1.0, 2.0), -1, "nothing landed at (1, 2)")


def test_a_point_equidistant_from_both_lattices_goes_to_the_offset_one() raises:
    # Same box as above. (1.5, 1.0) is lattice units (0.75, 0.25):
    # weighted distance 0.25 to lattice-1 center (2, 0) and 0.25 to the
    # offset center (1, 2). The tie is resolved toward the offset
    # lattice, and pinned here because this is where implementations
    # quietly differ.
    var x: List[Float64] = [0.0, 4.0, 1.5]
    var y: List[Float64] = [0.0, 4.0, 1.0]
    var b = _hexbin_bins(x, y, 2)
    assert_equal(_cell(b, 1.0, 2.0), 1, "the tie goes to the offset cell")
    assert_equal(_cell(b, 2.0, 0.0), -1)


def test_every_point_lands_in_exactly_one_cell() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(1000):
        x.append(Float64((i * 37) % 101) / 7.0)
        y.append(Float64((i * 53) % 97) / 3.0)
    var b = _hexbin_bins(x, y, 13)
    var total = 0
    for c in b.count:
        assert_true(c > 0, "only nonempty cells are returned")
        total += c
    assert_equal(total, 1000)


def test_empty_cells_show_the_background_and_full_ones_the_ramp_top() raises:
    # Two clusters far apart: the cells between them are empty and
    # must be background, not the ramp's bottom color (blue).
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(50):
        x.append(0.0 + Float64(i % 5) * 0.01)
        y.append(0.0 + Float64(i % 7) * 0.01)
        x.append(10.0 + Float64(i % 5) * 0.01)
        y.append(10.0 + Float64(i % 7) * 0.01)
    var c = render(
        hexbin(x, y, gridsize=10, theme=_theme(), width=300, height=220)
    )
    assert_true(_count_color(c, _HI) > 50, "the two full cells are red")
    assert_equal(
        _count_color(c, _LO),
        0,
        "no cell is painted the ramp's bottom color -- empty is background",
    )
    # The middle of the chart, between the clusters, is background.
    var mid = c.get_pixel(c.width // 2, c.height // 2)
    assert_true(
        mid.r == _BG.r and mid.g == _BG.g and mid.b == _BG.b,
        "the gap between clusters is background",
    )


def test_svg_fills_one_path_per_distinct_count() raises:
    # Counts 1, 2 and 2 from the hand-derived set: cells with equal
    # counts share one filled path, so two fills (plus their two
    # face-colored strokes).
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 2.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0, 2.0, 2.0]
    var s = render_svg(
        hexbin(x, y, gridsize=2, theme=_theme(), width=300, height=220)
    ).to_string()
    assert_equal(_count_tag(s, "path"), 4)


def test_dtype_overload_renders_identically() raises:
    var xf: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 2.0]
    var yf: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0, 2.0, 2.0]
    var xi: List[Int32] = [0, 1, 2, 3, 4, 2, 2]
    var yi: List[Int32] = [0, 0, 0, 0, 4, 2, 2]
    _assert_same_canvas(
        render(hexbin(xf, yf, gridsize=2, width=200, height=150)),
        render(hexbin(xi, yi, gridsize=2, width=200, height=150)),
        "Int32 hexbin matches Float64",
    )


def test_hexbin_raises_with_names() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="same length"):
        _ = render(hexbin(x, y))
    with assert_raises(contains="gridsize must be at least 1"):
        _ = render(hexbin(x, x, gridsize=0))
    with assert_raises(contains="no points"):
        _ = render(hexbin(List[Float64](), List[Float64]()))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
