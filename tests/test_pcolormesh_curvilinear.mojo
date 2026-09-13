"""`pcolormesh` over a curvilinear mesh: one coordinate per grid vertex
rather than one boundary per row and column (#424).

The 1D form sets column widths and row heights independently, so every
cell is an axis-aligned rectangle. That cannot describe a rotated,
sheared, polar or model-output grid, which is most of what a mesh is for
outside a table.

The 2D form takes `(rows + 1) x (cols + 1)` corner arrays, so cell
`(r, c)` is the quadrilateral through its four surrounding vertices.

The discriminator throughout is ink outside the axis-aligned bounding box
of the rectilinear equivalent: a rotated mesh paints pixels a rectangular
one cannot reach, and a rectangular one painted through the new code path
must land in exactly the same place as through the old.
"""

from std.math import cos, sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas

from dataviz import Theme
from dataviz.plot import Plot, render
from _test_helpers import _assert_same_canvas


def _z(rows: Int, cols: Int) -> List[List[Float64]]:
    var z = List[List[Float64]]()
    for r in range(rows):
        var row = List[Float64]()
        for c in range(cols):
            row.append(Float64(r * cols + c))
        z.append(row^)
    return z^


def _edges(n: Int) -> List[Float64]:
    var e = List[Float64]()
    for i in range(n + 1):
        e.append(Float64(i))
    return e^


def _rect_corners(
    rows: Int, cols: Int
) -> Tuple[List[List[Float64]], List[List[Float64]]]:
    """The corner arrays describing exactly the grid `_edges()` describes.

    The bridge between the two forms: the same mesh said both ways must
    render identically, which is what says the new code path is drawing
    the cells it was handed rather than something of its own.

    Args:
        rows: Row count of `z`.
        cols: Column count of `z`.

    Returns:
        `(x_corners, y_corners)`.
    """
    var xs = List[List[Float64]]()
    var ys = List[List[Float64]]()
    for r in range(rows + 1):
        var xr = List[Float64]()
        var yr = List[Float64]()
        for c in range(cols + 1):
            xr.append(Float64(c))
            yr.append(Float64(r))
        xs.append(xr^)
        ys.append(yr^)
    return (xs^, ys^)


def _rotated_corners(
    rows: Int, cols: Int, angle: Float64
) -> Tuple[List[List[Float64]], List[List[Float64]]]:
    """The same grid turned by `angle` about its own centre.

    A rotation is the smallest departure from axis-aligned that the 1D
    form cannot express at all, and it keeps every cell congruent, so a
    difference in the output cannot be blamed on the cells changing size.

    Args:
        rows: Row count of `z`.
        cols: Column count of `z`.
        angle: Rotation in radians.

    Returns:
        `(x_corners, y_corners)`.
    """
    var cx = Float64(cols) / 2.0
    var cy = Float64(rows) / 2.0
    var ca = cos(angle)
    var sa = sin(angle)
    var xs = List[List[Float64]]()
    var ys = List[List[Float64]]()
    for r in range(rows + 1):
        var xr = List[Float64]()
        var yr = List[Float64]()
        for c in range(cols + 1):
            var dx = Float64(c) - cx
            var dy = Float64(r) - cy
            xr.append(cx + dx * ca - dy * sa)
            yr.append(cy + dx * sa + dy * ca)
        xs.append(xr^)
        ys.append(yr^)
    return (xs^, ys^)


def _theme() -> Theme:
    return Theme(show_gridlines=False, show_legend=False)


def _ink(c: Canvas, bg_r: Int, bg_g: Int, bg_b: Int) -> Int:
    var n = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if not (Int(p.r) == bg_r and Int(p.g) == bg_g and Int(p.b) == bg_b):
                n += 1
    return n


def test_a_rectangular_mesh_puts_the_same_colors_in_the_same_cells() raises:
    """The bridge: the same mesh described both ways.

    Cell *interiors* are compared, not the whole canvas. The two paths
    differ at cell boundaries by construction: the rectilinear one snaps
    edges to whole pixels and fills rects, and the curvilinear one fills
    an antialiased path, because a quad has no rectangular outline to
    snap. Measured at 1,439 differing pixels out of 56,000, every one of
    them on a boundary.

    Asserting byte-identity here would be asserting that a quad fill
    behaves like a rect fill, which it does not and should not. What
    matters is that the same cell gets the same color.
    """
    var z = _z(3, 4)
    var corners = _rect_corners(3, 4)
    var rectilinear = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(_edges(4), _edges(3), z)
        .theme(_theme())
        .size(280, 200)
    )
    var curvilinear = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(corners[0], corners[1], z)
        .theme(_theme())
        .size(280, 200)
    )
    # The plot rect is x:[60,260], y:[20,180] at this size with no
    # legend, so a 3x4 grid's cell centres are these.
    var checked = 0
    for r in range(3):
        for c in range(4):
            var px = 60 + Int((Float64(c) + 0.5) * 200.0 / 4.0)
            var py = 20 + Int((Float64(2 - r) + 0.5) * 160.0 / 3.0)
            var a = rectilinear.get_pixel(px, py)
            var b = curvilinear.get_pixel(px, py)
            assert_equal(
                Int(a.r) * 65536 + Int(a.g) * 256 + Int(a.b),
                Int(b.r) * 65536 + Int(b.g) * 256 + Int(b.b),
                "cell ("
                + String(r)
                + ", "
                + String(c)
                + ") at pixel ("
                + String(px)
                + ", "
                + String(py)
                + ") differs between the two forms",
            )
            checked += 1
    assert_equal(checked, 12, "every cell centre was compared")


def test_a_rotated_mesh_differs_from_the_rectangular_one() raises:
    # The property the 1D form cannot express at all.
    var z = _z(3, 4)
    var straight = _rect_corners(3, 4)
    var turned = _rotated_corners(3, 4, 0.4)
    var a = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(straight[0], straight[1], z)
        .theme(_theme())
        .size(280, 200)
    )
    var b = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(turned[0], turned[1], z)
        .theme(_theme())
        .size(280, 200)
    )
    var bg = _theme().background
    var ink_a = _ink(a, Int(bg.r), Int(bg.g), Int(bg.b))
    var ink_b = _ink(b, Int(bg.r), Int(bg.g), Int(bg.b))
    assert_true(ink_a > 100, "the straight mesh drew nothing")
    assert_true(ink_b > 100, "the rotated mesh drew nothing")
    assert_true(
        ink_a != ink_b,
        "rotating the mesh changed no pixels, so the corners were ignored",
    )


def test_the_domain_covers_every_vertex_not_just_the_first_and_last() raises:
    # A rotated grid's leftmost point sits in the middle of a row, so a
    # domain taken from a first and last edge would clip the corners off.
    # With the extent taken from every vertex the whole mesh is inside.
    var z = _z(3, 4)
    var turned = _rotated_corners(3, 4, 0.6)
    var c = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(turned[0], turned[1], z)
        .theme(_theme())
        .size(280, 200)
    )
    # Nothing painted in the outermost ring of the canvas: the mesh is
    # inside the plot rect, which is inset by the margins.
    var bg = _theme().background
    var edge_ink = 0
    for x in range(c.width):
        var top = c.get_pixel(x, 0)
        var bot = c.get_pixel(x, c.height - 1)
        if not (top.r == bg.r and top.g == bg.g and top.b == bg.b):
            edge_ink += 1
        if not (bot.r == bg.r and bot.g == bg.g and bot.b == bg.b):
            edge_ink += 1
    assert_equal(edge_ink, 0, "the mesh spilled off the canvas")


def test_a_corner_array_of_the_wrong_shape_raises() raises:
    var z = _z(3, 4)
    var ok = _rect_corners(3, 4)

    # One row short: needs rows + 1.
    var short_rows = List[List[Float64]]()
    for r in range(3):
        short_rows.append(ok[0][r].copy())
    with assert_raises(contains="one row per grid vertex"):
        _ = render(
            Plot()
            .mark_pcolormesh()
            .encode_pcolormesh(short_rows, ok[1], z)
            .size(280, 200)
        )

    # Right number of rows, one row too short: needs cols + 1.
    var ragged = List[List[Float64]]()
    for r in range(4):
        var row = ok[0][r].copy()
        if r == 2:
            _ = row.pop()
        ragged.append(row^)
    with assert_raises(contains="needs cols + 1"):
        _ = render(
            Plot()
            .mark_pcolormesh()
            .encode_pcolormesh(ragged, ok[1], z)
            .size(280, 200)
        )


def test_the_two_forms_are_exclusive() raises:
    # Calling one encoder after the other must leave the plot describing
    # one mesh, not two. The last call wins.
    var z = _z(3, 4)
    var corners = _rect_corners(3, 4)
    var curvilinear_last = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(_edges(4), _edges(3), z)
        .encode_pcolormesh(corners[0], corners[1], z)
        .theme(_theme())
        .size(280, 200)
    )
    var only_curvilinear = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(corners[0], corners[1], z)
        .theme(_theme())
        .size(280, 200)
    )
    _assert_same_canvas(
        curvilinear_last,
        only_curvilinear,
        "the earlier rectilinear call still affected the render",
    )


def _uniform_sheared_mesh(
    rows: Int, cols: Int
) raises -> Tuple[
    List[List[Float64]], List[List[Float64]], List[List[Float64]]
]:
    """A sheared mesh whose cells all carry the same value.

    One value everywhere means one color everywhere, so the whole
    painted region should be a single solid block and any interior pixel
    that is not that color came from a seam between two cells. Sheared
    rather than rectangular so the quad path runs; a rectangular mesh
    goes through `_fill_cells()` and its merged `fill_rect` runs.

    Args:
        rows: Cell rows.
        cols: Cell columns.

    Returns:
        `(z, x_corners, y_corners)`.
    """
    var z = List[List[Float64]]()
    for _ in range(rows):
        var row = List[Float64]()
        for _ in range(cols):
            row.append(5.0)
        z.append(row^)
    var xc = List[List[Float64]]()
    var yc = List[List[Float64]]()
    for r in range(rows + 1):
        var xr = List[Float64]()
        var yr = List[Float64]()
        for c in range(cols + 1):
            xr.append(Float64(c) + Float64(r) * 0.35)
            yr.append(Float64(r))
        xc.append(xr^)
        yc.append(yr^)
    return (z^, xc^, yc^)


def _key(c: Canvas, x: Int, y: Int) -> Int:
    var p = c.get_pixel(x, y)
    return Int(p.r) * 65536 + Int(p.g) * 256 + Int(p.b)


def test_no_background_leaks_between_neighbouring_cells() raises:
    """#576: the curvilinear mesh used to leak along every shared edge.

    Two anti-aliased fills sharing an edge each blend their coverage
    against the background rather than against each other, so a mesh
    drawn one cell at a time carries a light line along every interior
    boundary. Nothing asserted otherwise, so it had been there since the
    curvilinear path was written: 1,815 interior pixels off the fill
    color, worst by 48 levels, on exactly the mesh below.

    Drawing every face as one `fill_mesh` leaves no interior edges to
    blend against anything, and the same measurement gives zero.

    Only strictly interior pixels are checked. The mesh's outer boundary
    is anti-aliased against the background on purpose, and two columns of
    margin either side keep that out of the count.
    """
    var mesh = _uniform_sheared_mesh(6, 8)
    var img = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(mesh[1], mesh[2], mesh[0])
        .theme(_theme())
        .size(400, 300)
    )

    # The fill is whichever non-background color covers the most pixels.
    var background = (
        Int(_theme().background.r) * 65536
        + Int(_theme().background.g) * 256
        + Int(_theme().background.b)
    )
    var fill = -1
    var best = 0
    var keys = List[Int]()
    var counts = List[Int]()
    for y in range(img.height):
        for x in range(img.width):
            var k = _key(img, x, y)
            if k == background:
                continue
            var found = False
            for i in range(len(keys)):
                if keys[i] == k:
                    counts[i] += 1
                    found = True
                    break
            if not found:
                keys.append(k)
                counts.append(1)
    for i in range(len(keys)):
        if counts[i] > best:
            best = counts[i]
            fill = keys[i]
    assert_true(best > 5000, "the mesh painted almost nothing")

    var strays = 0
    var worst = 0
    for y in range(img.height):
        var first = -1
        var last = -1
        for x in range(img.width):
            if _key(img, x, y) == fill:
                if first == -1:
                    first = x
                last = x
        if first == -1:
            continue
        for x in range(first + 2, last - 1):
            var k = _key(img, x, y)
            if k != fill:
                strays += 1
                var d = max(
                    abs(((k >> 16) & 255) - ((fill >> 16) & 255)),
                    max(
                        abs(((k >> 8) & 255) - ((fill >> 8) & 255)),
                        abs((k & 255) - (fill & 255)),
                    ),
                )
                if d > worst:
                    worst = d
    assert_equal(
        strays,
        0,
        (
            "the mesh leaked at "
            + String(strays)
            + " interior pixels, worst by "
            + String(worst)
            + " levels; every cell carries the same value, so the painted"
            " region should be one solid color"
        ),
    )


def test_a_folded_mesh_still_paints_later_cells_over_earlier_ones() raises:
    """Face order has to survive the move to one `fill_mesh` call.

    A mesh that folds back on itself has two cells covering the same
    pixels, and matplotlib's rule -- the one this has always followed --
    is that the later cell wins. Drawing every face in one call only
    preserves that if the call paints faces in the order given.

    Column 2's vertices are pulled back behind column 1's, so cell
    (0, 1) lies under cell (0, 0)'s right half. The overlap must show
    (0, 1)'s color, which is the higher value and so the lighter end of
    the ramp.
    """
    var z = List[List[Float64]]()
    var row = List[Float64]()
    row.append(0.0)
    row.append(100.0)
    z.append(row^)

    var xc = List[List[Float64]]()
    var yc = List[List[Float64]]()
    for r in range(2):
        var xr = List[Float64]()
        var yr = List[Float64]()
        xr.append(0.0)
        xr.append(4.0)
        xr.append(2.0)  # folded back behind the previous edge
        for _ in range(3):
            yr.append(Float64(r))
        xc.append(xr^)
        yc.append(yr^)

    var img = render(
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(xc, yc, z)
        .theme(_theme())
        .size(320, 220)
    )

    # Sample inside the overlap, which spans data x from 2 to 4.
    var overlap = _key(img, 200, 110)
    # And inside the part only the first cell covers, data x under 2.
    var first_only = _key(img, 100, 110)
    assert_true(
        overlap != first_only,
        (
            "the folded cell did not paint over the one before it: both"
            " samples read "
            + String(overlap)
        ),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
