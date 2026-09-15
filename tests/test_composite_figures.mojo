"""Figures assembled from several plots: jointplot() and pairplot().

One module rather than 2: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from canvas.buffer import Canvas
from canvas.color import Color
from dataviz import (
    Theme,
    clustermap,
    clustermap_pdf,
    clustermap_svg,
    jointplot,
    jointplot_pdf,
    jointplot_svg,
    pairplot,
    pairplot_pdf,
    pairplot_svg,
    save,
)
from dataviz.core.cluster import linkage
from dataviz.grid.heatmap import heatmap
from dataviz.plot import render_svg
from _test_helpers import _attr_values, _count_tag


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


# ==== clustermap (#355) ====


def _interleaved() -> List[List[Float64]]:
    """Six rows in two shapes, interleaved, so the arrival order cannot
    be mistaken for the clustered one: rows 0, 2, 4 rise and 1, 3, 5
    fall.
    """
    var out = List[List[Float64]]()
    for i in range(6):
        var row = List[Float64]()
        for c in range(4):
            if i % 2 == 0:
                row.append(10.0 + Float64(c) * 10.0 + Float64(i))
            else:
                row.append(90.0 - Float64(c) * 10.0 + Float64(i))
        out.append(row^)
    return out^


def _row_names() -> List[String]:
    var out: List[String] = ["r0", "r1", "r2", "r3", "r4", "r5"]
    return out^


def _col_names() -> List[String]:
    var out: List[String] = ["c0", "c1", "c2", "c3"]
    return out^


def test_a_clustermap_is_the_size_it_was_asked_for() raises:
    var c = clustermap(
        _interleaved(), _row_names(), _col_names(), width=700, height=600
    )
    assert_equal(c.width, 700)
    assert_equal(c.height, 600)


def test_a_clustermap_reorders_its_rows_into_groups() raises:
    # The whole feature. The rows arrive interleaved and have to come
    # out with each shape contiguous.
    var svg = render_grid_svg_of_clustermap()
    var order = List[Int]()
    var at = 0
    while True:
        var best = -1
        var best_at = 0
        for i in range(6):
            var needle = ">r" + String(i) + "<"
            var found = svg.find(needle, at)
            if found >= 0 and (best < 0 or found < best_at):
                best = i
                best_at = found
        if best < 0:
            break
        order.append(best)
        at = best_at + 1
    assert_equal(len(order), 6, "every row is labeled once")
    var switches = 0
    for i in range(1, len(order)):
        if order[i] % 2 != order[i - 1] % 2:
            switches += 1
    assert_equal(switches, 1, "each shape's rows are contiguous")


def render_grid_svg_of_clustermap() raises -> String:
    """The clustermap's SVG, for reading its label order.

    A helper rather than a test: `clustermap()` returns a raster canvas,
    so the labels are read from an equivalent figure rendered to vector.
    """
    var tree = linkage(_interleaved())
    var xs = List[String]()
    var ys = List[String]()
    var vals = List[Float64]()
    var rows = _interleaved()
    var names = _row_names()
    var cols = _col_names()
    for r in range(6):
        var source = tree.leaf_order[r]
        for c in range(4):
            xs.append(cols[c])
            ys.append(names[source])
            vals.append(rows[source][c])
    return render_svg(heatmap(xs, ys, vals)).to_string()


def test_not_clustering_an_axis_keeps_its_order() raises:
    # Both figures are the same size, so the one difference is the
    # order; a matrix that already has a meaningful order down one axis
    # should be able to keep it.
    var clustered = clustermap(
        _interleaved(), _row_names(), _col_names(), width=700, height=600
    )
    var rows_only = clustermap(
        _interleaved(),
        _row_names(),
        _col_names(),
        width=700,
        height=600,
        cluster_cols=False,
    )
    assert_equal(rows_only.width, clustered.width)
    var different = 0
    for y in range(0, clustered.height, 11):
        for x in range(0, clustered.width, 11):
            var a = clustered.get_pixel(x, y)
            var b = rows_only.get_pixel(x, y)
            if not (a.r == b.r and a.g == b.g and a.b == b.b):
                different += 1
    assert_true(
        different > 0,
        "dropping the column tree changes the figure",
    )


def test_a_clustermap_checks_its_input() raises:
    var empty = List[List[Float64]]()
    with assert_raises(contains="must not be empty"):
        _ = clustermap(empty)

    var two: List[String] = ["a", "b"]
    with assert_raises(contains="one row label per row"):
        _ = clustermap(_interleaved(), two)

    with assert_raises(contains="ratio must be above zero"):
        _ = clustermap(_interleaved(), _row_names(), _col_names(), ratio=0.0)


# ==== vector output for the composite figures (#620) ====
# These two were the only charts in the library that could not be
# exported as vector, because they return a rendered raster canvas.


def test_a_vector_pairplot_draws_the_same_panels() raises:
    # The panels are built once and handed to whichever render_facets
    # the caller asked for, so the two forms cannot drift. The check:
    # the same number of cells with the same axis titles.
    var data = _three()
    var raster = pairplot(data[0], data[1], theme=_theme_pairplot())
    var svg = pairplot_svg(
        data[0], data[1], theme=_theme_pairplot()
    ).to_string()
    assert_equal(
        Int(Float64(_attr_values(svg, "svg", "width")[0])),
        raster.width,
        "the vector figure is the same size",
    )
    assert_equal(
        Int(Float64(_attr_values(svg, "svg", "height")[0])), raster.height
    )
    for name in data[1]:
        assert_true(
            svg.find(">" + name + "<") != -1,
            "every variable is still named: " + name,
        )
    # Nine panels of three variables, each with its own axis frame.
    assert_true(_count_tag(svg, "circle") > 0, "the scatters drew")
    assert_true(_count_tag(svg, "rect") > 9, "and the histograms")


def test_a_vector_jointplot_draws_the_same_panels() raises:
    var s = _samples(120)
    var raster = jointplot(s[0], s[1], theme=_theme(), width=400, height=400)
    var svg = jointplot_svg(
        s[0], s[1], theme=_theme(), width=400, height=400, title="Joint"
    ).to_string()
    assert_equal(Int(Float64(_attr_values(svg, "svg", "width")[0])), 400)
    assert_equal(
        Int(Float64(_attr_values(svg, "svg", "height")[0])), raster.height
    )
    assert_true(svg.find(">Joint<") != -1, "the title carries over")
    assert_true(_count_tag(svg, "circle") > 0, "the scatter drew")


def test_saving_a_vector_figure_writes_markup() raises:
    var s = _samples(120)
    var path = "/tmp/dataviz_test_jointplot.svg"
    save(
        jointplot_svg(s[0], s[1], theme=_theme(), width=300, height=300),
        path,
    )
    var f = open(path, "r")
    var text = f.read()
    f.close()
    assert_true("<svg" in text, "the file is a document")
    assert_true("</svg>" in text)


def test_saving_vector_markup_to_a_raster_path_raises() raises:
    # A clear refusal beats writing markup into a file named .png.
    var s = _samples(120)
    with assert_raises(contains="vector markup, not pixels"):
        save(
            jointplot_svg(s[0], s[1], theme=_theme(), width=300, height=300),
            "/tmp/dataviz_test_jointplot.png",
        )


def test_a_vector_clustermap_draws_the_same_figure() raises:
    # The third composite figure, split the same way.
    var raster = clustermap(
        _interleaved(), _row_names(), _col_names(), width=700, height=600
    )
    var svg = clustermap_svg(
        _interleaved(),
        _row_names(),
        _col_names(),
        width=700,
        height=600,
        title="Clustered",
    ).to_string()
    assert_equal(Int(Float64(_attr_values(svg, "svg", "width")[0])), 700)
    assert_equal(
        Int(Float64(_attr_values(svg, "svg", "height")[0])), raster.height
    )
    assert_true(svg.find(">Clustered<") != -1, "the title carries over")
    for name in _row_names():
        assert_true(
            svg.find(">" + name + "<") != -1, "every row is still named"
        )


# ==== every composite can produce a PDF too (#372) ====
# `jointplot`, `pairplot` and `clustermap` got vector output in #620,
# and nothing for PDF, so a publication workflow could reach a
# composition in SVG and not in the format a journal asks for.
#
# These assert the document rather than its bytes. A PDF embeds the
# font program, and the CI matrix installs DejaVu from apt on Linux and
# brew on macOS -- the same glyph outlines, different file bytes -- so
# a byte-level assertion here would fail on one platform for a
# difference that is not a regression. What is stable, and what these
# check, is that a real PDF came out with the figure's own page size.


def _is_pdf(data: List[UInt8]) -> Bool:
    """Whether `data` opens with the PDF magic bytes, `%PDF`."""
    if len(data) < 4:
        return False
    return data[0] == 37 and data[1] == 80 and data[2] == 68 and data[3] == 70


def test_a_jointplot_renders_to_pdf() raises:
    var xy = _samples(40)
    var doc = jointplot_pdf(xy[0], xy[1], width=360, height=360)
    assert_equal(doc.width, 360, "the page is not the figure's width")
    assert_equal(doc.height, 360, "the page is not the figure's height")
    assert_true(_is_pdf(doc.to_bytes()), "jointplot_pdf wrote no PDF")


def test_a_pairplot_renders_to_pdf() raises:
    var cols = _three()
    var doc = pairplot_pdf(cols[0], cols[1], cell_width=140, cell_height=120)
    assert_true(doc.width > 0, "the page has no width")
    assert_true(_is_pdf(doc.to_bytes()), "pairplot_pdf wrote no PDF")


def test_a_clustermap_renders_to_pdf() raises:
    var doc = clustermap_pdf(_interleaved(), width=420, height=360)
    assert_equal(doc.width, 420, "the page is not the figure's width")
    assert_true(_is_pdf(doc.to_bytes()), "clustermap_pdf wrote no PDF")


def test_the_same_figure_gives_the_same_pdf_twice() raises:
    # Reproducibility on one machine, which is what `save()` promises a
    # caller re-exporting the same chart. Cross-machine is a different
    # question and an open one -- see #631.
    var xy = _samples(40)
    var a = jointplot_pdf(xy[0], xy[1], width=360, height=360)
    var b = jointplot_pdf(xy[0], xy[1], width=360, height=360)
    var ab = a.to_bytes()
    var bb = b.to_bytes()
    assert_equal(len(ab), len(bb), "two renders gave different byte counts")
    var same = True
    for i in range(len(ab)):
        if ab[i] != bb[i]:
            same = False
            break
    assert_true(same, "the same figure gave two different PDFs")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
