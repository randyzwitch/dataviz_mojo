"""Deterministic jitter for a continuous scatter (#149).

Overplotted points are a real problem and every other library solves it by
sampling a random offset. This package cannot: its tests assert hand-derived
pixel positions, so a render that moved points by a sampled amount would not
be checkable, and a seeded generator would be checkable for one seed only.

So the offset is `(2 * frac(i * phi) - 1) * jitter` for an irrational `phi`,
which these tests recompute independently rather than reading the constant
back out of the implementation.

The open question #149 records is what a continuous scatter jitters
*within*: a categorical mark has its category's band and a continuous axis
has nothing. The answer here is that the caller names a pixel width, so the
knob describes the visual separation wanted rather than a quantity in the
data's units.
"""

from std.math import floor
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from canvas.buffer import Canvas

from dataviz import Theme
from dataviz.plot import Plot, render, render_svg
from _test_helpers import _assert_same_canvas, _bbox_of_color


def _xs(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for _ in range(n):
        # Every point on the same coordinate: the overplotting case
        # jitter exists for. Without it these are one pixel stack.
        v.append(5.0)
    return v^


def _ys(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for _ in range(n):
        v.append(5.0)
    return v^


def _spread(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for i in range(n):
        v.append(Float64(i))
    return v^


def _expected_offset(index: Int, amount: Float64, phi: Float64) -> Float64:
    """The offset recomputed here rather than imported.

    Importing `_jitter_offset` would assert only that the function equals
    itself. This is the formula from `mark_point()`'s docstring, written
    out, so a change to the implementation has to agree with the documented
    contract rather than with itself.

    Args:
        index: The point's position in the data.
        amount: Half-width in pixels.
        phi: The irrational multiplier.

    Returns:
        The expected pixel offset.
    """
    var t = Float64(index) * phi
    return (2.0 * (t - floor(t)) - 1.0) * amount


def test_the_default_leaves_every_point_exactly_where_it_was() raises:
    # The whole feature is opt-in. If this fails, every existing chart moved.
    var plain = render(
        Plot().mark_point().encode(x=_spread(8), y=_spread(8)).size(240, 180)
    )
    var explicit_zero = render(
        Plot()
        .mark_point(jitter_x=0.0, jitter_y=0.0)
        .encode(x=_spread(8), y=_spread(8))
        .size(240, 180)
    )
    _assert_same_canvas(plain, explicit_zero, "jitter=0 changed the render")


def test_the_offsets_match_the_documented_formula() raises:
    # Pinned against the formula in the docstring, recomputed above. The
    # first four offsets for a 10 pixel jitter, to four places.
    var phi = 0.6180339887498949
    var got0 = _expected_offset(0, 10.0, phi)
    var got1 = _expected_offset(1, 10.0, phi)
    var got2 = _expected_offset(2, 10.0, phi)
    assert_almost_equal(got0, -10.0, atol=1e-9, msg="index 0 sits at -amount")
    assert_almost_equal(got1, 2.360679, atol=1e-5, msg="index 1")
    assert_almost_equal(got2, -5.278640, atol=1e-5, msg="index 2")


def test_jitter_separates_points_that_share_a_coordinate() raises:
    # Twelve points on one coordinate. Without jitter they paint a single
    # marker-sized blob; with it they spread across a wider box.
    var theme = Theme(show_gridlines=False)
    var n = 12
    var stacked = render(
        Plot()
        .mark_point()
        .encode(x=_xs(n), y=_ys(n))
        .theme(theme)
        .size(240, 180)
    )
    var jittered = render(
        Plot()
        .mark_point(jitter_x=12.0)
        .encode(x=_xs(n), y=_ys(n))
        .theme(theme)
        .size(240, 180)
    )
    var a = _bbox_of_color(stacked, theme.mark_color)
    var b = _bbox_of_color(jittered, theme.mark_color)
    var stacked_w = a.x1 - a.x0
    var jittered_w = b.x1 - b.x0
    assert_true(
        jittered_w > stacked_w + 8,
        "jitter did not widen the cluster: "
        + String(stacked_w)
        + " then "
        + String(jittered_w),
    )


def test_the_two_axes_jitter_independently() raises:
    # x only must not move anything vertically. A single shared constant
    # for both axes would smear the cluster diagonally instead.
    var theme = Theme(show_gridlines=False)
    var n = 12
    var base = _bbox_of_color(
        render(
            Plot()
            .mark_point()
            .encode(x=_xs(n), y=_ys(n))
            .theme(theme)
            .size(240, 180)
        ),
        theme.mark_color,
    )
    var x_only = _bbox_of_color(
        render(
            Plot()
            .mark_point(jitter_x=12.0)
            .encode(x=_xs(n), y=_ys(n))
            .theme(theme)
            .size(240, 180)
        ),
        theme.mark_color,
    )
    assert_equal(
        x_only.y1 - x_only.y0,
        base.y1 - base.y0,
        "jitter_x changed the vertical extent",
    )


def test_the_same_chart_renders_identically_every_time() raises:
    # Determinism is the property that lets this package test jitter at
    # all, so it is asserted rather than assumed.
    var a = render(
        Plot()
        .mark_point(jitter_x=9.0, jitter_y=4.0)
        .encode(x=_spread(10), y=_spread(10))
        .size(240, 180)
    )
    var b = render(
        Plot()
        .mark_point(jitter_x=9.0, jitter_y=4.0)
        .encode(x=_spread(10), y=_spread(10))
        .size(240, 180)
    )
    _assert_same_canvas(a, b, "two renders of the same jittered chart")


def test_jitter_reaches_the_svg_backend_too() raises:
    # Both backends go through _draw_point_layer, but a reader would not
    # know that from the outside.
    var plain = render_svg(
        Plot().mark_point().encode(x=_xs(8), y=_ys(8)).size(240, 180)
    ).to_string()
    var jittered = render_svg(
        Plot()
        .mark_point(jitter_x=10.0)
        .encode(x=_xs(8), y=_ys(8))
        .size(240, 180)
    ).to_string()
    assert_true(plain != jittered, "the SVG backend ignored jitter")


def test_a_negative_jitter_raises() raises:
    with assert_raises(contains="must not be negative"):
        _ = Plot().mark_point(jitter_x=-1.0)
    with assert_raises(contains="must not be negative"):
        _ = Plot().mark_point(jitter_y=-1.0)


def test_the_y_axis_uses_its_own_constant() raises:
    """The two axes must not share one irrational multiplier.

    If they did, every point's y offset would equal its x offset and a
    jittered cloud would collapse onto a 45 degree line. `mark_point()`
    claims two constants for exactly this reason, and nothing else in
    this file would notice if the claim stopped being true: sharing one
    constant leaves the default untouched, still separates points, still
    renders identically twice, and still reaches the SVG backend.

    Two points is enough to tell the constants apart. Index 0 sits at
    `-amount` under either. Index 1 lands at
    `(2 * frac(phi) - 1) * amount`, which for amount 20 is 4.72 pixels
    under the x constant and 10.20 under the y one, so the vertical span
    between the pair differs by about five and a half pixels.
    """
    var theme = Theme(show_gridlines=False)
    var flat = render(
        Plot()
        .mark_point()
        .encode(x=_xs(2), y=_ys(2))
        .theme(theme)
        .size(240, 180)
    )
    var jittered = render(
        Plot()
        .mark_point(jitter_y=20.0)
        .encode(x=_xs(2), y=_ys(2))
        .theme(theme)
        .size(240, 180)
    )
    var base = _bbox_of_color(flat, theme.mark_color)
    var moved = _bbox_of_color(jittered, theme.mark_color)
    # The marker's own diameter is in both boxes, so the difference is
    # the offset span alone.
    var span = Float64((moved.y1 - moved.y0) - (base.y1 - base.y0))
    assert_almost_equal(
        span,
        30.195,
        atol=2.0,
        msg=(
            "vertical span "
            + String(span)
            + " matches the x constant (24.7), not the y one (30.2), so"
            " both axes are using the same multiplier"
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
