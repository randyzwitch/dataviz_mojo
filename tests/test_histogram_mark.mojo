"""Tests for `Mark.HISTOGRAM` (#435): one rectangle per bin at numeric
x positions, with a separator between adjacent nonempty bins, and the
`stepfilled` form that keeps the staircase."""

from std.testing import TestSuite, assert_equal, assert_true

from _test_helpers import _assert_same_canvas, _attr_values, _count_tag
from canvas.color import Color
from dataviz import histogram
from dataviz.histogram import HistogramBins, uniform_bin_edges
from dataviz.mark import Mark
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme


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
    assert_equal(_count_tag(s, "rect"), 1 + 3 + 2)


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
    assert_equal(_count_tag(s, "rect"), 1 + 2)


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
    assert_true(_count_tag(s, "path") >= 1, "the staircase is a path")
    assert_equal(_count_tag(s, "rect"), 1, "only the background rect")


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
    for w in _attr_values(s, "rect", "width"):
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
    assert_equal(len(p.x_data), 3, "step_x(): every edge")
    assert_equal(len(p.y_data), 3, "step_y(): values plus the last repeated")
    assert_equal(p.y_data[2], 1.0)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
