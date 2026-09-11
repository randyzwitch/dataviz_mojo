"""Tests for plot-area clipping (#369).

With an axis domain narrower than the data, marks used to paint over the
axis labels and off the canvas: nothing clipped, because the mark layers
draw through `T: DrawTarget` and clipping was not on that trait until
canvas v0.32.0. The measure here is the one that found the bug --- count
pixels of the mark color outside the plot rect --- so a regression reads
the same way the original report did.
"""

from canvas.buffer import Canvas
from canvas.color import Color
from std.testing import TestSuite, assert_equal, assert_true

from dataviz import Theme, area, histogram, line, scatter
from dataviz.colors import CRIMSON
from dataviz.plot import Plot, render, render_layers


# 400x300 with gridlines off: the plot rect is x:[60,380], y:[20,250].
comptime _X0 = 60
comptime _X1 = 380
comptime _Y0 = 20
comptime _Y1 = 250


def _theme() -> Theme:
    return Theme(show_gridlines=False, mark_color=CRIMSON)


def _outside(c: Canvas) raises -> Int:
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == CRIMSON.r and p.g == CRIMSON.g and p.b == CRIMSON.b:
                if x < _X0 or x > _X1 or y < _Y0 or y > _Y1:
                    n += 1
    return n


def _inside(c: Canvas) raises -> Int:
    var n = 0
    for y in range(_Y0, _Y1 + 1):
        for x in range(_X0, _X1 + 1):
            var p = c.get_pixel(x, y)
            if p.r == CRIMSON.r and p.g == CRIMSON.g and p.b == CRIMSON.b:
                n += 1
    return n


def _ramp() -> Tuple[List[Float64], List[Float64]]:
    var xs = List[Float64]()
    var ys = List[Float64]()
    for i in range(40):
        xs.append(Float64(i))
        ys.append(Float64((i * 13) % 20))
    return (xs^, ys^)


def test_a_pinned_x_domain_keeps_every_mark_inside_the_plot_rect() raises:
    # The reproduction from #369. Before the fix: 67 stray pixels for the
    # scatter and 268 for the line, painted across the y-axis labels and
    # off both edges of the canvas.
    var d = _ramp()
    var s = render(
        scatter(d[0], d[1], theme=_theme(), width=400, height=300)
        ^.scale_x_domain(15.0, 25.0)
    )
    assert_equal(_outside(s), 0, "no scatter marker escapes the plot rect")
    assert_true(_inside(s) > 100, "and the markers inside are still drawn")

    var l = render(
        line(d[0], d[1], theme=_theme(), width=400, height=300)
        ^.scale_x_domain(15.0, 25.0)
    )
    assert_equal(_outside(l), 0, "no line segment escapes the plot rect")
    assert_true(_inside(l) > 300, "and the line inside is still drawn")


def test_a_pinned_y_domain_clips_too() raises:
    var d = _ramp()
    var s = render(
        scatter(d[0], d[1], theme=_theme(), width=400, height=300)
        ^.scale_y_domain(5.0, 12.0)
    )
    assert_equal(_outside(s), 0, "clipping is not an x-axis-only fix")
    assert_true(_inside(s) > 100, "the visible markers survive")


def test_an_area_and_a_histogram_are_clipped_as_well() raises:
    var d = _ramp()
    var a = render(
        area(d[0], d[1], theme=_theme(), width=400, height=300)
        ^.scale_x_domain(15.0, 25.0)
    )
    assert_equal(_outside(a), 0, "the area fill stops at the plot rect")
    assert_true(_inside(a) > 500, "and still fills inside it")

    var values = List[Float64]()
    for i in range(60):
        values.append(Float64(i % 20))
    var h = render(
        histogram(values, bins=8, theme=_theme(), width=400, height=300)
        ^.scale_x_domain(5.0, 12.0)
    )
    assert_equal(_outside(h), 0, "no bar escapes the plot rect")
    assert_true(_inside(h) > 500, "and the bars inside are drawn")


def test_a_layered_chart_is_clipped_by_the_same_code() raises:
    # `render_layers()` calls the same layer functions against a frame it
    # built, which is why the clip is pushed from the scales inside the
    # layer rather than from a frame outside it.
    var d = _ramp()
    var plots: List[Plot] = [
        line(d[0], d[1], theme=_theme(), width=400, height=300)
        ^.scale_x_domain(15.0, 25.0),
        scatter(d[0], d[1], theme=_theme(), width=400, height=300)
        ^.scale_x_domain(15.0, 25.0),
    ]
    var c = render_layers(plots)
    assert_equal(_outside(c), 0, "an overlay clips its layers too")
    assert_true(_inside(c) > 300, "and both layers still draw")


def test_the_axis_furniture_is_not_clipped_away() raises:
    # The clip covers the mark layer only. A tick label sits below the
    # plot rect and must survive, or the fix would have traded one bug
    # for a worse one.
    var d = _ramp()
    var t = Theme(show_gridlines=False)
    var c = render(
        line(d[0], d[1], theme=t, width=400, height=300)
        ^.scale_x_domain(15.0, 25.0)
    )
    # Counted as "not the page color" rather than as an exact text
    # color: the glyphs are antialiased, so only a handful of pixels
    # ever land on `Theme.text_color` exactly.
    var label_ink = 0
    for y in range(_Y1 + 2, c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (p.r == 255 and p.g == 255 and p.b == 255):
                label_ink += 1
    assert_true(
        label_ink > 100,
        "the x tick labels are still drawn -- got " + String(label_ink),
    )


def test_an_unpinned_chart_is_unchanged() raises:
    # Nothing moves for the common case: without a domain override the
    # data already fits, so the clip is a no-op.
    var d = _ramp()
    var c = render(scatter(d[0], d[1], theme=_theme(), width=400, height=300))
    assert_equal(_outside(c), 0)
    assert_true(_inside(c) > 100, "the whole scatter is inside anyway")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
