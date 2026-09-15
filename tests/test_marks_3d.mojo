"""The three surface marks: `surface3d`, `wire3d` and `trisurf3d` (#345).

Step 4 of #345. The camera and the frame they project through have
their own unit tests in `test_primitives.mojo`; what is tested here is
what the marks build on top of that -- the order faces are handed over
in, the seamless fill that order feeds, and the grid rules the input has
to satisfy.
"""

from std.math import cos, sin
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color

from dataviz import surface3d, trisurf3d, wire3d
from dataviz.core.color_scale import _ColorDomainOverride, _color_scale_for
from dataviz.core.mark import Mark
from dataviz.core.theme import Theme
from dataviz.plot import Plot, render, render_svg
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


def _walled_grid(far: Bool) -> List[List[Float64]]:
    """A flat field with a wall standing along one edge of it.

    At the default view row 4 is the far edge and row 0 the near one.
    The far wall is the case that needs the depth sort: its lower part
    lies behind the plane in projection, so the plane has to be drawn
    over it.
    """
    var z = _flat_grid(5, 5, 0.0)
    var wall = 4 if far else 0
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


def test_a_wall_behind_the_field_never_eats_into_it() raises:
    # The whole point of the depth sort, stated without a threshold:
    # the flat plane is in front of a far wall and in front of nothing
    # at all when the wall is near, so both renders must show exactly as
    # much plane as each other.
    #
    # Measured here: 9508 pixels either way with the faces handed over
    # farthest first. Reverse that order and the far case drops to 6887
    # -- the wall painted over a quarter of the plane -- while the near
    # case is unchanged, which is why the assertion compares the two
    # rather than checking one against a number.
    var near = _count_plane_pixels(_walled_grid(False))
    var far = _count_plane_pixels(_walled_grid(True))
    assert_true(near > 5000, "the plane barely drew at all: " + String(near))
    assert_equal(
        far,
        near,
        (
            "a wall on the far side covered part of the plane in front of"
            " it -- the faces are not going over farthest first"
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
