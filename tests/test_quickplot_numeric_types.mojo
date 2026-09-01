"""Tests for the `DType`-generic overloads added to every quickplot
convenience function whose data is flat `List[Float64]` columns (not
nested `List[List[Float64]]` -- see each overload's own docstring for
why those are a separate, deferred follow-up). One test per function:
calling it with `List[Int]` data renders byte-for-byte identically to
calling it with the equivalent `List[Float64]` data, proving the
overload is a real, lossless pass-through (`_materialize_scalar_list`)
rather than a silently different code path.

Reuses each function's own updated `Example:` docstring data (now
`List[Int]` there too, per #167) so this test doubles as confirmation
that data still renders correctly.
"""

from std.testing import assert_equal, TestSuite

from dataviz_mojo import (
    area,
    bar,
    bullet,
    calendar_heatmap,
    candlestick,
    chord,
    effect_scatter,
    funnel,
    gantt,
    graph,
    heatmap,
    histogram,
    line,
    lollipop,
    nightingale,
    pie,
    polar,
    polarbar,
    population_pyramid,
    punchcard,
    radialbar,
    sankey,
    scatter,
    single_axis,
    span_chart,
    sunburst,
    tree,
    treemap,
    waterfall,
)
from dataviz_mojo.plot import render_svg


def test_scatter_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [1, 2, 3]
    var yi: List[Int] = [10, 20, 30]
    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [10.0, 20.0, 30.0]
    assert_equal(render_svg(scatter(xi, yi)).to_string(), render_svg(scatter(xf, yf)).to_string())


def test_line_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [0, 1]
    var yi: List[Int] = [42, 61]
    var xf: List[Float64] = [0.0, 1.0]
    var yf: List[Float64] = [42.0, 61.0]
    assert_equal(render_svg(line(xi, yi)).to_string(), render_svg(line(xf, yf)).to_string())


def test_area_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [0, 1, 2]
    var yi: List[Int] = [6, 10, 6]
    var xf: List[Float64] = [0.0, 1.0, 2.0]
    var yf: List[Float64] = [6.0, 10.0, 6.0]
    assert_equal(render_svg(area(xi, yi)).to_string(), render_svg(area(xf, yf)).to_string())


def test_effect_scatter_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [10, 25, 40]
    var yi: List[Int] = [15, 40, 20]
    var xf: List[Float64] = [10.0, 25.0, 40.0]
    var yf: List[Float64] = [15.0, 40.0, 20.0]
    assert_equal(
        render_svg(effect_scatter(xi, yi)).to_string(), render_svg(effect_scatter(xf, yf)).to_string()
    )


def test_polar_accepts_list_int_matching_list_float64() raises:
    var ai: List[Int] = [0, 1, 2]
    var ri: List[Int] = [5, 10, 5]
    var af: List[Float64] = [0.0, 1.0, 2.0]
    var rf: List[Float64] = [5.0, 10.0, 5.0]
    assert_equal(render_svg(polar(ai, ri)).to_string(), render_svg(polar(af, rf)).to_string())


def test_single_axis_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [12, 14, 13, 90]
    var xf: List[Float64] = [12.0, 14.0, 13.0, 90.0]
    assert_equal(render_svg(single_axis(xi)).to_string(), render_svg(single_axis(xf)).to_string())


def test_histogram_accepts_list_int_matching_list_float64() raises:
    var di: List[Int] = [52, 61, 65, 68, 70, 71, 72, 74, 75, 76]
    var df: List[Float64] = [52.0, 61.0, 65.0, 68.0, 70.0, 71.0, 72.0, 74.0, 75.0, 76.0]
    assert_equal(render_svg(histogram(di)).to_string(), render_svg(histogram(df)).to_string())


def test_bar_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [12, 19, -4]
    var vf: List[Float64] = [12.0, 19.0, -4.0]
    assert_equal(render_svg(bar(cats, vi)).to_string(), render_svg(bar(cats, vf)).to_string())


def test_lollipop_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [12, 19, 4]
    var vf: List[Float64] = [12.0, 19.0, 4.0]
    assert_equal(render_svg(lollipop(cats, vi)).to_string(), render_svg(lollipop(cats, vf)).to_string())


def test_pie_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [65, 18, 17]
    var vf: List[Float64] = [65.0, 18.0, 17.0]
    assert_equal(render_svg(pie(cats, vi)).to_string(), render_svg(pie(cats, vf)).to_string())


def test_funnel_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [10000, 3200, 950]
    var vf: List[Float64] = [10000.0, 3200.0, 950.0]
    assert_equal(render_svg(funnel(cats, vi)).to_string(), render_svg(funnel(cats, vf)).to_string())


def test_radialbar_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [92, 78, 45]
    var vf: List[Float64] = [92.0, 78.0, 45.0]
    assert_equal(render_svg(radialbar(cats, vi)).to_string(), render_svg(radialbar(cats, vf)).to_string())


def test_polarbar_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [92, 78, 45]
    var vf: List[Float64] = [92.0, 78.0, 45.0]
    assert_equal(render_svg(polarbar(cats, vi)).to_string(), render_svg(polarbar(cats, vf)).to_string())


def test_nightingale_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [1857, 202, 97]
    var vf: List[Float64] = [1857.0, 202.0, 97.0]
    assert_equal(
        render_svg(nightingale(cats, vi)).to_string(), render_svg(nightingale(cats, vf)).to_string()
    )


def test_waterfall_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [50, -18, 4]
    var vf: List[Float64] = [50.0, -18.0, 4.0]
    assert_equal(render_svg(waterfall(cats, vi)).to_string(), render_svg(waterfall(cats, vf)).to_string())


def test_calendar_heatmap_accepts_list_int_matching_list_float64() raises:
    var dates: List[String] = ["2024-01-01", "2024-01-02", "2024-01-03"]
    var vi: List[Int] = [3, 7, 1]
    var vf: List[Float64] = [3.0, 7.0, 1.0]
    assert_equal(
        render_svg(calendar_heatmap(dates, vi)).to_string(),
        render_svg(calendar_heatmap(dates, vf)).to_string(),
    )


def test_tree_accepts_list_int_matching_list_float64() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var vi: List[Int] = [0, 1, 1]
    var vf: List[Float64] = [0.0, 1.0, 1.0]
    assert_equal(
        render_svg(tree(ids, parents, vi)).to_string(), render_svg(tree(ids, parents, vf)).to_string()
    )


def test_treemap_accepts_list_int_matching_list_float64() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var vi: List[Int] = [0, 45, 20]
    var vf: List[Float64] = [0.0, 45.0, 20.0]
    assert_equal(
        render_svg(treemap(ids, parents, vi)).to_string(), render_svg(treemap(ids, parents, vf)).to_string()
    )


def test_sunburst_accepts_list_int_matching_list_float64() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var vi: List[Int] = [0, 45, 20]
    var vf: List[Float64] = [0.0, 45.0, 20.0]
    assert_equal(
        render_svg(sunburst(ids, parents, vi)).to_string(),
        render_svg(sunburst(ids, parents, vf)).to_string(),
    )


def test_chord_accepts_list_int_matching_list_float64() raises:
    var from_cats: List[String] = ["A", "B", "C"]
    var to_cats: List[String] = ["X", "Y", "Z"]
    var vi: List[Int] = [12, 8, 15]
    var vf: List[Float64] = [12.0, 8.0, 15.0]
    assert_equal(
        render_svg(chord(from_cats, to_cats, vi)).to_string(),
        render_svg(chord(from_cats, to_cats, vf)).to_string(),
    )


def test_sankey_accepts_list_int_matching_list_float64() raises:
    var from_cats: List[String] = ["A", "B", "C"]
    var to_cats: List[String] = ["X", "Y", "Z"]
    var vi: List[Int] = [30, 20, 15]
    var vf: List[Float64] = [30.0, 20.0, 15.0]
    assert_equal(
        render_svg(sankey(from_cats, to_cats, vi)).to_string(),
        render_svg(sankey(from_cats, to_cats, vf)).to_string(),
    )


def test_graph_accepts_list_int_matching_list_float64() raises:
    var from_cats: List[String] = ["A", "B", "C"]
    var to_cats: List[String] = ["X", "Y", "Z"]
    var vi: List[Int] = [8, 3, 5]
    var vf: List[Float64] = [8.0, 3.0, 5.0]
    assert_equal(
        render_svg(graph(from_cats, to_cats, vi)).to_string(),
        render_svg(graph(from_cats, to_cats, vf)).to_string(),
    )


def test_heatmap_accepts_list_int_matching_list_float64() raises:
    var x: List[String] = ["A", "B", "C"]
    var y: List[String] = ["X", "Y", "Z"]
    var vi: List[Int] = [3, 8, 5]
    var vf: List[Float64] = [3.0, 8.0, 5.0]
    assert_equal(render_svg(heatmap(x, y, vi)).to_string(), render_svg(heatmap(x, y, vf)).to_string())


def test_punchcard_accepts_list_int_matching_list_float64() raises:
    var x: List[String] = ["Mon", "Tue", "Wed"]
    var y: List[String] = ["9am", "12pm", "3pm"]
    var vi: List[Int] = [15, 60, 15]
    var vf: List[Float64] = [15.0, 60.0, 15.0]
    assert_equal(render_svg(punchcard(x, y, vi)).to_string(), render_svg(punchcard(x, y, vf)).to_string())


def test_population_pyramid_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["0-9", "10-19", "20-29"]
    var li: List[Int] = [12, 13, 14]
    var ri: List[Int] = [11, 12, 13]
    var lf: List[Float64] = [12.0, 13.0, 14.0]
    var rf: List[Float64] = [11.0, 12.0, 13.0]
    assert_equal(
        render_svg(population_pyramid(cats, li, ri)).to_string(),
        render_svg(population_pyramid(cats, lf, rf)).to_string(),
    )


def test_candlestick_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["D1", "D2", "D3"]
    var oi: List[Int] = [100, 104, 101]
    var hi: List[Int] = [106, 105, 103]
    var li: List[Int] = [98, 99, 95]
    var ci: List[Int] = [104, 101, 97]
    var of: List[Float64] = [100.0, 104.0, 101.0]
    var hf: List[Float64] = [106.0, 105.0, 103.0]
    var lf: List[Float64] = [98.0, 99.0, 95.0]
    var cf: List[Float64] = [104.0, 101.0, 97.0]
    assert_equal(
        render_svg(candlestick(cats, oi, hi, li, ci)).to_string(),
        render_svg(candlestick(cats, of, hf, lf, cf)).to_string(),
    )


def test_gantt_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Task A", "Task B", "Task C"]
    var si: List[Int] = [0, 5, 20]
    var ei: List[Int] = [8, 25, 28]
    var sf: List[Float64] = [0.0, 5.0, 20.0]
    var ef: List[Float64] = [8.0, 25.0, 28.0]
    assert_equal(
        render_svg(gantt(cats, si, ei)).to_string(), render_svg(gantt(cats, sf, ef)).to_string()
    )


def test_span_chart_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Jan", "Feb", "Mar"]
    var li: List[Int] = [-3, -2, 3]
    var hi: List[Int] = [5, 7, 12]
    var lf: List[Float64] = [-3.0, -2.0, 3.0]
    var hf: List[Float64] = [5.0, 7.0, 12.0]
    assert_equal(
        render_svg(span_chart(cats, li, hi)).to_string(), render_svg(span_chart(cats, lf, hf)).to_string()
    )


def test_bullet_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var mi: List[Int] = [72, 58, 85]
    var ti: List[Int] = [80, 65, 70]
    var mf: List[Float64] = [72.0, 58.0, 85.0]
    var tf: List[Float64] = [80.0, 65.0, 70.0]
    var ranges: List[List[Float64]] = [[50.0, 90.0], [50.0, 90.0], [50.0, 90.0]]
    assert_equal(
        render_svg(bullet(cats, mi, ti, ranges)).to_string(),
        render_svg(bullet(cats, mf, tf, ranges)).to_string(),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
