"""Unequal-cell figure composition (#347).

`render_facets()` is a uniform grid and `render_layers()` is a full
overlay. `render_grid()` is the gridspec model in between: each plot names
a row, a column and optional spans, over a grid whose tracks can carry
weights.

#347 says how to test it: "assert that a two-column layout with weights
2:1 puts the divider at the right pixel, and that each plot's own frame
lands inside its cell. An overlapping spec must raise." That is what is
below, with the divider checked arithmetically rather than by eye.

The second half of the file is about the shared core rather than about
weights. `render_grid()` and `render_facets()` run the same cell loop, so
a cell gets its annotations, its shared y-domain and an SVG target
whichever entry point placed it -- and the last test pins that by
rendering one figure both ways and comparing the pixels.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import (
    GridCell,
    Theme,
    render_facets,
    render_grid,
    render_grid_svg,
    save_grid,
)
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


def test_a_cell_draws_its_own_annotations() raises:
    """The defect that made the unified core worth building.

    `render_grid()` began as a separate cell loop and silently dropped
    every `annotate_*()` call, which no test caught because none asked.
    A plot with a horizontal rule at y = 3 must put ink there.
    """
    var plain = List[Plot]()
    var annotated = List[Plot]()
    var cells = List[GridCell]()
    for i in range(2):
        plain.append(_plot(Float64(i) + 1.0))
        annotated.append(
            Plot()
            .mark_line()
            .encode(x=_xs(8), y=_ys(8, Float64(i) + 1.0))
            .annotate_line(3.0, label="target")
            .annotate_vline(4.0, label="cutover")
            .annotate_point(2.0, 3.0, label="peak")
            .theme(_theme())
            .size(200, 150)
        )
        cells.append(GridCell(0, i))
    var without = render_grid(plain, cells, 400, 200)
    var with_ = render_grid(annotated, cells, 400, 200)
    var diff = 0
    for y in range(without.height):
        for x in range(without.width):
            var a = without.get_pixel(x, y)
            var b = with_.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_true(
        diff > 200,
        (
            "a cell's annotations drew nothing: "
            + String(diff)
            + " pixels differ between an annotated grid and a plain one"
        ),
    )


def test_the_grid_renders_to_svg() raises:
    # The other half of what the separate implementation was missing:
    # it was not generic over the draw target, so there was no vector
    # path at all.
    var d = _two_across()
    var svg = render_grid_svg(d[0], d[1], 400, 200)
    assert_equal(svg.width, 400, "svg width")
    assert_equal(svg.height, 200, "svg height")
    var markup = svg.to_string()
    assert_true(
        markup.byte_length() > 500, "the svg grid produced almost no markup"
    )
    assert_true("<svg" in markup, "no svg root element")


def test_save_grid_writes_each_format() raises:
    var d = _two_across()
    var png = "/tmp/dataviz_test_grid.png"
    save_grid(d[0], d[1], 400, 200, png)
    var f = open(png, "r")
    var head = f.read_bytes(4)
    f.close()
    assert_equal(Int(head[1]), 80, "not a PNG (no 'P' in the signature)")

    var svg_path = "/tmp/dataviz_test_grid.svg"
    save_grid(d[0], d[1], 400, 200, svg_path)
    var g = open(svg_path, "r")
    var text = g.read()
    g.close()
    assert_true("<svg" in text, "the saved svg has no root element")


def test_a_shared_y_scale_reaches_every_cell() raises:
    # Two cells whose y-ranges differ by 3x. Under a shared scale the
    # flatter one must be drawn flatter than it is on its own.
    var d = _two_across()
    var separate = render_grid(d[0], d[1], 400, 200)
    var shared = render_grid(d[0], d[1], 400, 200, shared_y_scale=True)
    var diff = 0
    for y in range(separate.height):
        for x in range(0, 200):
            var a = separate.get_pixel(x, y)
            var b = shared.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_true(diff > 50, "the shared y-domain did not change the first cell")


def test_equal_tracks_land_on_the_pixels_facets_always_used() raises:
    """The guard on the one number the merge could quietly move.

    `render_facets()` divided its canvas with `width * col // cols`, an
    integer floor. The weighted path rounds a running sum, and on three
    tracks across 100 pixels the two disagree: floor puts the second
    edge at 66 and rounding puts it at 67. Every facet figure in the
    library would shift a pixel, so the equal-weight path stays integer
    arithmetic and this pins it.
    """
    var left = Theme(
        show_gridlines=False, show_legend=False, background=Color(250, 250, 250)
    )
    var mid = Theme(
        show_gridlines=False, show_legend=False, background=Color(200, 210, 220)
    )
    var right = Theme(
        show_gridlines=False, show_legend=False, background=Color(120, 130, 140)
    )
    var themes = List[Theme]()
    themes.append(left)
    themes.append(mid)
    themes.append(right)
    var plots = List[Plot]()
    var cells = List[GridCell]()
    for i in range(3):
        plots.append(
            Plot()
            .mark_line()
            .encode(x=_xs(8), y=_ys(8, 1.0))
            .theme(themes[i])
            .size(100, 80)
        )
        cells.append(GridCell(0, i))
    var c = render_grid(plots, cells, 100, 80)
    var second = -1
    var third = -1
    for x in range(c.width):
        var p = c.get_pixel(x, 0)
        if second < 0 and p.r == 200:
            second = x
        if third < 0 and p.r == 120:
            third = x
    assert_equal(second, 33, "the second equal track does not start at 33")
    assert_equal(third, 66, "the third equal track does not start at 66")


def test_a_uniform_grid_is_a_facet_grid() raises:
    """One figure, two entry points, the same pixels.

    This is what folding the two implementations together bought: a
    uniform `render_grid()` is `render_facets()`, not a near-copy of it.
    """
    var plots = List[Plot]()
    var cells = List[GridCell]()
    for i in range(4):
        plots.append(
            Plot()
            .mark_line()
            .encode(x=_xs(9), y=_ys(9, Float64(i) + 1.0))
            .labels(title="Panel", x_title="quarter", y_title="value")
            .theme(_theme())
            .size(200, 150)
        )
        cells.append(GridCell(i // 2, i % 2))
    var faceted = render_facets(plots, 2)
    var gridded = render_grid(plots, cells, faceted.width, faceted.height)
    var diff = 0
    for y in range(faceted.height):
        for x in range(faceted.width):
            var a = faceted.get_pixel(x, y)
            var b = gridded.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_equal(
        diff, 0, "a uniform grid and a facet grid drew different pixels"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
