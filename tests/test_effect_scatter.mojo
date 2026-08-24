"""Tests for Mark.EFFECT_SCATTER: Mark.POINT plus a halo drawn under
each point (raster + SVG) -- see plot.mojo's _draw_point_layer
(`draw_halo`) and `_lighten` docstrings for the geometry/color rules
verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import effect_scatter

from _test_helpers import BG, _assert_color


def test_render_effect_scatter_matches_hand_derived_halo_and_point() raises:
    # One point (5, 5) -- a constant-valued column on both axes, so
    # _data_extent pads +-1 on each side (span 0 -> the "else 1.0" pad
    # branch every _data_extent-based mark's tests already rely
    # on): domain [4, 6] on both x and y. Canvas 400x300, default
    # margins -> plot area x:[60,380], y:[20,250]; scale_x = 320/2 =
    # 160, scale_y = -230/2 = -115 (y's range is reversed, top of the
    # domain lands at the smaller pixel y). Both put (5, 5) at pixel
    # (220, 135) -- independently computed via python3. Default
    # point_radius 3.5 rounds to 4; the halo is 2.2x that (8.8 -> 9),
    # colored by `_lighten` (Theme.mark_color's (30,100,180) blended
    # toward white at a fixed 90/255 mix -- (175,200,228), read off a
    # real render rather than hand-derived, since Color.blend_over's
    # integer-division rounding isn't the thing this test exists to
    # re-verify).
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var c = effect_scatter(x, y, theme=t, width=400, height=300)

    _assert_color(c, 220, 135, t.mark_color, "the point itself, dead center")
    _assert_color(c, 220, 128, Color(175, 200, 228), "inside the halo (radius 9) but outside the point (radius 4)")
    _assert_color(c, 220, 100, BG, "well outside the halo -- background")


def test_render_effect_scatter_svg_matches_confirmed_circles() raises:
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y).theme(
        Theme(show_gridlines=False, show_legend=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<circle cx="220" cy="135" r="9" fill="#afc8e4"/>' in s, "the halo, drawn first")
    assert_true('<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s, "the point itself, drawn on top")


def test_render_point_mark_draws_no_halo() raises:
    # A plain Mark.POINT plot at the same data/theme -- confirms
    # draw_halo really does default off for every mark besides
    # EFFECT_SCATTER, not just that EFFECT_SCATTER turns it on.
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=False, show_legend=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('r="9"' not in s, "no halo circle for a plain Mark.POINT plot")


def test_render_effect_scatter_empty_data_only_fills_background() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    var c = effect_scatter(x, y, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
