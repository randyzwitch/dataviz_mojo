"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_arc.mojo`: Tests for Mark.ARC (pie/donut): wedge colors, inner_radius donut
  behavior, SVG wedge paths.

- `test_nightingale.mojo`: Tests for Mark.NIGHTINGALE (rose/coxcomb chart): equal-angle wedge
  colors, the radius-vs-area rose_type distinction, SVG wedge paths.

- `test_polar.mojo`: Tests for Mark.POLAR (polar-coordinate line plot): the shared
  `_polar_point` angle/radius -> pixel primitive, the polyline/marker
  geometry it drives, the surrounding polar grid, and encode_polar_
  series()'s multi-series generalization.

- `test_polar_bar.mojo`: Tests for Mark.POLAR_BAR (circular column chart): equal-slot bar
  colors, the angular gap between bars, SVG bar paths.

- `test_radialbar.mojo`: Tests for Mark.RADIALBAR (multi-ring progress chart): per-ring
  track color, swept-vs-unswept ring color, the radial gap between
  rings, SVG bar paths.

- `test_radar.mojo`: Tests for Mark.RADAR (spider chart): polygon fill/outline geometry,
  encode_radar()'s length-mismatch validation.

- `test_gauge.mojo`: Tests for Mark.GAUGE: the needle's angle, the three color-band
  sectors, out-of-range value clamping, encode_gauge()'s min/max
  validation, and custom breakpoints/band_colors.

- `test_parallel.mojo`: Tests for Mark.PARALLEL (parallel-coordinates chart): per-dimension
  auto-scaling, polyline geometry, encode_parallel()'s length
  validation.

- `test_single_axis.mojo`: Tests for Mark.SINGLE_AXIS: one continuous axis, every point on a
  fixed row (raster + SVG) -- see single_axis.mojo's docstrings for
  the degenerate-y_scale trick verified here.

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
    _index_of,
    _lighten,
    _unique_categories,
)
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_arc.mojo
# ---------------------------------------------------------------

def test_render_arc_mark_matches_hand_derived_wedge_colors() raises:
    # Two equal-value wedges -- each spans exactly half the circle.
    # Wedges start at 12 o'clock (-pi/2) and sweep clockwise (see
    # _render_arc's docstring for why increasing angle is
    # clockwise here): wedge 0 covers -pi/2 -> pi/2 (12 o'clock down
    # to 6 o'clock, passing through 3 o'clock/angle 0) -- a point
    # straight right of center is inside it. Wedge 1 covers pi/2 ->
    # 3pi/2 (6 o'clock back up to 12, passing through 9 o'clock/angle
    # pi) -- a point straight left of center is inside it. Center and
    # radius solved directly from the same margin-box math every
    # other mark uses, minus the 130px legend column reserved on the
    # right by default (theme.show_legend defaults True -- see
    # _render_arc's docstring): canvas 400x300, default margins ->
    # plot area x:[60,250], y:[20,250], center (155,135), radius =
    # min(190,230)/2*0.9 = 85.5 -- both test points sit only 50px out,
    # well inside that.
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
    # 2 categories, values [1, 3] (total 4) -- wedge 0 spans pi/2 (a
    # small arc, large-arc-flag 0), wedge 1 spans 3*pi/2 (large-arc-
    # flag 1) -- deliberately not a 50/50 split, whose each-wedge span
    # would land exactly on the pi boundary the large-arc-flag itself
    # switches on, an ambiguous case not worth testing. Endpoint
    # coordinates formatted through
    # `_format_svg_float`'s 3-decimal rounding (see the LINE
    # test's comment) -- which also resolves what would otherwise
    # print as 219.99999999999997 (pi's finite representation
    # leaking through) down to a clean 220.000, the expected value on
    # both ends of the full circle these two wedges split.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,135.000 L220.000,31.500 A103.500,103.500 0 0,1 323.500,135.000'
        ' Z" fill="#1f77b4"/>' in s,
        "wedge 0 (value 1, span pi/2): small arc, large-arc-flag 0, palette[0]",
    )
    assert_true(
        '<path d="M220.000,135.000 L323.500,135.000 A103.500,103.500 0 1,1 220.000,31.500'
        ' Z" fill="#ff7f0e"/>' in s,
        "wedge 1 (value 3, span 3pi/2): wide arc, large-arc-flag 1, palette[1]",
    )


def test_render_donut_leaves_the_center_unfilled_and_fills_the_ring() raises:
    # Same 2-category [1, 3] data (and the same hand-solved center/
    # radius: cx=220, cy=135, radius=103.5, no legend) test_render_
    # svg_arc_mark_matches_confirmed_wedge_paths already uses --
    # donut_inner_radius_fraction=0.5 makes inner_radius=51.75, so the
    # exact center (220, 135) must stay background (the donut hole),
    # while a point on wedge 0's angular bisector (start=-pi/2,
    # end=0, bisector=-pi/4) at the ring's midpoint radius
    # ((51.75+103.5)/2=77.625) -- (275, 80), lands deep inside the
    # filled ring, not near either edge where AA blending would make
    # an exact color match unreliable.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var _hoisted5 = pie(
        cats, vals, theme=Theme(show_legend=False, donut_inner_radius_fraction=0.5), width=400, height=300
    )
    var c = render(_hoisted5)

    _assert_color(c, 220, 135, BG, "donut hole: the exact center stays background")
    _assert_color(
        c, 275, 80, default_categorical_palette()[0], "wedge 0's ring, well inside its bounds"
    )


def test_render_donut_svg_matches_confirmed_ring_sector_paths() raises:
    # Same data/theme as the raster donut test above, through
    # render_svg() instead -- formatted through SvgCanvas's
    # 3-decimal `_format_svg_float`.
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 3.0]
    var plot = Plot().mark_arc().encode_categorical(x=cats, y=vals).theme(
        Theme(show_legend=False, donut_inner_radius_fraction=0.5)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M220.000,31.500 A103.500,103.500 0 0,1 323.500,135.000'
        ' L271.750,135.000 A51.750,51.750 0 0,0 220.000,83.250 Z" fill="#1f77b4"/>' in s,
        "wedge 0's ring-sector path, outer arc forward then inner arc backward",
    )
    assert_true(
        '<path d="M323.500,135.000 A103.500,103.500 0 1,1 220.000,31.500'
        ' L220.000,83.250 A51.750,51.750 0 1,0 271.750,135.000 Z" fill="#ff7f0e"/>' in s,
        "wedge 1's ring-sector path, wide arc (large-arc-flag 1) on both radii",
    )


def test_render_donut_raises_on_out_of_range_inner_radius_fraction() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, 1.0]
    with assert_raises():
        var _hoisted6 = pie(cats, vals, theme=Theme(donut_inner_radius_fraction=1.0), width=400, height=300)
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = pie(cats, vals, theme=Theme(donut_inner_radius_fraction=-0.1), width=400, height=300)
        _ = render(_hoisted7)

# ---------------------------------------------------------------
# from tests/test_nightingale.mojo
# ---------------------------------------------------------------

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
    var _hoisted1 = nightingale(x, y, width=400, height=300)
    var c = render(_hoisted1)

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

    var _hoisted2 = nightingale(x, y, area=False, width=400, height=300)
    var radius_mode = render(_hoisted2)
    _assert_color(radius_mode, 185, 135, BG, "radius mode: (1/4) * 85.5 = 21.375, point at r=30 is outside")
    _assert_color(radius_mode, 125, 135, palette[1], "radius mode: wedge 1 (frac 1.0) still reaches r=30")

    var _hoisted3 = nightingale(x, y, area=True, width=400, height=300)
    var area_mode = render(_hoisted3)
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
    var plot = Plot().mark_nightingale().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
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


def test_render_nightingale_empty_categories_only_fills_background() raises:
    var x = List[String]()
    var y = List[Float64]()
    var _hoisted7 = nightingale(x, y, width=100, height=80)
    var c = render(_hoisted7)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_polar.mojo
# ---------------------------------------------------------------

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
    var _hoisted1 = polar(angle, radius, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 243, 135, Theme().mark_color, "point 0 (angle 0, radius_px 23) -- east of center")
    _assert_color(c, 197, 135, Theme().mark_color, "point 1 (angle pi, radius_px 23) -- west of center")


def test_render_polar_draws_a_grid_even_with_no_data_on_it() raises:
    # A single point at the origin (radius 0) still gets the full
    # polar grid drawn -- confirmed by scanning a small column near the
    # outermost ring's nominal position, at least one pixel of which
    # must differ from a plain white background (see _render_polar's
    # docstring: no tick labels, but the rings/spokes themselves always
    # draw). A window scan, not one exact pixel: `render()`'s
    # supersample-then-downsample (`_RASTER_SUPERSAMPLE`, plot.mojo)
    # spreads a 1px ring's faint ink across a couple of columns rather
    # than concentrating it at one exact, stable position -- see
    # `_assert_near_color`'s docstring (tests/_test_helpers.mojo) for
    # the same underlying reason applied to a stroke's *color* instead
    # of its *position*.
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
        "the outer polar grid ring should paint something other than plain background somewhere near y=28-35",
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


def test_render_polar_empty_data_only_fills_background() raises:
    var angle = List[Float64]()
    var radius = List[Float64]()
    var _hoisted5 = polar(angle, radius, width=100, height=80)
    var c = render(_hoisted5)
    _assert_color(c, 50, 40, BG, "no data: nothing drawn but the background")


def test_render_polar_series_matches_hand_derived_line_and_markers() raises:
    # Two series, two single-char names ("A"/"B") -- the identical
    # dynamic-legend-width case test_nightingale.mojo's/test_polar_
    # bar.mojo's three-category cases establish for this
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
    var _hoisted6 = polar_series(angle, names, vals, width=400, height=300)
    var c = render(_hoisted6)
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


def test_render_polar_series_empty_angle_only_fills_background() raises:
    var angle = List[Float64]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    var _hoisted10 = polar_series(angle, names, vals, width=100, height=80)
    var c = render(_hoisted10)
    _assert_color(c, 50, 40, BG, "no data: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_polar_bar.mojo
# ---------------------------------------------------------------

def test_render_polar_bar_matches_hand_derived_bar_colors() raises:
    # Three equal-value categories -- same equal-angle slots (2*pi/3,
    # bisectors -30/90/210 degrees) and center/radius (400x300,
    # default margins, single-char labels -> center (155,135), max
    # radius 85.5) test_nightingale.mojo's three-category case
    # uses -- the 20% angular padding narrows each bar's span
    # around that same bisector but doesn't move it, so the same
    # radius-50 test points along each bisector stay inside their bar.
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var _hoisted1 = polarbar(x, y, width=400, height=300)
    var c = render(_hoisted1)

    var palette = default_categorical_palette()
    _assert_color(c, 198, 110, palette[0], "bar 0, bisector -30 degrees")
    _assert_color(c, 155, 185, palette[1], "bar 1, bisector 90 degrees (straight down)")
    _assert_color(c, 112, 110, palette[2], "bar 2, bisector 210 degrees")


def test_render_polar_bar_leaves_a_gap_between_bars() raises:
    # Same three-category setup as above. Slot boundaries sit at
    # -90/30/150 degrees; the 20% padding (theme.polar_bar_padding) carves
    # a 24-degree gap (2*pi/3 * 0.2) centered on each boundary, so at
    # radius 50 along the boundary between bar 0 and bar 1 (angle 30
    # degrees exactly -- offset (155 + 50*cos(30), 135 + 50*sin(30)) =
    # (198.3, 160)) neither bar has reached yet: background, not
    # either bar's color -- the one thing that actually distinguishes
    # this mark from Mark.NIGHTINGALE's edge-to-edge wedges (see
    # test_nightingale.mojo, which has no such gap to test).
    var x: List[String] = ["a", "b", "c"]
    var y: List[Float64] = [1.0, 1.0, 1.0]
    var _hoisted2 = polarbar(x, y, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 198, 160, BG, "the gap between bar 0 and bar 1, at their shared slot boundary")


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


def test_render_polar_bar_empty_categories_only_fills_background() raises:
    var x = List[String]()
    var y = List[Float64]()
    var _hoisted6 = polarbar(x, y, width=100, height=80)
    var c = render(_hoisted6)
    _assert_color(c, 50, 40, BG, "no categories: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_radialbar.mojo
# ---------------------------------------------------------------

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

# ---------------------------------------------------------------
# from tests/test_radar.mojo
# ---------------------------------------------------------------

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

# ---------------------------------------------------------------
# from tests/test_gauge.mojo
# ---------------------------------------------------------------

def test_render_gauge_matches_hand_derived_needle_and_pivot() raises:
    # value=50 over the default [0, 100] range -> fraction 0.5 ->
    # needle angle = 3*pi/4 + 3*pi/2*0.5 = 3*pi/2 (270 degrees) --
    # straight up (`_polar_point`'s convention: 270 degrees is due
    # north, since angle 0 is east and angle increases clockwise).
    # Canvas 400x300, no legend needed (a gauge has one value, nothing
    # to key one by): center (220,135), max radius 103.5 -- the same
    # no-legend numbers test_polar.mojo's tests derive for
    # this exact canvas size. Needle reaches 0.9*103.5=93.15; two
    # points straight up from center (at pixel rows 50 and 42, both
    # well short of that) fall on the needle. The center pivot dot is
    # also theme.mark_color.
    var _hoisted1 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted1)
    var mark_color = Theme().mark_color
    _assert_color(c, 220, 50, mark_color, "needle, straight up from center")
    _assert_color(c, 220, 42, mark_color, "needle, straight up from center (further out)")
    _assert_color(c, 220, 135, mark_color, "the pivot dot at the dial's center")


def test_render_gauge_matches_hand_derived_band_colors() raises:
    # Same center/radius as above. Three points at radius 88 (inside
    # the color band ring, between its 72.45 inner and 103.5 outer
    # radius), one per breakpoint band, each angle chosen well clear
    # of its band boundary and of the needle's angle (so the
    # needle line itself never explains the color): 180 degrees (west,
    # fraction (180-135)/270 = 0.167, inside the default [0, 0.2)
    # green band) -> (132, 135); 200 degrees (fraction 0.241, inside
    # [0.2, 0.8) blue) -> (137, 105); 18 degrees/378 unwrapped
    # (fraction 0.9, inside [0.8, 1.0] red) -> (304, 162).
    var _hoisted2 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted2)
    var breakpoint_colors = [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]
    _assert_color(c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167")
    _assert_color(c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241")
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_leaves_a_gap_at_the_bottom() raises:
    # The dial sweeps 270 degrees (135.405/45), leaving a 90-degree
    # gap centered on due south (90 degrees) -- a point at radius 88
    # straight down from center (220, 223) is neither a band nor the
    # needle: background.
    var _hoisted3 = gauge(50.0, width=400, height=300)
    var c = render(_hoisted3)
    _assert_color(c, 220, 223, BG, "the 90-degree gap at the bottom of the dial")


def test_render_gauge_clamps_values_beyond_the_range() raises:
    # value=1000 (way past max_value=100) clamps to fraction 1.0 ->
    # needle angle 405 degrees (= 45 degrees unwrapped), *not* an
    # error; value=-1000 clamps to fraction 0.0 -> needle angle 135
    # degrees. Both checked at a point along each needle's direction,
    # well short of its 93.15-pixel length.
    var mark_color = Theme().mark_color
    var _hoisted4 = gauge(1000.0, width=400, height=300)
    var high = render(_hoisted4)
    _assert_color(high, 255, 170, mark_color, "clamped to max_value -- needle at 45 degrees")
    var _hoisted5 = gauge(-1000.0, width=400, height=300)
    var low = render(_hoisted5)
    _assert_color(low, 185, 170, mark_color, "clamped to min_value -- needle at 135 degrees")


def test_render_gauge_raises_when_min_value_is_not_less_than_max_value() raises:
    with assert_raises():
        var _hoisted6 = gauge(5.0, min_value=10.0, max_value=10.0, width=200, height=150)
        _ = render(_hoisted6)
    with assert_raises():
        var _hoisted7 = gauge(5.0, min_value=10.0, max_value=0.0, width=200, height=150)
        _ = render(_hoisted7)


def test_render_gauge_custom_breakpoints_matches_hand_derived_band_colors() raises:
    # Same center (220,135)/radius (103.5 outer, 72.45 inner) as every
    # other test above -- breakpoints/band_colors only change which
    # color a given angle falls under, not the dial's geometry, so
    # the same three test points reused: (132,135) and (137,105) sit at
    # fractions 0.167/0.241 (both test_render_gauge_matches_hand_
    # derived_band_colors' green/blue bands under the *default*
    # split), which a two-band [0.5, 1.0] split both place in band
    # 0; (304,162) sits at fraction 0.9, in band 1 either way.
    var bps: List[Float64] = [0.5, 1.0]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    var _hoisted8 = gauge(50.0, width=400, height=300, breakpoints=bps, band_colors=cols)
    var c = render(_hoisted8)
    _assert_color(c, 132, 135, cols[0], "band 0, fraction 0.167")
    _assert_color(c, 137, 105, cols[0], "band 0, fraction 0.241")
    _assert_color(c, 304, 162, cols[1], "band 1, fraction 0.9")


def test_render_gauge_custom_breakpoints_default_empty_matches_original() raises:
    # Leaving breakpoints/band_colors at their default (empty lists)
    # must reproduce the fixed 20%/80%/100% green/blue/red default
    # exactly -- the same "purely additive" guarantee every other
    # optional feature in this package makes. Same test points/colors
    # as test_render_gauge_matches_hand_derived_band_colors, called
    # through the explicit-empty-list form instead of omitting the
    # parameters, so this exercises the actual sentinel-check code path.
    var empty_bps = List[Float64]()
    var empty_cols = List[Color]()
    var _hoisted9 = gauge(50.0, width=400, height=300, breakpoints=empty_bps, band_colors=empty_cols)
    var c = render(_hoisted9)
    var breakpoint_colors = [Color(46, 139, 87), Color(30, 144, 255), Color(220, 20, 60)]
    _assert_color(c, 132, 135, breakpoint_colors[0], "green band, fraction 0.167")
    _assert_color(c, 137, 105, breakpoint_colors[1], "blue band, fraction 0.241")
    _assert_color(c, 304, 162, breakpoint_colors[2], "red band, fraction 0.9")


def test_render_gauge_raises_on_mismatched_breakpoints_and_band_colors_length() raises:
    var bps: List[Float64] = [0.5, 1.0]
    var cols: List[Color] = [Color(10, 20, 30)]
    with assert_raises():
        var _hoisted10 = gauge(50.0, width=200, height=150, breakpoints=bps, band_colors=cols)
        _ = render(_hoisted10)


def test_render_gauge_raises_on_non_ascending_breakpoints() raises:
    var bps: List[Float64] = [0.5, 0.3]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    with assert_raises():
        var _hoisted11 = gauge(50.0, width=200, height=150, breakpoints=bps, band_colors=cols)
        _ = render(_hoisted11)


def test_render_gauge_raises_on_out_of_range_breakpoint() raises:
    var too_high: List[Float64] = [0.5, 1.5]
    var cols: List[Color] = [Color(10, 20, 30), Color(200, 100, 50)]
    with assert_raises():
        var _hoisted12 = gauge(50.0, width=200, height=150, breakpoints=too_high, band_colors=cols)
        _ = render(_hoisted12)
    var zero_start: List[Float64] = [0.0, 1.0]
    with assert_raises():
        var _hoisted13 = gauge(50.0, width=200, height=150, breakpoints=zero_start, band_colors=cols)
        _ = render(_hoisted13)

# ---------------------------------------------------------------
# from tests/test_parallel.mojo
# ---------------------------------------------------------------

def test_render_parallel_matches_hand_derived_polylines() raises:
    # Two dimensions (A, B), four rows -- two "real" rows (r1, r2)
    # plus two extra rows (r3=[0,0], r4=[10,10]) whose only job is to
    # set each column's domain to a clean [0, 10] without
    # themselves landing at a boundary pixel this test samples (a
    # point exactly at the plot's edge is prone to AA/stroke-cap
    # blending that isn't an exact color match).
    #
    # Canvas 400x300, no legend (show_legend=False): plot area
    # x:[60,380], y:[20,250] -- the same no-legend numbers test_polar.
    # mojo's tests derive for this exact canvas size. Two
    # axes (n=2) pin to the plot's left/right edges: A at x=60, B
    # at x=380.
    #
    # r1 = [3, 7]: A's frac 3/10=0.3 -> y = 250 - 0.3*230 = 181.
    # B's frac 7/10=0.7 -> y = 250 - 0.7*230 = 89. r2 = [7, 3]:
    # the mirror image, A -> y=89, B -> y=181. Both endpoints (the
    # polyline's first vertex, x=60) and an interior point 25% of
    # the way to the second axis (x=140, y linearly interpolated).
    var dims: List[String] = ["A", "B"]
    var row_names: List[String] = ["r1", "r2", "r3", "r4"]
    var data: List[List[Float64]] = [[3.0, 7.0], [7.0, 3.0], [0.0, 0.0], [10.0, 10.0]]
    var _hoisted1 = parallel(data, dims, row_names, theme=Theme(show_legend=False), width=400, height=300)
    var c = render(_hoisted1)

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
        var _hoisted2 = parallel(data, dims, row_names, width=200, height=150)
        _ = render(_hoisted2)


def test_render_parallel_raises_on_wrong_length_row() raises:
    var dims: List[String] = ["A", "B", "C"]
    var row_names: List[String] = ["r1"]
    var data: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted3 = parallel(data, dims, row_names, width=200, height=150)
        _ = render(_hoisted3)


def test_render_parallel_empty_dims_only_fills_background() raises:
    var dims = List[String]()
    var row_names = List[String]()
    var data = List[List[Float64]]()
    var _hoisted4 = parallel(data, dims, row_names, width=100, height=80)
    var c = render(_hoisted4)
    _assert_color(c, 50, 40, BG, "no dimensions: nothing drawn but the background")

# ---------------------------------------------------------------
# from tests/test_single_axis.mojo
# ---------------------------------------------------------------

def test_render_single_axis_matches_hand_derived_points() raises:
    # 3 values (10, 20, 30). Canvas 400x300, show_gridlines=False,
    # default margins -> plot area x:[60,380], y:[20,250]. x-domain =
    # _data_extent([10,20,30]): span 20, 5% pad 1.0 -> [9, 31]; scale
    # = (380-60)/(31-9) = 14.5454. -> pixel x's 75/220/365 (each
    # independently computed via python3 from LinearScale's to_
    # pixel formula). Every point lands on the same row, the plot area's
    # vertical center: (20+250)/2 = 135 exactly. Default point_
    # radius 3.5 rounds to 4.
    var x: List[Float64] = [10.0, 20.0, 30.0]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = single_axis(x, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 75, 135, t.mark_color, "the first point (x=10)")
    _assert_color(c, 220, 135, t.mark_color, "the second point (x=20)")
    _assert_color(c, 365, 135, t.mark_color, "the third point (x=30)")
    _assert_color(c, 75, 100, BG, "same column as the first point, but off its row -- background")


def test_render_single_axis_svg_matches_confirmed_circles() raises:
    var x: List[Float64] = [10.0, 20.0, 30.0]
    var plot = Plot().mark_single_axis().encode_single_axis(x=x).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<circle cx="75" cy="135" r="4" fill="#1e64b4"/>' in s, "the first point")
    assert_true('<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s, "the second point")
    assert_true('<circle cx="365" cy="135" r="4" fill="#1e64b4"/>' in s, "the third point")


def test_render_single_axis_color_encoding_reuses_point_channels() raises:
    # Two points (x=0, x=10 -> pixel columns 75/365, the same _data_
    # extent math the first test confirms for a different pair
    # of values), colored by a continuous channel spanning the same
    # [0, 10] domain -- confirms Mark.POINT's _draw_point_layer
    # channel logic really is reused unchanged here, not just the
    # plain flat-color path.
    var x: List[Float64] = [0.0, 10.0]
    var color: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted2 = single_axis(x, color=color, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 75, 135, t.color_scale_low, "x=0, color=0.0 -- the color domain's min")
    _assert_color(c, 365, 135, t.color_scale_high, "x=10, color=10.0 -- the color domain's max")


def test_render_single_axis_raises_on_mismatched_channel_length() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var color: List[Float64] = [1.0, 2.0]
    with assert_raises():
        var _hoisted3 = single_axis(x, color=color, width=200, height=150)
        _ = render(_hoisted3)


def test_render_single_axis_empty_data_only_fills_background() raises:
    var x = List[Float64]()
    var _hoisted4 = single_axis(x, width=200, height=150)
    var c = render(_hoisted4)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
