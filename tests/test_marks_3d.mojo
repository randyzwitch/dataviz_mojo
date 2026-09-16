"""The 3D marks that are not boxes: the three surfaces from step 4, and
the stem, arrow and ribbon marks from step 5 (#345).

The camera and the frame they project through have their own unit tests
in `test_primitives.mojo`, and the cuboid marks are in
`test_marks_3d_boxes.mojo`. What is tested here is what these marks
build on top of the frame -- the order faces are handed over in, the
seamless fill that order feeds, where a mark anchors itself, and the
rules each input has to satisfy.
"""

from std.math import cos, sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import (
    fill_between3d,
    quiver3d,
    scatter3d,
    stem3d,
    surface3d,
    trisurf3d,
    wire3d,
)
from dataviz.core.color_scale import _ColorDomainOverride, _color_scale_for
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.plot import Plot, render, render_svg
from dataviz.spatial.stem3d import (
    _draw_arrowhead,
    _stem3d_extent,
    _vectors3d_extent,
)
from dataviz.spatial.surface3d import _depth_sorted_faces
from _test_helpers import _attr_values, _count_color


comptime _W = 420
comptime _H = 320


def _flat_grid(rows: Int, cols: Int, value: Float64) -> List[List[Float64]]:
    """A constant field -- every face takes the same color, which is what
    makes a seam visible."""
    var z = List[List[Float64]]()
    for _ in range(rows):
        var row = List[Float64]()
        for _ in range(cols):
            row.append(value)
        z.append(row^)
    return z^


def _walled_grid(near: Bool) -> List[List[Float64]]:
    """A flat field with a wall standing along one edge of it.

    At the default view the last row is the near edge: `vertical` puts
    a growing y low on the page, and the bottom of an elevated view is
    the edge closest to the reader. The near wall is the case that
    needs the depth sort -- it stands between the reader and the plane,
    so it has to be drawn over it.
    """
    var z = _flat_grid(5, 5, 0.0)
    var wall = 4 if near else 0
    for c in range(5):
        z[wall][c] = 4.0
    return z^


def _count_plane_pixels(field: List[List[Float64]]) raises -> Int:
    """How much of the flat part of `field` shows in the render."""
    var c = render(surface3d(field, width=_W, height=_H))
    var scale = _color_scale_for(Theme(), _ColorDomainOverride(), 0.0, 4.0)
    return _count_color(c, scale.color_at(0.0))


# ==== the order faces are handed to fill_mesh ====


def test_depth_sorted_faces_puts_the_farthest_first() raises:
    # `fill_mesh` composites in the order given, so the farthest face
    # has to be first for a nearer one to cover it.
    var depths: List[Float64] = [0.5, 2.0, -1.0, 1.0]
    var order = _depth_sorted_faces(depths, 4)
    assert_equal(len(order), 4)
    for k in range(1, len(order)):
        assert_true(
            depths[order[k - 1]] >= depths[order[k]],
            "face " + String(k) + " is farther than the one before it",
        )
    assert_equal(order[0], 1)
    assert_equal(order[3], 2)


def test_depth_sorted_faces_keeps_ties_in_their_original_order() raises:
    # Two faces at one depth have no correct order between them, so the
    # sort must not invent one: a stable result is what keeps a render
    # reproducible when a field has a plateau.
    var depths: List[Float64] = [1.0, 1.0, 1.0]
    var order = _depth_sorted_faces(depths, 3)
    assert_equal(order[0], 0)
    assert_equal(order[1], 1)
    assert_equal(order[2], 2)


def test_a_near_wall_hides_the_plane_and_a_far_one_does_not() raises:
    # The whole point of the depth sort, and stated so that only the
    # right order passes. A wall on the near edge stands between the
    # reader and the plane, so it must cover part of it. The same wall
    # on the far edge is behind the plane and must cover none of it.
    #
    # Measured: 6887 pixels of plane with the wall near and 9508 with it
    # far. Hand the faces over nearest-first instead and the two swap,
    # so a test that only checked one of them, or only that they
    # differed, would pass with the sort inverted -- which is how an
    # inverted sort survived two releases here.
    var near = _count_plane_pixels(_walled_grid(True))
    var far = _count_plane_pixels(_walled_grid(False))
    assert_true(far > 5000, "the plane barely drew at all: " + String(far))
    assert_true(
        near < far,
        (
            "a wall on the near edge covered none of the plane behind it ("
            + String(near)
            + " against "
            + String(far)
            + ") -- the faces are not going over farthest first"
        ),
    )


# ==== one fill_mesh call, not one fill per face ====


def test_a_flat_surface_has_no_seam_between_adjacent_faces() raises:
    # Two antialiased fills sharing an edge each blend their partial
    # coverage against the background rather than against each other, so
    # a surface filled a face at a time carries a pale grid along every
    # shared edge. `fill_mesh` is what fixes that, and this is the check
    # that it is still being used.
    var c = render(surface3d(_flat_grid(6, 6, 1.0), width=_W, height=_H))
    var scale = _color_scale_for(Theme(), _ColorDomainOverride(), 1.0, 1.0)
    var fill = scale.color_at(1.0)
    var row = _H // 2
    var first = -1
    var last = -1
    for x in range(_W):
        var p = c.get_pixel(x, row)
        if p.r == fill.r and p.g == fill.g and p.b == fill.b:
            if first < 0:
                first = x
            last = x
    assert_true(first >= 0, "the flat surface drew none of its own color")
    assert_true(last - first > 100, "the run of surface is implausibly short")
    for x in range(first, last + 1):
        var p = c.get_pixel(x, row)
        assert_true(
            p.r == fill.r and p.g == fill.g and p.b == fill.b,
            (
                "a seam at x="
                + String(x)
                + " on row "
                + String(row)
                + " -- the faces are being filled one at a time"
            ),
        )


# ==== wire3d draws the lattice, not the faces ====


def test_wire3d_draws_one_stroke_per_lattice_line() raises:
    # Rows plus columns, each a *single* polyline so its joins are
    # mitered rather than each segment capping against the next.
    #
    # A non-square lattice, and the lines counted by how many points
    # each has: 4 rows of 7 points and 7 columns of 4. A square one
    # would pass with the two loops swapped, and a count of paths alone
    # would pass with a line dropped from each direction.
    var svg = render_svg(
        wire3d(_flat_grid(4, 7, 0.0), width=_W, height=_H)
    ).to_string()
    var ds = _attr_values(svg, "path", "d")
    # The twelve edges of the viewing box are paths too, with one
    # segment each.
    assert_equal(len(ds), 12 + 4 + 7, "one path per box edge and per line")
    var box = 0
    var rows = 0
    var cols = 0
    for d in ds:
        var segments = d.count("L")
        if segments == 1:
            box += 1
        elif segments == 6:
            rows += 1
        elif segments == 3:
            cols += 1
    assert_equal(box, 12, "the viewing box lost an edge")
    assert_equal(rows, 4, "there should be one 7-point line per lattice row")
    assert_equal(cols, 7, "there should be one 4-point line per lattice column")


def test_wire3d_fills_nothing() raises:
    # A wireframe's whole appeal is that the far side stays visible, and
    # a fill would hide it. A surface of the same field covers far more
    # of the figure than its lattice does.
    var grid = _walled_grid(True)
    var wire = render(wire3d(grid, width=_W, height=_H))
    var solid = render(surface3d(grid, width=_W, height=_H))
    var bg = Theme().background
    assert_true(
        _count_color(wire, bg) > _count_color(solid, bg) + 5000,
        "wire3d covered about as much of the figure as surface3d did",
    )


# ==== trisurf3d ====


def test_trisurf3d_fills_the_hull_of_scattered_points() raises:
    # Off-grid samples, so the triangulation is doing the work. The
    # field rises and falls across the disc, so a correct render carries
    # both ends of the ramp.
    var x = List[Float64]()
    var y = List[Float64]()
    var z = List[Float64]()
    for i in range(200):
        var t = Float64(i) * 2.399963
        var r = 0.2 * Float64(i) ** 0.5
        var px = r * cos(t)
        var py = r * sin(t)
        x.append(px)
        y.append(py)
        z.append(px + py)
    var c = render(trisurf3d(x, y, z, width=_W, height=_H))
    assert_true(
        _count_color(c, Theme().background) < _W * _H - 8000,
        "trisurf3d left the figure nearly empty",
    )
    # Counted by which way the pixel leans on the default diverging
    # ramp rather than by an exact color: no face's mean height lands on
    # a particular stop, so asking for one color would be asking for a
    # coincidence.
    var cool = 0
    var warm = 0
    for py in range(c.height):
        for px in range(c.width):
            var p = c.get_pixel(px, py)
            if Int(p.b) > Int(p.r) + 30:
                cool += 1
            elif Int(p.r) > Int(p.b) + 30:
                warm += 1
    assert_true(
        cool > 200 and warm > 200,
        (
            "only one end of the height ramp reached the figure (cool "
            + String(cool)
            + ", warm "
            + String(warm)
            + ")"
        ),
    )


# ==== what a grid has to be ====


def test_a_ragged_grid_names_the_row_that_disagrees() raises:
    var z = _flat_grid(3, 4, 0.0)
    z[1].append(9.0)
    with assert_raises(contains="row 1 has 5 values against 4"):
        _ = render(surface3d(z))


def test_a_grid_with_one_row_has_no_cells() raises:
    with assert_raises(contains="at least 2 rows"):
        _ = render(surface3d(_flat_grid(1, 4, 0.0)))


def test_a_grid_with_one_column_has_no_cells() raises:
    with assert_raises(contains="at least 2 columns"):
        _ = render(surface3d(_flat_grid(4, 1, 0.0)))


def test_lattice_coordinates_follow_the_same_rules_a_contours_do() raises:
    # Same checker, so a field drawn either way keeps the same axes.
    var z = _flat_grid(3, 3, 0.0)
    var wrong: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="Plot.encode_surface(): x must have one"):
        _ = render(surface3d(z, x=wrong))
    var backwards: List[Float64] = [0.0, 2.0, 1.0]
    with assert_raises(contains="strictly increasing"):
        _ = render(surface3d(z, y=backwards))


def test_encode_surface_rejects_a_mark_with_no_grid() raises:
    with assert_raises(contains="encode_surface"):
        _ = Plot().mark_scatter3d().encode_surface(_flat_grid(3, 3, 0.0))


def test_encode_xyz_accepts_trisurf3d() raises:
    # `trisurf3d` takes three loose columns, not a grid, so it rides
    # `encode_xyz` with the other scattered marks.
    var xs: List[Float64] = [0.0, 1.0, 0.5]
    var ys: List[Float64] = [0.0, 0.0, 1.0]
    var zs: List[Float64] = [0.0, 1.0, 2.0]
    var p = Plot().mark_trisurf3d().encode_xyz(xs, ys, zs)
    assert_true(p._mark == Mark.TRISURF3D)


# ==== where a stem anchors ====


def test_a_stem_always_reaches_the_base_plane() raises:
    # A stem is read as a length from the plane, so a range starting at
    # the lowest point would draw every stem from a floor that is not
    # zero and make the short ones look shorter than they are.
    var xs: List[Float64] = [0.0, 1.0]
    var ys: List[Float64] = [0.0, 1.0]
    var high: List[Float64] = [8.0, 9.0]
    var plot = Plot().mark_stem3d().encode_xyz(xs, ys, high)
    var extent = _stem3d_extent(plot)
    assert_equal(extent.z.min, 0.0, "the base plane is not in the range")
    assert_equal(extent.z.max, 9.0)
    # And downward stems keep the plane too, rather than each direction
    # getting its own floor.
    var low: List[Float64] = [-8.0, -9.0]
    var down = Plot().mark_stem3d().encode_xyz(xs, ys, low)
    var below = _stem3d_extent(down)
    assert_equal(below.z.max, 0.0, "the base plane is not in the range")
    assert_equal(below.z.min, -9.0)


def test_stem3d_draws_a_stem_under_every_marker() raises:
    # The tether is the whole mark: without it a floating marker's
    # height cannot be read, because nothing says where under it the
    # plane is. Compare against the same points with no stems.
    var xs: List[Float64] = [0.0, 1.0, 2.0]
    var ys: List[Float64] = [0.0, 1.0, 0.0]
    var zs: List[Float64] = [3.0, 5.0, 4.0]
    var stems = render(stem3d(xs, ys, zs, width=_W, height=_H))
    var bare = render(scatter3d(xs, ys, zs, width=_W, height=_H))
    var bg = Theme().background
    var stem_ink = 0
    var bare_ink = 0
    for y in range(_H):
        for x in range(_W):
            var p = stems.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                stem_ink += 1
            var q = bare.get_pixel(x, y)
            if q.r != bg.r or q.g != bg.g or q.b != bg.b:
                bare_ink += 1
    assert_true(
        stem_ink > bare_ink + 200,
        (
            "stem3d drew about as much as a bare scatter ("
            + String(stem_ink)
            + " against "
            + String(bare_ink)
            + "), so the stems are missing"
        ),
    )


# ==== arrows ====


def test_the_box_reaches_an_arrows_tip_not_just_its_tail() raises:
    # An arrow leaving the box would read as pointing at something
    # outside the data.
    var o: List[Float64] = [0.0]
    var u: List[Float64] = [3.0]
    var v: List[Float64] = [-2.0]
    var w: List[Float64] = [5.0]
    var plot = Plot().mark_quiver3d().encode_vectors3d(o, o, o, u, v, w)
    var extent = _vectors3d_extent(plot)
    assert_equal(extent.x.max, 3.0, "the box stops short of the tip in x")
    assert_equal(extent.y.min, -2.0, "the box stops short of the tip in y")
    assert_equal(extent.z.max, 5.0, "the box stops short of the tip in z")


def _head_ink(tail_x: Float64, tip_x: Float64) raises -> Int:
    """Pixels an arrowhead alone puts on a blank canvas."""
    var bg = Color(255, 255, 255)
    var c = Canvas(80, 80, bg)
    _draw_arrowhead(c, tail_x, 40.0, tip_x, 40.0, 10.0, Color(0, 0, 0))
    var ink = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                ink += 1
    return ink


def test_an_arrow_with_no_length_draws_no_head() raises:
    # There is no direction to point it, and guessing one would draw an
    # arrow the data does not support.
    #
    # Tested on the head alone rather than through two renders: each
    # render fits its own box to its own data, so two quiver charts
    # that differ in an arrow's length differ in scale as well, and
    # comparing their ink compares the scaling too.
    #
    # The perturbation this catches is substituting a direction for the
    # missing one. Dropping only the early return does *not* fail it --
    # a unit length puts the head's three corners on the tip and fills
    # nothing -- so that return is about the division, not about this.
    assert_equal(
        _head_ink(40.0, 40.0), 0, "a shaft with no length still got a head"
    )
    assert_true(
        _head_ink(10.0, 60.0) > 20,
        "a shaft with a direction got no head",
    )


def test_the_six_arrow_columns_must_agree() raises:
    var three: List[Float64] = [0.0, 1.0, 2.0]
    var two: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="w has 2"):
        _ = render(quiver3d(three, three, three, three, three, two))


# ==== ribbons ====


def test_a_ribbon_fills_between_the_two_curves() raises:
    # Two curves a constant distance apart, so the ribbon is a sheet
    # rather than a line: it has to cover far more than the curves do.
    var a = List[Float64]()
    var b = List[Float64]()
    var flat = List[Float64]()
    var up = List[Float64]()
    for i in range(12):
        a.append(Float64(i))
        b.append(Float64(i))
        flat.append(0.0)
        up.append(4.0)
    var c = render(
        fill_between3d(a, flat, flat, b, flat, up, width=_W, height=_H)
    )
    var bg = Theme().background
    var ink = 0
    for y in range(_H):
        for x in range(_W):
            var p = c.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                ink += 1
    assert_true(
        ink > 8000,
        "the ribbon covered only " + String(ink) + " pixels, so it is a line",
    )


def test_a_ribbon_needs_two_samples_to_have_any_surface() raises:
    var one: List[Float64] = [0.0]
    with assert_raises(contains="at least 2 samples"):
        _ = render(fill_between3d(one, one, one, one, one, one))


def test_the_six_ribbon_columns_must_agree() raises:
    var three: List[Float64] = [0.0, 1.0, 2.0]
    var two: List[Float64] = [0.0, 1.0]
    with assert_raises(contains="z2 has 2"):
        _ = render(fill_between3d(three, three, three, three, three, two))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
