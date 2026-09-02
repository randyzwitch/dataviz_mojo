"""Tests for Mark.ARC (pie/donut): wedge colors, inner_radius donut
behavior, SVG wedge paths.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from canvas.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
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
    _unique_categories,
)
from dataviz.theme import Theme
from dataviz import pie

from _test_helpers import BG, _count_color, _assert_color


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
