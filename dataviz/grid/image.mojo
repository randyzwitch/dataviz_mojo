"""Render 2D numeric arrays as colored cells.

`Mark.IMSHOW` uses a regular continuous grid; `Mark.PCOLORMESH` accepts
explicit cell edges. Unlike categorical `Mark.HEATMAP`, neither mark
draws category labels.
"""

from std.utils.numerics import isfinite

from std.math import log10

from canvas.buffer import Canvas
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.geometry import FPoint
from canvas.path import Path
from canvas.vector.draw_target import DrawTarget

from std.utils.numerics import inf, isnan

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_grid
from dataviz.core.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.core.color_scale import ColorScale, _color_scale_for
from dataviz.core.mark import Mark
from canvas.geometry import snap_to_pixel_edge
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _draw_continuous_axis_frame,
    _continuous_color_legend_layout,
    _draw_continuous_color_legend_at,
    _finished,
)
from dataviz.core.scale import LinearScale
from dataviz.core.theme import Theme
from dataviz.core.mark import _require_mark
from dataviz.binned.hist2d import _hist2d_counts


struct _ImageData(Copyable, Movable):
    """The array `Mark.IMSHOW`/`Mark.PCOLORMESH` display, plus the cell
    edges `PCOLORMESH` needs. See `encode_imshow()`/`encode_pcolormesh()`.
    Stored on `Plot._image`.

    `z` is row-major (`z[row][col]`), every row the same length. Rows are
    the y axis and columns the x axis for both marks; what differs is
    where the cell boundaries come from and which way the y-axis counts.

    `x_edges`/`y_edges` are empty for `IMSHOW`, which puts cell centers
    at the integers `0 .. cols - 1` and so needs no coordinates of its
    own. For `PCOLORMESH` they are the cell *boundaries*, so there is
    one more of each than there are columns/rows.
    """

    var z: List[List[Float64]]
    var x_edges: List[Float64]
    var y_edges: List[Float64]
    var x_corners: List[List[Float64]]
    """`Mark.PCOLORMESH` curvilinear form: one x per grid *vertex*,
    shaped `(rows + 1) x (cols + 1)`, so a cell is any quadrilateral
    rather than an axis-aligned rectangle (#424). Empty for the
    rectilinear form, which is what `x_edges`/`y_edges` describe.

    Both forms cannot be set at once: `encode_pcolormesh()` clears the
    other, so `len(x_corners) > 0` is what the renderer branches on."""

    var y_corners: List[List[Float64]]
    """The matching y per vertex, the same shape as `x_corners`."""
    var blank_zero: Bool
    """Leave a cell whose value is exactly 0 undrawn. Set by
    `encode_hist2d()`: an empty bin is "nothing here", not the bottom
    of the ramp."""
    var linear_auto_x: Bool
    """`hist2d()` chose the x bins itself, evenly in linear units. A log
    x axis over those would draw them wildly unequal, so the render
    raises and says to pass `log_x=True` instead (#718). Edges a caller
    gave `encode_hist2d()` are theirs and are drawn as given."""
    var linear_auto_y: Bool
    """The same for y."""

    def __init__(out self):
        self.z = List[List[Float64]]()
        self.x_edges = List[Float64]()
        self.x_corners = List[List[Float64]]()
        self.y_corners = List[List[Float64]]()
        self.y_edges = List[Float64]()
        self.blank_zero = False
        self.linear_auto_x = False
        self.linear_auto_y = False


def _image_grid_shape(
    z: List[List[Float64]], mark: Mark
) raises -> Tuple[Int, Int]:
    """`z`'s (rows, cols), raising unless it is a non-empty rectangular
    grid.

    One row or one column is fine, unlike `contour.mojo`'s `_grid_shape`,
    which needs 2x2 because marching squares walks the cells *between*
    samples. Here a sample is a cell, so a 1xN array is a perfectly good
    one-row image and rejecting it would be arbitrary.

    Args:
        z: The grid to measure.
        mark: The mark being drawn, so the message names the encode
            method the caller actually reached for.

    Returns:
        (rows, cols).

    Raises:
        Error: `z` is empty, has an empty row, or is ragged.
    """
    var method = (
        "Plot.encode_imshow()" if mark
        == Mark.IMSHOW else "Plot.encode_pcolormesh()"
    )
    var rows = len(z)
    if rows == 0:
        raise Error(
            method
            + ": there is no data to draw ("
            + mark.name()
            + " was given a grid with no rows)"
        )
    var cols = len(z[0])
    if cols == 0:
        raise Error(
            method
            + ": there is no data to draw ("
            + mark.name()
            + " was given a grid whose rows are empty)"
        )
    for r in range(1, rows):
        if len(z[r]) != cols:
            raise Error(
                method
                + ": z must be rectangular -- row 0 has "
                + String(cols)
                + " columns but row "
                + String(r)
                + " has "
                + String(len(z[r]))
            )
    return (rows, cols)


def _grid_min_max(z: List[List[Float64]]) raises -> Tuple[Float64, Float64]:
    """`z`'s smallest and largest values, the domain its colors span.

    A flat local loop rather than flattening into one `List[Float64]`
    and calling `_min_max`: the flattening would allocate a copy of the
    whole array, which for the array sizes this mark exists to handle is
    the single largest allocation in the render.

    Non-finite values are rejected for the reason `_min_max`'s own
    docstring gives at length -- a `NaN` poisons the domain into
    `(NaN, NaN)` because every comparison against it is false, and an
    `inf` survives the comparisons and produces a domain no color scale
    can project onto. The message names the cell, since an array big
    enough to want `imshow` is not one a reader can scan by eye.

    Args:
        z: The grid, already checked rectangular and non-empty.

    Returns:
        (min, max).

    Raises:
        Error: Any value is infinite, or every cell is missing.
    """
    var lo = inf[DType.float64]()
    var hi = -inf[DType.float64]()
    var seen = 0
    for r in range(len(z)):
        for c in range(len(z[r])):
            var v = z[r][c]
            # A missing cell is drawn as background and takes no part in
            # the color limits, so the ramp still spans the data that is
            # there (#367). An infinity is refused as before.
            if isnan(v):
                continue
            if not isfinite(v):
                raise Error(
                    "Plot.encode_imshow(): every value must be finite -- got "
                    + String(v)
                    + " at z["
                    + String(r)
                    + "]["
                    + String(c)
                    + "]"
                )
            if v < lo:
                lo = v
            if v > hi:
                hi = v
            seen += 1
    if seen == 0:
        raise Error(
            "Plot.encode_imshow(): every cell in this grid is missing, so"
            " it has no color limits to scale against"
        )
    return (lo, hi)


def _check_strictly_increasing(
    edges: List[Float64], count: Int, axis: String
) raises:
    """`Mark.PCOLORMESH`'s cell boundaries have to be `count + 1` values
    in strictly increasing order.

    Strictly, because two equal boundaries are a cell of zero width: it
    draws nothing, and its neighbors then sit next to each other with a
    value between them that never appears on the chart. Silently
    dropping a column of data is exactly the failure this package's
    encode checks exist to prevent.

    Increasing rather than merely monotonic: a descending coordinate
    array could be read as a request to flip the axis, but an axis that
    counts *down* because of the order values happened to arrive in is a
    surprising thing to infer from data. `Mark.IMSHOW` counts down
    deliberately and says so; here the caller can reverse the array and
    the values with it.

    Args:
        edges: The boundaries to check.
        count: How many cells they must bound, so `len(edges)` must be
            `count + 1`.
        axis: "x" or "y", for the message.

    Raises:
        Error: Wrong length, or not strictly increasing.
    """
    if len(edges) != count + 1:
        raise Error(
            "Plot.encode_pcolormesh(): "
            + axis
            + "_edges must have one more entry than z has "
            + ("columns" if axis == "x" else "rows")
            + " -- they bound the cells rather than sit at their centers (got "
            + String(len(edges))
            + " edges for "
            + String(count)
            + " cells, wanted "
            + String(count + 1)
            + ")"
        )
    for i in range(1, len(edges)):
        if not (edges[i] > edges[i - 1]):
            raise Error(
                "Plot.encode_pcolormesh(): "
                + axis
                + "_edges must be strictly increasing -- got "
                + String(edges[i - 1])
                + " then "
                + String(edges[i])
                + " at index "
                + String(i)
            )


def _edge_pixels(scale: LinearScale, values: List[Float64]) -> List[Float64]:
    """Every cell boundary's snapped pixel position, computed once.

    This one array is the whole seam argument (see the module
    docstring). `_fill_cells` reads `edges[i]` and `edges[i + 1]` for
    cell `i`, so the boundary between two cells is one number used
    twice, and no arithmetic can make the two sides disagree.

    A scale position is a pixel *index* -- `to_pixel(domain_min)` is
    `plot_x0`, the first column the plot rect covers -- and a column's
    geometry starts half a pixel before its index, so the `- 0.5` is
    what turns an index into the edge `fill_rect` wants. Without it the
    whole grid sits half a pixel right of and below the axes.

    Args:
        scale: The axis scale, with its pixel range already resolved
            by the frame.
        values: The boundaries in data units, in any order (the caller
            decides; `_fill_cells` takes min/max of each pair).

    Returns:
        One snapped pixel coordinate per value, in the same order.
    """
    var out = List[Float64](capacity=len(values))
    for i in range(len(values)):
        out.append(snap_to_pixel_edge(scale.to_pixel(values[i]) - 0.5))
    return out^


def _fill_cells[
    T: DrawTarget
](
    mut target: T,
    z: List[List[Float64]],
    x_edges: List[Float64],
    y_edges: List[Float64],
    color_scale: ColorScale,
    skip_zero: Bool = False,
) -> Int:
    """Paint the grid: one `fill_rect` per run of same-colored cells,
    shared by every mark that draws one (and, for a large `Mark.IMSHOW`
    grid on a vector target, replaced by `_draw_cells_as_image`).

    With `skip_zero`, a cell whose value is exactly 0 is not drawn at
    all and ends the run it would have joined, so the background shows
    through: `Mark.HIST2D`'s empty bin.

    `x_edges`/`y_edges` are snapped pixel boundaries from
    `_edge_pixels`, `len(z[0]) + 1` and `len(z) + 1` of them. Their
    order does not matter -- `min`/`max` of each pair gives the rect,
    which is what lets `Mark.IMSHOW`'s descending y-axis and
    `Mark.PCOLORMESH`'s ascending one share this code. Taking min/max
    keeps the shared-boundary property intact: both cells still read the
    same list element, whichever side of the pair it lands on.

    A cell whose two boundaries snapped together covers no pixels and is
    skipped rather than drawn as a zero-width rect. That is not a
    special case to be sorry about: it is how a grid finer than the plot
    rect resolves, the nearest-neighbor decimation an image gets when it
    is displayed smaller than its own resolution. The cells that survive
    still tile the rect exactly, because a skipped cell's two boundaries
    are the same number and its neighbors meet at it.

    Returns:
        How many rects were filled. `_render_image` discards it; it is
        the number the module docstring's cost measurements were taken
        from, and the only way to observe the skip-and-merge behavior
        without counting pixels.
    """
    var rows = len(z)
    var cols = len(z[0])
    var filled = 0
    for r in range(rows):
        var ya = y_edges[r]
        var yb = y_edges[r + 1]
        var top = min(ya, yb)
        var bottom = max(ya, yb)
        if bottom <= top:
            continue

        # One open run at a time: its left edge, its right edge so far,
        # and the color every cell in it resolved to.
        var run_open = False
        var run_left = 0.0
        var run_right = 0.0
        var run_color = Color(0, 0, 0)
        for c in range(cols):
            var xa = x_edges[c]
            var xb = x_edges[c + 1]
            var left = min(xa, xb)
            var right = max(xa, xb)
            if right <= left:
                continue
            # A missing cell draws nothing, exactly as a skipped zero
            # does, so the background shows through (#367).
            if isnan(z[r][c]):
                if run_open:
                    target.fill_rect(
                        run_left,
                        top,
                        run_right - run_left,
                        bottom - top,
                        run_color,
                    )
                    filled += 1
                    run_open = False
                continue
            if skip_zero and z[r][c] == 0.0:
                if run_open:
                    target.fill_rect(
                        run_left,
                        top,
                        run_right - run_left,
                        bottom - top,
                        run_color,
                    )
                    filled += 1
                    run_open = False
                continue
            var color = color_scale.color_at(z[r][c])
            if run_open and color == run_color and left == run_right:
                run_right = right
                continue
            if run_open:
                target.fill_rect(
                    run_left, top, run_right - run_left, bottom - top, run_color
                )
                filled += 1
            run_open = True
            run_left = left
            run_right = right
            run_color = color
        if run_open:
            target.fill_rect(
                run_left, top, run_right - run_left, bottom - top, run_color
            )
            filled += 1
    return filled


# On a vector target, a regular grid with more cells than this is drawn
# as one image rather than one rect per cell. See `_draw_cells_as_image`
# for the measurement behind the number.
comptime _IMAGE_MAX_RECT_CELLS = 1024


def _draw_cells_as_image[
    T: DrawTarget
](
    mut target: T,
    z: List[List[Float64]],
    x_edges: List[Float64],
    y_edges: List[Float64],
    color_scale: ColorScale,
) raises:
    """Paint a regular grid as one `draw_image`: an image holding each
    cell's color, stretched over the grid's box.

    This is `_fill_cells` for the large regular grid on a vector
    target, where one rect per cell is the wrong shape: a 512x512 field
    came out as megabytes of `<rect>` elements (#425), against tens of
    kilobytes as a PNG in one `<image>`. Measured on the SVG backend
    (benchmarks/METHODOLOGY.md), the image is the smaller file at every
    grid size, and render time is the same as the rect path up to tens
    of thousands of cells. Below `_IMAGE_MAX_RECT_CELLS` (a 32x32 grid)
    the grid still goes through `_fill_cells`, because each cell is
    then an element a reader can inspect and an editor can select,
    which a bitmap is not. Bytes alone would never choose rects; that
    is the one thing they buy.

    The raster backend never comes here. Its rect path snaps every cell
    edge in logical space (see `snap_to_pixel_edge`) so the edges stay
    hard under supersampling, while `draw_image` snaps in device space
    and lands interior edges between logical pixels; and building the
    device-sized block costs more than the rects do. `_render_image`
    makes the choice from its `vector_target` argument.

    Only `Mark.IMSHOW` comes here: its cells are uniform, which is what
    an image's cells are. `Mark.PCOLORMESH`'s edges are whatever the
    caller supplied, so it always goes through `_fill_cells`.

    The box is the outer boundaries from `_edge_pixels`, min/max of
    each pair as `_fill_cells` takes them, so the grid's outline lands
    exactly where the rect path would put it. A grid finer than the box
    is decimated to the box's size first, one cell per pixel, picking
    the cell each pixel's center falls in -- the same collapse the rect
    path gets from snapping, and what keeps a 1024x1024 array from
    encoding a megapixel PNG to fill a 430x350 rect. Rows are laid top
    to bottom; when `y_edges` runs the other way the rows are flipped so
    row 0 still sits at `y_edges[0]`. `IMSHOW` never does that, but the
    helper does not assume it.
    """
    var rows = len(z)
    var cols = len(z[0])
    var left = min(x_edges[0], x_edges[cols])
    var right = max(x_edges[0], x_edges[cols])
    var top = min(y_edges[0], y_edges[rows])
    var bottom = max(y_edges[0], y_edges[rows])
    if right <= left or bottom <= top:
        return
    var flip_rows = y_edges[0] > y_edges[rows]
    var flip_cols = x_edges[0] > x_edges[cols]

    # Snapped edges are whole pixels apart, so the box is an integer
    # size; never below one cell per axis.
    var img_w = min(cols, max(Int(right - left), 1))
    var img_h = min(rows, max(Int(bottom - top), 1))

    var pixels = List[UInt8](capacity=img_w * img_h * 4)
    for j in range(img_h):
        # floor((j + 0.5) * rows / img_h): the cell under the pixel's
        # center. When img_h == rows this is j.
        var r = ((2 * j + 1) * rows) // (2 * img_h)
        var ri = rows - 1 - r if flip_rows else r
        for i in range(img_w):
            var c = ((2 * i + 1) * cols) // (2 * img_w)
            var ci = cols - 1 - c if flip_cols else c
            # The bulk path writes every pixel, so a missing cell is
            # written transparent rather than skipped (#367).
            if isnan(z[ri][ci]):
                pixels.append(0)
                pixels.append(0)
                pixels.append(0)
                pixels.append(0)
                continue
            var color = color_scale.color_at(z[ri][ci])
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(color.a)
    var cells = Canvas(img_w, img_h, pixels^)
    target.draw_image(cells, left, top, right - left, bottom - top)


def _check_corner_grid(
    corners: List[List[Float64]], rows: Int, cols: Int, which: String
) raises:
    """A curvilinear corner array is `(rows + 1) x (cols + 1)` (#424).

    Checked here rather than at encode time, like every other shape rule
    in this package, because `z` and the corners arrive through separate
    calls and only the renderer sees both.

    Args:
        corners: The array to check.
        rows: `z`'s row count.
        cols: `z`'s column count.
        which: "x" or "y", for the message.

    Raises:
        Error: Wrong number of rows, or any row the wrong length.
    """
    if len(corners) != rows + 1:
        raise Error(
            "Plot.encode_pcolormesh(): "
            + which
            + "_corners needs one row per grid vertex, so rows + 1 = "
            + String(rows + 1)
            + " for a z with "
            + String(rows)
            + " rows -- got "
            + String(len(corners))
        )
    for i in range(len(corners)):
        if len(corners[i]) != cols + 1:
            raise Error(
                "Plot.encode_pcolormesh(): "
                + which
                + "_corners row "
                + String(i)
                + " has "
                + String(len(corners[i]))
                + " entries, but a z with "
                + String(cols)
                + " columns needs cols + 1 = "
                + String(cols + 1)
            )


def _corner_extent(
    corners: List[List[Float64]],
) raises -> Tuple[Float64, Float64]:
    """The min and max over every vertex.

    The rectilinear form takes its domain from the first and last edge,
    which a curvilinear mesh cannot do: a rotated grid's leftmost point
    can be in the middle of any row.

    Args:
        corners: The vertex array.

    Returns:
        `(min, max)`.

    Raises:
        Error: The array is empty.
    """
    if len(corners) == 0 or len(corners[0]) == 0:
        raise Error("Plot.encode_pcolormesh(): empty corner array")
    var lo = corners[0][0]
    var hi = corners[0][0]
    for r in range(len(corners)):
        for c in range(len(corners[r])):
            var v = corners[r][c]
            if v < lo:
                lo = v
            if v > hi:
                hi = v
    return (lo, hi)


def _fill_quad_cells[
    T: DrawTarget
](
    mut target: T,
    z: List[List[Float64]],
    x_corners: List[List[Float64]],
    y_corners: List[List[Float64]],
    x_scale: LinearScale,
    y_scale: LinearScale,
    color_scale: ColorScale,
    skip_zero: Bool,
) raises:
    """The curvilinear mesh, as two triangles per cell in one `fill_mesh`.

    Not one filled path per cell, which is what this was until #576.
    Two anti-aliased fills sharing an edge each blend their edge
    coverage against the background rather than against each other, so a
    mesh drawn a cell at a time carries a light line along every shared
    edge. It is invisible on a busy mesh and obvious on a smooth one, and
    nothing here asserted otherwise, so it had been there since the
    curvilinear path was written: measured at 1,815 interior pixels off
    the fill color, worst by 48 levels, on a 6 by 8 sheared mesh whose
    cells all carry the same value and which should therefore be one
    solid block of color.

    `fill_mesh` draws every face as one shape, so there are no interior
    edges to blend against anything. The same measurement gives zero.

    The rectilinear path is untouched. It merges runs of same-colored
    cells into one `fill_rect`, which has no anti-aliased edges to leak
    through in the first place.

    Faces go in row-major order, which `fill_mesh` preserves, so a
    self-overlapping mesh still paints later cells over earlier ones,
    which is why no validation rejects a non-convex cell.

    Args:
        target: The draw target.
        z: The values, row-major.
        x_corners: Vertex x, `(rows + 1) x (cols + 1)`.
        y_corners: Vertex y, the same shape.
        x_scale: Data to pixels, horizontally.
        y_scale: Data to pixels, vertically.
        color_scale: Value to color.
        skip_zero: Leave exactly-zero cells unpainted.

    Raises:
        Error: Whatever `fill_mesh()` raises for a malformed mesh.
    """
    var rows = len(z)
    if rows == 0:
        return
    var cols = len(z[0])
    if cols == 0:
        return

    # Every vertex once, so a shared corner is one point and the faces
    # that meet there index the same entry.
    var stride = cols + 1
    var points = List[FPoint](capacity=(rows + 1) * stride)
    for r in range(rows + 1):
        for c in range(stride):
            points.append(
                FPoint(
                    x_scale.to_pixel(x_corners[r][c]),
                    y_scale.to_pixel(y_corners[r][c]),
                )
            )

    var faces = List[Int](capacity=rows * cols * 6)
    var colors = List[Color](capacity=rows * cols * 2)
    for r in range(rows):
        for c in range(len(z[r])):
            var value = z[r][c]
            if isnan(value) or (skip_zero and value == 0.0):
                continue
            var top_left = r * stride + c
            var top_right = top_left + 1
            var bottom_left = (r + 1) * stride + c
            var bottom_right = bottom_left + 1
            var color = color_scale.color_at(value)
            faces.append(top_left)
            faces.append(top_right)
            faces.append(bottom_right)
            colors.append(color)
            faces.append(top_left)
            faces.append(bottom_right)
            faces.append(bottom_left)
            colors.append(color)

    if len(colors) == 0:
        return
    target.fill_mesh(points, faces, colors)


def _edge_scale(
    lo: Float64, hi: Float64, log: Bool, axis: String
) raises -> LinearScale:
    """An axis whose domain is exactly the outermost cell edges, linear or
    log.

    Not `_log_data_extent()`, which pads: a pcolormesh's outer edges are
    the extent of its data, not an estimate of it, so the cells meet the
    axis ends either way (#687). Every cell is then placed through
    `to_pixel()`, which takes the log itself, so a log axis needs nothing
    beyond this.

    Args:
        lo: The lowest edge or vertex.
        hi: The highest.
        log: Whether the axis is logarithmic.
        axis: "x" or "y", for the error message.

    Returns:
        The scale, with `is_log` set when asked for.

    Raises:
        Error: A log axis with an edge at or below zero.
    """
    if not log:
        return LinearScale(lo, hi, 0.0, 1.0)
    if lo <= 0.0:
        raise Error(
            "scale_"
            + axis
            + "_log(): every "
            + axis
            + " edge must be > 0 on a log axis -- the lowest is "
            + String(lo)
        )
    return LinearScale(log10(lo), log10(hi), 0.0, 1.0, is_log=True)


def _render_image[
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
    vector_target: Bool,
) raises -> _RenderResult:
    """Render `Mark.IMSHOW`, `Mark.PCOLORMESH` or `Mark.HIST2D`: the
    array as colored cells over a continuous frame, with a color legend
    beside it. `HIST2D` is `PCOLORMESH` with a grid `encode_hist2d()`
    counted from points, and its empty cells left undrawn.

    The two marks differ in exactly two places, both decided here and
    both about *coordinates*, never about drawing:

    - Where the cell boundaries are. `IMSHOW` has none of its own, so it
      puts cell centers on the integers and boundaries on the
      half-integers: the grid spans `[-0.5, cols - 0.5]`, keeping the
      axis in the same
      grid-index units `Mark.CONTOUR` uses for the same `z`.
      `PCOLORMESH` is handed its boundaries.
    - Which way y counts. `IMSHOW` counts *down* -- row 0 at the top --
      because a raster's first row is its top scanline; see
      `_draw_continuous_axis_frame`'s `y_descending`. `PCOLORMESH`
      counts up like every other continuous mark, because its rows are
      positions on a real axis rather than scanlines.

    Colors come from `_color_scale_for` over the array's own
    `[min, max]`, or over `Plot.scale_color_domain()`'s limits when one
    was set, so `Theme(color_ramp=colormaps.viridis())` reaches
    this mark with no code here -- which matters more for an image than
    for anything else this package draws, since a three-stop ramp
    invents contrast in a scalar field where the data has none.

    No interpolation: each cell is one flat color. Nearest-neighbor is
    the default because it shows the array's
    actual resolution instead of implying detail that was interpolated
    into it.

    Aspect: the grid fills the plot rect, which is what every other mark
    here does and what makes the axes bound the data. Pixels are not
    square unless the rect is -- see `imshow()`'s own docstring for what
    square pixels would cost and how to get them.

    `vector_target` says whether `target` keeps what it is given as
    elements rather than pixels (the SVG backend). There, a large
    regular grid is drawn as one image instead of one rect per cell;
    see `_draw_cells_as_image`.
    """
    var mark = plot._mark
    var shape = _image_grid_shape(plot._image.z, mark)
    var rows = shape[0]
    var cols = shape[1]

    var x_values = List[Float64](capacity=cols + 1)
    var y_values = List[Float64](capacity=rows + 1)
    if mark == Mark.PCOLORMESH or mark == Mark.HIST2D:
        if (
            len(plot._image.x_edges) == 0
            and len(plot._image.y_edges) == 0
            and len(plot._image.x_corners) == 0
        ):
            raise Error(
                "Plot.mark_pcolormesh(): no cell edges to draw the mesh over"
                " -- "
                + mark.name()
                + " needs Plot.encode_pcolormesh(x_edges, y_edges, z), not"
                " Plot.encode_imshow(z), which has no coordinates of its own"
            )
        if len(plot._image.x_corners) > 0:
            # Curvilinear (#424). The axis frame still needs a domain, and
            # a rotated mesh's extremes can be anywhere in the grid, so it
            # comes from every vertex rather than from a first and last
            # edge. `x_values`/`y_values` below carry only that domain;
            # the cells are drawn from the corner arrays directly.
            _check_corner_grid(plot._image.x_corners, rows, cols, "x")
            _check_corner_grid(plot._image.y_corners, rows, cols, "y")
            var xe = _corner_extent(plot._image.x_corners)
            var ye = _corner_extent(plot._image.y_corners)
            for c in range(cols + 1):
                x_values.append(
                    xe[0] + (xe[1] - xe[0]) * Float64(c) / Float64(cols)
                )
            for r in range(rows + 1):
                y_values.append(
                    ye[0] + (ye[1] - ye[0]) * Float64(r) / Float64(rows)
                )
        else:
            _check_strictly_increasing(plot._image.x_edges, cols, "x")
            _check_strictly_increasing(plot._image.y_edges, rows, "y")
            x_values = plot._image.x_edges.copy()
            y_values = plot._image.y_edges.copy()
    else:
        # The mirror of the check above, and the more dangerous
        # direction: a mark that quietly ignored coordinates the caller
        # supplied would draw a regular grid over irregular data and
        # look entirely plausible doing it. The other way round at least
        # has nothing to draw.
        if len(plot._image.x_edges) > 0 or len(plot._image.y_edges) > 0:
            raise Error(
                "Plot.mark_imshow(): "
                + mark.name()
                + " places cells by index and has no use for the cell edges"
                " Plot.encode_pcolormesh() supplied -- drawing them as a"
                " regular grid would misrepresent an irregular one. Use"
                " Plot.mark_pcolormesh() to honor the edges, or"
                " Plot.encode_imshow(z) to say the grid really is regular"
            )
        for c in range(cols + 1):
            x_values.append(Float64(c) - 0.5)
        for r in range(rows + 1):
            y_values.append(Float64(r) - 0.5)

    var extent = _grid_min_max(plot._image.z)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var color_scale = _color_scale_for(
        theme, plot._color_domain, extent[0], extent[1]
    )

    # Measured against the render's shared font cache before the plot
    # rect is finalized, the way every other legend-bearing mark sizes
    # its column (see `_dynamic_legend_width`).
    var legend = _continuous_color_legend_layout(
        color_scale, theme, sc, cache=cache
    )

    if mark == Mark.HIST2D:
        for axis in range(2):
            var is_x = axis == 0
            if (plot._x_log and plot._image.linear_auto_x) if is_x else (
                plot._y_log and plot._image.linear_auto_y
            ):
                var name = "x" if is_x else "y"
                raise Error(
                    "scale_"
                    + name
                    + "_log(): hist2d() binned "
                    + name
                    + " evenly in linear units, and on a log axis those"
                    " bins are wildly unequal widths. Pass log_"
                    + name
                    + "=True to hist2d() to bin in log space instead, or give"
                    " encode_hist2d() log_bin_edges()"
                )
    if plot._x_symlog or plot._y_symlog:
        raise Error(
            "Plot.scale_x_symlog()/scale_y_symlog(): "
            + mark.name()
            + " takes scale_x_log() and scale_y_log(), not symlog. A cell's"
            " edges are its data, and a symlog axis would redraw the cells"
            " that cross the linear threshold at a different width"
        )
    var frame = _draw_continuous_axis_frame(
        target,
        _edge_scale(x_values[0], x_values[cols], plot._x_log, "x"),
        _edge_scale(
            min(y_values[0], y_values[rows]),
            max(y_values[0], y_values[rows]),
            plot._y_log,
            "y",
        ),
        theme,
        legend,
        ox0,
        oy0,
        ox1,
        oy1,
        y_descending=mark == Mark.IMSHOW,
        cache=cache,
    )

    var x_px = _edge_pixels(frame.x_scale, x_values)
    var y_px = _edge_pixels(frame.y_scale, y_values)
    if (
        vector_target
        and mark == Mark.IMSHOW
        and rows * cols > _IMAGE_MAX_RECT_CELLS
    ):
        _draw_cells_as_image(target, plot._image.z, x_px, y_px, color_scale)
    elif len(plot._image.x_corners) > 0:
        _fill_quad_cells(
            target,
            plot._image.z,
            plot._image.x_corners,
            plot._image.y_corners,
            frame.x_scale,
            frame.y_scale,
            color_scale,
            skip_zero=plot._image.blank_zero,
        )
    else:
        _ = _fill_cells(
            target,
            plot._image.z,
            x_px,
            y_px,
            color_scale,
            skip_zero=plot._image.blank_zero,
        )

    _draw_continuous_color_legend_at(
        target,
        frame.text_requests,
        color_scale,
        legend,
        frame.px0,
        frame.py0,
        frame.px1,
        frame.py1,
        theme,
        cache=cache,
    )

    return frame.result()


def imshow(
    df: DataFrame,
    row: String,
    column: String,
    value: String,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """`imshow()` over a long-form `dataframe_mojo` `DataFrame` (#743):
    one row per cell, with `row` and `column` giving the cell's
    coordinates and `value` its height.

    A field is a grid, and a frame is a list of cells, so the rows are
    pivoted into one. Both axes come out ascending. A cell with no row
    is **missing**, not zero: it comes out blank and takes no part in
    the color limits (#367), which is what lets a table that was never
    rectangular be drawn as a field.

    Args:
        df: The frame to read.
        row: The numeric column giving each cell's row coordinate.
        column: The numeric column giving each cell's column coordinate.
        value: The numeric column holding each cell.
        theme: Full styling knobs beyond this function's own parameters.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A line under the title.
        x_title: The x-axis caption; defaults to `column`.
        y_title: The y-axis caption; defaults to `row`.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, is not numeric, the columns
            differ in length, or a (row, column) pair repeats.
    """
    var grid = _frame_grid(df, row, column, value, "imshow()", theme.missing)
    return imshow(
        grid[2],
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else column,
        y_title=y_title if y_title.byte_length() > 0 else row,
    )


def imshow[
    dtype: DType
](
    z: List[List[Scalar[dtype]]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Display a 2D array as an image: one colored cell per element, on
    continuous axes in row/column index units.

    `Mark.IMSHOW`. This is the chart for
    anything that *is* an array rather than a table -- a matrix, a
    raster, a spectrogram, a correlation surface, a decoded PNG.
    `Mark.HEATMAP` looks like the same thing and is not: it takes
    categorical x and y labels with one value per pair, so a 512x512
    array would need 512 category labels.

    **Row 0 is at the top**, and the y-axis counts downward to match.
    That is the order a raster's scanlines arrive in, and the order a
    matrix is written in --
    `imshow(read_png(...))` comes out the right way up. It is the
    opposite of `contour()`, which puts row 0 at the bottom because its
    grid is a sampled surface rather than an image.

    **The image fills the plot rect**, so its pixels are only square
    when the rect happens to be. The alternative, square pixels that
    leave the axes partly empty, is not the default. Filling is the right
    default here because every other mark in this package fills its
    rect, and because the common case -- a matrix, a correlation
    surface, a field -- has no physical aspect to preserve. For a photo
    or anything else where a stretch would misrepresent the data, size
    the chart so the plot rect matches the array: the rect is `width`
    minus the left margin, the right margin and the legend column, and
    `height` minus the top and bottom margins, all of which `Theme`
    exposes.

    Cells are flat colors, no interpolation: what you see is the array's
    own resolution, not detail invented between samples.

    Color comes from the theme's scale over the array's own range.
    `Theme(color_ramp=colormaps.viridis())` is worth reaching for here
    more than anywhere else in this package -- a scalar field shown
    through a three-stop ramp gets contrast where the data has none,
    which is the specific problem perceptually uniform maps were built
    to fix.

    Args:
        z: The array, row-major (`z[row][col]`), rectangular and
            non-empty. Rows are the y axis and columns the x axis.
            Every value must be finite.
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

        from dataviz import imshow
        from dataviz.core.colormaps import viridis
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Illustrative thermal-camera readings across a server rack.
            # Two hot components sit on top of a gentle exhaust gradient.
            var z = List[List[Float64]]()
            for r in range(48):
                var row = List[Float64]()
                for c in range(64):
                    var dx1 = (Float64(c) - 19.0) / 7.0
                    var dy1 = (Float64(r) - 17.0) / 6.0
                    var dx2 = (Float64(c) - 46.0) / 9.0
                    var dy2 = (Float64(r) - 31.0) / 8.0
                    var temperature = 24.0 + Float64(r) * 0.08
                    temperature += 31.0 * exp(-(dx1 * dx1 + dy1 * dy1))
                    temperature += 22.0 * exp(-(dx2 * dx2 + dy2 * dy2))
                    row.append(temperature)
                z.append(row^)

            var chart = imshow(
                z,
                theme=Theme(color_ramp=viridis()),
                title="Illustrative Server-Rack Thermal Scan (°C)",
                x_title="Sensor column",
                y_title="Sensor row",
            )
            save(chart, "docs/src/examples/out_imshow.svg")
        ```
    """
    var z_f = _materialize_nested_scalar_list(z)
    var plot = Plot().mark_imshow().encode_imshow(z=z_f)
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def pcolormesh(
    x_edges: List[Float64],
    y_edges: List[Float64],
    z: List[List[Float64]],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Display a 2D array over cell boundaries you supply: `imshow()`
    for a grid whose rows and columns are not evenly spaced.

    `Mark.PCOLORMESH`: an image over 1D coordinate arrays. The array is
    the same as `imshow()`'s; what changes is that
    each cell's extent comes from `x_edges`/`y_edges` rather than from
    its index, so a log-spaced frequency axis, unequal time bins, or a
    grid that was never regular in the first place lands where it
    belongs instead of being stretched into evenly spaced columns.

    The edges *bound* the cells, so there is one more of each than the
    array has columns and rows -- `len(x_edges) == cols + 1`,
    `len(y_edges) == rows + 1`. Both must
    be strictly increasing.

    **Row 0 is at the bottom**, unlike `imshow()`. `y_edges[0]` is a
    position on a real axis, not a scanline, so the axis counts upward
    the way every other continuous mark's does.

    Cells are flat colors and the color scale is the theme's, exactly as
    in `imshow()` -- see that docstring for why `Theme(color_ramp=...)`
    matters here.

    Only 1D edges are supported: a fully curvilinear mesh would need a
    quad per cell rather than a rect, which is
    a different drawing path.

    Args:
        x_edges: Column boundaries, `cols + 1` of them, strictly
            increasing.
        y_edges: Row boundaries, `rows + 1` of them, strictly
            increasing.
        z: The array, row-major (`z[row][col]`), rectangular and
            non-empty. Every value must be finite.
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
        from std.math import exp, sin

        from dataviz import pcolormesh
        from dataviz.core.colormaps import magma
        from dataviz import save
        from dataviz import Theme

        def main() raises:
            # Weather balloons are farther apart downrange and report at
            # uneven altitude bands, so each cell keeps its measured extent.
            var x_edges: List[Float64] = [
                0, 3, 7, 12, 18, 25, 33, 42, 52, 63, 75, 88, 102,
            ]
            var y_edges: List[Float64] = [
                0.0, 0.4, 0.9, 1.5, 2.3, 3.3, 4.6, 6.2, 8.0,
            ]

            var z = List[List[Float64]]()
            for r in range(len(y_edges) - 1):
                var row = List[Float64]()
                var altitude = (y_edges[r] + y_edges[r + 1]) / 2.0
                for c in range(len(x_edges) - 1):
                    var distance = (x_edges[c] + x_edges[c + 1]) / 2.0
                    var plume_x = (distance - 55.0) / 18.0
                    var plume_y = (altitude - 2.2) / 0.9
                    var temperature = 19.0 - 6.2 * altitude
                    temperature += 2.0 * sin(distance / 17.0)
                    temperature += 8.0 * exp(
                        -(plume_x * plume_x + plume_y * plume_y)
                    )
                    row.append(temperature)
                z.append(row^)

            var chart = pcolormesh(
                x_edges,
                y_edges,
                z,
                theme=Theme(color_ramp=magma()),
                title="Illustrative Atmospheric Temperature Cross-Section (°C)",
                x_title="Distance downrange (km)",
                y_title="Altitude (km)",
            )
            save(chart, "docs/src/examples/out_pcolormesh.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_pcolormesh()
        .encode_pcolormesh(x_edges=x_edges, y_edges=y_edges, z=z)
    )
    return _finished(
        plot^, theme, width, height, title, x_title, y_title, subtitle=subtitle
    )


def pcolormesh(
    df: DataFrame,
    row: String,
    column: String,
    value: String,
    x_edges: List[Float64],
    y_edges: List[Float64],
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 420,
    title: String = "",
    subtitle: String = "",
    x_title: String = "",
    y_title: String = "",
) raises -> Plot:
    """Draw an irregular cell mesh from long-form DataFrame values.

    `row` and `column` name numeric cell-center coordinates. The frame
    is pivoted into a grid in ascending coordinate order; absent cells
    stay blank. Explicit `x_edges` and `y_edges` give the boundaries of
    those columns and rows, so uneven cell widths are preserved.

    Args:
        df: One row per measured cell.
        row: Numeric column of cell-center y coordinates.
        column: Numeric column of cell-center x coordinates.
        value: Numeric column of cell values.
        x_edges: Boundaries of the sorted x coordinates, one extra.
        y_edges: Boundaries of the sorted y coordinates, one extra.
        theme: See the grid overload.
        width: See the grid overload.
        height: See the grid overload.
        title: See the grid overload.
        subtitle: See the grid overload.
        x_title: See the grid overload.
        y_title: See the grid overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is invalid, a cell repeats, the edge
            lengths do not fit the grid, or a center falls outside its
            corresponding cell.
    """
    var grid = _frame_grid(
        df, row, column, value, "pcolormesh()", theme.missing
    )
    if len(x_edges) != len(grid[1]) + 1 or len(y_edges) != len(grid[0]) + 1:
        raise Error(
            "pcolormesh(): x_edges and y_edges must have one more value"
            " than the frame's distinct column and row coordinates"
        )
    for c in range(len(grid[1])):
        if grid[1][c] <= x_edges[c] or grid[1][c] >= x_edges[c + 1]:
            raise Error(
                "pcolormesh(): column coordinate "
                + String(grid[1][c])
                + " is outside its cell boundaries"
            )
    for r in range(len(grid[0])):
        if grid[0][r] <= y_edges[r] or grid[0][r] >= y_edges[r + 1]:
            raise Error(
                "pcolormesh(): row coordinate "
                + String(grid[0][r])
                + " is outside its cell boundaries"
            )
    return pcolormesh(
        x_edges=x_edges,
        y_edges=y_edges,
        z=grid[2],
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
        x_title=x_title if x_title.byte_length() > 0 else column,
        y_title=y_title if y_title.byte_length() > 0 else row,
    )


def _encode_pcolormesh(
    mut plot: Plot,
    x_edges: List[Float64],
    y_edges: List[Float64],
    z: List[List[Float64]],
) raises:
    """`Plot.encode_pcolormesh()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark,
        "encode_pcolormesh",
        "mark_pcolormesh()",
        Mark.PCOLORMESH,
    )
    plot._image.z = z.copy()
    plot._image.x_edges = x_edges.copy()
    plot._image.y_edges = y_edges.copy()
    # The two forms are exclusive; see the curvilinear overload.
    plot._image.x_corners = List[List[Float64]]()
    plot._image.y_corners = List[List[Float64]]()


def _encode_pcolormesh(
    mut plot: Plot,
    x_corners: List[List[Float64]],
    y_corners: List[List[Float64]],
    z: List[List[Float64]],
) raises:
    """`Plot.encode_pcolormesh()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(
        plot._mark,
        "encode_pcolormesh",
        "mark_pcolormesh()",
        Mark.PCOLORMESH,
    )
    plot._image.z = z.copy()
    plot._image.x_corners = x_corners.copy()
    plot._image.y_corners = y_corners.copy()
    # Exclusive with the rectilinear form: a plot carrying both would
    # leave the renderer to guess which the caller meant.
    plot._image.x_edges = List[Float64]()
    plot._image.y_edges = List[Float64]()


def _encode_hist2d(
    mut plot: Plot,
    x: List[Float64],
    y: List[Float64],
    x_edges: List[Float64],
    y_edges: List[Float64],
) raises:
    """`Plot.encode_hist2d()`'s body, which forwards here with
    every argument; see that method for the contract."""
    _require_mark(plot._mark, "encode_hist2d", "mark_hist2d()", Mark.HIST2D)
    plot._image.z = _hist2d_counts(x, y, x_edges, y_edges)
    plot._image.x_edges = x_edges.copy()
    plot._image.y_edges = y_edges.copy()
    plot._image.blank_zero = True
