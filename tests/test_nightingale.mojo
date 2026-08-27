"""Tests for Mark.NIGHTINGALE (rose/coxcomb chart): equal-angle wedge
colors, the radius-vs-area rose_type distinction, SVG wedge paths.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import nightingale

from _test_helpers import BG, _assert_color


def test_render_nightingale_matches_hand_derived_wedge_colors() raises:
    # Three equal-value wedges -- each spans exactly 2*pi/3 (120
    # degrees). Wedges start at 12 o'clock (-pi/2) and sweep clockwise
    # (Mark.ARC's convention, reused unchanged -- see _render_
    # nightingale's docstring): wedge 0 spans -90.30 degrees
    # (bisector -30), wedge 1 spans 30.150 (bisector 90, straight
    # down), wedge 2 spans 150.270 (bisector 210). Same center/radius
    # as test_arc.mojo's "a"/"b" case (single-char category labels
    # reserve the same legend width regardless of how many rows, since
    # legend width depends on the widest label, not the row count):
    # canvas 400x300, default margins -> plot area x:[60,250],
    # y:[20,250], center (155,135), max radius 85.5 -- all three
    # wedges reach that same radius here (equal values -> frac=1.0
    # each). Test points at radius 50 (well inside, away from any
    # edge/AA blending) along each wedge's bisector, offsets
    # computed by hand from cos/sin of each bisector angle.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var c = nightingale(x, y, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 198, 110, palette[0], "wedge 0, bisector -30 degrees")
    _assert_color(c, 155, 185, palette[1], "wedge 1, bisector 90 degrees (straight down)")
    _assert_color(c, 112, 110, palette[2], "wedge 2, bisector 210 degrees")


def test_render_nightingale_area_mode_scales_radius_by_sqrt() raises:
    # Two categories, values [1, 4] (max 4): wedge 0 spans -90.90
    # degrees (bisector 0, straight right of center), wedge 1 spans
    # 90.270 (bisector 180, straight left). Same center/radius as
    # above (400x300, default margins, single-char labels): center
    # (155,135), max radius 85.5.
    #
    # rose_type="radius" (area=False, the default): wedge 0's radius = 85.5 * (1/4) = 21.375 -- a point at radius 30 along its
    # bisector (185, 135) falls *outside* it, background.
    # rose_type="area" (area=True): wedge 0's radius =
    # 85.5 * sqrt(1/4) = 85.5 * 0.5 = 42.75 -- that same point (185,
    # 135) now falls *inside* it. This is the one pixel that actually
    # discriminates the two modes; wedge 1 (value equals the max, frac
    # 1.0 either way -- sqrt(1) = 1) reaches full radius in both modes
    # -- unaffected, at (125, 135).
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, 4.0]
    var palette = default_categorical_palette()

    var radius_mode = nightingale(x, y, area=False, width=400, height=300)
    _assert_color(radius_mode, 185, 135, BG, "radius mode: (1/4) * 85.5 = 21.375, point at r=30 is outside")
    _assert_color(radius_mode, 125, 135, palette[1], "radius mode: wedge 1 (frac 1.0) still reaches r=30")

    var area_mode = nightingale(x, y, area=True, width=400, height=300)
    _assert_color(area_mode, 185, 135, palette[0], "area mode: sqrt(1/4) * 85.5 = 42.75, point at r=30 is inside")
    _assert_color(area_mode, 125, 135, palette[1], "area mode: wedge 1 (frac 1.0) still reaches r=30")


def test_render_nightingale_svg_matches_confirmed_wedge_paths() raises:
    # Same 2-category [1, 3] data test_arc.mojo's SVG test uses,
    # default rose_type="radius" mode -- center/radius solved the same
    # way (400x300, no legend): cx=220, cy=135, max radius=103.5.
    # Equal angles this time (not ARC's value-proportional ones):
    # wedge 0 spans -90.90 degrees at radius 103.5*(1/3)=34.5, wedge 1
    # spans 90.270 at radius 103.5*(3/3)=103.5, formatted through SvgCanvas's 3-decimal `_format_svg_float`.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_nightingale().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,135.000 L220.000,100.500 A34.500,34.500 0 1,1 220.000,169.500'
        ' Z" fill="#1f77b4"/>' in s,
        "wedge 0 (value 1, frac 1/3, radius 34.5, span -90.90)",
    )
    assert_true(
        '<path d="M220.000,135.000 L220.000,238.500 A103.500,103.500 0 1,1 220.000,31.500'
        ' Z" fill="#ff7f0e"/>' in s,
        "wedge 1 (value 3, frac 1.0, radius 103.5, span 90.270)",
    )


def test_render_nightingale_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    with assert_raises():
        _ = nightingale(x, y, width=200, height=150)


def test_render_nightingale_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    with assert_raises():
        _ = nightingale(x, y, width=200, height=150)


def test_render_nightingale_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = nightingale(x, y, width=200, height=150)


def test_render_nightingale_empty_categories_only_fills_background() raises:
    var x = List[String]()
    var y = List[Float64]()
    var c = nightingale(x, y, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
