"""Tests for Mark.POLAR (polar-coordinate line plot): the shared
`_polar_point` angle/radius -> pixel primitive, the polyline/marker
geometry it drives, the surrounding polar grid, and encode_polar_
series()'s multi-series generalization.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.theme import Theme
from dataviz_mojo import polar, polar_series

from _test_helpers import BG, _assert_color


def test_render_polar_matches_hand_derived_line_and_markers() raises:
    # Three points -- angle 0, pi, pi/2 -- radius [2, 2, 9] (max 9).
    # Canvas 400x300, default theme (no legend ever drawn for this
    # mark -- see _render_polar's docstring): plot area x:[60,380],
    # y:[20,250] (no legend column to subtract, unlike Mark.ARC/
    # NIGHTINGALE/POLAR_BAR's margin math), center (220,135), max
    # radius = min(320,230)/2*0.9 = 103.5 -- the same 103.5 test_arc.
    # mojo/test_nightingale.mojo's no-legend SVG tests already
    # derive for this exact canvas size.
    #
    # Point 0 (angle 0, value 2): radius_px = 103.5*(2/9) = 23.0 ->
    # (220+23, 135) = (243, 135). Point 1 (angle pi, value 2): same
    # radius, opposite side -> (220-23, 135) = (197, 135). Point 2
    # (angle pi/2, value 9, the one that sets max) reaches the full
    # 103.5 -- right at the plot edge, not sampled directly (AA/
    # clipping risk at an exact boundary). Both sampled points
    # land squarely on the stroked polyline through the center (points
    # 0 and 1 sit on the same horizontal line as the center), so
    # either the line stroke or the point's marker circle explains
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
    # _render_polar's docstring: no tick labels, but the rings/
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


def test_render_polar_series_matches_hand_derived_line_and_markers() raises:
    # Two series, two single-char names ("A"/"B") -- the identical
    # dynamic-legend-width case test_nightingale.mojo's/test_polar_
    # bar.mojo's three-category cases already establish for this
    # exact 400x300 canvas: center (155,135), max radius 85.5 (a short
    # label never grows the legend column past Theme's fixed 130px
    # default). Three angles 120 degrees apart (0, 2*pi/3, 4*pi/3) --
    # deliberately *not* the single-series test's 0/pi pair, which
    # would put two points on the same horizontal line through the
    # center and let one series' connecting segment fully overpaint
    # the other's identical-y marker; spread around a triangle instead,
    # so no segment coincides with another series' sample point.
    #
    # Series A = [3, 6, 9], series B = [9, 3, 6] -- shared global max 9
    # (each series contains the max once, so both share one radius
    # scale exactly). Sampling each series' non-edge fractions
    # (skipping every point at fraction 1.0 -- the plot's outer
    # edge, the same AA/clipping risk test_render_polar_matches_hand_
    # derived_line_and_markers already avoids):
    #   A, angle 0, value 3 (frac 1/3): radius_px 28.5 -> (183.5, 135)
    #   A, angle 120, value 6 (frac 2/3): radius_px 57.0 ->
    #     (155+57*cos120, 135+57*sin120) = (126.5, 184.36)
    #   B, angle 120, value 3 (frac 1/3): radius_px 28.5 ->
    #     (155+28.5*cos120, 135+28.5*sin120) = (140.75, 159.68)
    #   B, angle 240, value 6 (frac 2/3): radius_px 57.0 ->
    #     (155+57*cos240, 135+57*sin240) = (126.5, 85.64)
    var angle: List[Float64] = [0.0, 2.0943951023932, 4.1887902047864]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[3.0, 6.0, 9.0], [9.0, 3.0, 6.0]]
    var c = polar_series(angle, names, vals, width=400, height=300)
    var palette = default_categorical_palette()
    _assert_color(c, 183, 135, palette[0], "series A, angle 0, radius_px 28.5")
    _assert_color(c, 126, 184, palette[0], "series A, angle 120, radius_px 57.0")
    _assert_color(c, 141, 160, palette[1], "series B, angle 120, radius_px 28.5")
    _assert_color(c, 126, 86, palette[1], "series B, angle 240, radius_px 57.0")


def test_render_polar_series_raises_on_mismatched_names_and_values_length() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = polar_series(angle, names, vals, width=200, height=150)


def test_render_polar_series_raises_when_a_series_length_does_not_match_angle() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        _ = polar_series(angle, names, vals, width=200, height=150)


def test_render_polar_series_raises_on_negative_radius() raises:
    var angle: List[Float64] = [0.0]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[-1.0]]
    with assert_raises():
        _ = polar_series(angle, names, vals, width=200, height=150)


def test_render_polar_series_empty_angle_only_fills_background() raises:
    var angle = List[Float64]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    var c = polar_series(angle, names, vals, width=100, height=80)
    _assert_color(c, 50, 40, BG, "no data: nothing drawn but the background")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
