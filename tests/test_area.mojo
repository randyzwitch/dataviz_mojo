"""Tests for Mark.AREA: fill region and area_smoothing (raster + SVG).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import (
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
from dataviz_mojo.theme import Theme
from dataviz_mojo import area

from _test_helpers import BG, _count_color, _assert_color


def test_render_area_mark_matches_hand_derived_fill_region() raises:
    # x=[0,10], y=[0,10] on a 400x300 canvas, default margins (plot
    # area x:[60,380], y:[20,250]). x lands at pixel 75/365 (same
    # domain math as every other continuous-x test above).
    # _zero_baseline_y_extent([0,10]) pads only the non-zero end,
    # giving domain [0,10.5], baseline pixel y=250, top-right point
    # pixel y=31 -- so the filled region is a right-triangle-ish area
    # from (75,250) up to (365,31) then back down to the baseline
    # (both solved directly from LinearScale's formula, cross-
    # checked in Python). Interpolating that top edge at pixel x=220
    # (the plot's horizontal midpoint) puts it at y=140.5 -- a
    # point comfortably below that (y=200) must be filled, a point
    # comfortably above it (y=50) must still be background.
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    var t = Theme(show_gridlines=False)
    var c = area(x, y, theme=t, width=400, height=300)

    _assert_color(c, 220, 200, t.mark_color, "inside the filled area")
    _assert_color(c, 220, 50, BG, "above the area's top edge -- background")


def test_render_svg_area_smoothing_matches_hand_derived_curve() raises:
    # x=[0,10,20], y=[2,10,4] (a peak, deliberately not touching zero at
    # either end -- unlike this data's y=0 endpoints would, which
    # would make the closing line_to()s down to baseline degenerate,
    # zero-length segments landing exactly on the curve's last
    # point; not wrong, just a less illustrative hand-derivation).
    # Canvas 400x300, default margins, show_gridlines=False.
    # _zero_baseline_y_extent([2,10,4]) -> domain [0, 10.5] (zero
    # already exact; 10's +5% pad -> 10.5) -- the *top* edge only
    # (px/py, the same LinearScale math Mark.LINE's equivalent test
    # established the technique for) is smoothed; the two
    # line_to()s down to/along baseline (pixel y=250, to_pixel(0.0))
    # stay straight. Every control-point coordinate independently
    # re-derived via python3.
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_area().encode(x=x, y=y).theme(Theme(line_smoothing=1.0, show_gridlines=False))
    render_svg(svg, plot)
    assert_true(
        '<path d="M74.545,206.190 C98.788,176.984 171.515,38.254 220.000,30.952'
        ' C268.485,23.651 341.212,140.476 365.455,162.381 L365.455,250.000'
        ' L74.545,250.000 Z" fill="#1e64b4"/>' in svg.to_string(),
        "the smoothed top edge, then two straight line_to()s down to baseline, closed",
    )


def test_render_area_smoothing_default_matches_straight_output_exactly() raises:
    # line_smoothing's default (0.0) must reproduce the exact pre-
    # existing straight-edged Mark.AREA render byte-for-byte -- the same
    # "purely additive" bar every optional Theme field has had to clear
    # (see e.g. Mark.LINE's equivalent test). Compared pixel-for-
    # pixel across the whole canvas between Theme's bare default and
    # an explicit Theme(line_smoothing=0.0).
    var x: List[Float64] = [0.0, 10.0, 20.0]
    var y: List[Float64] = [2.0, 10.0, 4.0]
    var c_default = area(x, y, width=400, height=300)
    var c_explicit = area(x, y, theme=Theme(line_smoothing=0.0), width=400, height=300)

    for yy in range(c_default.height):
        for xx in range(c_default.width):
            var p_default = c_default.get_pixel(xx, yy)
            var p_explicit = c_explicit.get_pixel(xx, yy)
            assert_equal(p_default.r, p_explicit.r)
            assert_equal(p_default.g, p_explicit.g)
            assert_equal(p_default.b, p_explicit.b)


def test_render_area_raises_on_out_of_range_smoothing() raises:
    var x: List[Float64] = [0.0, 10.0]
    var y: List[Float64] = [0.0, 10.0]
    with assert_raises():
        _ = area(x, y, theme=Theme(line_smoothing=-0.1), width=200, height=150)
    with assert_raises():
        _ = area(x, y, theme=Theme(line_smoothing=1.1), width=200, height=150)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
