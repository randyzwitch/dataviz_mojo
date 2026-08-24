"""Tests for Mark.FUNNEL: tapering trapezoids, largest value first
(raster + SVG) -- see funnel.mojo's docstrings for the sort/taper
rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import funnel

from _test_helpers import BG, _assert_color


def test_render_funnel_matches_hand_derived_trapezoids() raises:
    # 3 categories, already given largest-to-smallest (100, 60, 20) so
    # display order matches input order -- isolates the taper/palette
    # math from the sort itself (see the dedicated sort test below for
    # that). Canvas 400x300, show_legend=False: plot area x:[60,380],
    # y:[20,250], center x=220, max_width=320, row_height=(250-20)/3 =
    # 76.667. top_width[i] = value[i]/100*320 -> 320/192/64; bottom_
    # width[i] = top_width[i+1] (192/64), except the last row, whose
    # own bottom matches its top (64, flat). See this file's SVG test
    # for the exact path data. Sampled at
    # each row's vertical midpoint, x=220 (dead center -- always
    # inside every trapezoid, symmetric around cx, regardless of its
    # own width), so no left/right-edge math is needed here at all.
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Float64] = [100.0, 60.0, 20.0]
    var t = Theme(show_legend=False)
    var c = funnel(cats, vals, theme=t, width=400, height=300)

    var palette = default_categorical_palette()
    _assert_color(c, 220, 58, palette[0], "row 0 (A, value 100) -- the widest row")
    _assert_color(c, 220, 134, palette[1], "row 1 (B, value 60)")
    _assert_color(c, 220, 211, palette[2], "row 2 (C, value 20) -- the narrowest row")
    _assert_color(c, 10, 10, BG, "outside the whole funnel -- background")


def test_render_funnel_svg_matches_confirmed_paths() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[Float64] = [100.0, 60.0, 20.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_funnel().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<path d="M60.000,20.000 L380.000,20.000 L316.000,96.000 L124.000,96.000 Z" fill="#1f77b4"/>' in s, "row 0")
    assert_true(
        '<path d="M124.000,96.000 L316.000,96.000 L252.000,173.000 L188.000,173.000 Z" fill="#ff7f0e"/>' in s,
        "row 1",
    )
    assert_true(
        '<path d="M188.000,173.000 L252.000,173.000 L252.000,250.000 L188.000,250.000 Z" fill="#2ca02c"/>' in s,
        "row 2 -- flat bottom, matching its top",
    )


def test_render_funnel_sorts_largest_value_first_regardless_of_input_order() raises:
    # "Small" (10) given *before* "Big" (100) -- the opposite of
    # display order. If sorting works, row 0 (drawn first, topmost) is
    # still "Big," so its top edge spans the full plot width edge
    # to edge (the largest value always does, by construction) --
    # confirmed geometrically, no need to parse the legend's text.
    var cats: List[String] = ["Small", "Big"]
    var vals: List[Float64] = [10.0, 100.0]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_funnel().encode_categorical(x=cats, y=vals).theme(Theme(show_legend=False))
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('M60.000,20.000 L380.000,20.000' in s, "row 0's top edge spans the full plot width -- it's Big, not Small")


def test_render_funnel_raises_on_negative_value() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [1.0, -1.0]
    with assert_raises():
        _ = funnel(cats, vals, width=200, height=150)


def test_render_funnel_raises_on_all_zero_values() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[Float64] = [0.0, 0.0]
    with assert_raises():
        _ = funnel(cats, vals, width=200, height=150)


def test_render_funnel_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var vals: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = funnel(cats, vals, width=200, height=150)


def test_render_funnel_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[Float64]()
    var c = funnel(cats, vals, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
