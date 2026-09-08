"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers Mark.BEESWARM (jittered points),
Mark.VIOLIN (KDE silhouettes, bandwidth and scale_by_count),
Mark.RIDGELINE (overlapping KDE rows), Mark.ECDF (the empirical
cumulative staircase), Mark.STREAMGRAPH (centered
stacked bands and smoothing), Mark.BUMP (rank lines), and
Mark.EFFECT_SCATTER (the halo under each point), each raster + SVG.
"""

from _test_helpers import (
    BG,
    _assert_color,
    _assert_near_color,
    _assert_same_canvas,
    _bbox_of_color,
    _bbox_of_color_in,
    _column_extent,
    _row_extent,
)
from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.vector.svg import SvgCanvas
from dataviz import (
    StepStyle,
    ecdf,
    kdeplot,
    rugplot,
    beeswarm,
    bump,
    effect_scatter,
    ridgeline,
    stacked_area,
    streamgraph,
    violin,
)
from dataviz.color_scale import default_categorical_palette
from dataviz.frame import _draw_continuous_axis_frame
from dataviz.ecdf import _ecdf_points, _ecdf_step_style
from dataviz.kde import _kde_curve
from dataviz.legend import _LegendLayout
from dataviz.layers import render_layers
from dataviz.plot import Plot, render, render_svg
from dataviz.scale import LinearScale
from dataviz.stack_baseline import StackBaseline
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
        '<path d="M293.678,239.545' in s,
        "the path's first point -- right edge at y=1.0 (bottom)",
    )
    assert_true(
        "322.400,138.605 L322.400,131.395" in s,
        "the flat peak-density plateau, at its full half_width",
    )
    assert_true(
        "L146.322,239.545 Z" in s,
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


def test_kde_curve_peaks_where_the_data_concentrates() raises:
    """The estimate is the one violins already draw, so this checks it
    reaches the chart with the right shape rather than re-testing the
    estimator: a bimodal sample must produce two peaks with a dip.
    """
    var v = List[Float64]()
    for _ in range(12):
        v.append(10.0)
    for _ in range(12):
        v.append(30.0)

    var curve = _kde_curve(v, 0.0)
    var xs = curve[0].copy()
    var ys = curve[1].copy()

    # the density at each mode must exceed the density midway between
    var mid_index = len(xs) // 2
    var peak_low = 0.0
    var peak_high = 0.0
    for i in range(len(xs)):
        if xs[i] < 20.0 and ys[i] > peak_low:
            peak_low = ys[i]
        if xs[i] > 20.0 and ys[i] > peak_high:
            peak_high = ys[i]
    assert_true(
        peak_low > ys[mid_index] and peak_high > ys[mid_index],
        "both modes rise above the dip between them",
    )
    assert_true(
        peak_low > 0.0 and peak_high > 0.0, "both modes have real density"
    )


def test_render_kde_draws_a_curve_and_rug_draws_one_tick_per_value() raises:
    """`Mark.KDE` strokes a path; `Mark.RUG` draws a tick per
    observation, countable as runs of ink along its baseline row."""
    var v: List[Float64] = [1.0, 2.0, 3.0, 7.0, 8.0, 9.0]

    var svg = render_svg(kdeplot(v, width=320, height=240)).to_string()
    assert_true(
        svg.count('fill="none"') > 0, "the density curve is a stroked path"
    )

    var c = render(rugplot(v, width=400, height=260))
    var t = Theme()
    var row = c.height - 1
    var best = 0
    for yy in range(c.height):
        var n = 0
        for xx in range(c.width):
            var p = c.get_pixel(xx, yy)
            if (
                p.r == t.mark_color.r
                and p.g == t.mark_color.g
                and p.b == t.mark_color.b
            ):
                n += 1
        if n > best:
            best = n
            row = yy
    var runs = 0
    var inside = False
    for xx in range(c.width):
        var p = c.get_pixel(xx, row)
        var ink = (
            p.r == t.mark_color.r
            and p.g == t.mark_color.g
            and p.b == t.mark_color.b
        )
        if ink and not inside:
            runs += 1
        inside = ink
    assert_equal(runs, len(v), "one rug tick per observation")


def test_kde_rug_is_visible_over_a_filled_curve() raises:
    """Ticks under a fill are cut in the background color, because
    mark_color on mark_color would be invisible -- the rug exists to show
    where the sample actually is, so it has to be legible.

    Asserted as "the rug changes the picture" rather than by pinning tick
    colors: the ticks are antialiased, so their pixels are blends rather
    than any exact color.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 7.0, 8.0, 9.0]
    var without = render(
        kdeplot(v, fill=True, rug=False, width=400, height=260)
    )
    var with_rug = render(
        kdeplot(v, fill=True, rug=True, width=400, height=260)
    )
    var differing = 0
    for yy in range(without.height):
        for xx in range(without.width):
            var a = without.get_pixel(xx, yy)
            var b = with_rug.get_pixel(xx, yy)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                differing += 1
    assert_true(
        differing > 0,
        (
            "rug=True is visible over the fill (differing pixels: "
            + String(differing)
            + ")"
        ),
    )


def _count_in_region(
    c: Canvas, x0: Int, y0: Int, x1: Int, y1: Int, color: Color
) -> Int:
    """How many pixels in the inclusive box match `color`."""
    var n = 0
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            var p = c.get_pixel(x, y)
            if p.r == color.r and p.g == color.g and p.b == color.b:
                n += 1
    return n


def _count_not_color(
    c: Canvas, x0: Int, y0: Int, x1: Int, y1: Int, color: Color
) -> Int:
    """How many pixels in the inclusive box are anything but `color`."""
    var area = (x1 - x0 + 1) * (y1 - y0 + 1)
    return area - _count_in_region(c, x0, y0, x1, y1, color)


def _widest_row_of_color(c: Canvas, color: Color) -> Int:
    """The most pixels of `color` any single row holds.

    "Is there a horizontal gridline anywhere?" without depending on
    which row a particular scale put it on: a horizontal gridline spans
    the plot rect, so it dwarfs the handful of pixels the vertical
    gridlines contribute to a row they merely cross.
    """
    var best = 0
    for y in range(c.height):
        var n = 0
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == color.r and p.g == color.g and p.b == color.b:
                n += 1
        if n > best:
            best = n
    return best


def _canvases_differ(a: Canvas, b: Canvas) -> Int:
    """How many pixels of `a` and `b` disagree.

    `_assert_same_canvas`'s inverse, for a claim that two renders must
    *not* match. Returns the count rather than a Bool so a failure
    message can say how far apart they were.
    """
    if a.width != b.width or a.height != b.height:
        return -1
    var n = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                n += 1
    return n


def test_rug_draws_no_y_axis_while_kde_keeps_one() raises:
    """#378: a rug has no y dimension, so it draws no y-axis at all --
    no axis line, tick marks, tick labels or horizontal gridlines. The
    `LinearScale(0, 1, ...)` `_render_rug` passes exists only because
    `_draw_continuous_axis_frame` demands a y-domain; drawn out, it
    captioned the chart `0.0 0.2 ... 1.0`, a density that is not there.

    `Mark.KDE` is rendered alongside as the control. It shares the same
    frame function and its y-axis is real (it is the density), so every
    number that goes to zero for the rug must stay put for the KDE --
    which is what says the `y_axis_visible` flag did not leak into the
    default path.

    Every expected value below was read off an actual 400x260 render
    (saved as a .bmp and parsed byte by byte), not derived from the
    margin arithmetic:

                                  rug before  rug after   kde
        non-background, x < 60           626          0   762
        axis_color in column 60          190          0   190
        widest gridline row              319          4   313

    Column 60 is `plot_x0` under the stock `margin_left=60`, so it is
    where the y-axis line stood; x < 60 is the gutter its tick marks and
    labels lived in. The rug's residual 4 is the three vertical
    gridlines plus the plot edge crossing that row -- those stay, since
    the x-axis is the rug's one real dimension. Asserted as thresholds
    on the KDE side (a font metric could move a label a pixel) but as an
    exact 0 on the rug side, where the claim is that nothing is drawn.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 7.0, 8.0, 9.0]
    var t = Theme()
    var rug = render(rugplot(v, width=400, height=260))
    var kde = render(kdeplot(v, width=400, height=260))

    var bg = t.background
    assert_equal(
        _count_not_color(rug, 0, 0, 59, rug.height - 1, bg),
        0,
        "a rugplot draws nothing in the y-tick-label gutter (was 626)",
    )
    assert_true(
        _count_not_color(kde, 0, 0, 59, kde.height - 1, bg) > 400,
        "a kdeplot still labels its y-axis in that gutter",
    )

    var axis = t.axis_color
    assert_equal(
        _column_extent(rug, 60, axis).found,
        False,
        "a rugplot draws no y-axis line at plot_x0 (was 190px of it)",
    )
    assert_true(
        _column_extent(kde, 60, axis).height() > 150,
        "a kdeplot still draws its y-axis line at plot_x0",
    )

    var grid = t.gridline_color
    assert_true(
        _widest_row_of_color(rug, grid) < 20,
        (
            "a rugplot draws no horizontal gridline -- only the vertical"
            " ones crossing a row (widest row: "
            + String(_widest_row_of_color(rug, grid))
            + ")"
        ),
    )
    assert_true(
        _widest_row_of_color(kde, grid) > 200,
        "a kdeplot still draws horizontal gridlines across its plot rect",
    )


def test_rug_reclaims_the_y_tick_label_margin() raises:
    """#378 step 1's second half: with no y tick labels to fit, the left
    margin must stop being sized to them.

    `plot_x0` is `max(theme.margin_left, label_width + tick + gap +
    buffer)`. The second term is 34px for a rug's `0.0`-`1.0` labels
    (measured), so before this change every `margin_left` under 34
    clamped to 34 and the rug reserved a gutter for labels it drew --
    `margin_left=8` and `margin_left=16` rendered byte-identically. With
    the labels gone the dynamic term collapses to 0 and `margin_left`
    alone decides, so the two renders must now differ, and the tighter
    one must be the wider chart.

    Stated as a difference between two margins rather than as an
    absolute `plot_x0`, so it does not re-encode the 34 it is about. The
    stock `margin_left=60` already exceeds 34, which is why this is
    invisible on a default-themed chart and needs its own test.

    Measured on the 400x260 render: the rug's ink spans 338px at
    `margin_left=8` and 330px at `margin_left=16` -- the 8px the margins
    differ by. Before the change both were 314px.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 7.0, 8.0, 9.0]
    var tight = rugplot(v, theme=Theme(margin_left=8), width=400, height=260)
    var less_tight = rugplot(
        v, theme=Theme(margin_left=16), width=400, height=260
    )
    var a = render(tight)
    var b = render(less_tight)

    assert_true(
        _canvases_differ(a, b) > 0,
        (
            "margin_left below the old label-fitting floor now moves the"
            " plot rect (the two renders were byte-identical)"
        ),
    )

    var mark = Theme().mark_color
    var wide = _bbox_of_color(a, mark).width()
    var narrow = _bbox_of_color(b, mark).width()
    assert_true(
        wide > narrow,
        (
            "the tighter margin gives the wider rug ("
            + String(wide)
            + " vs "
            + String(narrow)
            + ")"
        ),
    )


def test_kde_still_clamps_its_left_margin_to_its_tick_labels() raises:
    """The control for the test above, and the compatibility claim in
    its own right: `Mark.KDE` keeps a visible y-axis, so its left margin
    is still sized to fit the tick labels and still clamps.

    `margin_left=8` and `margin_left=16` therefore stay byte-identical
    for a KDE -- both lose to the label-fitting term -- exactly as they
    did before `y_axis_visible` existed. If the flag ever leaked into
    the default path this is the assertion that catches it, because the
    KDE would start tracking `margin_left` the way the rug now does.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 7.0, 8.0, 9.0]
    var a = render(
        kdeplot(v, theme=Theme(margin_left=8), width=400, height=260)
    )
    var b = render(
        kdeplot(v, theme=Theme(margin_left=16), width=400, height=260)
    )
    _assert_same_canvas(a, b, "kdeplot margin_left=8 vs 16")


def test_continuous_frame_keeps_the_y_axis_by_default() raises:
    """`_draw_continuous_axis_frame`'s `y_axis_visible` defaults to
    `True`, which is what lets every continuous mark but `Mark.RUG` go
    on calling it unchanged (#378).

    Drawn at the seam rather than through a mark, because the claim is
    about the parameter and not about any one chart: omitting the
    keyword must be pixel-for-pixel the same as passing `True`, and
    passing `False` must actually change something -- a flag that
    defaults correctly but does nothing would satisfy the first half on
    its own.

    Straight onto a `Canvas` rather than via `render()`, so the
    comparison is of what this function draws and not of the
    supersample-then-downsample pass around it.
    """
    var t = Theme()
    var cache = FontCache()
    var x = LinearScale(0.0, 10.0, 0.0, 1.0)
    var y = LinearScale(0.0, 1.0, 0.0, 1.0)
    var bg = t.background

    var omitted = Canvas(400, 260, bg)
    _ = _draw_continuous_axis_frame(
        omitted, x, y, t, _LegendLayout(), 0, 0, 400, 260, cache=cache
    )

    var explicit = Canvas(400, 260, bg)
    _ = _draw_continuous_axis_frame(
        explicit,
        x,
        y,
        t,
        _LegendLayout(),
        0,
        0,
        400,
        260,
        y_axis_visible=True,
        cache=cache,
    )
    _assert_same_canvas(
        omitted, explicit, "y_axis_visible omitted vs explicitly True"
    )

    var hidden = Canvas(400, 260, bg)
    _ = _draw_continuous_axis_frame(
        hidden,
        x,
        y,
        t,
        _LegendLayout(),
        0,
        0,
        400,
        260,
        y_axis_visible=False,
        cache=cache,
    )
    assert_true(
        _canvases_differ(omitted, hidden) > 0,
        "y_axis_visible=False draws a different frame",
    )


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


def test_render_ridgeline_overlapping_rows_stay_distinguishable() raises:
    """Where one row's curve rises into the row above, the boundary
    between them must still be visible.

    Rows overlap by design (`ridgeline_overlap`, 1.3 row heights) and
    every row is filled with the same `Theme.mark_color`, so without an
    outline two overlapping ridges merge into one shape and the reader
    cannot tell where one distribution ends and the next begins -- the
    same failure the sunburst had between its rings.

    Asserted as a property rather than by pinning the outline's pixels:
    a vertical scan through the overlap must cross background between
    two runs of fill. A single merged blob gives one run and no gap.
    """
    var cats: List[String] = ["low", "high"]
    # "high" is concentrated well above "low", so its peak rises into
    # low's row and the two must overlap somewhere.
    var vals: List[List[Float64]] = [
        [10.0, 11.0, 12.0, 13.0, 14.0, 15.0],
        [12.0, 12.0, 12.0, 12.0, 12.0, 12.0],
    ]
    var t = Theme(show_gridlines=False)
    var _hoisted_ro = ridgeline(cats, vals, theme=t, width=420, height=300)
    var c = render(_hoisted_ro)

    var found_gap = False
    for x in range(c.width):
        var runs = 0
        var in_fill = False
        var saw_bg_between = False
        var pending_bg = False
        for y in range(c.height):
            var p = c.get_pixel(x, y)
            var is_fill = (
                p.r == t.mark_color.r
                and p.g == t.mark_color.g
                and p.b == t.mark_color.b
            )
            if is_fill and not in_fill:
                runs += 1
                if pending_bg and runs > 1:
                    saw_bg_between = True
                in_fill = True
            elif not is_fill:
                if in_fill:
                    pending_bg = True
                in_fill = False
        if runs >= 2 and saw_bg_between:
            found_gap = True
            break
    assert_true(
        found_gap,
        (
            "some column crosses two separate ridges with background"
            " between them, so the overlapping rows are distinguishable"
        ),
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
        '<path d="M74.545,96.667 L74.545,24.955' in s,
        "row A's baseline and left-edge rise",
    )
    assert_true(
        "214.984,-3.000" in s, "row A's peak, at its two middle samples"
    )
    assert_true(
        "L365.455,96.667 Z" in s, "row A's closing edge, back down to baseline"
    )
    assert_true(
        '<path d="M74.545,173.333 L74.545,101.622' in s,
        "row B's baseline and left-edge rise",
    )
    # Row C's baseline (250) lands on the bottom axis line, so it is pulled
    # to 249 before its samples are computed, shifting its whole curve up
    # 1px (178.289 -> 177.289). Rows A/B's baselines are interior
    # boundaries and unaffected.
    assert_true(
        '<path d="M74.545,249.000 L74.545,177.289' in s,
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
        '<path d="M140.000,135.000 L300.000,135.000 L300.000,239.545'
        ' L140.000,239.545 Z" fill="#1f77b4"/>'
        in s,
        "A's band",
    )
    assert_true(
        '<path d="M140.000,30.455 L300.000,30.455 L300.000,135.000'
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
        '<path d="M113.333,114.091 C131.111,114.091 184.444,107.818'
        " 220.000,114.091 C255.556,120.364 308.889,145.455 326.667,151.727"
        " L326.667,218.636 C308.889,222.121 255.556,243.030 220.000,239.545"
        ' C184.444,236.061 131.111,204.697 113.333,197.727 Z" fill="#1f77b4"'
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
        '<path d="M140.000,135.000 L300.000,135.000 L300.000,239.545'
        ' L140.000,239.545 Z" fill="#1f77b4"/>'
        in s,
        "A's band, straight",
    )
    assert_true(
        '<path d="M140.000,30.455 L300.000,30.455 L300.000,135.000'
        ' L140.000,135.000 Z" fill="#ff7f0e"/>'
        in s,
        "B's band, straight",
    )


def test_render_stacked_area_matches_hand_derived_bands() raises:
    # The same data and canvas as
    # test_render_streamgraph_matches_hand_derived_bands, with
    # StackBaseline.ZERO: 2 categories, 2 series, every value 10. What
    # changes is the domain. Zero baseline means the y-extent comes from
    # the per-category totals (both 20) through _zero_baseline_y_extent,
    # which pads only the non-zero end -> [0, 21], so zero is an exact
    # axis endpoint rather than the padded [-11, 11] of the wiggle case.
    #
    # Plot area y:[20,250], 230px over 21 units. A's stack runs 0 -> 10,
    # so its band is y:[140.5,250]; B's runs 10 -> 20, y:[31,140.5].
    # Sampled at each band's midpoint. Compare with the wiggle case's
    # y:[135,240] and y:[30,135] -- the option genuinely moves the bands.
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 10.0], [10.0, 10.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = (
        Plot()
        .mark_streamgraph(baseline=StackBaseline.ZERO)
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
    var c = render(plot)

    var palette = default_categorical_palette()
    _assert_color(
        c, 220, 195, palette[0], "A's band, midpoint -- y:[140.5,250]"
    )
    _assert_color(c, 220, 86, palette[1], "B's band, midpoint -- y:[31,140.5]")
    _assert_color(
        c, 10, 10, BG, "well outside the whole plot area -- background"
    )

    # The two rows above are inside both layouts' bands, so on their own
    # they would pass under WIGGLE too. These two are the ones that
    # actually pin the baseline, measured against a WIGGLE render of the
    # same data:
    #   y=137  ZERO -> B (its band reaches down to 140.5)
    #          WIGGLE -> A (its band starts at 135)
    #   y=245  ZERO -> A (its band runs to the axis at 250)
    #          WIGGLE -> background (the stack stops at 240)
    _assert_color(
        c, 220, 137, palette[1], "still B at y=137; under WIGGLE this is A"
    )
    _assert_color(
        c,
        220,
        245,
        palette[0],
        "A reaches the axis at y=245; under WIGGLE this is background",
    )


def test_render_stacked_area_bottom_is_flat_and_top_tracks_the_total() raises:
    # The property that makes a stacked area readable and a streamgraph
    # not: the bottom series sits on a straight axis, so the top edge is
    # the running total measured from it.
    #
    # 3 categories with totals 10, 20 and 40 (max_total 40, +5% pad ->
    # domain [0,42] over y:[20,250]). Category centers are x = 113, 220
    # and 326.
    var cats: List[String] = ["P", "Q", "R"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[4.0, 8.0, 16.0], [6.0, 12.0, 24.0]]
    var plot = (
        Plot()
        .mark_streamgraph(baseline=StackBaseline.ZERO)
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(Theme(show_gridlines=False, show_legend=False))
        .size(400, 300)
    )
    var c = render(plot)
    var palette = default_categorical_palette()

    # Flat bottom: the lowest row of the bottom series is the same all
    # the way across, regardless of how tall that category's stack is.
    for x in [120, 150, 220, 280, 326]:
        assert_equal(
            _column_extent(c, x, palette[0]).y1,
            249,
            "bottom series rests on the axis at x=" + String(x),
        )

    # Top edge: the stack's height above that flat bottom is proportional
    # to the category's total. Measured from the topmost row of the top
    # series, which is one row inside the antialiased edge, so the
    # heights come out as 107 and 216 rather than exactly 108 and 219 --
    # the ratio is what carries the claim, not the absolute rows.
    var height_q = 249 - _column_extent(c, 220, palette[1]).y0
    var height_r = 249 - _column_extent(c, 326, palette[1]).y0
    assert_equal(height_q, 107, "stack height at Q, total 20")
    assert_equal(height_r, 216, "stack height at R, total 40")
    assert_true(
        abs(Float64(height_r) / Float64(height_q) - 2.0) < 0.05,
        "R's total is twice Q's, so its stack is twice as tall -- got "
        + String(Float64(height_r) / Float64(height_q)),
    )


def test_stacked_area_defaults_to_straight_bands() raises:
    # streamgraph() defaults to smoothing=0.6 because it is meant to look
    # like flowing water. stacked_area() defaults to 0.0 because it is
    # meant to be read, and curving between categories invents values
    # that are not in the data. Same data as
    # test_streamgraph_defaults_to_smoothed_bands, opposite expectation.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A"]
    var vals: List[List[Float64]] = [[10.0, 15.0, 8.0]]
    var _hoisted_sa = stacked_area(cats, names, vals, width=400, height=300)
    var svg = render_svg(_hoisted_sa)
    assert_true(
        " C" not in svg.to_string(),
        "default stacked_area() output has no cubic curve command",
    )


def test_streamgraph_baseline_defaults_to_wiggle() raises:
    # The compatibility claim: mark_streamgraph() with no baseline must
    # render exactly what it did before #337 existed. Byte-identical to
    # the explicit WIGGLE spelling.
    var cats: List[String] = ["X", "Y"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 12.0], [10.0, 8.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var implicit = (
        Plot()
        .mark_streamgraph()
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
    var explicit = (
        Plot()
        .mark_streamgraph(baseline=StackBaseline.WIGGLE)
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
    _assert_same_canvas(
        render(implicit), render(explicit), "default baseline is WIGGLE"
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
    # (220, 135). point_radius 3.5 rounds to 4; the halo is 2.2x that
    # (8.8, drawn as a sub-pixel radius), colored by _lighten (mark_color (30,100,180) blended toward
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
        '<circle cx="220.000" cy="135.000" r="8.800" fill="#afc8e4"/>' in s,
        "the halo, drawn first",
    )
    assert_true(
        '<circle cx="220.000" cy="135.000" r="4.000" fill="#1e64b4"/>' in s,
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


# ---------------------------------------------------------------
# Mark.STREAMGRAPH step interpolation (#403)
# ---------------------------------------------------------------

# Two series over three categories, on a 400x300 canvas with no
# gridlines and no legend. Plot area x:[60,380] over 3 bands, so the
# category centers are 113.333 / 220.000 / 326.667. Every expected
# number below was read off a real render_svg() of this data, not
# recomputed here.
comptime _STEP_CATS = 3


def _step_stack_plot(step: StepStyle) raises -> Plot:
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 20.0, 15.0], [5.0, 8.0, 12.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    return stacked_area(
        cats, names, vals, theme=t, step=step, width=400, height=300
    )


def _band_paths(svg: String) -> List[String]:
    """Each `<path d="...">`'s `d` attribute, in draw order -- one per
    band for a streamgraph with no gridlines and no legend.
    """
    var out = List[String]()
    var i = svg.find(' d="')
    while i >= 0:
        var s = i + 4
        var j = svg.find('"', s)
        out.append(String(svg[byte=s:j]))
        i = svg.find(' d="', j)
    return out^


def _path_points(d: String) -> List[String]:
    """`d`'s vertices as `"x,y"` strings, in order, from a path built of
    `M`/`L` commands and a closing `Z` (a stepped band has no curves).
    """
    var out = List[String]()
    for tok in d.split(" "):
        if tok == "Z" or tok.byte_length() == 0:
            continue
        out.append(String(tok[byte=1:]))
    return out^


def test_stacked_area_step_matches_confirmed_paths() raises:
    # Read off a real render_svg() run, pasted verbatim. Band A is the
    # bottom series (#1f77b4), band B the one stacked on it (#ff7f0e).
    #
    # PRE/POST emit 2n-1 = 5 points per edge and MID 2n = 6, so a band
    # is 10 or 12 points; NONE is 3 per edge. The counts are part of
    # what is asserted here: they are what tells a staircase from a
    # straight edge that happens to pass through the same samples.
    var pre = render_svg(_step_stack_plot(StepStyle.PRE)).to_string()
    assert_true(
        '<path d="M113.333,171.769 L113.333,93.537 L220.000,93.537'
        " L220.000,132.653 L326.667,132.653 L326.667,250.000"
        " L220.000,250.000 L220.000,250.000 L113.333,250.000"
        ' L113.333,250.000 Z" fill="#1f77b4"/>'
        in pre,
        "PRE, band A",
    )
    assert_true(
        '<path d="M113.333,132.653 L113.333,30.952 L220.000,30.952'
        " L220.000,38.776 L326.667,38.776 L326.667,132.653"
        " L220.000,132.653 L220.000,93.537 L113.333,93.537"
        ' L113.333,171.769 Z" fill="#ff7f0e"/>'
        in pre,
        "PRE, band B",
    )

    var mid = render_svg(_step_stack_plot(StepStyle.MID)).to_string()
    assert_true(
        '<path d="M113.333,171.769 L166.667,171.769 L166.667,93.537'
        " L273.333,93.537 L273.333,132.653 L326.667,132.653"
        " L326.667,250.000 L273.333,250.000 L273.333,250.000"
        ' L166.667,250.000 L166.667,250.000 L113.333,250.000 Z"'
        ' fill="#1f77b4"/>'
        in mid,
        "MID, band A",
    )

    var post = render_svg(_step_stack_plot(StepStyle.POST)).to_string()
    assert_true(
        '<path d="M113.333,171.769 L220.000,171.769 L220.000,93.537'
        " L326.667,93.537 L326.667,132.653 L326.667,250.000"
        " L326.667,250.000 L220.000,250.000 L220.000,250.000"
        ' L113.333,250.000 Z" fill="#1f77b4"/>'
        in post,
        "POST, band A",
    )
    assert_true(
        '<path d="M113.333,132.653 L220.000,132.653 L220.000,30.952'
        " L326.667,30.952 L326.667,38.776 L326.667,132.653"
        " L326.667,93.537 L220.000,93.537 L220.000,171.769"
        ' L113.333,171.769 Z" fill="#ff7f0e"/>'
        in post,
        "POST, band B",
    )

    # The default is untouched: three points per edge, no risers.
    var none = render_svg(_step_stack_plot(StepStyle.NONE)).to_string()
    assert_true(
        '<path d="M113.333,171.769 L220.000,93.537 L326.667,132.653'
        ' L326.667,250.000 L220.000,250.000 L113.333,250.000 Z"'
        ' fill="#1f77b4"/>'
        in none,
        "NONE, band A -- unchanged by #403",
    )


def test_stacked_area_step_tiles_each_band_onto_the_one_below() raises:
    # The property a reversed-edge bug breaks, and the reason #403 warns
    # about one. Band B's bottom edge *is* band A's top edge -- the same
    # `running[i]` values -- so the two must trace the same staircase,
    # and band B's is traversed backwards. Asserted structurally rather
    # than by eye: split each band's points in half (top edge, then
    # bottom edge reversed) and check band B's bottom, re-reversed, is
    # band A's top point for point.
    #
    # This is what discriminates. Stepping the already-reversed bottom
    # edge, which is the obvious implementation, produces the mirrored
    # staircase: the risers land on the other x of each pair, band B's
    # bottom stops matching band A's top, and every style below fails
    # here while the point counts stay right.
    for style in [StepStyle.PRE, StepStyle.MID, StepStyle.POST]:
        var label = String(style.name())
        var paths = _band_paths(render_svg(_step_stack_plot(style)).to_string())
        assert_equal(len(paths), 2, label + ": two bands")

        var a = _path_points(paths[0])
        var b = _path_points(paths[1])
        assert_equal(len(a), len(b), label + ": both bands have as many points")
        var half = len(a) // 2
        assert_equal(
            2 * half, len(a), label + ": a band is two equal-length edges"
        )

        for k in range(half):
            assert_equal(
                b[len(b) - 1 - k],
                a[k],
                label
                + ": band B's bottom vertex "
                + String(k)
                + " sits on band A's top vertex",
            )

        # The two caps stay straight, which for a vertical cap means the
        # edge starts and ends on a category center: the first and last
        # top-edge vertices share an x with the last and first
        # bottom-edge ones. Stepping must not have moved either end.
        var a_top_first_x = a[0].split(",")[0]
        var a_top_last_x = a[half - 1].split(",")[0]
        var a_bot_first_x = a[half].split(",")[0]
        var a_bot_last_x = a[len(a) - 1].split(",")[0]
        assert_equal(
            String(a_top_last_x),
            String(a_bot_first_x),
            label + ": the closing cap at the last category is vertical",
        )
        assert_equal(
            String(a_top_first_x),
            String(a_bot_last_x),
            label + ": the closing cap at the first category is vertical",
        )
        assert_equal(
            String(a_top_first_x), "113.333", label + ": cap at center(0)"
        )
        assert_equal(
            String(a_top_last_x), "326.667", label + ": cap at center(2)"
        )


def test_stacked_area_step_leaves_no_background_between_bands() raises:
    # The raster half of the tiling property. A mismatched pair of edges
    # opens a wedge of background between two bands, and a wedge is
    # exactly what an SVG path assertion can miss if the numbers happen
    # to look plausible.
    #
    # Scanned down three columns, between the first and last
    # band-colored pixel: every pixel in between must belong to a band.
    # Interior only -- the two ends of the run are the antialiased
    # boundary against the background and are not asserted.
    #
    # The columns sit strictly inside the band, not on the category
    # centers: a band spans only x 113.333 to 326.667 (center(0) to
    # center(2)), so a column at 113 is outside it under every style and
    # would find no band at all. 150 and 320 land on a plateau in all
    # three styles and 250 falls between MID's two midpoints.
    var palette = default_categorical_palette()
    for style in [StepStyle.PRE, StepStyle.MID, StepStyle.POST]:
        var c = render(_step_stack_plot(style))
        for cx in [150, 250, 320]:
            var first = -1
            var last = -1
            for y in range(20, 250):
                var p = c.get_pixel(cx, y)
                var is_band = (
                    p.r == palette[0].r
                    and p.g == palette[0].g
                    and p.b == palette[0].b
                ) or (
                    p.r == palette[1].r
                    and p.g == palette[1].g
                    and p.b == palette[1].b
                )
                if is_band:
                    if first < 0:
                        first = y
                    last = y
            assert_true(
                first >= 0 and last > first,
                String(style.name())
                + ": column "
                + String(cx)
                + " crosses both bands",
            )
            for y in range(first + 1, last):
                var p = c.get_pixel(cx, y)
                assert_true(
                    not (p.r == BG.r and p.g == BG.g and p.b == BG.b),
                    String(style.name())
                    + ": no background at ("
                    + String(cx)
                    + ", "
                    + String(y)
                    + ") between the bands",
                )


def test_stacked_area_step_and_smoothing_are_mutually_exclusive() raises:
    # #336/#384's rule, extended to Mark.STREAMGRAPH. The message must
    # name mark_streamgraph, not mark_line or mark_area: a caller who
    # never touched either would otherwise be sent to the wrong setter.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 20.0, 15.0], [5.0, 8.0, 12.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    with assert_raises(contains="Plot.mark_streamgraph(step=...)"):
        _ = render_svg(
            stacked_area(
                cats,
                names,
                vals,
                theme=t,
                smoothing=0.6,
                step=StepStyle.POST,
                width=400,
                height=300,
            )
        )

    # And smoothing=0.0 with a step is fine, so the raise above is the
    # conflict and not the step itself.
    _ = render_svg(
        stacked_area(
            cats,
            names,
            vals,
            theme=t,
            smoothing=0.0,
            step=StepStyle.POST,
            width=400,
            height=300,
        )
    )


def test_mark_streamgraph_step_reaches_the_wiggle_baseline_too() raises:
    # #403 keeps `step` off streamgraph()'s own signature because that
    # function sets smoothing=0.6, which a step conflicts with. The
    # builder still exposes it, and a WIGGLE stack whose theme leaves
    # smoothing at 0.0 steps like any other.
    #
    # The assertion that discriminates is the *count*: a WIGGLE band
    # over three categories is 6 vertices unstepped and 10 stepped, so
    # this cannot pass against a plot that quietly ignored `step`.
    var cats: List[String] = ["X", "Y", "Z"]
    var names: List[String] = ["A", "B"]
    var vals: List[List[Float64]] = [[10.0, 20.0, 15.0], [5.0, 8.0, 12.0]]
    var t = Theme(show_gridlines=False, show_legend=False)
    var plot = (
        Plot()
        .mark_streamgraph(baseline=StackBaseline.WIGGLE, step=StepStyle.POST)
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
    var paths = _band_paths(render_svg(plot).to_string())
    assert_equal(len(paths), 2, "two bands")
    for p in paths:
        assert_equal(
            len(_path_points(p)), 10, "a stepped WIGGLE band is 2 x (2n-1)"
        )

    var straight = (
        Plot()
        .mark_streamgraph(baseline=StackBaseline.WIGGLE)
        .encode_grouped_bar(categories=cats, series_names=names, values=vals)
        .theme(t)
        .size(400, 300)
    )
    for p in _band_paths(render_svg(straight).to_string()):
        assert_equal(
            len(_path_points(p)), 6, "an unstepped WIGGLE band is 2 x n"
        )


# ---------------------------------------------------------------
# Mark.ECDF (#338)
# ---------------------------------------------------------------


def test_ecdf_points_are_the_hand_derived_staircase() raises:
    """`[3, 1, 2]` steps to 1/3 at 1, 2/3 at 2 and 1 at 3, whatever order
    it arrives in -- the whole computation, checked against the
    definition rather than against a render.

    The vertex list is `(1, 0) (1, 1/3) (2, 2/3) (3, 1)`: the leading
    `(min, 0)` is what makes the first step a riser instead of the curve
    starting partway up, and the last y is exactly `1.0`, not
    `0.999...`, because the last cumulative count is `n`.

    Byte-for-byte what matplotlib 3.11.1's `ax.ecdf([3, 1, 2])` puts in
    its Line2D (`x = [1, 1, 2, 3]`, `y = [0, 1/3, 2/3, 1]`), which is
    where these numbers were checked.
    """
    var v: List[Float64] = [3.0, 1.0, 2.0]
    var curve = _ecdf_points(v)

    assert_equal(len(curve.x), 4, "one vertex per value, plus the (min, 0)")
    assert_equal(len(curve.y), 4, "x and y stay the same length")

    assert_equal(curve.x[0], 1.0, "the curve starts at the smallest value")
    assert_equal(curve.y[0], 0.0, "and starts at zero")
    assert_equal(curve.x[1], 1.0, "the first riser is at the smallest value")
    assert_equal(curve.y[1], 1.0 / 3.0, "F(1) = 1/3")
    assert_equal(curve.x[2], 2.0)
    assert_equal(curve.y[2], 2.0 / 3.0, "F(2) = 2/3")
    assert_equal(curve.x[3], 3.0)
    assert_equal(curve.y[3], 1.0, "F(max) is exactly 1, not 1 - epsilon")


def test_ecdf_ties_share_one_step_of_k_over_n() raises:
    """The one thing likely to be wrong. `k` observations at the same
    value are one step of `k/n`, not `k` steps of `1/n` stacked at one x.

    `[1, 1, 2]` is the minimal case: two vertices past the leading
    `(1, 0)`, with `F(1) = 2/3`. A per-observation vertex list would
    have four; a run-walk that kept the run's *first* cumulative count
    -- which is what matplotlib 3.11.1's own `compress=True` does --
    would say `F(1) = 1/3`.

    `[1, 1, 1, 2, 5, 5]` is the case that separates the two failures
    further apart, and where matplotlib's `compress=True` visibly breaks:
    it reports `y = [0, 1/6, 2/3, 5/6]`, so the curve both understates
    `F(1)` and never reaches 1. The right answer is `F(1) = 1/2`,
    `F(2) = 2/3`, `F(5) = 1`.
    """
    var pair: List[Float64] = [1.0, 1.0, 2.0]
    var small = _ecdf_points(pair)
    assert_equal(len(small.x), 3, "a tie is one vertex, not one per value")
    assert_equal(small.y[0], 0.0)
    assert_equal(small.x[1], 1.0)
    assert_equal(small.y[1], 2.0 / 3.0, "the tie's step is 2/3, not 1/3")
    assert_equal(small.x[2], 2.0)
    assert_equal(small.y[2], 1.0)

    var runs: List[Float64] = [5.0, 1.0, 2.0, 1.0, 5.0, 1.0]
    var curve = _ecdf_points(runs)
    assert_equal(len(curve.x), 4, "three distinct values, plus the (min, 0)")
    assert_equal(curve.y[1], 0.5, "three of six at x = 1")
    assert_equal(curve.x[2], 2.0)
    assert_equal(curve.y[2], 2.0 / 3.0, "four of six at or below x = 2")
    assert_equal(curve.x[3], 5.0)
    assert_equal(curve.y[3], 1.0, "the last step still reaches exactly 1")


def test_ecdf_complementary_is_one_minus_the_ecdf() raises:
    """`complementary=True` is the survival curve `1 - F(x)`, falling
    from 1 to 0, with the *last* x repeated instead of the first so the
    final drop lands on the largest observation.

    `[3, 1, 2]` gives `x = [1, 2, 3, 3]`, `y = [1, 2/3, 1/3, 0]` --
    again exactly matplotlib's `ax.ecdf(..., complementary=True)`. Note
    the y values are not the forward curve reversed: reading this list
    backwards would give `0, 1/3, 2/3, 1` against x `3, 3, 2, 1`, which
    is a different chart.
    """
    var v: List[Float64] = [3.0, 1.0, 2.0]
    var curve = _ecdf_points(v, complementary=True)

    # Subtracted from a Float64 rather than written as the literal
    # `2.0 / 3.0`: Mojo folds float literals at comptime in exact
    # arithmetic, so the literal is the nearest double to 2/3 while
    # `1 - F` is one ulp above it. The complement is defined as the
    # subtraction, and matplotlib computes it the same way
    # (`1 - cum_weights`), so the subtraction is the expectation.
    var one_third = 1.0 / 3.0
    var two_thirds = 2.0 / 3.0

    assert_equal(len(curve.x), 4)
    assert_equal(curve.x[0], 1.0, "starts at the smallest value")
    assert_equal(curve.y[0], 1.0, "where all of the sample is still above")
    assert_equal(
        curve.x[1], 2.0, "the second x is the second value, not the first"
    )
    assert_equal(curve.y[1], 1.0 - one_third)
    assert_equal(curve.x[2], 3.0)
    assert_equal(curve.y[2], 1.0 - two_thirds)
    assert_equal(curve.x[3], 3.0, "the largest value is repeated")
    assert_equal(curve.y[3], 0.0, "and the curve ends at exactly zero")


def test_ecdf_steps_post_and_the_complement_steps_pre() raises:
    """An ECDF is right-continuous: it holds `F(x[i])` from `x[i]` until
    `x[i + 1]` and jumps there, which is `StepStyle.POST` and nothing
    else. `PRE` would draw a left-continuous function and `MID` would
    put each jump halfway between two observations, at an x where
    nothing was observed.

    Asserted on the choice itself as well as on pixels (below), because
    a wrong style still draws a plausible-looking staircase.
    """
    assert_true(
        _ecdf_step_style(False) == StepStyle.POST,
        "F(x) holds until the next observation, then jumps",
    )
    assert_true(
        _ecdf_step_style(True) == StepStyle.PRE,
        "1 - F(x) drops at the observation it passes",
    )


def test_render_ecdf_plateaus_land_on_the_hand_computed_rows() raises:
    """The staircase drawn, checked against arithmetic done by hand.

    `ecdf([1, 2, 3, 4])` at 400x300 lays out into the plot rect
    `(60, 20)-(380, 250)` (measured from the render). The x-domain is
    `_data_extent`'s 5% padding around `[1, 4]`, i.e. `[0.85, 4.15]`, so
    `x = 1` is at `60 + 0.15/3.3*320 = 74.5` and `x = 2` at `171.5`. The
    y-domain is exactly `[0, 1]`, so `F` maps to `250 - F*230`:
    `0.25 -> 192.5`, `0.5 -> 135.0`, `0.75 -> 77.5`.

    Columns 100/160 sit between `x = 1` and `x = 2`, and both must draw
    `F(1) = 0.25`. That is what discriminates the step style: `PRE`
    would put `F(2) = 0.5` (row 135) across that whole interval, and
    `MID` would put the riser at their midpoint, column 123, so column
    100 would read 0.25 and column 160 would read 0.5.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var c = render(ecdf(v, width=400, height=300))
    var mark = Theme().mark_color

    var left = _column_extent(c, 100, mark)
    assert_true(left.found, "the first plateau is drawn")
    assert_equal(left.y0, 192, "F = 0.25 is centered on row 192.5")
    assert_equal(left.y1, 193)

    var still_left = _column_extent(c, 160, mark)
    assert_equal(
        still_left.y0, 192, "the plateau holds all the way to the next x"
    )
    assert_equal(still_left.y1, 193)

    var middle = _column_extent(c, 220, mark)
    assert_equal(middle.y0, 135, "F = 0.5 is centered on row 135")
    assert_equal(middle.y1, 135)

    var right = _column_extent(c, 340, mark)
    assert_equal(right.y0, 77, "F = 0.75 is centered on row 77.5")
    assert_equal(right.y1, 78)


def test_render_ecdf_spans_exactly_zero_to_one() raises:
    """The y-domain is the fixed `[0, 1]`, not the drawn values padded:
    the riser at the smallest observation reaches the bottom of the plot
    rect and the one at the largest reaches the top.

    Padding the domain the way every other continuous mark does would
    caption the axis with proportions above 1 and below 0, which do not
    exist -- and would pull both ends of the curve visibly inward:
    `_data_extent`'s 5% on `[0, 1]` gives `[-0.05, 1.05]`, putting
    `F = 1` at row 30 and `F = 0` at row 240 instead of 20 and 250. The
    rows asserted below are nine and ten off that, so the two cases
    cannot be confused.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var c = render(ecdf(v, width=400, height=300))
    var mark = Theme().mark_color

    # The two risers' endpoints sit exactly on the rect's top and bottom
    # (rows 20 and 250), so those two rows are only half covered by a
    # butt-capped stroke and come out blended; the outermost *exactly*
    # mark-colored rows are the ones just inside, 21 and 249.
    var box = _bbox_of_color(c, mark)
    assert_true(box.found, "the curve is drawn")
    assert_equal(box.y0, 21, "F = 1 lands on the top of the plot rect")
    assert_equal(box.y1, 249, "F = 0 lands on the bottom of the plot rect")


def test_render_ecdf_draws_only_over_the_data_range() raises:
    """The curve stops at `min(values)` and `max(values)`. Running it out
    to the frame edges would draw a flat run at 0 to the left and at 1 to
    the right, asserting the distribution is bounded there -- which the
    sample does not say.

    The 5% padding `_data_extent` adds is what makes this visible: there
    are 14 blank columns inside the plot rect on each side, and both must
    stay blank while the middle does not.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var c = render(ecdf(v, width=400, height=300))
    var mark = Theme().mark_color

    var left_pad = _bbox_of_color_in(c, mark, 61, 20, 73, 250)
    assert_true(
        not left_pad.found,
        "nothing is drawn left of the smallest observation",
    )
    var right_pad = _bbox_of_color_in(c, mark, 367, 20, 379, 250)
    assert_true(
        not right_pad.found,
        "nothing is drawn right of the largest observation",
    )
    var inside = _bbox_of_color_in(c, mark, 80, 20, 360, 250)
    assert_true(inside.found, "the curve itself is drawn between them")


def test_render_ecdf_complementary_mirrors_the_staircase() raises:
    """`complementary=True` on the same data is the same three plateaus
    reflected about `y = 0.5`: 0.75 where the forward curve had 0.25, and
    the reverse.

    Rendered rather than only computed because the complement also
    changes the step style (`PRE`), and the pair of changes has to land
    as one mirrored picture -- flipping only the values would put the
    plateaus half a step out of place.
    """
    var v: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var c = render(ecdf(v, complementary=True, width=400, height=300))
    var mark = Theme().mark_color

    var left = _column_extent(c, 100, mark)
    assert_equal(left.y0, 77, "1 - F(1) = 0.75, the forward curve's last row")
    assert_equal(left.y1, 78)
    var middle = _column_extent(c, 220, mark)
    assert_equal(middle.y0, 135, "0.5 is its own mirror")
    assert_equal(middle.y1, 135)
    var right = _column_extent(c, 340, mark)
    assert_equal(right.y0, 192, "1 - F(3) = 0.25")
    assert_equal(right.y1, 193)


def test_render_ecdf_raises_without_observations() raises:
    """Both ways of arriving with nothing to draw: an empty column, which
    `encode_ecdf()` rejects on the spot, and a `Mark.ECDF` plot that was
    never encoded at all, which is only visible at render time and would
    otherwise index into an empty list.
    """
    with assert_raises():
        _ = ecdf(List[Float64](), width=200, height=150)
    with assert_raises():
        _ = render(Plot().mark_ecdf().size(200, 150))


def test_mark_kde_without_encode_kde_raises_instead_of_aborting() raises:
    """#439: `_kde_observations` reached for `values[0]` before checking
    that the outer list had any column at all, so a `Mark.KDE` plot with
    no `encode_kde()` hit an out-of-bounds assert.

    That is not a worse error message -- it **aborts the process**. No
    traceback into the caller's code, nothing an `except` can catch, and
    in a batch job it takes down every chart after it too. The guard has
    to come before the subscript.

    `assert_raises` is the whole assertion: it can only pass if the
    failure is catchable, which is exactly what was broken.
    """
    with assert_raises():
        _ = render(Plot().mark_kde().size(200, 150))


def test_mark_rug_without_encode_kde_raises_instead_of_aborting() raises:
    """`Mark.RUG` reads the same observations through the same helper, so
    it aborted the same way."""
    with assert_raises():
        _ = render(Plot().mark_rug().size(200, 150))


def test_a_layered_kde_without_data_raises_instead_of_aborting() raises:
    """The layered path calls `_kde_observations` in its first pass, to
    collect each layer's domain contribution before the shared frame is
    drawn -- so it reached the bad subscript earlier than the standalone
    render did, not later."""
    var plots: List[Plot] = [Plot().mark_kde().size(200, 150)]
    with assert_raises():
        _ = render_layers(plots)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
