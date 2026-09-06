"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.BEESWARM (jittered points),
Mark.VIOLIN (KDE silhouettes, bandwidth and scale_by_count),
Mark.RIDGELINE (overlapping KDE rows), Mark.STREAMGRAPH (centered
stacked bands and smoothing), Mark.BUMP (rank lines), and
Mark.EFFECT_SCATTER (the halo under each point), each raster + SVG.
"""

from _test_helpers import (
    BG,
    _assert_color,
    _assert_near_color,
    _assert_same_canvas,
    _bbox_of_color,
    _column_extent,
    _row_extent,
)
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.vector.svg import SvgCanvas
from dataviz import (
    beeswarm,
    bump,
    effect_scatter,
    ridgeline,
    streamgraph,
    violin,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


# ---------------------------------------------------------------
# from tests/test_beeswarm.mojo
# ---------------------------------------------------------------


def test_render_beeswarm_matches_hand_derived_offsets() raises:
    # 1 category, values [10, 11, 50]: 10 and 11 collide in pixel space, 50
    # stays alone. Canvas 400x300, no gridlines, default margins -> plot
    # area x:[60,380], y:[20,250]; one category spans the band, center
    # 220. y-domain = _data_extent([10,11,50]) = [8, 52], scale -5.2273 ->
    # pixel y 240 (v=10), 234 (v=11), 30 (v=50). point_radius 3.5 rounds
    # to 4, spacing 8: 50's row is alone (offset 0); 11 and 10 are 6px
    # apart, so 11 (sorted first) gets offset 0 and 10 gets +8.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = beeswarm(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c, 228, 240, t.mark_color, "value 10 -- offset +8 (second in its row)"
    )
    _assert_color(
        c, 220, 234, t.mark_color, "value 11 -- offset 0 (first in its row)"
    )
    _assert_color(
        c, 220, 30, t.mark_color, "value 50 -- offset 0 (alone in its row)"
    )
    _assert_color(c, 10, 10, BG, "well outside the plot area -- background")


def test_render_beeswarm_svg_matches_confirmed_circles() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 11.0, 50.0]]
    var plot = (
        Plot()
        .mark_beeswarm()
        .encode_distribution(categories=cats, values=vals)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<circle cx="228" cy="240" r="4" fill="#1e64b4"/>' in s, "value 10"
    )
    assert_true(
        '<circle cx="220" cy="234" r="4" fill="#1e64b4"/>' in s, "value 11"
    )
    assert_true(
        '<circle cx="220" cy="30" r="4" fill="#1e64b4"/>' in s, "value 50"
    )


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


def test_render_beeswarm_raises_on_no_data() raises:
    # #206: encode_distribution() now raises immediately on empty
    # categories, before beeswarm() even returns a Plot to render.
    var cats = List[String]()
    var vals = List[List[Float64]]()
    with assert_raises():
        _ = beeswarm(cats, vals, width=200, height=150)


# ---------------------------------------------------------------
# from tests/test_violin.mojo
# ---------------------------------------------------------------


def test_render_violin_matches_hand_derived_silhouette() raises:
    # 1 category, values [1,2,3,4,5]: symmetric, so the KDE is symmetric
    # around 3.0. Canvas 400x300, no gridlines, default margins -> plot
    # area x:[60,380], y:[20,250]. One category spans the band: step=320,
    # bandwidth=256, center=220, half_width = 256*0.4 = 102.4. Silverman's
    # bandwidth for this data is ~0.9225 (python3). Sampled at 30 points
    # across [1,5]: the two middle samples (y ~= 3.07) map to the full
    # half_width, pixel y 131/139, x 117.6/322.4; the end samples (y=1.0
    # and 5.0) taper to ~73.68, pixel y 240/30, x 146.32/293.68.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = violin(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c,
        220,
        135,
        t.mark_color,
        "near the peak (y~=3), dead center -- well inside",
    )
    _assert_color(
        c,
        280,
        235,
        t.mark_color,
        "near the bottom edge (y=1), still inside the ~74px half-width there",
    )
    _assert_color(
        c,
        300,
        235,
        BG,
        (
            "near the bottom edge (y=1), past the ~74px half-width there --"
            " outside"
        ),
    )
    _assert_color(
        c, 10, 10, BG, "well outside the whole plot area -- background"
    )


def test_render_violin_svg_matches_confirmed_path_points() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var plot = (
        Plot()
        .mark_violin()
        .encode_distribution(categories=cats, values=vals)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M293.678,240.000' in s,
        "the path's first point -- right edge at y=1.0 (bottom)",
    )
    assert_true(
        "322.400,139.000 L322.400,131.000" in s,
        "the flat peak-density plateau, at its full half_width",
    )
    assert_true(
        "L146.322,240.000 Z" in s,
        "the path's last point before closing -- left edge at y=1.0",
    )


def test_render_violin_identical_values_does_not_raise() raises:
    # Every value the same (7.0): std is 0.0, the case _kde_bandwidth
    # falls back to a fixed bandwidth. The silhouette collapses to zero
    # height, so this only confirms it renders and background remains away
    # from that row.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[7.0, 7.0, 7.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted2 = violin(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted2)
    _assert_color(c, 220, 20, BG, "well above the collapsed row -- background")


def test_render_violin_custom_bandwidth_widens_the_tapered_edge() raises:
    # The claim is comparative -- a larger bandwidth spreads every
    # Gaussian further, so the silhouette is wider where it tapers -- so
    # measure both renders rather than pinning the pixel the default
    # happens to leave empty. The tail row is taken from the default
    # silhouette's own extent (90% of the way down it), so no margin,
    # padding or supersample setting is baked in. There the default
    # measures 174px against bandwidth=3.0's 182px, and a deliberately
    # narrow bandwidth=0.3 collapses to 108px, so the comparison has
    # room either way.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var default_plot = violin(cats, vals, theme=t, width=400, height=300)
    var wide_plot = violin(
        cats, vals, bandwidth=3.0, theme=t, width=400, height=300
    )
    var default_c = render(default_plot)
    var wide_c = render(wide_plot)

    var silhouette = _bbox_of_color(default_c, t.mark_color)
    assert_true(silhouette.found, "the default silhouette is drawn")
    var tail_y = silhouette.y0 + (silhouette.height() * 9) // 10
    var default_tail = _row_extent(default_c, tail_y, t.mark_color)
    var wide_tail = _row_extent(wide_c, tail_y, t.mark_color)
    assert_true(
        wide_tail.width() > default_tail.width(),
        "bandwidth=3.0 widens the tail: "
        + String(wide_tail.width())
        + "px vs the default's "
        + String(default_tail.width())
        + "px at row "
        + String(tail_y),
    )


def test_render_violin_explicit_zero_bandwidth_matches_default() raises:
    # bandwidth=0.0 explicitly passed must produce the same output as
    # omitting it, exercising the sentinel check itself. The claim is
    # that the two renders are identical, so compare them to each other:
    # sampling a few pixels of the silhouette tests something weaker and
    # goes stale the moment the layout moves.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var explicit = violin(
        cats, vals, bandwidth=0.0, theme=t, width=400, height=300
    )
    var omitted = violin(cats, vals, theme=t, width=400, height=300)
    _assert_same_canvas(
        render(explicit), render(omitted), "violin bandwidth=0.0 vs omitted"
    )


def test_render_violin_scale_by_count_narrows_the_smaller_category() raises:
    # Two categories: "A" (5 values, [1..5]) sets max_n=5 with
    # count_factor 1.0; "B" (2 values, [2,4]) gets count_factor sqrt(2/5)
    # ~= 0.6325 under scale_by_count=True. Canvas 400x300, no gridlines:
    # 2-category OrdinalScale step=160, bandwidth=128, "B"'s center 300.
    # At row y=135, "B"'s silhouette spans x=[256,343] by default and
    # x=[272,327] narrowed (ratio 55/87 ~= 0.632). Point (260,135) is
    # inside the default silhouette but outside the narrowed one.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted5 = violin(
        cats, vals, scale_by_count=True, theme=t, width=400, height=300
    )
    var c = render(_hoisted5)
    _assert_color(
        c, 260, 135, BG, "scale_by_count narrows category B -- now outside"
    )
    _assert_color(
        c,
        300,
        135,
        t.mark_color,
        "category B's center, still inside even narrowed",
    )


def test_render_violin_scale_by_count_false_matches_default() raises:
    # scale_by_count=False explicitly passed must produce the same output
    # as omitting it.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted6 = violin(
        cats, vals, scale_by_count=False, theme=t, width=400, height=300
    )
    var c = render(_hoisted6)
    _assert_color(
        c,
        260,
        135,
        t.mark_color,
        "unscaled -- category B still reaches its full half-width here",
    )


def test_render_violin_raises_on_negative_bandwidth() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0]]
    with assert_raises():
        var _hoisted7 = violin(
            cats, vals, bandwidth=-1.0, width=200, height=150
        )
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


def test_render_violin_raises_on_no_data() raises:
    # #206: see test_render_beeswarm_raises_on_no_data above.
    var cats = List[String]()
    var vals = List[List[Float64]]()
    with assert_raises():
        _ = violin(cats, vals, width=200, height=150)


# ---------------------------------------------------------------
# from tests/test_ridgeline.mojo
# ---------------------------------------------------------------


def test_render_ridgeline_matches_hand_derived_rows() raises:
    # 3 categories, all [1,2,3,4,5] (the violin test's distribution, so the
    # KDE math is cross-checked there); this is about the horizontal-frame
    # geometry. Canvas 400x300, no gridlines, default margins -> plot area
    # x:[60,380], y:[20,250]. _draw_horizontal_categorical_axis_frame with
    # padding=0.0: step=(250-20)/3=76.667, bandwidth=step, row baselines
    # A=96.667, B=173.333, C=250.0.
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0, 5.0],
        [1.0, 2.0, 3.0, 4.0, 5.0],
        [1.0, 2.0, 3.0, 4.0, 5.0],
    ]
    var t = Theme(show_gridlines=False)
    var _hoisted1 = ridgeline(cats, vals, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(
        c,
        220,
        50,
        t.mark_color,
        "inside row A -- between its peak (~-3) and baseline (96.667)",
    )
    _assert_color(
        c,
        220,
        98,
        t.mark_color,
        (
            "just below row A's baseline (96.667) -- covered by row B's peak"
            " rising up to ~73.667, the edge-to-edge overlap padding=0.0 gives"
        ),
    )
    _assert_color(
        c, 10, 10, BG, "well outside the whole plot area -- background"
    )


def test_render_ridgeline_svg_matches_confirmed_path_points() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vals: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0, 5.0],
        [1.0, 2.0, 3.0, 4.0, 5.0],
        [1.0, 2.0, 3.0, 4.0, 5.0],
    ]
    var plot = (
        Plot()
        .mark_ridgeline()
        .encode_distribution(categories=cats, values=vals)
        .theme(Theme(show_gridlines=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M75.000,96.667 L75.000,24.955' in s,
        "row A's baseline and left-edge rise",
    )
    assert_true(
        "225.000,-3.000" in s, "row A's peak, at its two middle samples"
    )
    assert_true(
        "L365.000,96.667 Z" in s, "row A's closing edge, back down to baseline"
    )
    assert_true(
        '<path d="M75.000,173.333 L75.000,101.622' in s,
        "row B's baseline and left-edge rise",
    )
    # Row C's baseline (250) lands on the bottom axis line, so it is pulled
    # to 249 before its samples are computed, shifting its whole curve up
    # 1px (178.289 -> 177.289). Rows A/B's baselines are interior
    # boundaries and unaffected.
    assert_true(
        '<path d="M75.000,249.000 L75.000,177.289' in s,
        "row C's baseline and left-edge rise",
    )


def test_render_ridgeline_custom_bandwidth_widens_the_tail() raises:
    # As for violin: measure the curve's height at its tail column in
    # both renders instead of pinning the pixel the default leaves
    # empty. The column is the default curve's own left edge, so it
    # follows the layout rather than naming it. It has to be the edge
    # and not a fraction in: the default ramps up to its full height
    # within about 28 columns, and past that both renders saturate and
    # the measurement stops discriminating.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var default_plot = ridgeline(cats, vals, theme=t, width=400, height=300)
    var wide_plot = ridgeline(
        cats, vals, bandwidth=3.0, theme=t, width=400, height=300
    )
    var default_c = render(default_plot)
    var wide_c = render(wide_plot)

    var curve = _bbox_of_color(default_c, t.mark_color)
    assert_true(curve.found, "the default curve is drawn")
    var tail_x = curve.x0
    var default_tail = _column_extent(default_c, tail_x, t.mark_color)
    var wide_tail = _column_extent(wide_c, tail_x, t.mark_color)
    assert_true(
        wide_tail.height() > default_tail.height(),
        "bandwidth=3.0 lifts the tail: "
        + String(wide_tail.height())
        + "px vs the default's "
        + String(default_tail.height())
        + "px at column "
        + String(tail_x),
    )


def test_render_ridgeline_explicit_zero_bandwidth_matches_default() raises:
    # bandwidth=0.0 explicitly passed must produce the same output as
    # omitting it.
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var explicit = ridgeline(
        cats, vals, bandwidth=0.0, theme=t, width=400, height=300
    )
    var omitted = ridgeline(cats, vals, theme=t, width=400, height=300)
    _assert_same_canvas(
        render(explicit), render(omitted), "ridgeline bandwidth=0.0 vs omitted"
    )


def test_render_ridgeline_scale_by_count_shortens_the_smaller_row() raises:
    # Two categories: "A" (5 values, count_factor 1.0) and "B" (2 values,
    # count_factor sqrt(2/5) ~= 0.6325). Canvas 400x300, no gridlines: row
    # B's baseline is y=250 and row A (baseline y=135) never draws below
    # its baseline, so any filled pixel at y > 135 is row B's. At x=220,
    # row B's top sits at y=136 by default and y=169 under
    # scale_by_count=True; (220, 150) is inside the default rise but above
    # the narrowed one.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted4 = ridgeline(
        cats, vals, scale_by_count=True, theme=t, width=400, height=300
    )
    var c = render(_hoisted4)
    _assert_color(
        c,
        220,
        150,
        BG,
        "scale_by_count shortens row B's rise -- now above its curve",
    )
    _assert_color(
        c,
        220,
        200,
        t.mark_color,
        "still inside row B's (shorter) curve, closer to its baseline",
    )


def test_render_ridgeline_scale_by_count_false_matches_default() raises:
    # scale_by_count=False explicitly passed must produce the same output
    # as omitting it.
    var cats: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0]]
    var t = Theme(show_gridlines=False)
    var _hoisted5 = ridgeline(
        cats, vals, scale_by_count=False, theme=t, width=400, height=300
    )
    var c = render(_hoisted5)
    _assert_color(
        c, 220, 150, t.mark_color, "unscaled -- row B still reaches this height"
    )


def test_render_ridgeline_raises_on_negative_bandwidth() raises:
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0]]
    with assert_raises():
        var _hoisted6 = ridgeline(
            cats, vals, bandwidth=-1.0, width=200, height=150
        )
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


def test_render_ridgeline_raises_on_no_data() raises:
    # #206: see test_render_beeswarm_raises_on_no_data above.
    var cats = List[String]()
    var vals = List[List[Float64]]()
    with assert_raises():
        _ = ridgeline(cats, vals, width=200, height=150)


# ---------------------------------------------------------------
# from tests/test_streamgraph.mojo
# ---------------------------------------------------------------


def test_render_streamgraph_matches_hand_derived_bands() raises:
    # 2 categories, 2 series, every value 10, so each category totals 20
    # and the picture is uniform left to right. Canvas 400x300, no
    # gridlines, no legend: plot area x:[60,380], y:[20,250] (max_total=20,
    # pad 1.0, symmetric domain [-11,11]); x centers 140/300. A's stack:
    # baseline -10, top 0 -> band y:[135,240]. B's stack: 0 to 10 -> band
    # y:[30,135]. Sampled at each band's midpoint.
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = (
        Plot()
        .mark_streamgraph()
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(c, 220, 187, palette[0], "A's band, midpoint -- y:[135,240]")
    _assert_color(c, 220, 82, palette[1], "B's band, midpoint -- y:[30,135]")
    _assert_color(
        c, 10, 10, BG, "well outside the whole plot area -- background"
    )


def test_render_streamgraph_svg_matches_confirmed_paths() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var plot = (
        Plot()
        .mark_streamgraph()
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M140.000,135.000 L300.000,135.000 L300.000,240.000'
        ' L140.000,240.000 Z" fill="#1f77b4"/>'
        in s,
        "A's band",
    )
    assert_true(
        '<path d="M140.000,30.000 L300.000,30.000 L300.000,135.000'
        ' L140.000,135.000 Z" fill="#ff7f0e"/>'
        in s,
        "B's band",
    )


def test_render_streamgraph_svg_smoothing_matches_confirmed_cubic_path() raises:
    # 3 categories, 2 series: A=[10,15,8], B=[5,10,12]; totals [15,25,20],
    # max_total=25, pad=1.25, symmetric y-domain [-13.75,13.75]. Canvas
    # 400x300, no gridlines, no legend: plot area x:[60,380], y:[20,250], x
    # centers 113.333/220.000/326.667. A's stack: bottom=[-7.5,-12.5,-10],
    # top=[2.5,2.5,-2] -> via LinearScale(-13.75,13.75,250,20) rounded:
    # top_py=[114,114,152], bottom_py=[198,240,219]. Control points below
    # come from the Catmull-Rom tangent formula over those rounded
    # positions.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 15.0, 8.0], [5.0, 10.0, 12.0]]
    var plot = (
        Plot()
        .mark_streamgraph()
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(
            Theme(show_gridlines=False, show_legend=False, line_smoothing=1.0)
        )
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M113.333,114.000 C131.111,114.000 184.444,107.667'
        " 220.000,114.000 C255.556,120.333 308.889,145.667 326.667,152.000"
        " L326.667,219.000 C308.889,222.500 255.556,243.500 220.000,240.000"
        ' C184.444,236.500 131.111,205.000 113.333,198.000 Z" fill="#1f77b4"'
        "/>"
        in s,
        (
            "A's band: smoothed top edge, straight cap, smoothed bottom edge"
            " (reversed), straight cap via close()"
        ),
    )


def test_render_streamgraph_raises_on_out_of_range_smoothing() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var plot = (
            Plot()
            .mark_streamgraph()
            .encode_grouped_bar(
                categories=cats, series_names=names, values=vals
            )
            .theme(Theme(line_smoothing=-0.1))
            .size(200, 150)
        )
        _ = render(plot)
    with assert_raises():
        var plot = (
            Plot()
            .mark_streamgraph()
            .encode_grouped_bar(
                categories=cats, series_names=names, values=vals
            )
            .theme(Theme(line_smoothing=1.1))
            .size(200, 150)
        )
        _ = render(plot)


def test_streamgraph_defaults_to_smoothed_bands() raises:
    # streamgraph()'s default (smoothing=0.6) curves the bands: a cubic
    # command appears in the SVG.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 15.0, 8.0]]
    var _hoisted4 = streamgraph(cats, names, vals, width=400, height=300)
    var svg = render_svg(_hoisted4)
    assert_true(
        " C" in svg.to_string(),
        "default streamgraph() output includes a cubic curve command",
    )


def test_streamgraph_smoothing_zero_reproduces_straight_bands() raises:
    # smoothing=0.0 gives straight bands, byte-identical to a hand-built
    # Plot with Theme's default line_smoothing.
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var _hoisted5 = streamgraph(
        cats,
        names,
        vals,
        theme=Theme(show_gridlines=False, show_legend=False),
        smoothing=0.0,
        width=400,
        height=300,
    )
    var svg = render_svg(_hoisted5)
    var s = svg.to_string()
    assert_true(
        '<path d="M140.000,135.000 L300.000,135.000 L300.000,240.000'
        ' L140.000,240.000 Z" fill="#1f77b4"/>'
        in s,
        "A's band, straight",
    )
    assert_true(
        '<path d="M140.000,30.000 L300.000,30.000 L300.000,135.000'
        ' L140.000,135.000 Z" fill="#ff7f0e"/>'
        in s,
        "B's band, straight",
    )


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


def test_render_streamgraph_raises_on_no_data() raises:
    # #206: _validate_grouped_bar_series now raises on empty categories at
    # render() time (encode_grouped_bar() itself still defers length
    # checking, per its own docstring).
    var cats = List[String]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted3 = streamgraph(cats, names, vals, width=200, height=150)
        _ = render(_hoisted3)


# ---------------------------------------------------------------
# from tests/test_bump.mojo
# ---------------------------------------------------------------


def test_render_bump_matches_hand_derived_rank_lines() raises:
    # 2 categories, 2 series: A=[10, 30], B=[20, 5]. At X, B outranks A (A
    # rank 2, B rank 1); at Y, A outranks B. Canvas 400x300, default
    # margins -> plot area x:[60,380], y:[20,250]; OrdinalScale centers 140
    # (X) and 300 (Y). _bump_rank_pixel(1,2,20,250)=20, (2,2,...)=250: A's
    # line runs (140,250)->(300,20), B's the mirror.
    #
    # Two points per line: the row-250 endpoint and an interior point a
    # third of the way along (the row-20 endpoint doesn't reliably get ink
    # at the plot's top boundary). Interior points land exactly on the
    # palette color; the endpoints, at each line's rounded cap, only land
    # close (_assert_near_color).
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 30.0], [20.0, 5.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = (
        Plot()
        .mark_bump()
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
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
    var plot = (
        Plot()
        .mark_bump()
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<path d="M140.000,250.000 L300.000,20.000"' in s,
        "A's line: rank 2 at X, rank 1 at Y",
    )
    assert_true(
        '<path d="M140.000,20.000 L300.000,250.000"' in s,
        "B's line: rank 1 at X, rank 2 at Y",
    )
    assert_true('text-anchor="end">1<' in s, "the rank-1 tick label")
    assert_true('text-anchor="end">2<' in s, "the rank-2 tick label")


def test_render_bump_raises_on_mismatched_series_names_and_values_length() raises:
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[1.0, 2.0]]
    with assert_raises():
        var _hoisted1 = bump(cats, names, vals, width=200, height=150)
        _ = render(_hoisted1)


def test_render_bump_raises_on_no_data() raises:
    # #206: see test_render_streamgraph_raises_on_no_data above.
    var cats = List[String]()
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [List[Float64]()]
    with assert_raises():
        var _hoisted2 = bump(cats, names, vals, width=200, height=150)
        _ = render(_hoisted2)


# ---------------------------------------------------------------
# from tests/test_effect_scatter.mojo
# ---------------------------------------------------------------


def test_render_effect_scatter_matches_hand_derived_halo_and_point() raises:
    # One point (5, 5): both axes pad to [4, 6], canvas 400x300, default
    # margins -> plot area x:[60,380], y:[20,250], so the point is at
    # (220, 135). point_radius 3.5 rounds to 4; the halo is 2.2x that (8.8
    # -> 9), colored by _lighten (mark_color (30,100,180) blended toward
    # white at 90/255 -> (175,200,228), read off a real render since
    # Color.blend_over's rounding isn't what this test checks).
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var t = Theme(show_gridlines=False, show_legend=False)
    var _hoisted1 = effect_scatter(x, y, theme=t, width=400, height=300)
    var c = render(_hoisted1)

    _assert_color(c, 220, 135, t.mark_color, "the point itself, dead center")
    _assert_color(
        c,
        220,
        128,
        Color(175, 200, 228),
        "inside the halo (radius 9) but outside the point (radius 4)",
    )
    _assert_color(c, 220, 100, BG, "well outside the halo -- background")


def test_render_effect_scatter_svg_matches_confirmed_circles() raises:
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var plot = (
        Plot()
        .mark_effect_scatter()
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true(
        '<circle cx="220" cy="135" r="9" fill="#afc8e4"/>' in s,
        "the halo, drawn first",
    )
    assert_true(
        '<circle cx="220" cy="135" r="4" fill="#1e64b4"/>' in s,
        "the point itself, drawn on top",
    )


def test_render_point_mark_draws_no_halo() raises:
    # A plain Mark.POINT plot at the same data/theme draws no halo.
    var x: List[Float64] = [5.0]
    var y: List[Float64] = [5.0]
    var plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var svg = render_svg(plot)
    var s = svg.to_string()
    assert_true('r="9"' not in s, "no halo circle for a plain Mark.POINT plot")


def test_render_effect_scatter_raises_on_no_data() raises:
    # #206: Plot.encode()'s empty-data check (_require_non_empty) now
    # raises at render() time for Mark.EFFECT_SCATTER same as Mark.POINT.
    var x = List[Float64]()
    var y = List[Float64]()
    with assert_raises():
        var _hoisted2 = effect_scatter(x, y, width=200, height=150)
        _ = render(_hoisted2)


def test_diagnostic_ridgeline_render_determinism() raises:
    """TEMPORARY diagnostic for #298, not a behavioral test.

    Renders the same chart three times in one process and reports which
    of them differ. On Linux all three agree; the macOS CI job is what
    this is for. Reading the output there:

      1 differs, 2 == 3  -> first-render initialization state
      all three differ   -> per-run nondeterminism
      all three agree    -> the difference is tied to the call, not the
                            render, which would contradict the fact that
                            bandwidth=0.0 and omitted take the identical
                            branch

    Delete once #298 is diagnosed.
    """
    var cats: List[String] = ["A"]
    var vals: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0, 5.0]]
    var t = Theme(show_gridlines=False)
    var r1 = render(ridgeline(cats, vals, theme=t, width=400, height=300))
    var r2 = render(ridgeline(cats, vals, theme=t, width=400, height=300))
    var r3 = render(ridgeline(cats, vals, theme=t, width=400, height=300))

    def count(a: Canvas, b: Canvas) -> Int:
        var n = 0
        for y in range(a.height):
            for x in range(a.width):
                var p = a.get_pixel(x, y)
                var q = b.get_pixel(x, y)
                if p.r != q.r or p.g != q.g or p.b != q.b:
                    n += 1
        return n

    var d12 = count(r1, r2)
    var d23 = count(r2, r3)
    var d13 = count(r1, r3)
    print("#298 diagnostic: 1v2=", d12, " 2v3=", d23, " 1v3=", d13)
    var p1 = r1.get_pixel(99, 0)
    var p2 = r2.get_pixel(99, 0)
    var p3 = r3.get_pixel(99, 0)
    print(
        "#298 pixel(99,0): r1=",
        p1.r,
        p1.g,
        p1.b,
        " r2=",
        p2.r,
        p2.g,
        p2.b,
        " r3=",
        p3.r,
        p3.g,
        p3.b,
    )
    # Always passes: this reports, it does not gate.
    assert_true(True, "diagnostic")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
