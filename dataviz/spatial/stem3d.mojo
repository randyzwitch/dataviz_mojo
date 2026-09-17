"""`Mark.STEM3D`, `Mark.QUIVER3D` and `Mark.FILL_BETWEEN3D`: marks
built from lines through the cube (#345).

Step 5 of #345, the second half. A stem points at the base plane, an
arrow points wherever its components say, and a ribbon joins two
curves -- each is a line through the cube, with something on the end of
it or another line beside it.

**The lines are not depth sorted and cannot usefully be.** A line has
no interior to hide anything behind, so two stems or two shafts that
cross in projection cross visibly whichever went second, which is the
honest picture of two that cross. The markers on a stem's end *are*
sorted, because a marker is a disc at a single depth and ordering
those is exact -- the same split `scatter3d` makes. The ribbon is a
mesh and sorts like the surfaces do.

**An arrowhead is built in screen space, not in the cube.** A cone in
data space would need its own faces, its own depth sort against every
other arrow, and a size in data units that means nothing -- an arrow's
head is a reading aid whose size should not change when the data's
units do. So the shaft projects and the head is a triangle laid on the
projected shaft, sized in pixels like every other marker here. The cost
is that a head does not foreshorten: an arrow pointing at the reader
keeps a full-size head on a shaft with no length, which is exactly when
a reader should distrust the picture anyway.
"""

from std.math import sqrt

from canvas.color import Color
from canvas.path import Path
from canvas.text.font_cache import FontCache
from canvas.vector.draw_target import DrawTarget

from dataviz.core.array_like import _materialize_scalar_list
from dataviz.core.camera3d import Camera3D
from dataviz.core.frame3d import _Extent3D, _fit_frame3d
from dataviz.core.scale import MinMax
from dataviz.core.theme import Theme
from dataviz.plot import (
    Plot,
    _RenderResult,
    _Scaled,
    _TextRequest,
    _finished,
    _min_max,
    _require_non_empty,
)
from dataviz.spatial.bar3d import _Mesh, _Vertex
from dataviz.spatial.scatter3d import (
    _depth_order,
    _draw_box,
    _tick_labels,
    _validate_xyz,
)
from dataviz.spatial.scatter3d import _Xyz


struct _Vectors3D(Copyable, Defaultable, Movable):
    """Points with a direction each, for `Mark.QUIVER3D`.

    `u`/`v`/`w` are the components of the arrow at each `(x, y, z)`, in
    the data's own units on each axis -- so an arrow's length is read
    against the axes rather than against a separate legend.
    """

    var x: List[Float64]
    var y: List[Float64]
    var z: List[Float64]
    var u: List[Float64]
    var v: List[Float64]
    var w: List[Float64]
    var elev: Float64
    var azim: Float64

    def __init__(out self):
        self.x = List[Float64]()
        self.y = List[Float64]()
        self.z = List[Float64]()
        self.u = List[Float64]()
        self.v = List[Float64]()
        self.w = List[Float64]()
        self.elev = 30.0
        self.azim = -60.0


def _validate_vectors3d(plot: Plot) raises:
    """Six equal-length columns, at least one arrow.

    Raises:
        Error: The columns disagree in length, or there are no arrows.
    """
    var n = len(plot._data[_Vectors3D].x)
    for pair in [
        (len(plot._data[_Vectors3D].y), String("y")),
        (len(plot._data[_Vectors3D].z), String("z")),
        (len(plot._data[_Vectors3D].u), String("u")),
        (len(plot._data[_Vectors3D].v), String("v")),
        (len(plot._data[_Vectors3D].w), String("w")),
    ]:
        if pair[0] != n:
            raise Error(
                "Plot.encode_vectors3d(): x, y, z, u, v and w must all have"
                " the same length -- x has "
                + String(n)
                + " and "
                + pair[1]
                + " has "
                + String(pair[0])
            )
    _require_non_empty(n, "Plot.encode_vectors3d()")


def _vectors3d_extent(plot: Plot) raises -> _Extent3D:
    """The three ranges, reaching every arrow's tip as well as its tail.

    An arrow that left the box would be read as pointing at something
    outside the data, which is not what it says.
    """
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    for i in range(len(plot._data[_Vectors3D].x)):
        xs.append(plot._data[_Vectors3D].x[i])
        xs.append(plot._data[_Vectors3D].x[i] + plot._data[_Vectors3D].u[i])
        ys.append(plot._data[_Vectors3D].y[i])
        ys.append(plot._data[_Vectors3D].y[i] + plot._data[_Vectors3D].v[i])
        zs.append(plot._data[_Vectors3D].z[i])
        zs.append(plot._data[_Vectors3D].z[i] + plot._data[_Vectors3D].w[i])
    return _Extent3D(_min_max(xs), _min_max(ys), _min_max(zs))


def _draw_arrowhead[
    T: DrawTarget
](
    mut target: T,
    tail_x: Float64,
    tail_y: Float64,
    tip_x: Float64,
    tip_y: Float64,
    size: Float64,
    color: Color,
) raises:
    """Lay a filled triangle on the projected shaft, pointing at its
    tip.

    Built from the projected direction rather than the data direction,
    so the head follows the shaft as drawn. A shaft with no projected
    length gets no head at all: there is no direction to point it, and
    guessing one would draw an arrow the data does not support.

    The early return is there to avoid dividing by that zero length,
    not to be the only thing holding the no-head rule up -- carry on
    with a unit length and the head's three corners collapse onto the
    tip, which fills nothing either. What the rule rules out is
    *substituting* a direction, and that is what the test perturbs.

    Args:
        target: The draw target.
        tail_x: Shaft start, in pixels.
        tail_y: Shaft start, in pixels.
        tip_x: Shaft end, in pixels.
        tip_y: Shaft end, in pixels.
        size: The head's length in pixels.
        color: The fill.
    """
    var dx = tip_x - tail_x
    var dy = tip_y - tail_y
    var length = sqrt(dx * dx + dy * dy)
    if length <= 0.0:
        return
    var ux = dx / length
    var uy = dy / length
    # Base of the head, back along the shaft, and its two corners out
    # to either side.
    var bx = tip_x - ux * size
    var by = tip_y - uy * size
    var half = size * 0.4
    var head = Path()
    head.move_to(tip_x, tip_y)
    head.line_to(bx - uy * half, by + ux * half)
    head.line_to(bx + uy * half, by - ux * half)
    head.close()
    target.fill_path_aa(head, color)


def _stem3d_extent(plot: Plot) raises -> _Extent3D:
    """The three ranges, with z always reaching the base plane.

    A stem is read as a length from that plane, so a range starting at
    the lowest point would draw every stem from a floor that is not
    zero -- the same reason a bar's base is fixed.
    """
    var zs = _min_max(plot._data[_Xyz].z)
    return _Extent3D(
        _min_max(plot._data[_Xyz].x),
        _min_max(plot._data[_Xyz].y),
        MinMax(
            zs.min if zs.min < 0.0 else 0.0, zs.max if zs.max > 0.0 else 0.0
        ),
    )


def _render_stem3d[
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
    """Render `Mark.STEM3D`: a line from the base plane to each point,
    with a marker on the end.

    The stems are drawn first and all of them, then the markers in
    depth order. Splitting it that way orders exactly the part that can
    be ordered -- a marker is a disc at one depth -- without pretending
    the stems can be, which they cannot: a line has no interior to hide
    anything behind.

    With every marker the same color the sort changes little: two
    overlapping discs of one color differ only in the blended pixels
    along the overlap, since each disc is filled on its own and its
    partial coverage composites against whatever is already there.
    Reversing the order moves a measurable but small number of pixels.
    The sort is here because the order is *right*, and because it
    becomes the whole of the occlusion the moment markers differ in
    color or size.
    """
    _validate_xyz(plot)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var frame = _fit_frame3d(
        Camera3D(plot._data[_Xyz].elev, plot._data[_Xyz].azim),
        _stem3d_extent(plot),
        px0,
        py0,
        px1,
        py1,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var n = len(plot._data[_Xyz].x)
    for i in range(n):
        var foot = frame.to_pixel(
            plot._data[_Xyz].x[i], plot._data[_Xyz].y[i], 0.0
        )
        var head = frame.to_pixel(
            plot._data[_Xyz].x[i], plot._data[_Xyz].y[i], plot._data[_Xyz].z[i]
        )
        var stem = Path()
        stem.move_to(foot[0], foot[1])
        stem.line_to(head[0], head[1])
        target.stroke_path_aa(stem, theme.mark_color, width=sc.line_width)

    var order = _depth_order(plot, frame)
    for k in range(len(order)):
        var i = order[k]
        var at = frame.to_pixel(
            plot._data[_Xyz].x[i], plot._data[_Xyz].y[i], plot._data[_Xyz].z[i]
        )
        target.fill_circle_aa(at[0], at[1], sc.point_radius, theme.mark_color)
    return _RenderResult(text^, px0, py0, px1, py1)


def _render_quiver3d[
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
    """Render `Mark.QUIVER3D`: a shaft from each point along its
    components, with a screen-space head on the end.

    Arrows are drawn in data order. Nothing here is opaque enough for
    an order to matter: two shafts that cross in projection cross
    visibly either way, and that is what two crossing arrows look like.
    """
    _validate_vectors3d(plot)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var frame = _fit_frame3d(
        Camera3D(plot._data[_Vectors3D].elev, plot._data[_Vectors3D].azim),
        _vectors3d_extent(plot),
        px0,
        py0,
        px1,
        py1,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var head_size = sc.point_radius * 2.4
    for i in range(len(plot._data[_Vectors3D].x)):
        var tail = frame.to_pixel(
            plot._data[_Vectors3D].x[i],
            plot._data[_Vectors3D].y[i],
            plot._data[_Vectors3D].z[i],
        )
        var tip = frame.to_pixel(
            plot._data[_Vectors3D].x[i] + plot._data[_Vectors3D].u[i],
            plot._data[_Vectors3D].y[i] + plot._data[_Vectors3D].v[i],
            plot._data[_Vectors3D].z[i] + plot._data[_Vectors3D].w[i],
        )
        var shaft = Path()
        shaft.move_to(tail[0], tail[1])
        shaft.line_to(tip[0], tip[1])
        target.stroke_path_aa(shaft, theme.mark_color, width=sc.line_width)
        _draw_arrowhead(
            target,
            tail[0],
            tail[1],
            tip[0],
            tip[1],
            head_size,
            theme.mark_color,
        )
    return _RenderResult(text^, px0, py0, px1, py1)


struct _Ribbon3D(Copyable, Defaultable, Movable):
    """Two curves through the cube and the surface between them, for
    `Mark.FILL_BETWEEN3D`.

    The two are sampled together: index `i` of one is joined to index
    `i` of the other, so they have to be the same length and the
    pairing is the caller's, not something inferred from position.
    """

    var x1: List[Float64]
    var y1: List[Float64]
    var z1: List[Float64]
    var x2: List[Float64]
    var y2: List[Float64]
    var z2: List[Float64]
    var elev: Float64
    var azim: Float64

    def __init__(out self):
        self.x1 = List[Float64]()
        self.y1 = List[Float64]()
        self.z1 = List[Float64]()
        self.x2 = List[Float64]()
        self.y2 = List[Float64]()
        self.z2 = List[Float64]()
        self.elev = 30.0
        self.azim = -60.0


def _validate_ribbon3d(plot: Plot) raises:
    """Six columns of one length, and at least two samples.

    Raises:
        Error: The columns disagree, or there are fewer than two
            samples to make a quad from.
    """
    var n = len(plot._data[_Ribbon3D].x1)
    for pair in [
        (len(plot._data[_Ribbon3D].y1), String("y1")),
        (len(plot._data[_Ribbon3D].z1), String("z1")),
        (len(plot._data[_Ribbon3D].x2), String("x2")),
        (len(plot._data[_Ribbon3D].y2), String("y2")),
        (len(plot._data[_Ribbon3D].z2), String("z2")),
    ]:
        if pair[0] != n:
            raise Error(
                "Plot.encode_ribbon3d(): the six columns must all have the"
                " same length -- x1 has "
                + String(n)
                + " and "
                + pair[1]
                + " has "
                + String(pair[0])
            )
    if n < 2:
        raise Error(
            "Plot.encode_ribbon3d(): a ribbon needs at least 2 samples to"
            " have any surface between them (got "
            + String(n)
            + ")"
        )


def _render_fill_between3d[
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
    """Render `Mark.FILL_BETWEEN3D`: the surface joining two curves,
    one quad per pair of consecutive samples.

    A ribbon is the one surface here that routinely twists: nothing
    stops the two curves from crossing, and where they do, the quad
    joining them folds over itself. Centroid sorting has no right
    answer for a folded quad -- half of it is in front of the other
    half -- so the fold is drawn as one flat piece. It is visible as a
    pinch in the ribbon, which is the honest picture of two curves that
    cross.

    **The sort `_Mesh.draw` runs here currently changes nothing, and
    that is checkable rather than assumed**: every quad takes one
    color, and `fill_mesh` hands each sub-sample to exactly one face,
    so the composite is the same in any order. Inverting it leaves the
    raster bit-identical. It is kept because the order is right and
    because a color channel on this mark would make it load-bearing
    overnight -- but nothing here would notice if it broke, so do not
    read the digest entry as covering it.
    """
    _validate_ribbon3d(plot)
    var theme = plot._theme
    var sc = _Scaled(theme)
    var px0 = ox0 + sc.margin_left
    var py0 = oy0 + sc.margin_top
    var px1 = ox1 - sc.margin_right
    var py1 = oy1 - sc.margin_bottom
    var xs = List[Float64]()
    var ys = List[Float64]()
    var zs = List[Float64]()
    for i in range(len(plot._data[_Ribbon3D].x1)):
        xs.append(plot._data[_Ribbon3D].x1[i])
        xs.append(plot._data[_Ribbon3D].x2[i])
        ys.append(plot._data[_Ribbon3D].y1[i])
        ys.append(plot._data[_Ribbon3D].y2[i])
        zs.append(plot._data[_Ribbon3D].z1[i])
        zs.append(plot._data[_Ribbon3D].z2[i])
    var frame = _fit_frame3d(
        Camera3D(plot._data[_Ribbon3D].elev, plot._data[_Ribbon3D].azim),
        _Extent3D(_min_max(xs), _min_max(ys), _min_max(zs)),
        px0,
        py0,
        px1,
        py1,
    )
    _draw_box(target, frame, theme, sc)
    var text = List[_TextRequest]()
    _tick_labels(frame, theme, sc, text)

    var mesh = _Mesh()
    var color = theme.mark_color
    for i in range(len(plot._data[_Ribbon3D].x1) - 1):
        mesh.add_quad(
            frame,
            _Vertex(
                plot._data[_Ribbon3D].x1[i],
                plot._data[_Ribbon3D].y1[i],
                plot._data[_Ribbon3D].z1[i],
            ),
            _Vertex(
                plot._data[_Ribbon3D].x2[i],
                plot._data[_Ribbon3D].y2[i],
                plot._data[_Ribbon3D].z2[i],
            ),
            _Vertex(
                plot._data[_Ribbon3D].x2[i + 1],
                plot._data[_Ribbon3D].y2[i + 1],
                plot._data[_Ribbon3D].z2[i + 1],
            ),
            _Vertex(
                plot._data[_Ribbon3D].x1[i + 1],
                plot._data[_Ribbon3D].y1[i + 1],
                plot._data[_Ribbon3D].z1[i + 1],
            ),
            color,
        )
    mesh.draw(target)
    return _RenderResult(text^, px0, py0, px1, py1)


def stem3d[
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
    """Points tethered to the base plane: a line from the plane to each
    (x, y, z), with a marker on the end.

    `Mark.STEM3D`. The tether is what a plain 3D scatter is missing --
    a floating marker's height cannot be read, because nothing says
    where under it the plane is. The stem says.

    The base is always zero, so a stem's length is its value.

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
        from std.math import cos, sin

        from dataviz import save, stem3d

        def main() raises:
            # Illustrative readings taken around a circular track.
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            for i in range(28):
                var t = Float64(i) * 0.224
                x.append(cos(t))
                y.append(sin(t))
                z.append(1.0 + cos(t * 3.0) * 0.6)

            var c = stem3d(
                x, y, z, title="Illustrative Readings Around a Track"
            )
            save(c, "docs/src/examples/out_stem3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_stem3d(elev=elev, azim=azim)
        .encode_xyz(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(z),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def quiver3d[
    dtype: DType
](
    x: List[Scalar[dtype]],
    y: List[Scalar[dtype]],
    z: List[Scalar[dtype]],
    u: List[Scalar[dtype]],
    v: List[Scalar[dtype]],
    w: List[Scalar[dtype]],
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Plot:
    """Arrows in space: a direction and a magnitude sampled at points.

    `Mark.QUIVER3D`. Each arrow runs from its (x, y, z) along
    (u, v, w), in the data's own units, so its length is read against
    the axes.

    The box is fitted to the arrows' tips as well as their tails -- an
    arrow leaving the box would read as pointing at something outside
    the data.

    An arrow pointing near the viewer projects to almost nothing, and
    no view avoids that for every arrow at once. Where the field's
    structure matters more than any one arrow, a `streamplot` of a
    slice through it shows more.

    Args:
        x: The x coordinate of each arrow's tail.
        y: The y coordinate of each tail, the same length.
        z: The z coordinate of each tail, the same length.
        u: The x component of each arrow, the same length.
        v: The y component, the same length.
        w: The z component, the same length.
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
        Error: The six columns disagree in length, or are empty.

    Example:
        ```mojo
        from dataviz import quiver3d, save

        def main() raises:
            # Illustrative circulation: a field turning about the z axis
            # and drifting upward as it goes.
            var x = List[Float64]()
            var y = List[Float64]()
            var z = List[Float64]()
            var u = List[Float64]()
            var v = List[Float64]()
            var w = List[Float64]()
            for k in range(3):
                for j in range(3):
                    for i in range(3):
                        var px = Float64(i) - 1.0
                        var py = Float64(j) - 1.0
                        var pz = Float64(k) - 1.0
                        x.append(px)
                        y.append(py)
                        z.append(pz)
                        u.append(-py * 0.35)
                        v.append(px * 0.35)
                        w.append(0.25)

            var c = quiver3d(
                x, y, z, u, v, w, title="Illustrative Circulating Field"
            )
            save(c, "docs/src/examples/out_quiver3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_quiver3d(elev=elev, azim=azim)
        .encode_vectors3d(
            _materialize_scalar_list(x),
            _materialize_scalar_list(y),
            _materialize_scalar_list(z),
            _materialize_scalar_list(u),
            _materialize_scalar_list(v),
            _materialize_scalar_list(w),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )


def fill_between3d[
    dtype: DType
](
    x1: List[Scalar[dtype]],
    y1: List[Scalar[dtype]],
    z1: List[Scalar[dtype]],
    x2: List[Scalar[dtype]],
    y2: List[Scalar[dtype]],
    z2: List[Scalar[dtype]],
    elev: Float64 = 30.0,
    azim: Float64 = -60.0,
    theme: Theme = Theme(),
    width: Int = 640,
    height: Int = 480,
    title: String = "",
    subtitle: String = "",
) raises -> Plot:
    """The surface between two curves through space: a ribbon joining
    them sample by sample.

    `Mark.FILL_BETWEEN3D`. Sample `i` of the first curve is joined to
    sample `i` of the second, so the pairing is the caller's rather
    than something inferred from position, and the two columns must be
    the same length.

    Use it for the space a path sweeps, or the gap between a measured
    curve and a reference one where both live in three dimensions.
    Where the two curves cross, the quad joining them folds over
    itself and shows as a pinch in the ribbon -- there is no order that
    draws a folded quad correctly, and the pinch is the honest picture
    of curves that cross.

    Args:
        x1: The first curve's x column.
        y1: The first curve's y column, the same length.
        z1: The first curve's z column, the same length.
        x2: The second curve's x column, the same length.
        y2: The second curve's y column, the same length.
        z2: The second curve's z column, the same length.
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
        Error: The six columns disagree in length, or there are fewer
            than two samples.

    Example:
        ```mojo
        from std.math import cos, sin

        from dataviz import fill_between3d, save

        def main() raises:
            # Illustrative envelope: a helix and a wider one outside it,
            # with the sheet between them.
            var x1 = List[Float64]()
            var y1 = List[Float64]()
            var z1 = List[Float64]()
            var x2 = List[Float64]()
            var y2 = List[Float64]()
            var z2 = List[Float64]()
            for i in range(90):
                var t = Float64(i) * 0.14
                x1.append(cos(t))
                y1.append(sin(t))
                z1.append(Float64(i) * 0.04)
                x2.append(cos(t) * 1.7)
                y2.append(sin(t) * 1.7)
                z2.append(Float64(i) * 0.04)

            var c = fill_between3d(
                x1,
                y1,
                z1,
                x2,
                y2,
                z2,
                title="Illustrative Sheet Between Two Helices",
            )
            save(c, "docs/src/examples/out_fill_between3d.svg")
        ```
    """
    var plot = (
        Plot()
        .mark_fill_between3d(elev=elev, azim=azim)
        .encode_ribbon3d(
            _materialize_scalar_list(x1),
            _materialize_scalar_list(y1),
            _materialize_scalar_list(z1),
            _materialize_scalar_list(x2),
            _materialize_scalar_list(y2),
            _materialize_scalar_list(z2),
        )
    )
    return _finished(
        plot^, theme, width, height, title, "", "", subtitle=subtitle
    )
