"""Merged test module -- one process for a whole family of test
files, instead of one per file. Each `render()` call monomorphizes
`_render_generic[T: DrawTarget]` over every ~50 `_render_*`
function, and that cost is paid per process, so merging is what
keeps it from being paid once per file (see pixi.toml's `[tasks]`
comment for the measurements).

- `test_beeswarm.mojo`: Tests for Mark.BEESWARM: jittered points per category (raster + SVG)
  -- see beeswarm.mojo's docstrings for the row-clustering swarm
  rules verified here.

- `test_violin.mojo`: Tests for Mark.VIOLIN: kernel-density-estimate silhouettes per
  category (raster + SVG) -- see violin.mojo's docstrings for the
  bandwidth/sampling/width-scaling rules verified here.

- `test_ridgeline.mojo`: Tests for Mark.RIDGELINE: overlapping kernel-density-estimate rows
  (raster + SVG) -- see ridgeline.mojo's docstrings for the
  baseline/overlap rules verified here.

- `test_streamgraph.mojo`: Tests for Mark.STREAMGRAPH: centered stacked bands (raster + SVG) --
  see streamgraph.mojo's docstrings for the per-category baseline/
  band rules verified here.

- `test_bump.mojo`: Tests for Mark.BUMP: rank lines over a categorical axis (raster +
  SVG) -- see bump.mojo's docstrings for the rank-computation/rank-
  axis rules verified here.

- `test_effect_scatter.mojo`: Tests for Mark.EFFECT_SCATTER: Mark.POINT plus a halo drawn under
  each point (raster + SVG) -- see plot.mojo's _draw_point_layer
  (`draw_halo`) and `_lighten` docstrings for the geometry/color rules
  verified here.

"""

from _test_helpers import BG, _assert_color, _assert_near_color
from canvas.color import Color
from canvas.vector.svg import SvgCanvas
from dataviz import beeswarm, bump, effect_scatter, ridgeline, streamgraph, violin
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_beeswarm.mojo
# ---------------------------------------------------------------

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

# ---------------------------------------------------------------
# from tests/test_violin.mojo
# ---------------------------------------------------------------

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

# ---------------------------------------------------------------
# from tests/test_ridgeline.mojo
# ---------------------------------------------------------------

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

# ---------------------------------------------------------------
# from tests/test_streamgraph.mojo
# ---------------------------------------------------------------

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


def test_render_streamgraph_svg_smoothing_matches_confirmed_cubic_path() raises:
    # 3 categories (X,Y,Z), 2 series: A=[10,15,8], B=[5,10,12] --
    # totals [15,25,20], max_total=25, pad=1.25, symmetric y-domain
    # [-13.75,13.75]. Canvas 400x300, show_gridlines/show_legend=False:
    # plot area x:[60,380], y:[20,250], x-centers 113.333/220.000/
    # 326.667 (OrdinalScale step (380-60)/3=106.667, same padded-band
    # math every other categorical mark's tests already confirm).
    # A's stack (first series): running starts at -total_i/2 ->
    # bottom=[-7.5,-12.5,-10], top=[2.5,2.5,-2] -- pixel y via
    # LinearScale(-13.75,13.75,250,20) rounded to the nearest int (the
    # `_axis_pixel` every mark's hand-derived pixel test already relies
    # on): top_py=[114,114,152], bottom_py=[198,240,219]. Every control
    # point below independently re-derived via python3's own Catmull-
    # Rom tangent formula from these rounded pixel positions, then
    # checked against this actual rendered path -- not just asserted
    # from whatever the renderer happened to print.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 15.0, 8.0], [5.0, 10.0, 12.0]]
    var plot = Plot().mark_streamgraph().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
        Theme(show_gridlines=False, show_legend=False, line_smoothing=1.0)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M113.333,114.000 C131.111,114.000 184.444,107.667 220.000,114.000'
        ' C255.556,120.333 308.889,145.667 326.667,152.000 L326.667,219.000'
        ' C308.889,222.500 255.556,243.500 220.000,240.000 C184.444,236.500 131.111,205.000 113.333,198.000 Z"'
        ' fill="#1f77b4"/>' in s,
        "A's band: smoothed top edge, straight cap, smoothed bottom edge (reversed), straight cap via close()",
    )


def test_render_streamgraph_raises_on_out_of_range_smoothing() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var plot = Plot().mark_streamgraph().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
            Theme(line_smoothing=-0.1)
        ).size(200, 150)
        _ = render(plot)
    with assert_raises():
        var plot = Plot().mark_streamgraph().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
            Theme(line_smoothing=1.1)
        ).size(200, 150)
        _ = render(plot)


def test_streamgraph_defaults_to_smoothed_bands() raises:
    # streamgraph()'s own default (`smoothing=0.6`, unlike Theme's own
    # 0.0) means calling it with no explicit smoothing argument at all
    # already curves the bands -- a real cubic command in the SVG
    # output, not just straight `L` segments.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 15.0, 8.0]]
    var _hoisted4 = streamgraph(cats, names, vals, width=400, height=300)
    var svg = render_svg(_hoisted4)
    assert_true(" C" in svg.to_string(), "default streamgraph() output includes a cubic curve command")


def test_streamgraph_smoothing_zero_reproduces_straight_bands() raises:
    # Passing smoothing=0.0 explicitly opts back into the old plain-
    # straight-segment bands -- byte-identical to a hand-built Plot
    # with Theme's own line_smoothing default (0.0).
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var _hoisted5 = streamgraph(cats, names, vals, theme=Theme(show_gridlines=False, show_legend=False), smoothing=0.0, width=400, height=300)
    var svg = render_svg(_hoisted5)
    var s = svg.to_string()
    assert_true('<path d="M140.000,135.000 L300.000,135.000 L300.000,240.000 L140.000,240.000 Z" fill="#1f77b4"/>' in s, "A's band, straight")
    assert_true('<path d="M140.000,30.000 L300.000,30.000 L300.000,135.000 L140.000,135.000 Z" fill="#ff7f0e"/>' in s, "B's band, straight")


def test_render_streamgraph_raises_on_negative_value() raises:
    var cats: List[String] = ["X"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[-1.0]]
    with assert_raises():
        var _hoisted1 = streamgraph(cats, names, vals, width=200, height=150)
        _ = render(_hoisted1)


def test_render_streamgraph_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted2 = streamgraph(cats, names, vals, width=200, height=150)
        _ = render(_hoisted2)


def test_render_streamgraph_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    var _hoisted3 = streamgraph(cats, names, vals, width=200, height=150)
    var c = render(_hoisted3)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")

# ---------------------------------------------------------------
# from tests/test_bump.mojo
# ---------------------------------------------------------------

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
    # Two of each line's points sampled: the row-250 endpoint and one
    # interior point roughly a third of the way along (the row-20
    # endpoint itself does *not* reliably get ink -- some rounded-line-
    # cap/clip interaction at the plot area's top boundary row -- so
    # this test doesn't rely on it). The interior points land exactly
    # on palette color (`_assert_color`); the endpoints, right at each
    # line's own rounded cap, only land *close* to it -- `render()`'s
    # supersample-then-downsample (`_RASTER_SUPERSAMPLE`, plot.mojo)
    # blends a line-cap's curved edge slightly, the same reason
    # `_assert_near_color` exists (tests/_test_helpers.mojo).
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 30.0], [20.0, 5.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = Plot().mark_bump().encode_grouped_bar(categories=cats, series_names=names, values=vals).theme(
        t
    ).size(400, 300)
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_near_color(c, 140, 250, palette[0], 20, "A's rank-2-at-X endpoint")
    _assert_near_color(c, 300, 250, palette[1], 20, "B's rank-2-at-Y endpoint")
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
        var _hoisted1 = bump(cats, names, vals, width=200, height=150)
        _ = render(_hoisted1)


def test_render_bump_empty_categories_only_fills_background() raises:
    var cats = List[String]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    var _hoisted2 = bump(cats, names, vals, width=200, height=150)
    var c = render(_hoisted2)
    _assert_color(c, 100, 75, BG, "no categories -- background everywhere")

# ---------------------------------------------------------------
# from tests/test_effect_scatter.mojo
# ---------------------------------------------------------------

def test_render_effect_scatter_matches_hand_derived_halo_and_point() raises:
    # One point (5, 5) -- a constant-valued column on both axes, so
    # _data_extent pads +-1 on each side (span 0 -> the "else 1.0" pad
    # branch every _data_extent-based mark's tests already rely
    # on): domain [4, 6] on both x and y. Canvas 400x300, default
    # margins -> plot area x:[60,380], y:[20,250]; scale_x = 320/2 =
    # 160, scale_y = -230/2 = -115 (y's range is reversed, top of the
    # domain lands at the smaller pixel y). Both put (5, 5) at pixel
    # (220, 135) -- independently computed via python3. Default
    # point_radius 3.5 rounds to 4; the halo is 2.2x that (8.8 -> 9),
    # colored by `_lighten` (Theme.mark_color's (30,100,180) blended
    # toward white at a fixed 90/255 mix -- (175,200,228), read off a
    # real render rather than hand-derived, since Color.blend_over's
    # integer-division rounding isn't the thing this test exists to
    # re-verify).
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = effect_scatter(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 135, t.mark_color, "the point itself, dead center")
    _assert_color(c, 220, 128, Color(175, 200, 228), "inside the halo (radius 9) but outside the point (radius 4)")
    _assert_color(c, 220, 100, BG, "well outside the halo -- background")


def test_render_effect_scatter_svg_matches_confirmed_circles() raises:
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var plot = Plot().mark_effect_scatter().encode(x=x, y=y).theme(
        Theme(show_gridlines=False, show_legend=False)
    ).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('<circle cx="220" cy="135" r="9" fill="#afc8e4"/>' in s, "the halo, drawn first")
    assert_true('<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s, "the point itself, drawn on top")


def test_render_point_mark_draws_no_halo() raises:
    # A plain Mark.POINT plot at the same data/theme -- confirms
    # draw_halo really does default off for every mark besides
    # EFFECT_SCATTER, not just that EFFECT_SCATTER turns it on.
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var plot = Plot().mark_point().encode(x=x, y=y).theme(Theme(show_gridlines=False, show_legend=False)).size(400, 300)
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('r="9"' not in s, "no halo circle for a plain Mark.POINT plot")


def test_render_effect_scatter_empty_data_only_fills_background() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    var _hoisted2 = effect_scatter(x, y, width=200, height=150)
    var c = render(_hoisted2)
    _assert_color(c, 100, 75, BG, "no data at all -- background everywhere")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
