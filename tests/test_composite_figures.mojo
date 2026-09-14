"""Figures assembled from several plots: jointplot() and pairplot().

One module rather than 2: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from canvas.buffer import Canvas
from canvas.color import Color
from dataviz import Theme, jointplot, pairplot


# ==== from test_jointplot.mojo ====
# A bivariate chart with its marginal distributions (#354).
#
# seaborn's `jointplot`: a scatter with a histogram of x along the top and
# a histogram of y down the right.
#
# #354 says what to assert and why it is the right thing: "a value at the
# main panel's x pixel *p* must appear at pixel *p* in the top marginal.
# Assert that for two or three values, and the layout is correct or it is
# not -- no pixel counting needed." The layout is the feature, because a
# marginal offset from the panel it describes is lying about where the
# mass is.
#
# Two separate things have to hold for that, and the tests below separate
# them: the domains have to match, and the plot rects have to start at the
# same pixel. Equal domains alone are not enough, which is what #569 was
# about.


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


# ==== from test_pairplot.mojo ====
# A scatterplot matrix over every pair of variables (#353).
#
# The feature is the *scales*, not the grid. `render_facets()` already lays
# plots out in cells; what makes a pairplot is that column `j` shares one
# x-domain down its height and row `i` shares one y-domain across its
# width, so every panel showing a variable draws it at the same size.
#
# A grid of independently scaled cells looks identical and means something
# else, which is why the shared-domain tests below are the ones that matter
# and the "it rendered" test is the least interesting.


def _col(n: Int, scale: Float64, offset: Float64) -> List[Float64]:
    var v = List[Float64]()
    for i in range(n):
        v.append(Float64(i) * scale + offset)
    return v^


def _three() -> Tuple[List[List[Float64]], List[String]]:
    """Three variables on deliberately different ranges.

    The ranges differ by a factor of 100 so that an unshared scale is
    obvious: if each cell scaled itself, all three would fill their
    panels identically and the figure would hide the difference.

    Returns:
        `(columns, names)`.
    """
    var cols = List[List[Float64]]()
    cols.append(_col(12, 1.0, 0.0))
    cols.append(_col(12, 100.0, 0.0))
    cols.append(_col(12, -1.0, 50.0))
    var names = List[String]()
    names.append("small")
    names.append("large")
    names.append("falling")
    return (cols^, names^)


def _theme_pairplot() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def _ink(c: Canvas, theme: Theme) -> Int:
    var bg = theme.background
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                n += 1
    return n


def _ink_rows(c: Canvas, y0: Int, y1: Int, theme: Theme) -> Int:
    """`_ink` over rows `y0` up to `y1` only."""
    var bg = theme.background
    var n = 0
    for y in range(y0, y1):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                n += 1
    return n


def test_pairplot_title_sits_in_a_band_above_the_panels() raises:
    # The figure grows by the band; the panels underneath do not move.
    var data = _three()
    var plain = pairplot(data[0], data[1], theme=_theme_pairplot())
    var titled = pairplot(
        data[0], data[1], theme=_theme_pairplot(), title="Three variables"
    )
    var band = titled.height - plain.height
    assert_true(band > 0, "a title adds a band")
    assert_equal(titled.width, plain.width)
    assert_true(
        _ink_rows(titled, 0, band, _theme_pairplot()) > 0,
        "the band holds the title",
    )
    assert_equal(
        _ink_rows(titled, band, titled.height, _theme_pairplot()),
        _ink(plain, _theme_pairplot()),
        "the panels are unchanged under it",
    )


def test_the_figure_is_n_by_n_cells() raises:
    var d = _three()
    var c = pairplot(
        d[0], d[1], theme=_theme_pairplot(), cell_width=160, cell_height=120
    )
    assert_equal(c.width, 160 * 3, "three cells across")
    assert_equal(c.height, 120 * 3, "three cells down")


def test_two_variables_is_the_smallest_pairplot() raises:
    var cols = List[List[Float64]]()
    cols.append(_col(8, 1.0, 0.0))
    cols.append(_col(8, 2.0, 1.0))
    var names = List[String]()
    names.append("a")
    names.append("b")
    var c = pairplot(
        cols, names, theme=_theme_pairplot(), cell_width=140, cell_height=110
    )
    assert_equal(c.width, 280, "two cells across")
    assert_equal(c.height, 220, "two cells down")


def test_a_variable_is_drawn_at_the_same_scale_wherever_it_appears() raises:
    """The property that makes this a pairplot rather than a grid.

    Variable 0 is the x of every cell in column 0. If each cell scaled
    itself, the cell where variable 0 meets variable 1 and the cell where
    it meets variable 2 would place the same value at different x
    positions.

    Checked by rendering the same figure with variable 2 replaced by a
    copy of variable 1: column 0's cells must be unaffected, because
    column 0's x-domain comes from variable 0 and nothing else.
    """
    var d = _three()
    var a = pairplot(
        d[0], d[1], theme=_theme_pairplot(), cell_width=160, cell_height=120
    )

    var changed = List[List[Float64]]()
    changed.append(d[0][0].copy())
    changed.append(d[0][1].copy())
    changed.append(d[0][1].copy())  # was "falling"
    var b = pairplot(
        changed, d[1], theme=_theme_pairplot(), cell_width=160, cell_height=120
    )

    # Cell (0, 0) is the diagonal histogram of variable 0, whose domain
    # depends on variable 0 only. It must be pixel-identical.
    var diff = 0
    for y in range(120):
        for x in range(160):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                diff += 1
    assert_equal(
        diff,
        0,
        (
            "changing variable 2 moved variable 0's own panel, so a cell's"
            " scale is coming from something other than its own variables"
        ),
    )


def test_changing_a_variable_does_change_the_cells_that_show_it() raises:
    # The control for the test above: if nothing ever changed, that test
    # would pass on a blank canvas.
    var d = _three()
    var a = pairplot(
        d[0], d[1], theme=_theme_pairplot(), cell_width=160, cell_height=120
    )
    var changed = List[List[Float64]]()
    changed.append(d[0][0].copy())
    changed.append(d[0][1].copy())
    changed.append(d[0][1].copy())
    var b = pairplot(
        changed, d[1], theme=_theme_pairplot(), cell_width=160, cell_height=120
    )
    var diff = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                diff += 1
    assert_true(
        diff > 100,
        "replacing a whole variable changed only " + String(diff) + " pixels",
    )


def test_the_figure_draws_something_in_every_cell() raises:
    # Weak on its own, which is why it is last: it catches a layout that
    # renders one panel and leaves the rest blank.
    var d = _three()
    var theme = _theme_pairplot()
    var c = pairplot(d[0], d[1], theme=theme, cell_width=160, cell_height=120)
    for row in range(3):
        for col in range(3):
            var bg = theme.background
            var ink = 0
            for y in range(row * 120, (row + 1) * 120):
                for x in range(col * 160, (col + 1) * 160):
                    var p = c.get_pixel(x, y)
                    if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                        ink += 1
            assert_true(
                ink > 50,
                "cell ("
                + String(row)
                + ", "
                + String(col)
                + ") drew only "
                + String(ink)
                + " pixels",
            )


def test_bad_input_raises() raises:
    var d = _three()

    var one = List[List[Float64]]()
    one.append(d[0][0].copy())
    var one_name = List[String]()
    one_name.append("only")
    with assert_raises(contains="at least two variables"):
        _ = pairplot(one, one_name)

    var two_names = List[String]()
    two_names.append("a")
    two_names.append("b")
    with assert_raises(contains="one name per variable"):
        _ = pairplot(d[0], two_names)

    var ragged = List[List[Float64]]()
    ragged.append(_col(8, 1.0, 0.0))
    ragged.append(_col(5, 1.0, 0.0))
    with assert_raises(contains="same number of rows"):
        _ = pairplot(ragged, two_names)


def test_integer_columns_work_like_float_ones() raises:
    # pairplot is generic over element type, like every other quickplot.
    var cols = List[List[Int]]()
    var a = List[Int]()
    var b = List[Int]()
    for i in range(8):
        a.append(i)
        b.append(i * 2)
    cols.append(a^)
    cols.append(b^)
    var names = List[String]()
    names.append("a")
    names.append("b")
    var c = pairplot(
        cols, names, theme=_theme_pairplot(), cell_width=140, cell_height=110
    )
    assert_true(
        _ink(c, _theme_pairplot()) > 100, "the integer pairplot drew nothing"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
