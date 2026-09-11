"""Tests for `Plot.annotate_band()`'s clipping (#369).

Each vertex used to be clamped independently into the plot rect, which
moves a polygon's edges rather than cutting them: an edge running from
an in-range vertex to an out-of-range one ended at the boundary below
where it truly crosses. `push_clip` reached `DrawTarget` in canvas
v0.32.0, so the band is clipped now.
"""

from _test_helpers import _assert_same_canvas
from std.testing import TestSuite, assert_true

from dataviz import Theme, line
from dataviz.plot import render


# 400x300 with gridlines off: the plot rect is x:[60,380], y:[20,250].
comptime _TOP = 20
comptime _BOTTOM = 250


def _chart() -> Theme:
    return Theme(show_gridlines=False)


def _painted(r: UInt8, g: UInt8, b: UInt8) -> Bool:
    return not (r == 255 and g == 255 and b == 255)


def test_a_band_crossing_the_top_keeps_its_true_intersection() raises:
    # The upper edge runs from y=0 at x=0 to y=100 at x=10, while the
    # y-domain tops out near 10. So it leaves the plot near x=1, and
    # every column right of that is filled all the way to the top.
    #
    # Clamping instead pulled the far vertex down to the top-left of the
    # rect, turning the upper edge into a diagonal across the whole plot
    # -- at the middle column the band would stop about halfway up.
    var xs: List[Float64] = [0.0, 10.0]
    var ys: List[Float64] = [0.0, 10.0]
    var bx: List[Float64] = [0.0, 10.0]
    var lo: List[Float64] = [0.0, 0.0]
    var hi: List[Float64] = [0.0, 100.0]
    var c = render(
        line(xs, ys, theme=_chart(), width=400, height=300)
        ^.annotate_band(bx, lo, hi)
    )
    # Middle of the plot, two rows below the top edge.
    var p = c.get_pixel(220, _TOP + 2)
    assert_true(
        _painted(p.r, p.g, p.b),
        "the band reaches the top of the rect at the middle column",
    )
    # And it is still bounded: one row above the rect is untouched.
    var above = c.get_pixel(220, _TOP - 2)
    assert_true(
        not _painted(above.r, above.g, above.b),
        "the band does not paint above the plot rect",
    )


def test_a_band_entirely_above_the_domain_draws_nothing_inside() raises:
    # Every vertex out of range, so the clip excludes the whole polygon
    # and the chart is byte-for-byte the one without the band. Comparing
    # whole canvases rather than sampling: a color filter here caught the
    # line's own antialiasing instead of the band, which is exactly the
    # kind of false pass sampling invites.
    var xs: List[Float64] = [0.0, 10.0]
    var ys: List[Float64] = [0.0, 10.0]
    var bx: List[Float64] = [0.0, 10.0]
    var lo: List[Float64] = [80.0, 80.0]
    var hi: List[Float64] = [100.0, 100.0]
    _assert_same_canvas(
        render(
            line(xs, ys, theme=_chart(), width=400, height=300)
            ^.annotate_band(bx, lo, hi)
        ),
        render(line(xs, ys, theme=_chart(), width=400, height=300)),
        "an out-of-range band paints nothing",
    )


def test_a_band_inside_the_domain_is_unchanged() raises:
    # The common case must not move: a band wholly inside the plot has
    # nothing to clip, so it fills between its two curves as before.
    var xs: List[Float64] = [0.0, 10.0]
    var ys: List[Float64] = [0.0, 10.0]
    var bx: List[Float64] = [0.0, 10.0]
    var lo: List[Float64] = [2.0, 2.0]
    var hi: List[Float64] = [6.0, 6.0]
    var c = render(
        line(xs, ys, theme=_chart(), width=400, height=300)
        ^.annotate_band(bx, lo, hi)
    )
    var inside = c.get_pixel(220, 150)
    assert_true(_painted(inside.r, inside.g, inside.b), "the band fills")
    var outside = c.get_pixel(220, _TOP + 2)
    assert_true(
        not _painted(outside.r, outside.g, outside.b),
        "and stops where its own upper curve is, not at the rect's top",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
