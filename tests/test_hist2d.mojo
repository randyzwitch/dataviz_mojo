"""Tests for `Mark.HIST2D` / `hist2d()`: hand-derived counts, the
boundary rule, empty bins drawn as background, and the overloads."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

from _test_helpers import _assert_same_canvas, _bbox_of_color, _count_tag
from canvas.color import Color
from dataviz.hist2d import _hist2d_counts, hist2d
from dataviz.histogram import BinRule, bin_edges
from dataviz.plot import Plot, render, render_svg
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


def _is(p: Color, c: Color) -> Bool:
    return p.r == c.r and p.g == c.g and p.b == c.b


def test_counts_are_hand_derived_with_the_boundary_rule() raises:
    # x edges [0, 2, 4], y edges [0, 2, 4]. x=2 sits on the shared
    # boundary and goes to the upper bin; (4, 4) is the maximum on both
    # axes and goes to the last bin, not past it.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var ex: List[Float64] = [0.0, 2.0, 4.0]
    var ey: List[Float64] = [0.0, 2.0, 4.0]
    var counts = _hist2d_counts(x, y, ex, ey)
    assert_equal(len(counts), 2)
    assert_equal(len(counts[0]), 2)
    # Row 0 is the bottom band of y: x in [0, 2) holds 0 and 1; x in
    # [2, 4] holds 2 and 3.
    assert_equal(counts[0][0], 2.0)
    assert_equal(counts[0][1], 2.0)
    # Row 1: only (4, 4), in the last column.
    assert_equal(counts[1][0], 0.0)
    assert_equal(counts[1][1], 1.0)


def test_points_outside_the_edges_are_not_counted() raises:
    var x: List[Float64] = [-1.0, 0.5, 9.0, 0.5]
    var y: List[Float64] = [0.5, 0.5, 0.5, 7.0]
    var e: List[Float64] = [0.0, 1.0]
    var counts = _hist2d_counts(x, y, e, e)
    assert_equal(counts[0][0], 1.0, "only (0.5, 0.5) is inside the one cell")


def test_hist2d_bins_each_axis_over_its_own_range() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [10.0, 10.0, 10.0, 10.0, 30.0]
    var p = hist2d(x, y, bins=2)
    assert_equal(len(p._image.x_edges), 3)
    assert_equal(p._image.x_edges[1], 2.0)
    assert_equal(p._image.y_edges[1], 20.0)
    assert_equal(p._image.z[0][0], 2.0)
    assert_equal(p._image.z[1][1], 1.0)
    assert_true(p._image.blank_zero, "empty bins are left undrawn")


def test_empty_bins_draw_as_background_not_the_bottom_of_the_ramp() raises:
    # Counts [[2, 2], [0, 1]]: the bottom row is full (both cells at the
    # ramp's top, red), the top-left cell is empty and the top-right
    # holds one point. The red band's bounding box locates the plot
    # rect: it is the bottom half.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var c = render(hist2d(x, y, bins=2, theme=_theme(), width=300, height=220))
    var red = _bbox_of_color(c, _HI)
    assert_true(red.found, "the full cells are the top of the ramp")
    var w = red.x1 - red.x0 + 1
    var h = red.y1 - red.y0 + 1
    assert_true(w > 100 and h > 40, "red band is the bottom half of the rect")
    # Center of the top-left cell: background.
    var tl = c.get_pixel(red.x0 + w // 4, red.y0 - h // 2)
    assert_true(_is(tl, _BG), "an empty bin shows the background")
    # Center of the top-right cell: a ramp color that is neither
    # background nor the top of the ramp -- one point of a maximum of
    # two.
    var tr = c.get_pixel(red.x0 + (3 * w) // 4, red.y0 - h // 2)
    assert_true(
        not _is(tr, _BG) and not _is(tr, _HI) and tr.g == 0,
        "a one-count bin is colored between the ramp's ends",
    )


def test_svg_draws_one_rect_per_nonempty_bin() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var s = render_svg(
        hist2d(x, y, bins=2, theme=_theme(), width=300, height=220)
    ).to_string()
    # The two red cells of the bottom row merge into one run; the
    # one-count cell is its own; the empty cell is nothing. Plus the
    # background rect.
    assert_equal(_count_tag(s, "rect"), 3)


def test_rule_overload_bins_each_axis_by_the_rule() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(200):
        x.append(Float64(i))
        y.append(Float64((i * 37) % 101))
    var p = hist2d(x, y)
    var ex = bin_edges(x, BinRule.AUTO)
    var ey = bin_edges(y, BinRule.AUTO)
    assert_equal(len(p._image.x_edges), len(ex))
    assert_equal(len(p._image.y_edges), len(ey))
    assert_equal(p._image.x_edges[1], ex[1])
    assert_equal(p._image.y_edges[1], ey[1])
    var total = 0.0
    for r in range(len(p._image.z)):
        for c in range(len(p._image.z[r])):
            total += p._image.z[r][c]
    assert_equal(total, 200.0, "every point lands in exactly one bin")


def test_dtype_overload_renders_identically() raises:
    var xf: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var yf: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var xi: List[Int32] = [0, 1, 2, 3, 4]
    var yi: List[Int32] = [0, 0, 0, 0, 4]
    _assert_same_canvas(
        render(hist2d(xf, yf, bins=2, width=200, height=150)),
        render(hist2d(xi, yi, bins=2, width=200, height=150)),
        "Int32 hist2d matches Float64",
    )
    _assert_same_canvas(
        render(hist2d(xf, yf, width=200, height=150)),
        render(hist2d(xi, yi, width=200, height=150)),
        "Int32 hist2d (rule form) matches Float64",
    )


def test_hist2d_raises_with_names() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="same length"):
        _ = hist2d(x, y, bins=2)
    with assert_raises(contains="bins must be at least 1"):
        _ = hist2d(x, x, bins=0)
    var one: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="at least one bin"):
        _ = Plot().mark_hist2d().encode_hist2d(x, x, one, List[Float64]())
    with assert_raises():
        _ = hist2d(List[Float64](), List[Float64](), bins=2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
