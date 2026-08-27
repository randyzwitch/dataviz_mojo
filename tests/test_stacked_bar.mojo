"""Tests for Mark.STACKED_BAR: per-series stacked rectangles and legend,
including independent positive/negative stacking (raster + SVG).
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
from dataviz_mojo import stacked_bar

from _test_helpers import BG, _count_color, _assert_color


def test_render_stacked_bar_matches_hand_derived_rectangles() raises:
    # Same 2-category/2-series data test_render_grouped_bar_matches_
    # hand_derived_rectangles already hand-solved the axis frame for
    # (canvas 400x300, default margins, show_gridlines=False, legend
    # reserved -> OrdinalScale range [60,250], band_start(A)=69.5 ->70,
    # band_start(B)=164.5->165, bandwidth=76) -- all positive values
    # here, so only the *positive* running total ever moves. Per
    # category: North stacks first (bottom=0), South stacks on top of
    # it (bottom=North's value). y-domain: _zero_baseline_y_extent
    # over each category's *final* running total (A: 10+5=15, B:
    # 20+15=35) plus the always-included zero -> padded [0, 36.75].
    #
    # Every position independently re-derived via python3 (LinearScale's
    # own slope/intercept for the y-axis against this stacked-total
    # domain, OrdinalScale's band formula for x, unchanged from
    # Mark.GROUPED_BAR's own -- full band width per segment here, not
    # divided sub-bars).
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var c = stacked_bar(cats, names, values, theme=t, width=400, height=300)

    var palette = default_categorical_palette()
    # A, North (bottom segment, value 10): x:[70,146), y:[187,250)
    _assert_color(c, 100, 220, palette[0], "A/North segment, well inside")
    # A, South (top segment, value 5, stacked on North): x:[70,146), y:[156,187)
    _assert_color(c, 100, 170, palette[1], "A/South segment, stacked on top of North")
    # B, North (bottom segment, value 20): x:[165,241), y:[125,250)
    _assert_color(c, 195, 200, palette[0], "B/North segment, well inside")
    # B, South (top segment, value 15, stacked on North): x:[165,241), y:[31,125)
    _assert_color(c, 195, 80, palette[1], "B/South segment, stacked on top of North")
    # Unlike Mark.GROUPED_BAR, a stacked bar's segments share the
    # *full* band width, so there's no gap between series within a
    # category -- but the inter-category gap (OrdinalScale's 0.2
    # padding) is still there: x=155 sits in it at any y.
    _assert_color(c, 155, 150, BG, "the inter-category gap between A and B -- background")


def test_render_svg_stacked_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="187" width="76" height="63" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="70" y="156" width="76" height="31" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="165" y="125" width="76" height="125" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="165" y="31" width="76" height="94" fill="#ff7f0e"/>' in s, "B/South")
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch"
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch"
    )


def test_render_svg_stacked_bar_mixed_sign_stacks_independently_each_direction() raises:
    # One category ("A"), two series: North=10 (positive), South=-5
    # (negative) -- the one case test_render_stacked_bar_matches_hand_
    # derived_rectangles' all-positive data can't exercise: a
    # negative value must stack *downward* from its running
    # negative total (independent of North's positive stack), not
    # slide North's segment down by 5. y-domain: _zero_baseline_y_
    # extent over [pos_total=10, neg_total=-5] -> padded [-5.75, 10.75]
    # (span 15, 5% pad 0.75 each end, zero always included/kept exact).
    # band_start(0)=79 (1 category spans the whole OrdinalScale range,
    # no inter-category gap to speak of), bandwidth=152.
    #
    # Every position independently re-derived via python3.
    var cats: List[String] = ["A"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0], [-5.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_stacked_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    # North: data range [0,10] (positive stack, starts at zero).
    assert_true('<rect x="79" y="30" width="152" height="140" fill="#1f77b4"/>' in s, "North, above zero")
    # South: data range [-5,0] (negative stack, starts at zero, extends down).
    assert_true('<rect x="79" y="170" width="152" height="70" fill="#ff7f0e"/>' in s, "South, below zero")


def test_render_stacked_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var c = stacked_bar(cats, names, values, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


def test_render_stacked_bar_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = stacked_bar(cats, names, values, width=200, height=150)


def test_render_stacked_bar_raises_on_mismatched_value_series_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = stacked_bar(cats, names, values, width=200, height=150)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
