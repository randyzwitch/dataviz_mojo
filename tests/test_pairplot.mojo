"""A scatterplot matrix over every pair of variables (#353).

The feature is the *scales*, not the grid. `render_facets()` already lays
plots out in cells; what makes a pairplot is that column `j` shares one
x-domain down its height and row `i` shares one y-domain across its
width, so every panel showing a variable draws it at the same size.

A grid of independently scaled cells looks identical and means something
else, which is why the shared-domain tests below are the ones that matter
and the "it rendered" test is the least interesting.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas

from dataviz import Theme, pairplot


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


def _theme() -> Theme:
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


def test_the_figure_is_n_by_n_cells() raises:
    var d = _three()
    var c = pairplot(
        d[0], d[1], theme=_theme(), cell_width=160, cell_height=120
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
        cols, names, theme=_theme(), cell_width=140, cell_height=110
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
        d[0], d[1], theme=_theme(), cell_width=160, cell_height=120
    )

    var changed = List[List[Float64]]()
    changed.append(d[0][0].copy())
    changed.append(d[0][1].copy())
    changed.append(d[0][1].copy())  # was "falling"
    var b = pairplot(
        changed, d[1], theme=_theme(), cell_width=160, cell_height=120
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
        d[0], d[1], theme=_theme(), cell_width=160, cell_height=120
    )
    var changed = List[List[Float64]]()
    changed.append(d[0][0].copy())
    changed.append(d[0][1].copy())
    changed.append(d[0][1].copy())
    var b = pairplot(
        changed, d[1], theme=_theme(), cell_width=160, cell_height=120
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
    var theme = _theme()
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
        cols, names, theme=_theme(), cell_width=140, cell_height=110
    )
    assert_true(_ink(c, _theme()) > 100, "the integer pairplot drew nothing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
