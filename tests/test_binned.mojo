"""The binned marks: histogram(), hist2d() and hexbin().

One module rather than 3: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from canvas.color import Color
from dataviz.core.tooltips import Tooltips
from dataviz import histogram, kdeplot
from dataviz.binned.hexbin import _HexBins, _hexbin_bins, hexbin
from dataviz.binned.hist2d import _hist2d_counts, hist2d
from dataviz.binned.histogram import (
    BinRule,
    HistStat,
    HistogramBins,
    bin_edges,
    uniform_bin_edges,
)
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.plot import (
    Plot,
    render,
    render_facets,
    render_layers_svg,
    render_svg,
)
from _test_helpers import (
    _assert_same_canvas,
    _attr_values,
    _bbox_of_color,
    _count_color,
    _count_tag,
    _drawn,
)


# ==== from test_histogram_mark.mojo ====
# Tests for `Mark.HISTOGRAM` (#435): one rectangle per bin at numeric
# x positions, with a separator between adjacent nonempty bins, and the
# `stepfilled` form that keeps the staircase.


def _theme() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def _is(p: Color, c: Color) -> Bool:
    return p.r == c.r and p.g == c.g and p.b == c.b


def test_histogram_is_the_rect_mark_by_default_and_area_when_stepfilled() raises:
    var data: List[Float64] = [0.5, 1.5, 1.5, 2.5]
    assert_true(histogram(data, bins=3)._mark == Mark.HISTOGRAM)
    assert_true(histogram(data, bins=3, stepfilled=True)._mark == Mark.AREA)


def test_svg_draws_one_rect_per_nonempty_bin_plus_separators() raises:
    # Counts [1, 2, 4]: three bin rects, two separators (both neighbors
    # nonempty at both boundaries), and the background rect.
    var data: List[Float64] = [0.5, 1.2, 1.8, 2.1, 2.3, 2.7, 3.0]
    var s = render_svg(
        histogram(
            data,
            edges=uniform_bin_edges(0.0, 3.0, 3),
            theme=_theme(),
            width=400,
            height=300,
        )
    ).to_string()
    assert_equal(_count_tag(_drawn(s), "rect"), 1 + 3 + 2)


def test_an_empty_bin_draws_no_rect_and_no_separator() raises:
    # Counts [1, 0, 1]: the empty middle bin is nothing, and its risers
    # are already boundaries, so no separator either side of it.
    var data: List[Float64] = [0.5, 2.5]
    var s = render_svg(
        histogram(
            data,
            edges=uniform_bin_edges(0.0, 3.0, 3),
            theme=_theme(),
            width=400,
            height=300,
        )
    ).to_string()
    assert_equal(_count_tag(_drawn(s), "rect"), 1 + 2)


def test_equal_adjacent_bins_are_separated_by_one_edge_colored_column() raises:
    # #435's own case: two bins of count 2 over [0, 1) and [1, 2]. The
    # staircase drew them as one wide bar; here the shared edge at
    # x = 60 + 160 = 220 snaps to the 219.5 boundary and the separator
    # is column 219, the left bin's last, in the edge color. Its
    # neighbors on both sides are the mark color.
    var data: List[Float64] = [0.5, 0.5, 1.5, 1.5]
    var edges = uniform_bin_edges(0.0, 2.0, 2)
    var t = _theme()
    var c = render(histogram(data, edges=edges, theme=t, width=400, height=300))
    assert_true(_is(c.get_pixel(219, 200), t.histogram_edge_color), "separator")
    assert_true(_is(c.get_pixel(218, 200), t.mark_color), "left bin")
    assert_true(_is(c.get_pixel(220, 200), t.mark_color), "right bin")
    # A transparent edge color turns the separator off: the two bins
    # tile with no gap.
    var off = Theme(
        show_gridlines=False, histogram_edge_color=Color(0, 0, 0, 0)
    )
    var c2 = render(
        histogram(data, edges=edges, theme=off, width=400, height=300)
    )
    assert_true(_is(c2.get_pixel(219, 200), off.mark_color), "no separator")


def test_separator_stops_at_the_shorter_neighbor() raises:
    # Counts [1, 4]: the separator runs from the baseline up to the
    # short bin's top only. Above it, column 219 is background -- the
    # tall bin starts at column 220 -- not a white line drawn up the
    # side of the tall bin.
    var data: List[Float64] = [0.5, 1.5, 1.5, 1.5, 1.5]
    var edges = uniform_bin_edges(0.0, 2.0, 2)
    var t = _theme()
    var c = render(histogram(data, edges=edges, theme=t, width=400, height=300))
    # y-domain [0, 4.2] over rows 20..250: count 1 tops near row 195.
    assert_true(_is(c.get_pixel(219, 240), t.histogram_edge_color), "separator")
    assert_true(_is(c.get_pixel(219, 150), t.background), "background above")
    assert_true(_is(c.get_pixel(220, 150), t.mark_color), "tall bin beside it")


def test_stepfilled_keeps_the_staircase() raises:
    var data: List[Float64] = [0.5, 1.2, 1.8, 2.1, 2.3, 2.7, 3.0]
    var s = render_svg(
        histogram(
            data,
            edges=uniform_bin_edges(0.0, 3.0, 3),
            stepfilled=True,
            theme=_theme(),
            width=400,
            height=300,
        )
    ).to_string()
    assert_true(_count_tag(_drawn(s), "path") >= 1, "the staircase is a path")
    assert_equal(_count_tag(_drawn(s), "rect"), 1, "only the background rect")


def test_unequal_bin_widths_draw_proportional_rects() raises:
    # Edges 0, 1, 3, 7: widths 1, 2 and 4 over a 320 px plot area,
    # so the rects are about 46, 91 and 183 px wide, in a 1:2:4 ratio
    # to within the pixel snapping. The categorical encode_binned_categories()
    # would draw them equal, which is the lie #435 names.
    var data: List[Float64] = [0.5, 2.0, 5.0]
    var edges: List[Float64] = [0.0, 1.0, 3.0, 7.0]
    var s = render_svg(
        histogram(data, edges=edges, theme=_theme(), width=400, height=300)
    ).to_string()
    var widths = List[Float64]()
    for w in _attr_values(_drawn(s), "rect", "width"):
        var v = Float64(w)
        # Skip the background (the full canvas) and the 1 px separators.
        if v > 2.0 and v < 350.0:
            widths.append(v)
    assert_equal(len(widths), 3)
    var lo = min(widths[0], min(widths[1], widths[2]))
    var hi = max(widths[0], max(widths[1], widths[2]))
    var mid = widths[0] + widths[1] + widths[2] - lo - hi
    assert_true(abs(mid - 2.0 * lo) <= 2.0, "middle bin is twice the narrow")
    assert_true(abs(hi - 4.0 * lo) <= 3.0, "wide bin is four times the narrow")


def test_encode_histogram_bins_keeps_the_staircase_columns_for_the_domains() raises:
    var edges: List[Float64] = [0.0, 1.0, 2.0]
    var values: List[Float64] = [3.0, 1.0]
    var p = (
        Plot()
        .mark_histogram()
        .encode_histogram_bins(HistogramBins(edges.copy(), values.copy()))
    )
    assert_equal(len(p._continuous.x), 3, "step_x(): every edge")
    assert_equal(
        len(p._continuous.y), 3, "step_y(): values plus the last repeated"
    )
    assert_equal(p._continuous.y[2], 1.0)
    assert_equal(len(p._histogram.edges), 3)
    assert_equal(p._histogram.values[0], 3.0)


def test_dtype_overload_matches_the_float64_path() raises:
    var f: List[Float64] = [1.0, 2.0, 2.0, 3.0, 5.0, 8.0]
    var i: List[Int32] = [1, 2, 2, 3, 5, 8]
    _assert_same_canvas(
        render(histogram(f, bins=4, width=300, height=220)),
        render(histogram(i, bins=4, width=300, height=220)),
        "Int32 histogram matches Float64",
    )


struct _Rect(Copyable, ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64
    var w: Float64
    var h: Float64

    def __init__(out self, x: Float64, y: Float64, w: Float64, h: Float64):
        self.x = x
        self.y = y
        self.w = w
        self.h = h


def _bin_rects(raw: String) raises -> List[_Rect]:
    """Every `<rect>` wider and taller than 2 px that is not the
    background: the bin rects, in document order (bin order).

    Definitions are stripped first: plot-area clipping (#369) puts a
    `<rect>` inside a `<clipPath>`, which is never painted."""
    var svg = _drawn(raw)
    var xs = _attr_values(svg, "rect", "x")
    var ys = _attr_values(svg, "rect", "y")
    var ws = _attr_values(svg, "rect", "width")
    var hs = _attr_values(svg, "rect", "height")
    var out = List[_Rect]()
    for i in range(len(ws)):
        var w = Float64(ws[i])
        var h = Float64(hs[i])
        if w > 2.0 and h > 2.0 and not (w > 250.0 and h > 250.0):
            out.append(_Rect(Float64(xs[i]), Float64(ys[i]), w, h))
    return out^


def test_horizontal_is_the_transpose_of_vertical() raises:
    # A canvas whose plot rect is square (200x200: margins 60/20 across
    # and 20/50 down), so the same bins draw the same pixel lengths
    # either way round: bin i's width when vertical is its height when
    # horizontal, and its height is its width, to the pixel the
    # axis-line pull-off moves. Bin 0 sits at the left when vertical
    # and at the bottom (largest y) when horizontal.
    var data: List[Float64] = [0.5, 1.2, 1.8, 2.1, 2.3, 2.7, 3.0]
    var edges = uniform_bin_edges(0.0, 3.0, 3)
    var v = _bin_rects(
        render_svg(
            histogram(data, edges=edges, theme=_theme(), width=280, height=270)
        ).to_string()
    )
    var h = _bin_rects(
        render_svg(
            histogram(
                data,
                edges=edges,
                horizontal=True,
                theme=_theme(),
                width=280,
                height=270,
            )
        ).to_string()
    )
    assert_equal(len(v), 3)
    assert_equal(len(h), 3)
    for i in range(3):
        assert_true(abs(v[i].w - h[i].h) <= 1.0, "bin width transposes")
        assert_true(abs(v[i].h - h[i].w) <= 1.0, "bin value transposes")
    assert_true(v[0].x < v[1].x and v[1].x < v[2].x, "vertical: left to right")
    assert_true(h[0].y > h[1].y and h[1].y > h[2].y, "horizontal: bottom up")
    # And the values run right from the y-axis: every horizontal bar
    # starts at the same x, one column right of the axis line at 60 --
    # the 60.5 pixel-center boundary, which the SVG backend writes in
    # edge coordinates as 61.
    assert_equal(h[0].x, h[1].x)
    assert_equal(h[0].x, 61.0)


def test_horizontal_separators_are_rows_between_equal_bins() raises:
    # Counts [2, 2] up the y-axis over a 230 px plot height: the shared
    # edge at y = 250 - 115 = 135 snaps to 134.5, and the separator is
    # the lower bin's top row, 135, from the axis to the bar's end.
    var data: List[Float64] = [0.5, 0.5, 1.5, 1.5]
    var edges = uniform_bin_edges(0.0, 2.0, 2)
    var t = _theme()
    var c = render(
        histogram(
            data, edges=edges, horizontal=True, theme=t, width=400, height=300
        )
    )
    assert_true(
        _is(c.get_pixel(150, 135), t.histogram_edge_color), "separator row"
    )
    assert_true(_is(c.get_pixel(150, 134), t.mark_color), "upper bin above it")
    assert_true(_is(c.get_pixel(150, 136), t.mark_color), "lower bin below it")
    assert_true(
        _is(c.get_pixel(60, 200), t.axis_color), "the y-axis line shows"
    )


def test_horizontal_refuses_stepfilled_and_layers() raises:
    var data: List[Float64] = [0.5, 1.5, 2.5]
    with assert_raises(contains="stepfilled=True and horizontal=True"):
        _ = histogram(data, bins=3, horizontal=True, stepfilled=True)
    var plots: List[Plot] = [
        histogram(data, bins=3, horizontal=True, width=300, height=220)
    ]
    with assert_raises(contains="horizontal Mark.HISTOGRAM layer"):
        _ = render_layers_svg(plots)


def test_horizontal_histograms_facet_without_a_forced_y_baseline() raises:
    # Two horizontal panels with a shared y-scale: the shared domain is
    # the bins' range, not zero-baselined -- the bins start at 0.5 here
    # and the panel's bottom tick must be 0.5, not 0.
    var a: List[Float64] = [0.5, 1.2, 1.8, 2.1, 2.3, 2.7, 3.0]
    var b: List[Float64] = [0.6, 0.9, 1.1, 2.9, 3.0, 3.0, 3.0]
    var edges = uniform_bin_edges(0.5, 3.0, 5)
    var plots: List[Plot] = [
        histogram(a, edges=edges, horizontal=True, width=300, height=220),
        histogram(b, edges=edges, horizontal=True, width=300, height=220),
    ]
    var c = render_facets(plots, 2, shared_y_scale=True)
    assert_true(c.width > 0, "renders")


def test_histogram_and_kde_peak_in_the_same_pixel_column() raises:
    # #437's acceptance criterion: a histogram and a KDE on one frame
    # share a numeric x-domain, so a known value lands in the same
    # column in both marks. A sample with a spike at 5.0 puts the
    # tallest bin around 5 and the KDE's peak at 5; the KDE path's
    # highest point (smallest y) must fall inside that bin's rect.
    var data = List[Float64]()
    for i in range(60):
        data.append(1.0 + Float64(i) * 0.15)
    for _ in range(40):
        data.append(5.0)
    var h = histogram(
        data,
        edges=uniform_bin_edges(1.0, 10.0, 18),
        stat=HistStat.DENSITY,
        theme=_theme(),
        width=400,
        height=300,
    )
    var k = kdeplot(data, theme=_theme(), width=400, height=300)
    var plots: List[Plot] = [h^, k^]
    var s = render_layers_svg(plots).to_string()
    var rects = _bin_rects(s)
    var tallest = 0
    for i in range(len(rects)):
        if rects[i].h > rects[tallest].h:
            tallest = i
    # The KDE is the one path: walk "M x,y L x,y ..." for its peak.
    var d = _attr_values(s, "path", "d")[0]
    var peak_x = 0.0
    var peak_y = 1.0e9
    var at = 0
    while at < d.byte_length():
        var ch = d[byte = at : at + 1]
        if ch == "M" or ch == "L":
            var sp = d.find(" ", at + 1)
            if sp < 0:
                sp = d.byte_length()
            var pair = String(d[byte = at + 1 : sp])
            var comma = pair.find(",")
            var x = Float64(String(pair[byte=:comma]))
            var y = Float64(String(pair[byte = comma + 1 :]))
            if y < peak_y:
                peak_y = y
                peak_x = x
            at = sp
        else:
            at += 1
    var r = rects[tallest]
    assert_true(
        peak_x >= r.x and peak_x <= r.x + r.w,
        "the KDE peak at x="
        + String(peak_x)
        + " lies in the tallest bin's rect ["
        + String(r.x)
        + ", "
        + String(r.x + r.w)
        + "]",
    )


# ==== from test_hist2d.mojo ====
# Tests for `Mark.HIST2D` / `hist2d()`: hand-derived counts, the
# boundary rule, empty bins drawn as background, and the overloads.


comptime _LO = Color(0, 0, 255)
comptime _HI = Color(255, 0, 0)
comptime _BG = Color(0, 255, 0)


def _theme_hist2d() -> Theme:
    var stops: List[Color] = [_LO, _HI]
    return Theme(
        background=_BG,
        color_ramp=stops,
        show_gridlines=False,
        show_legend=False,
    )


def test_counts_are_hand_derived_with_the_boundary_rule() raises:
    # x edges [0, 2, 4], y edges [0, 2, 4]. x=2 sits on the shared
    # boundary and goes to the upper bin; (4, 4) is the maximum on both
    # axes and goes to the last bin, not past it.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var ex: List[Float64] = [0.0, 2.0, 4.0]
    var ey: List[Float64] = [0.0, 2.0, 4.0]
    var counts = _hist2d_counts(x, y, ex, ey)
    assert_equal(len(counts), 2)
    assert_equal(len(counts[0]), 2)
    # Row 0 is the bottom band of y: x in [0, 2) holds 0 and 1; x in
    # [2, 4] holds 2 and 3.
    assert_equal(counts[0][0], 2.0)
    assert_equal(counts[0][1], 2.0)
    # Row 1: only (4, 4), in the last column.
    assert_equal(counts[1][0], 0.0)
    assert_equal(counts[1][1], 1.0)


def test_points_outside_the_edges_are_not_counted() raises:
    var x: List[Float64] = [-1.0, 0.5, 9.0, 0.5]
    var y: List[Float64] = [0.5, 0.5, 0.5, 7.0]
    var e: List[Float64] = [0.0, 1.0]
    var counts = _hist2d_counts(x, y, e, e)
    assert_equal(counts[0][0], 1.0, "only (0.5, 0.5) is inside the one cell")


def test_hist2d_bins_each_axis_over_its_own_range() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [10.0, 10.0, 10.0, 10.0, 30.0]
    var p = hist2d(x, y, bins=2)
    assert_equal(len(p._image.x_edges), 3)
    assert_equal(p._image.x_edges[1], 2.0)
    assert_equal(p._image.y_edges[1], 20.0)
    assert_equal(p._image.z[0][0], 2.0)
    assert_equal(p._image.z[1][1], 1.0)
    assert_true(p._image.blank_zero, "empty bins are left undrawn")


def test_empty_bins_draw_as_background_not_the_bottom_of_the_ramp() raises:
    # Counts [[2, 2], [0, 1]]: the bottom row is full (both cells at the
    # ramp's top, red), the top-left cell is empty and the top-right
    # holds one point. The red band's bounding box locates the plot
    # rect: it is the bottom half.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var c = render(
        hist2d(x, y, bins=2, theme=_theme_hist2d(), width=300, height=220)
    )
    var red = _bbox_of_color(c, _HI)
    assert_true(red.found, "the full cells are the top of the ramp")
    var w = red.x1 - red.x0 + 1
    var h = red.y1 - red.y0 + 1
    assert_true(w > 100 and h > 40, "red band is the bottom half of the rect")
    # Center of the top-left cell: background.
    var tl = c.get_pixel(red.x0 + w // 4, red.y0 - h // 2)
    assert_true(_is(tl, _BG), "an empty bin shows the background")
    # Center of the top-right cell: a ramp color that is neither
    # background nor the top of the ramp -- one point of a maximum of
    # two.
    var tr = c.get_pixel(red.x0 + (3 * w) // 4, red.y0 - h // 2)
    assert_true(
        not _is(tr, _BG) and not _is(tr, _HI) and tr.g == 0,
        "a one-count bin is colored between the ramp's ends",
    )


def test_svg_draws_one_rect_per_nonempty_bin() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var s = render_svg(
        hist2d(x, y, bins=2, theme=_theme_hist2d(), width=300, height=220)
    ).to_string()
    # The two red cells of the bottom row merge into one run; the
    # one-count cell is its own; the empty cell is nothing. Plus the
    # background rect.
    assert_equal(_count_tag(s, "rect"), 3)


def test_rule_overload_bins_each_axis_by_the_rule() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(200):
        x.append(Float64(i))
        y.append(Float64((i * 37) % 101))
    var p = hist2d(x, y)
    var ex = bin_edges(x, BinRule.AUTO)
    var ey = bin_edges(y, BinRule.AUTO)
    assert_equal(len(p._image.x_edges), len(ex))
    assert_equal(len(p._image.y_edges), len(ey))
    assert_equal(p._image.x_edges[1], ex[1])
    assert_equal(p._image.y_edges[1], ey[1])
    var total = 0.0
    for r in range(len(p._image.z)):
        for c in range(len(p._image.z[r])):
            total += p._image.z[r][c]
    assert_equal(total, 200.0, "every point lands in exactly one bin")


def test_dtype_overload_renders_identically() raises:
    var xf: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0]
    var yf: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0]
    var xi: List[Int32] = [0, 1, 2, 3, 4]
    var yi: List[Int32] = [0, 0, 0, 0, 4]
    _assert_same_canvas(
        render(hist2d(xf, yf, bins=2, width=200, height=150)),
        render(hist2d(xi, yi, bins=2, width=200, height=150)),
        "Int32 hist2d matches Float64",
    )
    _assert_same_canvas(
        render(hist2d(xf, yf, width=200, height=150)),
        render(hist2d(xi, yi, width=200, height=150)),
        "Int32 hist2d (rule form) matches Float64",
    )


def test_hist2d_raises_with_names() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="same length"):
        _ = hist2d(x, y, bins=2)
    with assert_raises(contains="bins must be at least 1"):
        _ = hist2d(x, x, bins=0)
    var one: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="at least one bin"):
        _ = Plot().mark_hist2d().encode_hist2d(x, x, one, List[Float64]())
    with assert_raises():
        _ = hist2d(List[Float64](), List[Float64](), bins=2)


# ==== from test_hexbin.mojo ====
# Tests for `Mark.HEXBIN` / `hexbin()`: the lattice and its binning
# rule derived by hand, empty cells as background, and the overloads.


def _theme_hexbin() -> Theme:
    var stops: List[Color] = [_LO, _HI]
    return Theme(
        background=_BG,
        color_ramp=stops,
        show_gridlines=False,
        show_legend=False,
    )


def _cell(b: _HexBins, cx: Float64, cy: Float64) -> Int:
    """The count at center `(cx, cy)`, or -1 when no such cell."""
    for i in range(len(b.count)):
        if b.cx[i] == cx and b.cy[i] == cy:
            return b.count[i]
    return -1


def test_lattice_and_binning_are_hand_derived() raises:
    # gridsize 2 over the box [0, 4] x [0, 4]: nx = 2, ny = floor(2 /
    # sqrt 3) = 1, so sx = 2 and sy = 4. Lattice 1 centers are x in
    # {0, 2, 4} by y in {0, 4}; the offset lattice's are (1, 2) and
    # (3, 2). Each point below is nearer one specific center.
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 2.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0, 2.0, 2.0]
    var b = _hexbin_bins(x, y, 2)
    assert_equal(b.sx, 2.0)
    assert_equal(b.sy, 4.0)
    assert_equal(len(b.count), 5, "five cells are nonempty")
    assert_equal(_cell(b, 0.0, 0.0), 1, "(0, 0) is its own center")
    # (1, 0) is 0.5 lattice units from (2, 0) and, in the weighted
    # distance, 0.75 from the offset center (1, 2): it goes to (2, 0),
    # as does (2, 0) itself.
    assert_equal(_cell(b, 2.0, 0.0), 2)
    assert_equal(_cell(b, 4.0, 0.0), 1, "(3, 0) rounds to (4, 0)")
    assert_equal(_cell(b, 4.0, 4.0), 1, "the box corner is a center")
    # (2, 2) is half a row above (2, 0) -- weighted distance 0.75 --
    # and a quarter row from the offset center (3, 2) at 0.25: offset
    # lattice, both copies.
    assert_equal(_cell(b, 3.0, 2.0), 2)
    assert_equal(_cell(b, 1.0, 2.0), -1, "nothing landed at (1, 2)")


def test_a_point_equidistant_from_both_lattices_goes_to_the_offset_one() raises:
    # Same box as above. (1.5, 1.0) is lattice units (0.75, 0.25):
    # weighted distance 0.25 to lattice-1 center (2, 0) and 0.25 to the
    # offset center (1, 2). The tie is resolved toward the offset
    # lattice, and pinned here because this is where implementations
    # quietly differ.
    var x: List[Float64] = [0.0, 4.0, 1.5]
    var y: List[Float64] = [0.0, 4.0, 1.0]
    var b = _hexbin_bins(x, y, 2)
    assert_equal(_cell(b, 1.0, 2.0), 1, "the tie goes to the offset cell")
    assert_equal(_cell(b, 2.0, 0.0), -1)


def test_every_point_lands_in_exactly_one_cell() raises:
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(1000):
        x.append(Float64((i * 37) % 101) / 7.0)
        y.append(Float64((i * 53) % 97) / 3.0)
    var b = _hexbin_bins(x, y, 13)
    var total = 0
    for c in b.count:
        assert_true(c > 0, "only nonempty cells are returned")
        total += c
    assert_equal(total, 1000)


def test_empty_cells_show_the_background_and_full_ones_the_ramp_top() raises:
    # Two clusters far apart: the cells between them are empty and
    # must be background, not the ramp's bottom color (blue).
    var x = List[Float64]()
    var y = List[Float64]()
    for i in range(50):
        x.append(0.0 + Float64(i % 5) * 0.01)
        y.append(0.0 + Float64(i % 7) * 0.01)
        x.append(10.0 + Float64(i % 5) * 0.01)
        y.append(10.0 + Float64(i % 7) * 0.01)
    var c = render(
        hexbin(x, y, gridsize=10, theme=_theme_hexbin(), width=300, height=220)
    )
    assert_true(_count_color(c, _HI) > 50, "the two full cells are red")
    assert_equal(
        _count_color(c, _LO),
        0,
        "no cell is painted the ramp's bottom color -- empty is background",
    )
    # The middle of the chart, between the clusters, is background.
    var mid = c.get_pixel(c.width // 2, c.height // 2)
    assert_true(
        mid.r == _BG.r and mid.g == _BG.g and mid.b == _BG.b,
        "the gap between clusters is background",
    )


def test_svg_fills_one_path_per_distinct_count() raises:
    # Counts 1, 2 and 2 from the hand-derived set: cells with equal
    # counts share one filled path, so two fills (plus their two
    # face-colored strokes).
    var x: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 2.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0, 2.0, 2.0]
    var s = render_svg(
        hexbin(x, y, gridsize=2, theme=_theme_hexbin(), width=300, height=220)
    ).to_string()
    assert_equal(_count_tag(s, "path"), 4)


def _hex_byte(pair: String) raises -> Int:
    """`"4f"` to 79. The SVG backend writes colors as `#rrggbb`."""
    var value = 0
    for ch in pair.codepoints():
        var c = ch.to_u32()
        var digit: Int
        if c >= 48 and c <= 57:
            digit = Int(c) - 48
        elif c >= 97 and c <= 102:
            digit = Int(c) - 87
        elif c >= 65 and c <= 70:
            digit = Int(c) - 55
        else:
            raise Error("not a hex digit: " + pair)
        value = value * 16 + digit
    return value


def test_paths_come_out_grouped_and_in_ascending_count() raises:
    """What the cell sort is for, asserted directly.

    Cells sharing a count share a color and go into one path, so the
    sort has to do two things: put equal counts together, and put the
    groups in ascending order. Nothing checked either, so the sort could
    have been replaced with anything that happened to keep the path
    count right -- which is most of what a wrong sort does.

    The colors read off the ramp say both. Each fill's color is that
    group's count mapped through a blue-to-red ramp, so the reds must
    increase down the document and no color may appear twice.
    """
    # Counts 1, 2, 3 and 4, so four groups in a known order.
    var x = List[Float64]()
    var y = List[Float64]()
    var cells = List[Int]()
    cells.append(1)
    cells.append(2)
    cells.append(3)
    cells.append(4)
    for i in range(len(cells)):
        for _ in range(cells[i]):
            x.append(Float64(i) * 4.0)
            y.append(0.0)
    var s = render_svg(
        hexbin(x, y, gridsize=4, theme=_theme_hexbin(), width=360, height=260)
    ).to_string()

    # Fill colors in document order, keeping only the ones off this
    # theme's own ramp. _LO is pure blue and _HI pure red, so a ramp
    # color has no green and its red and blue sum to about 255 -- which
    # the green background and the near-black tick labels do not. About,
    # because each channel rounds independently: the midpoint comes out
    # #800080, which sums to 256.
    var reds = List[Int]()
    var rest = s
    while True:
        var at = rest.find('fill="#')
        if at == -1:
            break
        var r = _hex_byte(String(rest[byte = at + 7 : at + 9]))
        var g = _hex_byte(String(rest[byte = at + 9 : at + 11]))
        var b = _hex_byte(String(rest[byte = at + 11 : at + 13]))
        if g == 0 and r + b >= 254 and r + b <= 256:
            reds.append(r)
        var tail = String(rest[byte = at + 7 :])
        rest = tail
    assert_true(
        len(reds) >= 4,
        "expected at least one fill per count group, found "
        + String(len(reds)),
    )

    # Strokes repeat each fill's color, so take every distinct value in
    # the order it first appears: that is the group order.
    var groups = List[Int]()
    for r in reds:
        var seen = False
        for g in groups:
            if g == r:
                seen = True
        if not seen:
            groups.append(r)
    assert_equal(
        len(groups), 4, "four distinct counts should give four distinct colors"
    )
    for i in range(1, len(groups)):
        assert_true(
            groups[i] > groups[i - 1],
            (
                "group "
                + String(i)
                + " has red "
                + String(groups[i])
                + ", not above the previous group's "
                + String(groups[i - 1])
                + "; the groups are not in ascending count order"
            ),
        )


def test_hexbin_dtype_overload_renders_identically() raises:
    var xf: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 2.0]
    var yf: List[Float64] = [0.0, 0.0, 0.0, 0.0, 4.0, 2.0, 2.0]
    var xi: List[Int32] = [0, 1, 2, 3, 4, 2, 2]
    var yi: List[Int32] = [0, 0, 0, 0, 4, 2, 2]
    _assert_same_canvas(
        render(hexbin(xf, yf, gridsize=2, width=200, height=150)),
        render(hexbin(xi, yi, gridsize=2, width=200, height=150)),
        "Int32 hexbin matches Float64",
    )


def test_hexbin_raises_with_names() raises:
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="same length"):
        _ = render(hexbin(x, y))
    with assert_raises(contains="gridsize must be at least 1"):
        _ = render(hexbin(x, x, gridsize=0))
    with assert_raises(contains="no points"):
        _ = render(hexbin(List[Float64](), List[Float64]()))


# ---------------------------------------------------------------
# Tooltips on histogram and hexbin (#678)


def _titles_in(svg: String) -> List[String]:
    var out = List[String]()
    var at = 0
    while True:
        var open_at = svg.find("<title>", at)
        if open_at < 0:
            return out^
        var start = open_at + 7
        var close_at = svg.find("</title>", start)
        out.append(String(svg[byte=start:close_at]))
        at = close_at


def test_a_histogram_bar_is_titled_by_its_bin_edges_and_count() raises:
    # bins=3 over data spanning 0..3 gives integer edges [0,1,2,3];
    # the last bin is closed on the right, so its 3.0 lands inside it.
    var d: List[Float64] = [
        0.0,
        0.0,
        1.0,
        1.0,
        1.0,
        2.0,
        2.0,
        2.0,
        2.0,
        3.0,
    ]
    var titles = _titles_in(
        render_svg(histogram(d, bins=3, width=300, height=200)).to_string()
    )
    assert_equal(len(titles), 3, "one title per bin")
    assert_equal(titles[0], "[0, 1): 2")
    assert_equal(titles[1], "[1, 2): 3")
    assert_equal(titles[2], "[2, 3): 5")


def test_a_hexbin_cell_is_titled_by_its_count() raises:
    # Three points collapse onto one cell (count 3); the fourth, far
    # away, lands alone in a different cell (count 1) -- no adjacent
    # equal-count cells to merge, so each title is unambiguous.
    var x: List[Float64] = [0.0, 0.0, 0.0, 5.0]
    var y: List[Float64] = [0.0, 0.0, 0.0, 5.0]
    var titles = _titles_in(
        render_svg(hexbin(x, y, gridsize=4, width=200, height=200)).to_string()
    )
    assert_equal(len(titles), 2, "one title per occupied cell")
    assert_equal(titles[0], "count: 1")
    assert_equal(titles[1], "count: 3")


def test_binned_tooltips_follow_the_theme_flag() raises:
    var d: List[Float64] = [0.0, 1.0, 2.0]
    var off = render_svg(
        histogram(d, bins=3, theme=Theme(tooltips=Tooltips.OFF))
    ).to_string()
    assert_true("<title>" not in off, "Tooltips.OFF removes them")


# ---------------------------------------------------------------
# show_data_labels on HISTOGRAM (#684)


def test_a_histogram_bar_draws_its_count_above_the_bar() raises:
    # bins=3 over [0, 2]: edges [0, 0.667, 1.333, 2], counts 2/3/1. The
    # y-axis already draws "0" through "3" as ticks regardless of the
    # flag, so a bare `">2</text>" not in svg` check would pass even if
    # this were broken -- the full element (position and all) is what
    # a bin's own count label alone produces.
    var d: List[Float64] = [0.0, 0.0, 1.0, 1.0, 1.0, 2.0]
    var bin0 = (
        '<text x="97.000" y="63.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">2</text>'
    )
    var bin1 = (
        '<text x="170.000" y="22.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">3</text>'
    )
    var bin2 = (
        '<text x="243.000" y="105.000" font-size="12.000"'
        ' font-family="sans-serif" fill="#282828" text-anchor="middle">1</text>'
    )
    var off = render_svg(
        histogram(d, bins=3, width=300, height=200)
    ).to_string()
    assert_true(bin0 not in off and bin1 not in off and bin2 not in off)
    var t = Theme(show_data_labels=True)
    var on = render_svg(
        histogram(d, bins=3, theme=t, width=300, height=200)
    ).to_string()
    assert_true(bin0 in on and bin1 in on and bin2 in on)


# ---------------------------------------------------------------
# The mark_histogram().encode_histogram() chain (#698)


def _sample() -> List[Float64]:
    var d: List[Float64] = [0.5, 1.2, 1.8, 2.1, 2.3, 2.7, 3.0, 4.4, 4.9]
    return d^


def test_the_builder_chain_draws_what_histogram_draws() raises:
    # The chain used to raise -- encode_histogram() took Mark.BAR only;
    # that categorical chart is encode_binned_categories() now.
    # It now bins through bin_edges() and histogram_bins(), the path
    # histogram() takes, so the two render the same bytes.
    var d = _sample()
    assert_equal(
        render_svg(
            Plot().mark_histogram().encode_histogram(d, bins=4).size(400, 300)
        ).to_string(),
        render_svg(histogram(d, bins=4, width=400, height=300)).to_string(),
    )


def test_the_builder_chain_takes_every_normalization_histogram_does() raises:
    var d = _sample()
    var w: List[Float64] = [1.0, 2.0, 1.0, 1.0, 3.0, 1.0, 1.0, 2.0, 1.0]
    assert_equal(
        render_svg(
            Plot()
            .mark_histogram()
            .encode_histogram(
                d, bins=4, weights=w, stat=HistStat.DENSITY, cumulative=True
            )
            .size(400, 300)
        ).to_string(),
        render_svg(
            histogram(
                d,
                bins=4,
                weights=w,
                stat=HistStat.DENSITY,
                cumulative=True,
                width=400,
                height=300,
            )
        ).to_string(),
    )


def test_the_builder_chain_takes_a_bin_rule_as_histogram_does() raises:
    var d = _sample()
    assert_equal(
        render_svg(
            Plot()
            .mark_histogram()
            .encode_histogram(d, BinRule.SQRT, stat=HistStat.PROBABILITY)
            .size(400, 300)
        ).to_string(),
        render_svg(
            histogram(
                d,
                BinRule.SQRT,
                stat=HistStat.PROBABILITY,
                width=400,
                height=300,
            )
        ).to_string(),
    )


def test_the_builder_chain_draws_a_horizontal_histogram() raises:
    var d = _sample()
    assert_equal(
        render_svg(
            Plot()
            .mark_histogram(horizontal=True)
            .encode_histogram(d, bins=4)
            .size(400, 300)
        ).to_string(),
        render_svg(
            histogram(d, bins=4, horizontal=True, width=400, height=300)
        ).to_string(),
    )


def test_builder_chain_histograms_layer_as_histogram_ones_do() raises:
    # The same range, so both forms pin the same x-domain and
    # render_layers() accepts the pair (it refuses disagreeing ones,
    # for histogram() plots and chained ones alike).
    var a = _sample()
    var b: List[Float64] = [0.5, 1.5, 2.5, 3.5, 3.6, 4.9]
    var chained = List[Plot]()
    chained.append(
        Plot().mark_histogram().encode_histogram(a, bins=4).size(400, 300)
    )
    chained.append(
        Plot().mark_histogram().encode_histogram(b, bins=4).size(400, 300)
    )
    var one_call = List[Plot]()
    one_call.append(histogram(a, bins=4, width=400, height=300))
    one_call.append(histogram(b, bins=4, width=400, height=300))
    assert_equal(
        render_layers_svg(chained).to_string(),
        render_layers_svg(one_call).to_string(),
    )


def test_a_domain_set_before_encode_histogram_is_kept() raises:
    # #721: the bin-range pin used to overwrite a domain the caller had
    # already set, so the result depended on call order. Set before or
    # after, the caller's domain wins -- upright on x, horizontal on y.
    var d = _sample()
    var before = render_svg(
        Plot()
        .mark_histogram()
        .scale_x_domain(0.0, 10.0)
        .encode_histogram(d, bins=4)
        .size(400, 300)
    ).to_string()
    var after = render_svg(
        Plot()
        .mark_histogram()
        .encode_histogram(d, bins=4)
        .scale_x_domain(0.0, 10.0)
        .size(400, 300)
    ).to_string()
    assert_equal(before, after, "x: the caller's domain wins either way")
    assert_true(
        before
        != render_svg(
            Plot().mark_histogram().encode_histogram(d, bins=4).size(400, 300)
        ).to_string(),
        "and it is not the bin range",
    )
    var turned_before = render_svg(
        Plot()
        .mark_histogram(horizontal=True)
        .scale_y_domain(0.0, 10.0)
        .encode_histogram(d, bins=4)
        .size(400, 300)
    ).to_string()
    var turned_after = render_svg(
        Plot()
        .mark_histogram(horizontal=True)
        .encode_histogram(d, bins=4)
        .scale_y_domain(0.0, 10.0)
        .size(400, 300)
    ).to_string()
    assert_equal(turned_before, turned_after, "y, when horizontal")


def test_each_histogram_encoder_names_the_mark_it_needs() raises:
    # Two encoders, two charts: encode_histogram() for the numeric
    # Mark.HISTOGRAM, encode_binned_categories() for Mark.BAR's labeled
    # intervals. Each points at the other's mark rather than silently
    # drawing the wrong chart.
    var d = _sample()
    with assert_raises(contains="mark_histogram()"):
        _ = Plot().mark_bar().encode_histogram(d, bins=4)
    with assert_raises(contains="mark_bar()"):
        _ = Plot().mark_histogram().encode_binned_categories(d, bins=4)
    with assert_raises(contains="mark_histogram()"):
        _ = Plot().mark_point().encode_histogram(d, BinRule.AUTO)
    var bars = Plot().mark_bar().encode_binned_categories(d, bins=4)
    assert_equal(len(bars._categorical.x), 4, "four labeled bars")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
