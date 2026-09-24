"""Field marks from a long-form frame (#743, tier 3).

A field is a grid; a frame is a list of cells. `_frame_grid` pivots one
into the other, and the interesting case is the table that was never
rectangular: a cell with no row is **missing**, not zero, so it comes
out blank and takes no part in the limits (#367).

The equivalence test is the load-bearing one, as in the other tiers:
pivoting a complete table must give the same chart as passing the grid
by hand.
"""

from dataframe import Column, DataFrame, Series

from dataviz import (
    contour,
    contourf,
    imshow,
    pcolormesh,
    streamplot,
    surface3d,
    wire3d,
)
from dataviz.core.frame_input import _frame_grid
from dataviz.plot import render_svg
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from std.utils.numerics import isnan


def _full_frame() raises -> DataFrame:
    """A complete 3x4 field, one row per cell, deliberately out of
    order so the pivot's sorting is doing the work."""
    var rows = List[Float64]()
    var cols = List[Float64]()
    var vals = List[Float64]()
    for r in range(2, -1, -1):
        for c in range(3, -1, -1):
            rows.append(Float64(r))
            cols.append(Float64(c))
            vals.append(Float64(r * 10 + c))
    return DataFrame(
        [
            Series("y", Column[Float64](rows.copy())),
            Series("x", Column[Float64](cols.copy())),
            Series("z", Column[Float64](vals.copy())),
        ]
    )


def _holed_frame() raises -> DataFrame:
    """The same field with one cell absent from the table."""
    var rows = List[Float64]()
    var cols = List[Float64]()
    var vals = List[Float64]()
    for r in range(3):
        for c in range(4):
            if r == 1 and c == 2:
                continue
            rows.append(Float64(r))
            cols.append(Float64(c))
            vals.append(Float64(r * 10 + c))
    return DataFrame(
        [
            Series("y", Column[Float64](rows.copy())),
            Series("x", Column[Float64](cols.copy())),
            Series("z", Column[Float64](vals.copy())),
        ]
    )


def test_the_pivot_matches_the_grid_built_by_hand() raises:
    var by_frame = render_svg(
        imshow(
            _full_frame(), row="y", column="x", value="z", width=320, height=240
        )
    ).to_string()

    var grid = List[List[Float64]]()
    for r in range(3):
        var line = List[Float64]()
        for c in range(4):
            line.append(Float64(r * 10 + c))
        grid.append(line^)
    # The frame overload titles the axes from the column names, so the
    # hand-built call says the same thing.
    var by_hand = render_svg(
        imshow(grid, width=320, height=240, x_title="x", y_title="y")
    ).to_string()
    assert_equal(by_frame, by_hand, "same document, byte for byte")


def test_both_axes_come_out_ascending() raises:
    var grid = _frame_grid(_full_frame(), "y", "x", "z", "t")
    ref y = grid[0]
    ref x = grid[1]
    ref z = grid[2]
    assert_equal(y[0], 0.0, "rows ascending despite the table's order")
    assert_equal(y[2], 2.0)
    assert_equal(x[0], 0.0, "and columns")
    assert_equal(x[3], 3.0)
    assert_equal(z[1][2], 12.0, "the cell at (row 1, column 2)")


def test_a_cell_with_no_row_comes_out_missing_not_zero() raises:
    """The whole point of the tier: a table that was never rectangular
    can be drawn as a field without inventing a value."""
    var grid = _frame_grid(_holed_frame(), "y", "x", "z", "t")
    ref z = grid[2]
    assert_true(isnan(z[1][2]), "the absent cell is missing")
    assert_equal(z[1][1], 11.0, "its neighbours are untouched")
    assert_equal(z[2][2], 22.0)


def test_a_repeated_cell_raises_rather_than_picking_one() raises:
    var df = DataFrame(
        [
            Series("y", Column[Float64]([0.0, 0.0])),
            Series("x", Column[Float64]([1.0, 1.0])),
            Series("z", Column[Float64]([5.0, 9.0])),
        ]
    )
    with assert_raises(contains="more than one row at"):
        _ = _frame_grid(df, "y", "x", "z", "t")


def test_a_string_coordinate_is_refused() raises:
    """A field's axes are coordinates, not labels: these marks
    interpolate between them."""
    var df = DataFrame(
        [
            Series("y", Column[String](["a", "b"])),
            Series("x", Column[Float64]([1.0, 2.0])),
            Series("z", Column[Float64]([5.0, 9.0])),
        ]
    )
    with assert_raises(contains="not a numeric column"):
        _ = _frame_grid(df, "y", "x", "z", "t")


def test_every_field_mark_takes_a_holed_frame() raises:
    """Before #367 a missing cell reached `Int(nan)` in contour's
    marching squares and crashed the process. Each of these renders a
    field with a hole in it."""
    var df = _holed_frame()
    var svgs = List[String]()
    svgs.append(
        render_svg(
            imshow(df, row="y", column="x", value="z", width=320, height=240)
        ).to_string()
    )
    svgs.append(
        render_svg(
            pcolormesh(
                df,
                row="y",
                column="x",
                value="z",
                x_edges=[-0.5, 0.5, 1.5, 2.5, 3.5],
                y_edges=[-0.5, 0.5, 1.5, 2.5],
                width=320,
                height=240,
            )
        ).to_string()
    )
    svgs.append(
        render_svg(
            contour(df, row="y", column="x", value="z", width=320, height=240)
        ).to_string()
    )
    svgs.append(
        render_svg(
            contourf(df, row="y", column="x", value="z", width=320, height=240)
        ).to_string()
    )
    svgs.append(
        render_svg(
            surface3d(df, row="y", column="x", value="z", width=320, height=260)
        ).to_string()
    )
    svgs.append(
        render_svg(
            wire3d(df, row="y", column="x", value="z", width=320, height=260)
        ).to_string()
    )
    for svg in svgs:
        assert_true(svg.byte_length() > 500, "each mark drew a chart")


def test_a_contour_skips_only_the_cells_touching_the_hole() raises:
    """A hole leaves a hole: the contours around it are still drawn, so
    the chart is not empty and not complete."""
    var holed = render_svg(
        contour(
            _holed_frame(),
            row="y",
            column="x",
            value="z",
            width=320,
            height=240,
        )
    ).to_string()
    var whole = render_svg(
        contour(
            _full_frame(), row="y", column="x", value="z", width=320, height=240
        )
    ).to_string()
    assert_true(holed != whole, "the hole changes the picture")
    assert_true(
        holed.byte_length() > 500, "and the rest of the field still draws"
    )


def test_streamplot_pivots_both_components_onto_one_grid() raises:
    var rows = List[Float64]()
    var cols = List[Float64]()
    var us = List[Float64]()
    var vs = List[Float64]()
    for r in range(3):
        for c in range(3):
            rows.append(Float64(r))
            cols.append(Float64(c))
            us.append(Float64(c) * 0.5)
            vs.append(Float64(r) * 0.5)
    var df = DataFrame(
        [
            Series("y", Column[Float64](rows.copy())),
            Series("x", Column[Float64](cols.copy())),
            Series("u", Column[Float64](us.copy())),
            Series("v", Column[Float64](vs.copy())),
        ]
    )
    var svg = render_svg(
        streamplot(df, row="y", column="x", u="u", v="v", width=320, height=240)
    ).to_string()
    assert_true(svg.byte_length() > 500, "a field of streamlines")
    assert_true(">x</text>" in svg, "the x axis is titled by its column")


def test_pcolormesh_frame_keeps_irregular_cell_boundaries() raises:
    var x_edges: List[Float64] = [-0.5, 0.4, 1.6, 2.7, 4.5]
    var y_edges: List[Float64] = [-0.4, 0.6, 1.3, 3.5]
    var by_frame = render_svg(
        pcolormesh(
            _full_frame(),
            row="y",
            column="x",
            value="z",
            x_edges=x_edges,
            y_edges=y_edges,
            width=320,
            height=240,
        )
    ).to_string()
    var grid = List[List[Float64]]()
    for r in range(3):
        var line = List[Float64]()
        for c in range(4):
            line.append(Float64(r * 10 + c))
        grid.append(line^)
    var by_hand = render_svg(
        pcolormesh(
            x_edges,
            y_edges,
            grid,
            width=320,
            height=240,
            x_title="x",
            y_title="y",
        )
    ).to_string()
    assert_equal(by_frame, by_hand, "frame cells keep supplied edges")
    with assert_raises(contains="one more value"):
        _ = pcolormesh(
            _full_frame(),
            row="y",
            column="x",
            value="z",
            x_edges=[-0.5, 0.5],
            y_edges=y_edges,
        )
    with assert_raises(contains="outside its cell boundaries"):
        _ = pcolormesh(
            _full_frame(),
            row="y",
            column="x",
            value="z",
            x_edges=[0.1, 0.4, 1.6, 2.7, 4.5],
            y_edges=y_edges,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
