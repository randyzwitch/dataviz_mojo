"""Tests for Mark.VIOLIN: kernel-density-estimate silhouettes per
category (raster + SVG) -- see violin.mojo's docstrings for the
bandwidth/sampling/width-scaling rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas.color import Color
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from dataviz import violin

from _test_helpers import BG, _assert_color


def test_render_violin_matches_hand_derived_silhouette() raises:
    # 1 category ("A"), values [1,2,3,4,5] -- symmetric, evenly spaced,
    # so the KDE's density is symmetric around the mean (3.0) too.
    # Canvas 400x300, show_gridlines=False, default margins (short
    # "1"."5" tick labels keep the dynamic left margin at 60) -> plot
    # area x:[60,380], y:[20,250]. One category spans the whole
    # OrdinalScale band: step=320, bandwidth=320*0.8=256, center=220;
    # half_width = 256*0.4 = 102.4. Silverman's bandwidth (std-only,
    # see _kde_bandwidth's docstring) for this data computes to
    # ~0.9225 (python3, matching this file's formula exactly, not
    # re-derived by hand -- exp()-based math isn't hand arithmetic).
    # Sampled at 30 points across [1,5]: density peaks at the two
    # middle samples (y ~= 3.07, near the mean) -- both scale to the
    # violin's full half_width (102.4, by construction: the peak
    # density always maps to exactly half_width) -- pixel y 131/139,
    # x 117.6/322.4. The two end samples (y=1.0 and y=5.0, symmetric,
    # so the exact same width) scale to a *narrower* width (~73.68) --
    # pixel y 240/30 (y=1.0 -> pixel 240, confirmed below), x
    # 146.32/293.68 (see this file's SVG test for the exact path
    # substrings).
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = violin(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 135, t.mark_color, "near the peak (y~=3), dead center -- well inside")
    _assert_color(c, 280, 235, t.mark_color, "near the bottom edge (y=1), still inside the ~74px half-width there")
    _assert_color(c, 300, 235, BG, "near the bottom edge (y=1), past the ~74px half-width there -- outside")
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_violin_svg_matches_confirmed_path_points() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var plot = Plot().mark_violin().encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<path d="M293.678,240.000' in s, "the path's first point -- right edge at y=1.0 (bottom)")
    assert_true('322.400,139.000 L322.400,131.000' in s, "the flat peak-density plateau, at its full half_width")
    assert_true('L146.322,240.000 Z' in s, "the path's last point before closing -- left edge at y=1.0")


def test_render_violin_identical_values_does_not_raise() raises:
    # Every value the same (7.0) -- std comes out exactly 0.0, the one
    # case _kde_bandwidth's docstring says falls back to a fixed
    # bandwidth rather than dividing by zero. Not asserting exact
    # pixels here (the resulting silhouette has zero height -- every
    # one of its 30 samples collapses to the same y, a genuinely
    # degenerate shape, not a typical one worth pixel-deriving) -- just
    # confirming it renders at all, and background still shows well
    # away from the single collapsed row.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[7.0, 7.0, 7.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted2 = violin(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 220, 20, BG, "well above the collapsed row -- background")


def test_render_violin_custom_bandwidth_widens_the_tapered_edge() raises:
    # Same category/values/canvas as test_render_violin_matches_hand_
    # derived_silhouette above -- Silverman's default bandwidth for
    # this data is ~0.9225, tapering the y=1.0/y=5.0 tail samples down
    # to a ~74px half-width (the point (300, 235) sits just past that,
    # background under the default). A caller-given bandwidth=3.0 (a
    # much wider kernel) makes every point's Gaussian spread out
    # further, so the tails taper far less relative to the peak:
    # (300, 235) now falls *inside* the wider silhouette, and the
    # interior/exterior sanity points
    # from the default-bandwidth test still hold (a wider bandwidth
    # doesn't change *where* the peak or the far background are).
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = violin(cats, vals, bandwidth=3.0, theme=t, width=400, height=300)
    var c = render(_hoisted3)
    _assert_color(c, 300, 235, t.mark_color, "bandwidth=3.0 widens the tail -- now inside the silhouette")
    _assert_color(c, 220, 135, t.mark_color, "still inside near the peak")
    _assert_color(c, 10, 10, BG, "still background, well outside the plot area")


def test_render_violin_explicit_zero_bandwidth_matches_default() raises:
    # bandwidth=0.0 explicitly passed must reproduce the exact same
    # output as omitting it entirely -- the same "purely additive,
    # empty/zero is a sentinel for the default" guarantee Plot.encode_
    # gauge()'s breakpoints/band_colors make, exercised through the
    # actual sentinel-check code path rather than just relying on the
    # parameter's default value.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted4 = violin(cats, vals, bandwidth=0.0, theme=t, width=400, height=300)
    var c = render(_hoisted4)
    _assert_color(c, 220, 135, t.mark_color, "near the peak (y~=3), dead center -- well inside")
    _assert_color(c, 280, 235, t.mark_color, "near the bottom edge (y=1), still inside the ~74px half-width there")
    _assert_color(c, 300, 235, BG, "near the bottom edge (y=1), past the ~74px half-width there -- outside")


def test_render_violin_scale_by_count_narrows_the_smaller_category() raises:
    # Two categories: "A" (5 values, [1.5]) and "B" (2 values, [2,4]) --
    # "A" has the larger sample count, so it sets max_n=5 and its count_factor stays 1.0 (unaffected either way); "B"'s count_factor is sqrt(2/5) ~= 0.6325 under scale_by_count=True.
    # Canvas 400x300, show_gridlines=False, default margins: 2-category
    # OrdinalScale step=160, bandwidth=128, "B"'s center_x=300.
    # Sampling row y=135 (near "B"'s peak density, wherever exactly
    # that peak's y sits doesn't matter here): under the default
    # (False), "B"'s silhouette spans x=[256,343]; under scale_by_count=True, the same
    # row narrows to x=[272,327] (ratio 55/87 ~= 0.632, matching the
    # predicted sqrt(2/5) factor). Point (260,135) sits inside the
    # default silhouette but outside the narrowed one.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted5 = violin(cats, vals, scale_by_count=True, theme=t, width=400, height=300)
    var c = render(_hoisted5)
    _assert_color(c, 260, 135, BG, "scale_by_count narrows category B -- now outside")
    _assert_color(c, 300, 135, t.mark_color, "category B's center, still inside even narrowed")


def test_render_violin_scale_by_count_false_matches_default() raises:
    # scale_by_count=False explicitly passed must reproduce the exact
    # same output as omitting it -- the same explicit-default-value
    # guarantee test_render_violin_explicit_zero_bandwidth_matches_
    # default proves for bandwidth.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted6 = violin(cats, vals, scale_by_count=False, theme=t, width=400, height=300)
    var c = render(_hoisted6)
    _assert_color(c, 260, 135, t.mark_color, "unscaled -- category B still reaches its full half-width here")


def test_render_violin_raises_on_negative_bandwidth() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0]]
    with assert_raises():
        var _hoisted7 = violin(cats, vals, bandwidth=-1.0, width=200, height=150)
        _ = render(_hoisted7)


def test_render_violin_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var _hoisted8 = violin(cats, vals, width=200, height=150)
        _ = render(_hoisted8)


def test_render_violin_raises_on_empty_category_distribution() raises:
    var cats: List[String] = ["a"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted9 = violin(cats, vals, width=200, height=150)
        _ = render(_hoisted9)


def test_render_violin_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var _hoisted10 = violin(cats, vals, width=200, height=150)
    var c = render(_hoisted10)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
