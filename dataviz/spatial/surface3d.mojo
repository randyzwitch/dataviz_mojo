"""`Mark.SURFACE3D`, `Mark.WIRE3D` and `Mark.TRISURF3D`: a height field
drawn as shaded faces, as a wireframe, or over scattered points (#345).

Step 4 of #345. All three project through `Frame3D` like the point
marks, and differ in what they build from the projected vertices: two
triangles per grid cell, the grid's edges as lines, or the triangles a
Delaunay triangulation gives over scattered `(x, y)`.

**The faces go to `fill_mesh`, not to one fill each.** Two
antialiased fills sharing an edge each blend their partial coverage
against the *background* rather than against each other, so a surface
drawn a quad at a time carries a pale grid along every shared edge --
measured upstream at 52 bad pixels along a 60-pixel edge. Only a call
that sees all the faces can fix it, which is what `fill_mesh` is for.

**Depth sorting is a centroid sort, and it has a known-wrong case.**
Faces are handed over farthest first, and `fill_mesh` composites in the
order given, so a nearer face covers a farther one. That is right for
the surfaces a height field produces, where faces meet edge to edge and
never interpenetrate. It is wrong for geometry that crosses itself or
for long thin faces seen edge-on: there is no single correct order, and
the fix is splitting faces at their crossings or a depth buffer,
neither of which exists here.
"""

from canvas.color import Color
from canvas.geometry import FPoint
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import (
    _materialize_nested_scalar_list,
    _materialize_scalar_list,
)
from dataviz.core.color_scale import ColorScale, _color_scale_for
from dataviz.core.delaunay import Triangulation, delaunay
from dataviz.core.camera3d import Camera3D
from dataviz.core.frame3d import Frame3D, _Extent3D, _fit_frame3d
from dataviz.core.scale import MinMax
from dataviz.core.validate import _check_grid_coordinates
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _finished,
    _min_max,
    _require_non_empty,
)
from dataviz.spatial.scatter3d import (
    _draw_box,
    _frame_for,
    _tick_labels,
    _validate_xyz,
)
from dataviz.core.theme import Theme


struct _Surface(Copyable, Movable):
    """A height field: `z` row-major over a lattice, plus the view.

    `x`/`y` are the lattice's coordinates, one per column and per row.
    Left empty they are the indices, which is `surface3d(z)`'s default
    and the same convention `encode_contour()` uses.
    """

    var z: List[List[Float64]]
    var x: List[Float64]
    var y: List[Float64]
    var elev: Float64
    var azim: Float64

    def __init__(out self):
        self.z = List[List[Float64]]()
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.elev = 30.0
        self.azim = -60.0


def _surface_shape(plot: Plot) raises -> Tuple[Int, Int]:
    """`(rows, cols)`, raising unless the grid is rectangular and at
    least 2x2 -- a surface is built from cells, and a grid with one row
    or column has none.
    """
    var rows = len(plot._surface.z)
    if rows < 2:
        raise Error(
            "Plot.encode_surface(): z needs at least 2 rows to have any"
            " cells (got "
            + String(rows)
            + ")"
        )
    var cols = len(plot._surface.z[0])
    if cols < 2:
        raise Error(
            "Plot.encode_surface(): z needs at least 2 columns to have any"
            " cells (got "
            + String(cols)
            + ")"
        )
    for r in range(1, rows):
        if len(plot._surface.z[r]) != cols:
            raise Error(
                "Plot.encode_surface(): z must be rectangular -- row "
                + String(r)
                + " has "
                + String(len(plot._surface.z[r]))
                + " values against "
                + String(cols)
                + " in row 0"
            )
    # The same coordinate rules a contour's grid follows, from the same
    # checker: a field should draw either way without its axes changing
    # meaning, and one column silently ignored for being the wrong
    # length is the failure this catches.
    _check_grid_coordinates(
        plot._surface.x, cols, "x", "column", "Plot.encode_surface()"
    )
    _check_grid_coordinates(
        plot._surface.y, rows, "y", "row", "Plot.encode_surface()"
    )
    return (rows, cols)


def _surface_extent(plot: Plot, rows: Int, cols: Int) raises -> _Extent3D:
    """The three data ranges: the lattice's own coordinates when it has
    them, its indices otherwise, and the grid's height range for z."""
    var flat = List[Float64]()
    for row in plot._surface.z:
        for v in row:
            flat.append(v)
    var x_span = _min_max(plot._surface.x) if len(
        plot._surface.x
    ) > 0 else MinMax(0.0, Float64(cols - 1))
    var y_span = _min_max(plot._surface.y) if len(
        plot._surface.y
    ) > 0 else MinMax(0.0, Float64(rows - 1))
    return _Extent3D(x_span, y_span, _min_max(flat))


def _lattice_at(plot: Plot, axis: Int, index: Int) -> Float64:
    """The data coordinate of lattice `index` along `axis` (0 x, 1 y):
    the caller's own column when it gave one, else the index.

    Only emptiness is tested, not the length: `_surface_shape()` has
    already rejected a column that does not match the grid, so a
    non-empty one is known to reach `index`.
    """
    if axis == 0:
        if len(plot._surface.x) > 0:
            return plot._surface.x[index]
        return Float64(index)
    if len(plot._surface.y) > 0:
        return plot._surface.y[index]
    return Float64(index)


def _depth_sorted_faces(depths: List[Float64], face_count: Int) -> List[Int]:
    """Face indices farthest first, so handing them to `fill_mesh` in
    this order composites as the painter's algorithm expects.

    An insertion sort, as `_depth_order` uses for points and for the
    same reason: the face counts a readable surface has are small, and
    the key is a `Float64` already computed.
    """
    var order = List[Int](capacity=face_count)
    for i in range(face_count):
        order.append(i)
    for i in range(1, face_count):
        var key = order[i]
        var kd = depths[key]
        var j = i - 1
        while j >= 0 and depths[order[j]] < kd:
            order[j + 1] = order[j]
            j -= 1
        order[j + 1] = key
    return order^


def _render_surface3d[
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
    """Render `Mark.SURFACE3D`: two triangles per lattice cell, colored
    by height and handed to `fill_mesh` farthest first.

    Colored by the face's own mean height rather than per vertex: a
    flat face reads as one sample of the field, which is what a lattice
    cell is. `fill_mesh_shaded` would interpolate the corners, which
    looks smoother and implies the surface was measured between the
    samples.
    """
    var shape = _surface_shape(plot)
    var rows = shape[0]
    var cols = shape[1]
    var theme = plot._theme
    var sc = _Scaled(theme)
    var extent = _surface_extent(plot, rows, cols)
    var frame = _fit_frame3d(
        Camera3D(plot._surface.elev, plot._surface.azim),
        extent,
        ox0 + sc.margin_left,
        oy0 + sc.margin_top,
        ox1 - sc.margin_right,
        oy1 - sc.margin_bottom,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    # One vertex per lattice point, shared by the faces that meet there:
    # `fill_mesh` needs shared indices to know two faces touch, which is
    # the whole basis of its seamless fill.
    var points = List[FPoint]()
    for r in range(rows):
        for c in range(cols):
            var at = frame.to_pixel(
                _lattice_at(plot, 0, c),
                _lattice_at(plot, 1, r),
                plot._surface.z[r][c],
            )
            points.append(FPoint(at[0], at[1]))

    var color_scale = _color_scale_for(
        theme, plot._color_domain, extent.z.min, extent.z.max
    )
    var faces = List[Int]()
    var colors = List[Color]()
    var depths = List[Float64]()
    for r in range(rows - 1):
        for c in range(cols - 1):
            var i00 = r * cols + c
            var i01 = r * cols + c + 1
            var i10 = (r + 1) * cols + c
            var i11 = (r + 1) * cols + c + 1
            # The quad's two triangles, each carrying its own mean
            # height and its own depth.
            for half in range(2):
                var a = i00
                var b = i01 if half == 0 else i11
                var cc = i11 if half == 0 else i10
                faces.append(a)
                faces.append(b)
                faces.append(cc)
                var za = plot._surface.z[a // cols][a % cols]
                var zb = plot._surface.z[b // cols][b % cols]
                var zc = plot._surface.z[cc // cols][cc % cols]
                colors.append(color_scale.color_at((za + zb + zc) / 3.0))
                depths.append(
                    (
                        frame.depth(
                            _lattice_at(plot, 0, a % cols),
                            _lattice_at(plot, 1, a // cols),
                            za,
                        )
                        + frame.depth(
                            _lattice_at(plot, 0, b % cols),
                            _lattice_at(plot, 1, b // cols),
                            zb,
                        )
                        + frame.depth(
                            _lattice_at(plot, 0, cc % cols),
                            _lattice_at(plot, 1, cc // cols),
                            zc,
                        )
                    )
                    / 3.0
                )

    var order = _depth_sorted_faces(depths, len(depths))
    var sorted_faces = List[Int](capacity=len(faces))
    var sorted_colors = List[Color](capacity=len(colors))
    for k in range(len(order)):
        var f = order[k]
        sorted_faces.append(faces[f * 3])
        sorted_faces.append(faces[f * 3 + 1])
        sorted_faces.append(faces[f * 3 + 2])
        sorted_colors.append(colors[f])
    target.fill_mesh(points, sorted_faces, sorted_colors)

    return _RenderResult(
        text^,
        ox0 + sc.margin_left,
        oy0 + sc.margin_top,
        ox1 - sc.margin_right,
        oy1 - sc.margin_bottom,
    )


def _render_wire3d[
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
    """Render `Mark.WIRE3D`: the lattice's own lines, no fill.

    Not depth sorted, and it does not need to be: nothing is opaque, so
    no line can hide another and there is no order that would look
    different. That is the whole appeal of a wireframe over a surface --
    the far side stays visible -- and the cost is that a dense lattice
    reads as a thicket.
    """
    var shape = _surface_shape(plot)
    var rows = shape[0]
    var cols = shape[1]
    var theme = plot._theme
    var sc = _Scaled(theme)
    var frame = _fit_frame3d(
        Camera3D(plot._surface.elev, plot._surface.azim),
        _surface_extent(plot, rows, cols),
        ox0 + sc.margin_left,
        oy0 + sc.margin_top,
        ox1 - sc.margin_right,
        oy1 - sc.margin_bottom,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    # One path per lattice line rather than per segment: a polyline is
    # one stroke, so the joins between its segments are mitered instead
    # of each segment capping against the next.
    for r in range(rows):
        var path = Path()
        for c in range(cols):
            var at = frame.to_pixel(
                _lattice_at(plot, 0, c),
                _lattice_at(plot, 1, r),
                plot._surface.z[r][c],
            )
            if c == 0:
                path.move_to(at[0], at[1])
            else:
                path.line_to(at[0], at[1])
        target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)
    for c in range(cols):
        var path = Path()
        for r in range(rows):
            var at = frame.to_pixel(
                _lattice_at(plot, 0, c),
                _lattice_at(plot, 1, r),
                plot._surface.z[r][c],
            )
            if r == 0:
                path.move_to(at[0], at[1])
            else:
                path.line_to(at[0], at[1])
        target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)

    return _RenderResult(
        text^,
        ox0 + sc.margin_left,
        oy0 + sc.margin_top,
        ox1 - sc.margin_right,
        oy1 - sc.margin_bottom,
    )


def _render_trisurf3d[
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
    """Render `Mark.TRISURF3D`: a Delaunay triangulation of the
    scattered `(x, y)`, lifted to z and filled.

    The triangulation is of the *projection onto the x-y plane*, not of
    the surface in space, which is what makes it a height field: every
    `(x, y)` has one z. Points that shadow each other -- a cave, an
    overhang -- cannot be drawn by this mark at all, and the
    triangulation silently picks one of them.
    """
    _validate_xyz(plot)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var frame = _frame_for(plot, px0, py0, px1, py1)
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var tri = delaunay(plot._xyz.x, plot._xyz.y)
    var n = len(plot._xyz.x)
    var points = List[FPoint](capacity=n)
    for i in range(n):
        var at = frame.to_pixel(plot._xyz.x[i], plot._xyz.y[i], plot._xyz.z[i])
        points.append(FPoint(at[0], at[1]))

    var z_span = _min_max(plot._xyz.z)
    var color_scale = _color_scale_for(
        theme, plot._color_domain, z_span.min, z_span.max
    )
    var face_count = len(tri.triangles) // 3
    var colors = List[Color](capacity=face_count)
    var depths = List[Float64](capacity=face_count)
    for f in range(face_count):
        var a = tri.triangles[f * 3]
        var b = tri.triangles[f * 3 + 1]
        var c = tri.triangles[f * 3 + 2]
        colors.append(
            color_scale.color_at(
                (plot._xyz.z[a] + plot._xyz.z[b] + plot._xyz.z[c]) / 3.0
            )
        )
        depths.append(
            (
                frame.depth(plot._xyz.x[a], plot._xyz.y[a], plot._xyz.z[a])
                + frame.depth(plot._xyz.x[b], plot._xyz.y[b], plot._xyz.z[b])
                + frame.depth(plot._xyz.x[c], plot._xyz.y[c], plot._xyz.z[c])
            )
            / 3.0
        )

    var order = _depth_sorted_faces(depths, face_count)
    var faces = List[Int](capacity=face_count * 3)
    var sorted_colors = List[Color](capacity=face_count)
    for k in range(face_count):
        var f = order[k]
        faces.append(tri.triangles[f * 3])
        faces.append(tri.triangles[f * 3 + 1])
        faces.append(tri.triangles[f * 3 + 2])
        sorted_colors.append(colors[f])
    target.fill_mesh(points, faces, sorted_colors)

    return _RenderResult(text^, px0, py0, px1, py1)


def surface3d[
    dtype: DType
](
    z: List[List[Scalar[dtype]]],
    x: List[Float64] = List[Float64](),
    y: List[Float64] = List[Float64](),
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Plot:
    """A 3D surface: a height field over a regular grid, drawn as filled
    faces shaded by height.

    `Mark.SURFACE3D`. Each lattice cell becomes two triangles, colored
    by its own mean height, and the faces are composited farthest first.

    Height is already on the z axis with its own ticks, so no color
    bar is drawn: the shading is there to make the shape legible, not
    to be read off.

    A surface shows the shape of a field -- ridges, saddles, where it
    falls away -- better than any flat encoding. It reads values worse
    than all of them: the perspective hides part of the field behind the
    rest, and no two heights can be compared by eye across the picture.
    Where the question is "what is the value here", `heatmap` or
    `contour` answers it; this answers "what does it look like".

    Args:
        z: The grid, row-major (`z[row][col]`), rectangular and at
            least 2x2. Rows run along y, columns along x.
        x: One x coordinate per column of `z`. Empty (the default)
            leaves the x axis in grid-index units.
        y: One y coordinate per row of `z`. Empty (the default) leaves
            the y axis in grid-index units.
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
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.pdf/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: The grid is ragged, or smaller than 2x2.

    Example:
        ```mojo
        from std.math import exp

        from dataviz import save, surface3d

        def main() raises:
            # Illustrative field: a peak beside a shallower basin.
            var z = List[List[Float64]]()
            for r in range(32):
                var row = List[Float64]()
                for c in range(32):
                    var u = (Float64(c) - 16.0) / 6.0
                    var v = (Float64(r) - 16.0) / 6.0
                    row.append(
                        exp(-(u * u + v * v))
                        - 0.6 * exp(-((u - 2.2) * (u - 2.2) + v * v))
                    )
                z.append(row^)

            var c = surface3d(
                z, title="Illustrative Field With One Peak and One Basin"
            )
            save(c, "docs/src/examples/out_surface3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_surface3d(elev=elev, azim=azim)
        .encode_surface(_materialize_nested_scalar_list(z), x.copy(), y.copy())
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def wire3d[
    dtype: DType
](
    z: List[List[Scalar[dtype]]],
    x: List[Float64] = List[Float64](),
    y: List[Float64] = List[Float64](),
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Plot:
    """A 3D wireframe: the same height field as `surface3d`, drawn as
    the lattice's own lines with nothing filled in.

    `Mark.WIRE3D`. Nothing is opaque, so the far side of the surface
    stays visible through the near side -- which is the point, and also
    the cost: on a dense lattice the lines pile up into a thicket that
    shows no shape at all. Coarsen the grid before reaching for this
    over `surface3d`.

    Args:
        z: The grid, row-major (`z[row][col]`), rectangular and at
            least 2x2. Rows run along y, columns along x.
        x: One x coordinate per column of `z`. Empty (the default)
            leaves the x axis in grid-index units.
        y: One y coordinate per row of `z`. Empty (the default) leaves
            the y axis in grid-index units.
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
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.pdf/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: The grid is ragged, or smaller than 2x2.

    Example:
        ```mojo
        from std.math import sqrt, sin

        from dataviz import save, wire3d

        def main() raises:
            # Illustrative ripple, on a grid coarse enough to see through.
            var z = List[List[Float64]]()
            for r in range(18):
                var row = List[Float64]()
                for c in range(18):
                    var u = (Float64(c) - 9.0) / 3.0
                    var v = (Float64(r) - 9.0) / 3.0
                    var d = sqrt(u * u + v * v)
                    row.append(sin(d * 1.6) / (1.0 + d))
                z.append(row^)

            var c = wire3d(z, title="Illustrative Ripple Drawn as a Lattice")
            save(c, "docs/src/examples/out_wire3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_wire3d(elev=elev, azim=azim)
        .encode_surface(_materialize_nested_scalar_list(z), x.copy(), y.copy())
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def trisurf3d[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    z: List[Scalar[dtype]],
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Plot:
    """A 3D surface over scattered points: the `(x, y)` are
    triangulated, lifted to their z, and filled.

    `Mark.TRISURF3D`. Use it when the samples do not sit on a grid --
    survey points, sensor sites, anywhere the measurements landed where
    they landed. On gridded data `surface3d` is the same picture without
    a triangulation to compute.

    The triangulation covers the convex hull of the points, so a
    concave sampled region gets filled across the gap. It is a height
    field besides: one z per `(x, y)`, so no overhang can be drawn.

    Args:
        x: The x column.
        y: The y column, the same length.
        z: The height at each point, the same length.
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
        The finished `Plot` -- unrendered. Call `save(plot, path)` to write it (any of .svg/.png/.pdf/.bmp), or `render(plot)`/`render_svg(plot)` for the explicit two-step.

    Raises:
        Error: The three columns disagree in length, or are empty.

    Example:
        ```mojo
        from std.math import cos, sin, sqrt

        from dataviz import save, trisurf3d

        def main() raises:
            # Illustrative survey: samples off the grid, spread over a
            # disc by the golden angle so the density is even.
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            for i in range(400):
                var t = Float64(i) * 2.399963
                var r = 0.16 * sqrt(Float64(i))
                var px = r * cos(t)
                var py = r * sin(t)
                x.append(px)
                y.append(py)
                z.append(0.8 * sin(px * 1.1) * cos(py * 1.1))

            var c = trisurf3d(
                x, y, z, title="Illustrative Survey Sampled Off the Grid"
            )
            save(c, "docs/src/examples/out_trisurf3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_trisurf3d(elev=elev, azim=azim)
        .encode_xyz(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(z),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )
