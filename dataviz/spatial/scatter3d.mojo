"""`Mark.SCATTER3D` and `Mark.PLOT3D`: points and polylines in three
dimensions, projected through a `Camera3D` onto a `Frame3D` (#345).

The third of #345's five steps, and the first that draws anything. Both
marks are the same pipeline -- normalise, project, sort, draw -- and
differ only in the glyph at the end, which is why they share a module
and a data struct.

**Depth sorting is the whole of the correctness.** canvas is a
painter's-algorithm rasteriser with no z-buffer, so a nearer point hides
a farther one only by being drawn second. For points that is a sort by
projected depth and it is exact. For a polyline it is not: a line is
drawn in data order, so a segment that passes behind another is drawn
over it if it comes later in the series. The fix is splitting
segments at their crossings, which needs geometry canvas does not
have, so the behavior is stated here rather than left to be
discovered.
"""

from dataviz.core.chart_settings import _ChartSettings
from canvas.color import Color
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataframe import DataFrame

from dataviz.core.frame_input import _frame_floats
from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.camera3d import Camera3D
from dataviz.core.frame3d import (
    Frame3D,
    _Extent3D,
    _axis_ends,
    _fit_frame3d,
    _outward,
    _point_on_axis,
    _tick_edge,
)
from dataviz.plot import Plot, _finished
from dataviz.core.render_result import _RenderResult
from dataviz.core.text import _Scaled, _TextRequest
from dataviz.core.scale import _min_max, LinearScale
from dataviz.core.validate import _require_non_empty
from dataviz.core.tooltip_labels import _xyz_tooltip_label
from dataviz.core.theme import Theme
from canvas.text.render import TextAlign
from dataviz.core.mark import Mark, _require_mark


struct _Xyz(Copyable, Movable):
    """Three equal-length columns, for `Mark.SCATTER3D`/`PLOT3D`. See
    `encode_xyz()`. Stored on `Plot._xyz`.

    `elev`/`azim` ride along here rather than on `Theme`: a view angle
    is a property of this chart's data, the way a domain override is,
    not a styling choice a theme should carry across every figure.
    """

    var x: List[Float64]
    var y: List[Float64]
    var z: List[Float64]
    var elev: Float64
    var azim: Float64

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.z = List[Float64]()
        self.elev = 30.0
        self.azim = -60.0


def _validate_xyz(xyz: _Xyz) raises:
    """Three columns of the same length, at least one point.

    Raises:
        Error: The columns disagree in length, or there are no points.
    """
    var n = len(xyz.x)
    if len(xyz.y) != n or len(xyz.z) != n:
        raise Error(
            "Plot.encode_xyz(): x, y and z must all have the same length (got "
            + String(n)
            + ", "
            + String(len(xyz.y))
            + " and "
            + String(len(xyz.z))
            + ")"
        )
    _require_non_empty(n, "Plot.encode_xyz()")


def _frame_for(
    xyz: _Xyz, px0: Int, py0: Int, px1: Int, py1: Int
) raises -> Frame3D:
    """The fitted frame for this plot's data and view."""
    return _fit_frame3d(
        Camera3D(xyz.elev, xyz.azim),
        _Extent3D(
            _min_max(xyz.x),
            _min_max(xyz.y),
            _min_max(xyz.z),
        ),
        px0,
        py0,
        px1,
        py1,
    )


def _depth_order(xyz: _Xyz, frame: Frame3D) -> List[Int]:
    """Point indices from farthest to nearest, so drawing in this order
    leaves the nearest on top.

    An insertion sort: the point counts a 3D scatter is readable at are
    small, and the comparison is on a `Float64` already computed, so the
    quadratic never shows. `_draw_hexbin_layer`'s counting sort exists
    because its keys are small integers and its counts are large;
    neither is true here.
    """
    var n = len(xyz.x)
    var depths = List[Float64](capacity=n)
    for i in range(n):
        depths.append(frame.depth(xyz.x[i], xyz.y[i], xyz.z[i]))
    var order = List[Int](capacity=n)
    for i in range(n):
        order.append(i)
    for i in range(1, n):
        var key = order[i]
        var kd = depths[key]
        var j = i - 1
        while j >= 0 and depths[order[j]] < kd:
            order[j + 1] = order[j]
            j -= 1
        order[j + 1] = key
    return order^


def _draw_box[
    T: DrawTarget
](mut target: T, frame: Frame3D, theme: Theme, sc: _Scaled) raises:
    """Draw the twelve edges of the viewing cube.

    The box is the axes furniture: without it a projected point cloud
    has no frame of reference and the view angle is unreadable. Drawn
    in the gridline color and before the data, so it sits behind
    everything -- a wireframe in front of the points would read as part
    of the chart rather than as its frame.

    All twelve edges rather than the three nearest axes, because a
    partial box makes the cube ambiguous: the same three lines fit two
    different orientations, and a reader cannot tell which face is
    front.
    """
    var e = frame.extent
    var xs: List[Float64] = [e.x.min, e.x.max]
    var ys: List[Float64] = [e.y.min, e.y.max]
    var zs: List[Float64] = [e.z.min, e.z.max]
    for axis in range(3):
        for a in range(2):
            for b in range(2):
                var path = Path()
                var p0: Tuple[Float64, Float64]
                var p1: Tuple[Float64, Float64]
                if axis == 0:
                    p0 = frame.to_pixel(xs[0], ys[a], zs[b])
                    p1 = frame.to_pixel(xs[1], ys[a], zs[b])
                elif axis == 1:
                    p0 = frame.to_pixel(xs[a], ys[0], zs[b])
                    p1 = frame.to_pixel(xs[a], ys[1], zs[b])
                else:
                    p0 = frame.to_pixel(xs[a], ys[b], zs[0])
                    p1 = frame.to_pixel(xs[a], ys[b], zs[1])
                path.move_to(p0[0], p0[1])
                path.line_to(p1[0], p1[1])
                target.stroke_path_aa(
                    path, theme.gridline_color, width=sc.line_width
                )


def _tick_labels(
    frame: Frame3D, theme: Theme, sc: _Scaled, mut out: List[_TextRequest]
) raises:
    """Label the three axes, each on the edge `_tick_edge` chose.

    Values come from the same `LinearScale.ticks()` every 2D axis uses,
    so a 3D axis is labelled at the same "nice" numbers and formatted by
    the same `Theme.y_tick_format` -- a reader should not have to learn
    a second convention because the chart gained an axis.

    Alignment follows which side of the box the label landed on: a
    label to the left of the cube ends at its anchor, one to the right
    starts at it. Anchoring every label the same way would push half of
    them back over the box they are labelling.
    """
    var gap = Float64(sc.tick_length + sc.label_gap)
    for axis in range(3):
        var ends = _axis_ends(frame, axis)
        var scale = LinearScale(ends[0], ends[1], 0.0, 1.0)
        var ticks = scale.ticks()
        var labels = ticks.labels(theme.y_tick_format)
        var edge = _tick_edge(frame, axis)
        for i in range(len(ticks.values)):
            var at = _point_on_axis(
                frame, axis, ticks.values[i], edge[0], edge[1]
            )
            var placed = _outward(frame, at, gap)
            # Left of the cube's centre reads right-to-left, so the text
            # ends at the anchor; right of it, the text starts there.
            var centre_x = frame.to_pixel(
                (frame.extent.x.min + frame.extent.x.max) / 2.0,
                (frame.extent.y.min + frame.extent.y.max) / 2.0,
                (frame.extent.z.min + frame.extent.z.max) / 2.0,
            )[0]
            var align = (
                TextAlign.RIGHT if placed[0] < centre_x else TextAlign.LEFT
            )
            out.append(
                _TextRequest(
                    Int(placed[0]),
                    Int(placed[1] + sc.font_size * 0.35),
                    labels[i],
                    theme.text_color,
                    sc.font_size,
                    align,
                    theme.font_family,
                )
            )


def _render_scatter3d[
    T: DrawTarget
](
    mut target: T,
    xyz: _Xyz,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render `Mark.SCATTER3D`: one marker per (x, y, z), drawn farthest
    first so nearer points land on top.

    The depth sort is exact for points: a marker is a disc at a single
    depth, so ordering by that depth is the whole of the occlusion.
    """
    _validate_xyz(xyz)
    var theme = settings.theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var frame = _frame_for(xyz, px0, py0, px1, py1)
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var order = _depth_order(xyz, frame)
    var radius = sc.point_radius
    var tooltips = settings.tooltips_on(len(order))
    for k in range(len(order)):
        var i = order[k]
        var at = frame.to_pixel(xyz.x[i], xyz.y[i], xyz.z[i])
        if tooltips:
            target.begin_annotated_group(
                _xyz_tooltip_label(xyz.x[i], xyz.y[i], xyz.z[i])
            )
        # A circle, not `Theme.shape_by_category`'s cycle: shapes there
        # encode a category, and this mark has no category channel yet.
        target.fill_circle_aa(at[0], at[1], radius, theme.mark_color)
        if tooltips:
            target.end_annotated_group()
    return _RenderResult(text^, px0, py0, px1, py1)


def _render_scatter3d_plot[
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
    """`_render_scatter3d` on `plot`'s own columns and settings: the callback
    its `mark_*()` setter binds. This is the one place the mark's
    renderer meets a `Plot` (#826)."""
    return _render_scatter3d(
        target, plot._xyz, plot._settings, ox0, oy0, ox1, oy1, cache=cache
    )


def _render_plot3d[
    T: DrawTarget
](
    mut target: T,
    xyz: _Xyz,
    settings: _ChartSettings,
    ox0: Int,
    oy0: Int,
    ox1: Int,
    oy1: Int,
    *,
    mut cache: FontCache,
) raises -> _RenderResult:
    """Render `Mark.PLOT3D`: the points joined in data order as one
    polyline through the cube.

    **Not depth sorted, and it cannot be.** A polyline is one connected
    path; reordering its segments by depth would reorder the line
    itself. So a segment passing behind another is drawn over it when it
    comes later in the series. The fix -- splitting segments where
    they cross in projection -- needs geometry canvas does not have.
    """
    _validate_xyz(xyz)
    var theme = settings.theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var frame = _frame_for(xyz, px0, py0, px1, py1)
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var n = len(xyz.x)
    if n >= 2:
        var path = Path()
        var first = frame.to_pixel(xyz.x[0], xyz.y[0], xyz.z[0])
        path.move_to(first[0], first[1])
        for i in range(1, n):
            var at = frame.to_pixel(xyz.x[i], xyz.y[i], xyz.z[i])
            path.line_to(at[0], at[1])
        target.stroke_path_aa(path, theme.mark_color, width=sc.line_width)
    return _RenderResult(text^, px0, py0, px1, py1)


def _render_plot3d_plot[
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
    """`_render_plot3d` on `plot`'s own columns and settings: the callback
    its `mark_*()` setter binds. This is the one place the mark's
    renderer meets a `Plot` (#826)."""
    return _render_plot3d(
        target, plot._xyz, plot._settings, ox0, oy0, ox1, oy1, cache=cache
    )


def scatter3d(
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
) raises -> Plot:
    """`scatter3d()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        y: The numeric column for this channel.
        z: The numeric column for this channel.
        elev: See the list overload.
        azim: See the list overload.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var x_values = _frame_floats(df, x, "scatter3d()", theme.missing)
    var y_values = _frame_floats(df, y, "scatter3d()", theme.missing)
    var z_values = _frame_floats(df, z, "scatter3d()", theme.missing)
    return scatter3d(
        x=x_values,
        y=y_values,
        z=z_values,
        elev=elev,
        azim=azim,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
    )


def scatter3d[
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
    """A 3D scatter: one marker per (x, y, z) in an orthographic view of
    a viewing cube.

    `Mark.SCATTER3D`. Points are drawn farthest first, so a nearer point
    covers a farther one -- which is the whole of the occlusion, since
    the renderer has no depth buffer.

    Read it knowing what a projection costs: a single view collapses
    three dimensions onto two, and two points that look adjacent may be
    far apart along the view direction. Where the question is about two
    variables, a 2D scatter answers it better.

    Args:
        x: The x column.
        y: The y column, the same length.
        z: The z column, the same length.
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
        from std.math import cos, sin

        from dataviz import save, scatter3d

        def main() raises:
            # Illustrative sampling of a helix climbing through the box.
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            for i in range(120):
                var t = Float64(i) * 0.12
                x.append(cos(t))
                y.append(sin(t))
                z.append(Float64(i) * 0.05)

            var c = scatter3d(
                x, y, z, title="Illustrative Helix Sampled in Three Axes"
            )
            save(c, "docs/src/examples/out_scatter3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_scatter3d(elev=elev, azim=azim)
        .encode_xyz(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(z),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def plot3d(
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
) raises -> Plot:
    """`plot3d()` over named columns of a `dataframe_mojo`
    `DataFrame` (#743). Each argument names a column instead of
    holding the values.

    See `Plot.encode_frame()` for how columns are read and what a
    column with missing values does.

    Args:
        df: The frame to read.
        x: The numeric column for this channel.
        y: The numeric column for this channel.
        z: The numeric column for this channel.
        elev: See the list overload.
        azim: See the list overload.
        theme: See the list overload.
        width: See the list overload.
        height: See the list overload.
        title: See the list overload.
        subtitle: See the list overload.

    Returns:
        The finished `Plot` -- unrendered.

    Raises:
        Error: A named column is missing, has the wrong dtype for
            its channel, or has missing values.
    """
    var x_values = _frame_floats(df, x, "plot3d()", theme.missing)
    var y_values = _frame_floats(df, y, "plot3d()", theme.missing)
    var z_values = _frame_floats(df, z, "plot3d()", theme.missing)
    return plot3d(
        x=x_values,
        y=y_values,
        z=z_values,
        elev=elev,
        azim=azim,
        theme=theme,
        width=width,
        height=height,
        title=title,
        subtitle=subtitle,
    )


def plot3d[
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
    """A 3D line: the points joined in data order as one polyline
    through the viewing cube.

    `Mark.PLOT3D`, `scatter3d()`'s companion for data with an order --
    a trajectory, a path, a parametric curve.

    **Not depth sorted**, and it cannot be: a polyline is one connected
    path, so reordering its segments by depth would reorder the line
    itself. A segment passing behind another is drawn over it when it
    comes later in the series; the fix
    is splitting segments where they cross in projection, which needs
    geometry the renderer does not have.

    Args:
        x: The x column.
        y: The y column, the same length.
        z: The z column, the same length.
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
        from std.math import cos, sin

        from dataviz import plot3d, save

        def main() raises:
            # Illustrative trajectory: a spiral tightening as it climbs.
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            for i in range(200):
                var t = Float64(i) * 0.1
                var r = 1.0 - Float64(i) * 0.004
                x.append(r * cos(t))
                y.append(r * sin(t))
                z.append(Float64(i) * 0.02)

            var c = plot3d(
                x, y, z, title="Illustrative Tightening Spiral Trajectory"
            )
            save(c, "docs/src/examples/out_plot3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_plot3d(elev=elev, azim=azim)
        .encode_xyz(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(z),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def _encode_xyz(
    mark: Mark,
    mut xyz: _Xyz,
    x: List[Float64],
    y: List[Float64],
    z: List[Float64],
) raises:
    """`Plot.encode_xyz()`'s body, which forwards here with
    every argument; see that method for the contract."""
    var _ok_encode_xyz = List[Mark]()
    _ok_encode_xyz.append(Mark.SCATTER3D)
    _ok_encode_xyz.append(Mark.PLOT3D)
    _ok_encode_xyz.append(Mark.TRISURF3D)
    _ok_encode_xyz.append(Mark.STEM3D)
    _require_mark(mark, "encode_xyz", "mark_scatter3d()", _ok_encode_xyz^)
    xyz.x = x.copy()
    xyz.y = y.copy()
    xyz.z = z.copy()
