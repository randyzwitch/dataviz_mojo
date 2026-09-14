"""Marks over a field or a mesh: curvilinear pcolormesh(), Gouraud-shaded tripcolor(),
the public triangulation, quiver() and streamplot().

One module rather than 5: every test module pays the same dependency
compilation, so the suite is organized by family (#605).
"""

from std.math import cos, pi, sin, sqrt
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from canvas.buffer import Canvas
from canvas.color import Color
from dataviz import Theme, Triangulation, delaunay, streamplot
from dataviz.core.colormaps import viridis
from dataviz.core.theme import Theme
from dataviz.multivariate.quiver import _auto_pixels_per_unit, quiver
from dataviz.multivariate.streamplot import (
    _Line,
    _Occupancy,
    _STEP,
    _build_field,
    _streamlines,
    _trace,
)
from dataviz.multivariate.triplot import tripcolor
from dataviz.plot import Plot, render, render_svg
from _test_helpers import (
    _assert_same_canvas,
    _attr_values,
    _count_color,
    _count_tag,
)


# ==== from test_pcolormesh_curvilinear.mojo ====
# `pcolormesh` over a curvilinear mesh: one coordinate per grid vertex
# rather than one boundary per row and column (#424).
#
# The 1D form sets column widths and row heights independently, so every
# cell is an axis-aligned rectangle. That cannot describe a rotated,
# sheared, polar or model-output grid, which is most of what a mesh is for
# outside a table.
#
# The 2D form takes `(rows + 1) x (cols + 1)` corner arrays, so cell
# `(r, c)` is the quadrilateral through its four surrounding vertices.
#
# The discriminator throughout is ink outside the axis-aligned bounding box
# of the rectilinear equivalent: a rotated mesh paints pixels a rectangular
# one cannot reach, and a rectangular one painted through the new code path
# must land in exactly the same place as through the old.


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


# ==== from test_gouraud.mojo ====
# Gouraud shading for `Mark.TRIPCOLOR` (#398).
#
# Flat shading gives each triangle one color, from the mean of its three
# vertex values. It is the right default -- a flat fill says "this
# triangle has this value", which is what the data supports -- but it
# makes a smooth field look faceted, and the facets are an artifact of
# where the samples happened to fall rather than anything in the data.
#
# #398 says how to test the difference, and it is a good test because it
# does not depend on the triangulation: over a linear ramp `z = x`, a
# Gouraud-shaded pixel's color is a function of its own x alone, so two
# pixels at the same x in *different* triangles must match. Under flat
# shading they do not, which is exactly the artifact.
#
# The issue's plan was recursive subdivision, because no drawing primitive
# could interpolate across a face. canvas_mojo v0.35.0 added
# `fill_mesh_shaded`, which does it directly, so the subdivision is not
# needed and is not here.


def _theme_gouraud() -> Theme:
    return Theme(
        color_ramp=viridis(),
        show_gridlines=False,
        show_legend=False,
        raster_supersample=1,
    )


def _ramp_samples() -> Tuple[List[Float64], List[Float64], List[Float64]]:
    """A coarse scatter over a square, with `z = x`.

    Coarse on purpose: the faceting Gouraud removes is only visible when
    the mesh is coarse relative to the field. The four corners are
    pinned so the hull is the whole square and the sampled interior is
    well inside it.
    """
    var xs: List[Float64] = [0.0, 10.0, 10.0, 0.0]
    var ys: List[Float64] = [0.0, 0.0, 10.0, 10.0]
    var seed = 20260913
    for _ in range(40):
        seed = (seed * 1103515245 + 12345) % 2147483648
        xs.append(Float64(seed % 10000) / 1000.0)
        seed = (seed * 1103515245 + 12345) % 2147483648
        ys.append(Float64(seed % 10000) / 1000.0)
    var zs = List[Float64]()
    for i in range(len(xs)):
        zs.append(xs[i])
    return (xs^, ys^, zs^)


def _column_spread(c: Canvas, x: Int, y0: Int, y1: Int) -> Int:
    """The widest channel gap between any two pixels in one column.

    Under `z = x` every pixel in a column has the same value, so a
    correct Gouraud render paints the column one color and this is 0.
    """
    var worst = 0
    for a in range(y0, y1):
        for b in range(a + 1, y1):
            var p = c.get_pixel(x, a)
            var q = c.get_pixel(x, b)
            var d = max(
                abs(Int(p.r) - Int(q.r)),
                max(abs(Int(p.g) - Int(q.g)), abs(Int(p.b) - Int(q.b))),
            )
            if d > worst:
                worst = d
    return worst


def test_a_linear_ramp_shades_by_x_alone() raises:
    """#398's stated criterion.

    Two pixels at the same x are at the same `z`, so under Gouraud they
    must be the same color whichever triangles they fall in. The column
    is sampled well inside the hull so the anti-aliased boundary never
    enters it.
    """
    var s = _ramp_samples()
    var img = render(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=True,
            width=300,
            height=220,
            theme=_theme_gouraud(),
        )
    )
    var worst = _column_spread(img, 150, 80, 140)
    assert_true(
        worst <= 2,
        (
            "a column of constant z spans "
            + String(worst)
            + " levels, so the shading is not a function of x alone"
        ),
    )


def test_flat_shading_is_the_thing_this_fixes() raises:
    # The control. The same mesh flat-shaded must NOT be constant down a
    # column, or the test above proves nothing about Gouraud.
    var s = _ramp_samples()
    var img = render(
        tripcolor(
            s[0], s[1], s[2], width=300, height=220, theme=_theme_gouraud()
        )
    )
    var worst = _column_spread(img, 150, 80, 140)
    assert_true(
        worst > 10,
        (
            "flat shading already paints a constant-z column one color (spread "
            + String(worst)
            + "), so there is nothing for Gouraud to fix"
        ),
    )


def test_gouraud_changes_the_picture() raises:
    var s = _ramp_samples()
    var flat = render(
        tripcolor(
            s[0], s[1], s[2], width=300, height=220, theme=_theme_gouraud()
        )
    )
    var smooth = render(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=True,
            width=300,
            height=220,
            theme=_theme_gouraud(),
        )
    )
    var diff = 0
    for y in range(flat.height):
        for x in range(flat.width):
            var a = flat.get_pixel(x, y)
            var b = smooth.get_pixel(x, y)
            if a.r != b.r or a.g != b.g or a.b != b.b:
                diff += 1
    assert_true(diff > 500, "gouraud changed nothing on the canvas")


def test_flat_is_still_the_default() raises:
    var s = _ramp_samples()
    var explicit = render(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=False,
            width=300,
            height=220,
            theme=_theme_gouraud(),
        )
    )
    var default = render(
        tripcolor(
            s[0], s[1], s[2], width=300, height=220, theme=_theme_gouraud()
        )
    )
    for y in range(0, default.height, 7):
        for x in range(0, default.width, 7):
            var a = explicit.get_pixel(x, y)
            var b = default.get_pixel(x, y)
            assert_equal(
                Int(a.r) * 65536 + Int(a.g) * 256 + Int(a.b),
                Int(b.r) * 65536 + Int(b.g) * 256 + Int(b.b),
                "the default is not flat shading",
            )


def test_gouraud_and_facecolors_are_exclusive() raises:
    # facecolors is one value per triangle, so there is nothing to
    # interpolate between. Caught in the builder rather than at render.
    var xs: List[Float64] = [0.0, 1.0, 0.5, 1.5]
    var ys: List[Float64] = [0.0, 0.0, 1.0, 1.0]
    var zs: List[Float64] = [0.0, 1.0, 2.0, 3.0]
    var faces: List[Float64] = [1.0, 2.0]
    from dataviz.core.delaunay import delaunay

    with assert_raises(contains="nothing to interpolate between"):
        _ = (
            Plot()
            .mark_tripcolor()
            .encode_triplot(
                x=xs,
                y=ys,
                z=zs,
                triangulation=delaunay(xs, ys),
                facecolors=faces,
                gouraud=True,
            )
        )


def test_svg_renders_and_says_it_approximates() raises:
    """SVG has no mesh gradient, so canvas draws each face flat at the
    mean of its corners. That is the first place the backends differ by
    design, and it is worth pinning that the vector path at least
    renders rather than raising.
    """
    var s = _ramp_samples()
    var svg = render_svg(
        tripcolor(
            s[0],
            s[1],
            s[2],
            gouraud=True,
            width=300,
            height=220,
            theme=_theme_gouraud(),
        )
    ).to_string()
    assert_true("<svg" in svg, "no svg root")
    assert_true(svg.count("<path") > 10, "the mesh drew almost nothing")


# ==== from test_public_triangulation.mojo ====
# A public `Triangulation`, and the per-triangle values it unlocks (#397).
#
# `delaunay()` and its result type were private, so every triangulation mark
# built its own inside its render function. Two consequences the issue names:
# a layered chart triangulated the same points twice, and matplotlib's
# `tripcolor(facecolors=...)` could not be offered at all, because the
# triangle order is an artifact of Bowyer-Watson's insertion sequence and
# nothing outside this package can predict it.
#
# Both are fixed by the same change: make the order knowable by making the
# triangulation something the caller owns.
#
# The tests below lean on that: a caller-built `Triangulation` has a triangle
# order the test itself chose, so `facecolors` can be asserted against
# specific triangles rather than against whatever the algorithm produced.


def _square() -> Tuple[List[Float64], List[Float64]]:
    """Four corners of a unit square, in a fixed order.

    Small enough that its two triangles can be written out by hand,
    which is what lets `facecolors` be checked against a known triangle
    rather than an arbitrary one.

    Returns:
        `(x, y)`.
    """
    var x = List[Float64]()
    var y = List[Float64]()
    x.append(0.0)
    y.append(0.0)
    x.append(1.0)
    y.append(0.0)
    x.append(1.0)
    y.append(1.0)
    x.append(0.0)
    y.append(1.0)
    return (x^, y^)


def _two_triangles() -> List[Int]:
    # Lower-left then upper-right, splitting the square on its diagonal.
    var t = List[Int]()
    t.append(0)
    t.append(1)
    t.append(2)
    t.append(0)
    t.append(2)
    t.append(3)
    return t^


def _zeros(n: Int) -> List[Float64]:
    var v = List[Float64]()
    for _ in range(n):
        v.append(0.0)
    return v^


def test_the_type_and_the_function_are_public() raises:
    # Imported from `dataviz` above rather than reaching into a module:
    # if either name stops being exported this file will not build.
    var pts = _square()
    var tri = delaunay(pts[0], pts[1])
    assert_equal(tri.count(), 2, "a square triangulates into two triangles")
    assert_equal(len(tri.x), 4, "the points come back in their own order")
    assert_equal(
        len(tri.triangles), 6, "three vertex indices per triangle, flat"
    )


def test_a_caller_can_build_one_from_its_own_triangles() raises:
    var pts = _square()
    var tri = Triangulation(pts[0], pts[1], _two_triangles())
    assert_equal(tri.count(), 2, "the caller's own two triangles")
    assert_equal(tri.triangles[0], 0, "and in the caller's own order")
    assert_equal(tri.triangles[5], 3, "including the last index")


def test_a_malformed_triangulation_raises() raises:
    var pts = _square()

    with assert_raises(contains="same length"):
        var short_y = List[Float64]()
        short_y.append(0.0)
        _ = Triangulation(pts[0], short_y, _two_triangles())

    with assert_raises(contains="multiple of 3"):
        var ragged = _two_triangles()
        _ = ragged.pop()
        _ = Triangulation(pts[0], pts[1], ragged)

    with assert_raises(contains="outside the 4 points"):
        var bad = _two_triangles()
        bad[0] = 9
        _ = Triangulation(pts[0], pts[1], bad)


def test_facecolors_color_the_triangle_the_caller_indexed() raises:
    """The capability #397 exists for.

    Two triangles, the first given a low value and the second a high
    one. The lower-left triangle covers the bottom-left of the plot rect
    and the upper-right covers the top-right, so the two regions must
    end up different colors, and swapping the values must swap which
    region is which.

    Comparing the two renders rather than naming colors: the ramp is the
    theme's business, and this test is about which triangle got which
    value.
    """
    var pts = _square()
    var tri = Triangulation(pts[0], pts[1], _two_triangles())

    var low_first = List[Float64]()
    low_first.append(0.0)
    low_first.append(1.0)
    var high_first = List[Float64]()
    high_first.append(1.0)
    high_first.append(0.0)

    var a = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(
            pts[0],
            pts[1],
            _zeros(4),
            triangulation=tri,
            facecolors=low_first,
        )
        .theme(_theme())
        .size(240, 180)
    )
    var b = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(
            pts[0],
            pts[1],
            _zeros(4),
            triangulation=tri,
            facecolors=high_first,
        )
        .theme(_theme())
        .size(240, 180)
    )
    var diff = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                diff += 1
    assert_true(
        diff > 200,
        "swapping the two facecolors changed only "
        + String(diff)
        + " pixels, so the values are not reaching their triangles",
    )


def test_facecolors_without_a_triangulation_raises() raises:
    # The order would be an artifact of the algorithm, so a per-triangle
    # column would be assigned arbitrarily. Refused rather than guessed.
    var pts = _square()
    var f = List[Float64]()
    f.append(0.0)
    f.append(1.0)
    with assert_raises(contains="needs a triangulation to index against"):
        _ = (
            Plot()
            .mark_tripcolor()
            .encode_triplot(pts[0], pts[1], _zeros(4), facecolors=f)
        )


def test_the_wrong_number_of_facecolors_raises_at_render() raises:
    var pts = _square()
    var tri = Triangulation(pts[0], pts[1], _two_triangles())
    var three = List[Float64]()
    three.append(0.0)
    three.append(1.0)
    three.append(2.0)
    with assert_raises(contains="one value per triangle"):
        _ = render(
            Plot()
            .mark_tripcolor()
            .encode_triplot(
                pts[0], pts[1], _zeros(4), triangulation=tri, facecolors=three
            )
            .size(240, 180)
        )


def test_a_supplied_triangulation_is_the_one_drawn() raises:
    # One triangle of the square instead of two: if the render still
    # triangulated internally it would draw both and cover more pixels.
    var pts = _square()
    var one = List[Int]()
    one.append(0)
    one.append(1)
    one.append(2)
    var half = Triangulation(pts[0], pts[1], one)
    var bg = _theme().background

    var whole = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(pts[0], pts[1], _zeros(4))
        .theme(_theme())
        .size(240, 180)
    )
    var partial = render(
        Plot()
        .mark_tripcolor()
        .encode_triplot(pts[0], pts[1], _zeros(4), triangulation=half)
        .theme(_theme())
        .size(240, 180)
    )

    var ink_whole = 0
    var ink_partial = 0
    for y in range(whole.height):
        for x in range(whole.width):
            var p = whole.get_pixel(x, y)
            var q = partial.get_pixel(x, y)
            if not (p.r == bg.r and p.g == bg.g and p.b == bg.b):
                ink_whole += 1
            if not (q.r == bg.r and q.g == bg.g and q.b == bg.b):
                ink_partial += 1
    assert_true(
        ink_partial < ink_whole,
        "one triangle covered as much as two ("
        + String(ink_partial)
        + " against "
        + String(ink_whole)
        + "), so the supplied triangulation was ignored",
    )


# ==== from test_quiver.mojo ====
# Tests for `Mark.QUIVER` / `quiver()`: the shaft and head geometry of
# a known vector, the y-up convention, the automatic scale, and the
# overloads.


def _near(a: Float64, b: Float64) -> Bool:
    return abs(a - b) < 0.01


struct _Seg(Copyable, Movable):
    var x0: Float64
    var y0: Float64
    var x1: Float64
    var y1: Float64

    def __init__(out self, x0: Float64, y0: Float64, x1: Float64, y1: Float64):
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1


def _lines(svg: String) raises -> List[_Seg]:
    """Every `<line>` as a segment."""
    var x1 = _attr_values(svg, "line", "x1")
    var y1 = _attr_values(svg, "line", "y1")
    var x2 = _attr_values(svg, "line", "x2")
    var y2 = _attr_values(svg, "line", "y2")
    var out = List[_Seg]()
    for i in range(len(x1)):
        out.append(
            _Seg(Float64(x1[i]), Float64(y1[i]), Float64(x2[i]), Float64(y2[i]))
        )
    return out^


def _find_shaft(segs: List[_Seg], dx: Float64, dy: Float64) -> Int:
    """The index of the segment with exactly this displacement, or -1."""
    for i in range(len(segs)):
        if _near(segs[i].x1 - segs[i].x0, dx) and _near(
            segs[i].y1 - segs[i].y0, dy
        ):
            return i
    return -1


def _head_tips(svg: String) raises -> List[List[Float64]]:
    """The first point of every `<path>`: the tip of each arrowhead,
    since the head path starts at its tip."""
    var ds = _attr_values(svg, "path", "d")
    var out = List[List[Float64]]()
    for d in ds:
        # "M<x>,<y> L..." -- the tip is the pair after M.
        var m = d.find("M")
        var sp = d.find(" ", m)
        var pair = String(d[byte = m + 1 : sp])
        var comma = pair.find(",")
        var tip = List[Float64]()
        tip.append(Float64(String(pair[byte=:comma])))
        tip.append(Float64(String(pair[byte = comma + 1 :])))
        out.append(tip^)
    return out^


def test_svg_arrow_geometry_pins_the_scale_and_the_y_up_convention() raises:
    # Two arrows at scale 2 px per unit: (10, 0) is a 20 px arrow due
    # east; (0, 10) is a 20 px arrow due *north*, which in pixel y means
    # y decreasing -- the place a y-down slip would show. The shaft
    # stops 11 px (the head length) short of the tip, so it is 9 px
    # long; the head path starts at the tip, 20 px from the tail.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var u: List[Float64] = [10.0, 0.0]
    var v: List[Float64] = [0.0, 10.0]
    var plot = (
        Plot()
        .mark_quiver(scale=2.0)
        .encode_quiver(x=x, y=y, u=u, v=v)
        .size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    var segs = _lines(svg)
    var east = _find_shaft(segs, 9.0, 0.0)
    assert_true(east >= 0, "the (10, 0) arrow's shaft runs 9 px due east")
    var north = _find_shaft(segs, 0.0, -9.0)
    assert_true(north >= 0, "the (0, 10) arrow's shaft runs 9 px up the page")

    var tips = _head_tips(svg)
    assert_equal(len(tips), 2, "one head per arrow")
    var east_tip = False
    var north_tip = False
    for t in tips:
        if _near(t[0], segs[east].x0 + 20.0) and _near(t[1], segs[east].y0):
            east_tip = True
        if _near(t[0], segs[north].x0) and _near(t[1], segs[north].y0 - 20.0):
            north_tip = True
    assert_true(east_tip, "the east head's tip is 20 px from its tail")
    assert_true(north_tip, "the north head's tip is 20 px above its tail")


def test_an_arrow_shorter_than_a_head_is_only_a_head() raises:
    # At scale 0.5 the (10, 0) vector is 5 px: no shaft, and a head
    # shortened to 5 px whose tip is 5 px from the tail.
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var u: List[Float64] = [10.0, 0.0]
    var v: List[Float64] = [0.0, 0.0]
    var plot = (
        Plot()
        .mark_quiver(scale=0.5)
        .encode_quiver(x=x, y=y, u=u, v=v)
        .size(400, 300)
    )
    var svg = render_svg(plot).to_string()
    assert_equal(len(_head_tips(svg)), 1, "the zero vector draws nothing")
    # Axis ticks are lines too, so count against the same chart at a
    # scale where the arrow does get a shaft: exactly one line fewer.
    var full = render_svg(
        Plot()
        .mark_quiver(scale=2.0)
        .encode_quiver(x=x, y=y, u=u, v=v)
        .size(400, 300)
    ).to_string()
    assert_equal(len(_lines(svg)) + 1, len(_lines(full)), "no shaft drawn")


def test_auto_scale_follows_the_mean_magnitude_rule() raises:
    # Four arrows of magnitude 10: sn = max(10, sqrt 4) = 10, so an
    # arrow of the mean magnitude is width / 18 px long, and pixels per
    # unit is width / 180.
    var u: List[Float64] = [10.0, 0.0, -10.0, 0.0]
    var v: List[Float64] = [0.0, 10.0, 0.0, -10.0]
    assert_true(_near(_auto_pixels_per_unit(u, v, 360.0), 2.0))
    # A field of zero vectors has no mean to scale by, and 1.0 draws
    # nothing anyway.
    var z: List[Float64] = [0.0, 0.0]
    assert_equal(_auto_pixels_per_unit(z, z, 360.0), 1.0)


def test_color_by_magnitude_colors_the_longest_arrow_the_ramp_top() raises:
    var lo = Color(0, 0, 255)
    var hi = Color(255, 0, 0)
    var stops: List[Color] = [lo, hi]
    var theme = Theme(color_ramp=stops, show_gridlines=False, show_legend=False)
    var x: List[Float64] = [0.0, 1.0, 2.0]
    var y: List[Float64] = [0.0, 1.0, 2.0]
    var u: List[Float64] = [10.0, 5.0, 2.0]
    var v: List[Float64] = [0.0, 0.0, 0.0]
    var c = render(
        quiver(
            x,
            y,
            u,
            v,
            color_by_magnitude=True,
            theme=theme,
            width=400,
            height=300,
        )
    )
    assert_true(_count_color(c, hi) > 10, "the longest arrow is the ramp's top")
    var plain = render(quiver(x, y, u, v, theme=theme, width=400, height=300))
    assert_equal(_count_color(plain, hi), 0, "without the flag, the mark color")
    assert_true(
        _count_color(plain, theme.mark_color) > 10,
        "the mark color is on the canvas",
    )


def test_dtype_overload_matches_the_float64_path() raises:
    var xf: List[Float64] = [0.0, 1.0, 2.0]
    var yf: List[Float64] = [0.0, 1.0, 2.0]
    var uf: List[Float64] = [10.0, 5.0, 2.0]
    var vf: List[Float64] = [0.0, 3.0, -4.0]
    var xi: List[Int32] = [0, 1, 2]
    var yi: List[Int32] = [0, 1, 2]
    var ui: List[Int32] = [10, 5, 2]
    var vi: List[Int32] = [0, 3, -4]
    _assert_same_canvas(
        render(quiver(xf, yf, uf, vf, width=300, height=220)),
        render(quiver(xi, yi, ui, vi, width=300, height=220)),
        "Int32 quiver matches Float64",
    )


def test_quiver_raises_with_names() raises:
    var x: List[Float64] = [0.0, 1.0]
    var y: List[Float64] = [0.0, 1.0]
    var short: List[Float64] = [1.0]
    with assert_raises(contains="Plot.encode_quiver(): x, y, u, and v"):
        _ = render(quiver(x, y, short, y))
    with assert_raises(contains="scale must be 0"):
        _ = render(quiver(x, y, x, y, scale=-1.0))
    with assert_raises(contains="Plot.encode_quiver()"):
        _ = render(
            quiver(
                List[Float64](),
                List[Float64](),
                List[Float64](),
                List[Float64](),
            )
        )


# ==== from test_streamplot.mojo ====
# Tests for `Mark.STREAMPLOT` (#343).
#
# The integrator and the seeding can each produce a plausible-looking but
# wrong picture, and "looks like flow" is not evidence of anything, so the
# numerical half is checked against two fields whose exact streamlines are
# known: a uniform field, whose lines are straight, and solid-body
# rotation, whose lines are circles.


def _coords(n: Int, lo: Float64, step: Float64) -> List[Float64]:
    var out = List[Float64]()
    for i in range(n):
        out.append(lo + step * Float64(i))
    return out^


def _uniform(nx: Int, ny: Int) -> List[List[Float64]]:
    var out = List[List[Float64]]()
    for _ in range(ny):
        var row = List[Float64]()
        for _ in range(nx):
            row.append(1.0)
        out.append(row^)
    return out^


def _zeros_streamplot(nx: Int, ny: Int) -> List[List[Float64]]:
    var out = List[List[Float64]]()
    for _ in range(ny):
        var row = List[Float64]()
        for _ in range(nx):
            row.append(0.0)
        out.append(row^)
    return out^


def _rotation_field(
    xs: List[Float64], ys: List[Float64]
) -> Tuple[List[List[Float64]], List[List[Float64]]]:
    """Solid-body rotation about the origin, `(u, v) = (-y, x)`. Its
    streamlines are exactly the circles centered there."""
    var us = List[List[Float64]]()
    var vs = List[List[Float64]]()
    for j in range(len(ys)):
        var urow = List[Float64]()
        var vrow = List[Float64]()
        for i in range(len(xs)):
            urow.append(-ys[j])
            vrow.append(xs[i])
        us.append(urow^)
        vs.append(vrow^)
    return (us^, vs^)


def test_a_uniform_field_traces_straight_lines() raises:
    # (u, v) = (1, 0) everywhere: every streamline is a horizontal line,
    # so a traced point's row never changes and its column only grows.
    var xs = _coords(11, 0.0, 1.0)
    var ys = _coords(9, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _uniform(11, 9), _zeros_streamplot(11, 9))
    )
    var field = _build_field(p._stream)
    # One occupancy cell, so nothing can block the line and the trace is
    # the integrator alone.
    var occ = _Occupancy(1, 1)
    var claimed = List[Int]()
    var line = _trace(field, occ, 2.0, 4.0, 1.0, 0, 200, claimed)
    assert_true(len(line.fi) > 20, "the line crosses the grid")
    for k in range(len(line.fj)):
        assert_true(
            abs(line.fj[k] - 4.0) < 1e-9,
            "a uniform field's streamline stays in its row -- got "
            + String(line.fj[k])
            + " at step "
            + String(k),
        )
    for k in range(1, len(line.fi)):
        assert_true(
            abs(line.fi[k] - line.fi[k - 1] - _STEP) < 1e-9,
            "each step advances exactly one step's arc length",
        )
    # And it stops at the grid's edge rather than running past it.
    assert_true(line.fi[len(line.fi) - 1] <= 10.0 + 1e-9, "stops at the edge")
    assert_true(line.fi[len(line.fi) - 1] > 9.5, "having reached it")


def test_solid_body_rotation_traces_exact_circles() raises:
    # (u, v) = (-y, x): the streamline through a point at radius r is
    # the circle of radius r, so the radius is the invariant to check.
    # Bilinear interpolation is exact on a linear field, so any drift
    # here is the integrator's -- which is what Euler would fail, its
    # lines spiralling outward by a visible amount over one turn.
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var field_arrays = _rotation_field(xs, ys)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, field_arrays[0], field_arrays[1])
    )
    var field = _build_field(p._stream)
    var occ = _Occupancy(1, 1)
    var claimed = List[Int]()
    # The grid center is index (10, 10); seed 6 cells to its right.
    var radius = 6.0
    var turn = 2.0 * pi * radius
    var steps = Int(turn / _STEP) + 2
    var line = _trace(field, occ, 16.0, 10.0, 1.0, 0, steps, claimed)
    assert_equal(len(line.fi), steps + 1, "nothing stopped it early")

    var worst = 0.0
    for k in range(len(line.fi)):
        var dx = line.fi[k] - 10.0
        var dy = line.fj[k] - 10.0
        worst = max(worst, abs(sqrt(dx * dx + dy * dy) - radius))
    assert_true(
        worst < 1e-4,
        "the radius is conserved over a full turn -- worst drift "
        + String(worst)
        + " cells",
    )

    # And it comes back to where it started. The step is a fixed arc
    # length and the circumference is not a multiple of it, so the
    # closest approach is within half a step by construction; anything
    # worse is the integrator losing phase.
    var closest = 1.0e9
    for k in range(len(line.fi) // 2, len(line.fi)):
        var dx = line.fi[k] - 16.0
        var dy = line.fj[k] - 10.0
        closest = min(closest, sqrt(dx * dx + dy * dy))
    assert_true(
        closest < _STEP,
        "the line closes on its own seed -- closest approach "
        + String(closest)
        + " cells",
    )


def test_a_line_stops_where_another_one_already_passed() raises:
    # The even-spacing rule: with the whole grid one occupancy cell,
    # a second trajectory cannot take a single step.
    var xs = _coords(11, 0.0, 1.0)
    var ys = _coords(9, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _uniform(11, 9), _zeros_streamplot(11, 9))
    )
    var field = _build_field(p._stream)
    var occ = _Occupancy(1, 1)
    var claimed = List[Int]()
    var first = _trace(field, occ, 2.0, 4.0, 1.0, 0, 200, claimed)
    assert_true(len(first.fi) > 20, "the first line runs")
    var claimed2 = List[Int]()
    var second = _trace(field, occ, 2.0, 2.0, 1.0, 1, 200, claimed2)
    assert_equal(len(second.fi), 1, "the second gets only its seed")


def test_a_field_with_no_flow_draws_no_lines() raises:
    # Every point is a stagnation point: the direction is undefined, so
    # there is nothing to integrate and nothing to draw. The interesting
    # part is that it does not wander off on the last bits of zero.
    var xs = _coords(9, 0.0, 1.0)
    var ys = _coords(9, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(
            xs, ys, _zeros_streamplot(9, 9), _zeros_streamplot(9, 9)
        )
    )
    assert_equal(len(_streamlines(p._stream)), 0)


def test_density_controls_how_many_lines_are_drawn() raises:
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var f = _rotation_field(xs, ys)
    var sparse = (
        Plot()
        .mark_streamplot(density=0.5)
        .encode_streamplot(xs, ys, f[0], f[1])
    )
    var dense = (
        Plot()
        .mark_streamplot(density=2.0)
        .encode_streamplot(xs, ys, f[0], f[1])
    )
    var n_sparse = len(_streamlines(sparse._stream))
    var n_dense = len(_streamlines(dense._stream))
    assert_true(n_sparse > 0, "a sparse field still draws")
    assert_true(
        n_dense > n_sparse,
        "raising the density draws more lines -- got "
        + String(n_dense)
        + " against "
        + String(n_sparse),
    )


def test_streamlines_run_downstream_not_from_the_seed_outward() raises:
    # Each line is the upstream half reversed then the downstream half,
    # so the points follow the flow end to end. In a uniform rightward
    # field every column must increase along the list -- a line built
    # seed-outward would turn around in the middle.
    var xs = _coords(21, 0.0, 1.0)
    var ys = _coords(11, 0.0, 1.0)
    var p = (
        Plot()
        .mark_streamplot()
        .encode_streamplot(xs, ys, _uniform(21, 11), _zeros_streamplot(21, 11))
    )
    var lines = _streamlines(p._stream)
    assert_true(len(lines) > 0, "a uniform field draws lines")
    for idx in range(len(lines)):
        ref line = lines[idx]
        for k in range(1, len(line.fi)):
            assert_true(
                line.fi[k] > line.fi[k - 1],
                "the points run downstream",
            )


def test_svg_draws_a_path_per_line_and_one_more_with_arrows() raises:
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var f = _rotation_field(xs, ys)
    var t = Theme(show_gridlines=False, show_legend=False)
    var plain = render_svg(
        streamplot(
            xs, ys, f[0], f[1], arrows=False, theme=t, width=400, height=300
        )
    ).to_string()
    var arrowed = render_svg(
        streamplot(
            xs, ys, f[0], f[1], arrows=True, theme=t, width=400, height=300
        )
    ).to_string()
    var lines = _count_tag(plain, "path")
    assert_true(lines > 4, "the field draws several lines")
    assert_true(
        _count_tag(arrowed, "path") > lines,
        "each arrowhead is a path of its own",
    )


def test_color_by_magnitude_strokes_each_step_separately() raises:
    # The speed varies along a streamline, so a line drawn in one color
    # would claim it does not: the colored form is one stroke per step.
    var xs = _coords(21, -10.0, 1.0)
    var ys = _coords(21, -10.0, 1.0)
    var f = _rotation_field(xs, ys)
    var t = Theme(show_gridlines=False, show_legend=False)
    var plain = _count_tag(
        render_svg(
            streamplot(
                xs, ys, f[0], f[1], arrows=False, theme=t, width=400, height=300
            )
        ).to_string(),
        "path",
    )
    var colored = _count_tag(
        render_svg(
            streamplot(
                xs,
                ys,
                f[0],
                f[1],
                arrows=False,
                color_by_magnitude=True,
                theme=t,
                width=400,
                height=300,
            )
        ).to_string(),
        "path",
    )
    assert_true(
        colored > 10 * plain,
        "coloring by magnitude strokes every step -- got "
        + String(colored)
        + " against "
        + String(plain),
    )


def test_streamplot_dtype_overload_matches_the_float64_path() raises:
    var xf = _coords(9, 0.0, 1.0)
    var yf = _coords(9, 0.0, 1.0)
    var uf = List[List[Float64]]()
    var vf = List[List[Float64]]()
    var ui = List[List[Int32]]()
    var vi = List[List[Int32]]()
    var xi = List[Int32]()
    var yi = List[Int32]()
    for i in range(9):
        xi.append(Int32(i))
        yi.append(Int32(i))
    for j in range(9):
        var ur = List[Float64]()
        var vr = List[Float64]()
        var ur_i = List[Int32]()
        var vr_i = List[Int32]()
        for i in range(9):
            ur.append(Float64(-(j - 4)))
            vr.append(Float64(i - 4))
            ur_i.append(Int32(-(j - 4)))
            vr_i.append(Int32(i - 4))
        uf.append(ur^)
        vf.append(vr^)
        ui.append(ur_i^)
        vi.append(vr_i^)
    _assert_same_canvas(
        render(streamplot(xf, yf, uf, vf, width=300, height=220)),
        render(streamplot(xi, yi, ui, vi, width=300, height=220)),
        "Int32 streamplot matches Float64",
    )


def test_streamplot_raises_with_names() raises:
    var xs = _coords(5, 0.0, 1.0)
    var ys = _coords(4, 0.0, 1.0)
    with assert_raises(contains="density must be positive"):
        _ = streamplot(
            xs, ys, _uniform(5, 4), _zeros_streamplot(5, 4), density=0.0
        )
    # An uneven grid: the integrator works in cells, so it refuses.
    var uneven: List[Float64] = [0.0, 1.0, 3.0, 4.0, 5.0]
    var p = streamplot(uneven, ys, _uniform(5, 4), _zeros_streamplot(5, 4))
    with assert_raises(contains="must be evenly spaced"):
        _ = render(p)
    var descending: List[Float64] = [5.0, 4.0, 3.0, 2.0, 1.0]
    var p2 = streamplot(descending, ys, _uniform(5, 4), _zeros_streamplot(5, 4))
    with assert_raises(contains="must be strictly increasing"):
        _ = render(p2)
    var p3 = streamplot(xs, ys, _uniform(5, 3), _zeros_streamplot(5, 4))
    with assert_raises(contains="one row per y coordinate"):
        _ = render(p3)
    var short = List[List[Float64]]()
    for _ in range(4):
        var row = List[Float64]()
        for _ in range(3):
            row.append(1.0)
        short.append(row^)
    var p4 = streamplot(xs, ys, short, _zeros_streamplot(5, 4))
    with assert_raises(contains="one entry per x coordinate"):
        _ = render(p4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
