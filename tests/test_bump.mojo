"""Tests for Mark.BUMP: rank lines over a categorical axis (raster +
SVG) -- see bump.mojo's docstrings for the rank-computation/rank-
axis rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.color_scale import default_categorical_palette
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import bump

from _test_helpers import BG, _assert_color


def test_render_bump_matches_hand_derived_rank_lines() raises:
    # 2 categories ("X", "Y"), 2 series: A=[10, 30], B=[20, 5]. At X,
    # B (20) outranks A (10) -- A rank 2, B rank 1; at Y, A (30)
    # outranks B (5) -- A rank 1, B rank 2. Canvas 400x300, default
    # margins (rank labels "1"/"2" stay well under the default 60px
    # left margin, the same short-label convention every other mark's
    # tests already rely on) -> plot area x:[60,380], y:[20,250].
    # x_scale = OrdinalScale(["X","Y"], 60, 380) (default padding 0.2):
    # step 160, bandwidth 128, centers 140 (X) and 300 (Y).
    # n_series=2 -> _bump_rank_pixel(1,2,20,250)=20 (top),
    # _bump_rank_pixel(2,2,20,250)=250 (bottom): A's line runs
    # (140,250)->(300,20) [rank 2 at X, rank 1 at Y], B's the exact
    # mirror, (140,20)->(300,250).
    #
    # Built via a plain Canvas()+render() (not the bump() quickplot
    # wrapper) -- the same choice test_line.mojo makes for every
    # stroked-line pixel check here: quickplot's supersample-then-
    # downsample pass measurably shifts a thin diagonal stroke's exact
    # pixel position -- a real, if subtle, difference from a plain
    # render() call, not something to test around by picking a bigger
    # tolerance. Two of each line's points sampled: the row-250
    # endpoint (both lines reliably get full ink exactly at that one)
    # and one interior point roughly a third of the way along (the
    # row-20 endpoint itself does *not* reliably get ink -- some
    # rounded-line-cap/clip interaction at the plot area's top
    # boundary row -- so this test doesn't rely on it).
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 30.0], [20.0, 5.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = Plot().mark_bump().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
        t
    ).size(400, 300)
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 140, 250, palette[0], "A's rank-2-at-X endpoint")
    _assert_color(c, 300, 250, palette[1], "B's rank-2-at-Y endpoint")
    _assert_color(c, 185, 185, palette[0], "A's line, partway from X to Y")
    _assert_color(c, 255, 185, palette[1], "B's line, partway from X to Y")


def test_render_bump_svg_matches_confirmed_paths_and_ticks() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 30.0], [20.0, 5.0]]
    var plot = Plot().mark_bump().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<path d="M140.000,250.000 L300.000,20.000"' in s, "A's line: rank 2 at X, rank 1 at Y")
    assert_true('<path d="M140.000,20.000 L300.000,250.000"' in s, "B's line: rank 1 at X, rank 2 at Y")
    assert_true('text-anchor="end">1<' in s, "the rank-1 tick label")
    assert_true('text-anchor="end">2<' in s, "the rank-2 tick label")


def test_render_bump_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        _ = bump(cats, names, vals, width=200, height=150)


def test_render_bump_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    var c = bump(cats, names, vals, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
