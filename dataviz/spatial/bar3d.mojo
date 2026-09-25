"""`Mark.BAR3D` and `Mark.VOXELS`: solids built from axis-aligned boxes
(#345).

Step 5 of #345, the cuboid half. Both marks draw the same thing -- a
box's six faces, projected through `Frame3D`, depth sorted and handed to
`fill_mesh` -- and differ in where the boxes come from: one per (x, y)
sample, rising to its own height, or one per filled cell of a solid
occupancy grid.

**A box needs shading to read as a box.** Every face of a cuboid drawn
in one flat color projects to a hexagon with no internal structure, and
a row of them reads as a row of hexagons. The three face orientations
are therefore drawn at three lightnesses, brightest on top. It is a
fixed key, not a light source: the same orientation is the same
lightness in every box in the figure, so the shading never carries data
and two boxes can still be compared.

**Interior faces are dropped where they can be.** `voxels` emits a
face only when the neighbor across it is empty, which takes a filled
block from six faces per cell down to its surface area. It is a
neighbor test, not a visibility test, so it keeps one thing it could
drop: the six walls of a cavity sealed inside a solid all have an
empty neighbor and all get built, though nothing outside can see them.
Finding those needs reachability from outside, and six faces per
sealed pocket is not yet worth it. A `bar3d` bar has no neighbors to
test against at all, so it emits all six faces and lets the depth sort
cover the ones facing away.
"""

from dataviz.chart import Chart
from dataviz.marks import Bar3d, Voxels
from dataviz.core.chart_settings import _ChartSettings
from canvas.color import Color
from canvas.text.font_cache import FontCache
from canvas.geometry import FPoint
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame
from std.utils.numerics import isfinite

from dataviz.core.frame_input import _frame_floats
from dataviz.core.missing import Missing
from dataviz.basic.continuous import _lighten
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.camera3d import Camera3D
from dataviz.core.frame3d import Frame3D, _Extent3D, _fit_frame3d
from dataviz.core.theme import Theme
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.scale import _min_max, MinMax
from dataviz.core.validate import _require_non_empty
from dataviz.spatial.scatter3d import _draw_box, _tick_labels
from dataviz.spatial.surface3d import _depth_sorted_faces
from dataviz.core.mark import Mark, _require_mark


struct _Bars3D(Copyable, Movable):
    """Bars standing on the x-y plane, for `Mark.BAR3D`.

    `x`/`y` are each bar's center on the base plane and `z` its height,
    so a bar occupies `z` from 0 up (or down, for a negative height).
    `bar_width`/`bar_depth` are fractions of the closest spacing found
    between distinct coordinates, which keeps a lattice of bars from
    touching without the caller measuring their own grid.
    """

    var x: List[Float64]
    var y: List[Float64]
    var z: List[Float64]
    var bar_width: Float64
    var bar_depth: Float64
    var elev: Float64
    var azim: Float64

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.z = List[Float64]()
        self.bar_width = 0.8
        self.bar_depth = 0.8
        self.elev = 30.0
        self.azim = -60.0


struct _Voxels(Copyable, Movable):
    """A solid occupancy grid, for `Mark.VOXELS`.

    `filled[layer][row][col]` is `True` where a cell of the grid is
    solid: layers run up the z axis, rows along y and columns along x,
    the same order `encode_surface()` reads a height grid in with a
    third index in front.
    """

    var filled: List[List[List[Bool]]]
    var elev: Float64
    var azim: Float64

    def __init__(out self):
        self.filled = List[List[List[Bool]]]()
        self.elev = 30.0
        self.azim = -60.0


struct _Vertex(ImplicitlyCopyable, Movable):
    """One corner of a box, in data coordinates."""

    var x: Float64
    var y: Float64
    var z: Float64

    def __init__(out self, x: Float64, y: Float64, z: Float64):
        """Build the corner.

        Args:
            x: The x coordinate.
            y: The y coordinate.
            z: The z coordinate.
        """
        self.x = x
        self.y = y
        self.z = z


struct _Mesh(Movable):
    """The four parallel lists `fill_mesh` takes, plus a depth per face.

    Gathered into one struct because a mark building boxes appends to
    all four together, and four `mut` lists threaded through every call
    is four chances to append to three of them.
    """

    var points: List[FPoint]
    var faces: List[Int]
    var colors: List[Color]
    var depths: List[Float64]

    def __init__(out self):
        self.points = List[FPoint]()
        self.faces = List[Int]()
        self.colors = List[Color]()
        self.depths = List[Float64]()

    def add_quad(
        mut self,
        frame: Frame3D,
        a: _Vertex,
        b: _Vertex,
        c: _Vertex,
        d: _Vertex,
        color: Color,
    ) raises:
        """Add one flat quadrilateral as two triangles sharing a
        diagonal.

        Both triangles take the quad's own mean depth rather than their
        own. They are coplanar and meet along the diagonal, so any order
        between them is equally right, and one depth keeps the sort from
        separating them and letting a third face land in between.

        Args:
            frame: The fitted frame to project through.
            a: First corner, in order around the quad.
            b: Second corner.
            c: Third corner.
            d: Fourth corner.
            color: The fill color for both triangles.
        """
        var base = len(self.points)
        var total = 0.0
        for v in [a, b, c, d]:
            var at = frame.to_pixel(v.x, v.y, v.z)
            self.points.append(FPoint(at[0], at[1]))
            total += frame.depth(v.x, v.y, v.z)
        self.faces.append(base)
        self.faces.append(base + 1)
        self.faces.append(base + 2)
        self.faces.append(base)
        self.faces.append(base + 2)
        self.faces.append(base + 3)
        var mean = total / 4.0
        for _ in range(2):
            self.colors.append(color)
            self.depths.append(mean)

    def draw[T: DrawTarget](self, mut target: T) raises:
        """Sort the faces farthest first and draw them as one mesh.

        Args:
            target: The draw target.

        Raises:
            Error: Whatever `fill_mesh` raises.
        """
        var count = len(self.colors)
        var order = _depth_sorted_faces(self.depths, count)
        var sorted_faces = List[Int](capacity=count * 3)
        var sorted_colors = List[Color](capacity=count)
        for k in range(count):
            var f = order[k]
            sorted_faces.append(self.faces[f * 3])
            sorted_faces.append(self.faces[f * 3 + 1])
            sorted_faces.append(self.faces[f * 3 + 2])
            sorted_colors.append(self.colors[f])
        target.fill_mesh(self.points, sorted_faces, sorted_colors)


# How much of the mark color each face orientation keeps, the rest
# being the figure's own ground. A fixed key rather than a light
# source: the same orientation is the same shade in every box, so two
# boxes stay comparable and the shading carries no data.
#
# Blended toward the ground rather than toward black, because a dark
# theme's mark color multiplied down is indistinguishable from the
# ground it sits on. Toward the ground the face still recedes -- less
# contrast reads as farther -- and stays visible on any theme.
comptime _FACE_ALPHA_Z: UInt8 = 255
comptime _FACE_ALPHA_X: UInt8 = 200
comptime _FACE_ALPHA_Y: UInt8 = 160


def _face_color(base: Color, axis: Int, theme: Theme) -> Color:
    """`base` at the lightness this face orientation is drawn with."""
    if axis == 2:
        return _lighten(base, _FACE_ALPHA_Z, theme.background)
    if axis == 0:
        return _lighten(base, _FACE_ALPHA_X, theme.background)
    return _lighten(base, _FACE_ALPHA_Y, theme.background)


def _box_face(
    mut mesh: _Mesh,
    frame: Frame3D,
    lo: _Vertex,
    hi: _Vertex,
    axis: Int,
    upper: Bool,
    color: Color,
) raises:
    """Add the one face of the box `lo`-`hi` whose normal is `axis`
    (0 x, 1 y, 2 z), at the high end of that axis when `upper`.

    Winding is not chosen: `fill_mesh` draws a face the same either
    way, and the depth sort is what decides which face covers which.

    Args:
        mesh: The mesh being built.
        frame: The fitted frame to project through.
        lo: The corner with the smallest coordinate on every axis.
        hi: The opposite corner.
        axis: Which axis the face's normal runs along.
        upper: The face at the high end of `axis` rather than the low.
        color: The face's fill.
    """
    if axis == 0:
        var x = hi.x if upper else lo.x
        mesh.add_quad(
            frame,
            _Vertex(x, lo.y, lo.z),
            _Vertex(x, hi.y, lo.z),
            _Vertex(x, hi.y, hi.z),
            _Vertex(x, lo.y, hi.z),
            color,
        )
    elif axis == 1:
        var y = hi.y if upper else lo.y
        mesh.add_quad(
            frame,
            _Vertex(lo.x, y, lo.z),
            _Vertex(hi.x, y, lo.z),
            _Vertex(hi.x, y, hi.z),
            _Vertex(lo.x, y, hi.z),
            color,
        )
    else:
        var z = hi.z if upper else lo.z
        mesh.add_quad(
            frame,
            _Vertex(lo.x, lo.y, z),
            _Vertex(hi.x, lo.y, z),
            _Vertex(hi.x, hi.y, z),
            _Vertex(lo.x, hi.y, z),
            color,
        )


def _box(
    mut mesh: _Mesh,
    frame: Frame3D,
    lo: _Vertex,
    hi: _Vertex,
    base: Color,
    theme: Theme,
) raises:
    """Add all six faces of the box `lo`-`hi`.

    The three facing away are added too, and the depth sort covers
    them. Dropping them would need the face normals against the view
    direction; it saves drawing three quads that land under three
    others, which is not what a chart this size is spending its time
    on.

    Args:
        mesh: The mesh being built.
        frame: The fitted frame to project through.
        lo: The corner with the smallest coordinate on every axis.
        hi: The opposite corner.
        base: The mark color before the per-orientation shading.
        theme: Supplies the ground the shading blends toward.
    """
    for axis in range(3):
        var color = _face_color(base, axis, theme)
        _box_face(mesh, frame, lo, hi, axis, False, color)
        _box_face(mesh, frame, lo, hi, axis, True, color)


def _smallest_gap(values: List[Float64]) -> Float64:
    """The closest two distinct values in `values` come, or 1.0 when
    they are all the same.

    This is what a bar's footprint is a fraction of, so a lattice of
    bars leaves a gap at the closest pair rather than at the average
    pair -- one crowded row is what makes a figure unreadable, and the
    rest of it having room does not help.
    """
    # Sorted, the closest pair is adjacent, so one pass finds it. The
    # first version compared every pair -- quadratic in the bar count,
    # twice per render -- which a 100-by-100 lattice turned into a
    # hundred million comparisons for a number that takes one sort
    # (#647). Equal neighbors are skipped, not counted as a gap of zero.
    var sorted_values = values.copy()
    sort(sorted_values)
    var gap = 0.0
    for i in range(1, len(sorted_values)):
        var d = sorted_values[i] - sorted_values[i - 1]
        if d > 0.0 and (gap == 0.0 or d < gap):
            gap = d
    return gap if gap > 0.0 else 1.0


def _validate_bars3d(bars3d: _Bars3D) raises:
    """Three equal-length columns, at least one bar, and footprints
    that leave the bars separate.

    Raises:
        Error: The columns disagree in length, there are no bars, or a
            footprint fraction is outside (0, 1].
    """
    var n = len(bars3d.x)
    if len(bars3d.y) != n or len(bars3d.z) != n:
        raise Error(
            "Plot.encode_bars3d(): x, y and z must all have the same length"
            " (got "
            + String(n)
            + ", "
            + String(len(bars3d.y))
            + " and "
            + String(len(bars3d.z))
            + ")"
        )
    _require_non_empty(n, "Plot.encode_bars3d()")
    for pair in [
        (bars3d.bar_width, String("bar_width")),
        (bars3d.bar_depth, String("bar_depth")),
    ]:
        if not (pair[0] > 0.0) or pair[0] > 1.0:
            raise Error(
                "bar3d(): "
                + pair[1]
                + " is a fraction of the closest spacing between bars, so"
                " it must be above 0 and at most 1 (got "
                + String(pair[0])
                + "). At 1 the bars touch; above it they overlap and hide"
                " each other."
            )


def _bars3d_extent(
    bars3d: _Bars3D,
) raises -> Tuple[_Extent3D, Float64, Float64]:
    """The three data ranges, plus each bar's footprint in x and y.

    The z range always reaches 0, because a bar is read as a length
    from the base plane: a range starting at the shortest bar would
    draw every bar from a floor that is not zero and make the short
    ones look shorter than they are.
    """
    var half_w = _smallest_gap(bars3d.x) * bars3d.bar_width / 2.0
    var half_d = _smallest_gap(bars3d.y) * bars3d.bar_depth / 2.0
    var xs = _min_max(bars3d.x)
    var ys = _min_max(bars3d.y)
    var zs = _min_max(bars3d.z)
    return (
        _Extent3D(
            MinMax(xs.min - half_w, xs.max + half_w),
            MinMax(ys.min - half_d, ys.max + half_d),
            MinMax(
                zs.min if zs.min < 0.0 else 0.0, zs.max if zs.max > 0.0 else 0.0
            ),
        ),
        half_w,
        half_d,
    )


def _render_bar3d[
    T: DrawTarget
](
    mut target: T,
    bars3d: _Bars3D,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render `Mark.BAR3D`: one shaded box per sample, standing on the
    base plane.

    Every face of every bar goes into one mesh and one sort, not a
    sort per bar: two bars can interleave in depth -- a near short one
    in front of a far tall one -- and sorting them as wholes would draw
    one entire bar over the other.
    """
    _validate_bars3d(bars3d)
    var theme = settings.theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var measured = _bars3d_extent(bars3d)
    var frame = _fit_frame3d(
        Camera3D(bars3d.elev, bars3d.azim),
        measured[0],
        px0,
        py0,
        px1,
        py1,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var half_w = measured[1]
    var half_d = measured[2]
    var mesh = _Mesh()
    for i in range(len(bars3d.x)):
        var cx = bars3d.x[i]
        var cy = bars3d.y[i]
        var h = bars3d.z[i]
        _box(
            mesh,
            frame,
            _Vertex(cx - half_w, cy - half_d, h if h < 0.0 else 0.0),
            _Vertex(cx + half_w, cy + half_d, 0.0 if h < 0.0 else h),
            theme.mark_color,
            theme,
        )
    mesh.draw(target)
    return _RenderResult(text^, px0, py0, px1, py1)


def _voxel_shape(voxels: _Voxels) raises -> Tuple[Int, Int, Int]:
    """`(layers, rows, cols)`, raising unless the grid is a full box.

    A ragged occupancy grid has no reading at all: a row shorter than
    its neighbors is not "empty there", it is a grid that was never
    built, and filling in the gap would invent cells the caller never
    described.
    """
    var layers = len(voxels.filled)
    _require_non_empty(layers, "Plot.encode_voxels()")
    var rows = len(voxels.filled[0])
    _require_non_empty(rows, "Plot.encode_voxels()")
    var cols = len(voxels.filled[0][0])
    _require_non_empty(cols, "Plot.encode_voxels()")
    for l in range(layers):
        if len(voxels.filled[l]) != rows:
            raise Error(
                "Plot.encode_voxels(): every layer needs the same number of"
                " rows -- layer "
                + String(l)
                + " has "
                + String(len(voxels.filled[l]))
                + " against "
                + String(rows)
                + " in layer 0"
            )
        for r in range(rows):
            if len(voxels.filled[l][r]) != cols:
                raise Error(
                    "Plot.encode_voxels(): every row needs the same number"
                    " of columns -- layer "
                    + String(l)
                    + " row "
                    + String(r)
                    + " has "
                    + String(len(voxels.filled[l][r]))
                    + " against "
                    + String(cols)
                    + " in layer 0 row 0"
                )
    return (layers, rows, cols)


def _occupied(
    voxels: _Voxels, shape: Tuple[Int, Int, Int], l: Int, r: Int, c: Int
) -> Bool:
    """Whether cell `(l, r, c)` is filled; out of the grid is empty, so
    the solid's outer faces are all emitted."""
    if l < 0 or r < 0 or c < 0:
        return False
    if l >= shape[0] or r >= shape[1] or c >= shape[2]:
        return False
    return voxels.filled[l][r][c]


def _voxel_mesh(
    voxels: _Voxels, frame: Frame3D, shape: Tuple[Int, Int, Int], theme: Theme
) raises -> _Mesh:
    """The faces of the solid: every face of a filled cell whose
    neighbor across it is empty.

    A free function, and the count of what it returns is the only way
    the culling can be checked. Everything it drops is invisible by
    construction, so a render looks identical whether or not it
    happened, and a test that only reads the picture cannot tell a
    culled mesh from one six times the size.

    The test is on the neighbor, not on visibility, so the walls of a
    cavity sealed inside a solid are built: their neighbors are empty.
    See the module docstring.

    Args:
        voxels: The mark's `_Voxels` columns.
        frame: The fitted frame to project through.
        shape: `(layers, rows, cols)`, already validated.
        theme: Supplies the mark color and the ground it shades toward.

    Returns:
        The mesh, unsorted.

    Raises:
        Error: Whatever projecting a vertex raises.
    """
    var mesh = _Mesh()
    for l in range(shape[0]):
        for r in range(shape[1]):
            for c in range(shape[2]):
                if not voxels.filled[l][r][c]:
                    continue
                var lo = _Vertex(Float64(c), Float64(r), Float64(l))
                var hi = _Vertex(Float64(c + 1), Float64(r + 1), Float64(l + 1))
                # Six neighbors, one per face: (axis, upper, step).
                for face in [
                    (0, False, (0, 0, -1)),
                    (0, True, (0, 0, 1)),
                    (1, False, (0, -1, 0)),
                    (1, True, (0, 1, 0)),
                    (2, False, (-1, 0, 0)),
                    (2, True, (1, 0, 0)),
                ]:
                    var step = face[2]
                    if _occupied(
                        voxels, shape, l + step[0], r + step[1], c + step[2]
                    ):
                        continue
                    _box_face(
                        mesh,
                        frame,
                        lo,
                        hi,
                        face[0],
                        face[1],
                        _face_color(theme.mark_color, face[0], theme),
                    )
    return mesh^


def _render_voxels[
    T: DrawTarget
](
    mut target: T,
    voxels: _Voxels,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render `Mark.VOXELS`: a unit cube per filled cell, with the
    faces between two filled cells left out.

    That omission is exact rather than an approximation: a face with a
    filled cell on both sides is inside the solid, and nothing outside
    the solid can see it. On a filled block it takes the face count
    from six per cell to the surface area, which is the difference
    between a grid that draws and one that does not.
    """
    var shape = _voxel_shape(voxels)
    var layers = shape[0]
    var rows = shape[1]
    var cols = shape[2]
    var theme = settings.theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var frame = _fit_frame3d(
        Camera3D(voxels.elev, voxels.azim),
        _Extent3D(
            MinMax(0.0, Float64(cols)),
            MinMax(0.0, Float64(rows)),
            MinMax(0.0, Float64(layers)),
        ),
        px0,
        py0,
        px1,
        py1,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var mesh = _voxel_mesh(voxels, frame, shape, theme)
    mesh.draw(target)
    return _RenderResult(text^, px0, py0, px1, py1)


def bar3d(
    df: DataFrame,
    x: String,
    y: String,
    z: String,
    bar_width: Float64 = 0.8,
    bar_depth: Float64 = 0.8,
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Chart[Bar3d]:
    """`bar3d()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        y: The numeric column for this channel.
        z: The numeric column for this channel.
        bar_width: See the list overload.
        bar_depth: See the list overload.
        elev: See the list overload.
        azim: See the list overload.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.

    Returns:
        The finished chart -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var x_values = _frame_floats(df, x, "bar3d()", theme.missing)
    var y_values = _frame_floats(df, y, "bar3d()", theme.missing)
    var z_values = _frame_floats(df, z, "bar3d()", theme.missing)
    return bar3d(
        x=x_values,
        y=y_values,
        z=z_values,
        bar_width=bar_width,
        bar_depth=bar_depth,
        elev=elev,
        azim=azim,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
    )


def bar3d[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    z: List[Scalar[dtype]],
    bar_width: Float64 = 0.8,
    bar_depth: Float64 = 0.8,
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Chart[Bar3d]:
    """Bars standing on a plane: a value over two axes, drawn as a
    solid rising from each (x, y).

    `Mark.BAR3D`. Each bar's footprint is centered on its (x, y) and
    its height is z, measured from the base plane, so a bar's length is
    the value and the base is always zero.

    Read it knowing what the projection costs, which here is more than
    usual: a bar hides whatever stands behind it, and no arrangement of
    the view fixes that for every bar at once. A `heatmap` of the same
    values hides nothing and is read exactly; this shows the shape of
    the field at the price of the values in the back rows.

    Args:
        x: Each bar's center along x.
        y: Each bar's center along y, the same length.
        z: Each bar's height, the same length.
        bar_width: The bar's footprint along x, as a fraction of the
            closest spacing between two bars. At 1 the closest pair
            touches.
        bar_depth: The same along y.
        elev: Degrees to look down on the scene from, above the x-y
            plane.
        azim: Degrees to turn the scene through, about the z axis.
        theme: Full styling knobs beyond this function's own
            parameters -- see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.

    Returns:
        The finished chart -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.pdf/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: The three columns disagree in length, are empty, or a
            footprint fraction is outside (0, 1].

    Example:
        ```mojo
        from dataviz import bar3d, save

        def main() raises:
            # Illustrative counts over a 5-by-4 lattice of conditions.
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            for row in range(4):
                for col in range(5):
                    x.append(Float64(col))
                    y.append(Float64(row))
                    z.append(Float64((col * 3 + row * 5) % 7 + 1))

            var c = bar3d(
                x, y, z, title="Illustrative Counts Across Two Conditions"
            )
            save(c, "docs/src/examples/out_bar3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_bar3d(
            bar_width=bar_width, bar_depth=bar_depth, elev=elev, azim=azim
        )
        .encode_bars3d(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(z),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def voxels(
    filled: List[List[List[Bool]]],
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Chart[Voxels]:
    """A solid built out of unit cubes: which cells of a 3D grid are
    filled.

    `Mark.VOXELS`. One cube per filled cell, with the faces between two
    filled cells left out -- they are inside the solid and cannot be
    seen. What is drawn is the surface of the shape, so a hollow shell
    and the same shell packed solid look identical, which is the point:
    only the outside is ever visible.

    Use it for a shape that is genuinely three-dimensional and blocky --
    an occupancy grid, a segmentation, a lattice of on/off states.
    Cells buried inside the solid are invisible by construction, so a
    grid whose interesting structure is interior needs slices, not this.

    Args:
        filled: `filled[layer][row][col]`, `True` where the cell is
            solid. Layers run up z, rows along y, columns along x, and
            every layer and row must be the same size.
        elev: Degrees to look down on the scene from, above the x-y
            plane.
        azim: Degrees to turn the scene through, about the z axis.
        theme: Full styling knobs beyond this function's own
            parameters -- see `Theme`'s docstring.
        width: Pixel width of the returned `Plot` (`.size()`).
        height: Pixel height of the returned `Plot` (`.size()`).
        title: The chart's title, shown above the plot.
        subtitle: A secondary line shown under the title.

    Returns:
        The finished chart -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.pdf/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: The grid is empty, or a layer or row is the wrong size.

    Example:
        ```mojo
        from dataviz import save, voxels

        def main() raises:
            # Illustrative occupancy: a staircase climbing through the
            # grid, so every layer differs from the one below it.
            var grid = List[List[List[Bool]]]()
            for layer in range(6):
                var rows = List[List[Bool]]()
                for row in range(6):
                    var cols = List[Bool]()
                    for col in range(6):
                        cols.append(col >= layer and row >= layer)
                    rows.append(cols^)
                grid.append(rows^)

            var c = voxels(grid, title="Illustrative Occupancy Grid")
            save(c, "docs/src/examples/out_voxels.svg")
        ```
    """
    var plot = Plot().mark_voxels(elev=elev, azim=azim).encode_voxels(filled)
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def _voxel_index(value: Float64, axis: String) raises -> Int:
    """One nonnegative integer coordinate from a sparse voxel table."""
    if not isfinite(value) or value < 0.0 or value != Float64(Int(value)):
        raise Error(
            "voxels(): "
            + axis
            + " coordinates must be finite, nonnegative integers"
        )
    return Int(value)


def voxels(
    df: DataFrame,
    x: String,
    y: String,
    z: String,
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Chart[Voxels]:
    """Draw occupied voxels from a sparse DataFrame of coordinates.

    Each row marks one filled unit cube. `x`, `y`, and `z` must be
    zero-based integer coordinates; unlisted cells are empty. The
    highest coordinate on each axis sets the grid's extent.

    Args:
        df: The frame listing occupied cells.
        x: Numeric column of voxel column indices.
        y: Numeric column of voxel row indices.
        z: Numeric column of voxel layer indices.
        elev: See the grid overload.
        azim: See the grid overload.
        theme: See the grid overload.
        width: See the grid overload.
        height: See the grid overload.
        title: See the grid overload.
        subtitle: See the grid overload.

    Returns:
        The finished chart -- unrendered.

    Raises:
        Error: There are no occupied cells, a column is invalid, a
            coordinate is not a nonnegative integer, or a cell repeats.
    """
    var xs = _frame_floats(df, x, "voxels()", Missing.RAISE)
    var ys = _frame_floats(df, y, "voxels()", Missing.RAISE)
    var zs = _frame_floats(df, z, "voxels()", Missing.RAISE)
    if len(xs) == 0:
        raise Error("voxels(): needs at least one occupied cell")
    var max_x = 0
    var max_y = 0
    var max_z = 0
    for i in range(len(xs)):
        max_x = max(max_x, _voxel_index(xs[i], "x"))
        max_y = max(max_y, _voxel_index(ys[i], "y"))
        max_z = max(max_z, _voxel_index(zs[i], "z"))
    var filled = List[List[List[Bool]]](capacity=max_z + 1)
    for _ in range(max_z + 1):
        var layer = List[List[Bool]](capacity=max_y + 1)
        for _ in range(max_y + 1):
            var row = List[Bool](capacity=max_x + 1)
            for _ in range(max_x + 1):
                row.append(False)
            layer.append(row^)
        filled.append(layer^)
    for i in range(len(xs)):
        var col = Int(xs[i])
        var row = Int(ys[i])
        var layer = Int(zs[i])
        if filled[layer][row][col]:
            raise Error(
                "voxels(): duplicate occupied cell at ("
                + String(col)
                + ", "
                + String(row)
                + ", "
                + String(layer)
                + ")"
            )
        filled[layer][row][col] = True
    return voxels(
        filled=filled,
        elev=elev,
        azim=azim,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
    )


def _encode_bars3d(
    mark: Mark,
    mut bars3d: _Bars3D,
    x: List[Float64],
    y: List[Float64],
    z: List[Float64],
) raises:
    """`Plot.encode_bars3d()`'s body, which forwards here with
    every argument; see that method for the contract."""
    var _ok_encode_bars3d = List[Mark]()
    _ok_encode_bars3d.append(Mark.BAR3D)
    _require_mark(mark, "encode_bars3d", "mark_bar3d()", _ok_encode_bars3d^)
    bars3d.x = x.copy()
    bars3d.y = y.copy()
    bars3d.z = z.copy()


def _encode_voxels(
    mark: Mark, mut voxels: _Voxels, filled: List[List[List[Bool]]]
) raises:
    """`Plot.encode_voxels()`'s body, which forwards here with
    every argument; see that method for the contract."""
    var _ok_encode_voxels = List[Mark]()
    _ok_encode_voxels.append(Mark.VOXELS)
    _require_mark(mark, "encode_voxels", "mark_voxels()", _ok_encode_voxels^)
    voxels.filled = filled.copy()
