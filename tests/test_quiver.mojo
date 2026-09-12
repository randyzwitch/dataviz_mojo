"""Tests for `Mark.QUIVER` / `quiver()`: the shaft and head geometry of
a known vector, the y-up convention, the automatic scale, and the
overloads."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

from _test_helpers import _assert_same_canvas, _attr_values, _count_color
from canvas.color import Color
from dataviz.quiver import _auto_pixels_per_unit, quiver
from dataviz.plot import Plot, render, render_svg
from dataviz.core.theme import Theme


def _near(a: Float64, b: Float64) -> Bool:
    return abs(a - b) < 0.01


struct _Seg(Copyable, Movable):
    var x0: Float64
    var y0: Float64
    var x1: Float64
    var y1: Float64

    def __init__(out self, x0: Float64, y0: Float64, x1: Float64, y1: Float64):
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1


def _lines(svg: String) raises -> List[_Seg]:
    """Every `<line>` as a segment."""
    var x1 = _attr_values(svg, "line", "x1")
    var y1 = _attr_values(svg, "line", "y1")
    var x2 = _attr_values(svg, "line", "x2")
    var y2 = _attr_values(svg, "line", "y2")
    var out = List[_Seg]()
    for i in range(len(x1)):
        out.append(
            _Seg(Float64(x1[i]), Float64(y1[i]), Float64(x2[i]), Float64(y2[i]))
        )
    return out^


def _find_shaft(segs: List[_Seg], dx: Float64, dy: Float64) -> Int:
    """The index of the segment with exactly this displacement, or -1."""
    for i in range(len(segs)):
        if _near(segs[i].x1 - segs[i].x0, dx) and _near(
            segs[i].y1 - segs[i].y0, dy
        ):
            return i
    return -1


def _head_tips(svg: String) raises -> List[List[Float64]]:
    """The first point of every `<path>`: the tip of each arrowhead,
    since the head path starts at its tip."""
    var ds = _attr_values(svg, "path", "d")
    var out = List[List[Float64]]()
    for d in ds:
        # "M<x>,<y> L..." -- the tip is the pair after M.
        var m = d.find("M")
        var sp = d.find(" ", m)
        var pair = String(d[byte = m + 1 : sp])
        var comma = pair.find(",")
        var tip = List[Float64]()
        tip.append(Float64(String(pair[byte=:comma])))
        tip.append(Float64(String(pair[byte = comma + 1 :])))
        out.append(tip^)
    return out^


def test_svg_arrow_geometry_pins_the_scale_and_the_y_up_convention() raises:
    # Two arrows at scale 2 px per unit: (10, 0) is a 20 px arrow due
    # east; (0, 10) is a 20 px arrow due *north*, which in pixel y means
    # y decreasing -- the place a y-down slip would show. The shaft
    # stops 11 px (the head length) short of the tip, so it is 9 px
    # long; the head path starts at the tip, 20 px from the tail.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var u: List[Float64] = [10.0, 0.0]
    var v: List[Float64] = [0.0, 10.0]
    var plot = (
        Plot()
        .mark_quiver(scale=2.0)
        .encode_quiver(x=x, y=y, u=u, v=v)
        .size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    var segs = _lines(svg)
    var east = _find_shaft(segs, 9.0, 0.0)
    assert_true(east >= 0, "the (10, 0) arrow's shaft runs 9 px due east")
    var north = _find_shaft(segs, 0.0, -9.0)
    assert_true(north >= 0, "the (0, 10) arrow's shaft runs 9 px up the page")

    var tips = _head_tips(svg)
    assert_equal(len(tips), 2, "one head per arrow")
    var east_tip = False
    var north_tip = False
    for t in tips:
        if _near(t[0], segs[east].x0 + 20.0) and _near(t[1], segs[east].y0):
            east_tip = True
        if _near(t[0], segs[north].x0) and _near(t[1], segs[north].y0 - 20.0):
            north_tip = True
    assert_true(east_tip, "the east head's tip is 20 px from its tail")
    assert_true(north_tip, "the north head's tip is 20 px above its tail")


def test_an_arrow_shorter_than_a_head_is_only_a_head() raises:
    # At scale 0.5 the (10, 0) vector is 5 px: no shaft, and a head
    # shortened to 5 px whose tip is 5 px from the tail.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var u: List[Float64] = [10.0, 0.0]
    var v: List[Float64] = [0.0, 0.0]
    var plot = (
        Plot()
        .mark_quiver(scale=0.5)
        .encode_quiver(x=x, y=y, u=u, v=v)
        .size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    assert_equal(len(_head_tips(svg)), 1, "the zero vector draws nothing")
    # Axis ticks are lines too, so count against the same chart at a
    # scale where the arrow does get a shaft: exactly one line fewer.
    var full = render_svg(
        Plot()
        .mark_quiver(scale=2.0)
        .encode_quiver(x=x, y=y, u=u, v=v)
        .size(400, 300)
    ).to_string()
    assert_equal(len(_lines(svg)) + 1, len(_lines(full)), "no shaft drawn")


def test_auto_scale_follows_the_mean_magnitude_rule() raises:
    # Four arrows of magnitude 10: sn = max(10, sqrt 4) = 10, so an
    # arrow of the mean magnitude is width / 18 px long, and pixels per
    # unit is width / 180.
    var u: List[Float64] = [10.0, 0.0, -10.0, 0.0]
    var v: List[Float64] = [0.0, 10.0, 0.0, -10.0]
    assert_true(_near(_auto_pixels_per_unit(u, v, 360.0), 2.0))
    # A field of zero vectors has no mean to scale by, and 1.0 draws
    # nothing anyway.
    var z: List[Float64] = [0.0, 0.0]
    assert_equal(_auto_pixels_per_unit(z, z, 360.0), 1.0)


def test_color_by_magnitude_colors_the_longest_arrow_the_ramp_top() raises:
    var lo = Color(0, 0, 255)
    var hi = Color(255, 0, 0)
    var stops: List[Color] = [lo, hi]
    var theme = Theme(color_ramp=stops, show_gridlines=False, show_legend=False)
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0, 2.0]
    var u: List[Float64] = [10.0, 5.0, 2.0]
    var v: List[Float64] = [0.0, 0.0, 0.0]
    var c = render(
        quiver(
            x,
            y,
            u,
            v,
            color_by_magnitude=True,
            theme=theme,
            width=400,
            height=300,
        )
    )
    assert_true(_count_color(c, hi) > 10, "the longest arrow is the ramp's top")
    var plain = render(quiver(x, y, u, v, theme=theme, width=400, height=300))
    assert_equal(_count_color(plain, hi), 0, "without the flag, the mark color")
    assert_true(
        _count_color(plain, theme.mark_color) > 10,
        "the mark color is on the canvas",
    )


def test_dtype_overload_matches_the_float64_path() raises:
    var xf: List[Float64] = [0.0, 1.0, 2.0]
    var yf: List[Float64] = [0.0, 1.0, 2.0]
    var uf: List[Float64] = [10.0, 5.0, 2.0]
    var vf: List[Float64] = [0.0, 3.0, -4.0]
    var xi: List[Int32] = [0, 1, 2]
    var yi: List[Int32] = [0, 1, 2]
    var ui: List[Int32] = [10, 5, 2]
    var vi: List[Int32] = [0, 3, -4]
    _assert_same_canvas(
        render(quiver(xf, yf, uf, vf, width=300, height=220)),
        render(quiver(xi, yi, ui, vi, width=300, height=220)),
        "Int32 quiver matches Float64",
    )


def test_quiver_raises_with_names() raises:
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var short: List[Float64] = [1.0]
    with assert_raises(contains="Plot.encode_quiver(): x, y, u, and v"):
        _ = render(quiver(x, y, short, y))
    with assert_raises(contains="scale must be 0"):
        _ = render(quiver(x, y, x, y, scale=-1.0))
    with assert_raises(contains="Plot.encode_quiver()"):
        _ = render(
            quiver(
                List[Float64](),
                List[Float64](),
                List[Float64](),
                List[Float64](),
            )
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
