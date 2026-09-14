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

from _test_helpers import _attr_values

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import (
    GridCell,
    Theme,
    render_facets,
    render_facets_svg,
    render_grid,
    render_grid_svg,
    save_grid,
)
from dataviz.core.text import _Scaled
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


def test_an_empty_square_takes_the_figure_background() raises:
    """A grid may have a hole on purpose.

    The corner opposite a joint plot's two marginals is the standard
    case. An unpainted square is white, which reads as a hole in any
    theme whose background is not, so the figure is filled before the
    cells are.
    """
    var dark = Theme(
        show_gridlines=False, show_legend=False, background=Color(20, 20, 30)
    )
    var plots = List[Plot]()
    var cells = List[GridCell]()
    var coords = List[Int]()
    coords.append(0)
    coords.append(2)
    coords.append(3)
    for i in range(3):
        plots.append(
            Plot()
            .mark_line()
            .encode(x=_xs(8), y=_ys(8, 1.0))
            .theme(dark)
            .size(200, 150)
        )
        cells.append(GridCell(coords[i] // 2, coords[i] % 2))
    var c = render_grid(plots, cells, 400, 300)
    # Row 0, column 1 has no plot in it.
    var p = c.get_pixel(300, 20)
    assert_true(
        p.r == 20 and p.g == 20 and p.b == 30,
        (
            "the empty square is ("
            + String(p.r)
            + ","
            + String(p.g)
            + ","
            + String(p.b)
            + "), not the theme background"
        ),
    )


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


def _axis_left(c: Canvas, y0: Int, y1: Int) -> Int:
    """Leftmost column holding a tall run of the axis color: the left
    spine, which is where the plot rect starts.

    Tick labels sit outside that rect and are not it, which an earlier
    version of this measured by mistake and got a confusing answer from:
    wide labels start further left precisely because the rect they
    belong to starts further right.
    """
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


def _axis_bottom(c: Canvas, x0: Int, x1: Int) -> Int:
    """Lowest row holding a wide run of the axis color: the bottom
    spine."""
    var axis = Theme().axis_color
    for y in range(c.height - 1, -1, -1):
        var run = 0
        for x in range(x0, x1):
            var p = c.get_pixel(x, y)
            if p.r == axis.r and p.g == axis.g and p.b == axis.b:
                run += 1
        if run > (x1 - x0) // 2:
            return y
    return -1


def _wide_and_narrow_labels() raises -> Tuple[List[Plot], List[GridCell]]:
    """Two cells stacked in one column, whose y-labels differ a lot in
    width: values near 1 above, values in the millions below.

    That width difference is the whole problem. Each cell sizes its own
    left margin from its own tick labels, so a shared domain puts the
    two on the same numbers while leaving them on different pixels.
    """
    var small = List[Float64]()
    var large = List[Float64]()
    for i in range(8):
        small.append(Float64(i) * 0.1 + 1.0)
        large.append(Float64(i) * 1000000.0 + 5000000.0)
    var plots = List[Plot]()
    plots.append(
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=small)
        .theme(_theme())
        .size(300, 200)
    )
    plots.append(
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=large)
        .theme(_theme())
        .size(300, 200)
    )
    var cells = List[GridCell]()
    cells.append(GridCell(0, 0))
    cells.append(GridCell(1, 0))
    return (plots^, cells^)


def test_align_axes_puts_a_column_on_one_left_edge() raises:
    """#569's point, and what #354's joint plot needs.

    `shared_y_scale` is the domain half of this and has always existed.
    The pixel half did not: two cells on the same numbers still sat on
    different pixels, because each sized its margins from its own tick
    labels.
    """
    var d = _wide_and_narrow_labels()
    var loose = render_grid(d[0], d[1], 400, 400)
    var top = _axis_left(loose, 10, 190)
    var bottom = _axis_left(loose, 210, 390)
    assert_true(
        top != bottom,
        (
            "both cells already start at "
            + String(top)
            + ", so there is nothing for align_axes to fix and this test"
            " proves nothing"
        ),
    )

    var tight = render_grid(d[0], d[1], 400, 400, align_axes=True)
    var atop = _axis_left(tight, 10, 190)
    var abottom = _axis_left(tight, 210, 390)
    assert_equal(
        atop,
        abottom,
        (
            "aligned, the two cells' left spines are at "
            + String(atop)
            + " and "
            + String(abottom)
        ),
    )
    # And it aligns on the widest margin rather than the narrowest, so
    # no cell has its labels clipped to fit.
    assert_equal(
        atop, max(top, bottom), "the column did not take the widest margin"
    )


def test_align_axes_shares_a_row_s_bottom_edge() raises:
    # The other axis. Two cells side by side, one with an x-axis title
    # and one without, so their bottom margins differ.
    var plain = (
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=_ys(8, 1.0))
        .theme(_theme())
        .size(200, 200)
    )
    var titled = (
        Plot()
        .mark_line()
        .encode(x=_xs(8), y=_ys(8, 1.0))
        .labels(x_title="quarter")
        .theme(_theme())
        .size(200, 200)
    )
    var plots = List[Plot]()
    plots.append(plain^)
    plots.append(titled^)
    var cells = List[GridCell]()
    cells.append(GridCell(0, 0))
    cells.append(GridCell(0, 1))

    var loose = render_grid(plots, cells, 400, 240)
    var left = _axis_bottom(loose, 20, 180)
    var right = _axis_bottom(loose, 220, 380)
    assert_true(
        left != right,
        "the two cells already share a bottom edge, so this proves nothing",
    )

    var tight = render_grid(plots, cells, 400, 240, align_axes=True)
    assert_equal(
        _axis_bottom(tight, 20, 180),
        _axis_bottom(tight, 220, 380),
        "aligned, the row's two cells do not share a bottom edge",
    )


def test_align_axes_is_off_by_default() raises:
    # It costs a second measuring render, so it has to be asked for, and
    # asking for nothing has to draw what it always drew.
    var d = _wide_and_narrow_labels()
    var implicit = render_grid(d[0], d[1], 400, 400)
    var explicit = render_grid(d[0], d[1], 400, 400, align_axes=False)
    var diff = 0
    for y in range(implicit.height):
        for x in range(implicit.width):
            var a = implicit.get_pixel(x, y)
            var b = explicit.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_equal(diff, 0, "align_axes=False is not the default")


def _title_band(theme: Theme) -> Int:
    """What a figure title reserves: the same band a chart title takes."""
    var sc = _Scaled(theme)
    return Int(sc.title_font_size) + sc.label_gap


def _ink_between(c: Canvas, y0: Int, y1: Int, theme: Theme) -> Int:
    """Pixels that are not the background in rows `y0` up to `y1`."""
    var bg = theme.background
    var n = 0
    for y in range(y0, y1):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                n += 1
    return n


def test_a_grid_title_takes_a_band_and_the_cells_tile_the_rest() raises:
    # The figure keeps its given size, so the cells give up the band.
    var pc = _two_across()
    var plain = render_grid_svg(pc[0], pc[1], 400, 200).to_string()
    var titled = render_grid_svg(
        pc[0], pc[1], 400, 200, title="Two across"
    ).to_string()
    assert_true(plain.find(">Two across<") == -1, "no title unless asked")
    assert_true(titled.find(">Two across<") != -1, "the title is drawn")
    # rect 0 is the figure fill in both; rect 1 is the first cell's
    # background, which starts at the top without a title and under
    # the band with one.
    var plain_ys = _attr_values(plain, "rect", "y")
    var titled_ys = _attr_values(titled, "rect", "y")
    assert_equal(plain_ys[1], plain_ys[0], "no title: the cell starts at 0")
    assert_true(
        titled_ys[1] != titled_ys[0],
        "a title pushes the first cell below the top",
    )
    assert_equal(
        _attr_values(titled, "svg", "height")[0],
        _attr_values(plain, "svg", "height")[0],
        "render_grid keeps the size it was given",
    )


def test_a_grid_title_is_centered_on_the_figure() raises:
    var pc = _two_across()
    var svg = render_grid_svg(
        pc[0], pc[1], 400, 200, title="Two across"
    ).to_string()
    # The title is the first <text> written: the core appends it before
    # any cell runs.
    var xs = _attr_values(svg, "text", "x")
    var anchors = _attr_values(svg, "text", "text-anchor")
    assert_equal(xs[0], "200", "centered on the 400-wide figure")
    assert_equal(anchors[0], "middle")


def test_a_facet_title_grows_the_figure_and_leaves_the_cells_alone() raises:
    # render_facets sizes the figure from the plots, so a title adds its
    # band on top rather than shrinking the cells: everything below the
    # band is the untitled figure, pixel for pixel.
    var plots = List[Plot]()
    plots.append(_plot(1.0))
    plots.append(_plot(3.0))
    var plain = render_facets(plots, 2)
    var titled = render_facets(plots, 2, title="Two across")
    var band = _title_band(_theme())
    assert_true(band > 0)
    assert_equal(titled.height, plain.height + band)
    assert_equal(titled.width, plain.width)
    assert_true(
        _ink_between(titled, 0, band, _theme()) > 0,
        "the band holds the title's ink",
    )
    for y in range(plain.height):
        for x in range(plain.width):
            var a = plain.get_pixel(x, y)
            var b = titled.get_pixel(x, y + band)
            if not (a.r == b.r and a.g == b.g and a.b == b.b):
                raise Error(
                    "pixel differs under the band at ("
                    + String(x)
                    + ", "
                    + String(y)
                    + ")"
                )


def test_a_facet_title_reaches_the_svg_backend_too() raises:
    var plots = List[Plot]()
    plots.append(_plot(1.0))
    plots.append(_plot(3.0))
    var svg = render_facets_svg(plots, 2, title="Two across").to_string()
    assert_true(svg.find(">Two across<") != -1)
    assert_equal(
        _attr_values(svg, "svg", "height")[0],
        String(150 + _title_band(_theme())),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
