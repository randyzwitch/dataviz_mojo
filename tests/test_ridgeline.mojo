"""Tests for Mark.RIDGELINE: overlapping kernel-density-estimate rows
(raster + SVG) -- see ridgeline.mojo's docstrings for the
baseline/overlap rules verified here.
"""

from std.testing import assert_equal, assert_true, assert_raises, TestSuite

from canvas_mojo.color import Color
from dataviz_mojo.plot import Plot, render, render_svg
from dataviz_mojo.theme import Theme
from dataviz_mojo import ridgeline

from _test_helpers import BG, _assert_color


def test_render_ridgeline_matches_hand_derived_rows() raises:
    # 3 categories ("A", "B", "C"), all the same symmetric values
    # [1,2,3,4,5] -- the exact same distribution Mark.VIOLIN's test
    # uses, so the KDE math itself (bandwidth, per-sample density) is
    # already independently cross-checked there; this test is about
    # the horizontal-frame geometry and row baselines/overlap, not the
    # KDE formula again. Canvas 400x300, show_gridlines=False, default
    # margins (short "A"/"B"/"C" row labels keep the dynamic left
    # margin at 60) -> plot area x:[60,380], y:[20,250].
    # _draw_horizontal_categorical_axis_frame (Mark.GANTT's core,
    # called with padding=0.0 -- see that function's docstring for
    # why a ridgeline needs edge-to-edge rows, not its 0.2 default):
    # 3-category OrdinalScale y-axis, step=(250-20)/3=76.667,
    # bandwidth=step (no padding to subtract) -- row A's baseline
    # (band_start(0) + row height) = 96.667, row B's = 173.333, row
    # C's = 250.0 (see this file's SVG test for the exact path
    # data).
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0],
    ]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = ridgeline(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 50, t.mark_color, "inside row A -- between its peak (~-3) and baseline (96.667)")
    _assert_color(
        c, 220, 98, t.mark_color,
        "just below row A's baseline (96.667) -- covered by row B's peak rising up to ~73.667,"
        " the edge-to-edge overlap padding=0.0 gives",
    )
    _assert_color(c, 10, 10, BG, "well outside the whole plot area -- background")


def test_render_ridgeline_svg_matches_confirmed_path_points() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0],
    ]
    var plot = Plot().mark_ridgeline().encode_distribution(categories=cats, values=vals).theme(
        Theme(show_gridlines=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<path d="M75.000,96.667 L75.000,24.955' in s, "row A's baseline and left-edge rise")
    assert_true('225.000,-3.000' in s, "row A's peak, at its two middle samples")
    assert_true('L365.000,96.667 Z' in s, "row A's closing edge, back down to baseline")
    assert_true('<path d="M75.000,173.333 L75.000,101.622' in s, "row B's baseline and left-edge rise")
    # Row C is the bottom-most row, so its baseline (250) lands exactly
    # on the drawn bottom axis line -- pulled 1px up to 249 before every
    # sample in its curve is computed relative to it, so its whole curve
    # (not just the flat closing edge) shifts up 1px too, 178.289 ->
    # 177.289 -- see _pull_off_axis_line's docstring (plot.mojo). Rows
    # A/B's baselines are interior row boundaries, never the drawn
    # line, so theirs (96.667/173.333 above) are unaffected.
    assert_true('<path d="M75.000,249.000 L75.000,177.289' in s, "row C's baseline and left-edge rise")


def test_render_ridgeline_custom_bandwidth_widens_the_tail() raises:
    # Single category ("A"), values [1,2,3,4,5], canvas 400x300 --
    # Silverman's default bandwidth tapers the curve's rise
    # near x=1.0 (the left tail, pixel column x=77) enough that
    # (77, 25) sits above the curve's top (background); a caller-
    # given bandwidth=3.0 (much wider than Silverman's ~0.9225) spreads
    # every sample's Gaussian further, so the tail's rise no
    # longer tapers away: (77, 25) falls inside the wider curve,
    # while a point near the row's peak (x~=220, near value 3) and one well outside the whole plot
    # area stay unaffected either way. x=77, not x=75 -- immediately
    # past the curve's own AA edge column at this resolution, so the
    # sampled pixel is a solid fill on both sides of the contrast, not
    # a partial-coverage blend either bandwidth would produce there.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted2 = ridgeline(cats, vals, bandwidth=3.0, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 77, 25, t.mark_color, "bandwidth=3.0 widens the tail -- now inside the curve")
    _assert_color(c, 220, 25, t.mark_color, "still inside near the peak")
    _assert_color(c, 10, 10, BG, "still background, well outside the plot area")


def test_render_ridgeline_explicit_zero_bandwidth_matches_default() raises:
    # bandwidth=0.0 explicitly passed must reproduce the exact same
    # output as omitting it entirely -- the same sentinel-is-the-
    # default guarantee test_render_violin_explicit_zero_bandwidth_
    # matches_default proves for Mark.VIOLIN.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted3 = ridgeline(cats, vals, bandwidth=0.0, theme=t, width=400, height=300)
    var c = render(_hoisted3)
    _assert_color(c, 75, 25, BG, "default bandwidth still tapers away at the tail -- background")
    _assert_color(c, 220, 25, t.mark_color, "still inside near the peak")


def test_render_ridgeline_scale_by_count_shortens_the_smaller_row() raises:
    # Two categories: "A" (5 values, [1.5], the larger sample count --
    # sets max_n=5, so its count_factor stays 1.0) and "B" (2
    # values, [2,4], count_factor sqrt(2/5) ~= 0.6325 under scale_by_
    # count=True). Canvas 400x300, show_gridlines=False -- row B (the
    # second, bottom row) has its baseline at y=250 and never rises
    # below its baseline, but row A (baseline y=135) never draws
    # *below* its baseline either, so any filled pixel at y > 135
    # can only be row B's curve, letting this test isolate row B's
    # rise without the two rows' overlap (`theme.ridgeline_overlap`)
    # making a taller row A ambiguous with a shorter row B. At x=220 (near
    # value 3, row B's peak-density region), row B's curve
    # top sits at y=136 under the default (right at this test's zone boundary -- tall), and only y=169 under scale_by_count=True
    # (visibly shorter). (220, 150) sits inside the default rise but
    # above the narrowed one's top.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted4 = ridgeline(cats, vals, scale_by_count=True, theme=t, width=400, height=300)
    var c = render(_hoisted4)
    _assert_color(c, 220, 150, BG, "scale_by_count shortens row B's rise -- now above its curve")
    _assert_color(c, 220, 200, t.mark_color, "still inside row B's (shorter) curve, closer to its baseline")


def test_render_ridgeline_scale_by_count_false_matches_default() raises:
    # scale_by_count=False explicitly passed must reproduce the exact
    # same output as omitting it -- the same explicit-default-value
    # guarantee test_render_ridgeline_explicit_zero_bandwidth_matches_
    # default proves for bandwidth.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted5 = ridgeline(cats, vals, scale_by_count=False, theme=t, width=400, height=300)
    var c = render(_hoisted5)
    _assert_color(c, 220, 150, t.mark_color, "unscaled -- row B still reaches this height")


def test_render_ridgeline_raises_on_negative_bandwidth() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0]]
    with assert_raises():
        var _hoisted6 = ridgeline(cats, vals, bandwidth=-1.0, width=200, height=150)
        _ = render(_hoisted6)


def test_render_ridgeline_raises_on_mismatched_category_length() raises:
    var cats: List[String] = ["a", "b"]
    var vals: List[List[Float64]] = [[1.0]]
    with assert_raises():
        var _hoisted7 = ridgeline(cats, vals, width=200, height=150)
        _ = render(_hoisted7)


def test_render_ridgeline_raises_on_empty_category_distribution() raises:
    var cats: List[String] = ["a"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted8 = ridgeline(cats, vals, width=200, height=150)
        _ = render(_hoisted8)


def test_render_ridgeline_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var vals = List[List[Float64]]()
    var _hoisted9 = ridgeline(cats, vals, width=200, height=150)
    var c = render(_hoisted9)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
