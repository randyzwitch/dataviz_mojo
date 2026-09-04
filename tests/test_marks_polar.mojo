"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.ARC (wedges, donut, SVG
paths), Mark.NIGHTINGALE (equal-angle wedges, radius vs area mode),
Mark.POLAR (_polar_point, polyline/markers, the grid,
encode_polar_series()), Mark.POLAR_BAR (bar gaps), Mark.RADIALBAR
(track, rings, radial gap), Mark.RADAR (polygon fill/outline,
validation), Mark.GAUGE (needle, bands, clamping, custom
breakpoints), Mark.PARALLEL (per-dimension scaling, polylines), and
Mark.SINGLE_AXIS (every point on one row).
"""

from _test_helpers import BG, _assert_color, _count_color
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from canvas.vector.svg import SvgCanvas
from dataviz import (
    gauge,
    nightingale,
    parallel,
    pie,
    polar,
    polar_series,
    polarbar,
    radar,
    radialbar,
    single_axis,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import (
    Plot,
    render,
    render_facets,
    render_facets_svg,
    render_layers,
    render_layers_svg,
    render_svg,
    _build_line_path,
    _lighten,
)
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_arc.mojo
# ---------------------------------------------------------------


def test_render_arc_mark_matches_hand_derived_wedge_colors() raises:
    # Two equal wedges, each half the circle, starting at 12 o'clock
    # (-pi/2) and sweeping clockwise: wedge 0 covers -pi/2..pi/2 (a point
    # straight right of center is inside it), wedge 1 covers pi/2..3pi/2
    # (straight left). Canvas 400x300, default margins, the 130px legend
    # reserved by default: plot area x:[60,250], y:[20,250], center
    # (155,135), radius = min(190,230)/2*0.9 = 85.5; both test points sit
    # 50px out.
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, 1.0]
    var _hoisted1 = pie(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 205, 135, palette[0], "right of center -- wedge 0 (a)")
    _assert_color(c, 105, 135, palette[1], "left of center -- wedge 1 (b)")


def test_render_arc_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    with assert_raises():
        var _hoisted2 = pie(x, y, width=200, height=150)
        _ = render(_hoisted2)


def test_render_arc_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    with assert_raises():
        var _hoisted3 = pie(x, y, width=200, height=150)
        _ = render(_hoisted3)


def test_render_arc_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted4 = pie(x, y, width=200, height=150)
        _ = render(_hoisted4)


def test_render_svg_arc_mark_matches_confirmed_wedge_paths() raises:
    # 2 categories, values [1, 3] (total 4): wedge 0 spans pi/2
    # (large-arc-flag 0), wedge 1 spans 3*pi/2 (large-arc-flag 1); not a
    # 50/50 split, whose spans would land exactly on the pi boundary the
    # flag switches on. Endpoints go through `_format_svg_float`'s
    # 3-decimal rounding, which also resolves 219.99999999999997 to
    # 220.000.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = (
        Plot()
        .mark_arc()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,135.000 L220.000,31.500 A103.500,103.500 0 0,1'
        ' 323.500,135.000 Z" fill="#1f77b4"/>'
        in s,
        "wedge 0 (value 1, span pi/2): small arc, large-arc-flag 0, palette[0]",
    )
    assert_true(
        '<path d="M220.000,135.000 L323.500,135.000 A103.500,103.500 0 1,1'
        ' 220.000,31.500 Z" fill="#ff7f0e"/>'
        in s,
        "wedge 1 (value 3, span 3pi/2): wide arc, large-arc-flag 1, palette[1]",
    )


def test_render_donut_leaves_the_center_unfilled_and_fills_the_ring() raises:
    # Same [1, 3] data and center/radius as the SVG test (cx=220, cy=135,
    # radius=103.5, no legend); inner_radius_fraction=0.5 gives
    # inner_radius=51.75, so the center (220, 135) stays background while
    # a point on wedge 0's bisector (-pi/4) at the ring's mid radius
    # 77.625, (275, 80), is inside the ring.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var _hoisted5 = pie(
        cats,
        vals,
        theme=Theme(show_legend=False),
        inner_radius_fraction=0.5,
        width=400,
        height=300,
    )
    var c = render(_hoisted5)

    _assert_color(
        c, 220, 135, BG, "donut hole: the exact center stays background"
    )
    _assert_color(
        c,
        275,
        80,
        default_categorical_palette()[0],
        "wedge 0's ring, well inside its bounds",
    )


def test_render_donut_svg_matches_confirmed_ring_sector_paths() raises:
    # Same data/theme as the raster donut test through render_svg(),
    # formatted with 3-decimal `_format_svg_float`.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = (
        Plot()
        .mark_arc(inner_radius_fraction=0.5)
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,31.500 A103.500,103.500 0 0,1 323.500,135.000'
        ' L271.750,135.000 A51.750,51.750 0 0,0 220.000,83.250 Z"'
        ' fill="#1f77b4"/>'
        in s,
        "wedge 0's ring-sector path, outer arc forward then inner arc backward",
    )
    assert_true(
        '<path d="M323.500,135.000 A103.500,103.500 0 1,1 220.000,31.500'
        ' L220.000,83.250 A51.750,51.750 0 1,0 271.750,135.000 Z"'
        ' fill="#ff7f0e"/>'
        in s,
        "wedge 1's ring-sector path, wide arc (large-arc-flag 1) on both radii",
    )


def test_render_donut_raises_on_out_of_range_inner_radius_fraction() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var _hoisted6 = pie(
            cats, vals, inner_radius_fraction=1.0, width=400, height=300
        )
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = pie(
            cats, vals, inner_radius_fraction=-0.1, width=400, height=300
        )
        _ = render(_hoisted7)


# ---------------------------------------------------------------
# from tests/test_nightingale.mojo
# ---------------------------------------------------------------


def test_render_nightingale_matches_hand_derived_wedge_colors() raises:
    # Three equal wedges, each 2*pi/3, from 12 o'clock clockwise: wedge 0
    # spans -90..30 degrees (bisector -30), wedge 1 30..150 (bisector 90),
    # wedge 2 150..270 (bisector 210). Same center/radius as the arc test's
    # single-char-label case: canvas 400x300, plot area x:[60,250],
    # y:[20,250], center (155,135), max radius 85.5, and every wedge
    # reaches it (frac 1.0). Test points at radius 50 along each bisector.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var _hoisted1 = nightingale(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 198, 110, palette[0], "wedge 0, bisector -30 degrees")
    _assert_color(
        c, 155, 185, palette[1], "wedge 1, bisector 90 degrees (straight down)"
    )
    _assert_color(c, 112, 110, palette[2], "wedge 2, bisector 210 degrees")


def test_render_nightingale_area_mode_scales_radius_by_sqrt() raises:
    # Two categories, values [1, 4]: wedge 0 spans -90..90 degrees
    # (bisector 0, right of center), wedge 1 90..270 (bisector 180). Center
    # (155,135), max radius 85.5.
    #
    # area=False: wedge 0's radius = 85.5 * (1/4) = 21.375, so a point at
    # radius 30 on its bisector, (185, 135), is background. area=True:
    # radius = 85.5 * sqrt(1/4) = 42.75, so (185, 135) is inside. Wedge 1
    # (frac 1.0, sqrt(1) = 1) reaches full radius either way, at
    # (125, 135).
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, 4.0]
    var palette = default_categorical_palette()

    var _hoisted2 = nightingale(x, y, area=False, width=400, height=300)
    var radius_mode = render(_hoisted2)
    _assert_color(
        radius_mode,
        185,
        135,
        BG,
        "radius mode: (1/4) * 85.5 = 21.375, point at r=30 is outside",
    )
    _assert_color(
        radius_mode,
        125,
        135,
        palette[1],
        "radius mode: wedge 1 (frac 1.0) still reaches r=30",
    )

    var _hoisted3 = nightingale(x, y, area=True, width=400, height=300)
    var area_mode = render(_hoisted3)
    _assert_color(
        area_mode,
        185,
        135,
        palette[0],
        "area mode: sqrt(1/4) * 85.5 = 42.75, point at r=30 is inside",
    )
    _assert_color(
        area_mode,
        125,
        135,
        palette[1],
        "area mode: wedge 1 (frac 1.0) still reaches r=30",
    )


def test_render_nightingale_svg_matches_confirmed_wedge_paths() raises:
    # Same [1, 3] data as the arc SVG test in the default radius mode:
    # cx=220, cy=135, max radius=103.5, no legend. Equal angles: wedge 0
    # spans -90..90 degrees at radius 103.5/3=34.5, wedge 1 spans 90..270
    # at 103.5.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = (
        Plot()
        .mark_nightingale()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,135.000 L220.000,100.500 A34.500,34.500 0 1,1'
        ' 220.000,169.500 Z" fill="#1f77b4"/>'
        in s,
        "wedge 0 (value 1, frac 1/3, radius 34.5, span -90.90)",
    )
    assert_true(
        '<path d="M220.000,135.000 L220.000,238.500 A103.500,103.500 0 1,1'
        ' 220.000,31.500 Z" fill="#ff7f0e"/>'
        in s,
        "wedge 1 (value 3, frac 1.0, radius 103.5, span 90.270)",
    )


def test_render_nightingale_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    with assert_raises():
        var _hoisted4 = nightingale(x, y, width=200, height=150)
        _ = render(_hoisted4)


def test_render_nightingale_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    with assert_raises():
        var _hoisted5 = nightingale(x, y, width=200, height=150)
        _ = render(_hoisted5)


def test_render_nightingale_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted6 = nightingale(x, y, width=200, height=150)
        _ = render(_hoisted6)


def test_render_nightingale_raises_on_no_data() raises:
    # #206: an empty categorical mark used to render a plain background
    # with no error; _validate_categorical_encoding now raises before any
    # layout.
    var x = List[String]()
    var y = List[Float64]()
    with assert_raises():
        var _hoisted7 = nightingale(x, y, width=100, height=80)
        _ = render(_hoisted7)


# ---------------------------------------------------------------
# from tests/test_polar.mojo
# ---------------------------------------------------------------


def test_render_polar_matches_hand_derived_line_and_markers() raises:
    # Three points, angles 0, pi, pi/2, radius [2, 2, 9] (max 9). Canvas
    # 400x300, default theme (no legend for this mark): plot area
    # x:[60,380], y:[20,250], center (220,135), max radius 103.5.
    #
    # Point 0 (angle 0, value 2): radius_px = 103.5*(2/9) = 23.0 ->
    # (243, 135). Point 1 (angle pi): (197, 135). Point 2 (angle pi/2,
    # value 9) sits at the plot edge and isn't sampled. Both sampled points
    # are on the polyline through the center, and line and marker share
    # theme.mark_color.
    var angle: List[Float64] = [0.0, 3.14159265358979, 1.5707963267949]
    var radius: List[Float64] = [2.0, 2.0, 9.0]
    var _hoisted1 = polar(angle, radius, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c,
        243,
        135,
        Theme().mark_color,
        "point 0 (angle 0, radius_px 23) -- east of center",
    )
    _assert_color(
        c,
        197,
        135,
        Theme().mark_color,
        "point 1 (angle pi, radius_px 23) -- west of center",
    )


def test_render_polar_draws_a_grid_even_with_no_data_on_it() raises:
    # A single point at the origin still gets the full polar grid: a small
    # column near the outermost ring's position must contain at least one
    # non-background pixel. A window scan, since supersampling spreads a
    # 1px ring's ink across a couple of columns.
    var angle: List[Float64] = [0.0]
    var radius: List[Float64] = [0.0]
    var _hoisted2 = polar(angle, radius, width=400, height=300)
    var c = render(_hoisted2)
    var found_ring_ink = False
    for y in range(28, 36):
        var p = c.get_pixel(220, y)
        if p.r != BG.r or p.g != BG.g or p.b != BG.b:
            found_ring_ink = True
    assert_true(
        found_ring_ink,
        (
            "the outer polar grid ring should paint something other than plain"
            " background somewhere near y=28-35"
        ),
    )


def test_render_polar_raises_on_mismatched_length() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var radius: List[Float64] = [1.0]
    with assert_raises():
        var _hoisted3 = polar(angle, radius, width=200, height=150)
        _ = render(_hoisted3)


def test_render_polar_raises_on_negative_radius() raises:
    var angle: List[Float64] = [0.0]
    var radius: List[Float64] = [-1.0]
    with assert_raises():
        var _hoisted4 = polar(angle, radius, width=200, height=150)
        _ = render(_hoisted4)


def test_render_polar_raises_on_no_data() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var angle = List[Float64]()
    var radius = List[Float64]()
    with assert_raises():
        var _hoisted5 = polar(angle, radius, width=100, height=80)
        _ = render(_hoisted5)


def test_render_polar_series_matches_hand_derived_line_and_markers() raises:
    # Two series, single-char names, so the same legend width as the
    # nightingale/polar-bar three-category cases: center (155,135), max
    # radius 85.5. Three angles 120 degrees apart (0, 2*pi/3, 4*pi/3)
    # rather than 0/pi, so no segment of one series overpaints another
    # series' marker.
    #
    # Series A = [3, 6, 9], B = [9, 3, 6], shared max 9. Sampling the
    # non-edge fractions:
    # A, angle 0, value 3: radius_px 28.5 -> (183.5, 135)
    # A, angle 120, value 6: radius_px 57.0 -> (126.5, 184.36)
    # B, angle 120, value 3: radius_px 28.5 -> (140.75, 159.68)
    # B, angle 240, value 6: radius_px 57.0 -> (126.5, 85.64)
    var angle: List[Float64] = [0.0, 2.0943951023932, 4.1887902047864]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[3.0, 6.0, 9.0], [9.0, 3.0, 6.0]]
    var _hoisted6 = polar_series(angle, names, vals, width=400, height=300)
    var c = render(_hoisted6)
    var palette = default_categorical_palette()
    _assert_color(c, 183, 135, palette[0], "series A, angle 0, radius_px 28.5")
    _assert_color(
        c, 126, 184, palette[0], "series A, angle 120, radius_px 57.0"
    )
    _assert_color(
        c, 141, 160, palette[1], "series B, angle 120, radius_px 28.5"
    )
    _assert_color(c, 126, 86, palette[1], "series B, angle 240, radius_px 57.0")


def test_render_polar_series_raises_on_mismatched_names_and_values_length() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted7 = polar_series(angle, names, vals, width=200, height=150)
        _ = render(_hoisted7)


def test_render_polar_series_raises_when_a_series_length_does_not_match_angle() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var _hoisted8 = polar_series(angle, names, vals, width=200, height=150)
        _ = render(_hoisted8)


def test_render_polar_series_raises_on_negative_radius() raises:
    var angle: List[Float64] = [0.0]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[-1.0]]
    with assert_raises():
        var _hoisted9 = polar_series(angle, names, vals, width=200, height=150)
        _ = render(_hoisted9)


def test_render_polar_series_raises_on_empty_angle() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var angle = List[Float64]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted10 = polar_series(angle, names, vals, width=100, height=80)
        _ = render(_hoisted10)


# ---------------------------------------------------------------
# from tests/test_polar_bar.mojo
# ---------------------------------------------------------------


def test_render_polar_bar_matches_hand_derived_bar_colors() raises:
    # Three equal-value categories: the same equal-angle slots (bisectors
    # -30/90/210 degrees) and center/radius (155,135)/85.5 as the
    # nightingale test; the 20% angular padding narrows each bar around
    # its bisector, so radius-50 points on each bisector stay inside.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var _hoisted1 = polarbar(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 198, 110, palette[0], "bar 0, bisector -30 degrees")
    _assert_color(
        c, 155, 185, palette[1], "bar 1, bisector 90 degrees (straight down)"
    )
    _assert_color(c, 112, 110, palette[2], "bar 2, bisector 210 degrees")


def test_render_polar_bar_leaves_a_gap_between_bars() raises:
    # Same setup. Slot boundaries at -90/30/150 degrees; the 20% padding
    # carves a 24-degree gap centered on each, so at radius 50 along the
    # 30-degree boundary, (198.3, 160), neither bar has reached:
    # background.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var _hoisted2 = polarbar(x, y, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(
        c,
        198,
        160,
        BG,
        "the gap between bar 0 and bar 1, at their shared slot boundary",
    )


def test_render_polar_bar_raises_on_negative_value() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [1.0, -1.0]
    with assert_raises():
        var _hoisted3 = polarbar(x, y, width=200, height=150)
        _ = render(_hoisted3)


def test_render_polar_bar_raises_on_all_zero_values() raises:
    var x: List[String] = ["a", "b"]
    var y: List[Float64] = [0.0, 0.0]
    with assert_raises():
        var _hoisted4 = polarbar(x, y, width=200, height=150)
        _ = render(_hoisted4)


def test_render_polar_bar_raises_on_mismatched_category_length() raises:
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted5 = polarbar(x, y, width=200, height=150)
        _ = render(_hoisted5)


def test_render_polar_bar_raises_on_no_data() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var x = List[String]()
    var y = List[Float64]()
    with assert_raises():
        var _hoisted6 = polarbar(x, y, width=100, height=80)
        _ = render(_hoisted6)


# ---------------------------------------------------------------
# from tests/test_radialbar.mojo
# ---------------------------------------------------------------

comptime _TRACK = Color(230, 230, 230)


def test_render_radialbar_ring_colors_and_track() raises:
    # Same 400x300 canvas and single-char labels as the polar-bar test:
    # center (155,135), max_radius 85.5. Values [1, 2, 4] (max 4): ring 0
    # (outermost, "a") sweeps 90 degrees, ring 1 ("b") 180, ring 2 ("c")
    # the full circle.
    #
    # n=3 -> ring_slot = 28.5, gap = 7.125.
    # Ring 0: outer 81.9375, inner 60.5625 (mid 71.25).
    # Ring 1: outer 53.4375, inner 32.0625 (mid 42.75).
    # Ring 2: outer 24.9375, inner 3.5625 (mid 14.25).
    #
    # Angle 0 is 3 o'clock, -90 is 12 o'clock, sweeping clockwise. Ring 0's
    # sweep runs -90..0; its midpoint (-45) sits at (205.4, 84.6). Ring 1's
    # runs -90..90; its midpoint (0) sits at (197.75, 135).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 2.0, 4.0]
    var _hoisted1 = radialbar(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(
        c, 205, 85, palette[0], "ring 0 (outermost), swept half at -45 degrees"
    )
    _assert_color(
        c, 198, 135, palette[1], "ring 1, swept half at 0 degrees (due east)"
    )
    _assert_color(
        c, 155, 149, palette[2], "ring 2 (innermost), fully swept -- any angle"
    )

    # Unswept portions of rings 0/1 (due west) show the track color, not
    # the category color or the background.
    _assert_color(
        c,
        84,
        135,
        _TRACK,
        "ring 0, unswept portion (due west) shows the track color",
    )
    _assert_color(
        c,
        112,
        135,
        _TRACK,
        "ring 1, unswept portion (due west) shows the track color",
    )


def test_render_radialbar_leaves_a_radial_gap_between_rings() raises:
    # Same setup. The radial gap between ring 0's inner edge (60.5625) and
    # ring 1's outer edge (53.4375) is centered on radius 57, due east:
    # (212, 135) is background, not the track color.
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


def test_render_radialbar_raises_on_no_data() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var x = List[String]()
    var y = List[Float64]()
    with assert_raises():
        var _hoisted6 = radialbar(x, y, width=100, height=80)
        _ = render(_hoisted6)


def test_render_radialbar_svg_matches_confirmed_ring_paths() raises:
    # Two categories (no legend), values [1, 3]: ring 0 sweeps 1/3 of the
    # way, ring 1 the full circle. Each ring draws its gray track first (a
    # full-circle path, `#e6e6e6`), then its value arc; ring 1's value arc
    # is a second full-circle path in its category color.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = (
        Plot()
        .mark_radialbar()
        .encode_categorical(x=cats, y=vals)
        .theme(Theme(show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,37.969 A97.031,97.031 0 1,1 220.000,37.969'
        ' L220.000,76.781 A58.219,58.219 0 1,0 220.000,76.781 Z"'
        ' fill="#e6e6e6"/>'
        in s,
        "ring 0's full-circle track path",
    )
    assert_true(
        '<path d="M220.000,37.969 A97.031,97.031 0 0,1 304.032,183.516'
        ' L270.419,164.109 A58.219,58.219 0 0,0 220.000,76.781 Z"'
        ' fill="#1f77b4"/>'
        in s,
        "ring 0's value arc, swept 1/3 of the way around (no large-arc-flag)",
    )
    assert_true(
        '<path d="M220.000,89.719 A45.281,45.281 0 1,1 220.000,89.719'
        ' L220.000,128.531 A6.469,6.469 0 1,0 220.000,128.531 Z"'
        ' fill="#ff7f0e"/>'
        in s,
        (
            "ring 1's value arc, fully swept -- identical shape to its track,"
            " category color on top"
        ),
    )


# ---------------------------------------------------------------
# from tests/test_radar.mojo
# ---------------------------------------------------------------


def test_render_radar_matches_hand_derived_polygon_fill() raises:
    # Three indicators, all max 100, one series at [100, 100, 100]: every
    # vertex at the outer radius, an equilateral triangle. Spokes at
    # -90/30/150 degrees. No legend: canvas 400x300 -> center (220,135),
    # max radius 103.5.
    #
    # The centroid (the center) and a point on the median toward a vertex
    # (angle -90, radius 50) lie inside the polygon. A point between two
    # vertices near the edge (angle 90, radius 100; the edge sits at the
    # apothem, 103.5*cos(60)=51.75) falls outside, confirming a real
    # triangle rather than a disk.
    var indicators: List[String] = ["Attack", "Defense", "Speed"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0]
    var series_names: List[String] = ["Team A"]
    var series_values: List[List[Float64]] = [[100.0, 100.0, 100.0]]
    var _hoisted1 = radar(
        indicators,
        max_values,
        series_names,
        series_values,
        theme=Theme(show_legend=False),
        width=400,
        height=300,
    )
    var c = render(_hoisted1)

    # mark_radar(fill_alpha=...)'s default, passed explicitly since
    # _lighten takes alpha as a parameter.
    var fill = _lighten(default_categorical_palette()[0], 90)
    _assert_color(
        c, 220, 135, fill, "centroid of the fully-maxed triangle -- inside"
    )
    _assert_color(
        c,
        220,
        85,
        fill,
        "median from center toward the -90 degree vertex -- inside",
    )
    _assert_color(
        c,
        220,
        235,
        BG,
        "angle 90, radius 100 -- beyond the triangle's 51.75 apothem, outside",
    )


def test_render_radar_raises_on_mismatched_indicator_length() raises:
    var indicators: List[String] = ["A", "B", "C"]
    var max_values: List[Float64] = [1.0, 1.0]
    var series_names: List[String] = ["s"]
    var series_values: List[List[Float64]] = [[1.0, 1.0, 1.0]]
    with assert_raises():
        var _hoisted2 = radar(
            indicators,
            max_values,
            series_names,
            series_values,
            width=200,
            height=150,
        )
        _ = render(_hoisted2)


def test_render_radar_raises_on_mismatched_series_length() raises:
    var indicators: List[String] = ["A", "B"]
    var max_values: List[Float64] = [1.0, 1.0]
    var series_names: List[String] = ["s1", "s2"]
    var series_values: List[List[Float64]] = [[1.0, 1.0]]
    with assert_raises():
        var _hoisted3 = radar(
            indicators,
            max_values,
            series_names,
            series_values,
            width=200,
            height=150,
        )
        _ = render(_hoisted3)


def test_render_radar_raises_on_wrong_length_series_values() raises:
    var indicators: List[String] = ["A", "B", "C"]
    var max_values: List[Float64] = [1.0, 1.0, 1.0]
    var series_names: List[String] = ["s"]
    var series_values: List[List[Float64]] = [[1.0, 1.0]]
    with assert_raises():
        var _hoisted4 = radar(
            indicators,
            max_values,
            series_names,
            series_values,
            width=200,
            height=150,
        )
        _ = render(_hoisted4)


def test_render_radar_raises_on_no_indicators() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var indicators = List[String]()
    var max_values = List[Float64]()
    var series_names = List[String]()
    var series_values = List[List[Float64]]()
    with assert_raises():
        var _hoisted5 = radar(
            indicators,
            max_values,
            series_names,
            series_values,
            width=100,
            height=80,
        )
        _ = render(_hoisted5)


# ---------------------------------------------------------------
# from tests/test_gauge.mojo
# ---------------------------------------------------------------


def test_render_gauge_matches_hand_derived_needle_and_pivot() raises:
    # value=50 over [0, 100] -> fraction 0.5 -> needle angle = 3*pi/4 +
    # 3*pi/2*0.5 = 3*pi/2 (270 degrees, straight up). Canvas 400x300, no
    # legend: center (220,135), max radius 103.5. The needle reaches
    # 0.9*103.5=93.15; two points straight up from center (rows 50 and 42)
    # fall on it. The pivot dot is also theme.mark_color.
    var _hoisted1 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted1)
    var mark_color = Theme().mark_color
    _assert_color(c, 220, 50, mark_color, "needle, straight up from center")
    _assert_color(
        c, 220, 42, mark_color, "needle, straight up from center (further out)"
    )
    _assert_color(c, 220, 135, mark_color, "the pivot dot at the dial's center")


def test_render_gauge_matches_hand_derived_band_colors() raises:
    # Same center/radius. Three points at radius 88 (inside the band ring,
    # between 72.45 and 103.5), one per band, each angle clear of its band
    # boundary and the needle: 180 degrees (fraction (180-135)/270 =
    # 0.167, the [0, 0.2) green band) -> (132, 135); 200 degrees (fraction
    # 0.241, blue) -> (137, 105); 18 degrees / 378 unwrapped (fraction 0.9,
    # red) -> (304, 162).
    var _hoisted2 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted2)
    var breakpoint_colors = [
        Color(46, 139, 87),
        Color(30, 144, 255),
        Color(220, 20, 60),
    ]
    _assert_color(
        c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167"
    )
    _assert_color(
        c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241"
    )
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_leaves_a_gap_at_the_bottom() raises:
    # The dial sweeps 270 degrees (135 to 405), leaving a 90-degree gap
    # centered on due south: (220, 223) at radius 88 is background.
    var _hoisted3 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted3)
    _assert_color(
        c, 220, 223, BG, "the 90-degree gap at the bottom of the dial"
    )


def test_render_gauge_clamps_values_beyond_the_range() raises:
    # value=1000 clamps to fraction 1.0 -> needle angle 405 degrees (45
    # unwrapped); value=-1000 clamps to 0.0 -> 135 degrees. Checked along
    # each needle's direction, short of its length.
    var mark_color = Theme().mark_color
    var _hoisted4 = gauge(1000.0, width=400, height=300)
    var high = render(_hoisted4)
    _assert_color(
        high,
        255,
        170,
        mark_color,
        "clamped to max_value -- needle at 45 degrees",
    )
    var _hoisted5 = gauge(-1000.0, width=400, height=300)
    var low = render(_hoisted5)
    _assert_color(
        low,
        185,
        170,
        mark_color,
        "clamped to min_value -- needle at 135 degrees",
    )


def test_render_gauge_raises_when_min_value_is_not_less_than_max_value() raises:
    with assert_raises():
        var _hoisted6 = gauge(
            5.0, min_value=10.0, max_value=10.0, width=200, height=150
        )
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = gauge(
            5.0, min_value=10.0, max_value=0.0, width=200, height=150
        )
        _ = render(_hoisted7)


def test_render_gauge_custom_breakpoints_matches_hand_derived_band_colors() raises:
    # Same center/radius; breakpoints/band_colors only change which color
    # an angle falls under. (132,135) and (137,105) sit at fractions
    # 0.167/0.241, both in band 0 of a [0.5, 1.0] split; (304,162) at
    # fraction 0.9 is in band 1.
    var bps: List[Float64] = [0.5, 1.0]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    var _hoisted8 = gauge(
        50.0, width=400, height=300, breakpoints=bps, band_colors=cols
    )
    var c = render(_hoisted8)
    _assert_color(c, 132, 135, cols[0], "band 0, fraction 0.167")
    _assert_color(c, 137, 105, cols[0], "band 0, fraction 0.241")
    _assert_color(c, 304, 162, cols[1], "band 1, fraction 0.9")


def test_render_gauge_custom_breakpoints_default_empty_matches_original() raises:
    # Empty breakpoints/band_colors (passed explicitly) reproduce the
    # 20%/80%/100% green/blue/red default, exercising the sentinel check
    # itself.
    var empty_bps = List[Float64]()
    var empty_cols = List[Color]()
    var _hoisted9 = gauge(
        50.0,
        width=400,
        height=300,
        breakpoints=empty_bps,
        band_colors=empty_cols,
    )
    var c = render(_hoisted9)
    var breakpoint_colors = [
        Color(46, 139, 87),
        Color(30, 144, 255),
        Color(220, 20, 60),
    ]
    _assert_color(
        c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167"
    )
    _assert_color(
        c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241"
    )
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_raises_on_mismatched_breakpoints_and_band_colors_length() raises:
    var bps: List[Float64] = [0.5, 1.0]
    var cols: List[Color] = [Color(10, 20, 30)]
    with assert_raises():
        var _hoisted10 = gauge(
            50.0, width=200, height=150, breakpoints=bps, band_colors=cols
        )
        _ = render(_hoisted10)


def test_render_gauge_raises_on_non_ascending_breakpoints() raises:
    var bps: List[Float64] = [0.5, 0.3]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    with assert_raises():
        var _hoisted11 = gauge(
            50.0, width=200, height=150, breakpoints=bps, band_colors=cols
        )
        _ = render(_hoisted11)


def test_render_gauge_raises_on_out_of_range_breakpoint() raises:
    var too_high: List[Float64] = [0.5, 1.5]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    with assert_raises():
        var _hoisted12 = gauge(
            50.0, width=200, height=150, breakpoints=too_high, band_colors=cols
        )
        _ = render(_hoisted12)
    var zero_start: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted13 = gauge(
            50.0,
            width=200,
            height=150,
            breakpoints=zero_start,
            band_colors=cols,
        )
        _ = render(_hoisted13)


# ---------------------------------------------------------------
# from tests/test_parallel.mojo
# ---------------------------------------------------------------


def test_render_parallel_matches_hand_derived_polylines() raises:
    # Two dimensions (A, B), four rows: r1, r2, plus r3=[0,0] and
    # r4=[10,10], whose job is to set each column's domain to [0, 10]
    # without being sampled at a boundary pixel.
    #
    # Canvas 400x300, no legend: plot area x:[60,380], y:[20,250]. Two axes
    # pin to the edges: A at x=60, B at x=380.
    #
    # r1 = [3, 7]: A's frac 0.3 -> y = 250 - 0.3*230 = 181; B's frac 0.7 ->
    # y = 89. r2 = [7, 3]: the mirror. Sampled at the first vertex (x=60)
    # and 25% of the way to the second axis (x=140, y interpolated).
    var dims: List[String] = ["A", "B"]
    var row_names: List[String] = ["r1", "r2", "r3", "r4"]
    var data: List[List[Float64]] = [
        [3.0, 7.0],
        [7.0, 3.0],
        [0.0, 0.0],
        [10.0, 10.0],
    ]
    var _hoisted1 = parallel(
        data,
        dims,
        row_names,
        theme=Theme(show_legend=False),
        width=400,
        height=300,
    )
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(
        c, 60, 181, palette[0], "r1's first vertex, axis A (frac 0.3)"
    )
    _assert_color(
        c, 140, 158, palette[0], "r1's polyline, 25% of the way to axis B"
    )
    _assert_color(c, 60, 89, palette[1], "r2's first vertex, axis A (frac 0.7)")
    _assert_color(
        c, 140, 112, palette[1], "r2's polyline, 25% of the way to axis B"
    )


def test_render_parallel_raises_on_mismatched_row_length() raises:
    var dims: List[String] = ["A", "B"]
    var row_names: List[String] = ["r1", "r2"]
    var data: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted2 = parallel(data, dims, row_names, width=200, height=150)
        _ = render(_hoisted2)


def test_render_parallel_raises_on_wrong_length_row() raises:
    var dims: List[String] = ["A", "B", "C"]
    var row_names: List[String] = ["r1"]
    var data: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted3 = parallel(data, dims, row_names, width=200, height=150)
        _ = render(_hoisted3)


def test_render_parallel_raises_on_no_dims() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var dims = List[String]()
    var row_names = List[String]()
    var data = List[List[Float64]]()
    with assert_raises():
        var _hoisted4 = parallel(data, dims, row_names, width=100, height=80)
        _ = render(_hoisted4)


# ---------------------------------------------------------------
# from tests/test_single_axis.mojo
# ---------------------------------------------------------------


def test_render_single_axis_matches_hand_derived_points() raises:
    # 3 values (10, 20, 30). Canvas 400x300, no gridlines, default margins
    # -> plot area x:[60,380], y:[20,250]. x-domain =
    # _data_extent([10,20,30]) = [9, 31], scale 14.5454 -> pixel x
    # 75/220/365. Every point lands on the vertical center row, (20+250)/2
    # = 135. point_radius 3.5 rounds to 4.
    var x: List[Float64] = [10.0, 20.0, 30.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = single_axis(x, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 75, 135, t.mark_color, "the first point (x=10)")
    _assert_color(c, 220, 135, t.mark_color, "the second point (x=20)")
    _assert_color(c, 365, 135, t.mark_color, "the third point (x=30)")
    _assert_color(
        c,
        75,
        100,
        BG,
        "same column as the first point, but off its row -- background",
    )


def test_render_single_axis_svg_matches_confirmed_circles() raises:
    var x: List[Float64] = [10.0, 20.0, 30.0]
    var plot = (
        Plot()
        .mark_single_axis()
        .encode_single_axis(x=x)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<circle cx="75" cy="135" r="4" fill="#1e64b4"/>' in s,
        "the first point",
    )
    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s,
        "the second point",
    )
    assert_true(
        '<circle cx="365" cy="135" r="4" fill="#1e64b4"/>' in s,
        "the third point",
    )


def test_render_single_axis_color_encoding_reuses_point_channels() raises:
    # Two points (x=0, x=10 -> columns 75/365) colored by a continuous
    # channel over [0, 10]: _draw_point_layer's channel logic is reused
    # unchanged here.
    var x: List[Float64] = [0.0, 10.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = single_axis(x, color=color, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(
        c,
        75,
        135,
        t.color_scale_low,
        "x=0, color=0.0 -- the color domain's min",
    )
    _assert_color(
        c,
        365,
        135,
        t.color_scale_high,
        "x=10, color=10.0 -- the color domain's max",
    )


def test_render_single_axis_raises_on_mismatched_channel_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var color: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted3 = single_axis(x, color=color, width=200, height=150)
        _ = render(_hoisted3)


def test_render_single_axis_raises_on_no_data() raises:
    # #206: see test_render_nightingale_raises_on_no_data above.
    var x = List[Float64]()
    with assert_raises():
        var _hoisted4 = single_axis(x, width=200, height=150)
        _ = render(_hoisted4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
