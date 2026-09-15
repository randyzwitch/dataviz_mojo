from std.collections import Dict
from std.math import isfinite

from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.fill_rule import FillRule
from canvas.geometry import round_to_int
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.core.color_scale import ColorScale, _color_scale_for
from dataviz.plot import (
    Plot,
    _LegendLayout,
    _RenderResult,
    _data_extent,
    _draw_continuous_axis_frame,
    _draw_legend_at,
    _finished,
    _legend_layout,
    _levels_descending,
)
from dataviz.core.scale import _format_tick
from dataviz.core.text import _Scaled
from dataviz.core.scale import LinearScale
from dataviz.core.theme import Theme


struct _ContourData(Copyable, Movable):
    """The grid and level list for `Mark.CONTOUR`. See
    `encode_contour()`/`mark_contour()`. Stored on `Plot._contour`.

    `z` is row-major: `z[row][col]`, every row the same length. Rows are
    the y axis and columns the x axis, both in grid-index units, so a
    10x20 grid spans x `[0, 19]` and y `[0, 9]`.

    `x`/`y` are the grid's coordinates, one per column and one per row.
    Left empty they *are* the grid indices, which is the behavior
    `contour(z)` has always had. Given, they put the grid on the
    caller's own axes: `contour(x, y, z)` in matplotlib's terms, and
    what lets a contour share a frame with a coordinate mark rather
    than silently equating column 12 with the value 12 (#423).

    `levels` empty means "choose them", which `_auto_levels` does from
    `level_count` once the data's range is known at render time.
    """

    var z: List[List[Float64]]
    var x: List[Float64]
    var y: List[Float64]
    var levels: List[Float64]
    var level_count: Int

    def __init__(out self):
        self.z = List[List[Float64]]()
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.levels = List[Float64]()
        self.level_count = 8


struct _Polyline(Movable):
    """One chained isoline: parallel x/y lists in grid-index coordinates,
    ready to be projected through the axis scales and stroked as a
    `Path`.
    """

    var xs: List[Float64]
    var ys: List[Float64]

    def __init__(out self):
        self.xs = List[Float64]()
        self.ys = List[Float64]()


struct _Segments(Movable):
    """Every marching-squares segment for one level, as parallel arrays.

    A segment's two ends are identified twice over: by grid *edge id*
    (`ea`/`eb`, what `_chain_segments` joins on) and by position
    (`ax`/`ay`/`bx`/`by`, what actually gets drawn). The edge id is the
    key insight that keeps chaining exact -- a crossing always lies on a
    grid edge shared by at most two cells, so joining on an integer edge
    id needs no tolerance and no hashing of floats.
    """

    var ea: List[Int]
    var eb: List[Int]
    var ax: List[Float64]
    var ay: List[Float64]
    var bx: List[Float64]
    var by: List[Float64]

    def __init__(out self):
        self.ea = List[Int]()
        self.eb = List[Int]()
        self.ax = List[Float64]()
        self.ay = List[Float64]()
        self.bx = List[Float64]()
        self.by = List[Float64]()

    def add(
        mut self,
        ea: Int,
        ax: Float64,
        ay: Float64,
        eb: Int,
        bx: Float64,
        by: Float64,
    ):
        self.ea.append(ea)
        self.ax.append(ax)
        self.ay.append(ay)
        self.eb.append(eb)
        self.bx.append(bx)
        self.by.append(by)


struct _GridAxis(Copyable, Movable):
    """Grid index to pixel, in one step, for one axis of a contour.

    Marching squares works in grid indices and always will: a crossing
    is a fraction along a cell edge, which is an index, not a
    coordinate. So every point this mark draws starts as a fractional
    index and has to become a pixel. With no coordinates that is one
    affine step and the scale does it alone; with coordinates it is a
    lookup and then the scale.

    Holding both here rather than mapping the points first keeps the
    geometry in the units it is computed in right up to the pixel, and
    means the drawing functions take one thing per axis instead of a
    scale plus a column they have to remember to apply in the same
    order.

    `coords` empty means the index *is* the coordinate, which is
    `contour(z)`'s own behavior and keeps that path exactly as it was:
    same scale, same call, no lookup.
    """

    var coords: List[Float64]
    var scale: LinearScale

    def __init__(out self, var coords: List[Float64], var scale: LinearScale):
        """Build an axis.

        Args:
            coords: One coordinate per grid column (or row), strictly
                increasing; empty for grid-index units.
            scale: That axis's data-to-pixel scale.
        """
        self.coords = coords^
        self.scale = scale^

    def coordinate(self, index: Float64) -> Float64:
        """The data coordinate at fractional grid `index`.

        Linear between the two neighbors, which is the same assumption
        marching squares already makes inside a cell: a crossing is
        placed by linear interpolation of the corner values, so
        interpolating the coordinate the same way keeps a crossing at
        the fraction of the cell it was computed to be at. A
        non-uniform grid is therefore drawn with straight segments
        across each cell rather than a curve through it, which is what
        the algorithm computes and all it knows.

        An index outside the grid clamps to the end coordinate rather
        than extrapolating; nothing generates one, and a silently
        extrapolated coordinate would be worse than a visibly pinned
        one.

        Args:
            index: Fractional grid index along this axis.

        Returns:
            The coordinate, or `index` itself when there are none.
        """
        var n = len(self.coords)
        if n == 0:
            return index
        if index <= 0.0:
            return self.coords[0]
        if index >= Float64(n - 1):
            return self.coords[n - 1]
        var i = Int(index)
        var f = index - Float64(i)
        return self.coords[i] + (self.coords[i + 1] - self.coords[i]) * f

    def to_pixel(self, index: Float64) -> Float64:
        """The pixel at fractional grid `index`.

        Args:
            index: Fractional grid index along this axis.

        Returns:
            The pixel coordinate.
        """
        return self.scale.to_pixel(self.coordinate(index))


def _check_grid_coordinates(
    coords: List[Float64], n: Int, name: String, what: String
) raises:
    """Raise unless `coords` is empty or names `n` strictly increasing
    values.

    Strictly increasing rather than merely monotone: `_GridAxis`
    interpolates between neighbors, and a repeated coordinate makes a
    cell zero wide, so a whole column of the grid would collapse onto
    one pixel with no way to say which of the two it belonged to.
    Decreasing is not accepted either -- `scale_x_reverse()` is how an
    axis is reversed, and accepting it here would give two ways to say
    it that could disagree.

    Args:
        coords: The column to check; empty passes.
        n: How many values the grid needs.
        name: The argument's name, for the message.
        what: What `n` counts, for the message.

    Raises:
        Error: Wrong length, non-finite, or not strictly increasing.
    """
    if len(coords) == 0:
        return
    if len(coords) != n:
        raise Error(
            "Plot.encode_contour(): "
            + name
            + " must have one value per "
            + what
            + " of z (got "
            + String(len(coords))
            + " for "
            + String(n)
            + " "
            + what
            + "s)"
        )
    for i in range(len(coords)):
        if not isfinite(coords[i]):
            raise Error(
                "Plot.encode_contour(): "
                + name
                + " must be finite -- got "
                + String(coords[i])
                + " at index "
                + String(i)
            )
    for i in range(1, len(coords)):
        if not (coords[i] > coords[i - 1]):
            raise Error(
                "Plot.encode_contour(): "
                + name
                + " must be strictly increasing -- "
                + String(coords[i])
                + " at index "
                + String(i)
                + " does not exceed "
                + String(coords[i - 1])
                + " before it. Use Plot.scale_"
                + ("x" if name == "x" else "y")
                + "_reverse() to reverse the axis."
            )


def _validate_contour(
    plot: Plot, mark_context: String
) raises -> Tuple[Int, Int]:
    """Every check a contour's data has to pass, and its shape.

    A free function because the layer path runs it before the shared
    frame exists, the same arrangement `_validate_tricontour` has: a
    bad layer then raises the message a standalone render of it would.

    Args:
        plot: The plot carrying `_contour`.
        mark_context: The builder to name in a level-count message, so
            a `Mark.CONTOURF` failure says `mark_contourf()`.

    Returns:
        (rows, cols).

    Raises:
        Error: The grid is not rectangular and at least 2x2, the level
            count is not positive, or a coordinate column is the wrong
            length, non-finite, or not strictly increasing.
    """
    var shape = _grid_shape(plot._contour.z)
    if plot._contour.level_count <= 0:
        raise Error(
            mark_context
            + ": levels must be positive (got "
            + String(plot._contour.level_count)
            + ")"
        )
    # Both or neither. One alone would leave the grid padded on one
    # axis and unpadded on the other, which is a frame nothing else in
    # the package draws and which no caller has asked for; matplotlib's
    # `contour(X, Y, Z)` takes both together for the same reason.
    if (len(plot._contour.x) == 0) != (len(plot._contour.y) == 0):
        raise Error(
            "Plot.encode_contour(): give both x and y or neither -- got "
            + ("x" if len(plot._contour.x) > 0 else "y")
            + " alone, which would put one axis in the caller's units and"
            " the other in grid-index units"
        )
    _check_grid_coordinates(plot._contour.x, shape[1], "x", "column")
    _check_grid_coordinates(plot._contour.y, shape[0], "y", "row")
    return shape


def _contour_axes(
    plot: Plot, rows: Int, cols: Int
) raises -> Tuple[_GridAxis, _GridAxis]:
    """The two axes a contour draws through, coordinates or indices.

    Without coordinates the domain is the grid's index range with no
    padding, so the grid spans the plot rect edge to edge -- what
    `contour(z)` has always drawn. With them it is `_data_extent`, the
    same 5%-padded rule every other continuous mark uses, which is what
    makes the axis mean the caller's units and lets a contour share a
    frame with a scatter (#423).

    Args:
        plot: The plot carrying `_contour`.
        rows: The grid's row count.
        cols: Its column count.

    Returns:
        (x axis, y axis).

    Raises:
        Error: Whatever `_data_extent` raises.
    """
    var x_axis = _GridAxis(
        plot._contour.x.copy(),
        _data_extent(plot._contour.x) if len(plot._contour.x)
        > 0 else LinearScale(0.0, Float64(cols - 1), 0.0, 1.0),
    )
    var y_axis = _GridAxis(
        plot._contour.y.copy(),
        _data_extent(plot._contour.y) if len(plot._contour.y)
        > 0 else LinearScale(0.0, Float64(rows - 1), 0.0, 1.0),
    )
    return (x_axis^, y_axis^)


def _grid_shape(z: List[List[Float64]]) raises -> Tuple[Int, Int]:
    """`z`'s (rows, cols), raising unless it is a rectangular grid of at
    least 2x2 -- marching squares walks cells, and a grid with fewer than
    two rows or columns has none.

    Args:
        z: The grid to measure.

    Returns:
        (rows, cols).

    Raises:
        Error: `z` is empty, ragged, or smaller than 2x2.
    """
    var rows = len(z)
    if rows < 2:
        raise Error(
            "Plot.encode_contour(): z needs at least 2 rows to have any grid"
            " cells (got "
            + String(rows)
            + ")"
        )
    var cols = len(z[0])
    if cols < 2:
        raise Error(
            "Plot.encode_contour(): z needs at least 2 columns to have any"
            " grid cells (got "
            + String(cols)
            + ")"
        )
    for r in range(1, rows):
        if len(z[r]) != cols:
            raise Error(
                "Plot.encode_contour(): z must be rectangular -- row 0 has "
                + String(cols)
                + " columns but row "
                + String(r)
                + " has "
                + String(len(z[r]))
            )
    return (rows, cols)


def _auto_levels(z: List[List[Float64]], count: Int) raises -> List[Float64]:
    """`count` levels evenly spaced strictly inside `z`'s range.

    Strictly inside on purpose: a level exactly at the minimum or maximum
    traces the grid's own boundary or a single point, which is a degenerate
    contour rather than a useful one. A flat grid has no interior to
    divide and returns no levels, so it draws nothing rather than raising.

    Args:
        z: The grid to take the range from.
        count: How many levels to place.

    Returns:
        The levels, ascending; empty when `z` is flat.
    """
    var lo = z[0][0]
    var hi = z[0][0]
    for r in range(len(z)):
        for c in range(len(z[r])):
            var v = z[r][c]
            if v < lo:
                lo = v
            if v > hi:
                hi = v
    var levels = List[Float64]()
    if hi <= lo:
        return levels^
    for i in range(count):
        levels.append(lo + (hi - lo) * Float64(i + 1) / Float64(count + 1))
    return levels^


def _crossing(v0: Float64, v1: Float64, level: Float64) -> Float64:
    """Where along an edge from `v0` to `v1` the value crosses `level`, as
    a fraction in [0, 1].

    Args:
        v0: Value at the edge's start.
        v1: Value at the edge's end.
        level: The level being traced.

    Returns:
        The interpolation fraction; 0.5 for a zero-length value span,
        which only arises when both ends equal `level`.
    """
    var span = v1 - v0
    if span == 0.0:
        return 0.5
    return (level - v0) / span


def _contour_segments(
    z: List[List[Float64]], rows: Int, cols: Int, level: Float64
) -> _Segments:
    """Marching squares over every cell for one `level`.

    Each cell's four corners are classified above/below `level` into a
    4-bit case, and the standard 16-case table says which pair of cell
    edges the isoline crosses. Crossing positions come from linear
    interpolation along the edge.

    The two ambiguous (saddle) cases -- diagonal corners on the same side
    -- are resolved by the average of the four corners, the same rule
    contourpy uses: whichever side the cell center falls on is the side
    whose two corners are connected through the middle, which leaves the
    other pair isolated in their own corners.

    Edge ids number the grid's own edges, not the cell's: a horizontal
    edge between `(r, c)` and `(r, c+1)` is `r * (cols - 1) + c`, and a
    vertical edge between `(r, c)` and `(r+1, c)` follows them. Two cells
    sharing an edge therefore produce the same id for the crossing on it,
    which is what lets `_chain_segments` join them exactly.

    Args:
        z: The grid, row-major.
        rows: `len(z)`.
        cols: `len(z[0])`.
        level: The value to trace.

    Returns:
        Every segment found, unordered.
    """
    var segs = _Segments()
    var h_count = rows * (cols - 1)

    for r in range(rows - 1):
        for c in range(cols - 1):
            var a = z[r][c]
            var b = z[r][c + 1]
            var cc = z[r + 1][c + 1]
            var d = z[r + 1][c]

            var mask = 0
            if a > level:
                mask += 1
            if b > level:
                mask += 2
            if cc > level:
                mask += 4
            if d > level:
                mask += 8
            if mask == 0 or mask == 15:
                continue

            # The four possible crossings, in grid-index coordinates.
            var bottom_x = Float64(c) + _crossing(a, b, level)
            var bottom_y = Float64(r)
            var bottom_e = r * (cols - 1) + c

            var right_x = Float64(c + 1)
            var right_y = Float64(r) + _crossing(b, cc, level)
            var right_e = h_count + r * cols + (c + 1)

            var top_x = Float64(c) + _crossing(d, cc, level)
            var top_y = Float64(r + 1)
            var top_e = (r + 1) * (cols - 1) + c

            var left_x = Float64(c)
            var left_y = Float64(r) + _crossing(a, d, level)
            var left_e = h_count + r * cols + c

            if mask == 1 or mask == 14:
                segs.add(left_e, left_x, left_y, bottom_e, bottom_x, bottom_y)
            elif mask == 2 or mask == 13:
                segs.add(
                    bottom_e, bottom_x, bottom_y, right_e, right_x, right_y
                )
            elif mask == 3 or mask == 12:
                segs.add(left_e, left_x, left_y, right_e, right_x, right_y)
            elif mask == 4 or mask == 11:
                segs.add(right_e, right_x, right_y, top_e, top_x, top_y)
            elif mask == 6 or mask == 9:
                segs.add(bottom_e, bottom_x, bottom_y, top_e, top_x, top_y)
            elif mask == 7 or mask == 8:
                segs.add(left_e, left_x, left_y, top_e, top_x, top_y)
            else:
                # Cases 5 and 10: diagonal corners share a side, so the
                # cell center decides which pair the isoline separates.
                var center = (a + b + cc + d) / 4.0
                var center_above = center > level
                # In case 5 the "above" pair is a/cc; in case 10 it is
                # b/d. The center joining the above pair isolates the
                # below corners, and vice versa.
                var join_diagonal = (
                    center_above if mask == 5 else not center_above
                )
                if join_diagonal:
                    # b and d are each alone in their corner.
                    segs.add(
                        bottom_e, bottom_x, bottom_y, right_e, right_x, right_y
                    )
                    segs.add(top_e, top_x, top_y, left_e, left_x, left_y)
                else:
                    # a and cc are each alone in their corner.
                    segs.add(
                        left_e, left_x, left_y, bottom_e, bottom_x, bottom_y
                    )
                    segs.add(right_e, right_x, right_y, top_e, top_x, top_y)

    return segs^


def _chain_segments(segs: _Segments) raises -> List[_Polyline]:
    """Join segments end to end into as few polylines as possible.

    Marching squares emits each cell's segments independently, so an
    isoline arrives as a pile of unordered two-point pieces. Stroking
    them individually would draw thousands of separate paths and put a
    line cap at every cell boundary; chaining first draws each isoline as
    one path.

    Joins are on the integer edge id both ends carry, so no coordinate
    comparison or tolerance is involved. An edge is shared by at most two
    cells, so at most two segments meet at any crossing: an open isoline
    ends where its edge has only one, and a closed one comes back to its
    start.

    Args:
        segs: Unordered segments from `_contour_segments`.

    Returns:
        One `_Polyline` per isoline.
    """
    var n = len(segs.ea)
    var out = List[_Polyline]()
    if n == 0:
        return out^

    # edge id -> the (at most two) segments touching it.
    var first = Dict[Int, Int]()
    var second = Dict[Int, Int]()
    for s in range(n):
        for which in range(2):
            var e = segs.ea[s] if which == 0 else segs.eb[s]
            if e in first:
                second[e] = s
            else:
                first[e] = s

    var used = List[Bool](length=n, fill=False)

    for start in range(n):
        if used[start]:
            continue
        used[start] = True

        var line = _Polyline()
        line.xs.append(segs.ax[start])
        line.ys.append(segs.ay[start])
        line.xs.append(segs.bx[start])
        line.ys.append(segs.by[start])

        # Walk forward from the b end, then reverse and walk forward from
        # the original a end, so a chain found from its middle still comes
        # out as one polyline.
        for direction in range(2):
            if direction == 1:
                line.xs.reverse()
                line.ys.reverse()

            var edge = segs.eb[start] if direction == 0 else segs.ea[start]
            while True:
                var candidate = -1
                var f = first.get(edge, -1)
                if f >= 0 and not used[f]:
                    candidate = f
                else:
                    var sc = second.get(edge, -1)
                    if sc >= 0 and not used[sc]:
                        candidate = sc
                if candidate < 0:
                    break

                used[candidate] = True
                # Append whichever end of the next segment isn't the one
                # we arrived on.
                if segs.ea[candidate] == edge:
                    line.xs.append(segs.bx[candidate])
                    line.ys.append(segs.by[candidate])
                    edge = segs.eb[candidate]
                else:
                    line.xs.append(segs.ax[candidate])
                    line.ys.append(segs.ay[candidate])
                    edge = segs.ea[candidate]

        out.append(line^)

    return out^


def _append_above_region(
    mut path: Path,
    z: List[List[Float64]],
    rows: Int,
    cols: Int,
    level: Float64,
    x_axis: _GridAxis,
    y_axis: _GridAxis,
) raises -> Int:
    """Append every cell's "at or above `level`" area to `path`, one
    closed sub-path per cell, in pixel coordinates.

    This is the filled counterpart to `_contour_segments`: instead of the
    boundary between the two sides, it emits the side itself. Walking a
    cell's four corners in a fixed rotation and emitting each above-corner
    plus each edge crossing is exactly the polygon of the above-region
    for twelve of the sixteen cases -- the same clip Sutherland-Hodgman
    performs against a half-plane, which is what a single cell edge is.

    The saddles need their own branch again. With the center above, the
    two above-corners really are joined through the middle and the plain
    walk is right; with the center below they are two disjoint corner
    triangles, and the walk would wrongly fill the middle between them,
    so each triangle is emitted as its own sub-path.

    Every sub-path is wound the same way, which is what lets the caller
    fill them all in one `FillRule.NONZERO` pass: same-direction loops
    union rather than cancel, so cells that share an edge merge into one
    region with no seam between them. Filling cell by cell instead would
    leave a hairline at every shared edge where two anti-aliased edges
    meet.

    Args:
        path: Path to append sub-paths to.
        z: The grid, row-major.
        rows: `len(z)`.
        cols: `len(z[0])`.
        level: Values at or above this are inside.
        x_axis: Grid column to pixel x.
        y_axis: Grid row to pixel y.

    Returns:
        How many sub-paths were appended.
    """
    var count = 0
    for r in range(rows - 1):
        for c in range(cols - 1):
            var a = z[r][c]
            var b = z[r][c + 1]
            var cc = z[r + 1][c + 1]
            var d = z[r + 1][c]

            var mask = 0
            if a > level:
                mask += 1
            if b > level:
                mask += 2
            if cc > level:
                mask += 4
            if d > level:
                mask += 8
            if mask == 0:
                continue

            var xs = List[Float64]()
            var ys = List[Float64]()

            if mask == 5 or mask == 10:
                var center = (a + b + cc + d) / 4.0
                if not (center > level):
                    # Two disjoint corner triangles: emit each alone so
                    # the middle, which is below the level, stays empty.
                    if mask == 5:
                        count += _emit_corner_triangle(
                            path, x_axis, y_axis, r, c, 0, a, b, d, level
                        )
                        count += _emit_corner_triangle(
                            path, x_axis, y_axis, r, c, 2, cc, d, b, level
                        )
                    else:
                        count += _emit_corner_triangle(
                            path, x_axis, y_axis, r, c, 1, b, cc, a, level
                        )
                        count += _emit_corner_triangle(
                            path, x_axis, y_axis, r, c, 3, d, a, cc, level
                        )
                    continue

            # The plain walk: each above-corner, plus a crossing wherever
            # an edge changes side.
            var cx = List[Float64](capacity=4)
            var cy = List[Float64](capacity=4)
            var cv = List[Float64](capacity=4)
            cx.append(Float64(c))
            cy.append(Float64(r))
            cv.append(a)
            cx.append(Float64(c + 1))
            cy.append(Float64(r))
            cv.append(b)
            cx.append(Float64(c + 1))
            cy.append(Float64(r + 1))
            cv.append(cc)
            cx.append(Float64(c))
            cy.append(Float64(r + 1))
            cv.append(d)

            for i in range(4):
                var j = (i + 1) % 4
                if cv[i] > level:
                    xs.append(cx[i])
                    ys.append(cy[i])
                if (cv[i] > level) != (cv[j] > level):
                    var f = _crossing(cv[i], cv[j], level)
                    xs.append(cx[i] + (cx[j] - cx[i]) * f)
                    ys.append(cy[i] + (cy[j] - cy[i]) * f)

            if len(xs) >= 3:
                _append_subpath(path, xs, ys, x_axis, y_axis)
                count += 1
    return count


def _emit_corner_triangle(
    mut path: Path,
    x_axis: _GridAxis,
    y_axis: _GridAxis,
    r: Int,
    c: Int,
    corner: Int,
    v_here: Float64,
    v_next: Float64,
    v_prev: Float64,
    level: Float64,
) raises -> Int:
    """One saddle corner's triangle: the above-corner and the crossing on
    each of its two edges.

    `corner` is its index in the same rotation `_append_above_region`
    walks -- 0 at `(c, r)`, then clockwise in grid coordinates -- and
    `v_next`/`v_prev` are the corner values on the far end of the two
    edges meeting there.

    Args:
        path: Path to append to.
        x_axis: Grid column to pixel x.
        y_axis: Grid row to pixel y.
        r: Cell's row.
        c: Cell's column.
        corner: Which corner, 0-3.
        v_here: Value at that corner.
        v_next: Value at the next corner in rotation.
        v_prev: Value at the previous corner in rotation.
        level: The level being filled.

    Returns:
        1, so callers can total the sub-paths appended.
    """
    var corner_x = List[Float64](capacity=4)
    var corner_y = List[Float64](capacity=4)
    corner_x.append(Float64(c))
    corner_y.append(Float64(r))
    corner_x.append(Float64(c + 1))
    corner_y.append(Float64(r))
    corner_x.append(Float64(c + 1))
    corner_y.append(Float64(r + 1))
    corner_x.append(Float64(c))
    corner_y.append(Float64(r + 1))

    var nxt = (corner + 1) % 4
    var prv = (corner + 3) % 4
    var f_next = _crossing(v_here, v_next, level)
    var f_prev = _crossing(v_here, v_prev, level)

    var xs = List[Float64]()
    var ys = List[Float64]()
    xs.append(corner_x[corner])
    ys.append(corner_y[corner])
    xs.append(corner_x[corner] + (corner_x[nxt] - corner_x[corner]) * f_next)
    ys.append(corner_y[corner] + (corner_y[nxt] - corner_y[corner]) * f_next)
    xs.append(corner_x[corner] + (corner_x[prv] - corner_x[corner]) * f_prev)
    ys.append(corner_y[corner] + (corner_y[prv] - corner_y[corner]) * f_prev)
    _append_subpath(path, xs, ys, x_axis, y_axis)
    return 1


def _append_subpath(
    mut path: Path,
    xs: List[Float64],
    ys: List[Float64],
    x_axis: _GridAxis,
    y_axis: _GridAxis,
) raises:
    """Add one closed sub-path, projecting grid coordinates to pixels.

    Args:
        path: Path to append to.
        xs: Grid x coordinates.
        ys: Grid y coordinates.
        x_axis: Grid column to pixel x.
        y_axis: Grid row to pixel y.
    """
    path.move_to(x_axis.to_pixel(xs[0]), y_axis.to_pixel(ys[0]))
    for i in range(1, len(xs)):
        path.line_to(x_axis.to_pixel(xs[i]), y_axis.to_pixel(ys[i]))
    path.close()


def _contour_levels(plot: Plot) raises -> List[Float64]:
    """The levels a contour traces: the caller's own, or `_auto_levels`
    over `level_count` when none were given.

    Its own function because the standalone render needs them before the
    frame, to build the legend, and the draw pass needs the same list --
    two lists chosen independently would key a legend to levels the
    chart does not draw.

    Args:
        plot: The plot carrying `_contour`.

    Returns:
        The levels, in the order given or chosen.

    Raises:
        Error: Whatever `_auto_levels` raises.
    """
    if len(plot._contour.levels) > 0:
        return plot._contour.levels.copy()
    return _auto_levels(plot._contour.z, plot._contour.level_count)


def _level_span(levels: List[Float64]) -> Tuple[Float64, Float64]:
    """`levels`' lowest and highest, which the color ramp spans."""
    var lo = levels[0]
    var hi = levels[0]
    for v in levels:
        if v < lo:
            lo = v
        if v > hi:
            hi = v
    return (lo, hi)


def _draw_contour_layer[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    x_scale: LinearScale,
    y_scale: LinearScale,
    sc: _Scaled,
) raises:
    """Draw one `Mark.CONTOUR` plot's isolines into an already-laid-out
    continuous axis frame, the counterpart to `_draw_tricontour_layer`
    in tricontour.mojo.

    Shared by standalone and layered rendering so both stroke the same
    isolines rather than reimplementing them. Layering these over a
    `Mark.CONTOURF` of the same grid is the composition this exists for
    (#423), the grid counterpart of the tricontour/tricontourf pair.

    `sc` is the *layer's* own `_Scaled`, not the frame's: identical for
    a standalone render, but in a stack the frame belongs to `plots[0]`
    while each layer keeps its own line width.

    Args:
        target: The draw target.
        plot: The plot carrying `_contour`.
        x_scale: The frame's x-scale, already ranged onto the plot rect.
        y_scale: The y-scale this layer draws against.
        sc: This layer's scaled layout metrics.

    Raises:
        Error: Whatever `_validate_contour` raises.
    """
    var shape = _validate_contour(plot, "Plot.mark_contour()")
    var levels = _contour_levels(plot)
    if len(levels) == 0:
        return
    var span = _level_span(levels)
    var color_scale = _color_scale_for(
        plot._theme, plot._color_domain, span[0], span[1]
    )
    var x_axis = _GridAxis(plot._contour.x.copy(), x_scale)
    var y_axis = _GridAxis(plot._contour.y.copy(), y_scale)

    for li in range(len(levels)):
        var level = levels[li]
        var color = color_scale.color_at(level)
        var segs = _contour_segments(plot._contour.z, shape[0], shape[1], level)
        var lines = _chain_segments(segs)
        for k in range(len(lines)):
            ref line = lines[k]
            if len(line.xs) < 2:
                continue
            var path = Path()
            path.move_to(
                x_axis.to_pixel(line.xs[0]), y_axis.to_pixel(line.ys[0])
            )
            for i in range(1, len(line.xs)):
                path.line_to(
                    x_axis.to_pixel(line.xs[i]), y_axis.to_pixel(line.ys[i])
                )
            target.stroke_path_aa(path, color, width=sc.line_width)


def _draw_contourf_layer[
    T: DrawTarget
](mut target: T, plot: Plot, x_scale: LinearScale, y_scale: LinearScale) raises:
    """Draw one `Mark.CONTOURF` plot's filled bands into an
    already-laid-out continuous axis frame, the counterpart to
    `_draw_tricontourf_layer`.

    The band below the first level covers the grid's own footprint
    rather than the plot rect. Without coordinates those are the same
    rect, since the index domain is unpadded; with them the grid is
    inset by the usual 5%, and filling the rect would paint the lowest
    band out to the axes over ground the data does not cover.

    Args:
        target: The draw target.
        plot: The plot carrying `_contour`.
        x_scale: The frame's x-scale, already ranged onto the plot rect.
        y_scale: The y-scale this layer draws against.

    Raises:
        Error: Whatever `_validate_contour` raises.
    """
    var shape = _validate_contour(plot, "Plot.mark_contourf()")
    var rows = shape[0]
    var cols = shape[1]
    var levels = _contour_levels(plot)
    if len(levels) == 0:
        return
    var span = _level_span(levels)
    var color_scale = _color_scale_for(
        plot._theme, plot._color_domain, span[0], span[1]
    )
    var x_axis = _GridAxis(plot._contour.x.copy(), x_scale)
    var y_axis = _GridAxis(plot._contour.y.copy(), y_scale)

    var gx0 = x_axis.to_pixel(0.0)
    var gx1 = x_axis.to_pixel(Float64(cols - 1))
    var gy0 = y_axis.to_pixel(0.0)
    var gy1 = y_axis.to_pixel(Float64(rows - 1))
    target.fill_rect(
        round_to_int(min(gx0, gx1)),
        round_to_int(min(gy0, gy1)),
        round_to_int(abs(gx1 - gx0)),
        round_to_int(abs(gy1 - gy0)),
        color_scale.color_at(span[0]),
    )

    for li in range(len(levels)):
        var level = levels[li]
        var path = Path()
        var appended = _append_above_region(
            path, plot._contour.z, rows, cols, level, x_axis, y_axis
        )
        if appended > 0:
            target.fill_path_aa(
                path,
                color_scale.color_at(level),
                fill_rule=FillRule.NONZERO,
            )


def _render_contour[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.CONTOUR` plot: isolines over a regular grid.

    Layout is the shared continuous-axis frame (`_draw_continuous_axis_frame`),
    with both domains in grid-index units and no padding, so the grid
    spans the plot rect exactly edge to edge -- x over `[0, cols - 1]`
    and y over `[0, rows - 1]`. Row 0 is therefore the bottom of the
    plot, matching `contour(Z)`'s own default.

    Each level is traced by marching squares (`_contour_segments`),
    chained into whole isolines (`_chain_segments`), and stroked as one
    `Path` per line in that level's color from a `ColorScale` over the
    level range -- so a level's color says where it sits in the stack,
    the same reading `Mark.HEATMAP` gives a cell.

    Levels come from `encode_contour(levels=...)` when given, and
    otherwise from `mark_contour(levels=n)` evenly spaced strictly inside
    the data's range (`_auto_levels`). A flat grid produces no levels and
    draws an empty frame rather than raising: the axes still say what the
    data's extent was.
    """
    var shape = _validate_contour(plot, "Plot.mark_contour()")
    var rows = shape[0]
    var cols = shape[1]
    var axes = _contour_axes(plot, rows, cols)

    var levels = plot._contour.levels.copy() if len(
        plot._contour.levels
    ) > 0 else _auto_levels(plot._contour.z, plot._contour.level_count)

    var theme = plot._theme
    # Every level is a band or a line of its own, so the key is one
    # swatch per level rather than a gradient bar: a smooth ramp would
    # imply intermediate colors this mark never paints (#525). Built
    # before the frame because the column has to be reserved out of the
    # plot rect's width.
    var legend = _LegendLayout()
    var level_labels = List[String]()
    var level_colors = List[Color]()
    if theme.show_legend and len(levels) > 0:
        var llo = levels[0]
        var lhi = levels[0]
        for v in levels:
            if v < llo:
                llo = v
            if v > lhi:
                lhi = v
        # Through the resolver, so a `scale_color_domain()` override
        # shows in the key. A legend built from the data's own limits
        # would quietly contradict the bands beside it (#370).
        var legend_scale = _color_scale_for(theme, plot._color_domain, llo, lhi)
        var sc0 = _Scaled(theme)
        for v in _levels_descending(levels):
            level_labels.append(_format_tick(v, 1, theme.y_tick_format))
            level_colors.append(legend_scale.color_at(v))
        legend = _legend_layout(
            level_labels,
            sc0.legend_swatch_size,
            sc0,
            theme,
            ox1 - ox0,
            cache=cache,
        )

    var frame = _draw_continuous_axis_frame(
        target,
        axes[0].scale,
        axes[1].scale,
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_contour_layer(target, plot, frame.x_scale, frame.y_scale, frame.sc)

    _draw_legend_at(
        target,
        frame.text_requests,
        level_labels,
        level_colors,
        legend,
        frame.px0,
        frame.py0,
        frame.px1,
        frame.py1,
        theme,
    )

    return frame.result()


def _render_contourf[
    T: DrawTarget
](
    mut target: T,
    plot: Plot,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render a `Mark.CONTOURF` plot: filled bands between consecutive
    levels.

    Painted back to front.
    The plot rect is filled with the lowest band's color, then each
    level in ascending order fills its whole "at or above" region over
    the top, so what remains visible between two consecutive levels is
    the band between them. That is only correct for opaque bands, which
    is what makes it the cheap route: no band ever needs its own
    boundary traced, because the next one paints over the part that
    isn't its own.

    Each level's region is one `Path` of per-cell sub-paths filled in a
    single `FillRule.NONZERO` pass (`_append_above_region`). One pass,
    not one per cell, and nonzero specifically: same-direction loops
    union, so cells sharing an edge merge with no hairline seam where
    two anti-aliased edges would otherwise meet.

    Colors come from the same `ColorScale` `Mark.CONTOUR` uses, sampled
    at each band's own lower bound, so a band's color says where it sits
    in the stack. Levels and axes are `Mark.CONTOUR`'s exactly -- see
    `_render_contour`.
    """
    var shape = _validate_contour(plot, "Plot.mark_contourf()")
    var rows = shape[0]
    var cols = shape[1]
    var axes = _contour_axes(plot, rows, cols)

    var levels = plot._contour.levels.copy() if len(
        plot._contour.levels
    ) > 0 else _auto_levels(plot._contour.z, plot._contour.level_count)

    var theme = plot._theme
    # Every level is a band or a line of its own, so the key is one
    # swatch per level rather than a gradient bar: a smooth ramp would
    # imply intermediate colors this mark never paints (#525). Built
    # before the frame because the column has to be reserved out of the
    # plot rect's width.
    var legend = _LegendLayout()
    var level_labels = List[String]()
    var level_colors = List[Color]()
    if theme.show_legend and len(levels) > 0:
        var llo = levels[0]
        var lhi = levels[0]
        for v in levels:
            if v < llo:
                llo = v
            if v > lhi:
                lhi = v
        # Through the resolver, so a `scale_color_domain()` override
        # shows in the key. A legend built from the data's own limits
        # would quietly contradict the bands beside it (#370).
        var legend_scale = _color_scale_for(theme, plot._color_domain, llo, lhi)
        var sc0 = _Scaled(theme)
        for v in _levels_descending(levels):
            level_labels.append(_format_tick(v, 1, theme.y_tick_format))
            level_colors.append(legend_scale.color_at(v))
        legend = _legend_layout(
            level_labels,
            sc0.legend_swatch_size,
            sc0,
            theme,
            ox1 - ox0,
            cache=cache,
        )

    var frame = _draw_continuous_axis_frame(
        target,
        axes[0].scale,
        axes[1].scale,
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        cache=cache,
    )
    _draw_contourf_layer(target, plot, frame.x_scale, frame.y_scale)

    _draw_legend_at(
        target,
        frame.text_requests,
        level_labels,
        level_colors,
        legend,
        frame.px0,
        frame.py0,
        frame.px1,
        frame.py1,
        theme,
    )

    return frame.result()


def contour[
    dtype: DType
](
    z: List[List[Scalar[dtype]]],
    levels: List[Float64] = List[Float64](),
    level_count: Int = 8,
    x: List[Float64] = List[Float64](),
    y: List[Float64] = List[Float64](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A contour plot: isolines joining equal values across a regular
    grid, the standard way to read a scalar field (terrain height,
    temperature, a fitted surface) on flat paper.

    `Mark.CONTOUR`: marching squares per level over `z`, each isoline
    stroked in its level's color. See `Plot.encode_contour()` (plot.mojo)
    for the grid's shape.

    Args:
        z: The grid, row-major (`z[row][col]`), rectangular and at
            least 2x2. Rows are the y axis, columns the x axis, in
            grid-index units unless `x`/`y` give them coordinates.
        levels: The values to trace. Left empty (the default),
            `level_count` levels are spaced evenly inside `z`'s own
            range.
        level_count: How many levels to choose when `levels` is empty;
            defaults to `8`. Ignored when `levels` is given.
        x: One x coordinate per column of `z`, strictly increasing.
            Empty (the default) leaves the x axis in grid-index units.
        y: One y coordinate per row of `z`, strictly increasing. Empty
            (the default) leaves the y axis in grid-index units.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from std.math import exp

        from dataviz import contour
        from dataviz import save

        def main() raises:
            # Illustrative elevation model: two ridges separated by a saddle.
            var z = List[List[Float64]]()
            for r in range(48):
                var row = List[Float64]()
                for c in range(64):
                    var x = (Float64(c) - 31.5) / 10.0
                    var y = (Float64(r) - 23.5) / 10.0
                    var west = exp(-((x + 1.5) * (x + 1.5) + y * y))
                    var east = exp(
                        -((x - 1.4) * (x - 1.4) + (y - 0.4) * (y - 0.4))
                    )
                    var saddle = exp(-(x * x / 2.2 + (y + 0.2) * (y + 0.2)))
                    row.append(420.0 + 980.0 * west + 760.0 * east - 260.0 * saddle)
                z.append(row^)

            var c = contour(
                z,
                level_count=11,
                title="Illustrative Mountain Elevation Contours (m)",
                x_title="East-west grid cell",
                y_title="North-south grid cell",
            )
            save(c, "docs/src/examples/out_contour.svg")
        ```
    """
    var z_f = _materialize_nested_scalar_list(z)
    var plot = (
        Plot()
        .mark_contour(levels=level_count)
        .encode_contour(z=z_f, levels=levels, x=x, y=y)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def contourf[
    dtype: DType
](
    z: List[List[Scalar[dtype]]],
    levels: List[Float64] = List[Float64](),
    level_count: Int = 8,
    x: List[Float64] = List[Float64](),
    y: List[Float64] = List[Float64](),
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """A filled contour plot: the bands between consecutive levels of a
    scalar field, shaded rather than outlined -- `contour()`'s companion,
    and the better read when the field's shape matters more than its
    exact level lines.

    `Mark.CONTOURF`: the same marching-squares tracing `contour()` uses,
    filling each level's region instead of stroking its boundary. See
    `Plot.encode_contour()` (plot.mojo) for the grid's shape.

    Args:
        z: The grid, row-major (`z[row][col]`), rectangular and at
            least 2x2. Rows are the y axis, columns the x axis, in
            grid-index units unless `x`/`y` give them coordinates.
        levels: The band boundaries. Left empty (the default),
            `level_count` of them are spaced evenly inside `z`'s own
            range.
        level_count: How many levels to choose when `levels` is empty;
            defaults to `8`. Ignored when `levels` is given.
        x: One x coordinate per column of `z`, strictly increasing.
            Empty (the default) leaves the x axis in grid-index units.
        y: One y coordinate per row of `z`, strictly increasing. Empty
            (the default) leaves the y axis in grid-index units.
        theme: Full styling knobs beyond this function's own
            parameters (colors, margins, fonts, gridlines, ...) --
            see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.
        x_title: The x-axis caption.
        y_title: The y-axis caption.

    Returns:
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Example:
        ```mojo
        from std.math import exp

        from dataviz import contourf
        from dataviz import save

        def main() raises:
            # The same illustrative two-ridge elevation model as contour().
            var z = List[List[Float64]]()
            for r in range(48):
                var row = List[Float64]()
                for c in range(64):
                    var x = (Float64(c) - 31.5) / 10.0
                    var y = (Float64(r) - 23.5) / 10.0
                    var west = exp(-((x + 1.5) * (x + 1.5) + y * y))
                    var east = exp(
                        -((x - 1.4) * (x - 1.4) + (y - 0.4) * (y - 0.4))
                    )
                    var saddle = exp(-(x * x / 2.2 + (y + 0.2) * (y + 0.2)))
                    row.append(420.0 + 980.0 * west + 760.0 * east - 260.0 * saddle)
                z.append(row^)

            var c = contourf(
                z,
                level_count=11,
                title="Illustrative Mountain Elevation Bands (m)",
                x_title="East-west grid cell",
                y_title="North-south grid cell",
            )
            save(c, "docs/src/examples/out_contourf.svg")
        ```
    """
    var z_f = _materialize_nested_scalar_list(z)
    var plot = (
        Plot()
        .mark_contourf(levels=level_count)
        .encode_contour(z=z_f, levels=levels, x=x, y=y)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )
