"""Tests for Mark.RADAR (spider chart): polygon fill/outline geometry,
encode_radar()'s length-mismatch validation.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render, _lighten
from dataviz_mojo.theme import Theme
from dataviz_mojo import radar

from _test_helpers import BG, _assert_color


def test_render_radar_matches_hand_derived_polygon_fill() raises:
    # Three indicators, all max 100, one series at [100, 100, 100] --
    # every vertex sits exactly at the outer radius, an equilateral
    # triangle inscribed in the circle. Spokes at -90/30/150 degrees
    # (Mark.NIGHTINGALE's three-way angle split, reused here too).
    # No legend (show_legend=False, same no-legend margin math test_
    # arc.mojo's SVG tests derive): canvas 400x300 -> center
    # (220,135), max radius 103.5.
    #
    # The centroid of an equilateral triangle inscribed in a circle is
    # the circle's center -- always inside the filled polygon.
    # The median from center toward a vertex (angle -90, radius 50,
    # well short of the 103.5 vertex) also always lies inside a convex
    # polygon. A point *between* two vertices near the circle's edge, though (angle 90 -- exactly opposite the triangle's top edge, at radius 100 -- the edge itself sits at the triangle's
    # apothem, 103.5*cos(60)=51.75, well short of 100) falls
    # *outside* the triangle: still background, not the fill color --
    # confirming the polygon is a real triangle, not a full disk.
    var indicators: List[String] = ["Attack", "Defense", "Speed"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0]
    var series_names: List[String] = ["Team A"]
    var series_values: List[List[Float64]] = [[100.0, 100.0, 100.0]]
    var _hoisted1 = radar(
        indicators, max_values, series_names, series_values,
        theme=Theme(show_legend=False), width=400, height=300,
    )
    var c = render(_hoisted1)

    # Theme.radar_fill_alpha's default -- the same tint the render
    # path uses, passed explicitly since _lighten takes alpha as a parameter.
    var fill = _lighten(default_categorical_palette()[0], Theme().radar_fill_alpha)
    _assert_color(c, 220, 135, fill, "centroid of the fully-maxed triangle -- inside")
    _assert_color(c, 220, 85, fill, "median from center toward the -90 degree vertex -- inside")
    _assert_color(c, 220, 235, BG, "angle 90, radius 100 -- beyond the triangle's 51.75 apothem, outside")


def test_render_radar_raises_on_mismatched_indicator_length() raises:
    var indicators: List[String] = ["A", "B", "C"]
    var max_values: List[Float64] = [1.0, 1.0]
    var series_names: List[String] = ["s"]
    var series_values: List[List[Float64]] = [[1.0, 1.0, 1.0]]
    with assert_raises():
        var _hoisted2 = radar(indicators, max_values, series_names, series_values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_radar_raises_on_mismatched_series_length() raises:
    var indicators: List[String] = ["A", "B"]
    var max_values: List[Float64] = [1.0, 1.0]
    var series_names: List[String] = ["s1", "s2"]
    var series_values: List[List[Float64]] = [[1.0, 1.0]]
    with assert_raises():
        var _hoisted3 = radar(indicators, max_values, series_names, series_values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_radar_raises_on_wrong_length_series_values() raises:
    var indicators: List[String] = ["A", "B", "C"]
    var max_values: List[Float64] = [1.0, 1.0, 1.0]
    var series_names: List[String] = ["s"]
    var series_values: List[List[Float64]] = [[1.0, 1.0]]
    with assert_raises():
        var _hoisted4 = radar(indicators, max_values, series_names, series_values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_radar_empty_indicators_only_fills_background() raises:
    var indicators = List[String]()
    var max_values = List[Float64]()
    var series_names = List[String]()
    var series_values = List[List[Float64]]()
    var _hoisted5 = radar(indicators, max_values, series_names, series_values, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no indicators: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
