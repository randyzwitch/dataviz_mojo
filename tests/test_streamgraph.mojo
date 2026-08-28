"""Tests for Mark.STREAMGRAPH: centered stacked bands (raster + SVG) --
see streamgraph.mojo's docstrings for the per-category baseline/
band rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import streamgraph

from _test_helpers import BG, _assert_color


def test_render_streamgraph_matches_hand_derived_bands() raises:
    # 2 categories ("X", "Y"), 2 series (A, B), every value 10 -- each
    # category's total is 20, so the whole picture is uniform
    # left to right (isolates the centered-baseline/stacking math from
    # the "different categories get different heights" case). Canvas
    # 400x300, show_gridlines=False, show_legend=False: plot area
    # x:[60,380], y:[20,250] (short y-axis labels -- max_total=20, 5%
    # pad 1.0, symmetric domain [-11,11] -- keep the dynamic left
    # margin at Theme's default 60). x_scale
    # centers 140 (X) / 300 (Y) -- the same OrdinalScale math every
    # other categorical mark's tests confirm for this
    # identical 2-category/400-wide/default-margin setup. A's stack: baseline -10, top 0 -> band y:[135,240]. B's stack: baseline
    # 0, top 10 -> band y:[30,135] (see this file's SVG test for the
    # exact path data). Sampled at each band's midpoint.
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = Plot().mark_streamgraph().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(t).size(400, 300)
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 220, 187, palette[0], "A's band, midpoint -- y:[135,240]")
    _assert_color(c, 220, 82, palette[1], "B's band, midpoint -- y:[30,135]")
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_streamgraph_svg_matches_confirmed_paths() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var plot = Plot().mark_streamgraph().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<path d="M140.000,135.000 L300.000,135.000 L300.000,240.000 L140.000,240.000 Z" fill="#1f77b4"/>' in s, "A's band")
    assert_true('<path d="M140.000,30.000 L300.000,30.000 L300.000,135.000 L140.000,135.000 Z" fill="#ff7f0e"/>' in s, "B's band")


def test_render_streamgraph_raises_on_negative_value() raises:
    var cats: List[String] = ["X"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[-1.0]]
    with assert_raises():
        _ = streamgraph(cats, names, vals, width=200, height=150)


def test_render_streamgraph_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = streamgraph(cats, names, vals, width=200, height=150)


def test_render_streamgraph_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    var c = streamgraph(cats, names, vals, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
