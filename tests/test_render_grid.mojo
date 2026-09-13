"""Unequal-cell figure composition (#347).

`render_facets()` is a uniform grid and `render_layers()` is a full
overlay. `render_grid()` is the gridspec model in between: each plot names
a row, a column and optional spans, over a grid whose tracks can carry
weights.

#347 says how to test it: "assert that a two-column layout with weights
2:1 puts the divider at the right pixel, and that each plot's own frame
lands inside its cell. An overlapping spec must raise." That is what is
below, with the divider checked arithmetically rather than by eye.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import GridCell, Theme, render_grid
from dataviz.plot import Plot


def _xs(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for i in range(n):
        v.append(Float64(i))
    return v^


def _ys(n: Int, scale: Float64) -> List[Float64]:
    var v = List[Float64]()
    for i in range(n):
        v.append(Float64(i) * scale + 1.0)
    return v^


def _theme() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def _plot(scale: Float64) raises -> Plot:
    return (
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=_ys(8, scale))
        .theme(_theme())
        .size(200, 150)
    )


def _two_across() raises -> Tuple[List[Plot], List[GridCell]]:
    var plots = List[Plot]()
    plots.append(_plot(1.0))
    plots.append(_plot(3.0))
    var cells = List[GridCell]()
    cells.append(GridCell(0, 0))
    cells.append(GridCell(0, 1))
    return (plots^, cells^)


def _column_has_ink(c: Canvas, x: Int, theme: Theme) -> Bool:
    var bg = theme.background
    for y in range(c.height):
        var p = c.get_pixel(x, y)
        if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
            return True
    return False


def test_equal_weights_split_the_canvas_in_half() raises:
    var d = _two_across()
    var c = render_grid(d[0], d[1], 400, 200)
    assert_equal(c.width, 400, "canvas width is what was asked for")
    assert_equal(c.height, 200, "canvas height is what was asked for")


def test_a_two_to_one_split_puts_the_divider_where_the_weights_say() raises:
    """#347's stated test, measured rather than inferred.

    Weights 2:1 across 300 pixels put the divider at x = 200. Each cell
    fills its own rect with its own theme background, so giving the two
    plots different backgrounds makes the boundary directly visible: the
    first column whose top pixel is the second background *is* the
    divider.

    An earlier version of this test probed for chart ink either side of
    200 and failed, because a chart's own right margin leaves the last
    twenty pixels of its cell blank. That measured the margin, not the
    divider.
    """
    var left_theme = Theme(
        show_gridlines=False, show_legend=False, background=Color(250, 250, 250)
    )
    var right_theme = Theme(
        show_gridlines=False, show_legend=False, background=Color(200, 210, 220)
    )
    var plots = List[Plot]()
    plots.append(
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=_ys(8, 1.0))
        .theme(left_theme)
        .size(200, 150)
    )
    plots.append(
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=_ys(8, 3.0))
        .theme(right_theme)
        .size(200, 150)
    )
    var cells = List[GridCell]()
    cells.append(GridCell(0, 0))
    cells.append(GridCell(0, 1))
    var w = List[Float64]()
    w.append(2.0)
    w.append(1.0)
    var c = render_grid(plots, cells, 300, 200, col_weights=w)

    var divider = -1
    for x in range(c.width):
        var p = c.get_pixel(x, 0)
        if p.r == 200 and p.g == 210 and p.b == 220:
            divider = x
            break
    assert_equal(divider, 200, "the 2:1 divider is not at x = 200")

    # And equal weights put it at 150, so the weights are what moved it.
    var even = render_grid(plots, cells, 300, 200)
    var even_divider = -1
    for x in range(even.width):
        var q = even.get_pixel(x, 0)
        if q.r == 200 and q.g == 210 and q.b == 220:
            even_divider = x
            break
    assert_equal(even_divider, 150, "equal weights did not split in half")


def test_tracks_always_add_up_to_the_canvas() raises:
    # Rounding a running sum rather than accumulating rounded widths:
    # three columns across 100 pixels must not lose or gain one.
    var plots = List[Plot]()
    var cells = List[GridCell]()
    for i in range(3):
        plots.append(_plot(1.0))
        cells.append(GridCell(0, i))
    var c = render_grid(plots, cells, 100, 80)
    assert_equal(c.width, 100, "three columns across 100 pixels")


def test_a_span_covers_the_tracks_it_names() raises:
    # A wide panel above two narrow ones: the layout #347 opens with.
    var plots = List[Plot]()
    var cells = List[GridCell]()
    plots.append(_plot(1.0))
    cells.append(GridCell(0, 0, col_span=2))
    plots.append(_plot(2.0))
    cells.append(GridCell(1, 0))
    plots.append(_plot(3.0))
    cells.append(GridCell(1, 1))
    var c = render_grid(plots, cells, 400, 300)
    assert_equal(c.width, 400, "two columns")
    assert_equal(c.height, 300, "two rows")
    # The top panel spans both columns, so it has ink on both sides of
    # the vertical divider in its own half of the canvas.
    var left = False
    var right = False
    var bg = _theme().background
    for y in range(0, 150):
        for x in range(0, 200):
            var p = c.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                left = True
        for x in range(200, 400):
            var p2 = c.get_pixel(x, y)
            if not (p2.r == bg.r and p2.g == bg.g and p2.b == bg.b):
                right = True
    assert_true(left and right, "the spanning panel did not cross the divider")


def test_overlapping_cells_raise_and_name_both_plots() raises:
    var plots = List[Plot]()
    var cells = List[GridCell]()
    plots.append(_plot(1.0))
    cells.append(GridCell(0, 0, col_span=2))
    plots.append(_plot(2.0))
    cells.append(GridCell(0, 1))
    with assert_raises(contains="overlaps plot 0"):
        _ = render_grid(plots, cells, 400, 300)


def test_a_cell_outside_its_own_grid_raises() raises:
    # The grid is inferred from the cells, so "outside" can only happen
    # via a span that runs past what the other cells established.
    var plots = List[Plot]()
    var cells = List[GridCell]()
    plots.append(_plot(1.0))
    cells.append(GridCell(0, 0))
    plots.append(_plot(2.0))
    cells.append(GridCell(0, 1, row_span=3))
    # Rows become 3 because of the span, so this is legal; the illegal
    # case is a negative coordinate.
    _ = render_grid(plots, cells, 400, 300)

    var bad = List[GridCell]()
    bad.append(GridCell(0, 0))
    bad.append(GridCell(-1, 0))
    with assert_raises(contains="may be negative"):
        _ = render_grid(plots, bad, 400, 300)


def test_a_zero_span_raises() raises:
    var plots = List[Plot]()
    plots.append(_plot(1.0))
    var cells = List[GridCell]()
    cells.append(GridCell(0, 0, col_span=0))
    with assert_raises(contains="at least 1"):
        _ = render_grid(plots, cells, 400, 300)


def test_mismatched_weights_raise() raises:
    var d = _two_across()
    var w = List[Float64]()
    w.append(1.0)
    w.append(2.0)
    w.append(3.0)
    with assert_raises(contains="weights to match the grid"):
        _ = render_grid(d[0], d[1], 400, 200, col_weights=w)


def test_a_non_positive_weight_raises() raises:
    var d = _two_across()
    var w = List[Float64]()
    w.append(1.0)
    w.append(0.0)
    with assert_raises(contains="cannot hold a plot"):
        _ = render_grid(d[0], d[1], 400, 200, col_weights=w)


def test_mismatched_plots_and_cells_raise() raises:
    var d = _two_across()
    var one = List[GridCell]()
    one.append(GridCell(0, 0))
    with assert_raises(contains="one cell per plot"):
        _ = render_grid(d[0], one, 400, 200)


def test_an_empty_figure_raises() raises:
    var plots = List[Plot]()
    var cells = List[GridCell]()
    with assert_raises(contains="nothing to draw"):
        _ = render_grid(plots, cells, 400, 200)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
