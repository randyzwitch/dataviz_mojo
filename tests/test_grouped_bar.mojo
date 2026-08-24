"""Tests for Mark.GROUPED_BAR: per-series rectangles and legend (raster +
SVG).
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
from dataviz_mojo import grouped_bar

from _test_helpers import BG, _count_color, _assert_color


def test_render_grouped_bar_matches_hand_derived_rectangles() raises:
    # 2 categories ("A"/"B", short labels -- dynamic left margin stays
    # at Theme's default 60, the same short-label convention every
    # other hand-derived test in this file already relies on), 2 series
    # -- `values[0]` (North) = [10, 20] (North's value for A, then
    # B), `values[1]` (South) = [5, 15] (South's value for A, then
    # B): North_A=10, North_B=20, South_A=5, South_B=15 -- easy to
    # mis-cross with North_A/South_A both "the first number," which is
    # exactly what a first pass at this test's hand-derivation got
    # wrong before a real render() run caught it; the values below are
    # the corrected, confirmed ones. Canvas 400x300, default margins,
    # show_gridlines=False, show_legend left at its default (True)
    # -- grouped bar always reserves a legend column, unlike plain
    # Mark.BAR, so the OrdinalScale's range is [60, 250], not
    # [60, 380] (270 = 400 - Theme's default 130px legend_width,
    # minus margin_right=20).
    #
    # y-domain: _zero_baseline_y_extent over every value (10, 20, 5, 15)
    # -> [0, 21] (zero already exact, so unpadded; 20's +5% pad ->
    # 21). OrdinalScale over [60, 250], 2 categories, step=95,
    # bandwidth=76 (0.2 padding) -> band_start(A)=69.5, band_start(B)=
    # 164.5. sub_width = bandwidth/2 = 38. Every sub-bar's left/
    # right edge computed as a *rounded boundary*, not an independently
    # rounded width -- see _render_grouped_bar's docstring for why.
    #
    # Every position independently re-derived via python3 (LinearScale's
    # own slope/intercept for the y-axis, OrdinalScale's band
    # formula for x, both re-solved for this shrunk-by-the-legend
    # range), then confirmed against a real render() run before trusting
    # it here.
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var t = Theme(show_gridlines=False)
    var c = grouped_bar(cats, names, values, theme=t, width=400, height=300)

    var palette = default_categorical_palette()
    # A, North (series 0, value 10): x:[70,108), y:[140,250)
    _assert_color(c, 89, 200, palette[0], "A/North bar, well inside")
    # A, South (series 1, value 5): x:[108,146), y:[195,250)
    _assert_color(c, 127, 220, palette[1], "A/South bar, well inside")
    # B, North (series 0, value 20): x:[165,203), y:[31,250)
    _assert_color(c, 184, 100, palette[0], "B/North bar, well inside")
    # B, South (series 1, value 15): x:[203,241), y:[86,250)
    _assert_color(c, 222, 150, palette[1], "B/South bar, well inside")
    # The gap between A's two sub-bars and B's two sub-bars is
    # zero (consecutive-boundary rounding, no gap within a category) --
    # but there IS a real gap *between* categories A and B (OrdinalScale's
    # own 0.2 padding, band_start(B)=164.5 vs A's band ending at
    # 69.5+76=145.5): x=155 sits in that inter-category gap at any y.
    _assert_color(c, 155, 150, BG, "the inter-category gap between A and B -- background")


def test_render_svg_grouped_bar_matches_confirmed_rects_and_legend() raises:
    var cats: List[String] = ["A", "B"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[10.0, 20.0], [5.0, 15.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_grouped_bar().encode_grouped_bar(cats, names, values).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()

    assert_true('<rect x="70" y="140" width="38" height="110" fill="#1f77b4"/>' in s, "A/North")
    assert_true('<rect x="108" y="195" width="38" height="55" fill="#ff7f0e"/>' in s, "A/South")
    assert_true('<rect x="165" y="31" width="38" height="219" fill="#1f77b4"/>' in s, "B/North")
    assert_true('<rect x="203" y="86" width="38" height="164" fill="#ff7f0e"/>' in s, "B/South")

    # Legend: _draw_legend's row layout (legend_swatch_size=14,
    # legend_row_gap=8) is already covered by Mark.POINT's/Mark.ARC's
    # own hand-derived legend tests -- this only confirms _render_
    # grouped_bar actually calls it with the right labels/palette/
    # starting position: x=plot_x1+margin_right=250+20=270, y=plot_y0=
    # 20 (row 0), row 1 at y=20+(14+8)=42.
    assert_true(
        '<rect x="270" y="20" width="14" height="14" fill="#1f77b4"/>' in s, "North's legend swatch"
    )
    assert_true(
        '<rect x="270" y="42" width="14" height="14" fill="#ff7f0e"/>' in s, "South's legend swatch"
    )


def test_render_grouped_bar_zero_length_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [List[Float64]()]
    var c = grouped_bar(cats, names, values, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- just the background fill")


def test_render_grouped_bar_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["a", "b"]
    var names: List[String] = ["North", "South"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = grouped_bar(cats, names, values, width=200, height=150)


def test_render_grouped_bar_raises_on_mismatched_value_series_length() raises:
    var cats: List[String] = ["a", "b", "c"]
    var names: List[String] = ["North"]
    var values: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = grouped_bar(cats, names, values, width=200, height=150)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
