"""Tests for Mark.POLAR (polar-coordinate line plot): the shared
`_polar_point` angle/radius -> pixel primitive, the polyline/marker
geometry it drives, and the surrounding polar grid.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.theme import Theme
from dataviz_mojo import polar

from _test_helpers import BG, _assert_color


def test_render_polar_matches_hand_derived_line_and_markers() raises:
    # Three points -- angle 0, pi, pi/2 -- radius [2, 2, 9] (max 9).
    # Canvas 400x300, default theme (no legend ever drawn for this
    # mark -- see _render_polar's own docstring): plot area x:[60,380],
    # y:[20,250] (no legend column to subtract, unlike Mark.ARC/
    # NIGHTINGALE/POLAR_BAR's own margin math), center (220,135), max
    # radius = min(320,230)/2*0.9 = 103.5 -- the same 103.5 test_arc.
    # mojo/test_nightingale.mojo's own no-legend SVG tests already
    # derive for this exact canvas size.
    #
    # Point 0 (angle 0, value 2): radius_px = 103.5*(2/9) = 23.0 ->
    # (220+23, 135) = (243, 135). Point 1 (angle pi, value 2): same
    # radius, opposite side -> (220-23, 135) = (197, 135). Point 2
    # (angle pi/2, value 9, the one that sets max) reaches the full
    # 103.5 -- right at the plot edge, not sampled directly (AA/
    # clipping risk at an exact boundary). Confirmed via a real render
    # first (not assumed from the formula alone): both sampled points
    # land squarely on the stroked polyline through the center (points
    # 0 and 1 sit on the same horizontal line as the center), so
    # either the line stroke or the point's own marker circle explains
    # the color -- both paint in the same theme.mark_color, so this
    # doesn't need to distinguish which one.
    var angle: List[Float64] = [0.0, 3.14159265358979, 1.5707963267949]
    var radius: List[Float64] = [2.0, 2.0, 9.0]
    var c = polar(angle, radius, width=400, height=300)

    _assert_color(c, 243, 135, Theme().mark_color, "point 0 (angle 0, radius_px 23) -- east of center")
    _assert_color(c, 197, 135, Theme().mark_color, "point 1 (angle pi, radius_px 23) -- west of center")


def test_render_polar_draws_a_grid_even_with_no_data_on_it() raises:
    # A single point at the origin (radius 0) still gets the full
    # polar grid drawn -- confirmed by sampling a point on the
    # outermost ring (220, 31), which must differ from a plain white
    # background even though AA blending on a 1px stroke makes an
    # *exact* gridline-color match unreliable to assert (see
    # _render_polar's own docstring: no tick labels, but the rings/
    # spokes themselves always draw).
    var angle: List[Float64] = [0.0]
    var radius: List[Float64] = [0.0]
    var c = polar(angle, radius, width=400, height=300)
    var p = c.get_pixel(220, 31)
    assert_true(
        p.r != BG.r or p.g != BG.g or p.b != BG.b,
        "the outer polar grid ring should paint something other than plain background",
    )


def test_render_polar_raises_on_mismatched_length() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var radius: List[Float64] = [1.0]
    with assert_raises():
        _ = polar(angle, radius, width=200, height=150)


def test_render_polar_raises_on_negative_radius() raises:
    var angle: List[Float64] = [0.0]
    var radius: List[Float64] = [-1.0]
    with assert_raises():
        _ = polar(angle, radius, width=200, height=150)


def test_render_polar_empty_data_only_fills_background() raises:
    var angle = List[Float64]()
    var radius = List[Float64]()
    var c = polar(angle, radius, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no data: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
