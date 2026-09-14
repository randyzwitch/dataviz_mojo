"""A bivariate chart with its marginal distributions (#354).

seaborn's `jointplot`: a scatter with a histogram of x along the top and
a histogram of y down the right.

#354 says what to assert and why it is the right thing: "a value at the
main panel's x pixel *p* must appear at pixel *p* in the top marginal.
Assert that for two or three values, and the layout is correct or it is
not -- no pixel counting needed." The layout is the feature, because a
marginal offset from the panel it describes is lying about where the
mass is.

Two separate things have to hold for that, and the tests below separate
them: the domains have to match, and the plot rects have to start at the
same pixel. Equal domains alone are not enough, which is what #569 was
about.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import Theme, jointplot


comptime _BG = Color(250, 250, 250)


def _theme() -> Theme:
    return Theme(background=_BG, show_gridlines=False, show_legend=False)


def _samples(n: Int) -> Tuple[List[Float64], List[Float64]]:
    """A correlated cloud whose y runs into the millions.

    The magnitude is deliberate. A marginal's own axis counts
    observations, so its labels are two or three characters wide; the
    panel's y-axis shows the data. Unless those differ in width, the two
    cells reach the same margin by accident and an alignment test passes
    whether or not anything aligned them -- which is what the first
    version of this file did, and it took turning align_axes off to
    notice.
    """
    var x = List[Float64]()
    var y = List[Float64]()
    var seed = 20260913
    for _ in range(n):
        seed = (seed * 1103515245 + 12345) % 2147483648
        var a = Float64(seed % 10000) / 1000.0
        seed = (seed * 1103515245 + 12345) % 2147483648
        var b = Float64(seed % 10000) / 1000.0
        x.append(a)
        y.append((a * 0.6 + b * 0.4) * 1000000.0 + 5000000.0)
    return (x^, y^)


def _axis_column(c: Canvas, y0: Int, y1: Int) -> Int:
    """The leftmost column carrying a tall run of the axis color: a
    panel's left spine, which is where its plot rect starts."""
    var axis = Theme().axis_color
    for x in range(c.width):
        var run = 0
        for y in range(y0, y1):
            var p = c.get_pixel(x, y)
            if p.r == axis.r and p.g == axis.g and p.b == axis.b:
                run += 1
        if run > (y1 - y0) // 2:
            return x
    return -1


def _axis_row(c: Canvas, x0: Int, x1: Int, from_bottom: Bool) -> Int:
    """A panel's bottom spine, searching up from the figure's bottom or
    down from its top."""
    var axis = Theme().axis_color
    for step in range(c.height):
        var y = (c.height - 1 - step) if from_bottom else step
        var run = 0
        for x in range(x0, x1):
            var p = c.get_pixel(x, y)
            if p.r == axis.r and p.g == axis.g and p.b == axis.b:
                run += 1
        if run > (x1 - x0) // 2:
            return y
    return -1


def test_the_top_marginal_sits_over_the_panel_it_describes() raises:
    """#354's stated criterion.

    The top strip and the main panel are the two cells of column 0, so
    their plot rects must share a left edge. Without that, a bar in the
    strip sits over the wrong part of the scatter and the figure
    misreports where the mass is.
    """
    var s = _samples(400)
    var c = jointplot(s[0], s[1], width=640, height=640, theme=_theme())
    assert_equal(c.width, 640, "figure width")
    assert_equal(c.height, 640, "figure height")

    # The top strip is the first fifth at ratio 4; the panel is below it.
    var strip_left = _axis_column(c, 20, 110)
    var panel_left = _axis_column(c, 200, 480)
    assert_true(strip_left > 0, "no left spine found in the top marginal")
    assert_true(panel_left > 0, "no left spine found in the main panel")
    assert_equal(
        strip_left,
        panel_left,
        (
            "the top marginal starts at "
            + String(strip_left)
            + " and the panel at "
            + String(panel_left)
            + ", so a bar does not sit over the data it counts"
        ),
    )


def test_the_right_marginal_lines_up_with_the_panel() raises:
    # The other axis: the panel and the right strip are the two cells of
    # row 1, so they must share a bottom edge.
    var s = _samples(400)
    var c = jointplot(s[0], s[1], width=640, height=640, theme=_theme())
    var panel_bottom = _axis_row(c, 150, 450, True)
    var strip_bottom = _axis_row(c, 560, 620, True)
    assert_true(panel_bottom > 0, "no bottom spine in the main panel")
    assert_true(strip_bottom > 0, "no bottom spine in the right marginal")
    assert_equal(
        panel_bottom,
        strip_bottom,
        (
            "the panel's baseline is at "
            + String(panel_bottom)
            + " and the right marginal's at "
            + String(strip_bottom)
        ),
    )


def test_the_empty_corner_is_the_figure_background() raises:
    # Top-right has no cell, as seaborn leaves it. It must not show the
    # canvas's white default through (#568/#576's sibling).
    var s = _samples(400)
    var c = jointplot(s[0], s[1], width=640, height=640, theme=_theme())
    var p = c.get_pixel(600, 40)
    assert_true(
        p.r == _BG.r and p.g == _BG.g and p.b == _BG.b,
        (
            "the empty corner is ("
            + String(p.r)
            + ","
            + String(p.g)
            + ","
            + String(p.b)
            + "), not the figure background"
        ),
    )


def test_the_ratio_moves_the_divider() raises:
    # ratio is how many times the marginals the panel is, so a bigger
    # ratio makes the strips thinner. Measured as where the panel's left
    # spine sits vertically: with a thinner top strip the panel starts
    # higher.
    var s = _samples(400)
    var thin = jointplot(
        s[0], s[1], width=640, height=640, ratio=8.0, theme=_theme()
    )
    var thick = jointplot(
        s[0], s[1], width=640, height=640, ratio=2.0, theme=_theme()
    )
    var thin_top = _axis_row(thin, 150, 450, False)
    var thick_top = _axis_row(thick, 150, 450, False)
    assert_true(
        thin_top < thick_top,
        (
            "ratio 8 put the first spine at "
            + String(thin_top)
            + " and ratio 2 at "
            + String(thick_top)
            + "; a larger ratio should give thinner marginals"
        ),
    )


def test_jointplot_raises_with_names() raises:
    var x: List[Float64] = [1.0, 2.0, 3.0]
    var y: List[Float64] = [1.0, 2.0]
    with assert_raises(contains="same length"):
        _ = jointplot(x, y)

    var empty = List[Float64]()
    with assert_raises(contains="no values"):
        _ = jointplot(empty, empty)

    var ok: List[Float64] = [1.0, 2.0, 3.0]
    with assert_raises(contains="bins must be positive"):
        _ = jointplot(ok, ok, bins=0)
    with assert_raises(contains="ratio must be above zero"):
        _ = jointplot(ok, ok, ratio=0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
