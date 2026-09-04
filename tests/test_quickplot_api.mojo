"""Merged test module (one process per test family; see pixi.toml's
`[tasks]` comment for why). Covers:

- The one-call convenience functions: each is checked pixel-for-pixel
  against a manually built `Plot` rendered through the same
  `render()` (#112), so these catch a wrapper drifting from the
  builder (a renamed kwarg, a dropped .labels()/.theme()/.size()
  call, a wrong default), not rendering math. One "matches the manual
  builder with non-default theme/size/labels" test per mark, plus one
  "matches Theme()/640x420 with nothing passed" test. Imported from
  the package, as a caller would.
- The DType-generic overloads of every quickplot function with flat
  `List[Float64]` data: `List[Int]` renders byte-for-byte like the
  equivalent `List[Float64]`. Reuses each function's `Example:` data
  (#167).
- The nested `List[List[Float64]]` overloads (grouped_bar/stacked_bar/
  bump/streamgraph, beeswarm/ridgeline/violin/box, marimekko, radar,
  parallel, polar_series) via `_materialize_nested_scalar_list`, plus
  radar()'s independent flat `max_values` axis (#173). corrplot()/
  parallel() use synthetic whole-number data here.
"""

from canvas.buffer import Canvas
from canvas.color import Color
from dataviz import (
    area,
    bar,
    beeswarm,
    box,
    bullet,
    bump,
    calendar_heatmap,
    candlestick,
    chord,
    corrplot,
    effect_scatter,
    funnel,
    gantt,
    graph,
    grouped_bar,
    heatmap,
    histogram,
    line,
    lollipop,
    marimekko,
    nightingale,
    parallel,
    pie,
    polar,
    polar_series,
    polarbar,
    population_pyramid,
    punchcard,
    radar,
    radialbar,
    ridgeline,
    sankey,
    scatter,
    single_axis,
    span_chart,
    stacked_bar,
    streamgraph,
    sunburst,
    tree,
    treemap,
    violin,
    waterfall,
)
from dataviz.plot import Plot, render, render_svg
from dataviz.theme import Theme
from std.testing import TestSuite, assert_equal


# ---------------------------------------------------------------
# from tests/test_quickplot.mojo
# ---------------------------------------------------------------


def _assert_canvas_equal(a: Canvas, b: Canvas, label: String) raises:
    assert_equal(a.width, b.width, label + ": width")
    assert_equal(a.height, b.height, label + ": height")
    for y in range(a.height):
        for x in range(a.width):
            var pa = a.get_pixel(x, y)
            var pb = b.get_pixel(x, y)
            assert_equal(
                pa.r,
                pb.r,
                label + ": r @ (" + String(x) + "," + String(y) + ")",
            )
            assert_equal(
                pa.g,
                pb.g,
                label + ": g @ (" + String(x) + "," + String(y) + ")",
            )
            assert_equal(
                pa.b,
                pb.b,
                label + ": b @ (" + String(x) + "," + String(y) + ")",
            )


def test_scatter_matches_manual_plot() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 1.0]
    var t = Theme(mark_color=Color(10, 20, 30))
    var _hoisted1 = scatter(
        x,
        y,
        theme=t,
        width=300,
        height=200,
        title="T",
        x_title="X",
        y_title="Y",
    )
    var got = render(_hoisted1)

    var want_plot = (
        Plot()
        .mark_point()
        .encode(x=x, y=y)
        .theme(t)
        .size(300, 200)
        .labels(title="T", x_title="X", y_title="Y")
    )
    _assert_canvas_equal(got, render(want_plot), "scatter")


def test_line_matches_manual_plot() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 1.0]
    var t = Theme(line_width=4.0)
    var _hoisted2 = line(x, y, theme=t, width=300, height=200)
    var got = render(_hoisted2)

    var want_plot = Plot().mark_line().encode(x=x, y=y).theme(t).size(300, 200)
    _assert_canvas_equal(got, render(want_plot), "line")


def test_area_matches_manual_plot() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 1.0]
    var t = Theme(mark_color=Color(5, 6, 7))
    var _hoisted3 = area(x, y, theme=t, width=300, height=200)
    var got = render(_hoisted3)

    var want_plot = Plot().mark_area().encode(x=x, y=y).theme(t).size(300, 200)
    _assert_canvas_equal(got, render(want_plot), "area")


def test_bar_matches_manual_plot() raises:
    var cats: List[String] = ["Mon", "Tue", "Wed"]
    var values: List[Float64] = [12.0, 19.0, -4.0]
    var t = Theme(mark_color=Color(40, 130, 90))
    var _hoisted4 = bar(cats, values, theme=t)
    var got = render(_hoisted4)

    var want_plot = (
        Plot()
        .mark_bar()
        .encode_categorical(x=cats, y=values)
        .theme(t)
        .size(640, 420)
    )
    _assert_canvas_equal(got, render(want_plot), "bar")


def test_pie_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [30.0, 50.0, 20.0]
    var _hoisted5 = pie(
        cats, values, inner_radius_fraction=0.5, width=300, height=300
    )
    var got = render(_hoisted5)

    var want_plot = (
        Plot()
        .mark_arc(inner_radius_fraction=0.5)
        .encode_categorical(x=cats, y=values)
        .size(300, 300)
    )
    _assert_canvas_equal(got, render(want_plot), "pie")


def test_lollipop_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [3.0, 7.0, 5.0]
    var t = Theme(point_radius=6.0)
    var _hoisted6 = lollipop(cats, values, theme=t, width=300, height=200)
    var got = render(_hoisted6)

    var want_plot = (
        Plot()
        .mark_lollipop()
        .encode_categorical(x=cats, y=values)
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "lollipop")


def test_waterfall_matches_manual_plot() raises:
    var cats: List[String] = ["start", "delta", "end"]
    var deltas: List[Float64] = [10.0, -3.0, 0.0]
    var is_total: List[Bool] = [True, False, True]
    var t = Theme(waterfall_total_color=Color(1, 2, 3))
    var _hoisted7 = waterfall(
        cats, deltas, is_total=is_total, theme=t, width=300, height=200
    )
    var got = render(_hoisted7)

    var want_plot = (
        Plot()
        .mark_waterfall()
        .encode_waterfall(categories=cats, deltas=deltas, is_total=is_total)
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "waterfall")


def test_box_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var values: List[List[Float64]] = [
        [1.0, 2.0, 3.0, 4.0],
        [2.0, 3.0, 3.0, 9.0],
    ]
    var t = Theme(mark_color=Color(9, 9, 9))
    var _hoisted8 = box(cats, values, theme=t, width=300, height=200)
    var got = render(_hoisted8)

    var want_plot = (
        Plot()
        .mark_box()
        .encode_boxplot(categories=cats, values=values)
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "box")


def test_candlestick_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [10.0, 12.0]
    var high: List[Float64] = [14.0, 13.0]
    var low: List[Float64] = [9.0, 10.0]
    var close: List[Float64] = [12.0, 11.0]
    var t = Theme(mark_color_negative=Color(1, 1, 1))
    var _hoisted9 = candlestick(
        cats, open, high, low, close, theme=t, width=300, height=200
    )
    var got = render(_hoisted9)

    var want_plot = (
        Plot()
        .mark_candlestick()
        .encode_candlestick(
            categories=cats, open=open, high=high, low=low, close=close
        )
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "candlestick")


def test_bullet_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var measures: List[Float64] = [70.0, 40.0]
    var targets: List[Float64] = [80.0, 60.0]
    var ranges: List[List[Float64]] = [[50.0, 75.0, 100.0], [50.0, 75.0, 100.0]]
    var t = Theme(bullet_range_color_dark=Color(11, 12, 13))
    var _hoisted10 = bullet(
        cats, measures, targets, ranges, theme=t, width=300, height=200
    )
    var got = render(_hoisted10)

    var want_plot = (
        Plot()
        .mark_bullet()
        .encode_bullet(
            categories=cats, measures=measures, targets=targets, ranges=ranges
        )
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "bullet")


def test_gantt_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var start: List[Float64] = [0.0, 2.0]
    var end: List[Float64] = [3.0, 6.0]
    var t = Theme(mark_color=Color(3, 4, 5))
    var _hoisted11 = gantt(cats, start, end, theme=t, width=300, height=200)
    var got = render(_hoisted11)

    var want_plot = (
        Plot()
        .mark_gantt()
        .encode_gantt(categories=cats, start=start, end=end)
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "gantt")


def test_grouped_bar_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var series: List[String] = ["S1", "S2"]
    var values: List[List[Float64]] = [[1.0, 2.0], [2.0, 1.0]]
    var t = Theme(show_legend=False)
    var _hoisted12 = grouped_bar(
        cats, series, values, theme=t, width=300, height=200
    )
    var got = render(_hoisted12)

    var want_plot = (
        Plot()
        .mark_grouped_bar()
        .encode_grouped_bar(categories=cats, series_names=series, values=values)
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "grouped_bar")


def test_stacked_bar_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var series: List[String] = ["S1", "S2"]
    var values: List[List[Float64]] = [[1.0, 2.0], [2.0, 1.0]]
    var t = Theme(show_legend=False)
    var _hoisted13 = stacked_bar(
        cats, series, values, theme=t, width=300, height=200
    )
    var got = render(_hoisted13)

    var want_plot = (
        Plot()
        .mark_stacked_bar()
        .encode_grouped_bar(categories=cats, series_names=series, values=values)
        .theme(t)
        .size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "stacked_bar")


def test_bar_defaults_to_theme_default_and_640x420() raises:
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [1.0, 2.0]
    var _hoisted14 = bar(cats, values)
    var got = render(_hoisted14)  # no theme/width/height/labels given

    var want_plot = Plot().mark_bar().encode_categorical(x=cats, y=values)
    _assert_canvas_equal(got, render(want_plot), "bar defaults")


# ---------------------------------------------------------------
# from tests/test_quickplot_numeric_types.mojo
# ---------------------------------------------------------------


def test_scatter_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [1, 2, 3]
    var yi: List[Int] = [10, 20, 30]
    var xf: List[Float64] = [1.0, 2.0, 3.0]
    var yf: List[Float64] = [10.0, 20.0, 30.0]
    assert_equal(
        render_svg(scatter(xi, yi)).to_string(),
        render_svg(scatter(xf, yf)).to_string(),
    )


def test_line_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [0, 1]
    var yi: List[Int] = [42, 61]
    var xf: List[Float64] = [0.0, 1.0]
    var yf: List[Float64] = [42.0, 61.0]
    assert_equal(
        render_svg(line(xi, yi)).to_string(),
        render_svg(line(xf, yf)).to_string(),
    )


def test_area_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [0, 1, 2]
    var yi: List[Int] = [6, 10, 6]
    var xf: List[Float64] = [0.0, 1.0, 2.0]
    var yf: List[Float64] = [6.0, 10.0, 6.0]
    assert_equal(
        render_svg(area(xi, yi)).to_string(),
        render_svg(area(xf, yf)).to_string(),
    )


def test_effect_scatter_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [10, 25, 40]
    var yi: List[Int] = [15, 40, 20]
    var xf: List[Float64] = [10.0, 25.0, 40.0]
    var yf: List[Float64] = [15.0, 40.0, 20.0]
    assert_equal(
        render_svg(effect_scatter(xi, yi)).to_string(),
        render_svg(effect_scatter(xf, yf)).to_string(),
    )


def test_polar_accepts_list_int_matching_list_float64() raises:
    var ai: List[Int] = [0, 1, 2]
    var ri: List[Int] = [5, 10, 5]
    var af: List[Float64] = [0.0, 1.0, 2.0]
    var rf: List[Float64] = [5.0, 10.0, 5.0]
    assert_equal(
        render_svg(polar(ai, ri)).to_string(),
        render_svg(polar(af, rf)).to_string(),
    )


def test_single_axis_accepts_list_int_matching_list_float64() raises:
    var xi: List[Int] = [12, 14, 13, 90]
    var xf: List[Float64] = [12.0, 14.0, 13.0, 90.0]
    assert_equal(
        render_svg(single_axis(xi)).to_string(),
        render_svg(single_axis(xf)).to_string(),
    )


def test_histogram_accepts_list_int_matching_list_float64() raises:
    var di: List[Int] = [52, 61, 65, 68, 70, 71, 72, 74, 75, 76]
    var df: List[Float64] = [
        52.0,
        61.0,
        65.0,
        68.0,
        70.0,
        71.0,
        72.0,
        74.0,
        75.0,
        76.0,
    ]
    assert_equal(
        render_svg(histogram(di)).to_string(),
        render_svg(histogram(df)).to_string(),
    )


def test_bar_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [12, 19, -4]
    var vf: List[Float64] = [12.0, 19.0, -4.0]
    assert_equal(
        render_svg(bar(cats, vi)).to_string(),
        render_svg(bar(cats, vf)).to_string(),
    )


def test_lollipop_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [12, 19, 4]
    var vf: List[Float64] = [12.0, 19.0, 4.0]
    assert_equal(
        render_svg(lollipop(cats, vi)).to_string(),
        render_svg(lollipop(cats, vf)).to_string(),
    )


def test_pie_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [65, 18, 17]
    var vf: List[Float64] = [65.0, 18.0, 17.0]
    assert_equal(
        render_svg(pie(cats, vi)).to_string(),
        render_svg(pie(cats, vf)).to_string(),
    )


def test_funnel_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [10000, 3200, 950]
    var vf: List[Float64] = [10000.0, 3200.0, 950.0]
    assert_equal(
        render_svg(funnel(cats, vi)).to_string(),
        render_svg(funnel(cats, vf)).to_string(),
    )


def test_radialbar_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [92, 78, 45]
    var vf: List[Float64] = [92.0, 78.0, 45.0]
    assert_equal(
        render_svg(radialbar(cats, vi)).to_string(),
        render_svg(radialbar(cats, vf)).to_string(),
    )


def test_polarbar_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [92, 78, 45]
    var vf: List[Float64] = [92.0, 78.0, 45.0]
    assert_equal(
        render_svg(polarbar(cats, vi)).to_string(),
        render_svg(polarbar(cats, vf)).to_string(),
    )


def test_nightingale_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [1857, 202, 97]
    var vf: List[Float64] = [1857.0, 202.0, 97.0]
    assert_equal(
        render_svg(nightingale(cats, vi)).to_string(),
        render_svg(nightingale(cats, vf)).to_string(),
    )


def test_waterfall_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B", "C"]
    var vi: List[Int] = [50, -18, 4]
    var vf: List[Float64] = [50.0, -18.0, 4.0]
    assert_equal(
        render_svg(waterfall(cats, vi)).to_string(),
        render_svg(waterfall(cats, vf)).to_string(),
    )


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
        render_svg(tree(ids, parents, vi)).to_string(),
        render_svg(tree(ids, parents, vf)).to_string(),
    )


def test_treemap_accepts_list_int_matching_list_float64() raises:
    var ids: List[String] = ["root", "a", "b"]
    var parents: List[String] = ["", "root", "root"]
    var vi: List[Int] = [0, 45, 20]
    var vf: List[Float64] = [0.0, 45.0, 20.0]
    assert_equal(
        render_svg(treemap(ids, parents, vi)).to_string(),
        render_svg(treemap(ids, parents, vf)).to_string(),
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
    assert_equal(
        render_svg(heatmap(x, y, vi)).to_string(),
        render_svg(heatmap(x, y, vf)).to_string(),
    )


def test_punchcard_accepts_list_int_matching_list_float64() raises:
    var x: List[String] = ["Mon", "Tue", "Wed"]
    var y: List[String] = ["9am", "12pm", "3pm"]
    var vi: List[Int] = [15, 60, 15]
    var vf: List[Float64] = [15.0, 60.0, 15.0]
    assert_equal(
        render_svg(punchcard(x, y, vi)).to_string(),
        render_svg(punchcard(x, y, vf)).to_string(),
    )


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
        render_svg(gantt(cats, si, ei)).to_string(),
        render_svg(gantt(cats, sf, ef)).to_string(),
    )


def test_span_chart_accepts_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Jan", "Feb", "Mar"]
    var li: List[Int] = [-3, -2, 3]
    var hi: List[Int] = [5, 7, 12]
    var lf: List[Float64] = [-3.0, -2.0, 3.0]
    var hf: List[Float64] = [5.0, 7.0, 12.0]
    assert_equal(
        render_svg(span_chart(cats, li, hi)).to_string(),
        render_svg(span_chart(cats, lf, hf)).to_string(),
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


# ---------------------------------------------------------------
# from tests/test_quickplot_nested_numeric_types.mojo
# ---------------------------------------------------------------


def test_grouped_bar_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Q1", "Q2"]
    var names: List[String] = ["North", "South"]
    var vi: List[List[Int]] = [[42, 48], [30, 35]]
    var vf: List[List[Float64]] = [[42.0, 48.0], [30.0, 35.0]]
    assert_equal(
        render_svg(grouped_bar(cats, names, vi)).to_string(),
        render_svg(grouped_bar(cats, names, vf)).to_string(),
    )


def test_stacked_bar_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["Q1", "Q2"]
    var names: List[String] = ["North", "South"]
    var vi: List[List[Int]] = [[42, 48], [30, 35]]
    var vf: List[List[Float64]] = [[42.0, 48.0], [30.0, 35.0]]
    assert_equal(
        render_svg(stacked_bar(cats, names, vi)).to_string(),
        render_svg(stacked_bar(cats, names, vf)).to_string(),
    )


def test_bump_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["2020", "2021"]
    var names: List[String] = ["Python", "Rust"]
    var vi: List[List[Int]] = [[85, 90], [92, 88]]
    var vf: List[List[Float64]] = [[85.0, 90.0], [92.0, 88.0]]
    assert_equal(
        render_svg(bump(cats, names, vi)).to_string(),
        render_svg(bump(cats, names, vf)).to_string(),
    )


def test_streamgraph_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["2020", "2021"]
    var names: List[String] = ["Rock", "Pop"]
    var vi: List[List[Int]] = [[30, 40], [45, 35]]
    var vf: List[List[Float64]] = [[30.0, 40.0], [45.0, 35.0]]
    assert_equal(
        render_svg(streamgraph(cats, names, vi)).to_string(),
        render_svg(streamgraph(cats, names, vf)).to_string(),
    )


def test_beeswarm_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[72, 75, 78], [65, 70, 72]]
    var vf: List[List[Float64]] = [[72.0, 75.0, 78.0], [65.0, 70.0, 72.0]]
    assert_equal(
        render_svg(beeswarm(cats, vi)).to_string(),
        render_svg(beeswarm(cats, vf)).to_string(),
    )


def test_ridgeline_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[68, 70, 72], [78, 80, 82]]
    var vf: List[List[Float64]] = [[68.0, 70.0, 72.0], [78.0, 80.0, 82.0]]
    assert_equal(
        render_svg(ridgeline(cats, vi)).to_string(),
        render_svg(ridgeline(cats, vf)).to_string(),
    )


def test_violin_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[72, 75, 78], [65, 70, 72]]
    var vf: List[List[Float64]] = [[72.0, 75.0, 78.0], [65.0, 70.0, 72.0]]
    assert_equal(
        render_svg(violin(cats, vi)).to_string(),
        render_svg(violin(cats, vf)).to_string(),
    )


def test_box_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[72, 75, 78, 80], [60, 65, 68, 70]]
    var vf: List[List[Float64]] = [
        [72.0, 75.0, 78.0, 80.0],
        [60.0, 65.0, 68.0, 70.0],
    ]
    assert_equal(
        render_svg(box(cats, vi)).to_string(),
        render_svg(box(cats, vf)).to_string(),
    )


def test_corrplot_accepts_nested_list_int_matching_list_float64() raises:
    var vars: List[String] = ["A", "B"]
    var mi: List[List[Int]] = [[1, 0], [0, 1]]
    var mf: List[List[Float64]] = [[1.0, 0.0], [0.0, 1.0]]
    assert_equal(
        render_svg(corrplot(vars, mi)).to_string(),
        render_svg(corrplot(vars, mf)).to_string(),
    )


def test_marimekko_accepts_nested_list_int_matching_list_float64() raises:
    var cats: List[String] = ["A", "B"]
    var subcats: List[String] = ["X", "Y"]
    var vi: List[List[Int]] = [[5, 20], [30, 35]]
    var vf: List[List[Float64]] = [[5.0, 20.0], [30.0, 35.0]]
    assert_equal(
        render_svg(marimekko(cats, subcats, vi)).to_string(),
        render_svg(marimekko(cats, subcats, vf)).to_string(),
    )


def test_radar_accepts_nested_list_int_matching_list_float64() raises:
    var indicators: List[String] = ["A", "B", "C"]
    var max_values: List[Float64] = [100.0, 100.0, 100.0]
    var names: List[String] = ["S1", "S2"]
    var vi: List[List[Int]] = [[90, 60, 80], [65, 85, 55]]
    var vf: List[List[Float64]] = [[90.0, 60.0, 80.0], [65.0, 85.0, 55.0]]
    assert_equal(
        render_svg(radar(indicators, max_values, names, vi)).to_string(),
        render_svg(radar(indicators, max_values, names, vf)).to_string(),
    )


def test_radar_accepts_list_int_max_values_matching_list_float64() raises:
    # radar()'s other DType-generic axis (#173): max_values, a flat
    # List[Float64], independent of series_values' nested axis; each
    # overload generalizes one of the two.
    var indicators: List[String] = ["A", "B", "C"]
    var names: List[String] = ["S1", "S2"]
    var series_values: List[List[Float64]] = [
        [90.0, 60.0, 80.0],
        [65.0, 85.0, 55.0],
    ]
    var max_i: List[Int] = [100, 100, 100]
    var max_f: List[Float64] = [100.0, 100.0, 100.0]
    assert_equal(
        render_svg(radar(indicators, max_i, names, series_values)).to_string(),
        render_svg(radar(indicators, max_f, names, series_values)).to_string(),
    )


def test_parallel_accepts_nested_list_int_matching_list_float64() raises:
    var dims: List[String] = ["A", "B"]
    var rows: List[String] = ["R1", "R2"]
    var vi: List[List[Int]] = [[180, 32], [280, 22]]
    var vf: List[List[Float64]] = [[180.0, 32.0], [280.0, 22.0]]
    assert_equal(
        render_svg(parallel(vi, dims, rows)).to_string(),
        render_svg(parallel(vf, dims, rows)).to_string(),
    )


def test_polar_series_accepts_nested_list_int_matching_list_float64() raises:
    var angle: List[Float64] = [0.0, 1.0]
    var names: List[String] = ["A", "B"]
    var vi: List[List[Int]] = [[68, 69], [57, 61]]
    var vf: List[List[Float64]] = [[68.0, 69.0], [57.0, 61.0]]
    assert_equal(
        render_svg(polar_series(angle, names, vi)).to_string(),
        render_svg(polar_series(angle, names, vf)).to_string(),
    )


def test_dtype_generic_overloads_forward_their_mark_style_parameters() raises:
    """A `[dtype]`-generic quickplot overload must forward its mark-style
    parameters to the concrete one. Regression test: when the per-mark
    knobs moved off `Theme` onto `mark_*()`/quickplot parameters, the
    generic overloads gained the parameters without forwarding them, and
    the only symptom was one changed image in the docs corpus.
    """
    var cats: List[String] = ["a", "b"]
    var vals_f: List[Float64] = [1.0, 3.0]
    var vals_i: List[Int] = [1, 3]

    # pie(): List[Int] takes the generic overload, List[Float64] the
    # concrete one; same pixels only if inner_radius_fraction is forwarded.
    var _p_gen = pie(
        cats, vals_i, inner_radius_fraction=0.55, width=300, height=300
    )
    var _p_con = pie(
        cats, vals_f, inner_radius_fraction=0.55, width=300, height=300
    )
    _assert_canvas_equal(
        render(_p_gen), render(_p_con), "pie inner_radius_fraction"
    )

    # radar(): an Int-typed parameter, the other shape these take --
    # here the generic axis is the per-series value lists.
    var inds: List[String] = ["a", "b", "c"]
    var maxes: List[Float64] = [10.0, 10.0, 10.0]
    var names: List[String] = ["s1"]
    var sv_f: List[List[Float64]] = [[3.0, 6.0, 9.0]]
    var sv_i: List[List[Int]] = [[3, 6, 9]]
    var _r_gen = radar(
        inds, maxes, names, sv_i, grid_rings=7, width=300, height=250
    )
    var _r_con = radar(
        inds, maxes, names, sv_f, grid_rings=7, width=300, height=250
    )
    _assert_canvas_equal(render(_r_gen), render(_r_con), "radar grid_rings")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
