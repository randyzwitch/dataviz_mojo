"""Tests for Mark.BEESWARM: jittered points per category (raster + SVG)
-- see beeswarm.mojo's docstrings for the row-clustering swarm
rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.vector.svg import SvgCanvas
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import beeswarm

from _test_helpers import BG, _assert_color


def test_render_beeswarm_matches_hand_derived_offsets() raises:
    # 1 category ("A"), values [10, 11, 50] -- two of the three (10 and
    # 11) land close enough in pixel space to collide, the third (50)
    # is far away and stays alone. Canvas 400x300, show_gridlines=
    # False, default margins -> plot area x:[60,380], y:[20,250].
    # x_scale = OrdinalScale(["A"], 60, 380): one category spans the
    # whole band, center = 220. y-domain = _data_extent([10,11,50]):
    # span 40, 5% pad 2.0 -> [8, 52]; scale = (20-250)/(52-8) =
    # -5.2273 -> pixel y's 240 (v=10), 234 (v=11), 30 (v=50) --
    # independently computed via python3 from LinearScale's to_
    # pixel formula. Default point_radius 3.5 rounds to 4, spacing = 8:
    # sorted by y, 50's row (y=30) is 204px from 11's (y=234,
    # sorted next) -- far past the 8px spacing threshold, its row
    # by itself, offset 0. 11 and 10 are only 6px apart (234 vs 240) --
    # inside the same row: 11 (sorted first in that row) gets offset 0,
    # 10 (sorted second) gets +1*spacing = +8.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = beeswarm(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 228, 240, t.mark_color, "value 10 -- offset +8 (second in its row)")
    _assert_color(c, 220, 234, t.mark_color, "value 11 -- offset 0 (first in its row)")
    _assert_color(c, 220, 30, t.mark_color, "value 50 -- offset 0 (alone in its row)")
    _assert_color(c, 10, 10, BG, "well outside the plot area -- background")


def test_render_beeswarm_svg_matches_confirmed_circles() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var plot = Plot().mark_beeswarm().encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<circle cx="228" cy="240" r="4" fill="#1e64b4"/>' in s, "value 10")
    assert_true('<circle cx="220" cy="234" r="4" fill="#1e64b4"/>' in s, "value 11")
    assert_true('<circle cx="220" cy="30" r="4" fill="#1e64b4"/>' in s, "value 50")


def test_render_beeswarm_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var _hoisted2 = beeswarm(cats, vals, width=200, height=150)
        _ = render(_hoisted2)


def test_render_beeswarm_raises_on_empty_category_distribution() raises:
    var cats: List[String] = ["a"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted3 = beeswarm(cats, vals, width=200, height=150)
        _ = render(_hoisted3)


def test_render_beeswarm_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var _hoisted4 = beeswarm(cats, vals, width=200, height=150)
    var c = render(_hoisted4)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
