"""Tests for Mark.CHORD: node ring sectors plus flow ribbons (raster +
smoke-level SVG) -- see chord.mojo's docstrings for the angle/
ribbon-geometry rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.vector.svg import SvgCanvas
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import chord

from _test_helpers import BG, _assert_color


def test_render_chord_two_nodes_one_edge_matches_hand_derived_geometry() raises:
    # 2 nodes ("A", "B"), one edge A->B, value 10 -- each node's total flow is 10 (its only edge), so the two ring sectors split
    # the circle exactly in half, the same -pi/2->pi/2 (A) / pi/2->3pi/2
    # (B) split test_render_arc_mark_matches_hand_derived_wedge_colors
    # confirms for two equal Mark.ARC wedges (this mark reuses
    # that exact start-at-12-o'clock, sweep-clockwise convention).
    # Canvas 400x300, show_legend=False (sidesteps the legend column's
    # font-metric-dependent width): plot area x:[60,380], y:[20,250]
    # (Theme's default margins, no dynamic-left-margin case here --
    # Mark.CHORD has no y-axis labels at all), center (220,135), radius
    # = min(320,230)/2*0.9 = 103.5, inner_radius = radius*0.92 = 95.22.
    #
    # With only one edge, that edge's sub-arc allocation *is* each
    # node's full span -- so the ribbon's rim segments trace
    # A's entire rim (-pi/2 -> pi/2) then B's entire rim (pi/2 -> 3pi/2
    # == -pi/2), a full 2*pi sweep back to the start point, with both
    # "cross" quad_curve_to calls degenerating to a single point (their
    # start and end angles are identical -- pi/2 and -pi/2 respectively).
    # The whole ribbon path is therefore just the full circle's circumference at inner_radius, traced once -- filling it fills the
    # *entire* inner disk in the ribbon's color (A's palette color,
    # index 0), not just "A's half": the inner-disk sample point on
    # B's geometric side (left of center) is still palette[0], not
    # palette[1].
    var from_cats: List[String] = ["A"]
    var to_cats: List[String] = ["B"]
    var values: List[Float64] = [10.0]
    var t = Theme(show_legend=False)
    var _hoisted1 = chord(from_cats, to_cats, values, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()

    # Ring band (radius in (95.22, 103.5)), right of center -> A.
    _assert_color(c, 319, 135, palette[0], "A's ring sector, right of center")
    # Ring band, left of center -> B.
    _assert_color(c, 121, 135, palette[1], "B's ring sector, left of center")
    # Inner disk (radius < 95.22): entirely the one ribbon's color.
    _assert_color(c, 270, 135, palette[0], "inner disk, right of center -- A's ribbon")
    _assert_color(c, 170, 135, palette[0], "inner disk, left of center (B's geometric side) -- still A's ribbon")
    _assert_color(c, 220, 135, palette[0], "dead center -- still inside the one ribbon's filled disk")
    _assert_color(c, 10, 10, BG, "well outside the whole circle -- background")


def test_render_chord_svg_writes_ribbon_and_ring_paths() raises:
    # A smoke-level structural check (not a pixel-exact one -- a
    # curved, multi-segment filled path isn't practically hand-derived
    # the way a rect-based mark's SVG output is): three nodes, real
    # flows between them, confirms real <path>/<path fill=.> markup
    # comes out for both the ribbons and the ring sectors, not just an
    # empty or background-only canvas.
    var from_cats: List[String] = ["A", "B"]
    var to_cats: List[String] = ["B", "C"]
    var values: List[Float64] = [5.0, 3.0]
    var plot = Plot().mark_chord().encode_chord(
        from_categories=from_cats, to_categories=to_cats, values=values
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true("<path " in s, "at least one ribbon drawn as a real SVG path")
    # default_categorical_palette()'s first three entries, hardcoded
    # the same way test_population_pyramid.mojo's SVG test hardcodes
    # palette hex values (Color(31,119,180)/(255,127,14)/(44,160,44)).
    assert_true("#1f77b4" in s, "node A's ring sector color appears")
    assert_true("#ff7f0e" in s, "node B's ring sector color appears")
    assert_true("#2ca02c" in s, "node C's ring sector color appears")


def test_render_chord_raises_on_mismatched_length() raises:
    var from_cats: List[String] = ["a", "b", "c"]
    var to_cats: List[String] = ["x", "y"]
    var values: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted2 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted2)


def test_render_chord_raises_on_negative_value() raises:
    var from_cats: List[String] = ["a"]
    var to_cats: List[String] = ["b"]
    var values: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted3 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted3)


def test_render_chord_raises_on_all_zero_values() raises:
    var from_cats: List[String] = ["a"]
    var to_cats: List[String] = ["b"]
    var values: List[Float64] = [0.0]
    with assert_raises():
        var _hoisted4 = chord(from_cats, to_cats, values, width=200, height=150)
        _ = render(_hoisted4)


def test_render_chord_empty_data_only_fills_background() raises:
    var from_cats = List[String]()
    var to_cats = List[String]()
    var values = List[Float64]()
    var _hoisted5 = chord(from_cats, to_cats, values, width=200, height=150)
    var c = render(_hoisted5)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
