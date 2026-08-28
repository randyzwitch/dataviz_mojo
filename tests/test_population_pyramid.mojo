"""Tests for Mark.POPULATION_PYRAMID: two mirrored magnitude bars per
category, growing outward from a shared, always-centered zero baseline
(raster + SVG) -- see population_pyramid.mojo's docstrings for the
domain/rendering rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import population_pyramid

from _test_helpers import BG, _assert_color


def test_render_population_pyramid_matches_hand_derived_bars() raises:
    # 2 categories ("A", "B"), left=[10, 30], right=[20, 10]. Canvas
    # 400x300, show_gridlines=False, show_legend=False (isolates the
    # bars from the legend's column reservation). The largest
    # magnitude across both sides is 30 -> 5% pad 1.5 -> symmetric
    # x-domain [-31.5, 31.5], mapped to plot x:[60, 380] (short "A"/"B"
    # labels keep the dynamic left margin at Theme's default 60,
    # the same margin test_render_gantt_matches_hand_derived_bars
    # confirms for this identical setup) -- a symmetric
    # domain's midpoint (0.0) always maps to the pixel range's midpoint, so the center baseline lands exactly on pixel 220. y is
    # the categorical axis: OrdinalScale over [20, 250] (2 categories,
    # step 115, bandwidth 92) -- the exact same numbers that same gantt
    # test confirms, since Mark.POPULATION_PYRAMID reuses Mark.
    # GANTT's horizontal frame unchanged. Every x pixel below
    # independently computed via python3 from LinearScale's to_
    # pixel formula.
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 30.0]
    var right: List[Float64] = [20.0, 10.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var c = population_pyramid(cats, left, right, theme=t, width=400, height=300)

    var palette = default_categorical_palette()

    # A's row, y:[32,124) -- left bar x:[169,220), right bar x:[220,322).
    _assert_color(c, 190, 60, palette[0], "A's left bar, well inside")
    _assert_color(c, 270, 60, palette[1], "A's right bar, well inside")
    _assert_color(c, 100, 60, BG, "left of A's left bar -- background")

    # B's row, y:[147,239) -- left bar x:[68,220), right bar x:[220,271).
    _assert_color(c, 100, 180, palette[0], "B's left bar, well inside")
    _assert_color(c, 250, 180, palette[1], "B's right bar, well inside")
    _assert_color(c, 330, 180, BG, "right of B's right bar -- background")

    _assert_color(c, 190, 140, BG, "the gap between A's and B's rows -- background")


def test_render_population_pyramid_svg_matches_confirmed_rects() raises:
    var cats: List[String] = ["A", "B"]
    var left: List[Float64] = [10.0, 30.0]
    var right: List[Float64] = [20.0, 10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right
    ).theme(Theme(show_gridlines=False, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<rect x="169" y="32" width="51" height="92" fill="#1f77b4"/>' in s, "A's left bar")
    assert_true('<rect x="220" y="32" width="102" height="92" fill="#ff7f0e"/>' in s, "A's right bar")
    assert_true('<rect x="68" y="147" width="152" height="92" fill="#1f77b4"/>' in s, "B's left bar")
    assert_true('<rect x="220" y="147" width="51" height="92" fill="#ff7f0e"/>' in s, "B's right bar")


def test_render_population_pyramid_zero_magnitude_draws_no_bar() raises:
    # A zero on one side means nothing to mark there -- unlike Mark.
    # GANTT's zero-length-span-floors-to-1px rule (a real milestone
    # marker), see _render_population_pyramid's docstring for why
    # this mark deliberately does not floor.
    var cats: List[String] = ["Only"]
    var left: List[Float64] = [0.0]
    var right: List[Float64] = [10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right
    ).theme(Theme(show_gridlines=False, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('fill="#1f77b4"' not in s, "zero-magnitude left side draws no rect at all")
    assert_true('fill="#ff7f0e"' in s, "the non-zero right side still draws")


def test_render_population_pyramid_legend_uses_left_right_fallback_names() raises:
    # No left_name/right_name given -- _render_population_pyramid's docstring says the legend still draws, falling back to "Left"/
    # "Right", unlike Mark.GROUPED_BAR's legend which needs real names.
    var cats: List[String] = ["A"]
    var left: List[Float64] = [10.0]
    var right: List[Float64] = [10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">Left<" in s, "the fallback legend label for the left side")
    assert_true(">Right<" in s, "the fallback legend label for the right side")


def test_render_population_pyramid_legend_uses_given_names() raises:
    var cats: List[String] = ["A"]
    var left: List[Float64] = [10.0]
    var right: List[Float64] = [10.0]
    var plot = Plot().mark_population_pyramid().encode_population_pyramid(
        categories=cats, left_values=left, right_values=right, left_name="Male", right_name="Female"
    ).theme(Theme(show_gridlines=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(">Male<" in s, "the given left legend label")
    assert_true(">Female<" in s, "the given right legend label")


def test_render_population_pyramid_raises_on_mismatched_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    with assert_raises():
        _ = population_pyramid(cats, one, one, width=200, height=150)


def test_render_population_pyramid_empty_data_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[Float64]()
    var c = population_pyramid(cats, vals, vals, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
