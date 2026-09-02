"""Tests for Mark.RADIALBAR (multi-ring progress chart): per-ring
track color, swept-vs-unswept ring color, the radial gap between
rings, SVG bar paths.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import radialbar

from _test_helpers import BG, _assert_color

comptime _TRACK = Color(230, 230, 230)


def test_render_radialbar_ring_colors_and_track() raises:
    # Same 400x300, single-char "a"/"b"/"c" labels test_polar_bar.mojo
    # uses -> identical center (155,135) and max_radius 85.5
    # (default margins, dynamic legend width for three one-char labels).
    # Values [1, 2, 4] (max 4) give clean fractions: ring 0 (outermost,
    # category "a") sweeps 1/4 of the way around (90 degrees), ring 1
    # ("b") sweeps 1/2 (180 degrees), ring 2 (innermost, "c") sweeps the
    # full circle.
    #
    # n=3 -> ring_slot = 85.5/3 = 28.5, gap = 28.5*0.25 = 7.125.
    # Ring 0: outer = 85.5 - 7.125/2 = 81.9375, inner = 85.5 - 28.5 +
    #   7.125/2 = 60.5625 (mid-radius 71.25).
    # Ring 1: outer = 85.5 - 28.5 - 7.125/2 = 53.4375, inner =
    #   85.5 - 57 + 7.125/2 = 32.0625 (mid-radius 42.75).
    # Ring 2: outer = 85.5 - 57 - 7.125/2 = 24.9375, inner =
    #   85.5 - 85.5 + 7.125/2 = 3.5625 (mid-radius 14.25).
    #
    # Angle 0 = 3 o'clock (east), -90 = 12 o'clock, sweeping clockwise.
    # Ring 0's 90-degree sweep runs -90 -> 0; its angular
    # midpoint (-45, safely 45 degrees from either edge -- ~55.7px of
    # arc at this radius) sits at (155 + 71.25*cos(-45), 135 +
    # 71.25*sin(-45)) = (205.4, 84.6). Ring 1's 180-degree sweep
    # runs -90 -> 90; its midpoint (0 degrees, due east) sits at
    # (155 + 42.75, 135) = (197.75, 135).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0, 4.0]
    var _hoisted1 = radialbar(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 205, 85, palette[0], "ring 0 (outermost), swept half at -45 degrees")
    _assert_color(c, 198, 135, palette[1], "ring 1, swept half at 0 degrees (due east)")
    _assert_color(c, 155, 149, palette[2], "ring 2 (innermost), fully swept -- any angle")

    # Unswept portions of ring 0 / ring 1 (due west, 180 degrees --
    # nowhere near either ring's swept range) show the light-gray
    # track, not the category color or the plain background.
    _assert_color(c, 84, 135, _TRACK, "ring 0, unswept portion (due west) shows the track color")
    _assert_color(c, 112, 135, _TRACK, "ring 1, unswept portion (due west) shows the track color")


def test_render_radialbar_leaves_a_radial_gap_between_rings() raises:
    # Same setup as above. The radial gap between ring 0's inner
    # edge (60.5625) and ring 1's outer edge (53.4375) is centered
    # on radius 57, due east (angle 0): (155 + 57, 135) = (212, 135) --
    # untouched by either ring, so plain background, not the track
    # color (the track only covers each ring's inner/outer band).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0, 4.0]
    var _hoisted2 = radialbar(x, y, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 212, 135, BG, "the radial gap between ring 0 and ring 1")


def test_render_radialbar_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    with assert_raises():
        var _hoisted3 = radialbar(x, y, width=200, height=150)
        _ = render(_hoisted3)


def test_render_radialbar_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    with assert_raises():
        var _hoisted4 = radialbar(x, y, width=200, height=150)
        _ = render(_hoisted4)


def test_render_radialbar_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted5 = radialbar(x, y, width=200, height=150)
        _ = render(_hoisted5)


def test_render_radialbar_empty_categories_only_fills_background() raises:
    var x = List[String]()
    var y = List[Float64]()
    var _hoisted6 = radialbar(x, y, width=100, height=80)
    var c = render(_hoisted6)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")


def test_render_radialbar_svg_matches_confirmed_ring_paths() raises:
    # Two categories (no legend, to keep the geometry simple), values
    # [1, 3] -- ring 0 ("a", outermost) sweeps 1/3 of the way around,
    # ring 1 ("b", innermost) sweeps the full circle: each ring draws its gray
    # track first (a full-circle ring-sector path, `#e6e6e6`), then its
    # own value arc on top -- ring 1's value arc is a second, identical
    # full-circle path in its category color, since a fraction of
    # 1.0 sweeps the same full turn the track itself does.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = Plot().mark_radialbar().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,37.969 A97.031,97.031 0 1,1 220.000,37.969'
        ' L220.000,76.781 A58.219,58.219 0 1,0 220.000,76.781 Z" fill="#e6e6e6"/>' in s,
        "ring 0's full-circle track path",
    )
    assert_true(
        '<path d="M220.000,37.969 A97.031,97.031 0 0,1 304.032,183.516'
        ' L270.419,164.109 A58.219,58.219 0 0,0 220.000,76.781 Z" fill="#1f77b4"/>' in s,
        "ring 0's value arc, swept 1/3 of the way around (no large-arc-flag)",
    )
    assert_true(
        '<path d="M220.000,89.719 A45.281,45.281 0 1,1 220.000,89.719'
        ' L220.000,128.531 A6.469,6.469 0 1,0 220.000,128.531 Z" fill="#ff7f0e"/>' in s,
        "ring 1's value arc, fully swept -- identical shape to its track, category color on top",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
