"""A horizontal color legend marks a centered ramp's neutral point (#526).

`Plot.scale_color_center()` pins a diverging ramp's neutral color to a
value and lets the two arms be different sizes. The vertical legend draws
a third label at that center. The row form, used for
`LegendPosition.TOP`/`BOTTOM`, drew nothing, so the chart showed a
gradient with two end numbers and no way to read where the center went.

It now draws a tick on the bar instead of a label under it: a row legend
exists to cost no height, and a label stacked below would spend exactly
what the layout saved.

These read pixels rather than SVG `<text>`, because the tick carries no
text. The discriminator is a column of `text_color` inside the bar's own
rows, which the gradient never produces on its own.
"""

from std.testing import TestSuite, assert_equal, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import scatter
from dataviz.legend_position import LegendPosition
from dataviz.plot import Plot, render
from dataviz.theme import Theme


def _xs() -> List[Float64]:
    var x = List[Float64]()
    for i in range(12):
        x.append(Float64(i))
    return x^


def _ys() -> List[Float64]:
    var y = List[Float64]()
    for i in range(12):
        y.append(Float64(i % 5) + 1.0)
    return y^


def _values(lo: Float64, hi: Float64) -> List[Float64]:
    """A color channel spanning `lo` to `hi`, so the legend's domain is
    known exactly rather than inferred from the data's shape.

    Args:
        lo: The first value.
        hi: The last value.

    Returns:
        Twelve values from `lo` to `hi`.
    """
    var c = List[Float64]()
    for i in range(12):
        c.append(lo + (hi - lo) * Float64(i) / 11.0)
    return c^


def _theme() -> Theme:
    return Theme(legend_position=LegendPosition.BOTTOM, show_gridlines=False)


def _tick_columns(c: Canvas, theme: Theme) -> List[Int]:
    """Every x where a full vertical run of `text_color` appears, which
    is what the tick draws and the gradient does not.

    Scans the whole canvas rather than an assumed bar rectangle: the
    legend's position is layout, and a test that hard-codes it breaks
    whenever the layout moves rather than when the tick does.

    Args:
        c: The rendered chart.
        theme: Supplies the tick's color.

    Returns:
        The x positions carrying a run of at least 6 such pixels.
    """
    var tc = theme.text_color
    var cols = List[Int]()
    for x in range(c.width):
        var run = 0
        var best = 0
        for y in range(c.height):
            var p = c.get_pixel(x, y)
            if p.r == tc.r and p.g == tc.g and p.b == tc.b:
                run += 1
                if run > best:
                    best = run
            else:
                run = 0
        if best >= 6:
            cols.append(x)
    return cols^


def _centered(lo: Float64, hi: Float64, center: Float64) raises -> Canvas:
    var p = (
        scatter(_xs(), _ys(), theme=_theme(), width=420, height=300)
        .encode(x=_xs(), y=_ys(), color=_values(lo, hi))
        .scale_color_center(center)
    )
    return render(p^)


def _uncentered(lo: Float64, hi: Float64) raises -> Canvas:
    var p = scatter(_xs(), _ys(), theme=_theme(), width=420, height=300).encode(
        x=_xs(), y=_ys(), color=_values(lo, hi)
    )
    return render(p^)


def _lowest_frame_row(c: Canvas, tc: Color) -> Int:
    """The last row carrying a long horizontal run of `tc`, which is the
    axis frame's bottom line.

    Module level rather than nested: a nested `def` in Mojo 1.0 cannot
    capture, so the color has to be a parameter.

    Args:
        c: The rendered chart.
        tc: The frame's color.

    Returns:
        The row index, or -1 if no row qualifies.
    """
    var found = -1
    for y in range(c.height):
        var run = 0
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == tc.r and p.g == tc.g and p.b == tc.b:
                run += 1
        if run > 40:
            found = y
    return found


def test_a_centered_ramp_draws_a_tick_an_uncentered_one_does_not() raises:
    # The control matters more than the positive here: text glyphs and
    # the axis frame are also drawn in text_color, so "found a column"
    # only means something against the same chart without a center.
    var with_center = len(_tick_columns(_centered(-10.0, 30.0, 0.0), _theme()))
    var without = len(_tick_columns(_uncentered(-10.0, 30.0), _theme()))
    assert_true(
        with_center > without,
        "centering added no vertical run: "
        + String(with_center)
        + " vs "
        + String(without),
    )


def test_the_tick_sits_off_middle_when_the_arms_are_asymmetric() raises:
    # The whole reason the tick exists. On -10..30 centered at 0 the
    # neutral point is a quarter along, so a tick drawn at the bar's
    # midpoint would be wrong while still being a tick.
    var near = _tick_columns(_centered(-10.0, 30.0, 0.0), _theme())
    var far = _tick_columns(_centered(-10.0, 30.0, 20.0), _theme())
    assert_true(len(near) > 0, "no tick for center 0")
    assert_true(len(far) > 0, "no tick for center 20")

    # Compare the rightmost new column in each: moving the center from
    # 0 to 20 must move the tick right.
    var a = near[len(near) - 1]
    var b = far[len(far) - 1]
    assert_true(
        b > a,
        "moving the center right did not move the tick right: "
        + String(a)
        + " then "
        + String(b),
    )


def test_the_tick_costs_no_height() raises:
    # The reason it is a tick and not a label. The rendered canvas is a
    # fixed size, so the claim is about the legend's own row height:
    # the chart body must not shrink when a center is added.
    var plain = _uncentered(-10.0, 30.0)
    var centered = _centered(-10.0, 30.0, 0.0)
    assert_equal(plain.width, centered.width, "width")
    assert_equal(plain.height, centered.height, "height")

    # The axis frame's lowest row is where the plot rect ends. If the
    # legend had grown, the frame would have been squeezed upward.
    assert_equal(
        _lowest_frame_row(plain, _theme().text_color),
        _lowest_frame_row(centered, _theme().text_color),
        "the plot rect moved, so the legend changed height",
    )


def test_a_center_all_but_on_the_domain_edge_draws_no_tick() raises:
    # A tick within its own width of the bar's end reads as a border
    # rather than a mark, so it is skipped.
    #
    # The center is 0.1 rather than 0.0 because `scale_color_center()`
    # already rejects a center on the domain boundary outright ("must
    # lie strictly inside the color domain"). So the exact-edge case is
    # unreachable through the public API and the guard in the drawing
    # code is only for centers near the edge, which are allowed. This
    # test pins the reachable half; the API owns the other.
    var edge = len(_tick_columns(_centered(0.0, 30.0, 0.1), _theme()))
    var plain = len(_tick_columns(_uncentered(0.0, 30.0), _theme()))
    assert_equal(edge, plain, "a tick was drawn at the bar's end")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
