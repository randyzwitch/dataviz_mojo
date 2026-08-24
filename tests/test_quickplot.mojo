"""Tests for the one-call convenience functions: every one is checked
pixel-for-pixel against `_rendered()` -- the private helper every one
of them calls internally (see plot.mojo's docstring) -- fed the
identical `Plot`/`theme`/`width`/`height`/`title`/`x_title`/`y_title`
a caller would pass building the same chart by hand. Not a second
hand-derived pixel check (that's already covered per-mark in
test_point.mojo/test_bar.mojo/test_waterfall.mojo/etc.), so these
tests catch a wrapper drifting out of sync with Plot's builder (a
renamed encode_*() kwarg, a dropped .labels()/.theme() call, a wrong
default), not Plot's rendering math.

This no longer compares against a raw `Canvas` + `render()` call at
the same size: `_rendered()` now supersamples its output before
handing it back (see its docstring), so a quickplot call and an
unsupersampled `render()` at the identical size are no longer
pixel-identical by construction -- only genuinely different anymore,
not a bug in either. Comparing against `_rendered()` itself instead
keeps exactly what this file was always for (a wrapper built the right
`Plot`, not that `Plot`'s rendering math is correct) without
needing to re-derive the supersampling math by hand in every test
here too.

These all lived in one dataviz_mojo/quickplot.mojo when this file was
written; each now sits in its mark's file instead (see plot.mojo's module docstring for the rule). They stay tested together here
because what they share -- the builder contract and the documented
defaults -- is exactly what these tests check, and that's a property of
the group, not of any one mark. Imported from the package itself, the
way a caller is meant to (see dataviz_mojo/__init__.mojo's docstring), which is also what keeps this file indifferent to which
mark file any given one ends up in.

One "matches the manual builder, non-default theme/size/labels"
test per mark (proves the escape hatch and the shared parameters all
actually reach Plot), plus one "matches Theme()/640x420 with nothing
passed" test to lock in the documented defaults.
"""

from std.testing import assert_equal, TestSuite

from canvas_mojo.color import Color
from canvas_mojo.buffer import Canvas
from dataviz_mojo.plot import Plot, _rendered
from dataviz_mojo.theme import Theme
from dataviz_mojo import (
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
    var got = scatter(x, y, theme=t, width=300, height=200, title="T", x_title="X", y_title="Y")

    var want_plot = Plot().mark_point().encode(x=x, y=y)
    var want_c = _rendered(want_plot^, t, 300, 200, "T", "X", "Y")
    _assert_canvas_equal(got, want_c, "scatter")


def test_line_matches_manual_plot() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 1.0]
    var t = Theme(line_width=4.0)
    var got = line(x, y, theme=t, width=300, height=200)

    var want_plot = Plot().mark_line().encode(x=x, y=y)
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "line")


def test_area_matches_manual_plot() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [2.0, 4.0, 1.0]
    var t = Theme(mark_color=Color(5, 6, 7))
    var got = area(x, y, theme=t, width=300, height=200)

    var want_plot = Plot().mark_area().encode(x=x, y=y)
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "area")


def test_bar_matches_manual_plot() raises:
    var cats: List[String] = ["Mon", "Tue", "Wed"]
    var values: List[Float64] = [12.0, 19.0, -4.0]
    var t = Theme(mark_color=Color(40, 130, 90))
    var got = bar(cats, values, theme=t)

    var want_plot = Plot().mark_bar().encode_categorical(x=cats, y=values)
    var want_c = _rendered(want_plot^, t, 640, 420, "", "", "")
    _assert_canvas_equal(got, want_c, "bar")


def test_pie_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [30.0, 50.0, 20.0]
    var t = Theme(donut_inner_radius_fraction=0.5)
    var got = pie(cats, values, theme=t, width=300, height=300)

    var want_plot = Plot().mark_arc().encode_categorical(x=cats, y=values)
    var want_c = _rendered(want_plot^, t, 300, 300, "", "", "")
    _assert_canvas_equal(got, want_c, "pie")


def test_lollipop_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b", "c"]
    var values: List[Float64] = [3.0, 7.0, 5.0]
    var t = Theme(point_radius=6.0)
    var got = lollipop(cats, values, theme=t, width=300, height=200)

    var want_plot = Plot().mark_lollipop().encode_categorical(x=cats, y=values)
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "lollipop")


def test_waterfall_matches_manual_plot() raises:
    var cats: List[String] = ["start", "delta", "end"]
    var deltas: List[Float64] = [10.0, -3.0, 0.0]
    var is_total: List[Bool] = [True, False, True]
    var t = Theme(waterfall_total_color=Color(1, 2, 3))
    var got = waterfall(cats, deltas, is_total=is_total, theme=t, width=300, height=200)

    var want_plot = Plot().mark_waterfall().encode_waterfall(categories=cats, deltas=deltas, is_total=is_total)
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "waterfall")


def test_box_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var values: List[List[Float64]] = [[1.0, 2.0, 3.0, 4.0], [2.0, 3.0, 3.0, 9.0]]
    var t = Theme(mark_color=Color(9, 9, 9))
    var got = box(cats, values, theme=t, width=300, height=200)

    var want_plot = Plot().mark_box().encode_boxplot(categories=cats, values=values)
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "box")


def test_candlestick_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var open: List[Float64] = [10.0, 12.0]
    var high: List[Float64] = [14.0, 13.0]
    var low: List[Float64] = [9.0, 10.0]
    var close: List[Float64] = [12.0, 11.0]
    var t = Theme(mark_color_negative=Color(1, 1, 1))
    var got = candlestick(cats, open, high, low, close, theme=t, width=300, height=200)

    var want_plot = (
        Plot().mark_candlestick().encode_candlestick(categories=cats, open=open, high=high, low=low, close=close)
    )
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "candlestick")


def test_bullet_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var measures: List[Float64] = [70.0, 40.0]
    var targets: List[Float64] = [80.0, 60.0]
    var ranges: List[List[Float64]] = [[50.0, 75.0, 100.0], [50.0, 75.0, 100.0]]
    var t = Theme(bullet_range_color_dark=Color(11, 12, 13))
    var got = bullet(cats, measures, targets, ranges, theme=t, width=300, height=200)

    var want_plot = (
        Plot().mark_bullet().encode_bullet(categories=cats, measures=measures, targets=targets, ranges=ranges)
    )
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "bullet")


def test_gantt_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var start: List[Float64] = [0.0, 2.0]
    var end: List[Float64] = [3.0, 6.0]
    var t = Theme(mark_color=Color(3, 4, 5))
    var got = gantt(cats, start, end, theme=t, width=300, height=200)

    var want_plot = Plot().mark_gantt().encode_gantt(categories=cats, start=start, end=end)
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "gantt")


def test_grouped_bar_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var series: List[String] = ["S1", "S2"]
    var values: List[List[Float64]] = [[1.0, 2.0], [2.0, 1.0]]
    var t = Theme(show_legend=False)
    var got = grouped_bar(cats, series, values, theme=t, width=300, height=200)

    var want_plot = (
        Plot().mark_grouped_bar().encode_grouped_bar(categories=cats, series_names=series, values=values)
    )
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "grouped_bar")


def test_stacked_bar_matches_manual_plot() raises:
    var cats: List[String] = ["a", "b"]
    var series: List[String] = ["S1", "S2"]
    var values: List[List[Float64]] = [[1.0, 2.0], [2.0, 1.0]]
    var t = Theme(show_legend=False)
    var got = stacked_bar(cats, series, values, theme=t, width=300, height=200)

    var want_plot = (
        Plot().mark_stacked_bar().encode_grouped_bar(categories=cats, series_names=series, values=values)
    )
    var want_c = _rendered(want_plot^, t, 300, 200, "", "", "")
    _assert_canvas_equal(got, want_c, "stacked_bar")


def test_bar_defaults_to_theme_default_and_640x420() raises:
    var cats: List[String] = ["a", "b"]
    var values: List[Float64] = [1.0, 2.0]
    var got = bar(cats, values)  # no theme/width/height/labels given

    var want_plot = Plot().mark_bar().encode_categorical(x=cats, y=values)
    var want_c = _rendered(want_plot^, Theme(), 640, 420, "", "", "")
    _assert_canvas_equal(got, want_c, "bar defaults")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
