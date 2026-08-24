"""Tests for Mark.PARALLEL (parallel-coordinates chart): per-dimension
auto-scaling, polyline geometry, encode_parallel()'s length
validation.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render
from dataviz_mojo.theme import Theme
from dataviz_mojo import parallel

from _test_helpers import BG, _assert_color


def test_render_parallel_matches_hand_derived_polylines() raises:
    # Two dimensions (A, B), four rows -- two "real" rows (r1, r2)
    # plus two extra rows (r3=[0,0], r4=[10,10]) whose only job is to
    # set each column's domain to a clean [0, 10] without
    # themselves landing at a boundary pixel this test samples (a
    # point exactly at the plot's edge is prone to AA/stroke-cap
    # blending that isn't an exact color match -- confirmed directly
    # by probing before writing this test, not assumed).
    #
    # Canvas 400x300, no legend (show_legend=False): plot area
    # x:[60,380], y:[20,250] -- the same no-legend numbers test_polar.
    # mojo's tests already derive for this exact canvas size. Two
    # axes (n=2) pin to the plot's left/right edges: A at x=60, B
    # at x=380.
    #
    # r1 = [3, 7]: A's frac 3/10=0.3 -> y = 250 - 0.3*230 = 181.
    # B's frac 7/10=0.7 -> y = 250 - 0.7*230 = 89. r2 = [7, 3]:
    # the mirror image, A -> y=89, B -> y=181. Both endpoints (the
    # polyline's first vertex, x=60) and an interior point 25% of
    # the way to the second axis (x=140, y linearly interpolated)
    # confirmed via a real render() run first.
    var dims: List[String] = ["A", "B"]
    var row_names: List[String] = ["r1", "r2", "r3", "r4"]
    var data: List[List[Float64]] = [[3.0, 7.0], [7.0, 3.0], [0.0, 0.0], [10.0, 10.0]]
    var c = parallel(data, dims, row_names, theme=Theme(show_legend=False), width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 60, 181, palette[0], "r1's first vertex, axis A (frac 0.3)")
    _assert_color(c, 140, 158, palette[0], "r1's polyline, 25% of the way to axis B")
    _assert_color(c, 60, 89, palette[1], "r2's first vertex, axis A (frac 0.7)")
    _assert_color(c, 140, 112, palette[1], "r2's polyline, 25% of the way to axis B")


def test_render_parallel_raises_on_mismatched_row_length() raises:
    var dims: List[String] = ["A", "B"]
    var row_names: List[String] = ["r1", "r2"]
    var data: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = parallel(data, dims, row_names, width=200, height=150)


def test_render_parallel_raises_on_wrong_length_row() raises:
    var dims: List[String] = ["A", "B", "C"]
    var row_names: List[String] = ["r1"]
    var data: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = parallel(data, dims, row_names, width=200, height=150)


def test_render_parallel_empty_dims_only_fills_background() raises:
    var dims = List[String]()
    var row_names = List[String]()
    var data = List[List[Float64]]()
    var c = parallel(data, dims, row_names, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no dimensions: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
