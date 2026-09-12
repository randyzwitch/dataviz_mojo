"""Tests for `Mark.HISTOGRAM` (#435): one rectangle per bin at numeric
x positions, with a separator between adjacent nonempty bins, and the
`stepfilled` form that keeps the staircase."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from _test_helpers import (
    _assert_same_canvas,
    _attr_values,
    _bbox_of_color,
    _count_tag,
    _drawn,
)
from canvas.color import Color
from dataviz import histogram, kdeplot
from dataviz.histogram import HistStat, HistogramBins, uniform_bin_edges
from dataviz.core.mark import Mark
from dataviz.plot import (
    Plot,
    render,
    render_facets,
    render_layers_svg,
    render_svg,
)
from dataviz.core.theme import Theme


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
    # to within the pixel snapping. The categorical encode_histogram()
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
