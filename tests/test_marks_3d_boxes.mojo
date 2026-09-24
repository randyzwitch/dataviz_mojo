"""The cuboid marks: `bar3d` and `voxels` (#345).

Step 5's first half. What is specific to these two, and so tested here,
is the box itself: that its faces are ordered so the ones facing the
reader win, that the three orientations are told apart by shade, and
that a face buried inside a solid is never built.

The camera and frame they project through are tested in
`test_primitives.mojo`, and the mesh plumbing they share with the
surfaces in `test_marks_3d.mojo`.
"""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from canvas.buffer import Canvas
from canvas.color import Color
from dataframe import Column, DataFrame, Series

from dataviz.core.camera3d import Camera3D
from dataviz.core.frame3d import _Extent3D, _fit_frame3d
from dataviz.core.mark import Mark
from dataviz.core.scale import MinMax
from dataviz.core.theme import Theme
from dataviz.plot import Plot
from dataviz import render, render_svg, bar3d, voxels
from dataviz.spatial.bar3d import _face_color, _smallest_gap, _voxel_mesh


comptime _W = 420
comptime _H = 320


def _solid(layers: Int, rows: Int, cols: Int) -> List[List[List[Bool]]]:
    """A fully filled box of cells."""
    var grid = List[List[List[Bool]]]()
    for _ in range(layers):
        var rs = List[List[Bool]]()
        for _ in range(rows):
            var cs = List[Bool]()
            for _ in range(cols):
                cs.append(True)
            rs.append(cs^)
        grid.append(rs^)
    return grid^


def _mesh_for(grid: List[List[List[Bool]]]) raises -> Int:
    """How many triangles the culled mesh of `grid` holds."""
    var plot = Plot().mark_voxels().encode_voxels(grid)
    var layers = len(grid)
    var rows = len(grid[0])
    var cols = len(grid[0][0])
    var frame = _fit_frame3d(
        Camera3D(),
        _Extent3D(
            MinMax(0.0, Float64(cols)),
            MinMax(0.0, Float64(rows)),
            MinMax(0.0, Float64(layers)),
        ),
        0,
        0,
        _W,
        _H,
    )
    var mesh = _voxel_mesh(plot, frame, (layers, rows, cols), Theme())
    return len(mesh.colors)


# ==== faces inside a solid are never built ====


def test_a_lone_cell_builds_all_six_of_its_faces() raises:
    # Nothing next to it, so nothing is culled: six quads, two
    # triangles each.
    assert_equal(_mesh_for(_solid(1, 1, 1)), 12)


def test_a_filled_block_builds_only_its_surface() raises:
    # The whole reason the culling exists, and the only way to see it:
    # the render is identical either way, because everything dropped is
    # behind something that is drawn. A 2x2x2 block has 8 cells and 48
    # faces, of which 24 are on the surface -- each of the 6 sides
    # showing 4 cells.
    assert_equal(_mesh_for(_solid(2, 2, 2)), 24 * 2)
    # And it keeps scaling with the surface rather than the volume: a
    # 4x4x4 has 64 cells but the same six 4-by-4 sides.
    assert_equal(_mesh_for(_solid(4, 4, 4)), 6 * 16 * 2)


def test_a_sealed_cavity_still_costs_its_six_walls() raises:
    # The limit of the rule, pinned so it is a known cost rather than a
    # surprise. Culling asks one question -- is the neighbor across this
    # face filled -- and a cavity's walls all answer no, so the six
    # faces around a hole in the middle of a block get built even though
    # no one outside the block can see them.
    #
    # Dropping them needs reachability from outside the solid, not a
    # neighbor test. That is worth doing when a caller turns up whose
    # grids are mostly sealed pockets; until then it is six faces.
    var full = _mesh_for(_solid(3, 3, 3))
    assert_equal(full, 6 * 9 * 2, "a 3x3x3 block is six 3-by-3 sides")
    var hollow = _solid(3, 3, 3)
    hollow[1][1][1] = False
    assert_equal(
        _mesh_for(hollow),
        full + 6 * 2,
        "a sealed cavity should cost exactly its own six walls",
    )


# ==== a box is drawn from the outside ====


def _bright_split(c: Canvas) raises -> Tuple[Int, Int]:
    """Pixels of the top-and-bottom shade above and below the middle of
    the figure."""
    var bright = _face_color(Theme().mark_color, 2, Theme())
    var above = 0
    var below = 0
    for y in range(c.height):
        for x in range(c.width):
            var p = c.get_pixel(x, y)
            if p.r == bright.r and p.g == bright.g and p.b == bright.b:
                if y < c.height // 2:
                    above += 1
                else:
                    below += 1
    return (above, below)


def test_a_lone_cube_shows_its_top_and_not_its_underside() raises:
    # The camera is above the scene, so the face a reader sees is the
    # top one. Both z-facing faces take the same shade, so which of them
    # was drawn is read off where the shade landed: a top face sits in
    # the upper half of the cube's outline, an underside in the lower.
    #
    # This is the guard the whole family needs. Hand the faces over
    # nearest-first and the cube's underside is painted over its own
    # sides, which is what the first render of this mark did (#642).
    var split = _bright_split(render(voxels(_solid(1, 1, 1))))
    assert_true(split[0] > 0, "the cube drew none of its top-and-bottom shade")
    assert_true(
        split[0] > split[1] * 3,
        (
            "the top-and-bottom shade is mostly in the lower half ("
            + String(split[0])
            + " above against "
            + String(split[1])
            + " below), so the cube is being seen from underneath"
        ),
    )


def test_the_three_face_orientations_are_told_apart() raises:
    # A box in one flat color projects to a hexagon with no internal
    # structure, and a row of them reads as a row of hexagons.
    var theme = Theme()
    var top = _face_color(theme.mark_color, 2, theme)
    var side_x = _face_color(theme.mark_color, 0, theme)
    var side_y = _face_color(theme.mark_color, 1, theme)
    for pair in [(top, side_x), (top, side_y), (side_x, side_y)]:
        assert_true(
            pair[0].r != pair[1].r
            or pair[0].g != pair[1].g
            or pair[0].b != pair[1].b,
            "two face orientations came out the same color",
        )


# ==== bar footprints ====


def test_the_footprint_follows_the_closest_pair_not_the_average() raises:
    # One crowded row is what makes a figure unreadable; the rest of it
    # having room does not help.
    var spread: List[Float64] = [0.0, 1.0, 1.25, 10.0]
    assert_equal(_smallest_gap(spread), 0.25)


def test_the_closest_pair_is_found_wherever_it_sits_in_the_input() raises:
    # The pair need not be adjacent in the caller's order, and repeats
    # are not a gap of zero.
    var scattered: List[Float64] = [0.0, 10.0, 0.3, 5.0]
    assert_equal(_smallest_gap(scattered), 0.3)
    var repeats: List[Float64] = [2.0, 2.5, 2.0, 2.0]
    assert_equal(_smallest_gap(repeats), 0.5)


def test_one_position_leaves_the_footprint_a_unit_wide() raises:
    # No pair at all, so nothing to be a fraction of.
    var same: List[Float64] = [3.0, 3.0, 3.0]
    assert_equal(_smallest_gap(same), 1.0)


def test_bars_at_a_full_footprint_touch_without_overlapping() raises:
    var xs: List[Float64] = [0.0, 1.0]
    var ys: List[Float64] = [0.0, 0.0]
    var zs: List[Float64] = [1.0, 2.0]
    _ = render(bar3d(xs, ys, zs, bar_width=1.0, bar_depth=1.0))


def test_a_footprint_wider_than_the_spacing_is_refused() raises:
    # Overlapping bars hide each other, and which one wins is the depth
    # sort rather than anything the reader can reason about.
    var xs: List[Float64] = [0.0, 1.0]
    var ys: List[Float64] = [0.0, 0.0]
    var zs: List[Float64] = [1.0, 2.0]
    with assert_raises(contains="at most 1"):
        _ = render(bar3d(xs, ys, zs, bar_width=1.5))
    with assert_raises(contains="above 0"):
        _ = render(bar3d(xs, ys, zs, bar_depth=0.0))


def test_a_bars_base_is_always_zero() raises:
    # A bar is read as a length from the base plane, so a range that
    # started at the shortest bar would make every bar look shorter
    # than it is. Bars above zero and bars below it therefore share the
    # plane rather than each getting their own floor.
    var xs: List[Float64] = [0.0, 1.0]
    var ys: List[Float64] = [0.0, 0.0]
    var rising: List[Float64] = [3.0, 5.0]
    var falling: List[Float64] = [-3.0, -5.0]
    var up = render(bar3d(xs, ys, rising, width=_W, height=_H))
    var down = render(bar3d(xs, ys, falling, width=_W, height=_H))
    var bg = Theme().background
    var up_ink = 0
    var down_ink = 0
    for y in range(_H):
        for x in range(_W):
            var p = up.get_pixel(x, y)
            if p.r != bg.r or p.g != bg.g or p.b != bg.b:
                up_ink += 1
            var q = down.get_pixel(x, y)
            if q.r != bg.r or q.g != bg.g or q.b != bg.b:
                down_ink += 1
    assert_true(
        up_ink > 3000 and down_ink > 3000,
        "one of the two directions drew almost nothing",
    )


# ==== what the data has to be ====


def test_the_three_bar_columns_must_agree_in_length() raises:
    var xs: List[Float64] = [0.0, 1.0]
    var ys: List[Float64] = [0.0]
    var zs: List[Float64] = [1.0, 2.0]
    with assert_raises(contains="same length"):
        _ = render(bar3d(xs, ys, zs))


def test_an_empty_bar_chart_raises() raises:
    var empty = List[Float64]()
    with assert_raises(contains="encode_bars3d"):
        _ = render(bar3d(empty, empty, empty))


def test_a_ragged_voxel_layer_names_the_layer() raises:
    var grid = _solid(2, 2, 2)
    grid[1].append([True, True])
    with assert_raises(contains="layer 1 has 3 against 2"):
        _ = render(voxels(grid))


def test_a_ragged_voxel_row_names_the_row() raises:
    var grid = _solid(2, 2, 2)
    grid[1][0].append(True)
    with assert_raises(contains="layer 1 row 0 has 3 against 2"):
        _ = render(voxels(grid))


def test_encode_voxels_rejects_a_mark_with_no_grid() raises:
    with assert_raises(contains="encode_voxels"):
        _ = Plot().mark_bar3d().encode_voxels(_solid(1, 1, 1))


def test_voxels_frame_marks_sparse_occupied_cells() raises:
    var frame = DataFrame(
        [
            Series("col", Column[Float64]([0.0, 1.0, 0.0])),
            Series("row", Column[Float64]([0.0, 0.0, 1.0])),
            Series("layer", Column[Float64]([0.0, 0.0, 1.0])),
        ]
    )
    var by_frame = render_svg(
        voxels(frame, x="col", y="row", z="layer", width=360, height=280)
    ).to_string()
    var grid: List[List[List[Bool]]] = [
        [[True, True], [False, False]],
        [[False, False], [True, False]],
    ]
    var by_grid = render_svg(voxels(grid, width=360, height=280)).to_string()
    assert_equal(by_frame, by_grid, "sparse frame matches filled grid")
    var fractional = DataFrame(
        [
            Series("x", Column[Float64]([0.5])),
            Series("y", Column[Float64]([0.0])),
            Series("z", Column[Float64]([0.0])),
        ]
    )
    with assert_raises(contains="nonnegative integers"):
        _ = voxels(fractional, x="x", y="y", z="z")
    var repeated = DataFrame(
        [
            Series("x", Column[Float64]([0.0, 0.0])),
            Series("y", Column[Float64]([0.0, 0.0])),
            Series("z", Column[Float64]([0.0, 0.0])),
        ]
    )
    with assert_raises(contains="duplicate occupied cell"):
        _ = voxels(repeated, x="x", y="y", z="z")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
