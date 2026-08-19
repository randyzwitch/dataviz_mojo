"""Tests for Mark.VIOLIN: kernel-density-estimate silhouettes per
category (raster + SVG) -- see violin.mojo's own docstrings for the
bandwidth/sampling/width-scaling rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from canvas_mojo.vector.svg import SvgCanvas
from dataviz_mojo.plot import Plot, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import violin

from _test_helpers import BG, _assert_color


def test_render_violin_matches_hand_derived_silhouette() raises:
    # 1 category ("A"), values [1,2,3,4,5] -- symmetric, evenly spaced,
    # so the KDE's own density is symmetric around the mean (3.0) too.
    # Canvas 400x300, show_gridlines=False, default margins (short
    # "1".."5" tick labels keep the dynamic left margin at 60) -> plot
    # area x:[60,380], y:[20,250]. One category spans the whole
    # OrdinalScale band: step=320, bandwidth=320*0.8=256, center=220;
    # half_width = 256*0.4 = 102.4. Silverman's bandwidth (std-only,
    # see _kde_bandwidth's own docstring) for this data computes to
    # ~0.9225 (python3, matching this file's own formula exactly, not
    # re-derived by hand -- exp()-based math isn't hand arithmetic).
    # Sampled at 30 points across [1,5]: density peaks at the two
    # middle samples (y ~= 3.07, near the mean) -- both scale to the
    # violin's own full half_width (102.4, by construction: the peak
    # density always maps to exactly half_width) -- pixel y 131/139,
    # x 117.6/322.4. The two end samples (y=1.0 and y=5.0, symmetric,
    # so the exact same width) scale to a *narrower* width (~73.68) --
    # pixel y 240/30 (y=1.0 -> pixel 240, confirmed below), x
    # 146.32/293.68. Every number here confirmed against a real
    # render_svg() run before trusting it (see this file's own SVG
    # test for the exact path substrings).
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var c = violin(cats, vals, theme=t, width=400, height=300)

    _assert_color(c, 220, 135, t.mark_color, "near the peak (y~=3), dead center -- well inside")
    _assert_color(c, 280, 235, t.mark_color, "near the bottom edge (y=1), still inside the ~74px half-width there")
    _assert_color(c, 300, 235, BG, "near the bottom edge (y=1), past the ~74px half-width there -- outside")
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_violin_svg_matches_confirmed_path_points() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var svg = SvgCanvas(400, 300)
    var plot = Plot().mark_violin().encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    )
    render_svg(svg, plot)
    var s = svg.to_string()
    assert_true('<path d="M293.678,240.000' in s, "the path's own first point -- right edge at y=1.0 (bottom)")
    assert_true('322.400,139.000 L322.400,131.000' in s, "the flat peak-density plateau, at its own full half_width")
    assert_true('L146.322,240.000 Z' in s, "the path's own last point before closing -- left edge at y=1.0")


def test_render_violin_identical_values_does_not_raise() raises:
    # Every value the same (7.0) -- std comes out exactly 0.0, the one
    # case _kde_bandwidth's own docstring says falls back to a fixed
    # bandwidth rather than dividing by zero. Not asserting exact
    # pixels here (the resulting silhouette has zero height -- every
    # one of its own 30 samples collapses to the same y, a genuinely
    # degenerate shape, not a typical one worth pixel-deriving) -- just
    # confirming it renders at all, and background still shows well
    # away from the single collapsed row.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[7.0, 7.0, 7.0]]
    var t = Theme(show_gridlines=False)
    var c = violin(cats, vals, theme=t, width=400, height=300)
    _assert_color(c, 220, 20, BG, "well above the collapsed row -- background")


def test_render_violin_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        _ = violin(cats, vals, width=200, height=150)


def test_render_violin_raises_on_empty_category_distribution() raises:
    var cats: List[String] = ["a"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        _ = violin(cats, vals, width=200, height=150)


def test_render_violin_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var c = violin(cats, vals, width=200, height=150)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
