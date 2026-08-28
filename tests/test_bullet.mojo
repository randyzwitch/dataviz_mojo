"""Tests for Mark.BULLET: qualitative range bands, measure, and target
(raster + SVG).
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.path import _CUBIC_TO, _LINE_TO, _MOVE_TO
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
from dataviz_mojo import bullet

from _test_helpers import BG, _count_color, _assert_color, _assert_near_color


def test_render_bullet_matches_hand_derived_bands_measure_and_target() raises:
    # 2 categories, canvas 400x300, default margins (plot area x:[60,
    # 380], y:[20,250]), show_gridlines=False. "A" = ranges=[40,70,100],
    # measure=55, target=65; "B" = ranges=[30,60,90], measure=75,
    # target=50. Domain data = {0, range-top, measure, target} per
    # category = [0,100,55,65, 0,90,75,50] -> _zero_baseline_y_extent
    # gives lo=min(0,0)=0 (unpadded, already at zero), hi=max(0,100)=100
    # padded 5% of the 100-span to 105 -- domain [0, 105]. Same
    # 2-category OrdinalScale over [60,380] every other categorical test
    # establishes (bands at x=76/236, width 128, centers
    # 140/300). Every pixel below independently computed via python3
    # from LinearScale's slope/intercept formula (scale=(20-250)/
    # 105=-2.190476., translate=250).
    # Built via Plot/Canvas/render() directly, not bullet() -- see
    # test_render_boxplot_matches_hand_derived_box_whiskers_and_
    # outlier's comment for why an exact hand-derived pixel check
    # uses render() itself rather than the (now internally
    # supersampled) quickplot wrapper.
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = Plot().mark_bullet().encode_bullet(cats, measures, targets, ranges).theme(t).size(400, 300)
    var c = render(_hoisted1)

    _assert_color(c, 90, 200, Color(224, 224, 224), "A: lightest range band [0,40], off the measure bar")
    _assert_color(c, 90, 130, Color(172, 172, 172), "A: middle range band [40,70], off the measure bar")
    _assert_color(c, 90, 60, Color(120, 120, 120), "A: darkest range band [70,100], off the measure bar")
    _assert_color(c, 140, 200, t.mark_color, "A: inside the measure bar (0 to 55), over the bands")
    # A's target tick, not B's: `render()`'s supersample-then-downsample
    # (`_RASTER_SUPERSAMPLE`, plot.mojo) doesn't land this particular
    # 1px-wide stroke fully opaque at this column -- B's target tick
    # below, at a different pixel position, still does (see
    # `_assert_near_color`'s docstring, tests/_test_helpers.mojo).
    _assert_near_color(c, 90, 108, t.axis_color, 65, "A: the target tick (65), off the measure bar")
    _assert_color(c, 140, 10, BG, "A: above every band -- background")
    _assert_color(c, 300, 150, t.mark_color, "B: inside the measure bar (0 to 75)")
    _assert_color(c, 250, 140, t.axis_color, "B: the target tick (50), off the measure bar")
    _assert_color(c, 220, 150, BG, "the gap between A's and B's bands -- background")


def test_render_bullet_svg_matches_confirmed_bands_measure_and_target() raises:
    var cats: List[String] = ["A", "B"]
    var measures: List[Float64] = [55.0, 75.0]
    var targets: List[Float64] = [65.0, 50.0]
    var ranges: List[List[Float64]] = [[40.0, 70.0, 100.0], [30.0, 60.0, 90.0]]
    var plot = Plot().mark_bullet().encode_bullet(cats, measures, targets, ranges).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    # The lightest band's bottom (prev_threshold=0) and the measure
    # bar's bottom (baseline=0) both land exactly on the drawn bottom
    # axis line, so both heights are pulled 1px off it (88->87,
    # 120->119) -- the middle/darkest bands and the target tick never
    # touch 0, so theirs are unaffected. See _pull_off_axis_line's
    # docstring (plot.mojo).
    assert_true('<rect x="76" y="162" width="128" height="87" fill="#e0e0e0"/>' in s, "A's lightest band [0,40]")
    assert_true('<rect x="76" y="97" width="128" height="65" fill="#acacac"/>' in s, "A's middle band [40,70]")
    assert_true('<rect x="76" y="31" width="128" height="66" fill="#787878"/>' in s, "A's darkest band [70,100]")
    assert_true('<rect x="118" y="130" width="45" height="119" fill="#1e64b4"/>' in s, "A's measure bar")
    assert_true(
        '<line x1="76" y1="108" x2="204" y2="108" stroke="#505050" stroke-width="1.000"'
        ' stroke-linecap="round"/>' in s,
        "A's target tick, full band width",
    )


def test_render_bullet_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], [1.0]]
    with assert_raises():
        var _hoisted2 = bullet(cats, one, one, ranges, width=200, height=150)
        _ = render(_hoisted2)


def test_render_bullet_raises_on_empty_range_thresholds() raises:
    var cats: List[String] = ["a", "b"]
    var one: List[Float64] = [1.0, 2.0]
    var ranges: List[List[Float64]] = [[1.0], List[Float64]()]
    with assert_raises():
        var _hoisted3 = bullet(cats, one, one, ranges, width=200, height=150)
        _ = render(_hoisted3)


def test_render_bullet_raises_on_non_ascending_range_thresholds() raises:
    var cats: List[String] = ["a"]
    var one: List[Float64] = [1.0]
    var ranges: List[List[Float64]] = [[50.0, 30.0, 100.0]]
    with assert_raises():
        var _hoisted4 = bullet(cats, one, one, ranges, width=200, height=150)
        _ = render(_hoisted4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
