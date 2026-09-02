"""Tests for the one-call convenience functions: every one is checked
pixel-for-pixel against a manually-built `Plot`, both rendered through
the identical `render()` (issue #112 -- quickplot now just returns the
`Plot` it builds internally, not a rendered `Canvas`, so there's no
quickplot-specific rendering path left to differ from `render()`'s at
all; see plot.mojo's module docstring). Not a second hand-derived
pixel check (that's already covered per-mark in test_point.mojo/
test_bar.mojo/test_waterfall.mojo/etc.), so these tests catch a
wrapper drifting out of sync with Plot's builder (a renamed
encode_*() kwarg, a dropped .labels()/.theme()/.size() call, a wrong
default), not Plot's rendering math.

Each one-call function lives in its own mark's file (see plot.mojo's
module docstring for the rule). They stay tested together here
because what they share -- the builder contract and the documented
defaults -- is exactly what these tests check, and that's a property of
the group, not of any one mark. Imported from the package itself, the
way a caller is meant to (see dataviz/__init__.mojo's docstring), which is also what keeps this file indifferent to which
mark file any given one ends up in.

One "matches the manual builder, non-default theme/size/labels"
test per mark (proves the escape hatch and the shared parameters all
actually reach Plot), plus one "matches Theme()/640x420 with nothing
passed" test to lock in the documented defaults.
"""

from std.testing import assert_equal, TestSuite

from canvas.color import Color
from canvas.buffer import Canvas
from dataviz.plot import Plot, render
from dataviz.theme import Theme
from dataviz import (
    area,
    bar,
    box,
    bullet,
    candlestick,
    gantt,
    grouped_bar,
    line,
    lollipop,
    pie,
    scatter,
    stacked_bar,
    waterfall,
)


def _assert_canvas_equal(a: Canvas, b: Canvas, label: String) raises:
    assert_equal(a.width, b.width, label + ": width")
    assert_equal(a.height, b.height, label + ": height")
    for y in range(a.height):
        for x in range(a.width):
            var pa = a.get_pixel(x, y)
            var pb = b.get_pixel(x, y)
            assert_equal(pa.r, pb.r, label + ": r @ (" + String(x) + "," + String(y) + ")")
            assert_equal(pa.g, pb.g, label + ": g @ (" + String(x) + "," + String(y) + ")")
            assert_equal(pa.b, pb.b, label + ": b @ (" + String(x) + "," + String(y) + ")")


def test_scatter_matches_manual_plot() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 1.0]
    var t = Theme(mark_color=Color(10, 20, 30))
    var _hoisted1 = scatter(x, y, theme=t, width=300, height=200, title="T", x_title="X", y_title="Y")
    var got = render(_hoisted1)

    var want_plot = Plot().mark_point().encode(x=x, y=y).theme(t).size(300, 200).labels(
        title="T", x_title="X", y_title="Y"
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

    var want_plot = Plot().mark_bar().encode_categorical(x=cats, y=values).theme(t).size(640, 420)
    _assert_canvas_equal(got, render(want_plot), "bar")


def test_pie_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [30.0, 50.0, 20.0]
    var t = Theme(donut_inner_radius_fraction=0.5)
    var _hoisted5 = pie(cats, values, theme=t, width=300, height=300)
    var got = render(_hoisted5)

    var want_plot = Plot().mark_arc().encode_categorical(x=cats, y=values).theme(t).size(300, 300)
    _assert_canvas_equal(got, render(want_plot), "pie")


def test_lollipop_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [3.0, 7.0, 5.0]
    var t = Theme(point_radius=6.0)
    var _hoisted6 = lollipop(cats, values, theme=t, width=300, height=200)
    var got = render(_hoisted6)

    var want_plot = Plot().mark_lollipop().encode_categorical(x=cats, y=values).theme(t).size(300, 200)
    _assert_canvas_equal(got, render(want_plot), "lollipop")


def test_waterfall_matches_manual_plot() raises:
    var cats: List[String] = ["start", "delta", "end"]
    var deltas: List[Float64] = [10.0, -3.0, 0.0]
    var is_total: List[Bool] = [True, False, True]
    var t = Theme(waterfall_total_color=Color(1, 2, 3))
    var _hoisted7 = waterfall(cats, deltas, is_total=is_total, theme=t, width=300, height=200)
    var got = render(_hoisted7)

    var want_plot = Plot().mark_waterfall().encode_waterfall(
        categories=cats, deltas=deltas, is_total=is_total
    ).theme(t).size(300, 200)
    _assert_canvas_equal(got, render(want_plot), "waterfall")


def test_box_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var values: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0], [2.0, 3.0, 3.0, 9.0]]
    var t = Theme(mark_color=Color(9, 9, 9))
    var _hoisted8 = box(cats, values, theme=t, width=300, height=200)
    var got = render(_hoisted8)

    var want_plot = Plot().mark_box().encode_boxplot(categories=cats, values=values).theme(t).size(300, 200)
    _assert_canvas_equal(got, render(want_plot), "box")


def test_candlestick_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [10.0, 12.0]
    var high: List[Float64] = [14.0, 13.0]
    var low: List[Float64] = [9.0, 10.0]
    var close: List[Float64] = [12.0, 11.0]
    var t = Theme(mark_color_negative=Color(1, 1, 1))
    var _hoisted9 = candlestick(cats, open, high, low, close, theme=t, width=300, height=200)
    var got = render(_hoisted9)

    var want_plot = (
        Plot().mark_candlestick().encode_candlestick(categories=cats, open=open, high=high, low=low, close=close)
        .theme(t).size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "candlestick")


def test_bullet_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var measures: List[Float64] = [70.0, 40.0]
    var targets: List[Float64] = [80.0, 60.0]
    var ranges: List[List[Float64]] = [[50.0, 75.0, 100.0], [50.0, 75.0, 100.0]]
    var t = Theme(bullet_range_color_dark=Color(11, 12, 13))
    var _hoisted10 = bullet(cats, measures, targets, ranges, theme=t, width=300, height=200)
    var got = render(_hoisted10)

    var want_plot = (
        Plot().mark_bullet().encode_bullet(categories=cats, measures=measures, targets=targets, ranges=ranges)
        .theme(t).size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "bullet")


def test_gantt_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var start: List[Float64] = [0.0, 2.0]
    var end: List[Float64] = [3.0, 6.0]
    var t = Theme(mark_color=Color(3, 4, 5))
    var _hoisted11 = gantt(cats, start, end, theme=t, width=300, height=200)
    var got = render(_hoisted11)

    var want_plot = Plot().mark_gantt().encode_gantt(categories=cats, start=start, end=end).theme(t).size(300, 200)
    _assert_canvas_equal(got, render(want_plot), "gantt")


def test_grouped_bar_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var series: List[String] = ["S1", "S2"]
    var values: List[List[Float64]] = [[1.0, 2.0], [2.0, 1.0]]
    var t = Theme(show_legend=False)
    var _hoisted12 = grouped_bar(cats, series, values, theme=t, width=300, height=200)
    var got = render(_hoisted12)

    var want_plot = (
        Plot().mark_grouped_bar().encode_grouped_bar(categories=cats, series_names=series, values=values)
        .theme(t).size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "grouped_bar")


def test_stacked_bar_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var series: List[String] = ["S1", "S2"]
    var values: List[List[Float64]] = [[1.0, 2.0], [2.0, 1.0]]
    var t = Theme(show_legend=False)
    var _hoisted13 = stacked_bar(cats, series, values, theme=t, width=300, height=200)
    var got = render(_hoisted13)

    var want_plot = (
        Plot().mark_stacked_bar().encode_grouped_bar(categories=cats, series_names=series, values=values)
        .theme(t).size(300, 200)
    )
    _assert_canvas_equal(got, render(want_plot), "stacked_bar")


def test_bar_defaults_to_theme_default_and_640x420() raises:
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [1.0, 2.0]
    var _hoisted14 = bar(cats, values)
    var got = render(_hoisted14)  # no theme/width/height/labels given

    var want_plot = Plot().mark_bar().encode_categorical(x=cats, y=values)
    _assert_canvas_equal(got, render(want_plot), "bar defaults")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
